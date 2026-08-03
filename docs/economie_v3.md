# SodoQuizz — Reproiectarea economiei (v3)

Document de proiectare, scris ÎNAINTE de orice modificare de cod (vezi PAS 6 din
cerință). Toate valorile de mai jos sunt propuneri; nimic nu se implementează
până la confirmare.

Regulă transversală aplicată peste tot: **fără valori perfect rotunjite** —
evităm 5 / 10 / 50 / 100 și folosim numere care par calculate (7, 23, 37, 47,
89, 137, 173, 298, 521...).

---

## 0. Diagnostic — de ce e dezechilibrată economia actuală

Măsurat din cod și din `assets/continut/*/intrebari.json` (1.394 întrebări în 14
categorii; `puncte_max` = 200 la 66% dintre ele, 400 la 21%, restul 300-1000).

| Problemă | Măsurătoare |
|---|---|
| XP-ul e egal cu punctele întrebării | 140-200 XP / răspuns corect, iar nivelul 2 cere 310 XP → **nivel 5 în 16 răspunsuri corecte** |
| Cultură Generală e mult peste orice altceva | 30 corecte/zi × 20 monede + 3 × 30 bonus = **690 monede, 1.380 XP, 10 vieți pe zi**, fără risc |
| Clippy plătește SUB gameplay-ul normal | multiplicator `0,85×` (cerința: strict mai mult) |
| Roata (24h) e cel mai mic reward din joc | 25-70 monede / 1-2 hints / 3-5 gems |
| Quest-urile aproape nu dau gems | 5 quest-uri din 70 au gems (1-2 buc.) |
| Costul hint-ului e simbolic | scade doar din scorul de sesiune (nu din avere) — nu se simte niciodată |
| Prea puține vieți / prea multe monede la start | start: 5 vieți, 3 hints, 0 monede, 0 gems; dar 690 monede/zi doar din Cultură |
| Nu există sink care să crească cu averea | taxă categorie fixă 15, taxă cameră fixă 20 |

---

## 1. Jucătorul nou (PAS 2.5)

| Valoare | Acum | Nou | Motivație |
|---|---|---|---|
| Monede la instalare | 0 | **173** | să poată plăti taxa de intrare + câteva hint-uri în prima sesiune, fără să fie bogat |
| Gems la instalare | 0 | **47** | "din partea casei" — exact cât să deblocheze o categorie **la alegerea lui** (34) + rest pentru următoarea |
| Vieți la instalare | 5 | **7** | prea puține vieți la primul playthrough |
| Hint-uri la instalare | 3 | **9** | prea puține hint-uri |
| Plafon standard vieți (regen pasivă) | 5 | **6** | |
| Regenerare pasivă | 1 viață / 30 min | **1 viață / 23 min** | |
| Recompensă zilnică gratuită (vieți) | +5 | **+6** | |
| Plafon stoc hint-uri | 20 | **26** | hint-urile costă acum monede la folosire, pot fi stocate puțin mai mult |
| Categorii deblocate gratuit | 3 random (tier 1) | **3 random + 47 gems** | a 4-a categorie o alege jucătorul, nu zarul |

Pe ecranul de Categorii apare o dată un banner: *"Ai 47 💎 din partea casei —
deblochează categoria pe care o vrei."*

---

## 2. XP și progresie (PAS 2.4)

Cauza reală a "nivel 3-5 în câteva minute" nu e curba, ci faptul că **XP-ul e
egal cu punctele întrebării** (140-200 per răspuns). Se repară pe ambele părți.

### 2.1 XP per răspuns corect — decuplat de puncte

| | Acum | Nou |
|---|---|---|
| Formulă | `xp = puncte întrebare` (140-200) | `xp = round(4 + puncte_max × 0,033)` |
| Întrebare 200p | 140-200 XP | **11 XP** |
| Întrebare 400p | 280-400 XP | **17 XP** |
| Întrebare 700p | 490-700 XP | **27 XP** |
| Întrebare 1000p | 700-1000 XP | **37 XP** |

Punctele (scorul de sesiune, clasamentul, recordul) rămân neschimbate — doar
XP-ul nu mai e același număr.

### 2.2 Curba de nivel — progresivă, nu liniară

| | Acum | Nou |
|---|---|---|
| Formulă | `250 + 60·L²` | **`145 + 58·L² + 4·L³`** |

XP cumulat necesar ca să AJUNGI la nivel:

| Nivel | Acum | Nou | Nou, exprimat în răspunsuri corecte (200p) |
|---|---|---|---|
| 2 | 310 | **207** | ~19 |
| 3 | 800 | **616** | ~56 |
| 5 | 2.800 | **2.720** | ~247 |
| 10 | 19.350 | **25.935** | ~2.358 |
| 15 | 64.400 | **105.000** | ~9.545 |

