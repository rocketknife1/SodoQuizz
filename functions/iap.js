// Validarea achizitiilor cu bani reali.
//
// PROBLEMA pe care o rezolva: pana acum magazinul acorda produsele LOCAL, dupa
// 900ms de asteptare falsa (vezi shop_screen.dart). Din secunda in care se vand
// pe bani reali, asta ar insemna ca oricine isi poate acorda singur orice.
//
// REGULA: clientul nu spune NICIODATA ce sa i se acorde. Trimite doar
// `purchaseToken`-ul primit de la Google; serverul intreaba Google daca e real,
// se uita in catalogul PROPRIU (iap_products.json) ce inseamna produsul ala, si
// abia apoi acorda. Un client modificat poate cere orice — fara un bon valid nu
// primeste nimic.
//
// Fisier separat de index.js dinadins: acolo sunt 443 de linii de notificari
// push, iar asta e alt subiect, cu alte capcane.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const crypto = require("crypto");

const RAW_CATALOG = require("./iap_products.json");
const PACKAGE = "com.dragosssx.guessit";

/** Catalogul curatat de cheile de comentariu (`_comentariu`). */
const CATALOG = Object.fromEntries(
  Object.entries(RAW_CATALOG).filter(([k]) => !k.startsWith("_"))
);

// `getFirestore()` la nivel de modul ar crapa daca fisierul asta e cerut
// INAINTE de `initializeApp()` din index.js. Lenes, deci ordinea nu conteaza.
let _db;
const db = () => (_db || (_db = getFirestore()));

const sha256 = (s) => crypto.createHash("sha256").update(s).digest("hex");

/** Eroare cu forma pe care o asteapta clientul: `details.retryable` decide daca
 * are voie sa consume tokenul de la Play sau trebuie sa reincerce. Daca gresim
 * aici, ori pierdem o plata, ori dam produsul de doua ori. */
function fail(code, reason, retryable, message) {
  return new HttpsError(code, message || reason, { reason, retryable });
}

// --- Vorbitul cu Google Play ----------------------------------------------
//
// NU folosim pachetul `googleapis`: ~40MB si sute de ms in plus la cold start,
// pentru UN singur apel REST. `google-auth-library` (deja instalat, tranzitiv
// prin firebase-admin, dar declarat explicit in package.json) plus `fetch`-ul
// nativ din Node 22 fac exact acelasi lucru.

let _authClient;
async function playToken() {
  if (!_authClient) {
    const { GoogleAuth } = require("google-auth-library");
    _authClient = await new GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    }).getClient();
  }
  const { token } = await _authClient.getAccessToken();
  return token;
}

const playUrl = (productId, purchaseToken, suffix) =>
  "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
  PACKAGE +
  "/purchases/products/" + encodeURIComponent(productId) +
  "/tokens/" + encodeURIComponent(purchaseToken) + (suffix || "");

/** Verificatorul FALS, folosit doar sub emulator. Citeste din
 * `purchase_fixtures/{sha256(token)}` un document cu exact forma raspunsului
 * Google (purchaseState, acknowledgementState, consumptionState, ...).
 *
 * ASTA e piesa cea mai valoroasa din tot fisierul: fara ea, toata masina de
 * stari (bon in asteptare / anulat / replay / alt cont / dublu apel simultan)
 * s-ar putea verifica doar in productie, cu bani reali. */
async function fakeVerify(purchaseToken) {
  const snap = await db().collection("purchase_fixtures").doc(sha256(purchaseToken)).get();
  if (!snap.exists) return { httpStatus: 404 };
  return { httpStatus: 200, body: snap.data() };
}

async function playGet(productId, purchaseToken) {
  if (process.env.FUNCTIONS_EMULATOR === "true") return fakeVerify(purchaseToken);
  try {
    const res = await fetch(playUrl(productId, purchaseToken), {
      headers: { Authorization: "Bearer " + (await playToken()) },
    });
    if (!res.ok) return { httpStatus: res.status };
    return { httpStatus: 200, body: await res.json() };
  } catch (e) {
    logger.warn("playGet a esuat (retea): " + e);
    return { httpStatus: 503 };
  }
}

/** Confirmarea catre Google. DACA NU SE FACE in 3 zile, Google ramburseaza
 * automat si revoca — dar produsul a fost deja dat. De-aia confirma SERVERUL,
 * nu clientul: altfel atacul e trivial (cumperi, force-stop, astepti 3 zile,
 * primesti banii inapoi si pastrezi marfa). */
