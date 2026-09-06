# SodoQuizz — raport complet de stare (7 septembrie 2026)

> **Context pentru cine citește:** n-ai mai auzit de proiectul ăsta de ~2 luni.
> Documentul e scris să fie de sine stătător — explică jocul de la zero, apoi
> ce s-a construit, apoi ce urmează. La final sunt întrebările la care chiar
> vreau o părere.
>
> **Cod public:** https://github.com/rocketknife1/SodoQuizz
> **Joc jucabil în browser:** https://rocketknife1.github.io/SodoQuizz/
> **Android:** în testare închisă pe Google Play (`com.dragosssx.guessit`)

---

## 1. Ce e jocul, pe scurt

**SodoQuizz** e un joc de quiz cu poze, în română și engleză, făcut în
Flutter cu backend Firebase. Dezvoltat de o singură persoană.

**Mecanica de bază:** vezi o poză neclară (blur) și ghicești ce e, din 4
variante. Cu cât ghicești mai repede, cu atât iei mai multe puncte. Poza se
clarifică treptat. Ai și hint-uri (50/50 etc.) care costă.

**Conținut:** 15 categorii, **1.494 de întrebări** verificate manual:
animale, aplicații, cartoon, celebrități, instrumente, jocuri, logouri,
mașini, matematică, mecanică, medical, monumente, România, sport, steaguri.
Matematica e singura fără poze — arată o formulă scrisă mare.

**Economie:** monede (💰), gems (💎), vieți (❤️), hint-uri (💡). XP separat de
monede, XP → nivel. Toate câștigate din joc; magazinul cu bani reali **nu e
pornit încă** (prețurile sunt afișate dar plățile sunt oprite).

**Progresie:** nivel (XP) → ligi Bronze→Diamond cu sezoane lunare →
clasament global. Quest-uri zilnice (rotație dintr-un catalog de 88) și
realizări permanente.

**Bucle zilnice:** categoria zilei, Provocarea Zilei (5 întrebări fixe, la fel
pentru toată lumea), streak de login, Roata Norocului (1/zi), Clippy (bonus la
5 minute), Planeta hologramelor (2 rulări la 12h).

### Cele 6 moduri multiplayer

Toate sunt **FFA** (fiecare pe cont propriu), nu pe echipe. Cameră privată pe
cod, sau matchmaking public 1v1. Fără boți — doar oameni reali.

| Mod | Ce e |
|---|---|
| **Clasic** | fiecare răspunde în ritmul lui, cronometrat, cine strânge mai multe puncte |
| **Higher & Lower** | voturi secrete „mai mult / mai puțin", eliminare progresivă |
| **Quizz Tanks** | până la 10 tancuri, bare de viață; cine răspunde corect alege pe cine trage |
| **Obby** | cursă de obstacole 3D (Flame engine); răspuns corect = sari peste obstacol |
| **Scaunul Electric** | vieți individuale; cine răspunde corect alege cine merge pe scaun ȘI ce întrebare primește |
| **Piatră-Hârtie-Foarfecă** | alegere secretă, primul la 10 puncte |

Se pune miză în monede; premiile merg la jumătatea de sus a clasamentului.

### Stack tehnic

- **Flutter 3.47.2** / Dart. Android + Web (același cod).
- **Firebase:** Firestore (date live), 6 Cloud Functions (nodejs22,
  europe-west1) pentru notificări push și audit de balanță, Remote Config
  (comutatoare de la distanță), Crashlytics, Analytics.
- **App Check pe ENFORCE** — Firestore refuză orice cerere care nu vine din
  binarul autentic (Play Integrity pe Android, reCAPTCHA Enterprise pe web).
- **Fără server propriu.** Tot ce nu e Cloud Function e client-authoritative.
  Asta contează pentru secțiunea de securitate de mai jos.

---

## 2. Punctul de plecare: analiza de retenție

Acum ~30 de ore de lucru, feedback real de la testeri: **„e plictisitor la un
moment dat"**. Analiza (făcută împreună cu tine + Claude, cu acces la tot
codul) a dat un diagnostic clar:

> Problema NU e „nu sunt destule întrebări". E gameplay loop-ul:
> alegi un mod → 10 întrebări → câștigi → repeți. **Adăugarea de conținut nu
> repară asta.**

A ieșit o listă de 12 puncte, ordonate după cât mișcă retenția vs cât costă.
**Punctele 1-8 sunt acum toate livrate și testate.** Punctele 9-12 sunt
blocate deliberat (explicat mai jos).

---

## 3. Ce s-a livrat de atunci