Cifrele din ultima coloană sunt teoretice (numai din întrebări); în practică XP-ul
vine și din quest-uri, milestone-uri, roată, multiplayer. Estimare realistă:

| Moment | Nivel estimat |
|---|---|
| Prima sesiune completă (~45-60 min, 3 categorii starter + Cultură + Clippy + roată) | **nivel 3** |
| Prima zi de joc serios | nivel 4 |
| O săptămână de joc activ (~2.500 XP/zi) | nivel 8-9 |
| Nivel 15 ("Veteran") | ~6-7 săptămâni |

### 2.3 Migrare
Cheie nouă `xp_curve_migrated_v3`: XP-ul existent se împarte la 8,5 (raportul
dintre rata veche și cea nouă de XP), iar `lastClaimedRewardLevel` se pune pe
nivelul rezultat — nimeni nu vede zeci de reward-uri "necolectate" apărute din
neant, dar nici nu rămâne cu un nivel umflat de rata veche.

---

## 3. Costul hint-ului (PAS 2.1) — scalat cu averea

| | Acum | Nou |
|---|---|---|
| Cost | 1 hint din stoc **+** ~20% din punctele întrebării scăzute din scorul de sesiune | 1 hint din stoc **+ taxă în monede, procent din averea curentă** |
| Formulă | `clamp(reward × 0,2, 1, maxPoints × 0,4)` puncte | **`min(coins, clamp(round(coins × 0,037), 6, 89))`** monede |
| Penalizare pe scor | da (20%) | **eliminată** — costul devine economic, vizibil, nu ascuns în scor |

| Averea ta | Costă un hint |
|---|---|
| 0-162 monede | 6 |
| 500 | 19 |
| 1.000 | 37 |
| 2.405+ | 89 (plafon) |

Proprietăți cerute:
- **nu te lasă în pagubă**: minimul (6) e sub recompensa oricărei întrebări (12+),
  deci hint + răspuns corect e mereu profit net; iar dacă ai sub 6 monede,
  hint-ul costă exact cât ai (niciodată datorie, niciodată blocat);
- **nu doare**: la plafon reprezintă 3,7% din avere;
- **cost real**: 12 hint-uri într-o zi la 1.000 monede = 444 monede, adică ~15%
  dintr-o zi de joc activ.

---

## 4. Ierarhia surselor de reward (PAS 2.3)

Interpretare: Clippy e **mic în valoare absolută** (o rundă = 3 întrebări), dar
**strict mai bun pe întrebare** decât gameplay-ul normal — asta e regula pe care
o impunem matematic.

| Sursă | Unitate | Acum | Nou | Motivație |
|---|---|---|---|---|
| **Gameplay normal** | 1 răspuns corect (200p) | 17 monede, 175 XP | **12 monede, 11 XP** | baza; are risc de viață + taxă de intrare |
| **Clippy** (5 min) | per întrebare | 0,85× baza (14 monede) | **1,35× baza (16 monede)** | strict peste gameplay-ul normal, cum s-a cerut |
| **Clippy** | bonus de finalizare | 0 | **+23 monede** | o rundă completă (~40 s) să merite |
| **Clippy** | plafon zilnic | niciunul | **7 runde la rată plină, apoi 0,4×** | anti-farm la 12 runde/oră |
| **Cultură Generală** | per corect | 20 monede, 40 XP | **13 monede, 9 XP** | rămâne cea mai bună pe minut, dar mult sub nivelul actual |
| **Cultură Generală** | bonus lot | 30 monede, 60 XP | **23 monede, 31 XP** | |
| **Cultură Generală** | vieți | 1 la 3 corecte (nelimitat) | **1 la 4 corecte, max 5/zi** | 10 vieți/zi gratis era prea mult |
| **Cultură Generală** | plafon rată plină | 30 corecte/zi | **27 corecte/zi**, apoi 4 monede / 3 XP | |
| **Cultură Generală** | total pe zi | **690 monede, 1.380 XP, 10 vieți** | **~420 monede, ~310 XP, 5 vieți** | −39% monede, −78% XP |
| **Quest-uri** | gems | doar 5 din 70 dau gems | **fiecare quest dă gems: ușor 1, mediu 2, greu 4** | cerința PAS 2.3 |
| **Quest-uri** | plafon gems/zi | — | **37 gems/zi** din quest-uri | fără el, 30 de quest-uri revendicate = 60+ gems/zi |
| **Roata norocului** (24h) | 1 rotire | 25-70 monede / 1-2 hints / 3-5 gems | **valoare medie ~489 echivalent-monede** | cel mai mare reward din joc, pe măsura cooldown-ului |

### 4.1 Roata norocului — noile premii

