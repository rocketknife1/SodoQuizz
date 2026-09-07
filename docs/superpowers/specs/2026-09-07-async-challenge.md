# Async Challenge — „Provoacă un prieten"

**Statut:** DRAFT, așteaptă OK de la user înainte de plan/implementare.

## Ce e

Un duel de quiz care NU cere doi oameni online în același moment.

1. Jucătorul A apasă „Provoacă un prieten" → primește 10 întrebări, le face.
2. Jocul generează un **cod** (`ABC123`) + un link (`guessit://challenge/<id>`).
3. A trimite codul/linkul prin orice (WhatsApp, Discord, share sheet).
4. Jucătorul B intră când poate — primește **EXACT aceleași 10 întrebări**, în
   aceeași ordine, cu aceleași variante.
5. La finalul lui B: „Tu 8.740 · A 9.120 — ai câștigat / ai pierdut".
6. A primește o notificare push: „B a răspuns provocării tale: 9.120 vs 8.740".

Fără boți. Fără meci fals. Fără simultaneitate. Un duel social real.

## De ce (din feedback-ul GPT)

Multiplayer-ul e cea mai bună parte a jocului dar cere jucători online
simultan — și jocul are ~0. Async Challenge e singura formă de PvP care merge
la 0 jucători online. GPT: „mult mai valoros acum decât 2v2".

## Ce refolosim (aproape tot există)

| Nevoie | Există deja |
|---|---|
| Set determinist de întrebări dintr-un seed | `core/daily_challenge.dart` (`stableShuffle` + `stableHash`) |
| Ecran de quiz cu 5-10 întrebări + scor + board | `screens/daily_challenge_screen.dart` |
| Deep link `guessit://...` (cold + warm start) | `main.dart._listenForDeepLinks` |
| Share sheet | `share_plus` (folosit la invitații prieteni) |
| Notificări push la un eveniment | Cloud Function + FCM (6 triggere există) |
| Cont anonim / prieteni / identitate | tot |

## Model de date

Colecție nouă `challenges/{challengeId}`:
```
{
  seed: int,              // din care se derivă cele 10 întrebări (determinist)
  creatorUid: string,
  creatorName: string,
  creatorScore: int,      // scris când A termină (A joacă PRIMUL, la creare)
  creatorCorrect: int,
  createdAt: timestamp,
  // scrise când B termină:
  opponentUid: string?,
  opponentName: string?,
  opponentScore: int?,
  opponentCorrect: int?,
  finishedAt: timestamp?,
}
```

- `challengeId` = 6 caractere din alfabetul fără ambiguități (`23456789ABCDEF...`,
  același ca `friendCode`).
- **A joacă la creare** — scorul lui e fix din prima, nu poate fi rejucat
  (aceeași filozofie ca anti-reluare: se scrie la primul răspuns).
- B poate juca **o singură dată** — după ce `opponentUid` e setat, provocarea
  e închisă. Al treilea care deschide linkul vede doar rezultatul.
- Întrebările NU se stochează — se derivă din `seed` pe fiecare client (ca la
  Provocarea Zilei). 10 întrebări cu poză, `stableShuffle(pool, seed)`.

## Reguli Firestore

```
match /challenges/{id} {
  allow read: if request.auth != null;
  allow create: if request.auth != null
    && request.resource.data.creatorUid == request.auth.uid
    && !('opponentUid' in request.resource.data);
  allow update: if request.auth != null
    && resource.data.creatorUid != request.auth.uid          // nu-ți rescrii propriul scor
    && !('opponentUid' in resource.data)                     // doar primul adversar
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['opponentUid','opponentName','opponentScore','opponentCorrect','finishedAt']);
}
```

Scorul e scriabil de client (ca tot restul economiei) — un trișor își poate
pune 10/10. Acceptabil: e un duel 1-la-1 între prieteni, nu clasament global.
Dacă devine problemă: mută calculul scorului într-o Cloud Function la
lansarea server-authoritative (Val 2).

## Deep link

`guessit://challenge/<id>` — `main.dart._handleFriendInviteUri` primește deja
`guessit://` cu host; adaug o ramură `host == 'challenge'` care deschide
`AsyncChallengeScreen(challengeId: id)`.

Fallback fără aplicație instalată: linkul e inert pe un telefon fără joc.
Pentru share e ok să trimitem și textul: „Te provoc la SodoQuizz! Cod: ABC123
— guessit://challenge/ABC123". Cine n-are jocul vede codul și textul.

## Ecrane

1. **Intrarea** — buton „⚔️ Provoacă un prieten" pe ecranul Multiplayer
   (lângă Create Room / Join Online / Join with Code) SAU pe ecranul de
   Prieteni, per rând de prieten („provoacă-l").
2. **AsyncChallengeScreen** — 3 stări:
   - `creating` (nu am jucat încă) → intro → 10 întrebări → „Trimite
     provocarea" (share sheet + cod copiabil)
   - `answering` (am deschis linkul cuiva, provocarea e liberă) → intro cu
     „X te-a provocat. Scorul lui: ascuns până termini" → 10 întrebări →
     rezultat comparativ
   - `done` (provocarea s-a încheiat, sau eu am creat-o și adversarul a
     jucat) → ecranul de rezultat: cele două scoruri + „revanșă" (creează o
     provocare nouă către același adversar)
3. **Notificare push** la `creatorUid` când B termină (Cloud Function nouă
   `onChallengeAnswered`, trigger pe update).

## Recompense

- Câștigătorul: monede + XP (scalate cu nivelul, ca la Provocarea Zilei).
- Perdantul: consolare mică (XP).
- Fără miză pe monede (evită gambling-adjacent — vezi TODO).
- Contorul „provocări câștigate" → titlu nou? („Duelist"). De discutat.

## Ce NU face v1

- Nu e ranked, nu mișcă ratingul Elo (ăla rămâne pentru meciurile simultane).
- Nu e best-of-N, o singură rundă de 10.
- Nu are chat/emote (poate mai târziu).
- Nu expiră (o provocare veche de o lună tot poate fi jucată de adversar).

## Efort estimat

- Model + service + reguli: ~2h
- Ecranul (refolosind daily_challenge_screen ca bază): ~3h
- Deep link + share + intrarea în UI: ~1h
- Cloud Function `onChallengeAnswered` + deploy: ~1h
- Test cu 2 conturi (browser): ~1h

Total ~1 zi de lucru.

## Întrebări pentru user

1. Intrarea: buton separat pe ecranul Multiplayer, sau „provoacă" per prieten
   în lista de Prieteni, sau ambele?
2. 10 întrebări (ca un meci clasic) sau 5 (ca Provocarea Zilei)?
3. Recompensă pentru câștigător — cât? (Provocarea Zilei dă până la 350; aici
   propun ~150-200 fiindcă se poate juca de mai multe ori pe zi cu prieteni
   diferiți.) Plafon zilnic de provocări create?
4. Titlu nou „Duelist" la X provocări câștigate — da/nu?
