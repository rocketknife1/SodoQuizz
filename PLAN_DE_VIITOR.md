# Plan de viitor — de ce devine plictisitor la 13-20 ani

Document de discuție, nu de implementare. Sinteză din două analize (Claude +
GPT, 2026-08-20) pornind de la feedback real: mai mulți jucători de 13-20 ani
au zis că jocul devine plictisitor. Nimic din acest fișier nu e construit —
e punctul de plecare pentru următoarea sesiune de lucru, când decidem ce
atacăm primul.

## Ce avem deja (nu pornim de la zero)

Conținutul nu lipsește: 1394 de întrebări, 14 categorii, hint-uri, XP/nivel,
quest-uri zilnice, achievements, vieți/monede, highscore, multiplayer cu
camere/matchmaking/rezultate, plus moduri distincte — Higher/Lower, Culture
Quiz, Quizz Tanks, Astro Sodo, Obby. Deci problema nu e "prea puțin conținut".

Există și un schelet de **sistem de ligă** ([lib/core/leagues.dart](lib/core/leagues.dart)):
5 trepte (Bronze/Silver/Gold/Platinum/Diamond), +20 puncte la victorie,
-8 la înfrângere, cumulativ pe viață, **fără sezoane și fără reset**. E motivul
concret pentru care "toți suntem Bronze" — nu e neapărat prag greșit (5
victorii ajung la Silver), ci puțin volum real de meciuri multiplayer termi-
nate normal + sistemul e v1, gândit să fie extins, nu varianta finală.

## Ce spun ambele analize, la un loc

Claude și GPT au ajuns independent la aceleași teme, din unghiuri diferite —
asta le face de încredere:

1. **Bucla de bază e prea previzibilă.** Întrebare → răspuns corect = înainte,
   greșit = stai pe loc. După câteva runde, creierul prinde tiparul și nu mai
   are ce să-l surprindă (asta rămâne valabil chiar și în Obby/Astro Sodo/Tanks,
   care aduc mișcare, dar nu variație de decizie).
2. **Recompensa e prea îndepărtată.** XP și progres pe termen lung sunt utile,
   dar la 13-20 ani miza imediată — "ce câștig ACUM, în runda asta" — motivează
   mult mai tare.
3. **Rivalitatea e episodică, nu persistentă.** Un meci se termină și rezultatul
   dispare. Nu există "cineva mă depășește", "sunt aproape să-l ajung", ceva
   de urmărit între sesiuni. Ăsta e punctul pe care GPT îl marchează explicit
   ca "cel mai mare potențial" — și e exact locul unde sistemul de ligă
   existent (dar neexploatat) s-ar activa natural.
4. **Lipsă de identitate/personalitate vizibilă.** Fără cosmetice, avatare,
   ceva de arătat prietenilor — status vizibil contează enorm la vârsta asta,
   nu neapărat grafică mai bună.
5. **Fără urgență/eveniment.** Nimic nu creează motiv să joci azi și nu mâine
   — fără conținut rotativ/sezonier, quest-urile zilnice devin rutină rapid.
6. **Replayability slab după ce înțelegi mecanica.** După 3-5 meciuri de Obby,
   dacă știi exact ce urmează, ce te face să mai apeși Play?

**Punctul-cheie al lui GPT**, cu care sunt de acord: nu încercăm să facem
jocul *mai mare* (mai multe categorii, mai multe întrebări) — încercăm să-l
facem **mai imprevizibil**. Exemple concrete date de GPT, bune ca punct de
plecare pentru runde de multiplayer (Obby/Astro Sodo/Tanks):

- "Ai răspuns corect. Alegi: traseu sigur sau traseu scurt?" (decizie, nu doar
  răspuns)
- "Toți jucătorii primesc aceeași întrebare" (moment de tensiune comună)
- "Ultimul primește o a doua șansă" (menține pe toată lumea în joc)
- "Obstacolul se schimbă" (rupe tiparul memorat)
- "Ai 5 secunde, dar dacă răspunzi primul corect, sari două poziții" (miză
  imediată + competiție directă)

Și un avertisment util de reținut: feedback-ul "devine plictisitor" nu e
semn că jocul e prost — e semn că bucla de bază *funcționează* (altfel n-ar
fi jucat destul cât să se plictisească), dar are nevoie de variație după
primele meciuri.

## Ce merită atacat primul, în ordine de impact/efort

1. **Activează sistemul de ligă ca rivalitate vizibilă** — efort mic (schela
   există deja), impact mare. Clasament de prieteni cu liga fiecăruia,
   notificare "X te-a depășit", eventual sezoane cu reset ca să nu rămână
   toată lumea blocată în Bronze pentru totdeauna.
2. **Cosmetice simple** — avatare/skin-uri/badge-uri de afișat, fără să
   atingem economia de bază. Combină direct cu liga (ex. skin exclusiv la
   Gold+).
3. **1-2 evenimente aleatorii per rundă multiplayer**, gen exemplele de mai
   sus de la GPT — nu toate modurile deodată, un pilot pe Obby sau Astro Sodo
   ca să vedem dacă schimbă senzația de "nu știu ce urmează".
4. **Recompensă imediată vizibilă în timpul rundei**, nu doar la final —
   ex. bonus pe loc la răspuns rapid, nu doar XP calculat după meci.
5. Conținut rotativ/sezonier — cel mai mare efort dintre toate, lăsat la
   urmă intenționat.

Următorul pas natural, când vrem să trecem la treabă: alegem UNUL din
punctele 1-4 (recomandarea mea: liga, pentru că infrastructura există deja)
și îl discutăm ca task separat, nu ca parte din acest plan.
