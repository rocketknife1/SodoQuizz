"""Generează assets/continut/mecanica/intrebari.json — gamemode cu piese
si scule auto (strict componente, fara marci de masini).

Fiecare item: (raspuns, termen_cautare_imagine_EN, hint1, hint2, hint3, [3 variante gresite])
Rulare: python tools/generate_mecanica_questions.py
"""
import json
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ITEMS = [
    ("CHEIE FRANCEZA", "adjustable wrench", "Are o falcă mobilă", "Se folosește la piulițe de diverse mărimi", "Se mai numește și cheie englezească", ["CHEIE FIXA", "CHEIE TUBULARA", "CLESTE"]),
    ("CHEIE FIXA", "open-end wrench", "Are un capăt deschis", "Vine în seturi de mărimi", "Instrument de bază în trusa de scule", ["CHEIE FRANCEZA", "CHEIE TUBULARA", "CHEIE DINAMOMETRICA"]),
    ("CHEIE TUBULARA", "socket wrench set", "Se pune peste șurub ca un tub", "Se folosește cu o clichetă", "Ajunge și în locuri înguste", ["CHEIE FIXA", "CHEIE FRANCEZA", "CHEIE DINAMOMETRICA"]),
    ("CHEIE DINAMOMETRICA", "torque wrench", "Are un afișaj sau scală de forță", "Se folosește la strângeri de precizie", "Oprește la un cuplu de strângere setat", ["CHEIE TUBULARA", "CHEIE FIXA", "CHEIE FRANCEZA"]),
    ("SURUBELNITA", "screwdriver tool", "Are un vârf plat sau în cruce", "Cel mai simplu instrument din trusă", "Se folosește manual, prin rotire", ["CLESTE", "CIOCAN", "CHEIE FIXA"]),
    ("CRIC", "car jack", "Ridică mașina de pe sol", "Se folosește la schimbat roata", "Poate fi hidraulic sau mecanic", ["SUPORT DE SIGURANTA", "POMPA DE AER", "EXTRACTOR DE RULMENTI"]),
    ("SUPORT DE SIGURANTA", "jack stand", "Se pune sub mașină după ridicare", "Are formă de X sau piramidă", "Ține mașina ridicată în siguranță", ["CRIC", "CHEIE TUBULARA", "EXTRACTOR DE RULMENTI"]),
    ("CLESTE", "pliers tool", "Are două brațe articulate", "Prinde, taie sau îndoaie", "Vine în multe variante specializate", ["SURUBELNITA", "CHEIE FRANCEZA", "CIOCAN"]),
    ("CIOCAN DE CAUCIUC", "rubber mallet", "Capul e din cauciuc, nu metal", "Nu zgârie și nu deformează piesele", "Folosit la lovituri ușoare de aliniere", ["CLESTE", "EXTRACTOR DE RULMENTI", "SURUBELNITA"]),
    ("EXTRACTOR DE RULMENTI", "bearing puller tool", "Are brațe care se strâng în jurul piesei", "Scoate rulmenții fără să-i strice", "Folosit la roți și transmisie", ["CRIC", "CHEIE TUBULARA", "CLESTE"]),
    ("POMPA DE AER", "tire inflator pump", "Umflă cauciucurile", "Are un manometru atașat", "Poate fi electrică sau manuală", ["COMPRESOR DE AER", "CRIC", "PISTOL DE VOPSIT"]),
    ("COMPRESOR DE AER", "air compressor workshop", "Aparat mai mare, de atelier", "Alimentează scule pneumatice", "Face zgomot când pompează aer", ["POMPA DE AER", "PISTOL DE VOPSIT", "POLIZOR UNGHIULAR"]),
    ("LAMPA DE LUCRU", "mechanic work light", "Se agață sub capotă", "Luminează zona în care lucrezi", "Poate fi cu LED sau halogen", ["MULTIMETRU AUTO", "FAR AUTO", "CLESTE"]),
    ("MULTIMETRU AUTO", "automotive multimeter", "Măsoară voltaj și curent", "Are două fire de test (probe)", "Verifică bateria și siguranțele", ["LAMPA DE LUCRU", "RELEU", "SIGURANTA AUTO"]),
    ("PISTOL DE VOPSIT", "spray paint gun", "Pulverizează vopsea sub presiune", "Se conectează la un compresor", "Folosit la caroserie", ["COMPRESOR DE AER", "POLIZOR UNGHIULAR", "APARAT DE SUDURA"]),
    ("POLIZOR UNGHIULAR", "angle grinder tool", "Are un disc care se rotește rapid", "Taie și șlefuiește metal", "Scoate scântei la tăiere", ["APARAT DE SUDURA", "PISTOL DE VOPSIT", "CHEIE FRANCEZA"]),
    ("APARAT DE SUDURA", "welding machine", "Topește metalul ca să-l îmbine", "Necesită mască de protecție", "Lasă o urmă de cordon metalic", ["POLIZOR UNGHIULAR", "COMPRESOR DE AER", "PISTOL DE VOPSIT"]),
    ("PISTON", "car engine piston", "Se mișcă în sus și-n jos în cilindru", "Are inele metalice pe margine", "Transformă explozia în mișcare", ["BIELA", "ARBORE COTIT", "CHIULASA"]),
    ("CHIULASA", "cylinder head engine", "Stă deasupra blocului motor", "Găzduiește supapele", "Se strânge cu o garnitură specială dedesubt", ["BLOC MOTOR", "GARNITURA DE CHIULASA", "GALERIE DE ADMISIE"]),
    ("BLOC MOTOR", "engine block", "Partea centrală, cea mai grea a motorului", "În el se mișcă pistoanele", "Pe el se montează chiulasa", ["CHIULASA", "ARBORE COTIT", "PISTON"]),
    ("ARBORE COTIT", "crankshaft part", "Se rotește sub acțiunea pistoanelor", "Transformă mișcarea liniară în rotație", "Se leagă de biele", ["PISTON", "BIELA", "ARBORE CU CAME"]),
    ("BIELA", "connecting rod engine", "Leagă pistonul de arborele cotit", "O piesă lungă și subțire de metal", "Transmite forța de la piston mai departe", ["PISTON", "ARBORE COTIT", "ARBORE CU CAME"]),
    ("ARBORE CU CAME", "camshaft part", "Are proeminențe numite came", "Controlează deschiderea supapelor", "Se rotește sincronizat cu arborele cotit", ["ARBORE COTIT", "BIELA", "CUREA DE DISTRIBUTIE"]),
    ("GARNITURA DE CHIULASA", "head gasket", "O foaie subțire între bloc și chiulasă", "Etanșează camerele de ardere", "Dacă se arde, motorul pierde compresie", ["CHIULASA", "BLOC MOTOR", "GALERIE DE ADMISIE"]),
    ("CUREA DE DISTRIBUTIE", "timing belt", "O curea dințată din cauciuc întărit", "Sincronizează arborele cotit cu cel cu came", "Se schimbă la un interval fix de km", ["LANT DE DISTRIBUTIE", "CUREA DE ALTERNATOR", "ARBORE CU CAME"]),
    ("LANT DE DISTRIBUTIE", "timing chain engine", "Face aceeași treabă ca o curea, dar din metal", "Durează de obicei toată viața motorului", "Zăngăne dacă se uzează", ["CUREA DE DISTRIBUTIE", "ARBORE CU CAME", "CUREA DE ALTERNATOR"]),
    ("BUJIE", "spark plug", "Produce o scânteie electrică", "Se înfiletează în chiulasă", "Aprinde amestecul de benzină și aer", ["BUJIE INCANDESCENTA", "INJECTOR", "SENZOR DE OXIGEN"]),
    ("BUJIE INCANDESCENTA", "glow plug diesel", "Încălzește camera de ardere", "Folosită la motoarele diesel", "Se aprinde câteva secunde înainte de pornire", ["BUJIE", "INJECTOR", "RELEU"]),
    ("INJECTOR", "fuel injector part", "Pulverizează combustibil fin", "Controlat electronic de calculatorul mașinii", "Înlocuiește vechiul carburator", ["CARBURATOR", "POMPA DE BENZINA", "BUJIE"]),
    ("CARBURATOR", "car carburetor", "Amestecă aerul cu benzina mecanic", "Tehnologie mai veche, azi rar folosită", "Are un flotor în interior", ["INJECTOR", "GALERIE DE ADMISIE", "FILTRU DE AER"]),
    ("POMPA DE BENZINA", "fuel pump car", "Trimite combustibilul din rezervor spre motor", "Poate fi electrică sau mecanică", "Dacă cedează, mașina nu mai pornește", ["INJECTOR", "FILTRU DE COMBUSTIBIL", "CARBURATOR"]),
    ("POMPA DE ULEI", "oil pump engine", "Circulă uleiul prin motor", "Menține presiunea de ungere", "Se rotește antrenată de arborele cotit", ["FILTRU DE ULEI", "POMPA DE APA", "POMPA DE BENZINA"]),
    ("FILTRU DE ULEI", "oil filter car", "Reține impuritățile din ulei", "Se schimbă la fiecare schimb de ulei", "Are formă cilindrică, se deșurubează", ["FILTRU DE AER", "FILTRU DE COMBUSTIBIL", "FILTRU DE POLEN"]),
    ("FILTRU DE AER", "car air filter", "Curăță aerul înainte să intre în motor", "Din hârtie plisată, în cutie de plastic", "Se colmatează cu praf în timp", ["FILTRU DE ULEI", "FILTRU DE POLEN", "GALERIE DE ADMISIE"]),
    ("FILTRU DE COMBUSTIBIL", "fuel filter car", "Reține impuritățile din benzină sau motorină", "Montat pe traseul spre injectoare", "Colmatat, dă probleme de pornire", ["FILTRU DE ULEI", "FILTRU DE AER", "POMPA DE BENZINA"]),
    ("FILTRU DE POLEN", "cabin air filter", "Curăță aerul care intră în habitaclu", "Se schimbă pentru mirosuri și alergii", "Nu are legătură cu motorul, ci cu ventilația", ["FILTRU DE AER", "FILTRU DE ULEI", "VENTILATOR RADIATOR"]),
    ("RADIATOR", "car radiator part", "Răcește lichidul din motor", "Are o rețea fină de canale metalice", "Montat în fața mașinii, în calea aerului", ["VAS DE EXPANSIUNE", "TERMOSTAT", "VENTILATOR RADIATOR"]),
    ("TERMOSTAT", "car thermostat part", "O supapă mică ce reglează temperatura", "Se deschide doar când motorul e cald", "Dacă e blocat, motorul supraîncălzește", ["RADIATOR", "POMPA DE APA", "VAS DE EXPANSIUNE"]),
    ("POMPA DE APA", "water pump car engine", "Circulă lichidul de răcire", "Antrenată de curea", "Dacă curge, apare o baltă sub mașină", ["TERMOSTAT", "RADIATOR", "POMPA DE ULEI"]),
    ("VAS DE EXPANSIUNE", "coolant reservoir tank", "Un recipient de plastic translucid", "Preia surplusul de lichid de răcire", "Are marcaje de nivel minim și maxim", ["RADIATOR", "TERMOSTAT", "POMPA DE APA"]),
    ("ALTERNATOR", "car alternator part", "Generează curent electric în timp ce motorul merge", "Încarcă bateria mașinii", "Antrenat printr-o curea", ["DEMAROR", "BATERIE AUTO", "RELEU"]),
    ("DEMAROR", "car starter motor", "Pornește motorul când răsucești cheia", "Un motoraș electric puternic", "Angrenează o roată dințată pe volantă", ["ALTERNATOR", "BATERIE AUTO", "BUJIE INCANDESCENTA"]),
    ("TURBINA", "car turbocharger part", "Folosește gazele de eșapament ca să comprime aerul", "Crește puterea motorului", "Poate ajunge la turații foarte mari", ["CATALIZATOR", "TOBA DE ESAPAMENT", "COMPRESOR DE AER"]),
    ("CATALIZATOR", "catalytic converter part", "Reduce poluarea din gazele de eșapament", "Conține un miez ceramic cu metale prețioase", "Face parte din sistemul de evacuare", ["TURBINA", "TOBA DE ESAPAMENT", "SENZOR DE OXIGEN"]),
    ("TOBA DE ESAPAMENT", "exhaust muffler part", "Reduce zgomotul motorului", "Montată la capătul evacuării", "Dacă se ruginește, mașina devine gălăgioasă", ["CATALIZATOR", "GALERIE DE EVACUARE", "TURBINA"]),
    ("GALERIE DE ADMISIE", "intake manifold part", "Distribuie amestecul aer-combustibil spre cilindri", "Montată pe partea opusă evacuării", "Formă ramificată, ca niște brațe", ["GALERIE DE EVACUARE", "CARBURATOR", "FILTRU DE AER"]),
    ("GALERIE DE EVACUARE", "exhaust manifold part", "Colectează gazele arse de la fiecare cilindru", "Devine foarte fierbinte în funcționare", "Se leagă mai departe de eșapament", ["GALERIE DE ADMISIE", "TOBA DE ESAPAMENT", "CATALIZATOR"]),
    ("SENZOR DE OXIGEN", "oxygen sensor car", "Măsoară cât oxigen rămâne în gazele arse", "Ajută calculatorul să regleze amestecul", "Montat pe traseul de evacuare", ["CATALIZATOR", "SENZOR DE TURATIE", "BUJIE"]),
    ("SENZOR DE TURATIE", "crankshaft position sensor", "Citește viteza de rotație a motorului", "Fără el, motorul nu pornește", "Montat lângă arborele cotit", ["SENZOR DE OXIGEN", "ARBORE COTIT", "RELEU"]),
    ("CUREA DE ALTERNATOR", "serpentine belt car", "Antrenează alternatorul și alte accesorii", "O curea lată, cu caneluri", "Dacă scârțâie, e semn că trebuie schimbată", ["CUREA DE DISTRIBUTIE", "LANT DE DISTRIBUTIE", "ALTERNATOR"]),
    ("VENTILATOR RADIATOR", "radiator cooling fan", "Trage aer prin radiator", "Pornește automat când motorul se încălzește", "Montat chiar în spatele radiatorului", ["RADIATOR", "POMPA DE APA", "VAS DE EXPANSIUNE"]),
    ("DISC DE FRANA", "brake disc rotor", "O piesă metalică rotundă, atașată de roată", "Plăcuțele se freacă de el", "Se poate deforma dacă se supraîncălzește", ["PLACUTE DE FRANA", "TAMBUR DE FRANA", "ETRIER DE FRANA"]),
    ("PLACUTE DE FRANA", "brake pads", "Se freacă de disc ca să oprească mașina", "Se uzează și trebuie schimbate periodic", "Scârțâie când sunt aproape tocite", ["DISC DE FRANA", "SABOTI DE FRANA", "ETRIER DE FRANA"]),
    ("ETRIER DE FRANA", "brake caliper part", "Strânge plăcuțele pe disc", "Conține pistonașe hidraulice", "Montat călare pe discul de frână", ["DISC DE FRANA", "SERVOFRANA", "TAMBUR DE FRANA"]),
    ("TAMBUR DE FRANA", "brake drum part", "Un cilindru metalic care acoperă sistemul de frânare", "Folosit mai des la roțile din spate", "În interior au loc saboții", ["DISC DE FRANA", "SABOTI DE FRANA", "ETRIER DE FRANA"]),
    ("SABOTI DE FRANA", "brake shoes part", "Se lipesc de interiorul tamburului", "Varianta mai veche pentru frâne pe spate", "Se extind spre exterior la apăsarea pedalei", ["PLACUTE DE FRANA", "TAMBUR DE FRANA", "DISC DE FRANA"]),
    ("SERVOFRANA", "brake booster part", "Amplifică forța aplicată pe pedala de frână", "Montat între pedală și cilindrul principal", "Fără el, frâna e foarte grea de apăsat", ["ETRIER DE FRANA", "FURTUN DE FRANA", "PEDALA DE FRANA"]),
    ("FURTUN DE FRANA", "brake hose part", "Un tub flexibil cu lichid de frână", "Leagă caroseria de etrier", "Dacă plesnește, se pierde presiunea de frânare", ["SERVOFRANA", "ETRIER DE FRANA", "LICHID DE FRANA"]),
    ("AMORTIZOR", "car shock absorber", "Absoarbe șocurile de la denivelări", "Montat lângă arcul spiral", "Dacă e uzat, mașina „sare” pe drum", ["ARC SPIRAL", "BARA STABILIZATOARE", "BRAT SUSPENSIE"]),
    ("ARC SPIRAL", "coil spring suspension", "O spirală metalică groasă", "Susține greutatea mașinii", "Lucrează împreună cu amortizorul", ["AMORTIZOR", "BARA STABILIZATOARE", "BUCSA SUSPENSIE"]),
    ("BARA STABILIZATOARE", "anti-roll bar suspension", "O bară transversală între roțile de aceeași parte", "Reduce înclinarea mașinii în viraje", "Se leagă de suspensie prin bielete", ["ARC SPIRAL", "BRAT SUSPENSIE", "AMORTIZOR"]),
    ("BRAT SUSPENSIE", "control arm suspension", "Leagă roata de caroserie", "Permite roții să se miște pe verticală", "Are bucșe de cauciuc la capete", ["BARA STABILIZATOARE", "ARTICULATIE SFERICA", "BUCSA SUSPENSIE"]),
    ("RULMENT ROATA", "wheel bearing part", "Permite roții să se rotească liber", "Dacă e uzat, face zgomot de vuiet", "Montat în butucul roții", ["ARTICULATIE SFERICA", "BUCSA SUSPENSIE", "PLANETARA"]),
    ("ARTICULATIE SFERICA", "ball joint suspension", "O articulație în formă de sferă", "Leagă brațul de suspensie de fuzetă", "Permite mișcare în mai multe direcții", ["RULMENT ROATA", "BUCSA SUSPENSIE", "BRAT SUSPENSIE"]),
    ("BUCSA SUSPENSIE", "suspension bushing part", "Un inel de cauciuc sau poliuretan", "Reduce vibrațiile transmise caroseriei", "Se montează la capetele brațelor de suspensie", ["ARTICULATIE SFERICA", "ARC SPIRAL", "BRAT SUSPENSIE"]),
    ("CUTIE DE VITEZE", "car gearbox transmission", "Schimbă raportul de transmisie", "Poate fi manuală sau automată", "Are o manetă sau selector în habitaclu", ["AMBREIAJ", "DIFERENTIAL", "CARDAN"]),
    ("AMBREIAJ", "car clutch part", "Cuplează și decuplează motorul de cutia de viteze", "Se apasă cu piciorul stâng", "Se uzează dacă e folosit greșit", ["DISC AMBREIAJ", "PLACA PRESIUNE", "RULMENT DE PRESIUNE"]),
    ("DISC AMBREIAJ", "clutch disc part", "O piesă rotundă cu garnitură de fricțiune", "Se prinde între volantă și placa de presiune", "Se uzează cu timpul, ca plăcuțele de frână", ["PLACA PRESIUNE", "RULMENT DE PRESIUNE", "AMBREIAJ"]),
    ("PLACA PRESIUNE", "clutch pressure plate", "Apasă discul de ambreiaj pe volantă", "Are arcuri puternice în interior", "Lucrează împreună cu discul de ambreiaj", ["DISC AMBREIAJ", "RULMENT DE PRESIUNE", "VOLANTA"]),
    ("RULMENT DE PRESIUNE", "clutch release bearing", "Apasă pe placa de presiune la călcarea ambreiajului", "O piesă mică, dar esențială", "Dacă scârțâie, e semn de defecțiune", ["PLACA PRESIUNE", "DISC AMBREIAJ", "RULMENT ROATA"]),
    ("CARDAN", "drive shaft car part", "Transmite mișcarea de la cutie la roți", "O tijă lungă, rotativă", "Are articulații la capete", ["DIFERENTIAL", "PLANETARA", "CUTIE DE VITEZE"]),
    ("PLANETARA", "axle shaft car part", "Leagă diferențialul de roată", "Are un capăt cu caneluri", "Se rupe rar, dar face zgomot dacă e uzată", ["CARDAN", "DIFERENTIAL", "RULMENT ROATA"]),
    ("DIFERENTIAL", "car differential part", "Permite roților să se rotească cu viteze diferite", "Esențial în viraje", "Montat de obicei pe puntea spate sau față", ["CUTIE DE VITEZE", "CARDAN", "PLANETARA"]),
    ("BATERIE AUTO", "car battery", "Stochează energie electrică", "Alimentează demarorul la pornire", "Are doi poli, plus și minus", ["ALTERNATOR", "DEMAROR", "RELEU"]),
    ("SIGURANTA AUTO", "car fuse box", "Se arde intenționat ca să protejeze circuitul", "Vine în culori diferite după amperaj", "Se schimbă ușor, fără scule", ["RELEU", "MULTIMETRU AUTO", "BATERIE AUTO"]),
    ("RELEU", "automotive relay", "Un comutator electric acționat electric", "Face un clic caracteristic", "Controlează circuite cu curent mare", ["SIGURANTA AUTO", "MULTIMETRU AUTO", "CLAXON"]),
    ("FAR AUTO", "car headlight part", "Luminează drumul noaptea", "Montat în fața mașinii", "Poate fi cu halogen, xenon sau LED", ["STOP AUTO", "LAMPA DE LUCRU", "OGLINDA RETROVIZOARE"]),
    ("STOP AUTO", "car tail light part", "Se aprinde în spatele mașinii", "Roșu, pentru frânare și semnalizare", "Montat la partea posterioară a caroseriei", ["FAR AUTO", "CLAXON", "BARA DE PROTECTIE"]),
    ("CLAXON", "car horn part", "Emite un sunet puternic de avertizare", "Se acționează de pe volan", "Electric, montat de obicei în față", ["RELEU", "STOP AUTO", "STERGATOR PARBRIZ"]),
    ("STERGATOR PARBRIZ", "windshield wiper blade", "O lamă de cauciuc pe un braț metalic", "Curăță parbrizul de ploaie", "Se uzează și lasă dâre dacă e vechi", ["MOTORAS STERGATOR", "PARBRIZ", "OGLINDA RETROVIZOARE"]),
    ("MOTORAS STERGATOR", "wiper motor part", "Acționează brațele ștergătoarelor", "Un motoraș electric ascuns sub capotă", "Fără el, ștergătoarele nu se mișcă deloc", ["STERGATOR PARBRIZ", "DEMAROR", "VENTILATOR RADIATOR"]),
    ("JANTA", "car wheel rim", "Piesa metalică pe care se montează cauciucul", "Poate fi din oțel sau aliaj", "Are găuri pentru prezoanele roții", ["CAUCIUC", "CAPAC ROATA", "RULMENT ROATA"]),
    ("CAUCIUC", "car tire", "Din cauciuc, montat pe jantă", "Singurul contact al mașinii cu drumul", "Are un profil cu caneluri", ["JANTA", "CAPAC ROATA", "AMORTIZOR"]),
    ("CAPAC ROATA", "wheel hub cap", "Acoperă janta din motive estetice", "Se prinde prin clipsare sau șuruburi", "Nu are rol funcțional, doar de aspect", ["JANTA", "CAUCIUC", "RULMENT ROATA"]),
    ("OGLINDA RETROVIZOARE", "car side mirror", "Montată pe ușă, se poate plia", "Ajută la observarea traficului din spate", "Poate avea încălzire sau semnalizare integrată", ["PARBRIZ", "FAR AUTO", "STERGATOR PARBRIZ"]),
    ("PARBRIZ", "car windshield", "Geamul mare din fața mașinii", "Din sticlă triplex, nu se sparge în cioburi", "Șters de ștergătoare", ["OGLINDA RETROVIZOARE", "BARA DE PROTECTIE", "CAPOTA MOTOR"]),
    ("BARA DE PROTECTIE", "car bumper part", "Absoarbe impactul la coliziuni ușoare", "Montată în față și în spate", "De obicei din plastic vopsit", ["CAPOTA MOTOR", "ARIPA", "PORTBAGAJ"]),
    ("CAPOTA MOTOR", "car hood bonnet", "Se ridică pentru acces la motor", "Panoul mare din fața mașinii", "Se deschide cu un mâner din habitaclu", ["PORTBAGAJ", "BARA DE PROTECTIE", "ARIPA"]),
    ("PORTBAGAJ", "car trunk open", "Spațiul de depozitare din spate", "Se deschide cu o clapetă", "Aici stă și roata de rezervă, de obicei", ["CAPOTA MOTOR", "BARA DE PROTECTIE", "ARIPA"]),
    ("ARIPA", "car fender part", "Panoul de caroserie de deasupra roții", "Protejează de stropi și noroi", "Montată lateral, lângă far", ["BARA DE PROTECTIE", "CAPOTA MOTOR", "PORTBAGAJ"]),
    ("ULEI DE MOTOR", "motor oil bottle", "Un lichid vâscos, de obicei maro-auriu", "Unge piesele mobile din motor", "Se verifică cu jojă", ["LICHID DE FRANA", "ANTIGEL", "LICHID DE PARBRIZ"]),
    ("LICHID DE FRANA", "brake fluid bottle", "Transmite presiunea în sistemul de frânare", "Absoarbe umezeala din aer în timp", "Se schimbă la un interval recomandat de ani", ["ULEI DE MOTOR", "ANTIGEL", "LICHID DE PARBRIZ"]),
    ("ANTIGEL", "engine coolant bottle", "Lichid colorat, de obicei verde sau roz", "Circulă prin radiator", "Împiedică înghețarea sau fierberea motorului", ["ULEI DE MOTOR", "LICHID DE FRANA", "LICHID DE PARBRIZ"]),
    ("LICHID DE PARBRIZ", "windshield washer fluid", "Se pulverizează pe parbriz", "Ajută ștergătoarele să curețe geamul", "Se toarnă într-un rezervor separat de plastic", ["ANTIGEL", "ULEI DE MOTOR", "LICHID DE FRANA"]),
    ("JOJA DE ULEI", "oil dipstick engine", "O tijă lungă și subțire", "Se scoate ca să verifici nivelul de ulei", "Are marcaje minim și maxim la capăt", ["FILTRU DE ULEI", "POMPA DE ULEI", "BUSON DE ULEI"]),
    ("BUSON DE ULEI", "oil filler cap engine", "Se deșurubează ca să torni ulei nou", "Montat deasupra chiulasei", "Are de obicei un simbol de canistră", ["JOJA DE ULEI", "FILTRU DE ULEI", "VAS DE EXPANSIUNE"]),
    ("VOLAN", "car steering wheel", "Îl ții cu ambele mâini când conduci", "Rotit, întoarce roțile mașinii", "Poate avea airbag integrat", ["COLOANA DE DIRECTIE", "PEDALA DE FRANA", "CASETA DE DIRECTIE"]),
    ("COLOANA DE DIRECTIE", "steering column part", "Leagă volanul de sistemul de direcție", "Se poate regla pe înălțime sau adâncime", "Ascunde adesea mecanisme de siguranță", ["VOLAN", "CASETA DE DIRECTIE", "CARDAN"]),
    ("CASETA DE DIRECTIE", "steering rack part", "Transformă rotirea volanului în mișcare laterală", "Leagă de roțile din față prin bare", "Poate fi asistată hidraulic sau electric", ["COLOANA DE DIRECTIE", "VOLAN", "BRAT SUSPENSIE"]),
    ("PEDALA DE FRANA", "brake pedal car", "O pârghie apăsată cu piciorul", "Acționează servofrâna și cilindrul principal", "Cea din mijloc la cutia manuală", ["SERVOFRANA", "VOLAN", "CASETA DE DIRECTIE"]),
]


def build():
    intrebari = []
    for i, (answer, search, h1, h2, h3, wrongs) in enumerate(ITEMS, start=1):
        qid = f"mec_{i:03d}"
        variante = [answer] + wrongs
        intrebari.append({
            "id": qid,
            "raspuns": answer,
            "variante": variante,
            "hint_1": h1,
            "hint_2": h2,
            "hint_3": h3,
            "dificultate": "usor" if i <= 50 else "mediu",
            "puncte_max": 200,
            "imagine_cautare": search,
            "imagine_sursa": "wikipedia",
        })

    data = {
        "categorii": {
            "mecanica": {
                "mod": "4_variante",
                "culoare_tema": "#E0A62B",
                "descriere": "Piese si scule auto",
                "intrebari": intrebari,
            }
        }
    }

    out = "assets/continut/mecanica/intrebari.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Scris {out} cu {len(intrebari)} intrebari")

    answers = [it[0] for it in ITEMS]
    dupes = {a for a in answers if answers.count(a) > 1}
    if dupes:
        print("ATENTIE, raspunsuri duplicate:", dupes)


if __name__ == "__main__":
    build()
