"""Generează assets/continut/medical/intrebari.json — gamemode cu obiecte medicale.

Fiecare item: (raspuns, termen_cautare_imagine_EN, hint1, hint2, hint3, [3 variante gresite])
Rulare: python tools/generate_medical_questions.py
"""
import json
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ITEMS = [
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


def build():
    intrebari = []
    for i, (answer, search, h1, h2, h3, wrongs) in enumerate(ITEMS, start=1):
        qid = f"med_{i:03d}"
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
            "medical": {
                "mod": "4_variante",
                "culoare_tema": "#2EC4B6",
                "descriere": "Obiecte medicale",
                "intrebari": intrebari,
            }
        }
    }

    out = "assets/continut/medical/intrebari.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Scris {out} cu {len(intrebari)} intrebari")

    answers = [it[0] for it in ITEMS]
    dupes = {a for a in answers if answers.count(a) > 1}
    if dupes:
        print("ATENTIE, raspunsuri duplicate:", dupes)


if __name__ == "__main__":
    build()
