/**
 * Notificari PUSH pentru SodoQuizz.
 *
 * DE CE EXISTA FISIERUL ASTA, dupa ce tot proiectul a mers pana acum fara
 * server: notificarile locale (roata, planeta, questuri, Clippy — vezi
 * lib/data/device_notification_service.dart) se pot programa pe telefon,
 * fiindca momentul lor se stie dinainte. Astea de aici NU se pot: depind de
 * ce face ALT jucator, cand aplicatia ta e inchisa. Iar un client nu poate
 * trimite FCM altui client — trimiterea cere cheia de server / Admin SDK.
 *
 * Proiectul a fost pe planul gratuit (Spark) pana acum, unde Functions nu se
 * pot deploya deloc. De cand contul e pe Blaze, se poate.
 *
 * ## Unde stau token-urile
 *
 * `users/{uid}/fcm_tokens/{token}`. NU in `player_profiles`, care e citibil
 * public (leaderboard): un token FCM in mana altcuiva inseamna notificari
 * false trimise in numele jocului. `users/{uid}` e strict al proprietarului.
 *
 * Functions citesc prin Admin SDK, deci regulile nu li se aplica — restrictia
 * din firestore.rules e doar impotriva clientilor.
 *
 * ## Token-urile mor, si asta e normal
 *
 * Un token devine invalid la dezinstalare, la stergerea datelor sau dupa
 * multa vreme. FCM raspunde cu `messaging/registration-token-not-registered`,
 * iar [sendToUser] sterge exact token-urile alea — altfel s-ar aduna la
 * nesfarsit si fiecare notificare ar incerca sa scrie la adrese moarte.
 */

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");

initializeApp();
const db = getFirestore();

// Europa, ca sa fie langa jucatori (proiectul e romanesc). maxInstances mic:
// jocul e in testare inchisa, iar plafonul asta e singura plasa de siguranta
// impotriva unei bucle care ar da facturi pe Blaze.
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

/** Canalul trebuie sa fie EXACT cel creat de aplicatie, altfel Android
 * foloseste unul implicit si se pierde sunetul propriu. Vezi
 * DeviceNotificationService._channelId. */
const CHANNEL_ID = "sodo_events_v1";

/** Contul de admin. Acelasi literal ca in firestore.rules si in
 * lib/core/admin.dart — daca se schimba, se schimba in toate trei. */
const ADMIN_EMAIL = "dragosssx@gmail.com";

/** uid-ul adminului, cautat dupa email si tinut in memoria instantei.
 *
 * De ce nu e o constanta: uid-ul nu se vede nicaieri in cod, iar scrierea lui
 * de mana ar fi insemnat un al doilea loc de tinut in sincron cu contul real.
 * Cautarea costa o cerere la Auth, dar doar la prima notificare a fiecarei
 * instante — pe urma raspunde din cache.
 *
 * `null` daca nu se poate rezolva (cont sters, Auth picat): atunci mesajul
 * jucatorului ramane doar in Firestore, unde adminul il vede oricum in
 * tab-ul Mesaje. Un push pierdut nu are voie sa rupa scrierea mesajului. */
let _adminUid;
async function adminUid() {
  if (_adminUid !== undefined) return _adminUid;
  try {
    _adminUid = (await getAuth().getUserByEmail(ADMIN_EMAIL)).uid;
  } catch (e) {
    logger.warn(`nu am putut rezolva uid-ul adminului: ${e}`);
    _adminUid = null;
  }
  return _adminUid;
}

/**
 * Trimite o notificare catre toate dispozitivele unui jucator.
 *
 * `data` ajunge in aplicatie si la tap — de acolo se decide unde se navigheaza
 * (ex. `type: "room_invite"` + `matchId`).
 */
async function sendToUser(uid, { title, body, data = {} }) {
  const snap = await db.collection("users").doc(uid).collection("fcm_tokens").get();
  const tokens = snap.docs.map((d) => d.id).filter(Boolean);
  if (tokens.length === 0) {
    logger.info(`fara token pentru ${uid} — nu are aplicatia instalata sau n-a dat permisiunea`);
    return;
  }

  // MESAJ DATA-ONLY, DELIBERAT — fara camp `notification`.
  //
  // Prima versiune (2026-09-03) trimitea `notification: {title, body}`, iar
  // Android afisa singur notificarea din system tray. DOUA probleme, ambele
  // raportate de user:
  //  1. TAP-ul nu ducea nicaieri in aplicatie — notificarea de sistem
  //     deschide doar activitatea de lansare, fara payload de rutare;
  //  2. INTARZIERE mare — FCM trateaza mesajele-notificare catre aplicatii in
  //     fundal ca "low priority" si le amana/grupeaza, mai ales pe Samsung cu
  //     optimizarea de baterie.
  //
  // Data-only cu `priority: high` NU e amanat la fel, iar aplicatia isi
  // deseneaza singura notificarea (background handler in push_service.dart),
  // deci controleaza si sunetul, si canalul, si ce se intampla la tap.
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    // Tot ce ii trebuie aplicatiei ca sa deseneze notificarea SI sa stie unde
    // sa navigheze la tap. Toate valorile STRING — FCM refuza numerele.
    data: Object.fromEntries(
      Object.entries({ title, body, channelId: CHANNEL_ID, ...data })
        .map(([k, v]) => [k, String(v)])
    ),
    android: { priority: "high" },
  });

  // Curatam token-urile moarte, ca lista sa nu creasca la nesfarsit.
  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token") {
      dead.push(tokens[i]);
    }
  });
  if (dead.length) {
    const batch = db.batch();
    for (const t of dead) {
      batch.delete(db.collection("users").doc(uid).collection("fcm_tokens").doc(t));
    }
    await batch.commit();
    logger.info(`sterse ${dead.length} token-uri moarte pentru ${uid}`);
  }
  logger.info(`trimis catre ${uid}: ${res.successCount}/${tokens.length}`);
}