**58 de commituri, 90 de fișiere, +7.190 / −989 linii, 15 fișiere noi în
`lib/`.** Totul pe `main`, pushat.

### RETENȚIE 1-8 (toate livrate)

**1. Cosmetice pe nivel.** Rame de avatar (5 ligi + 3 praguri de nivel) și
~14 titluri deblocate pe nivel/ligă/realizări. Titlurile sunt în stil
„challenges" din League of Legends — cerința ta: *„Boboc", „Google Ambulant",
„Creier de Cuantică", „Diferență de Nivel", „Toți Plătesc", „Fără Plasă de
Siguranță"*. Proprietatea NU se stochează, se recalculează din XP/ligă/
realizări (deci nu se poate falsifica prin editarea unui câmp). Picker cu 3
file (Avatar/Ramă/Titlu). Se văd în clasament, profil, listă de prieteni și
**în meci** — adversarul îți vede rama și titlul.

**2. Provocarea Zilei.** 5 întrebări FIXE pe zi, identice pentru toată lumea
(determinist, din hash pe dată — nu din Firestore, deci zero cost). O singură
rulare pe zi. Recompensă 40/corect + 150 bonus la 5/5. **Clasament global „de
azi"**, top 20 + locul tău.

**3. Prieteni online + jucători recenți.** Indicator „activ acum" (bulină
verde, sub 5 minute), prietenii activi sus în listă. Secțiune nouă „Jucători
recenți" — adversarii din ultimele meciuri, salvați local, cu buton Adaugă.
Zero citiri Firestore noi pentru ambele.

**4. Party persistentă.** Buton nou lângă REVANȘĂ: **„🎉 Rămâneți împreună
(alt mod)"**. Grupul nu se mai destramă după meci — camera nouă se oprește în
lobby, iar gazda schimbă modul dintr-un rând de pastile și dă START din nou.
Refolosește exact mecanismul de revanșă (aceiași participanți, acceptare de la
toți), cu un steag în plus. Zero colecții sau reguli noi.

**5. Ladder cu rating.** Rating Elo vizibil (start 1000, K=24). Fiindcă
modurile sunt FFA, delta se calculează **pe perechi**: pentru fiecare
adversar un mini-meci „am terminat peste el / sub el", scalat cu diferența de
rating, suma împărțită la numărul de adversari — ca un meci cu 5 jucători să
nu miște de 4 ori mai mult decât unul cu 2. Plafonat ±24/meci.
**Matchmaking-ul public se face acum pe rating**, nu pe ordinea sosirii.

**6. Recompense de sfârșit de sezon.** 100 monede (Bronze) → 2000 (Diamond),
o dată pe sezon. **Fără niciun job programat** — la pornirea aplicației se
observă că `seasonKey`-ul de pe profil e din luna trecută cu puncte > 0 și se
salvează local tier-ul atins ÎNAINTE ca primul meci din luna nouă să reseteze
totul. Dialog de revendicare pe ecranul Acasă.

**7. Evenimente limitate.** Se aprind dintr-o cheie Remote Config, **fără
build nou**: `{id, titlu, categorie, start, sfârșit, bonus}`. Când e activ:
card în Quest-uri + ecran propriu, bonus la monede pe categoria evenimentului,
clasament separat. Un motiv nou de revenit la fiecare 3-7 zile, controlat din
consolă.

**8. Emote-uri.** 6 reacții rapide în lobby ȘI **în meci**, în toate cele 6
moduri. Merg pe canalul de chat care exista deja (`matches/{id}/chat`) — zero
infrastructură nouă. Butonul stă sus-dreapta, reacțiile primite curg în jos și
se sting după 3 secunde.

### În plus, tot din lista de igienă

- **„Adversarul se reconectează…"** — bannerul care lipsea, în toate cele 6
  moduri. Zero scrieri noi: citește semnalul de viață pe care heartbeat-ul
  deja îl scria.
- **Profil public** — tap pe un jucător în clasament sau pe avatarul unui
  prieten → fișa lui (nivel, meciuri, winrate, cel mai bun streak, ramă,
  titlu, punctaj pe moduri, ultima dată online).

---

## 4. Bug-uri REALE găsite și reparate (partea care contează)

Am testat cu **2 și 4 jucători simultan** (contexte de browser separate =
conturi reale distincte, plus telefonul). Aici s-au văzut lucruri pe care un
singur jucător nu le poate găsi:

**a) Clasamentul Provocării Zilei era MEREU gol.** Scorurile erau în bază, dar
ecranul zicea „nimeni n-a terminat azi, ești primul!". Cauza: interogarea
sorta după două câmpuri, ceea ce cere un **index compus** în Firestore, care
nu exista. Interogarea pica, `catch`-ul returna listă goală, iar UI-ul nu
putea deosebi „n-a jucat nimeni" de „n-am putut citi". Reparat + index
deployat + acum eșecul se **vede** („Clasamentul nu s-a putut încărca"), nu
mai minte.

**b) Bannerul „Ai un meci în desfășurare — RECONECTEAZĂ-TE" apărea PESTE
meciul în care erai.** Verificarea rula la fiecare revenire în prim-plan, iar
în browser asta se declanșează la orice focus de fereastră.

**c) Butonul de emote acoperea a patra variantă de răspuns la Obby.** De-aia
a fost mutat sus-dreapta.

**d) 8 texte hardcodate în română** apăreau pe interfața engleză („MAI MULT"
lângă „MAI PUȚIN" care era tradus, „Clasament final", „ELIMINAT", „SCAUNUL
ELECTRIC", „Runda N", „Mod: …", „Ai pus X, ai luat Y", „Locul N").

**e) Scriptul de „reset total" nu reseta tot.** Îi lipseau 6 colecții
adăugate după ce fusese scris, plus un bug mai subtil: unele documente-părinte
sunt „fantomă" (n-au niciun câmp, există doar ca să țină o subcolecție), iar
API-ul nu le returna fără un flag special — deci scorurile rămâneau după orice
„reset complet".

### f) Trișatul prin abandon — găsit de user, cel mai important

Ai observat: **intri într-o activitate cu limită, răspunzi la câteva
întrebări, închizi aplicația din recente — și revii la un start curat.** Se
putea rerula până ieșea bine.

Același bug în **5 locuri**, aceeași cauză: starea se scria abia la finalul
*reușit*.

| Unde | Ce se putea fenta |
|---|---|
| Provocarea Zilei | rejucai toate cele 5 întrebări |
| Cultură Generală | reluai runda la nesfârșit |
| Planeta hologramelor | ieșeai și reintrai cu 2/2, inimile resetate |
| Quest „intră de 3 ori pe Planetă" | se bifa la **deschiderea ecranului** → deschis/închis de 3 ori în 10 secunde |
| Clippy | cooldown-ul de 5 min + plafonul zilnic nu însemnau nimic |

**Regula aplicată peste tot:** încercarea se consumă la **PRIMUL RĂSPUNS**.
Nu la deschiderea ecranului (intri din greșeală și ieși → nu pierzi nimic),
nu la final (abandonezi → nu o primești înapoi). Recompensa rămâne separată:
dacă abandonezi pierzi recompensa, nu încercarea.

Provocarea Zilei a primit în plus **reluare**: progresul se salvează după
fiecare răspuns și revii exact de unde ai rămas. Întrebările zilei sunt
deterministe, deci nu se poate „reroll-ui" un set prost ieșind din joc.

**Verificat pe telefon:** întrerupt la 3/5 → revenire → reluat exact de la
3/5. Planeta: „mai ai 2 rulări" → un singur răspuns + omorâtă aplicația →
„mai ai o rulare".

---

## 5. Cum se testează (fiindcă jocul are ~0 jucători acum)

Testerii au plecat, deci multiplayer-ul nu se poate testa „normal". Soluția:

- **2-4 contexte de browser separate** = 2-4 conturi anonime reale, plus
  telefonul pe adb wireless. Așa s-au găsit bug-urile de mai sus.
- **Simulare pentru ce nu se poate testa cu 2 conturi.** Matchmaking-ul pe
  rating dă același rezultat ca „primul venit" când sunt doar 2 în coadă. Deci
  am scos logica într-o funcție pură și am scris o simulare: **240 de jucători
  generați cu skill ascuns, 80 de runde**, perechile făcute DOAR prin codul
  real, ratingul mișcat DOAR prin codul real. Rezultat: concordanța
  rating↔skill **93,7%**, media ratingului rămâne exact 1000 (nu derivează),
  meciurile formate au un decalaj de rating de ~4 puncte față de >2× la
  pereche aleatoare. Zero cost — rulează local, nu atinge baza de date.

**Stare test/calitate:** 396 de teste automate (de la 375), `flutter analyze`
curat, 67/67 teste pe regulile Firestore (pe emulator local).

---

## 6. Unelte de operare (adăugate acum)

Userul nu e programator, deci tot ce trebuie apăsat manual a fost redus la 3
butoane într-un folder `comenzi/`, cu un fișier care explică ce face fiecare:

1. **RESET TOTAL** — golește tot Firebase, ca la lansare (cere „DA" scris de
   mână).
