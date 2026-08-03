# Ce ai de făcut manual în Play Console

Ordinea contează — fiecare pas îl deblochează pe următorul. Textele de copiat
sunt în `listare.md`, grafica în `grafica/`, capturile în `capturi/`.

---

## 0. Înainte de orice: regula care îți dictează calendarul

⚠️ **Dacă ai cont de developer personal creat după 13 noiembrie 2023**, Google
nu te lasă să publici direct. Trebuie mai întâi un **test închis cu minimum 12
testeri, activi neîntrerupt 14 zile**, și abia apoi poți cere acces la
producție. Vezi [regula oficială](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en).

Detalii care contează:
- „Testeri activi" înseamnă că au **acceptat invitația și au instalat** jocul
  cu contul Google invitat. Cei invitați care n-au instalat nu se pun la
  socoteală.
- Conturile de tip **organizație** și cele personale create înainte de acea
  dată sunt scutite — publică direct.

Practic: cele 14 zile încep abia după ce ai 12 oameni instalați, deci merită
să-i aduni pe toți deodată, nu pe rând. Prietenii care testează deja APK-ul de
pe GitHub sunt exact candidații.

**Ai nevoie și de:** cont Google Play Developer (taxă unică de 25 $) și
verificarea identității, care poate dura câteva zile. Dacă n-ai contul încă,
începe cu asta azi — restul poate aștepta, verificarea nu.

---

## 1. Creezi aplicația

**Play Console → Create app**

| Câmp | Ce alegi |
|---|---|
| App name | `SodoQuizz: Ghicește imaginea` |
| Default language | Română (ro-RO) |
| App or game | **Game** |
| Free or paid | **Free** |
| Declarații | bifezi ambele (politici pentru dezvoltatori + legile SUA de export) |

---

## 2. Urci fișierul aplicației

Fișierul e deja construit, semnat și sub limita Google:

```
build/app/outputs/bundle/release/app-release.aab      (120,5 MB)
```

**Testing → Closed testing → Create new release** (nu Production — vezi pasul 0).

⚠️ Bundle-ul ăsta e construit cu `--dart-define=REAL_ADS=true`, deci cu
reclamele reale. Ăsta e cel corect pentru Play. Dacă trebuie reconstruit:

```
flutter build appbundle --release --dart-define=REAL_ADS=true
```

**Nu** urca APK-ul de pe GitHub — ăla e cu reclame de test, intenționat.

La **Release notes**, poți pune direct:
```
Prima versiune publică. 1.394 de întrebări în 14 categorii, multiplayer cu
pariuri, Higher or Lower, roata norocului și quest-uri zilnice.
```

---

## 3. Store listing

**Grow → Store presence → Main store listing.** Copiezi din `listare.md`:
nume, descriere scurtă, descriere completă. Încarci:

- **App icon** → `grafica/icon-512.png`
- **Feature graphic** → `grafica/feature-graphic-1024x500.png`
- **Phone screenshots** → toate 8 din `capturi/`, în ordinea din `listare.md`
  (sari peste `_contact_sheet.png`, ăla e doar pentru tine)

---

## 4. Formularul de Data Safety

E cel mai ușor de greșit din toate, pentru că declari sub răspunderea ta. Am
verificat în cod exact ce colectează aplicația — completează așa:

### Colectezi date? **Da**

| Tip de dată | Colectată | Trimisă terților | Obligatorie | De ce |
|---|---|---|---|---|
| **Adresă de email** | **Da** | Nu | **Nu** (doar dacă te loghezi cu Google) | Gestionarea contului: identifică contul la reconectare |
| **Nume** | Da | Nu | **Nu** (doar dacă te loghezi cu Google) | Funcționalitate: numele afișat în clasament și multiplayer |
| **Fotografii** (poza de profil Google) | Da | Nu | **Nu** | Funcționalitate: avatarul din clasament |
| **Acțiuni în aplicație** (progres, scoruri) | Da | Nu | Da | Funcționalitate: salvare în cloud, clasament |
| **ID-uri de dispozitiv** | Da | **Da** | Da | Publicitate (AdMob) |

⚠️ **„Acțiuni în aplicație" se bifează ca fiind colectată de la TOȚI, nu doar
de la cei logați** (schimbare din 3 august 2026). Înainte, progresul unui
jucător fără cont Google rămânea doar pe telefon; acum se urcă și el în
`users/{uid}`, legat de identitatea anonimă, ca să poată fi verificat din
panoul de admin. E singurul motiv pentru care rândul ăsta e „obligatorie: Da"
— politica de confidențialitate publicată spune deja același lucru.