| # | Premiu acum | Premiu nou | Greutate |
|---|---|---|---|
| 1 | 25 monede | **268 monede** | 18 |
| 2 | 30 XP | **431 XP** | 14 |
| 3 | 60 monede | **517 monede** | 13 |
| 4 | 1 hint | **7 hint-uri** | 11 |
| 5 | 1 viață | **4 vieți** | 11 |
| 6 | 3 gems | **39 gems** | 10 |
| 7 | 70 XP | **692 monede + 3 vieți** | 9 |
| 8 | 2 hint-uri | **84 gems** | 7 |
| 9 | 40 XP + 1 viață | **344 monede + 9 hint-uri + 4 vieți** | 6 |
| 10 | 5 gems + 40 monede | **1.284 monede + 53 gems** | 4 |
| 11 | JACKPOT vieți nelimitate 24h | **JACKPOT: vieți nelimitate 24h + 173 gems + 500 monede** | 2 |

Valoare medie per rotire: **247 monede + 14,6 gems + 0,9 vieți + 1,25 hints + 57 XP**
≈ 489 echivalent-monede. Chiar și cel mai slab segment (268 monede) bate orice
altă acțiune singulară din joc.

### 4.2 Ladder-ul final (valoarea absolută a unei "unități de activitate")

1. 1 răspuns corect normal — 12-33 monede
2. 1 rundă Clippy (3 întrebări, ~40 s) — **~71 monede** (dar 1,35× pe întrebare)
3. 1 zi de Cultură Generală — ~420 monede
4. 1 zi de quest-uri revendicate — ~660 monede + 37 gems
5. **1 rotire de roată — ~489 echivalent-monede dintr-un singur tap**

---

## 5. Restul recompenselor, recalibrate

| Sursă | Acum | Nou |
|---|---|---|
| Monede / răspuns corect | `puncte ÷ 10` (14-20) | **`round(3 + puncte_max × 0,043)`** → 12 (200p), 20 (400p), 33 (700p) |
| **Multiplicator de serie** (nou) | — | 3 corecte la rând **1,17×**; 5 → **1,34×**; 8 → **1,58×**; 12+ → **1,79×** (pe monede și XP) |
| Milestone la 10 întrebări/sesiune | 30·m monede, 80·m XP, +1 viață mereu | **23 + 19·m monede, 17 + 13·m XP**, +1 viață la fiecare al 2-lea milestone |
| Gems din milestone | de la m≥3: 3·(m−2) | **de la m≥3: (m−2)** |
| Reward de nivel | 60 + 25·L monede | **47 + 34·L monede** (nivelurile sunt acum mult mai rare) |
| Hints la nivel | 2, la fiecare 3 niveluri | **3, la fiecare 3 niveluri** |
| Vieți la nivel | 1, la fiecare 4 niveluri | **2, la fiecare 4 niveluri** |
| Gems la nivel | 10 la fiecare 10 niveluri (+25 la 25) | **7 la fiecare 5 niveluri (+23 la multipli de 25)** |
| Streak zilnic (3/7/14/30/60/100 zile) | 5·m monede, 10·m XP | **27·m monede, 8·m XP, (m÷7)+1 gems** |
| Reclamă recompensată (Game Over, 4/zi) | 2 hints + 1 viață | **3 hints + 2 vieți + 43 monede** |
| Quiz Nelimitat (fără risc) | 0,6× baza, 0,2× peste 40 corecte/zi | **0,58× baza, 0,19× peste 43 corecte/zi** |
| **Higher or Lower solo** | **0 monede, 0 XP** (doar record) | **per pas corect: `3 + streak×0,7` monede (max 29), `2 + streak×0,4` XP (max 17)** — o serie de 20 ≈ 207 monede |
| Achievements — monede | 150-800 | **×1,4** (211-1.123) |
| Achievements — XP | 300-1.600 | **÷3,4** (88-471) — XP-ul valorează acum de ~15× mai mult |

### 5.1 Quest-uri — recompense pe nivel de dificultate

| Nivel | Monede acum | Monede nou | XP acum | XP nou | Gems acum | Gems nou |
|---|---|---|---|---|---|---|
| Ușor (28 quest-uri) | 10-20 | **9-17** | 12-28 | **7-13** | 0 (excepție 1) | **1** |
| Mediu (27) | 22-35 | **21-34** | 25-45 | **16-27** | 0 (excepție 2) | **2** |
| Greu (16) | 40-80 | **41-67** | 55-90 | **33-54** | 0 (excepție 2) | **4** |

Plafon: **37 gems/zi** din quest-uri (peste plafon, quest-ul plătește monede/XP/
hints, dar 0 gems). Hint-urile din quest-uri rămân ca acum.

