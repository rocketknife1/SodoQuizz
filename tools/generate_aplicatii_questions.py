"""Genereaza assets/continut/aplicatii/intrebari.json - gamemode cu aplicatii de telefon.

Nu contine YouTube, Instagram, Facebook, Netflix, Spotify, Twitter, TikTok,
WhatsApp, Uber, LinkedIn, Snapchat, Discord, Twitch, Steam, Zoom, Slack,
Dropbox, WordPress, Shopify, GitHub, Uber Eats, Glovo, Booking, TripAdvisor,
Duolingo, Pinterest, Reddit, Wikipedia, OpenAI, Canva, Figma, Amazon, Google,
Microsoft, PayPal - astea exista deja in categoria "logouri".

Fiecare item: (raspuns, termen_cautare_imagine_EN, hint1, hint2, hint3, [3 variante gresite])
Rulare: python tools/generate_aplicatii_questions.py
"""
import json
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ITEMS = [
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


def build():
    intrebari = []
    for i, (answer, search, h1, h2, h3, wrongs) in enumerate(ITEMS, start=1):
        qid = f"apl_{i:03d}"
        variante = [answer] + wrongs
        intrebari.append({
            "id": qid,
            "raspuns": answer,
            "variante": variante,
            "hint_1": h1,
            "hint_2": h2,
            "hint_3": h3,
            "dificultate": "usor" if i <= 30 else "mediu",
            "puncte_max": 200,
            "imagine_cautare": search,
            "imagine_sursa": "wikimedia",
        })

    data = {
        "version": "1.0",
        "limba": "ro",
        "categorii": {
            "aplicatii": {
                "mod": "4_variante",
                "culoare_tema": "#4C6FFF",
                "descriere": "Aplicatii de telefon",
                "intrebari": intrebari,
            }
        }
    }

    out = "assets/continut/aplicatii/intrebari.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Scris {out} cu {len(intrebari)} intrebari")

    answers = [it[0] for it in ITEMS]
    dupes = {a for a in answers if answers.count(a) > 1}
    if dupes:
        print("ATENTIE, raspunsuri duplicate:", dupes)


if __name__ == "__main__":
    build()
