# Listare Google Play — texte gata de copiat

Toate respectă limitele de caractere impuse de Play Console. Numărul din
paranteză e lungimea reală, ca să știi cât loc mai ai dacă vrei să modifici.

---

## Numele aplicației (max 30)

```
SodoQuizz: Ghicește imaginea
```
*(28 din 30)*

Alternative, dacă vrei alt accent:

| Variantă | Lungime |
|---|---|
| `SodoQuizz — Ghicești ce e?` | 26 |
| `SodoQuizz: Quiz cu poze` | 23 |
| `SodoQuizz` | 9 |

Recomand prima: conține și numele, și cuvântul „ghicește", pe care oamenii îl
caută efectiv în magazin.

---

## Descriere scurtă (max 80)

```
Ghicește ce se ascunde în poza neclară. 14 categorii și multiplayer live.
```
*(73 din 80)*

Asta e textul care apare sub titlu în rezultatele căutării — e cel mai citit
text din toată listarea.

---

## Descriere completă (max 4000)

```
Vezi o poză neclară. Ai patru variante. Cât de repede îți dai seama ce e?

SodoQuizz e un joc de ghicit imagini, în română, cu 1.394 de întrebări
împărțite în 14 categorii: logo-uri de firme, desene animate și filme, jocuri
video, mașini de lux, celebrități, sport, monumente, animale, steaguri,
instrumente muzicale, obiecte medicale, scule auto, aplicații de telefon și
România.

CUM SE JOACĂ
Alegi o categorie și primești o poză acoperită de blur. Sub ea sunt patru
variante — apeși pe cea care crezi că e răspunsul. Dacă nu-ți dai seama,
butonul de hint limpezește poza: al doilea hint elimină două variante
greșite, al treilea îți arată cât de sigură e o variantă. Fiecare hint costă,
însă, așa că merită gândit.

HIGHER OR LOWER
Un mod complet diferit: două lucruri față în față, unul cu popularitatea la
vedere, altul ascunsă. Ghicești dacă al doilea e căutat mai mult sau mai
puțin. O singură greșeală și seria se termină — dar cu cât ajungi mai
departe, cu atât fiecare pas plătește mai bine.

MULTIPLAYER CU PARIURI
Joci live cu prieteni sau cu adversari găsiți automat. Intri cu o taxă fixă
plus un pariu ales de tine, între 5% și 85% din câte monede ai. Toate
pariurile de la masă formează un pool care se împarte la final după cât ai
pariat, cât de bine ai jucat și cât risc ți-ai asumat — dar o parte se împarte
strict după clasament, indiferent de mărimea pariului. Concret: dacă cineva
mizează mult și pierde, banii lui ajung la cei care au rezistat până la final,
oricât de puțin ar fi pus ei.

CE MAI E ÎN JOC
• Roata norocului — un premiu mare o dată la 24 de ore
• Clippy — un bonus rapid de trei întrebări, fără risc, la fiecare 5 minute
• Cultură Generală — runde de întrebări cu răspuns la timp
• Quiz nelimitat, pentru când vrei doar să joci fără presiune
• Peste 70 de quest-uri zilnice și realizări permanente
• Clasament global, ligi și listă de prieteni
• Salvare în cloud cu contul Google, ca progresul să te urmeze pe orice telefon

JOCUL E ÎN BETA
Îl dezvolt singur, în timpul liber. Unele poze sunt încă provizorii sau
lipsesc, iar update-urile vin mai greu decât mi-aș dori. Dacă găsești ceva
stricat sau ai o idee, există un link către serverul de Discord chiar în joc —
citesc tot.

Jocul e gratuit. Conține reclame opționale: nu apar niciodată forțat, doar
dacă alegi tu să te uiți la una în schimbul unei recompense.
```
*(≈2.180 din 4.000)*

---

## Grafica (deja generată în `play_store/grafica/`)

| Fișier | Dimensiune | Format | Cerința Google |
|---|---|---|---|
| `icon-512.png` | 512×512 | PNG 32-bit cu alfa | ✔ |
| `feature-graphic-1024x500.png` | 1024×500 | PNG 24-bit fără alfa | ✔ |

## Capturi de ecran (în `play_store/capturi/`)

Opt bucăți, toate 1080×1920 (raport 9:16 exact), PNG 24-bit fără alfa.
Google cere minimum 2; ordinea de mai jos e cea recomandată, primele trei
sunt cele care se văd fără să dea nimeni scroll.

1. `1-acasa.png` — Tot jocul, într-un ecran
2. `3-intrebare.png` — Ce se ascunde în poză?
3. `4-raspuns.png` — Ai ghicit? Iei monede și XP
4. `2-categorii.png` — 14 categorii de ghicit
5. `6-higher-lower.png` — Mai mult sau mai puțin?
6. `7-multiplayer.png` — Joacă live cu prietenii
7. `8-pariu.png` — Pariază cât ai curaj
8. `5-questuri.png` — Quest-uri noi în fiecare zi

(`_contact_sheet.png` e doar pentru previzualizare rapidă, nu se încarcă.)