> **Actualizat în v3.1 (2026-08-03)** — vezi secțiunea 13. Valorile din tabelul
> de mai sus rămân cele din CATALOG (`lib/core/progression.dart`), dar monedele/
> XP-ul/hints-urile/viețile sunt multiplicate la acordare, iar gems-ul per tier a
> SCĂZUT la 0/1/2 (ținta: o categorie nouă pe săptămână, nu pe zi).

---

## 6. Sink-uri care scalează cu venitul (PAS 2.6)

| Sink | Acum | Nou |
|---|---|---|
| **Taxă intrare categorie** | fix 15 monede | **`clamp(round(coins × 0,021), 13, 174)`** — bogatul plătește 174, săracul 13 |
| **Recompensă la ieșire** | <4 corecte: 50% taxă; 4-7: 100%; 8+: 150% | **<4: 0%; 4-7: 60%; 8-14: 100%; 15+: 130%** |
| **Taxă hint** | — | **3,7% din avere, 6-89** (secțiunea 3) |
| **Vieți cu monede** (max 5/zi) | 150 / 250 / 400 / 650 / 1.000 = **2.450** | **89 / 167 / 312 / 578 / 1.043 = 2.189** |
| **Pachete de hints** (max 3/zi) | 5 hints = 180; 15 hints = 450 (preț fix) | **4 hints = 137; 13 hints = 389**, cu multiplicator pe achiziția zilei: ×1 / ×1,35 / ×1,79 |
| **Deblocare tier categorie (gems)** | 40 / 90 / 180 / 320 / 550 = 1.180 | **34 / 79 / 167 / 298 / 521 = 1.099** |
| **Umplere instant vieți (gems)** | 40 | **31** |
| **Taxă multiplayer** | 20 (doar camere cu chat), Join Online gratuit | **37, uniform pentru toate intrările** (secțiunea 8) |
| **Rake pariuri multiplayer** | — | **3,5% din pool** |

### 6.1 Verificare anti-inflație

Jucător "safe" (doar roata, 4 runde Clippy, revendicare vieți, câteva quest-uri
care se completează singure):

| Sursă | Monede/zi |
|---|---|
| Roata | ~247 (+14 gems, vieți, hints) |
| Clippy ×4 | ~310 |
| Quest-uri incidentale | ~60 (+3 gems) |
| **Total** | **~620 monede/zi fără să cheltuiască nimic** |

Jucător activ:

| Sursă | Monede/zi |
|---|---|
| Gameplay (60 corecte, cu taxe și reward la ieșire) | +1.020 |
| Hint-uri folosite (12) | −444 |
| Cultură Generală | +420 |
| Clippy ×7 | +500 |
| Roata | +247 |
| Quest-uri (~30 revendicate) | +660 |
| Milestone-uri de sesiune | +240 |
| Multiplayer (5 meciuri) | −100 … +300 |
| **Brut** | **~2.900/zi** |
| Cheltuială maximă posibilă (5 vieți + 3 pachete hints) | **−2.756 … −3.799** |

Adică: **un jucător hard care cumpără tot ce poate ajunge aproape de zero net pe
zi**; unul mediu strânge 1.000-1.500/zi → 7-10k într-o săptămână. Nici sărac,
nici milionar. ✓

---

## 7. Shop în RON (PAS 3)

### 7.1 Ofertele cumpărabile de mai multe ori pe zi (monede, nu bani reali)

Cerința: suma totală pentru toate achizițiile într-o zi să fie realistă de atins
**într-o zi de farm cu pauze**, nu în 10 minute.

| Ofertă | Preț per achiziție | Total dacă le cumperi pe toate |
|---|---|---|
| Viață bonus (5/zi) | 89 → 167 → 312 → 578 → 1.043 | **2.189 monede** |
| Pachet 4 hints (3/zi) | 137 → 185 → 245 | **567 monede** |
| Pachet 13 hints (3/zi) | 389 → 525 → 696 | **1.610 monede** |
| **Ambele oferte epuizate (varianta ieftină de hints)** | | **2.756 monede** |
| **Ambele oferte epuizate (varianta scumpă de hints)** | | **3.799 monede** |

Raportat la venitul brut de ~2.900/zi al unui jucător activ: cine are bani de 3
vieți dimineața, face pauză, se mai joacă și farmează, ajunge la 5 + 3 până
seara — exact scenariul cerut. Imposibil în 10 minute.

### 7.2 Prețuri cu bani reali — conversie în RON

Curs folosit: ~4,7 lei/USD, aliniat la pragurile reale de preț din Google Play
România, dar cu cifre "calculate", nu rotunde.