⚠️ **Emailul TREBUIE bifat.** E ușor de ratat, pentru că în Firestore nu se
scrie nicăieri — dar Firebase Authentication îl stochează la conectarea cu
Google, aplicația îl afișează în Profil, iar `firestore.rules` îl folosește
ca să recunoască adminul. Google consideră asta colectare de date, iar
politica ta de confidențialitate o declară deja. Dacă bifezi „nu", intri în
contradicție cu propria politică — motiv clasic de suspendare.

La „Data usage and handling" pentru email alege: **Colectată**, *nu* trimisă
terților, **opțională**, scop **Gestionarea contului**. Poate fi ștearsă de
utilizator (Profil → Șterge contul definitiv).

**Ce NU colectează** — nu bifa: locație, contacte, mesaje, fișiere,
informații financiare, date de sănătate, istoric de căutare. Verificat în
cod, Firestore conține exact două lucruri:
- `player_profiles/{uid}`, public: `name`, `photoUrl`, `avatarSeed`,
  `lastActive`, `hasGoogleAccount`, `activityEvents` și statistici de joc;
- `users/{uid}`, privat (doar proprietarul și adminul): progresul de joc și
  setările — monede, gems, XP, întrebări răspunse, quest-uri, sunet.

**Datele sunt criptate în tranzit?** Da (Firebase folosește HTTPS peste tot).

**Utilizatorii pot cere ștergerea datelor?** **Da** — există în joc, la
Profil → Șterge contul. Șterge și profilul public, și salvarea din cloud.

**Politica de confidențialitate:**
```
https://rocketknife1.github.io/SodoQuizz/privacy-policy.html
```

---

## 5. Content rating

**Policy → App content → Content rating.** Răspunsuri pentru jocul tău:

- Categorie: **Joc**
- Violență, sex, limbaj vulgar, droguri: **Nu** la toate
- **Jocuri de noroc simulate:** aici trebuie gândit. Sistemul de pariuri
  folosește **exclusiv monede virtuale, care nu se pot cumpăra cu bani reali
  și nu se pot converti în bani**. Răspunde ce te întreabă exact formularul,
  dar reține că nu e vorba de gambling real. Dacă întrebarea e „conține
  elemente de gambling simulat" — răspunsul onest e **da**, iar clasificarea
  probabil urcă la PEGI 12. Nu ascunde asta, e exact genul de lucru pentru
  care se retrag aplicații.
- Interacțiune între utilizatori: **Da** (chat în camerele multiplayer)
- Partajarea locației: **Nu**

---

## 6. Restul secțiunilor din App content

| Secțiune | Răspuns |
|---|---|
| **Ads** | **Da, conține reclame** |
| **App access** | „Toate funcțiile sunt disponibile fără acces special" — jocul merge complet fără cont |
| **Target audience** | 13+ (din cauza chatului și a pariurilor simulate) |
| **News app** | Nu |
| **COVID-19 apps** | Nu |
| **Data safety** | vezi pasul 4 |
| **Government apps** | Nu |
| **Financial features** | **Nu** — magazinul cu bani reali e dezactivat în cod (`realMoneyStoreEnabled = false`) |
| **Health apps** | Nu |

---

## 7. După ce aplicația e publicată

Abia acum se deblochează lucrurile pe care le-am tot încercat degeaba:

1. **AdMob → Apps to confirm → Finish setup** → de data asta „Link to Google
   Play" chiar găsește aplicația. Alege **„Add to an existing AdMob app" →
   Sodo Quizz**, ca App ID-ul din cod să rămână valabil.
2. **AdMob → app-ads.txt** → îți pregătesc eu fișierul, dar trebuie pus la
   rădăcina unui domeniu declarat în listarea din Play. Atenție:
   `rocketknife1.github.io/SodoQuizz/` e o pagină de *proiect*, nu o rădăcină
   validă — o să-ți trebuiască un repo numit exact `rocketknife1.github.io`.
3. **Firebase → Project settings → Google Play** → acum se poate lega. Merită
   activate: App Distribution (le trimiți testerilor bundle-uri, nu APK-uri de
   147 MB), Crashlytics și datele de venit în Analytics.
4. **Review-ul AdMob** pornește automat, durează 2-3 zile. După el încep
   reclamele plătite.

---

## Ce rămâne strict la tine

Nu pot face în locul tău: contul de developer și taxa de 25 $, verificarea
identității, adunarea celor 12 testeri, răspunsurile din formularele de rating
și data safety (le semnezi tu) și apăsarea butonului de publicare.

Tot ce ține de cod, grafică, texte și fișierul de urcat e gata.
