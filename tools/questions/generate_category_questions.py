"""Genereaza assets/continut/{categorie}/intrebari.json pentru cele trei
gamemoduri single-categorie cu format identic: aplicatii, mecanica, medical
(4 variante, 3 hinturi, dificultate dupa un prag pe index, imagine_cautare
pentru tools/images/fetch_question_images.py).

Inlocuieste fostele generate_aplicatii_questions.py / generate_mecanica_questions.py
/ generate_medical_questions.py - erau trei fisiere aproape identice, doar cu
ITEMS si cateva constante diferite. Vezi tools/questions/generate_premium_questions.py
pentru acelasi tipar aplicat celor 4 gamemoduri premium.

ATENTIE: scripturile astea au rulat deja o singura data, la bootstrap-ul
continutului. assets/continut/*/intrebari.json a fost modificat manual de
atunci (vezi tools/images/apply_manual_images.py, tools/questions/dedupe_questions.py) -
nu rulati din nou fara sa verificati intai ca nu suprascrieti acele modificari.

Fiecare item: (raspuns, termen_cautare_imagine_EN, hint1, hint2, hint3, [3 variante gresite])
Rulare: python tools/questions/generate_category_questions.py [aplicatii mecanica medical]
        (fara argumente = toate cele trei)
"""
import io
import json
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

