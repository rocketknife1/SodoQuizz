# Timp real: schimbările din exterior se văd fără repornire

Spec de design, 2026-08-31. Partea **A** din trei (A: timp real, B: Cloud
Functions pentru validarea meciurilor, C: audit final). B și C primesc
specuri separate.

Revizia 2 — după o recenzie independentă care a verificat fiecare afirmație
împotriva codului. Zece afirmații din revizia 1 erau greșite; corecțiile
sunt marcate în text cu **[corectat R1]** acolo unde cineva care a citit
prima versiune ar putea rămâne cu ideea veche.

## Problema

Nimic din ce vine din exterior nu ajunge la jucător cât timp stă în
aplicație. Totul se citește o singură dată, la pornire și la revenirea din
fundal:

- `main.dart:55-71` — la pornire
- `main.dart:354-367` — la `paused`/`detached` (urcare) și `resumed`
  (`ensureProfileHeartbeat`, `consumePendingGrant`, `loadBlocked`,
  `pullFromCloud`)

Consecința: dacă adminul trimite monede unui jucător care stă în meniu, nu
se întâmplă nimic până când acela nu dă aplicația în fundal și înapoi.

A doua jumătate, la fel de vizibilă: chiar și când grantul se aplică,
`CloudSyncService.grantsApplied` e ascultat **doar** de `HomeScreen`
(`home_screen.dart:60`). Scenariul real: dai jocul în fundal stând pe
Magazin, primești 1000 de monede, revii pe Magazin — cumpărătura pică pe
„n-ai destui bani", deși banii sunt în cont.

## Ce nu e în domeniul acestui spec