async function playAcknowledge(productId, purchaseToken) {
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    await db().collection("purchase_fixtures").doc(sha256(purchaseToken))
      .set({ acknowledgementState: 1 }, { merge: true });
    return true;
  }
  try {
    const res = await fetch(playUrl(productId, purchaseToken, ":acknowledge"), {
      method: "POST",
      headers: {
        Authorization: "Bearer " + (await playToken()),
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    // Un esec aici NU e esec al validarii: grantul e deja durabil in Firestore,
    // iar confirmarea se reincearca la urmatorul apel. Google ne da 3 zile.
    if (!res.ok) logger.warn("acknowledge " + productId + ": HTTP " + res.status);
    return res.ok;
  } catch (e) {
    logger.warn("acknowledge a esuat (retea): " + e);
    return false;
  }
}

// --- Plafon de incercari ---------------------------------------------------

const MAX_ATTEMPTS_PER_HOUR = 60;

async function tooManyAttempts(uid) {
  const ref = db().collection("purchase_attempts").doc(uid);
  try {
    return await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const now = Date.now();
      const d = snap.data() || {};
      const windowStart = typeof d.windowStart === "number" ? d.windowStart : 0;
      const fresh = now - windowStart < 3600000;
      const count = fresh ? (d.count || 0) + 1 : 1;
      tx.set(ref, { windowStart: fresh ? windowStart : now, count }, { merge: true });
      return count > MAX_ATTEMPTS_PER_HOUR;
    });
  } catch (e) {
    // Un plafon care nu se poate citi nu are voie sa blocheze o plata reala.
    logger.warn("tooManyAttempts a esuat, las sa treaca: " + e);
    return false;
  }
}

/** Notita pentru panoul de Admin — acelasi format ca la onBalanceAudit, ca
 * ecranul care exista deja sa le arate fara nicio modificare. */
async function flag(uid, reason) {
  try {
    await db().collection("security_flags").doc(uid).set({
      lastFlaggedAt: FieldValue.serverTimestamp(),
      lastReason: String(reason).slice(0, 500),
      flagCount: FieldValue.increment(1),
    }, { merge: true });
  } catch (e) {
    logger.warn("nu am putut scrie security_flags/" + uid + ": " + e);
  }
}

// --- Functia propriu-zisa --------------------------------------------------