2. **Vezi rapoartele jucătorilor** — adună într-un fișier toate rapoartele din
   joc: blocaje/crash-uri, „întrebarea e greșită", jucător raportează jucător.
3. **Pune/scoate mesajul de mentenanță** — aprinde ecranul „Revenim imediat"
   peste joc pentru toți jucătorii, din Remote Config. Ecranul a primit și o
   animație (iconița se leagănă + bară de progres) ca să nu se citească drept
   „aplicația e stricată".

---

## 7. Ce urmează / ce e blocat și de ce

### Blocat pe MINE (decizii sau pași manuali)

1. **AAB nou pentru Play** — ultimul e dinaintea a tot ce s-a livrat.
   Se construiește în 5 minute, dar **întâi** trebuie formularul Data safety.
2. **Formularul Data safety** — se completează o singură dată, la final, cu
   toată lista în față (Crashlytics, Analytics, rapoartele de bug, Remote
   Config). Un build trimis fără actualizarea lui face declarația falsă.
3. **IAP / magazin cu bani reali** — momentul corect e **în testarea închisă,
   înainte de a cere accesul la producție** (testerii licențiați cumpără fără
   să fie taxați). Pasul ZERO e validarea bonului pe server, nu la final.
4. **Dificultate Easy/Medium/Hard pe întrebare** — decizie de conținut, nu de
   cod. Nu există azi niciun semnal din care s-o deduc.

### Blocat pe BAZA DE JUCĂTORI (RETENȚIE 9-12)

Moduri în echipă (2v2/3v3), turnee/bracket, clanuri, spectating. Toate cer
mulți jucători online simultan ca să aibă sens. Săptămâni de muncă pentru
funcții pe care nimeni nu le poate folosi acum.

### Datorie tehnică (fără grabă)

Lanțul de build Android va trebui urcat (Gradle 9, AGP 9, Kotlin 2.3) — de la
AGP 9 se citește doar formatul nou de configurare, deci e un șantier separat,
nu de făcut odată cu o lansare.

---

## 8. Slăbiciunea de securitate pe care o știm și o acceptăm (deocamdată)

Jocul e **local-first**: merge offline, iar salvarea (monede/gems/vieți) se
urcă întreagă în cloud când bagi aplicația în fundal. Consecința: documentul
cu balanța e **scriabil de proprietar**. Cineva hotărât își poate edita
monedele.

**Azi e DETECTAT, nu blocat.** O Cloud Function semnalează salturile
implauzibile, iar panoul de admin arată un avertisment pe jucătorul respectiv.

De ce nu blocăm: blocarea reală cere ca balanța să fie scrisă doar de Cloud
Functions = **rescrierea stratului de economie** (35 de locuri în 14 fișiere)
și ar omorî jocul offline. Cât monedele sunt pur virtuale, leacul e mai rău
decât boala. Devine justificat **când intră bani reali** — și atunci oricum
trebuie validarea bonului pe server, deci se face odată.

Același raționament pentru reparațiile anti-trișat de la punctul 4f: ele
opresc fenta pe care o poate face **oricine** (închide aplicația din recente),
nu un telefon rootat care editează direct fișierul de preferințe. Decizia
conștientă a userului: **se adaptează pe viitor**, acum se construiește.

---

## 9. Întrebările la care chiar vreau o părere

1. **Retenția.** Punctele 1-8 sunt livrate. Din experiența ta, ce lipsește
   încă din bucla de retenție a unui quiz mobil, la un joc care încă n-are
   bază de jucători? Ce ai pune ÎNAINTE de moduri în echipă / turnee?

2. **Problema oului și găinii.** Multiplayer-ul e cea mai bună parte a
   jocului, dar are nevoie de oameni online simultan. Fără boți (decizie
   asumată — nu vrem meciuri false). Cum se pornește un joc multiplayer de la
   zero jucători? Ferestre de joc programate? Notificări „X e online"? Altceva?

3. **Momentul monetizării.** Plan: IAP în testarea închisă, înainte de
   producție. E corect, sau ar trebui lansat public întâi și monetizat după?

4. **Ce ratăm complet.** Uită-te peste lista de mai sus și peste cod
   (https://github.com/rocketknife1/SodoQuizz) — ce sistem important lipsește
   dintr-un joc de tipul ăsta și nu apare nicăieri în raport?

5. **Anti-trișat.** Poziția noastră: oprim fenta accesibilă oricui, nu
   atacurile cu unelte, până când intră bani reali. E rezonabil pentru un joc
   cu monedă virtuală și clasament global, sau clasamentul global schimbă
   calculul?
