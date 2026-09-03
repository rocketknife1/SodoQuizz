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

  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    // Toate valorile din `data` trebuie sa fie STRING — FCM refuza numerele.
    data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
    android: {
      priority: "high",
      notification: {
        channelId: CHANNEL_ID,
        sound: "sodo_notify",
        // Cerinta userului: notificarea RAMANE in bara, nu dispare la tap.
        // Trebuie spus si aici, nu doar in canal: campul e per-mesaj.
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
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