APLICATII_ITEMS = [
    ("TELEGRAM", "Telegram app logo", "Aplicatie de mesagerie cu avion de hartie ca logo", "Rivala WhatsApp, cunoscuta pentru canale si grupuri mari", "Are si varianta secreta cu mesaje care se autodistrug", ["VIBER", "MESSENGER", "WECHAT"]),
    ("MESSENGER", "Facebook Messenger app logo", "Aplicatie separata pentru chat, fulger albastru ca logo", "A fost desprinsa din aplicatia principala Facebook", "Prin ea trimiti mesaje prietenilor de pe Facebook", ["TELEGRAM", "WHATSAPP", "THREADS"]),
    ("VIBER", "Viber app logo", "Aplicatie de mesagerie si apeluri gratuite, logo mov", "Foarte populara in Europa de Est", "Are un simbol in forma de receptor de telefon in bula de chat", ["TELEGRAM", "MESSENGER", "WECHAT"]),
    ("WECHAT", "WeChat app logo", "Super-aplicatie chinezeasca, logo verde cu doua bule vorbire", "Combina mesagerie, plati si retea sociala intr-una singura", "Cea mai folosita aplicatie de mesagerie din China", ["TELEGRAM", "VIBER", "MESSENGER"]),
    ("THREADS", "Threads app logo Meta", "Lansata de Meta ca rivala pentru X", "Logo-ul e un simbol format dintr-o linie infasurata, ca un fir de ata", "Legata direct de contul de Instagram", ["MESSENGER", "TELEGRAM", "BEREAL"]),
    ("BEREAL", "BeReal app logo", "Iti trimite o notificare random sa te fotografiezi", "Foloseste camera fata si spate simultan", "Numele ei inseamna sa fii autentic, fara filtre", ["THREADS", "SNAPCHAT", "VSCO"]),
    ("GMAIL", "Gmail app logo", "Serviciu de email cu plicul rosu si alb", "Cel mai folosit serviciu de email din lume", "Vine cu spatiu gratuit de stocare in cloud", ["OUTLOOK", "GOOGLE MAPS", "GOOGLE DRIVE"]),
    ("GOOGLE MAPS", "Google Maps app logo", "Aplicatie de navigatie cu un pin rosu ca logo", "Iti arata trafic in timp real si rute alternative", "Are si vedere Street View a strazilor", ["WAZE", "GMAIL", "GOOGLE DRIVE"]),
    ("WAZE", "Waze app logo", "Aplicatie de navigatie cu un mascota zambareata, logo albastru", "Utilizatorii raporteaza radare si accidente in timp real", "A fost cumparata de Google, dar ramane separata", ["GOOGLE MAPS", "BOLT", "LYFT"]),
    ("GOOGLE DRIVE", "Google Drive app logo", "Stocare in cloud cu logo triunghiular colorat", "Aici salvezi documente, poze si fisiere online", "Vine la pachet cu Docs, Sheets si Slides", ["GMAIL", "GOOGLE PHOTOS", "GOOGLE MAPS"]),
    ("GOOGLE PHOTOS", "Google Photos app logo", "Aplicatie pentru pozele tale, logo cu morisca colorata", "Face backup automat la toate fotografiile", "Recunoaste fete si organizeaza albume singura", ["GOOGLE DRIVE", "GMAIL", "VSCO"]),
    ("GOOGLE CHROME", "Google Chrome browser logo", "Browser de internet, logo rotund in 4 culori", "Cel mai folosit browser din lume", "Are propriul motor de cautare Google incorporat", ["GOOGLE MEET", "GOOGLE TRANSLATE", "GOOGLE MAPS"]),
    ("GOOGLE TRANSLATE", "Google Translate app logo", "Traduce text intre zeci de limbi, logo cu literele A si o alta litera", "Poate traduce si folosind camera telefonului", "Extrem de util in calatorii in strainatate", ["GOOGLE CHROME", "GMAIL", "GOOGLE MEET"]),
    ("GOOGLE MEET", "Google Meet app logo", "Aplicatie de videoconferinta, logo cu forme colorate ca o camera video", "Integrata direct cu Gmail si Calendar", "Rivala Zoom si Microsoft Teams", ["ZOOM", "SKYPE", "MICROSOFT TEAMS"]),
    ("MICROSOFT TEAMS", "Microsoft Teams app logo", "Aplicatie de chat si videoconferinta, logo violet cu litera T", "Foarte folosita in mediul de birou si scoli", "Integrata cu Office 365", ["GOOGLE MEET", "SKYPE", "OUTLOOK"]),
    ("OUTLOOK", "Outlook app logo", "Aplicatie de email Microsoft, logo albastru cu litera O", "Combina email, calendar si contacte", "Foloseste mult mediul corporate alaturi de Teams", ["GMAIL", "MICROSOFT TEAMS", "SKYPE"]),
    ("SKYPE", "Skype app logo", "Aplicatie de apeluri video, logo albastru cu un nor", "A fost printre primele aplicatii populare de video call", "Cumparata de Microsoft acum multi ani", ["MICROSOFT TEAMS", "GOOGLE MEET", "OUTLOOK"]),
    ("NOTION", "Notion app logo", "Aplicatie de organizare si notite, logo alb-negru simplu", "Foarte populara printre studenti pentru planificare", "Combina notite, tabele si baze de date intr-un singur loc", ["TRELLO", "EVERNOTE", "TODOIST"]),
    ("TRELLO", "Trello app logo", "Aplicatie de organizare cu carduri pe un panou, logo albastru", "Foloseste sistemul de planse cu liste tip Kanban", "Populara pentru gestionarea proiectelor in echipa", ["NOTION", "TODOIST", "EVERNOTE"]),
    ("EVERNOTE", "Evernote app logo", "Aplicatie de notite, logo cu un elefant verde", "Sincronizeaza notitele pe toate dispozitivele", "Una dintre primele aplicatii mari de luat notite", ["NOTION", "TRELLO", "TODOIST"]),
    ("TODOIST", "Todoist app logo", "Aplicatie de liste si sarcini zilnice, logo rosu cu bifa", "Te ajuta sa nu uiti de task-uri si termene", "Foarte folosita pentru productivitate personala", ["TRELLO", "NOTION", "EVERNOTE"]),
    ("REVOLUT", "Revolut app logo", "Aplicatie bancara digitala, logo negru cu o forma geometrica", "Card si cont bancar direct din telefon, fara banca traditionala", "Foarte populara pentru schimb valutar si plati internationale", ["N26", "BINANCE", "CASH APP"]),
    ("N26", "N26 bank app logo", "Banca digitala germana, logo simplu cu literele N26", "Functioneaza complet fara sucursale fizice", "Rivala Revolut pe piata bancilor digitale", ["REVOLUT", "BINANCE", "VENMO"]),
    ("BINANCE", "Binance app logo", "Platforma de criptomonede, logo galben cu forme de diamant", "Una dintre cele mai mari burse de crypto din lume", "Aici cumperi si vinzi Bitcoin si alte monede digitale", ["REVOLUT", "N26", "CASH APP"]),
    ("VENMO", "Venmo app logo", "Aplicatie de plati intre prieteni, logo albastru cu litera V", "Foarte populara in Statele Unite pentru a imparti nota la restaurant", "Are un feed social unde vezi platile prietenilor", ["CASH APP", "REVOLUT", "N26"]),
    ("CASH APP", "Cash App logo", "Aplicatie de plati rapide, logo verde cu simbolul dolar", "Detinuta de compania din spatele Square", "Permite si investitii in actiuni si Bitcoin", ["VENMO", "REVOLUT", "BINANCE"]),
    ("EMAG", "eMAG app logo", "Cel mai mare magazin online din Romania, logo portocaliu", "Are Black Friday anual foarte asteptat", "Vinde de la electronice pana la alimente", ["ALIEXPRESS", "TEMU", "WISH"]),
    ("ALIEXPRESS", "AliExpress app logo", "Magazin online chinezesc, logo rosu-portocaliu", "Detinut de gigantul Alibaba", "Cunoscut pentru preturi mici si livrare lunga din China", ["TEMU", "WISH", "EMAG"]),
    ("TEMU", "Temu app logo", "Magazin online cu preturi foarte mici, logo portocaliu cu litera T", "A devenit brusc foarte popular datorita reclamelor agresive", "Sloganul lor e ca poti trai ca un rege la preturi mici", ["ALIEXPRESS", "WISH", "EMAG"]),
    ("WISH", "Wish app logo", "Magazin online, logo albastru cu o steluta", "Cunoscut pentru produse ieftine si livrare foarte lenta", "Numele inseamna dorinta in engleza", ["TEMU", "ALIEXPRESS", "EMAG"]),
    ("BOLT", "Bolt app logo", "Aplicatie de ride-sharing estona, logo verde cu un fulger", "Rivala directa a companiei Uber in Europa", "Ofera si trotinete electrice de inchiriat", ["LYFT", "WAZE", "WOLT"]),
    ("LYFT", "Lyft app logo", "Aplicatie de ride-sharing americana, logo roz-mov", "Principala rivala a Uber pe piata din SUA", "Numele vine de la cuvantul lift, adica a ridica sau a lua pe cineva", ["BOLT", "UBER EATS", "WOLT"]),
    ("WOLT", "Wolt app logo", "Aplicatie de livrare mancare, logo albastru cu litera W", "Fondata in Finlanda, foarte populara in Europa", "Cumparata de compania din spatele DoorDash", ["BOLT FOOD", "GLOVO", "UBER EATS"]),
    ("BOLT FOOD", "Bolt Food app logo", "Serviciul de livrare mancare al companiei Bolt, logo verde", "Frate cu aplicatia de ride-sharing Bolt", "Livreaza mancare de la restaurante direct la usa", ["WOLT", "GLOVO", "UBER EATS"]),
    ("DISNEY PLUS", "Disney Plus app logo", "Platforma de streaming, logo albastru cu D stilizat", "Aici gasesti filmele Disney, Pixar, Marvel si Star Wars", "Lansata ca sa concureze direct cu Netflix", ["HBO MAX", "AMAZON PRIME VIDEO", "NETFLIX"]),
    ("HBO MAX", "HBO Max app logo", "Platforma de streaming, logo alb-negru simplu cu HBO MAX", "Cunoscuta pentru seriale premiate ca Game of Thrones", "Rivala Netflix si Disney Plus", ["DISNEY PLUS", "AMAZON PRIME VIDEO", "NETFLIX"]),
    ("AMAZON PRIME VIDEO", "Amazon Prime Video app logo", "Platforma de streaming a gigantului Amazon, logo albastru", "Vine inclusa in abonamentul Amazon Prime", "Difuzeaza si meciuri sportive live in unele tari", ["DISNEY PLUS", "HBO MAX", "NETFLIX"]),
    ("SOUNDCLOUD", "SoundCloud app logo", "Platforma audio, logo portocaliu cu forma de nor sonor", "Foarte populara printre artistii independenti si rapperi", "Multi artisti celebri si-au lansat prima piesa acolo", ["SPOTIFY", "SHAZAM", "DEEZER"]),
    ("SHAZAM", "Shazam app logo", "Recunoaste melodii dupa ce le asculta cateva secunde, logo albastru cu S", "O tii aproape de difuzor si iti spune ce piesa canta", "Cumparata de Apple acum cativa ani", ["SOUNDCLOUD", "APPLE MUSIC", "DEEZER"]),
    ("APPLE MUSIC", "Apple Music app logo", "Serviciu de streaming muzical, logo rosu cu nota muzicala", "Vine preinstalat pe orice iPhone", "Rivala directa a Spotify", ["SPOTIFY", "DEEZER", "SOUNDCLOUD"]),
    ("DEEZER", "Deezer app logo", "Serviciu de streaming muzical francez, logo cu forme colorate", "Alternativa europeana la Spotify", "Ofera si versiune cu sunet in calitate audiofila", ["SPOTIFY", "APPLE MUSIC", "SOUNDCLOUD"]),
    ("STRAVA", "Strava app logo", "Aplicatie pentru alergat si ciclism, logo portocaliu", "Iti urmareste traseele pe harta prin GPS", "Foarte populara printre sportivii care posteaza kilometri parcursi", ["MYFITNESSPAL", "HEADSPACE", "CALM"]),
    ("MYFITNESSPAL", "MyFitnessPal app logo", "Aplicatie de numarat calorii, logo albastru", "Are o baza de date uriasa cu alimente scanate", "Te ajuta sa tii evidenta dietei zilnice", ["STRAVA", "HEADSPACE", "CALM"]),
    ("HEADSPACE", "Headspace app logo", "Aplicatie de meditatie, logo portocaliu cu un cap simplu", "Te ghideaza prin exercitii de respiratie si mindfulness", "Foarte folosita pentru somn mai bun si reducerea stresului", ["CALM", "STRAVA", "MYFITNESSPAL"]),
    ("CALM", "Calm app logo", "Aplicatie de relaxare si somn, logo cu un cerc albastru linistit", "Are povesti audio pentru adormit, spuse de celebritati", "Rivala directa a Headspace", ["HEADSPACE", "STRAVA", "MYFITNESSPAL"]),
    ("TINDER", "Tinder app logo", "Aplicatie de dating, logo cu o flacara portocalie", "Faci swipe la dreapta daca iti place cineva", "Una dintre cele mai cunoscute aplicatii de intalniri din lume", ["BUMBLE", "BEREAL", "THREADS"]),
    ("BUMBLE", "Bumble app logo", "Aplicatie de dating, logo galben cu o albinuta", "La intalnirile intre barbat si femeie, ea trebuie sa scrie prima", "Rivala directa a aplicatiei Tinder", ["TINDER", "BEREAL", "THREADS"]),
    ("CAPCUT", "CapCut app logo", "Aplicatie de editat video pe telefon, logo negru cu forma stilizata", "Facuta de aceeasi companie din spatele TikTok", "Foarte folosita pentru a crea clipuri scurte pentru social media", ["VSCO", "LIGHTROOM", "PHOTOSHOP EXPRESS"]),
    ("VSCO", "VSCO app logo", "Aplicatie de editat poze cu filtre artistice, logo alb-negru simplu", "Populara printre pasionatii de fotografie estetica", "Are propria retea sociala de partajat poze editate", ["CAPCUT", "LIGHTROOM", "PHOTOSHOP EXPRESS"]),
    ("LIGHTROOM", "Adobe Lightroom app logo", "Aplicatie profesionala de editat poze, logo cu litere Lr", "Facuta de Adobe, folosita mult de fotografi", "Permite editare avansata a culorilor si luminii", ["VSCO", "CAPCUT", "PHOTOSHOP EXPRESS"]),
    ("KAHOOT", "Kahoot app logo", "Aplicatie de quiz-uri interactive, logo violet cu forme geometrice", "Foarte folosita la scoala pentru jocuri educative in clasa", "Elevii raspund de pe telefon in timp ce intrebarea e pe ecran mare", ["TODOIST", "TRELLO", "NOTION"]),
    ("NORDVPN", "NordVPN app logo", "Aplicatie VPN, logo albastru cu un scut", "Iti ascunde locatia si iti cripteaza conexiunea la internet", "Una dintre cele mai cunoscute aplicatii VPN din lume", ["REVOLUT", "N26", "BINANCE"]),
]