| Produs | Acum | Nou (RON) | Conținut nou |
|---|---|---|---|
| Gems mic | $0,99 / 100 gems | **4,79 lei** | 118 gems |
| Gems mediu | $4,99 / 550 | **23,49 lei** | 634 gems (+10%) |
| Gems mare | $9,99 / 1.200 | **46,99 lei** | 1.372 gems (+20%) |
| Gems XL | $19,99 / 2.600 | **93,99 lei** | 2.918 gems (+30%) |
| Gems XXL | $49,99 / 7.000 | **233,99 lei** | 7.640 gems (+40%) |
| Vieți mic | $0,99 / 5 | **4,79 lei** | 7 vieți |
| Vieți mare | $2,49 / 15 | **11,79 lei** | 19 vieți |
| Vieți nelimitate 24h | $1,99 | **9,29 lei** | — |
| Hints mic | $0,99 / 20 | **4,79 lei** | 23 hints |
| Hints mediu | $2,49 / 60 | **11,79 lei** | 68 hints |
| Hints mare | $4,99 / 150 | **23,49 lei** | 172 hints |
| Pachet de Start (o dată) | $4,99 | **23,49 lei** | 434 gems, 3.170 monede, 17 vieți, 43 hints |
| Pachet Aventurier | $2,99 | **13,99 lei** | 167 gems, 1.283 monede, 6 vieți, 17 hints |
| Pachet Campion | $9,99 | **46,99 lei** | 534 gems, 4.270 monede, 17 vieți, 53 hints |
| Pachet Legendar | $24,99 | **117,99 lei** | 1.634 gems, 12.840 monede, 43 vieți, 158 hints |
| Fără reclame pe veci | $9,99 | **46,99 lei** | 214 gems, 2.130 monede, 17 vieți, 43 hints |

> ⚠️ **Blocant de publicare, de decis separat:** fluxul de cumpărare cu bani
> reali e **simulat** (nu există pachetul `in_app_purchase`, nu există produse în
> Play Console). Prețurile în RON pot intra în cod acum, dar secțiunea cu bani
> reali **nu trebuie să ajungă activă într-un build trimis la Google Play** —
> ambele magazine resping/sancționează plăți care nu trec prin billing-ul lor.
> Propunerea mea: prețurile în RON intră în cod, iar secțiunea Premium primește
> un state „În curând" în build-ul de release, până integrăm Google Play Billing.

---

## 8. Multiplayer — sistem de pariuri (PAS 4)

### 8.1 Intrarea în meci

| | Acum | Nou |
|---|---|---|
| Taxă fixă | 20 monede (doar camere cu chat), Join Online gratuit | **37 monede, uniform la orice intrare în meci** |
| Pariu | — | **procent ales de jucător, 5%–85% din monedele rămase după taxă** |
| Pariu minim absolut | — | **23 monede** (deci ai nevoie de min. 60 de monede ca să intri) |
| Retur | integral dacă meciul nu începe | idem — taxa ȘI pariul se întorc integral dacă meciul nu pornește |

Taxa fixă de 37 **iese din economie** (sink anti-inflație). Pariurile formează
pool-ul.

### 8.2 Plafonul mesei (anti-exploatare, partea 1)

La START se calculează **`plafon = mediana pariurilor × 7,3`**. Orice pariu peste
plafon e **retezat, iar surplusul se întoarce instant** în portofel (cu mesaj:
"Masa ți-a limitat pariul la X").

De ce: fără el, un jucător cu 50.000 de monede ar putea sufoca o masă de
începători pariind 30.000 și ar recupera sistematic majoritatea pool-ului doar
pentru că a pus cei mai mulți bani. Cu el, **mărimea mesei decide cât se poate
juca la masa aia**, exact ca la table stakes în poker.

### 8.3 Împărțirea pool-ului

```
Pool     = Σ pariuri_efective
PoolNet  = Pool × 0,965          (3,5% rake — sink anti-inflație)

PoolNet se împarte în două:
  Pot de miză  = 80% din PoolNet   → împărțit după w_i
  Pot de loc   = 20% din PoolNet   → împărțit DOAR după clasament

w_i      = pariu_efectiv_i × perf_i × risc_i
perf_i   = 0,34 + 0,66 × (scor_i / scor_maxim)         [Clasic]
         = 0,34 + 0,66 × ((N − loc_i) / (N − 1))       [Higher or Lower]
risc_i   = 0,74 + 0,52 × procentul_ales                (0,766 la 5% … 1,182 la 85%)

Pot de miză pentru i = PotMiză × w_i / Σ w_j
Pot de loc: ladder [0,41 / 0,24 / 0,15 / 0,09 / 0,06 / 0,03 / 0,02],
            trunchiat la N jucători și normalizat la 1
```

Cele trei pârghii cerute sunt toate în formulă:
- **(a) performanța** → `perf_i` (scorul / cât de departe ai ajuns)
- **(b) riscul asumat** → `risc_i`, până la +54% pentru cine pariază 85%
- **(c) numărul de jucători și mărimea pool-ului** → pool-ul crește liniar cu N,
  iar potul de loc concentrează 41% din el pe locul 1