- Validarea server-side a scorurilor de multiplayer (auditul #1) — partea B.
- Sincronizarea progresului între două telefoane. `pullOrSeed`
  (`cloud_sync_service.dart:66`) rămâne doar la logare: un „pull" automat ar
  putea suprascrie progres local mai nou.
- Clasamentul live și scorurile rundă-cu-rundă în modul Classic — vezi
  „Ce a mai găsit auditul".

---

## A1 — Abonamente live

Fiecare serviciu primește `startLive()` / `stopLive()` pentru domeniul lui.
Un singur coordonator, în `main.dart`, le pornește și oprește pe toate.

| Ce se ascultă | Unde | Efect |
|---|---|---|
| Resurse și reset de la admin | `admin_grants/{uid}` (document) | `consumePendingGrant()` pornește la scriere |
| Redenumire din Admin | `player_profiles/{uid}` (document) | `forcedName` se adoptă instant |
| Anunțuri de la admin | `player_profiles/{uid}/notifications` | Bulina se aprinde pe loc |
| Blocări | `player_profiles/{uid}/blocked` | Filtrarea de chat se aliniază |
| Cereri de prietenie | `player_profiles/{uid}/friend_requests` | Bulina + ecranul Prieteni |
| Fire de chat | `friend_chats/{threadId}`, **câte unul per prieten** | Bulina + rândurile din Prieteni |

**Reguli Firestore: niciuna nouă.** Ultimele trei sunt subcolecții sub
`player_profiles/{uid}` (wildcard-ul părinte e fixat de cale, iar
`fetchIncomingRequests` face deja exact acel `list` azi) sau documente
individuale.

### De ce NU se interoghează colecția de fire **[corectat R1]**

Revizia 1 cerea `friend_chats.where('members', arrayContains: uid)`. Ar fi
picat cu `permission-denied`. Regula (`firestore.rules:346-351`) verifică
apartenența despicând **numele documentului**
(`request.auth.uid in threadId.split('_')`), iar o interogare pe colecție nu
oferă motorului nicio cale să demonstreze condiția: regulile nu filtrează, ci
autorizează. Nu există azi nicio interogare de listă pe `friend_chats` și
nici `arrayContains` nicăieri în `lib/`, deci n-ar fi existat precedent care
să dea de gol greșeala.

Ar mai fi avut două defecte independente: `markRead`
(`friend_chat_service.dart:107-109`) creează documentul **fără** câmpul
`members`, deci firele deschise dar netrimise ar fi lipsit din rezultate; și
sortarea după `lastMessageAt` ar fi cerut un index compus creat manual
(repo-ul n-are `firestore.indexes.json`).

**În loc:** câte un `.snapshots()` pe `friend_chats/{threadIdFor(me, prieten)}`,
înlocuind cele N `get()` din `fetchSummaries`
(`friend_chat_service.dart:118-131`). `threadId` e fixat, deci regula
existentă le acoperă textual. Numărul de prieteni e mic și oricum se fac N
citiri azi — cost identic, zero reguli noi, zero indexuri.

### Ciclul de viață **[corectat R1]**

Legat de **identitate**, nu doar de ciclul de viață al aplicației. Un singur
ascultător pe `FirebaseAuth.instance.userChanges()`, după tiparul care
există deja la `main.dart:308-319`:

1. anulează **tot**, necondiționat, la fiecare eveniment;
2. repornește doar dacă `user != null && uid.isNotEmpty`;
3. reține uid-ul, ca să nu reconstruiască abonamentele la un eveniment care
   e doar `updateProfile`.

`userChanges()`, nu `authStateChanges()`: la legarea unui cont Google peste
identitatea anonimă (`auth_service.dart:207`) **uid-ul nu se schimbă**, deci
`authStateChanges` poate să nu emită deloc — dar sursa numelui se schimbă
(`updateProfile`, `:226-229`), iar A3 depinde de asta.

Gardă obligatorie: `if (Firebase.apps.isEmpty) return;`. Fără ea
`test/widget_test.dart` montează aplicația fără Firebase și
`FirebaseAuth.instance` aruncă — vezi precedentul documentat la
`main.dart:302-307`.

Căile de schimbare a identității, toate de acoperit:

- **Legare Google, cale de link** (`auth_service.dart:207`) — uid neschimbat,
  dar numele se schimbă.
- **Legare Google, cale `credential-already-in-use`** (`:210-219`) — uid nou.
- **Play Games** (`:293-305`) — a doua poartă de identitate, cu aceleași două
  ramuri. Revizia 1 n-o pomenea deloc.
- **`signOut()`** (`:330-337`) — **gaura serioasă.** Nu creează identitate
  anonimă nouă; `currentPlayerId` devine `''` și `ensureInitialized` nu mai
  poate repara nimic, fiindcă `_initialized` e deja `true`
  (`multiplayer_service.dart:114-115`). Aplicația rulează fără uid până la
  următoarea pornire la rece. Trecerea la `null` **trebuie** tratată ca
  schimbare de identitate: dacă garda `if (uid.isEmpty) return;` se pune
  *înaintea* anulării, abonamentele vechi rămân agățate.
- **`deleteAccount()`** (`:393-433`) — cazul cel mai prost: șterge userul, la
  Guest face `StorageService.resetAll()` (`:412`), apoi `signInAnonymously()`
  (`:429`). `_discardAnonymousIdentity` (`:377-385`) rulează
  `deleteMyProfile()` + `deleteCloudSave()` **cât timp uid-ul vechi e încă
  cel curent**, deci abonamentele trebuie rupte **înainte**, nu după.

Atașare la pornire din `_GuessItAppState.initState` (`main.dart:106-112`),
nu dintr-un callback de ciclu de viață: Flutter nu livrează starea inițială
prin `didChangeAppLifecycleState`.

Pe web (unde rulează verificarea Playwright) `paused` poate să nu vină
niciodată — se primește `hidden`. Se tratează și `hidden`, altfel
comportamentul verificat în browser diferă de cel de pe telefon.

### Capcane de implementare

**Bucla de scrieri.** Abonamentul pe `player_profiles/{uid}` se aprinde și
la scrierile noastre — heartbeat-ul scrie în chiar documentul ascultat. Se
ignoră snapshot-urile cu `metadata.hasPendingWrites`, iar `forcedName` se
compară cu valoarea locală înainte de orice scriere.

**`admin_grants` emite din nou după consum.** Tranzacția de revendicare
șterge documentul (`cloud_sync_service.dart:178`), deci ascultătorul
primește imediat un snapshot cu `exists == false`. Se ignoră. Filtrarea pe
`hasPendingWrites` se aplică și aici, nu doar pe profil.

**`pullFromCloud` n-are gardă de reintrare.** `consumePendingGrant` are
`_consumingGrant` (`cloud_sync_service.dart:40`) exact din acest motiv;
`NotificationService.pullFromCloud` (`notification_service.dart:154-188`) nu
are echivalent, iar `addLocal` (`:74-80`) e citire-modificare-scriere pe
SharedPreferences. Sub un declanșator live, două rulări concurente pot
**pierde o notificare**. Se adaugă `_pulling`, după tiparul existent.

**Amplificarea de citiri — condiție de acceptare, nu detaliu.** Fiecare
eveniment pe cereri sau fire de chat, dacă ajunge pe `refreshUnread()`
(`notification_service.dart:258`) → `fetchLive()` (`:199`), costă `2 + N`
citiri (N = numărul de prieteni). Un singur mesaj primit ar costa `2 + N`,
adică mai mult decât poll-ul pe care îl înlocuiește. **Ascultătorul trebuie
să actualizeze `unreadCount` din propriul snapshot**, nu prin `refreshUnread()`.

**Cost.** Cu regula de mai sus respectată: un abonament costă citiri doar la
atașare și la schimbări reale. Atașare la `resumed`, detașare la
`paused`/`hidden` ⇒ comparabil cu poll-ul de azi.

---

## A2 — Ecranele se reîmprospătează singure

`StorageService` primește un contor `balanceRevision` (`ValueNotifier<int>`).

### Punctul unic de trecere

```dart
static Future<void> _writeBalance(SharedPreferences prefs, String key, int value) async {
  await prefs.setInt(key, value);
  balanceRevision.value++;
}
```

Fiecare `prefs.setInt` pe `_coinsKey`, `_gemsKey`, `_livesKey`, `_hintsKey`,
`_xpKey` devine un apel la `_writeBalance` — 16 locuri în
`lib/data/storage_service.dart`:

| Cheie | Linii |
|---|---|
| `_livesKey` | `:160` (`setLives`), `:191` (`_rechargeLives`) |
| `_coinsKey` | `:265` (`addCoins`), `:273` (`spendCoins`), `:289` (`adjustCoins`) |
| `_gemsKey` | `:305` (`addGems`), `:313` (`spendGems`), `:323` (`adjustGems`) |
| `_hintsKey` | `:375` (`addHints`), `:385` (`addHintsUncapped`), `:394` (`adjustHints`), `:402` (`spendHint`) |
| `_xpKey` | `:419` (`addXp`), `:430` (`adjustXp`), `:449` + `:469` (migrări) |

`addLivesUncapped` (`:171-175`) și `grantQuestGems` (`:331`) sunt acoperite
tranzitiv — trec prin cele de mai sus.

### A doua regulă, fără de care mecanismul e incomplet **[corectat R1]**

Regula „cheile de balanță nu se scriu direct" e **necesară dar nu
suficientă**. Trei funcții schimbă balanța fără să atingă vreo cheie
literală:

- **`importAll`** (`:1794`) — `prefs.setInt(entry.key, value)`, cheie
  variabilă la runtime. Apelat din `cloud_sync_service.dart:72` (`pullOrSeed`)
  și din `:642`.
- **`resetToStartingBalance`** (`:641`) — `prefs.clear()`, nicio scriere de
  balanță; se bazează pe getterele care cad pe valorile de start.
- **`resetAll`** (`:595`) — `prefs.clear()`. **Lipsea complet din revizia 1.**
  Apelat din `auth_service.dart:412` (ștergere de cont Guest) și din Profil
  („șterge tot progresul").

Deci: *orice funcție care golește sau reimportă SharedPreferences crește
contorul explicit, la final.*

### Două lucruri de știut înainte de implementare **[corectat R1]**

- **`_rechargeLives` e chemat din CITIRI** — `getLives` (`:132`) și
  `livesRechargeRemaining` (`:142`). Cu `_writeBalance` acolo, o citire poate
  crește contorul, deci ascultătorii se redesenează și citesc iar. Converge
  (scrie doar când chiar au trecut minutele de regenerare, cel mult o dată la
  ~23 min), deci e acceptabil — dar e intenționat, nu de „reparat".
- **Migrările XP nu rulează „doar la pornire".** Sunt lazy, chemate din
  `getXp` (`:410`), `addXp` (`:417`), `adjustXp` (`:428`), și se rearmează
  după orice `prefs.clear()` fiindcă flagurile dispar. Pot rula în mijlocul
  sesiunii, cu ecranele deja abonate. Trec prin `_writeBalance` ca oricare
  altă scriere.

### Ecranele care ascultă

`home_screen.dart`, `profile_screen.dart`, `shop_screen.dart`,
`categories_screen.dart`, `game_screen.dart`, `quests_screen.dart`,
`achievements_screen.dart`, `planet_hologram_screen.dart`,
`widgets/lives_countdown_card.dart`, `widgets/match_stake_dialog.dart`.

Înlocuiește `CloudSyncService.grantsApplied`, care acoperea doar grant-urile
și doar `HomeScreen`.

---

## A3 — Numele: din lanț, în valoare de pornire

### Ce e azi

Două reguli separate, amândouă mai stricte decât intenția reală:

1. **Contul Google.** `auth_service.dart:93-96` — numele vine din
   `u.displayName` și ignoră orice nume local. `profile_screen.dart:121` —
   `nameLocked: identity.photoUrl != null || …`, deci cine are poză de Google
   nu vede nici creionul. Un jucător cu cont Google **nu-și poate schimba
   deloc numele**.
2. **`forcedName`.** Construită ca unealtă de moderare permanentă: la un cont
   Google doar adminul o putea ridica.

Intenția reală: redenumirea e o **etichetă de comoditate**, ca proprietarul
să-și recunoască prietenii. Oricine trebuie să-și poată schimba numele
oricând; un „război de redenumiri" e acceptabil.

### Ce rămâne necesar

Fără `forcedName`, redenumirea se anulează singură în câteva minute, fără ca
jucătorul să facă nimic: heartbeat-ul lui rescrie `name` din identitatea
locală (`player_profile_service.dart:93-94`). Asta nu e „el și-a pus
altceva", ci „i-am pus nume și s-a evaporat". Deci `forcedName` păstrează
rolul de „face redenumirea să țină" și pierde rolul de blocare.

### Prioritatea nouă

```
forcedName  →  numele ales de jucător  →  numele din contul Google
```

Cheia locală `display_name_chosen` (bool) desparte ultimele două. Devine
`true` abia când jucătorul chiar salvează un nume.

Pornind pe `false`, jucătorii Google de azi rămân **exact** pe comportamentul
actual până când aleg singuri altceva. Fiind cheie SharedPreferences, intră
automat în cloud-save (`exportAll`), deci alegerea se mută cu jucătorul pe
alt telefon.

### Trei capcane, toate găsite de recenzie **[corectat R1]**

**(a) `display_name_chosen` trebuie adăugată în `_resetPreservedKeys`**
(`storage_service.dart:605-618`). Altfel: adminul apasă „Reset" →
`resetToStartingBalance` face `prefs.clear()` → `display_name` supraviețuiește
(e în listă) dar `display_name_chosen` nu → jucătorul cade înapoi pe numele
din Google, adică **e redenumit în tăcere**. Exact riscul #1 al specului,
declanșat de o funcție care există deja. `test/account_reset_test.dart:44+`
se extinde cu ea.

**(b) `getDisplayName()` scrie la citire.** `storage_service.dart:1719-1726`
— la prima citire generează `JucatorNNN` **și îl salvează**. Azi e inofensiv
(se ajunge acolo doar când nu există nume Google). Sub noua prioritate,
întrebarea „și-a ales un nume?" se pune la fiecare rezolvare de identitate,
inclusiv pentru conturi Google — deci ar scrie `display_name` pentru fiecare
jucător Google care n-avea unul. Consecințe: cheia intră în `exportAll`,
amprenta `cloud_push_snapshot` (`cloud_sync_service.dart:110`) nu se mai
potrivește, și apare o **scriere Firestore în plus** — exact ce verificarea 6
interzice. Plus că ar crea chiar numele-gunoi pe care specul vrea să-l evite.

Deci: se adaugă un cititor **fără efecte secundare** (`getChosenDisplayName()`,
întoarce `''` când cheia lipsește). Funcția de prioritate primește
`(forcedName, chosenName, chosenFlag, googleName)` ca șiruri simple, deci e
pură și testabilă. `getDisplayName()` rămâne strict fallback-ul de Guest.

**(c) În `multiplayer_screen.dart` blocajul NU se numește `nameLocked`.** Se
numește `_isGoogleLinked`: definiție la `:63-64`, poartă la `:190`
(`if (_isGoogleLinked) return;`), creion ascuns la `:570`. Un grep după
`nameLocked` nu-l găsește, iar ecranul de Multiplayer ar rămâne blocat.
Locurile reale cu `nameLocked`: `home_screen.dart:103, 265, 474, 486` și
`profile_screen.dart:121, 130, 256, 267, 286, 783, 796`.

### Modificări concrete

- `nameLocked` dispare din `profile_screen.dart` și `home_screen.dart`;
  `_isGoogleLinked` dispare ca poartă de editare din `multiplayer_screen.dart`.
- Textul „Numele vine din contul tău Google" → „Apasă pe nume ca să-l
  schimbi". **Un singur loc**, `profile_screen.dart:287` — restul
  potrivirilor din grep sunt comentarii. **[corectat R1: revizia 1 zicea
  „peste tot".]**
- `editDisplayName` (`widgets/edit_name_dialog.dart`) setează
  `display_name_chosen = true`. **Nu** are nevoie de modificări pentru
  eliberarea lui `forcedName`: `:62-64` o face deja necondiționat, pentru
  toată lumea. Restricția „doar Guest" trăia exclusiv în porțile de mai sus.
  **[corectat R1: revizia 1 cerea o schimbare care e no-op.]**
- `clearForcedNameAsAdmin` se păstrează; butonul se redenumește din „Lasă-l
  liber" în „Anulează redenumirea" — singura cale de a da înapoi fără să
  știi numele original.
- Prin abonamentul de la A1, redenumirea apare pe ecranul jucătorului
  instant.

### Limite acceptate, ca să nu pară regresii

- `announceEntered` (`multiplayer_screen.dart:87-91`) și documentele de
  jucător din meci sunt **instantanee** ale numelui la intrare: un nume vechi
  poate persista într-un lobby deja deschis.
- `forced_name` nu e în `_resetPreservedKeys`, deci un reset îl șterge local,
  dar serverul îl mai are și următorul heartbeat îl adoptă înapoi
  (`player_profile_service.dart:86-89`). Preexistent; se rezolvă odată cu
  „Anulează redenumirea".
- `releaseMyForcedName` (`player_profile_service.dart:656`) așteaptă o
  scriere Firestore care offline nu se încheie niciodată. Preexistent, dar A3
  o mută de pe calea „doar Guest" pe calea tuturor, deci scrierea nu se mai
  așteaptă (`unawaited`), iar partea locală se aplică imediat.

---

## A4 — Ban-ul devine real

Azi ban-ul nu face aproape nimic: colecția `banned_players` e scrisă
(`player_profile_service.dart:672`) și **niciodată citită** de aplicație.
Cel banat joacă mai departe; îi dispar doar prietenii și clasamentul, iar
scrierile lui eșuează în tăcere.

Decizie: **jucătorul banat află și nu mai poate juca online.** Multiplayer și
clasament închise, cu un mesaj clar care spune de ce. Single-player rămâne
disponibil — un ban greșit nu trebuie să-i ia omului tot jocul.

Regula existentă (`firestore.rules:371-372`) permite citirea doar adminului,
deci **e nevoie de o regulă nouă**: proprietarul are voie să citească
`banned_players/{uid}` doar pentru propriul uid. Se verifică în Rules
Playground înainte, ca la orice regulă nouă.

Starea de ban se citește la pornire și prin abonament (A1), ca ridicarea unui
ban să ajungă la fel de repede ca punerea lui.

---

## Ce a mai găsit auditul

Un agent de explorare a parcurs toate apelurile `.get()`, toate
`FutureBuilder`-ele și toate `initState`-urile din `lib/screens`.

**În domeniul lui A:**

- **Sursa bulinei nu e alimentată de nimic din exterior.** Widget-ul
  (`widgets/notification_bell.dart:63-64`) e deja un `ValueListenableBuilder`
  pe `unreadCount` și e **corect** — nu se atinge. Ce lipsește e o sursă
  live: `refreshUnread()` e chemat doar din `initState` (`:42`), la
  închiderea panoului (`:57`), din `addLocal`/`markStoredRead`/`clearStored`,
  și din `main.dart:65,365`. **[corectat R1: revizia 1 acuza widget-ul.]**
- **Ecranul de Prieteni e o poză făcută la intrare**
  (`screens/friends_screen.dart:30,40,41,47`). Abonamentele per-fir îl
  rezolvă.
- **Blocările de pe alt telefon nu ajung în cadrul sesiunii.**
  `loadBlocked` (`moderation_service.dart:53-56`) **nu e un bug**: ieșirea
  devreme e documentată intenționat la `:49-52`, iar portița `force: true`
  există deja. Abonamentul o înlocuiește oricum.
  **[corectat R1: revizia 1 o numea „bug găsit pe drum".]**

**În afara lui A, cu motiv:** clasamentul
(`leaderboard_screen.dart:374,440,508`) și antetul de sezon au deja
pull-to-refresh și n-ar justifica abonamente peste sute de profiluri;
scorurile adversarilor în modul Classic
(`multiplayer_match_screen.dart:149-152`) sunt rare intenționat, ca economie
de scrieri.

**Deja corect, nu se atinge:** lobby-ul camerei, matchmaking-ul, chatul
privat, invitațiile de meci rapid, revanșa și anunțul de prezență — toate pe
`.snapshots()`, unele ascultate de la rădăcina aplicației.

---

## Verificare

Nimic nu se declară gata pe baza lui „ar trebui să meargă".

**Linia de bază, măsurată înainte de orice modificare:** `flutter analyze` —
zero probleme; `flutter test` — 199 teste verzi.

**Automat**, pentru logica pură:

- funcția de prioritate a numelui, pură, cu cele patru intrări;
- `display_name_chosen` supraviețuiește lui `resetToStartingBalance`
  (extinde `test/account_reset_test.dart`);
- `balanceRevision` crește la fiecare scriere de balanță — **inclusiv** la
  `resetAll`, `resetToStartingBalance` și `importAll`, care nu ating chei
  literale. `test/account_reset_test.dart:19-42` arată deja că resetul
  schimbă balanța fără niciun `setInt`, deci un test formulat ca „crește
  numai la mutatori" ar pica. **[corectat R1.]**
- adoptarea lui `forcedName` în ambele sensuri (apare / dispare).

**Pe viu**, doi jucători în Playwright (două contexte Chrome) + panoul de
Admin:

1. Jucătorul stă în meniu; adminul îi trimite monede → cifra se schimbă fără
   ca nimeni să atingă ceva.
2. Același test cu jucătorul pe **Profil** și pe **Magazin** — a doua
   jumătate a bugului.
3. Redenumire din Admin → apare instant; apoi jucătorul și-l schimbă singur,
   **inclusiv pe cont Google**.
4. „Anulează redenumirea" îl întoarce la numele original.
5. Anunț din Admin → bulina se aprinde fără repornire.
6. Ban → jucătorul primește mesajul și nu mai intră în multiplayer;
   ridicarea ban-ului îl lasă înapoi.
7. **Fără buclă de scrieri și fără amplificare:** aplicația stă deschisă și
   neatinsă două minute — contorul de scrieri din consola Firestore nu
   crește. Un mesaj primit produce **o** citire, nu `2 + N`.

**Reguli Firestore:** regula nouă de la A4 se verifică în Rules Playground
înainte de deploy. Deploy-ul (`firebase deploy --only firestore:rules`) cere
OK explicit — include și regula `completed_matches` scrisă pe 29 august și
încă nedeployată.

## Riscuri

- **Migrarea numelui** — `display_name_chosen` greșit ⇒ jucători Google
  redenumiți în tăcere. Se testează primul, inclusiv pe calea de reset.
- **Bucla de scrieri și amplificarea de citiri** — un abonament care își
  declanșează singur scrierea, sau o bulină care costă `2 + N` citiri per
  eveniment, consumă cotă în tăcere. Verificarea 7 e obligatorie, nu
  opțională.
- **Abonamente agățate de un uid vechi** — livrează datele altcuiva.
  Acoperit prin legarea de `userChanges()` și prin ruperea abonamentelor
  înainte de ștergerea identității.