/** Numele afisat al unui jucator, din profilul public. Fara el, notificarile
 * ar scrie "cineva ti-a scris", ceea ce nu spune nimic. */
async function displayName(uid) {
  try {
    const doc = await db.collection("player_profiles").doc(uid).get();
    return (doc.exists && doc.data().name) || "Cineva";
  } catch (e) {
    logger.warn(`nu am putut citi numele lui ${uid}: ${e}`);
    return "Cineva";
  }
}

// ─── Mesaj privat intre prieteni ────────────────────────────────────────────
// Id-ul firului e "uidA_uidB", sortat alfabetic (vezi FriendChatService si
// regula din firestore.rules) — destinatarul e celalalt din pereche.
exports.onFriendMessage = onDocumentCreated(
  "friend_chats/{threadId}/messages/{messageId}",
  async (event) => {
    const msg = event.data && event.data.data();
    if (!msg) return;
    const senderId = msg.senderId;
    if (!senderId) return;

    const parts = String(event.params.threadId).split("_");
    const recipient = parts.find((p) => p && p !== senderId);
    if (!recipient) return;

    const name = await displayName(senderId);
    const text = String(msg.text || "").slice(0, 120);
    await sendToUser(recipient, {
      title: `💬 ${name}`,
      body: text || "Ti-a trimis un mesaj.",
      data: { type: "chat", withUid: senderId },
    });
  }
);

// ─── Cerere de prietenie ────────────────────────────────────────────────────
// Documentul e player_profiles/{uid}/friend_requests/{fromUid} — destinatarul
// e chiar {uid}, expeditorul e id-ul documentului.
exports.onFriendRequest = onDocumentCreated(
  "player_profiles/{uid}/friend_requests/{fromUid}",
  async (event) => {
    const { uid, fromUid } = event.params;
    if (uid === fromUid) return;
    const name = await displayName(fromUid);
    await sendToUser(uid, {
      title: "👋 Cerere de prietenie",
      body: `${name} vrea sa te adauge.`,
      data: { type: "friend_request", fromUid },
    });
  }
);

// ─── Anunt de sistem scris de admin ─────────────────────────────────────────
// Cutia postala per jucator, vezi NotificationService.pullFromCloud.
exports.onSystemNotification = onDocumentCreated(
  "player_profiles/{uid}/notifications/{notificationId}",
  async (event) => {
    const n = event.data && event.data.data();
    if (!n) return;
    await sendToUser(event.params.uid, {
      title: String(n.title || "📣 Anunt"),
      body: String(n.body || n.message || ""),
      data: { type: "system" },
    });
  }
);

// ─── Invitatie intr-o camera de multiplayer ─────────────────────────────────
// Scrisa de cel care invita (vezi MultiplayerService.inviteFriendToRoom).
// La tap, aplicatia intra DIRECT in camera — de-aia `matchId` si `code` merg
// in `data`, nu doar in text.
exports.onRoomInvite = onDocumentCreated(
  "room_invites/{inviteId}",
  async (event) => {
    const inv = event.data && event.data.data();
    if (!inv || !inv.toUid || !inv.matchId) return;
    const name = await displayName(inv.fromUid || "");
    await sendToUser(inv.toUid, {
      title: "🎮 Te-a invitat la o partida",
      body: `${name} te asteapta in camera. Apasa ca sa intri.`,
      data: {
        type: "room_invite",
        matchId: inv.matchId,
        code: inv.code || "",
        fromUid: inv.fromUid || "",
      },
    });
    // Invitatia si-a facut treaba; o marcam ca trimisa ca sa se poata curata.
    try {
      await event.data.ref.update({ pushedAt: FieldValue.serverTimestamp() });
    } catch (e) {
      logger.warn(`nu am putut marca invitatia ${event.params.inviteId}: ${e}`);
    }
  }
);

// ─── Firul admin ↔ jucator ──────────────────────────────────────────────────
// O SINGURA functie pentru ambele sensuri: documentul stie el cine a scris
// (`fromAdmin`), iar destinatarul e mereu celalalt. Doua functii separate ar
// fi insemnat acelasi cod scris de doua ori, cu doua deploy-uri de tinut minte.
//
// `admin_threads/{uid}` se numeste cu uid-ul JUCATORULUI (vezi AdminChatService
// pentru de ce nu e perechea sortata ca la friend_chats), deci
// `event.params.uid` e mereu jucatorul, indiferent cine a scris mesajul.
exports.onAdminMessage = onDocumentCreated(
  "admin_threads/{uid}/messages/{messageId}",
  async (event) => {
    const msg = event.data && event.data.data();
    if (!msg) return;
    const playerUid = event.params.uid;
    const text = String(msg.text || "").slice(0, 120);

    if (msg.fromAdmin) {
      await sendToUser(playerUid, {
        title: "✉️ Raspuns de la administrator",
        body: text || "Ti-a raspuns la mesaj.",
        // Fara `withUid`: jucatorul deschide PROPRIUL fir, nu al altcuiva.
        data: { type: "admin_chat" },
      });
      return;
    }

    const admin = await adminUid();
    // Adminul care isi scrie in propriul fir nu are de ce sa se anunte singur.
    if (!admin || admin === playerUid) return;
    const name = await displayName(playerUid);
    await sendToUser(admin, {
      title: `✉️ Mesaj de la ${name}`,
      body: text || "Ti-a scris un jucator.",
      // `withUid` spune aplicatiei ca sunt adminul si al cui fir sa deschida.
      data: { type: "admin_chat", withUid: playerUid },
    });
  }
);