### 8.4 Simulări

**Masă echilibrată, 7 jucători, toți pariază 300 (30%):**

| Loc | Primește | Randament |
|---|---|---|
| 1 | 512 | **1,71×** |
| 4 | 288 | 0,96× |
| 7 | 126 | 0,42× |

**1 vs 1, ambii pariază 300:** câștigătorul 418 (1,39×), pierzătorul 161 (0,54×).
→ Cu cât masa e mai mare, cu atât potențialul crește. ✓

**Scenariul descris de tine — 7 jucători, un bogat pariază 60% (6.000), un mic
pariază 10% (40), restul 300; bogatul pierde, micul rămâne ultimul la masă:**

| Jucător | Pariu | Efectiv (după plafon) | Loc | Primește | Rezultat |
|---|---|---|---|---|---|
| Bogatul | 6.000 | **2.190** (3.810 returnați instant) | 7 | 1.329 | **−861** |
| Micul | 40 | 40 | 1 | **348** | **+308 (8,7×)** |
| Mijlocași (×5) | 300 | 300 | 2-6 | 305-517 | +5 … +217 |

Exact senzația cerută: **banii pierduți de cel mare se simt clar în buzunarul
celui mic care a rezistat până la final.**

**Anti-exploatare, verificat:** același bogat, dacă termină pe locul 1, primește
2.359 din 2.190 mizați — adică **+7,7%**. Asimetria (+169 la victorie vs −861 la
înfrângere) e intenționată: **a paria enorm la o masă mică e matematic o idee
proastă**, deci jucătorii mari nu pot fura sistematic banii celor mici. Dacă vor
randament bun, fie pariază un procent apropiat de nivelul mesei, fie caută mese
cu mize pe măsura lor.

**Abandon:** cine iese din meci după START e tratat ca ultimul clasat
(`perf = 0,34`, ultima poziție în potul de loc) — altfel s-ar putea evita
pierderea prin rage-quit. Dacă rămâne un singur jucător, tot pool-ul se întoarce.

> Notă de arhitectură: pariul se scrie în documentul jucătorului din Firestore
> (`bet`, `betPercent`), iar fiecare client calculează plata din aceleași date și
> își creditează doar propriul cont — la fel ca scorul azi. Nu e autoritate de
> server (deci teoretic falsificabil de un client modificat), exact ca restul
> multiplayer-ului actual. `firestore.rules` trebuie extins cu cele două câmpuri.

---

## 9. Balonul de BETA pe Home (PAS 5)

Un balon de vorbă plutitor, **între mascota Discord (stânga) și Clippy
(dreapta)**, animat discret (pulsează + se leagănă), cu text scurt de tip
"Jocul e în BETA — apasă aici". La tap se deschide un dialog scrollabil cu:

1. **Beta** — jocul e încă în teste; nu toate pozele sunt încărcate/editate;
   e dezvoltat de o singură persoană, deci update-urile vin mai greu.
2. **Multiplayer** — noua logică: taxă 37 + pariu 5-85%, plafonul mesei, potul de
   miză + potul de loc, de ce jucătorii mari nu pot domina sistematic.
3. **Modul Clasic** — cum se joacă și **pe ce apeși**: alegi una din cele 4
   variante de sub poză; poza se limpezește cu fiecare hint; răspuns greșit =
   −1 viață; la 10 întrebări primești bonus.
4. **Higher or Lower** — compari campionul cu provocatorul și apeși **MAI MULT**
   sau **MAI PUȚIN**; în multiplayer toți votează în secret, greșit = o pâine 🍞,
   3 pâini = eliminat, ultimul rămas câștigă.
5. **De unde începi** — PLAY → alegi categoria → plătești taxa → joci;
   MULTIPLAYER → Create Room / Join Online / Join with Code.

În plus, `MultiplayerInfoDialog` (ℹ️ din ecranul Multiplayer) se rescrie complet
cu noua logică de pariuri — acum descrie formula veche.

---

## 10. Alte reparații incluse

| Ce | De ce |
|---|---|
| Butonul dev **UNLIMITED** nu mai setează XP la 100.000 | cerut explicit — nu mai sare automat la nivelul 17. Consecință: realizările `level_5`/`level_15` rămân necompletate când folosești butonul (nu mai pot fi testate din el) |
| Higher or Lower solo primește economie | acum e singurul gamemod care nu dă nici monede, nici XP |
| `unlockedGameModeCount` (14) rămâne sincronizat manual | neschimbat, doar verificat |

---

## 11. Fișiere atinse la implementare