exports.validatePurchase = onCall(
  { enforceAppCheck: true, memory: "256MiB", maxInstances: 10 },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    // Conturile ANONIME sunt cetateni de rangul intai in jocul asta (un Guest
    // are uid din prima pornire si poate cumpara) — nu se cere cont Google.
    if (!uid) throw fail("unauthenticated", "no_auth", true, "nu esti autentificat");

    const data = request.data || {};
    const productId = String(data.productId || "");
    const purchaseToken = String(data.purchaseToken || "");
    if (!productId || !purchaseToken) {
      throw fail("invalid-argument", "bad_request", false, "lipsesc productId/purchaseToken");
    }

    const product = CATALOG[productId];
    if (!product) {
      await flag(uid, "produs necunoscut: " + productId);
      throw fail("invalid-argument", "unknown_product", false, "produs necunoscut");
    }

    if (await tooManyAttempts(uid)) {
      throw fail("resource-exhausted", "rate_limited", true, "prea multe incercari");
    }

    const tokenHash = sha256(purchaseToken);
    const tokenRef = db().collection("purchase_tokens").doc(tokenHash);
    const entRef = db().collection("entitlements").doc(uid);
    const grantRef = db().doc("purchase_grants/" + uid + "/pending/" + tokenHash);

    // Intrebam Google. `productId` face parte din URL, deci o nepotrivire intre
    // ce sustine clientul si ce are Play da 404 — nu e nevoie sa comparam campuri.
    const res = await playGet(productId, purchaseToken);
    if (res.httpStatus === 404) {
      await flag(uid, "token inexistent pentru " + productId);
      throw fail("invalid-argument", "unknown_token", false, "bon inexistent");
    }
    // 401/403 = Play Console inca nepropagat sau prost legat. NU e vina
    // jucatorului: retryable, ca sa reincerce la urmatoarea pornire.
    if (res.httpStatus === 401 || res.httpStatus === 403) {
      logger.error("androidpublisher a refuzat (HTTP " + res.httpStatus +
        ") - verifica legarea contului de serviciu in Play Console");
      throw fail("unavailable", "play_api_unavailable", true, "verificarea nu e disponibila");
    }
    if (res.httpStatus !== 200) {
      throw fail("unavailable", "play_api_unavailable", true, "verificarea nu e disponibila");
    }

    const p = res.body || {};
    // 0 = cumparat, 1 = anulat/rambursat, 2 = in asteptare.
    if (p.purchaseState === 1) {
      throw fail("aborted", "purchase_canceled", false, "achizitie anulata sau rambursata");
    }
    if (p.purchaseState === 2) {
      throw fail("failed-precondition", "purchase_pending", true, "plata e in asteptare");
    }
    if (p.purchaseState !== 0) {
      throw fail("unavailable", "play_api_unavailable", true, "stare necunoscuta");
    }

    const quantity = Math.max(1, Number(p.quantity) || 1);
    const grant = product.grant || {};
    const payload = {};
    for (const k of Object.keys(grant)) payload[k] = grant[k] * quantity;

    // --- Tranzactia: revendicarea tokenului SI acordarea, impreuna ---------
    //
    // `tx.create` (nu `set`) e ce face doua apeluri simultane sigure: al doilea
    // pica, tranzactia se reia, si reluarea intra pe ramura "exista deja".
    let status = "granted";
    try {
      await db().runTransaction(async (tx) => {
        const snap = await tx.get(tokenRef);

        if (snap.exists) {
          const owner = snap.data().uid;
          if (owner === uid) { status = "already_granted"; return; }

          // Alt cont a onorat deja bonul. Pentru NECONSUMABILE asta e cazul
          // normal al unui Guest care si-a reinstalat jocul: uid-ul anonim s-a
          // schimbat, dar Play tot detine produsul pentru acelasi cont Google.
          // Doar dispozitivul care chiar are contul poate produce un token viu,
          // deci transferul e sigur. Pentru CONSUMABILE nu se transfera nimic:
          // resursele au fost deja date o data, altui uid.
          const transfers = snap.data().transfers || [];
          if (product.consumable || p.consumptionState === 1 || transfers.length >= 3) {
            throw fail("permission-denied", "token_owned_by_other_account", false,
              "achizitia apartine altui cont");
          }
          tx.update(tokenRef, {
            uid,
            transfers: transfers.concat([{ fromUid: owner, at: Timestamp.now() }]),
          });
          if (product.entitlement) {
            tx.set(entRef, {
              [product.entitlement]: true,
              updatedAt: FieldValue.serverTimestamp(),
            }, { merge: true });
          }
          status = "transferred";
          return;
        }

        tx.create(tokenRef, {
          token: purchaseToken,
          uid,
          productId,
          orderId: p.orderId || null,
          quantity,
          purchaseTimeMillis: p.purchaseTimeMillis || null,
          purchaseType: typeof p.purchaseType === "number" ? p.purchaseType : null,
          status: "granted",
          createdAt: FieldValue.serverTimestamp(),
        });

        if (product.entitlement) {
          tx.set(entRef, {
            [product.entitlement]: true,
            [product.entitlement + "Since"]: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        // Un interval de 24h cumparat cu bani trebuie sa supravietuiasca unei
        // reinstalari, deci sta tot in drepturi, nu doar local.
        if (payload.unlimitedLivesHours) {
          tx.set(entRef, {
            unlimitedLivesUntil: Timestamp.fromMillis(
              Date.now() + payload.unlimitedLivesHours * 3600000),
            updatedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        if (Object.keys(payload).length) {
          tx.set(grantRef, Object.assign({ productId }, payload, {
            createdAt: FieldValue.serverTimestamp(),
          }));
        }
      });
    } catch (e) {
      if (e instanceof HttpsError) {
        if (e.details && e.details.reason === "token_owned_by_other_account") {
          await flag(uid, "bon revendicat de alt cont: " + productId);
        }
        throw e;
      }
      logger.error("tranzactia de acordare a esuat: " + e);
      throw fail("internal", "unexpected", true, "nu am putut inregistra achizitia");
    }

    // Confirmarea vine ABIA ACUM, dupa ce grantul e durabil in Firestore.
    // Ordinea inversa ar insemna: confirmam, aplicatia moare, jucatorul nu ia
    // nimic, iar Google considera tranzactia inchisa pe veci.
    let acknowledged = p.acknowledgementState === 1;
    if (!acknowledged) {
      acknowledged = await playAcknowledge(productId, purchaseToken);
      if (acknowledged) {
        try {
          await tokenRef.set({
            status: "acknowledged",
            acknowledgedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
        } catch (e) {
          logger.warn("nu am putut marca tokenul ca acknowledged: " + e);
        }
      }
    }

    let ent = {};
    try {
      const entSnap = await entRef.get();
      ent = entSnap.data() || {};
    } catch (e) {
      logger.warn("nu am putut citi drepturile: " + e);
    }

    return {
      ok: true,
      status,
      productId,
      grantId: Object.keys(payload).length && status !== "transferred" ? tokenHash : null,
      consume: product.consumable === true,
      acknowledged,
      entitlements: {
        noAdsForever: ent.noAdsForever === true,
        starterPackBought: ent.starterPackBought === true,
        unlimitedLivesUntil: ent.unlimitedLivesUntil
          ? ent.unlimitedLivesUntil.toMillis()
          : null,
      },
    };
  }
);