MECANICA_ITEMS = [
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

MEDICAL_ITEMS = [
    ("STETOSCOP", "stethoscope", "Îl poartă medicul la gât", "Se pune pe piept sau pe spate", "Cu el se ascultă inima și plămânii", ["OTOSCOP", "TENSIOMETRU", "CIOCAN DE REFLEXE"]),
    ("SERINGA", "medical syringe", "Are un ac la capăt", "Se folosește la injecții", "Cu ea se administrează vaccinuri", ["BRANULA", "PIPETA", "EPRUBETA"]),
    ("SCAUN CU ROTILE", "wheelchair", "Ajută la deplasare", "Are două roți mari laterale", "Îl folosesc persoanele care nu pot merge", ["CARJE", "CADRU DE MERS", "TARGA"]),
    ("APARAT RMN", "MRI scanner machine", "Un tunel mare în care intri complet", "Folosește câmp magnetic, nu radiații", "Face imagini detaliate ale creierului", ["COMPUTER TOMOGRAF", "ECOGRAF", "MAMOGRAF"]),
    ("COMPUTER TOMOGRAF", "CT scanner machine", "Un inel mare prin care trece patul", "Folosește raze X rotite în jurul corpului", "Prescurtat CT", ["APARAT RMN", "ECOGRAF", "APARAT DE RADIOGRAFIE"]),
    ("ECOGRAF", "ultrasound machine hospital", "Folosește ultrasunete", "Are o sondă care se plimbă pe piele cu gel", "Cu el se văd bebelușii în burtică", ["APARAT RMN", "SPIROMETRU", "ELECTROCARDIOGRAF"]),
    ("BISTURIU", "scalpel surgical", "Instrument foarte ascuțit", "Îl folosește chirurgul", "Lama cu care se face incizia la operație", ["FOARFECA CHIRURGICALA", "PENSETA", "AC DE SUTURA"]),
    ("PERFUZIE", "intravenous therapy drip bag", "Picură lent într-un tub", "Punga atârnă lângă patul pacientului", "Lichidul intră direct în venă", ["TRANSFUZIE", "BRANULA", "INJECTOMAT"]),
    ("BRANULA", "IV cannula", "Se montează pe mâna pacientului", "Rămâne fixată în venă mai multe zile", "Prin ea se conectează perfuzia", ["SERINGA", "CATETER", "AC DE SUTURA"]),
    ("TERMOMETRU", "medical thermometer fever", "Măsoară ceva în grade", "Se ține sub braț sau în gură", "Arată dacă ai febră", ["TENSIOMETRU", "PULSOXIMETRU", "GLUCOMETRU"]),
    ("TENSIOMETRU", "blood pressure monitor", "Are o manșetă care se umflă", "Se pune pe braț", "Măsoară tensiunea arterială", ["PULSOXIMETRU", "GLUCOMETRU", "TERMOMETRU"]),
    ("PULSOXIMETRU", "pulse oximeter finger", "Mic, cu clemă", "Se prinde pe deget", "Măsoară oxigenul din sânge și pulsul", ["GLUCOMETRU", "TENSIOMETRU", "HOLTER"]),
    ("GLUCOMETRU", "glucose meter diabetes", "Are nevoie de o picătură de sânge", "Folosit zilnic de diabetici", "Măsoară glicemia", ["PULSOXIMETRU", "TENSIOMETRU", "SPIROMETRU"]),
    ("DEFIBRILATOR", "defibrillator AED", "Se folosește în urgențe majore", "Are două padele sau electrozi", "Dă șocuri electrice ca să repornească inima", ["ELECTROCARDIOGRAF", "STIMULATOR CARDIAC", "MONITOR FUNCTII VITALE"]),
    ("ELECTROCARDIOGRAF", "electrocardiograph ECG machine", "Desenează linii pe hârtie sau ecran", "Electrozii se lipesc pe piept", "Înregistrează activitatea electrică a inimii — EKG", ["DEFIBRILATOR", "HOLTER", "SPIROMETRU"]),
    ("CARJE", "crutches", "Se țin sub brațe sau de mânere", "De obicei vin la pereche", "Le folosești când ai piciorul rupt", ["BASTON", "CADRU DE MERS", "SCAUN CU ROTILE"]),
    ("TARGA", "medical stretcher ambulance", "Pacientul stă întins pe ea", "E cărată de doi oameni sau are roți", "Cu ea se transportă răniții la ambulanță", ["PAT DE SPITAL", "SCAUN CU ROTILE", "MASA DE OPERATIE"]),
    ("PAT DE SPITAL", "hospital bed", "Are balustrade laterale", "Se poate ridica și înclina electric", "În el stau internații pe secție", ["TARGA", "MASA DE OPERATIE", "SCAUN STOMATOLOGIC"]),
    ("MASCA CHIRURGICALA", "surgical mask", "Se poartă pe față", "Are elastice pentru urechi", "Acoperă nasul și gura în operație", ["MASCA DE OXIGEN", "BONETA CHIRURGICALA", "OCHELARI DE PROTECTIE"]),
    ("MANUSI CHIRURGICALE", "surgical gloves latex", "Se poartă pe mâini", "De obicei din latex, sterile", "Chirurgul le pune înainte de operație", ["MASCA CHIRURGICALA", "HALAT MEDICAL", "BONETA CHIRURGICALA"]),
    ("HALAT MEDICAL", "doctor white coat", "Articol de îmbrăcăminte", "De obicei alb, cu buzunare", "Uniforma clasică a doctorului", ["BONETA CHIRURGICALA", "MASCA CHIRURGICALA", "MANUSI CHIRURGICALE"]),
    ("PLASTURE", "adhesive bandage plaster", "Mic și lipicios", "Se pune pe zgârieturi", "Îl lipești peste o rană mică", ["BANDAJ", "COMPRESA STERILA", "LEUCOPLAST"]),
    ("BANDAJ", "gauze bandage roll", "Vine în rolă", "Se înfășoară în jurul rănii", "Fașa cu care se leagă o rană", ["PLASTURE", "GHIPS", "ATELA"]),
    ("GAROU", "tourniquet medical", "O bandă care se strânge tare", "Se leagă deasupra rănii sau înainte de recoltare", "Oprește temporar circulația sângelui", ["BANDAJ", "LEUCOPLAST", "ATELA"]),
    ("ATELA", "medical splint arm", "Ține un membru nemișcat", "Rigidă, se prinde cu fașă", "Imobilizează fractura până la ghips", ["GHIPS", "ORTEZA", "GULER CERVICAL"]),
    ("GHIPS", "orthopedic cast arm", "Se întărește după aplicare", "Colegii pot semna pe el", "Îl porți săptămâni când ți-ai rupt mâna", ["ATELA", "ORTEZA", "BANDAJ"]),
    ("GULER CERVICAL", "cervical collar neck brace", "Se poartă în jurul gâtului", "Se pune după accidente de mașină", "Imobilizează coloana cervicală", ["ATELA", "ORTEZA", "GHIPS"]),
    ("PENSETA", "medical tweezers forceps", "Instrument mic de apucat", "Are două brațe care se strâng", "Cu ea scoți o așchie din piele", ["FOARFECA CHIRURGICALA", "BISTURIU", "AC DE SUTURA"]),
    ("FOARFECA CHIRURGICALA", "surgical scissors", "Instrument de tăiat, steril", "Adesea cu vârf curbat", "Cu ea chirurgul taie fire și bandaje", ["BISTURIU", "PENSETA", "CLEMA HEMOSTATICA"]),
    ("AC DE SUTURA", "surgical suture needle", "Mic, curbat, foarte ascuțit", "Trece prin piele cu ață specială", "Cu el se coase rana", ["FIR DE SUTURA", "SERINGA", "BRANULA"]),
    ("FIR DE SUTURA", "surgical suture thread", "Subțire, uneori se dizolvă singur", "Se scoate la 7-10 zile", "Ața cu care e cusută rana", ["AC DE SUTURA", "LEUCOPLAST", "BANDAJ"]),
    ("CIOCAN DE REFLEXE", "reflex hammer", "Mic instrument cu cap de cauciuc", "Neurologul îl folosește des", "Cu el se lovește ușor genunchiul", ["OTOSCOP", "STETOSCOP", "APASATOR DE LIMBA"]),
    ("OTOSCOP", "otoscope", "Are lumină și lupă", "Se introduce puțin în canal", "Cu el doctorul se uită în ureche", ["OFTALMOSCOP", "LARINGOSCOP", "ENDOSCOP"]),
    ("OFTALMOSCOP", "ophthalmoscope", "Instrument cu lumină", "Îl folosește oculistul", "Cu el se examinează interiorul ochiului", ["OTOSCOP", "LARINGOSCOP", "MICROSCOP"]),
    ("LARINGOSCOP", "laryngoscope", "Are o lamă metalică cu lumină", "Folosit la intubare", "Cu el se vede laringele și corzile vocale", ["ENDOSCOP", "OTOSCOP", "OFTALMOSCOP"]),
    ("ENDOSCOP", "endoscope", "Un tub lung și flexibil cu cameră", "Intră în corp prin gură", "Cu el se vede interiorul stomacului", ["LARINGOSCOP", "CATETER", "SONDA NAZOGASTRICA"]),
    ("MICROSCOP", "laboratory microscope", "Stă pe masa de laborator", "Are lentile și oglindă sau lampă", "Mărește celulele de sute de ori", ["CENTRIFUGA", "AUTOCLAV", "OFTALMOSCOP"]),
    ("EPRUBETA", "test tube laboratory", "Din sticlă, subțire și alungită", "Stă în stative de laborator", "În ea se recoltează sângele la analize", ["PIPETA", "CUTIE PETRI", "LAMA DE MICROSCOP"]),
    ("PIPETA", "laboratory pipette", "Ia lichid picătură cu picătură", "Adesea cu pară de cauciuc sau piston", "Cu ea se măsoară volume mici în laborator", ["EPRUBETA", "SERINGA", "CUTIE PETRI"]),
    ("CENTRIFUGA", "laboratory centrifuge", "Se învârte foarte repede", "Separă componentele sângelui", "În ea se pun eprubetele la rotit", ["AUTOCLAV", "INCUBATOR NEONATAL", "MICROSCOP"]),
    ("AUTOCLAV", "autoclave sterilizer", "Funcționează cu abur sub presiune", "Ca o oală sub presiune de laborator", "În el se sterilizează instrumentele", ["CENTRIFUGA", "INCUBATOR NEONATAL", "LAMPA CHIRURGICALA"]),
    ("CUTIE PETRI", "Petri dish bacteria", "Rotundă, plată, transparentă", "Are capac și gel nutritiv", "În ea se cultivă bacteriile", ["EPRUBETA", "LAMA DE MICROSCOP", "PIPETA"]),
    ("INCUBATOR NEONATAL", "neonatal incubator baby", "O cutie transparentă încălzită", "Se află la maternitate", "În el stau bebelușii prematuri", ["VENTILATOR MEDICAL", "AUTOCLAV", "PAT DE SPITAL"]),
    ("VENTILATOR MEDICAL", "medical ventilator ICU", "Aparat de la terapie intensivă", "Se conectează printr-un tub la pacient", "Respiră în locul pacientului", ["CONCENTRATOR DE OXIGEN", "NEBULIZATOR", "DEFIBRILATOR"]),
    ("CONCENTRATOR DE OXIGEN", "oxygen concentrator", "Aparat pentru acasă sau spital", "Extrage oxigen din aerul camerei", "Furnizează oxigen prin canulă nazală", ["BUTELIE DE OXIGEN", "VENTILATOR MEDICAL", "NEBULIZATOR"]),
    ("BUTELIE DE OXIGEN", "oxygen cylinder medical", "Un tub metalic sub presiune", "Adesea verde sau alb", "Rezerva de oxigen a ambulanței", ["CONCENTRATOR DE OXIGEN", "AUTOCLAV", "STATIV DE PERFUZIE"]),
    ("MASCA DE OXIGEN", "oxygen mask medical", "Se pune peste nas și gură", "Are un tub conectat la o sursă", "Prin ea pacientul primește oxigen", ["MASCA CHIRURGICALA", "CANULA NAZALA", "NEBULIZATOR"]),
    ("CANULA NAZALA", "nasal cannula", "Un tub subțire cu două vârfuri", "Se agață după urechi", "Duce oxigenul direct în nări", ["MASCA DE OXIGEN", "SONDA NAZOGASTRICA", "CATETER"]),
    ("NEBULIZATOR", "nebulizer machine", "Transformă lichidul în ceață", "Folosit des la copii cu tuse", "Prin el se inhalează medicamentele", ["INHALATOR", "CONCENTRATOR DE OXIGEN", "VENTILATOR MEDICAL"]),
    ("INHALATOR", "asthma inhaler", "Mic, de buzunar", "Se apasă și se trage aer în piept", "Salvarea astmaticilor în criză", ["NEBULIZATOR", "PULVERIZATOR NAZAL", "MASCA DE OXIGEN"]),
    ("LAMPA CHIRURGICALA", "surgical light operating room", "Foarte puternică, fără umbre", "Atârnă deasupra mesei de operație", "Luminează câmpul operator", ["MASA DE OPERATIE", "LAMPA DE FOTOTERAPIE", "MONITOR FUNCTII VITALE"]),
    ("MASA DE OPERATIE", "operating table surgery", "În centrul sălii de operație", "Se reglează pe înălțime și înclinare", "Pe ea stă pacientul operat", ["PAT DE SPITAL", "TARGA", "SCAUN STOMATOLOGIC"]),
    ("MONITOR FUNCTII VITALE", "patient monitor vital signs", "Un ecran care piuie lângă pat", "Arată linii și cifre colorate", "Urmărește pulsul, tensiunea și oxigenul", ["ELECTROCARDIOGRAF", "DEFIBRILATOR", "HOLTER"]),
    ("INJECTOMAT", "syringe pump medical", "O pompă electronică precisă", "Împinge pistonul seringii automat", "Administrează medicamentul cu viteză exactă", ["PERFUZIE", "SERINGA", "STATIV DE PERFUZIE"]),
    ("CATETER", "medical catheter", "Un tub subțire și flexibil", "Se introduce în corp prin vase sau canale", "Prin el se drenează sau se administrează lichide", ["BRANULA", "SONDA NAZOGASTRICA", "ENDOSCOP"]),
    ("SONDA NAZOGASTRICA", "nasogastric tube", "Un tub lung și subțire", "Intră prin nas", "Ajunge până în stomac pentru hrănire", ["CATETER", "CANULA NAZALA", "ENDOSCOP"]),
    ("PUNGA DE SANGE", "blood bag transfusion", "Pungă flexibilă cu lichid roșu", "Se păstrează la frigider special", "Din ea se face transfuzia", ["PERFUZIE", "PUNGA CU GHEATA", "EPRUBETA"]),
    ("STATIV DE PERFUZIE", "IV pole stand hospital", "Un suport înalt pe roți", "Are cârlige în vârf", "De el se agață punga de perfuzie", ["PERFUZIE", "INJECTOMAT", "PAT DE SPITAL"]),
    ("AMBULANTA", "ambulance", "Vehicul cu girofar", "Are sirenă și cruce pe caroserie", "Mașina care duce bolnavii la urgență", ["TARGA", "ELICOPTER SMURD", "MASINA DE POLITIE"]),
    ("TRUSA DE PRIM AJUTOR", "first aid kit", "O cutie cu cruce pe capac", "Obligatorie în orice mașină", "Conține plasturi, fașă și dezinfectant", ["GEANTA MEDICALA", "AUTOCLAV", "CUTIE PETRI"]),
    ("VATA", "cotton wool medical", "Albă și pufoasă", "Se îmbibă cu spirt", "Se pune pe braț după injecție", ["COMPRESA STERILA", "BANDAJ", "PLASTURE"]),
    ("LEUCOPLAST", "medical adhesive tape roll", "Vine în rolă, se rupe ușor", "Lipicios pe o parte", "Cu el se fixează pansamentul pe piele", ["PLASTURE", "BANDAJ", "FIR DE SUTURA"]),
    ("APASATOR DE LIMBA", "tongue depressor", "Un bețișor lat de lemn", "Doctorul îți spune să zici «aaa»", "Ține limba jos ca să se vadă gâtul", ["CIOCAN DE REFLEXE", "PENSETA", "SPECULUM"]),
    ("APARAT DE DIALIZA", "dialysis machine", "Pacientul stă conectat ore întregi", "Sângele trece prin el și se întoarce curat", "Înlocuiește rinichii bolnavi", ["APARAT RMN", "VENTILATOR MEDICAL", "INJECTOMAT"]),
    ("PROTEZA DENTARA", "dentures false teeth", "Se scoate noaptea într-un pahar", "Înlocuiește ceva pierdut", "Dinții falși ai bunicilor", ["APARAT DENTAR", "PROTEZA DE SOLD", "IMPLANT DENTAR"]),
    ("APARAT DENTAR", "dental braces teeth", "Se poartă ani de zile pe dinți", "Are sârme și bracketuri", "Îndreaptă dinții strâmbi", ["PROTEZA DENTARA", "FREZA DENTARA", "IMPLANT DENTAR"]),
    ("SCAUN STOMATOLOGIC", "dental chair", "Se lasă pe spate electric", "Are lampă și tăviță cu instrumente", "În el stai la dentist", ["MASA DE OPERATIE", "PAT DE SPITAL", "SCAUN CU ROTILE"]),
    ("FREZA DENTARA", "dental drill", "Scoate un sunet ascuțit temut", "Se rotește foarte repede", "Cu ea dentistul curăță caria", ["BISTURIU", "APARAT DENTAR", "PENSETA"]),
    ("APARAT DE RADIOGRAFIE", "X-ray machine hospital", "Vezi oasele cu el", "Folosește radiații", "Face poza alb-negru a scheletului", ["COMPUTER TOMOGRAF", "APARAT RMN", "MAMOGRAF"]),
    ("MAMOGRAF", "mammography machine", "Aparat de screening", "Folosit doar pentru o zonă a corpului", "Depistează cancerul de sân", ["ECOGRAF", "APARAT DE RADIOGRAFIE", "COMPUTER TOMOGRAF"]),
    ("SPIROMETRU", "spirometer lung test", "Sufli în el cât de tare poți", "Măsoară aerul expirat", "Testează capacitatea plămânilor", ["PULSOXIMETRU", "NEBULIZATOR", "ELECTROCARDIOGRAF"]),
    ("CANTAR MEDICAL", "medical scale weight", "Te urci pe el la control", "Adesea are și tijă de înălțime", "Măsoară greutatea corporală", ["TENSIOMETRU", "TALIOMETRU", "GLUCOMETRU"]),
    ("HOLTER", "Holter monitor heart", "Îl porți acasă 24 de ore", "Mic aparat prins de curea cu electrozi", "Înregistrează inima o zi întreagă", ["ELECTROCARDIOGRAF", "PULSOXIMETRU", "STIMULATOR CARDIAC"]),
    ("STIMULATOR CARDIAC", "artificial pacemaker", "Se implantează sub piele", "Funcționează pe baterie ani de zile", "Dă ritm inimii leneșe — pacemaker", ["DEFIBRILATOR", "STENT", "HOLTER"]),
    ("STENT", "coronary stent", "O plasă metalică minusculă", "Se montează prin cateter", "Ține artera inimii deschisă", ["STIMULATOR CARDIAC", "PROTEZA DE SOLD", "BRANULA"]),
    ("PROTEZA DE SOLD", "hip replacement prosthesis", "Din titan sau ceramică", "Se pune la operația de șold", "Înlocuiește articulația uzată", ["STENT", "PROTEZA DENTARA", "ORTEZA"]),
    ("APARAT AUDITIV", "hearing aid", "Mic, se poartă la ureche", "Are baterie și microfon", "Amplifică sunetele pentru cei care nu aud", ["IMPLANT COHLEAR", "OTOSCOP", "CASTI MEDICALE"]),
    ("OCHELARI DE VEDERE", "eyeglasses", "Se poartă pe nas", "Au lentile cu dioptrii", "Corectează miopia", ["LENTILE DE CONTACT", "OCHELARI DE PROTECTIE", "OFTALMOSCOP"]),
    ("LENTILE DE CONTACT", "contact lenses", "Aproape invizibile", "Se pun direct pe ochi", "Alternativa la ochelari", ["OCHELARI DE VEDERE", "OCHELARI DE PROTECTIE", "LAMA DE MICROSCOP"]),
    ("ELECTROZI EKG", "ECG electrodes chest", "Mici discuri lipicioase", "Se lipesc pe piept", "Prin ei se face electrocardiograma", ["ELECTROCARDIOGRAF", "HOLTER", "DEFIBRILATOR"]),
    ("GEL DE ECOGRAFIE", "ultrasound gel", "Rece și lipicios", "Se întinde pe burtă", "Fără el sonda ecografului nu vede", ["DEZINFECTANT", "APA OXIGENATA", "VATA"]),
    ("TERMOMETRU INFRAROSU", "infrared thermometer forehead", "Nu atinge pielea", "Se îndreaptă spre frunte", "Măsoară febra de la distanță", ["TERMOMETRU", "PULSOXIMETRU", "TENSIOMETRU"]),
    ("DEZINFECTANT", "hand sanitizer bottle", "Lichid sau gel cu miros de alcool", "Omoară microbii", "Îl folosești pe mâini la intrarea în spital", ["APA OXIGENATA", "GEL DE ECOGRAFIE", "SER FIZIOLOGIC"]),
    ("APA OXIGENATA", "hydrogen peroxide bottle", "Face spumă albă pe rană", "Sticluță din farmacie", "Cu ea se curăță rănile", ["DEZINFECTANT", "SER FIZIOLOGIC", "BETADINA"]),
    ("COMPRESA STERILA", "sterile gauze compress", "Pătrățele albe împachetate", "Din tifon steril", "Se pune direct pe rană sub bandaj", ["VATA", "PLASTURE", "BANDAJ"]),
    ("BONETA CHIRURGICALA", "surgical cap", "Se poartă pe cap", "Acoperă tot părul", "O poartă chirurgii în sală", ["MASCA CHIRURGICALA", "HALAT MEDICAL", "MANUSI CHIRURGICALE"]),
    ("OCHELARI DE PROTECTIE", "safety goggles medical", "Acoperă complet ochii", "Din plastic transparent", "Protejează ochii de stropi în laborator", ["OCHELARI DE VEDERE", "LENTILE DE CONTACT", "MASCA CHIRURGICALA"]),
    ("SPECULUM", "medical speculum", "Instrument de examinare", "Deschide și ține deschis", "Îl folosește ginecologul la consult", ["APASATOR DE LIMBA", "PENSETA", "LARINGOSCOP"]),
    ("LAMA DE MICROSCOP", "microscope slide", "Dreptunghi subțire de sticlă", "Pe ea se pune proba", "Se așază sub obiectivul microscopului", ["CUTIE PETRI", "EPRUBETA", "PIPETA"]),
    ("DOPPLER FETAL", "fetal doppler", "Aparat mic cu difuzor", "Se plimbă pe burtica gravidei", "Cu el se aude inima bebelușului", ["ECOGRAF", "STETOSCOP", "MONITOR FUNCTII VITALE"]),
    ("PULVERIZATOR NAZAL", "nasal spray bottle", "Flacon mic cu duză", "Se introduce în nară", "Din el se pulverizează medicament în nas", ["INHALATOR", "NEBULIZATOR", "PIPETA"]),
    ("ACE DE ACUPUNCTURA", "acupuncture needles", "Foarte subțiri și lungi", "Se înfig puțin în piele", "Terapie tradițională chinezească", ["AC DE SUTURA", "SERINGA", "BRANULA"]),
    ("TEST RAPID COVID", "rapid antigen test covid", "O casetă mică de plastic", "Aștepți 15 minute liniile", "Două linii înseamnă pozitiv", ["GLUCOMETRU", "TEST DE SARCINA", "EPRUBETA"]),
    ("TERMOFOR", "hot water bottle", "Se umple cu apă caldă", "Din cauciuc, cu dop", "Îl pui pe burtă când te doare", ["PUNGA CU GHEATA", "PERNA ELECTRICA", "COMPRESA STERILA"]),
    ("PUNGA CU GHEATA", "ice pack injury", "Foarte rece", "Se pune pe umflături", "Prim ajutor la entorse", ["TERMOFOR", "PUNGA DE SANGE", "COMPRESA STERILA"]),
    ("ORTEZA", "knee brace orthosis", "Se poartă pe articulație", "Cu arici și atele flexibile", "Susține genunchiul după accidentare", ["GHIPS", "ATELA", "GULER CERVICAL"]),
    ("CADRU DE MERS", "walking frame walker", "Din aluminiu ușor, cu patru picioare", "Îl ții în fața ta și pășești", "Sprijin la mers pentru vârstnici", ["CARJE", "BASTON", "SCAUN CU ROTILE"]),
    ("BASTON", "walking cane stick", "Simplu, cu mâner curbat", "Se ține într-o singură mână", "Sprijinul clasic al bunicului la plimbare", ["CARJE", "CADRU DE MERS", "ATELA"]),
    ("LAMPA DE FOTOTERAPIE", "phototherapy lamp jaundice baby", "Emite lumină albastră", "Se pune deasupra bebelușilor", "Tratează icterul nou-născuților", ["LAMPA CHIRURGICALA", "INCUBATOR NEONATAL", "LAMPA UV"]),
    ("EPIPEN", "epinephrine auto-injector EpiPen", "Ca un pix gros", "Se înfige în coapsă în urgență", "Salvează viața la șoc alergic", ["SERINGA", "INJECTOMAT", "INHALATOR"]),
]

# id_prefix, prag index sub care dificultatea e "usor" (peste -> "mediu"),
# culoare_tema, descriere, imagine_sursa, ITEMS, daca JSON-ul include
# "version"/"limba" (doar aplicatii le avea in scriptul original).
CATEGORII = {
    "aplicatii": dict(prefix="apl", prag_usor=30, culoare="#4C6FFF", descriere="Aplicatii de telefon", sursa="wikimedia", items=APLICATII_ITEMS, versioned=True),
    "mecanica": dict(prefix="mec", prag_usor=50, culoare="#E0A62B", descriere="Piese si scule auto", sursa="wikipedia", items=MECANICA_ITEMS, versioned=False),
    "medical": dict(prefix="med", prag_usor=50, culoare="#2EC4B6", descriere="Obiecte medicale", sursa="wikipedia", items=MEDICAL_ITEMS, versioned=False),
}


def build(categorie_id):
    cfg = CATEGORII[categorie_id]
    intrebari = []
    for i, (answer, search, h1, h2, h3, wrongs) in enumerate(cfg["items"], start=1):
        intrebari.append({
            "id": f"{cfg['prefix']}_{i:03d}",
            "raspuns": answer,
            "variante": [answer] + wrongs,
            "hint_1": h1,
            "hint_2": h2,
            "hint_3": h3,
            "dificultate": "usor" if i <= cfg["prag_usor"] else "mediu",
            "puncte_max": 200,
            "imagine_cautare": search,
            "imagine_sursa": cfg["sursa"],
        })

    data = {"categorii": {categorie_id: {
        "mod": "4_variante",
        "culoare_tema": cfg["culoare"],
        "descriere": cfg["descriere"],
        "intrebari": intrebari,
    }}}
    if cfg["versioned"]:
        data = {"version": "1.0", "limba": "ro", **data}

    out = f"assets/continut/{categorie_id}/intrebari.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Scris {out} cu {len(intrebari)} intrebari")

    answers = [it[0] for it in cfg["items"]]
    dupes = {a for a in answers if answers.count(a) > 1}
    if dupes:
        print(f"ATENTIE [{categorie_id}], raspunsuri duplicate:", dupes)


def main():
    targets = sys.argv[1:] or list(CATEGORII)
    for categorie_id in targets:
        build(categorie_id)


if __name__ == "__main__":
    main()