| Fișier | Ce se schimbă |
|---|---|
| `lib/core/progression.dart` | curbă XP, level rewards, milestone, taxe, quest-uri, achievements, constante multiplayer |
| `lib/core/game_helpers.dart` | XP/monede per răspuns, multiplicator de serie, cost hint, rate Cultură/Nelimitat |
| `lib/core/betting.dart` *(nou)* | formula de pariuri multiplayer, plafon masă, împărțire pool |
| `lib/data/shop.dart` | prețuri RON, prețuri vieți/hints progresive, tier-uri gems |
| `lib/data/storage_service.dart` | valori de start, regen, plafoane zilnice noi, plafon gems quest, buy* cu prețuri progresive, migrare XP v3, dev button |
| `lib/screens/game_screen.dart` | cost hint în monede, multiplicator de serie, milestone |
| `lib/screens/clippy_bonus_screen.dart` | multiplicator 1,35×, bonus de finalizare, plafon zilnic |
| `lib/widgets/culture_quiz_panel.dart` | recompense reduse |
| `lib/screens/higher_lower_screen.dart` | economie nouă |
| `lib/screens/unlimited_quiz_screen.dart` | rate noi |
| `lib/widgets/wheel_spin_dialog.dart` | premii noi |
| `lib/screens/categories_screen.dart` | taxă scalată, banner "47 gems din partea casei" |
| `lib/screens/multiplayer/*` | ecran de alegere a pariului, plată la START, calcul plăți la rezultate |
| `lib/widgets/multiplayer_entry_fee_dialog.dart` | devine dialog de pariu (slider 5-85%) |
| `lib/widgets/multiplayer_info_dialog.dart` | text rescris |
| `lib/widgets/beta_info_balloon.dart` *(nou)* | balonul de pe Home + dialogul |
| `lib/screens/home_screen.dart` | montarea balonului |
| `lib/models/multiplayer_models.dart`, `lib/data/multiplayer_service.dart` | câmpurile `bet` / `betPercent` |
| `firestore.rules` | permiterea noilor câmpuri |
| `lib/screens/shop_screen.dart` | afișare RON, prețuri progresive |

## 12. După implementare (cerut explicit)

Build + instalare pe telefon cu verificare pe capturi de ecran, apoi actualizare
GitHub, GitHub Pages (pagina web), Firebase, AdMob, Play Console — vezi
`LINKS.md` pentru destinațiile reale.

---

## 13. v3.1 — rotație de quest-uri, plafon Clippy, magazin premium ascuns (2026-08-03)

Ajustări cerute pentru lansarea publică, peste economia v3 de mai sus.

### 13.1 Quest-uri: ~10 pe zi, în rotație săptămânală

Înainte: toate cele 71 de quest-uri erau active în fiecare zi — o listă
copleșitoare, în care nimeni nu le termina oricum pe toate.

Acum catalogul e împărțit o singură dată în **7 grupe disjuncte** (partiție cu
sămânță fixă, `_questRotationSeed`), iar ziua săptămânii alege grupa. Deci:

- **9-11 quest-uri pe zi** (media 10,1 — cele 71 nu se împart perfect la 7);
- niciun quest nu se repetă în cadrul aceleiași săptămâni;
- **lunea revine exact setul de luni**, cum s-a cerut;
- fiecare zi primește din toate cele trei dificultăți (împărțirea se face
  separat pe tier, cu decalaje de pornire 0/3/5, ca resturile să nu cadă mereu
  în aceleași zile);
- variantele aceleiași familii (`answer_3`/`answer_5`/`answer_10`, care împart
  un singur contor de progres) pică pe zile consecutive, deci nu se aglomerează
  în aceeași zi în cadrul unui tier.

Recompensele sunt multiplicate, fiindcă numărul de quest-uri revendicabile a
scăzut de ~3× față de ce termina realist un jucător activ:

| Resursă | Multiplicator | De ce |
|---|---|---|
| Monede | **×3** | păstrează venitul zilnic din quest-uri la nivelul din v3 |
| XP | **×3** | idem |
| Hints | **×1,5** | stocul e oricum plafonat la 26 — mai mult s-ar irosi |
| Vieți | **×2** | resursa care decide cât poți juca, cea mai sensibilă la inflație |
| Gems | 1/2/4 → **0/1/2** per tier | scad, nu cresc — vezi mai jos |

Multiplicatorii se aplică într-un singur loc (getterii din `Quest`), nu prin
rescrierea celor 71 de intrări din catalog.

**Gems: ținta e o categorie pe SĂPTĂMÂNĂ, nu pe zi.** v3 făcea fiecare quest să
dea gems (1/2/4) cu un plafon de 37/zi — adică o categorie nouă (34 gems, vezi
`questionUnlockGemsPrice(1)`) la fiecare zi de joc, mult prea repede. Acum:

| Tier | Gems |
|---|---|
| Ușor | **0** |
| Mediu | **1** |
| Greu | **2** |

Pe o săptămână întreagă (27 medii + 16 grele, tot catalogul) maximul teoretic e
**59 gems**, dar nimeni nu termină chiar toate quest-urile grele (20 de răspunsuri
corecte, serie de 10, 5 gamemoduri, 500 de monede...). Un jucător realist adună
**30-40 gems pe săptămână** — adică exact pragul unei categorii noi, cu puțină
străduință și puțin noroc, cum s-a cerut.

**Plafon gems: 37 → 13/zi.** Cea mai bogată zi din rotație dă 10 gems revendicată
integral, deci plafonul nu retează niciodată un jucător cinstit — există strict ca
"Revendică x2" (care dublează și gems-ul) să nu poată comprima o săptămână de gems
într-o singură zi.

Verificat pe cele 7 zile: **681-876 monede**, **567-780 XP**, **7-10 gems**,
**22-29 hints** pe zi la revendicare completă (v3 estima ~660 monede pentru ~30
de quest-uri revendicate). Invariantele sunt prinse în
`test/quest_rotation_test.dart` și în `test/game_logic_test.dart`.

### 13.2 Clippy: plafon dur de 5 runde pe zi

Înainte: cooldown de 5 minute, fără plafon dur — doar o rată redusă (0,4×)
după 7 runde. Teoretic 12 runde/oră.

Acum: **5 runde pe zi calendaristică**, tot cu 5 minute de cooldown între ele.
Contorul se vede permanent sub mascotă, ca pastilă **"N/5"**: pornește la 5/5,
scade la 4/5 după fiecare rundă terminată, iar la 0/5 eticheta arată "MÂINE" în
loc de numărătoarea inversă și Clippy nu mai poate fi deschis până după 00:00
(contoarele zilnice sunt scoped pe dată). Ecranul de final al bonusului spune
și el explicit câte runde au mai rămas.

Fiindcă plafonul dur (5) e sub pragul de rată plină (acum tot 5), **toate**
rundele zilei plătesc integral; `clippyReducedMultiplier` rămâne doar plasă de
siguranță. Venit maxim de la Clippy: ~5×71 = **~355 monede/zi** (față de ~500
la 7 runde în v3).

Roata norocului rămâne neschimbată: o învârtire la 24h.

### 13.3 Magazinul premium — ascuns până la lansare

Tot ce se plătește cu bani reali (de la "Fără reclame pe veci" în jos: pachete,
gems, vieți & hints) e afișat **blurat**, complet inert, sub un strat "În
curând". Motivul e comercial: până la deschiderea magazinului nu vrem ca
ofertele și prețurile să fie vizibile în capturile de ecran din Google Play.

Secțiunile plătite în monede (Vieți, Hints) rămân neatinse — fac parte din joc,
nu din magazinul cu bani reali.

Reveal-ul e o singură linie: `premiumShopRevealed = true` în `lib/data/shop.dart`.
Comutatorul e separat de `realMoneyStoreEnabled` (ăla deblochează plățile
efective, ăsta doar vizibilitatea).

### 13.4 Home pe 0 vieți — Cultura Generală nu mai intră peste mascote

Cardul roșu cu numărătoarea de reîncărcare (`LivesCountdownCard`, ~62px) împingea
tot conținutul în jos, iar panoul de Cultură Generală ajungea exact peste Clippy
și balonul de BETA (ambele plutesc fix, în Stack-ul de deasupra) — variantele de
răspuns erau acoperite.

Cât timp cardul e pe ecran, logo-ul "GUESS IT!" (92px, pur decorativ) se ascunde.
Net, conținutul urcă ~30px față de normal: Cultura Generală stă imediat sub
"fereastra" de vieți și rămâne complet liberă de mascote.

### 13.5 Fișiere atinse în v3.1

| Fișier | Ce s-a schimbat |
|---|---|
| `lib/core/progression.dart` | rotația săptămânală, multiplicatorii de recompensă, gems 0/1/2, plafon 13 |
| `lib/core/game_helpers.dart` | `clippyDailyPlayLimit` |
| `lib/data/storage_service.dart` | `clippyPlaysLeftToday`, plafonul în `isClippyReady`, `clippyNextDayRemaining` |
| `lib/widgets/mascots/paperclip_mascot.dart` | pastila "N/5", starea "MÂINE" |
| `lib/screens/clippy_bonus_screen.dart` | runde rămase pe ecranul de final |
| `lib/screens/quests_screen.dart` | textul explicativ al rotației |
| `lib/data/shop.dart` | `premiumShopRevealed` |
| `lib/screens/shop_screen.dart` | `_PremiumVeil` (blur + "În curând") |
| `lib/screens/home_screen.dart` | logo ascuns pe 0 vieți |
| `test/quest_rotation_test.dart` *(nou)* | invariantele rotației |
