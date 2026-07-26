/// Întrebare de cultură generală — text simplu, fără imagine, 4 variante.
/// Folosită doar de [CultureQuizPanel] de pe Home, nu de GameScreen.
class CultureQuestion {
  final String question;
  final List<String> choices;
  final String answer;

  const CultureQuestion({
    required this.question,
    required this.choices,
    required this.answer,
  });
}

/// O categorie de cultură generală (țară) — fiecare are propriul pool de
/// [cultureQuizQuestionCount] întrebări din care [CultureQuizPanel] alege
/// aleatoriu un lot. Adaugă o intrare nouă aici ca să apară automat în
/// selectorul "Categorii" de pe Home.
class CultureCategory {
  final String id;
  final String title;
  final String flag;
  final List<CultureQuestion> questions;

  const CultureCategory({
    required this.id,
    required this.title,
    required this.flag,
    required this.questions,
  });
}

const int cultureQuizQuestionCount = 10;
const int cultureSecondsPerQuestion = 8;

const List<CultureQuestion> _cultureQuestionsRomania = [
  CultureQuestion(
    question: 'Care este satelitul natural al Pământului?',
    choices: ['Luna', 'Marte', 'Venus', 'Titan'],
    answer: 'Luna',
  ),
  CultureQuestion(
    question: 'Aproximativ cât la sută din corpul uman este apă?',
    choices: ['30%', '60%', '90%', '45%'],
    answer: '60%',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare ocean de pe Glob?',
    choices: ['Atlantic', 'Pacific', 'Indian', 'Arctic'],
    answer: 'Pacific',
  ),
  CultureQuestion(
    question: 'Cine a pictat Mona Lisa?',
    choices: ['Michelangelo', 'Rafael', 'Leonardo da Vinci', 'Picasso'],
    answer: 'Leonardo da Vinci',
  ),
  CultureQuestion(
    question: 'Care este capitala Franței?',
    choices: ['Londra', 'Paris', 'Berlin', 'Madrid'],
    answer: 'Paris',
  ),
  CultureQuestion(
    question: 'Care este cel mai înalt munte din lume?',
    choices: ['K2', 'Kilimanjaro', 'Mont Blanc', 'Everest'],
    answer: 'Everest',
  ),
  CultureQuestion(
    question: 'Câte oase are, în medie, corpul uman adult?',
    choices: ['186', '206', '226', '246'],
    answer: '206',
  ),
  CultureQuestion(
    question: 'Care este simbolul chimic al aurului?',
    choices: ['Ag', 'Fe', 'Au', 'Pb'],
    answer: 'Au',
  ),
  CultureQuestion(
    question: 'Care este capitala Italiei?',
    choices: ['Milano', 'Roma', 'Napoli', 'Torino'],
    answer: 'Roma',
  ),
  CultureQuestion(
    question: 'Care este considerat cel mai lung fluviu din lume?',
    choices: ['Amazonul', 'Nilul', 'Dunărea', 'Mississippi'],
    answer: 'Nilul',
  ),
  CultureQuestion(
    question: 'Care planetă este supranumită "Planeta Roșie"?',
    choices: ['Venus', 'Jupiter', 'Marte', 'Saturn'],
    answer: 'Marte',
  ),
  CultureQuestion(
    question: 'Cine a scris poemul "Luceafărul"?',
    choices: ['Mihai Eminescu', 'George Coșbuc', 'Vasile Alecsandri', 'Nichita Stănescu'],
    answer: 'Mihai Eminescu',
  ),
  CultureQuestion(
    question: 'În ce an a avut loc Marea Unire a României?',
    choices: ['1859', '1918', '1877', '1945'],
    answer: '1918',
  ),
  CultureQuestion(
    question: 'Care este cea mai mare planetă din Sistemul Solar?',
    choices: ['Saturn', 'Neptun', 'Jupiter', 'Uranus'],
    answer: 'Jupiter',
  ),
  CultureQuestion(
    question: 'Care este capitala Japoniei?',
    choices: ['Osaka', 'Kyoto', 'Tokyo', 'Hiroshima'],
    answer: 'Tokyo',
  ),
  CultureQuestion(
    question: 'Cine a scris "Amintiri din copilărie"?',
    choices: ['Ion Creangă', 'Mihail Sadoveanu', 'I.L. Caragiale', 'Marin Preda'],
    answer: 'Ion Creangă',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare mamifer de pe Pământ?',
    choices: ['Elefantul african', 'Balena albastră', 'Girafa', 'Ursul polar'],
    answer: 'Balena albastră',
  ),
  CultureQuestion(
    question: 'Care este cel mai adânc punct cunoscut din oceane?',
    choices: ['Groapa Marianelor', 'Fosa Tonga', 'Groapa Java', 'Fosa Peru-Chile'],
    answer: 'Groapa Marianelor',
  ),
  CultureQuestion(
    question: 'Care planetă este cea mai apropiată de Soare?',
    choices: ['Venus', 'Mercur', 'Marte', 'Pământul'],
    answer: 'Mercur',
  ),
  CultureQuestion(
    question: 'Cui îi este atribuită invenția becului electric?',
    choices: ['Nikola Tesla', 'Thomas Edison', 'Alexander Bell', 'Isaac Newton'],
    answer: 'Thomas Edison',
  ),
  CultureQuestion(
    question: 'Care este capitala Marii Britanii?',
    choices: ['Manchester', 'Liverpool', 'Londra', 'Edinburgh'],
    answer: 'Londra',
  ),
  CultureQuestion(
    question: 'Care este cel mai rapid animal terestru?',
    choices: ['Leul', 'Ghepardul', 'Antilopa', 'Calul'],
    answer: 'Ghepardul',
  ),
  CultureQuestion(
    question: 'Pe ce fluviu se află barajul Porțile de Fier?',
    choices: ['Oltul', 'Prutul', 'Dunărea', 'Siretul'],
    answer: 'Dunărea',
  ),
  CultureQuestion(
    question: 'Care este capitala Spaniei?',
    choices: ['Barcelona', 'Sevilla', 'Valencia', 'Madrid'],
    answer: 'Madrid',
  ),
  CultureQuestion(
    question: 'Cine a compus "Rapsodia Română"?',
    choices: ['George Enescu', 'Ciprian Porumbescu', 'Dinu Lipatti', 'Gheorghe Zamfir'],
    answer: 'George Enescu',
  ),
  CultureQuestion(
    question: 'Ce vitamină produce corpul expus la soare?',
    choices: ['Vitamina A', 'Vitamina C', 'Vitamina D', 'Vitamina B12'],
    answer: 'Vitamina D',
  ),
  CultureQuestion(
    question: 'Care este capitala Germaniei?',
    choices: ['Munchen', 'Hamburg', 'Berlin', 'Frankfurt'],
    answer: 'Berlin',
  ),
  CultureQuestion(
    question: 'Cine a fost primul om care a pășit pe Lună?',
    choices: ['Buzz Aldrin', 'Yuri Gagarin', 'Neil Armstrong', 'Michael Collins'],
    answer: 'Neil Armstrong',
  ),
  CultureQuestion(
    question: 'Ce limbă are cei mai mulți vorbitori nativi din lume?',
    choices: ['Engleza', 'Spaniola', 'Chineza', 'Hindi'],
    answer: 'Chineza',
  ),
  CultureQuestion(
    question: 'Câte planete are Sistemul Solar?',
    choices: ['7', '8', '9', '10'],
    answer: '8',
  ),
  CultureQuestion(
    question: 'Cine a scris "Romeo și Julieta"?',
    choices: ['Charles Dickens', 'William Shakespeare', 'Victor Hugo', 'Molière'],
    answer: 'William Shakespeare',
  ),
  CultureQuestion(
    question: 'Care este cel mai înalt vârf muntos din România?',
    choices: ['Omu', 'Negoiu', 'Moldoveanu', 'Parângul Mare'],
    answer: 'Moldoveanu',
  ),
  CultureQuestion(
    question: 'Care este capitala Statelor Unite ale Americii?',
    choices: ['New York', 'Los Angeles', 'Washington D.C.', 'Chicago'],
    answer: 'Washington D.C.',
  ),
  CultureQuestion(
    question: 'La ce mare are ieșire România?',
    choices: ['Marea Mediterană', 'Marea Baltică', 'Marea Neagră', 'Marea Adriatică'],
    answer: 'Marea Neagră',
  ),
  CultureQuestion(
    question: 'Cine a pictat tavanul Capelei Sixtine?',
    choices: ['Leonardo da Vinci', 'Michelangelo', 'Rafael', 'Botticelli'],
    answer: 'Michelangelo',
  ),
  CultureQuestion(
    question: 'Care este viteza aproximativă a luminii în vid?',
    choices: ['300.000 km/s', '150.000 km/s', '30.000 km/s', '3.000.000 km/s'],
    answer: '300.000 km/s',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare organ al corpului uman?',
    choices: ['Ficatul', 'Creierul', 'Pielea', 'Plămânii'],
    answer: 'Pielea',
  ),
  CultureQuestion(
    question: 'Care este capitala Rusiei?',
    choices: ['Sankt Petersburg', 'Moscova', 'Kiev', 'Minsk'],
    answer: 'Moscova',
  ),
  CultureQuestion(
    question: 'Care este capitala Egiptului?',
    choices: ['Alexandria', 'Cairo', 'Luxor', 'Giza'],
    answer: 'Cairo',
  ),
  CultureQuestion(
    question: 'Care este cea mai mare țară din lume ca suprafață?',
    choices: ['Canada', 'China', 'Rusia', 'SUA'],
    answer: 'Rusia',
  ),
  CultureQuestion(
    question: 'Cum se numește galaxia în care se află Sistemul Solar?',
    choices: ['Andromeda', 'Calea Lactee', 'Triunghiul', 'Omega Centauri'],
    answer: 'Calea Lactee',
  ),
  CultureQuestion(
    question: 'Care este unitatea de măsură pentru distanțe astronomice mari?',
    choices: ['Kilometrul', 'Anul-lumină', 'Mila marină', 'Parsecul'],
    answer: 'Anul-lumină',
  ),
  CultureQuestion(
    question: 'Ce organ produce insulina?',
    choices: ['Ficatul', 'Rinichiul', 'Pancreasul', 'Splina'],
    answer: 'Pancreasul',
  ),
  CultureQuestion(
    question: 'Ce tip de celule transportă oxigenul în sânge?',
    choices: ['Globulele albe', 'Trombocitele', 'Globulele roșii', 'Neuronii'],
    answer: 'Globulele roșii',
  ),
  CultureQuestion(
    question: 'Câte elemente chimice are, aproximativ, tabelul periodic?',
    choices: ['~90', '~118', '~150', '~200'],
    answer: '~118',
  ),
  CultureQuestion(
    question: 'Cine a formulat teoria relativității?',
    choices: ['Isaac Newton', 'Albert Einstein', 'Niels Bohr', 'Galileo Galilei'],
    answer: 'Albert Einstein',
  ),
  CultureQuestion(
    question: 'Cine a descoperit legea gravitației universale?',
    choices: ['Albert Einstein', 'Isaac Newton', 'Nikola Tesla', 'Charles Darwin'],
    answer: 'Isaac Newton',
  ),
  CultureQuestion(
    question: 'Cine a dezvoltat teoria evoluției prin selecție naturală?',
    choices: ['Gregor Mendel', 'Charles Darwin', 'Louis Pasteur', 'Alexander Fleming'],
    answer: 'Charles Darwin',
  ),
  CultureQuestion(
    question: 'Cine a descoperit penicilina?',
    choices: ['Louis Pasteur', 'Alexander Fleming', 'Marie Curie', 'Robert Koch'],
    answer: 'Alexander Fleming',
  ),
  CultureQuestion(
    question: 'Cine a pictat "Noaptea înstelată"?',
    choices: ['Claude Monet', 'Vincent van Gogh', 'Pablo Picasso', 'Salvador Dalí'],
    answer: 'Vincent van Gogh',
  ),
  CultureQuestion(
    question: 'Cine a compus "Simfonia a 9-a"?',
    choices: ['Wolfgang Amadeus Mozart', 'Ludwig van Beethoven', 'Johann Sebastian Bach', 'Frédéric Chopin'],
    answer: 'Ludwig van Beethoven',
  ),
  CultureQuestion(
    question: 'Cine a scris piesa "O scrisoare pierdută"?',
    choices: ['Ion Luca Caragiale', 'Ion Creangă', 'Mihail Sadoveanu', 'Marin Preda'],
    answer: 'Ion Luca Caragiale',
  ),
  CultureQuestion(
    question: 'Cine a fost primul domnitor care a unit Moldova și Țara Românească?',
    choices: ['Ștefan cel Mare', 'Mihai Viteazul', 'Alexandru Ioan Cuza', 'Vlad Țepeș'],
    answer: 'Mihai Viteazul',
  ),
  CultureQuestion(
    question: 'În ce an a început Primul Război Mondial?',
    choices: ['1912', '1914', '1916', '1918'],
    answer: '1914',
  ),
  CultureQuestion(
    question: 'În ce an s-a încheiat Al Doilea Război Mondial?',
    choices: ['1943', '1944', '1945', '1946'],
    answer: '1945',
  ),
  CultureQuestion(
    question: 'Cine a descoperit America în 1492?',
    choices: ['Vasco da Gama', 'Cristofor Columb', 'Fernando Magellan', 'Marco Polo'],
    answer: 'Cristofor Columb',
  ),
  CultureQuestion(
    question: 'Ce echipă a câștigat cele mai multe Cupe Mondiale la fotbal?',
    choices: ['Germania', 'Argentina', 'Brazilia', 'Italia'],
    answer: 'Brazilia',
  ),
  CultureQuestion(
    question: 'Cine este considerat fondatorul Microsoft?',
    choices: ['Steve Jobs', 'Bill Gates', 'Mark Zuckerberg', 'Elon Musk'],
    answer: 'Bill Gates',
  ),
  CultureQuestion(
    question: 'Cine a co-fondat Apple alături de Steve Jobs?',
    choices: ['Steve Wozniak', 'Bill Gates', 'Jeff Bezos', 'Larry Page'],
    answer: 'Steve Wozniak',
  ),
  CultureQuestion(
    question: 'Care a fost primul telefon mobil comercial din lume?',
    choices: ['Nokia 3310', 'Motorola DynaTAC', 'iPhone', 'Samsung Galaxy'],
    answer: 'Motorola DynaTAC',
  ),
  CultureQuestion(
    question: 'Câte continente are Pământul?',
    choices: ['5', '6', '7', '8'],
    answer: '7',
  ),
  CultureQuestion(
    question: 'Câte zile are un an bisect?',
    choices: ['365', '364', '366', '367'],
    answer: '366',
  ),
  CultureQuestion(
    question: 'Câte minute are o oră și jumătate?',
    choices: ['80', '90', '100', '120'],
    answer: '90',
  ),
  CultureQuestion(
    question: 'Ce gaz este esențial pentru respirația omului?',
    choices: ['Azot', 'Oxigen', 'Hidrogen', 'Heliu'],
    answer: 'Oxigen',
  ),
  CultureQuestion(
    question: 'În ce țară se află Turnul Eiffel?',
    choices: ['Italia', 'Belgia', 'Franța', 'Elveția'],
    answer: 'Franța',
  ),
  CultureQuestion(
    question: 'Care este moneda oficială a României?',
    choices: ['Euro', 'Leul', 'Forintul', 'Leva'],
    answer: 'Leul',
  ),
  CultureQuestion(
    question: 'Câte culori are curcubeul?',
    choices: ['5', '6', '7', '9'],
    answer: '7',
  ),
  CultureQuestion(
    question: 'Ce gaz predomină în atmosfera Pământului?',
    choices: ['Oxigenul', 'Dioxidul de carbon', 'Azotul', 'Argonul'],
    answer: 'Azotul',
  ),
  CultureQuestion(
    question: 'Ce râu trece prin București?',
    choices: ['Dâmbovița', 'Argeșul', 'Oltul', 'Mureșul'],
    answer: 'Dâmbovița',
  ),
  CultureQuestion(
    question: 'Câte zile are februarie într-un an obișnuit (nebisect)?',
    choices: ['27', '28', '29', '30'],
    answer: '28',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare deșert cald din lume?',
    choices: ['Gobi', 'Sahara', 'Kalahari', 'Atacama'],
    answer: 'Sahara',
  ),
  CultureQuestion(
    question: 'Câte picioare are un păianjen?',
    choices: ['6', '8', '10', '12'],
    answer: '8',
  ),
  CultureQuestion(
    question: 'Ce substanță are formula chimică H2O?',
    choices: ['Sarea', 'Apa', 'Zahărul', 'Oțetul'],
    answer: 'Apa',
  ),
  CultureQuestion(
    question: 'În ce oraș se află Colosseumul?',
    choices: ['Atena', 'Roma', 'Istanbul', 'Cairo'],
    answer: 'Roma',
  ),
  CultureQuestion(
    question: 'Ce animal este supranumit "regele junglei"?',
    choices: ['Tigrul', 'Leul', 'Elefantul', 'Gorila'],
    answer: 'Leul',
  ),
  CultureQuestion(
    question: 'Câte luni ale anului au 31 de zile?',
    choices: ['5', '6', '7', '8'],
    answer: '7',
  ),
  CultureQuestion(
    question: 'Ce organ pompează sângele în corpul uman?',
    choices: ['Plămânii', 'Ficatul', 'Inima', 'Rinichii'],
    answer: 'Inima',
  ),
  CultureQuestion(
    question: 'În ce an a căzut regimul comunist în România?',
    choices: ['1987', '1989', '1991', '1993'],
    answer: '1989',
  ),
  CultureQuestion(
    question: 'Cum se numește cea mai mică unitate a unui element chimic?',
    choices: ['Molecula', 'Atomul', 'Celula', 'Electronul'],
    answer: 'Atomul',
  ),
  CultureQuestion(
    question: 'Câte corzi are o vioară?',
    choices: ['3', '4', '5', '6'],
    answer: '4',
  ),
  CultureQuestion(
    question: 'Din ce cereală se face în mod tradițional pâinea?',
    choices: ['Porumb', 'Orez', 'Grâu', 'Ovăz'],
    answer: 'Grâu',
  ),
  CultureQuestion(
    question: 'Care este capitala Chinei?',
    choices: ['Shanghai', 'Hong Kong', 'Beijing', 'Guangzhou'],
    answer: 'Beijing',
  ),
  CultureQuestion(
    question: 'Care este capitala Canadei?',
    choices: ['Toronto', 'Vancouver', 'Montreal', 'Ottawa'],
    answer: 'Ottawa',
  ),
  CultureQuestion(
    question: 'Care este capitala Australiei?',
    choices: ['Sydney', 'Melbourne', 'Canberra', 'Perth'],
    answer: 'Canberra',
  ),
  CultureQuestion(
    question: 'Care este capitala Greciei?',
    choices: ['Salonic', 'Atena', 'Corint', 'Sparta'],
    answer: 'Atena',
  ),
  CultureQuestion(
    question: 'Care este capitala Portugaliei?',
    choices: ['Porto', 'Lisabona', 'Faro', 'Braga'],
    answer: 'Lisabona',
  ),
  CultureQuestion(
    question: 'Care este capitala Turciei?',
    choices: ['Istanbul', 'Izmir', 'Ankara', 'Antalya'],
    answer: 'Ankara',
  ),
  CultureQuestion(
    question: 'Care este capitala Olandei?',
    choices: ['Rotterdam', 'Haga', 'Amsterdam', 'Utrecht'],
    answer: 'Amsterdam',
  ),
  CultureQuestion(
    question: 'Care este capitala Austriei?',
    choices: ['Salzburg', 'Graz', 'Viena', 'Innsbruck'],
    answer: 'Viena',
  ),
  CultureQuestion(
    question: 'Care este capitala Ungariei?',
    choices: ['Debrecen', 'Budapesta', 'Szeged', 'Pécs'],
    answer: 'Budapesta',
  ),
  CultureQuestion(
    question: 'Care este capitala Poloniei?',
    choices: ['Cracovia', 'Varșovia', 'Gdansk', 'Wroclaw'],
    answer: 'Varșovia',
  ),
  CultureQuestion(
    question: 'Care este capitala Braziliei?',
    choices: ['Rio de Janeiro', 'São Paulo', 'Brasília', 'Salvador'],
    answer: 'Brasília',
  ),
  CultureQuestion(
    question: 'Care este capitala Indiei?',
    choices: ['Mumbai', 'New Delhi', 'Bangalore', 'Calcutta'],
    answer: 'New Delhi',
  ),
  CultureQuestion(
    question: 'Care este cel mai mic continent?',
    choices: ['Europa', 'Australia (Oceania)', 'Antarctica', 'America de Sud'],
    answer: 'Australia (Oceania)',
  ),
  CultureQuestion(
    question: 'Care este cel mai populat oraș din lume?',
    choices: ['New York', 'Tokyo', 'Shanghai', 'Delhi'],
    answer: 'Tokyo',
  ),
  CultureQuestion(
    question: 'Pe ce continent se află Egiptul?',
    choices: ['Asia', 'Africa', 'Europa', 'America de Sud'],
    answer: 'Africa',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare lac de pe glob?',
    choices: ['Lacul Superior', 'Marea Caspică', 'Lacul Victoria', 'Lacul Baikal'],
    answer: 'Marea Caspică',
  ),
  CultureQuestion(
    question: 'Câte oceane există pe Pământ?',
    choices: ['3', '4', '5', '6'],
    answer: '5',
  ),
  CultureQuestion(
    question: 'Care este cea mai lungă catenă muntoasă din lume?',
    choices: ['Himalaya', 'Alpii', 'Anzii', 'Munții Stâncoși'],
    answer: 'Anzii',
  ),
  CultureQuestion(
    question: 'Care este cea mai mică planetă din Sistemul Solar?',
    choices: ['Marte', 'Venus', 'Mercur', 'Pluto'],
    answer: 'Mercur',
  ),
];

const List<CultureQuestion> _cultureQuestionsBelgia = [
  CultureQuestion(
    question: 'Care este capitala Belgiei?',
    choices: ['Anvers', 'Bruxelles', 'Gent', 'Bruges'],
    answer: 'Bruxelles',
  ),
  CultureQuestion(
    question: 'Cine este creatorul personajului de benzi desenate Tintin?',
    choices: ['Hergé', 'René Goscinny', 'Albert Uderzo', 'Peyo'],
    answer: 'Hergé',
  ),
  CultureQuestion(
    question: 'În ce an a avut loc bătălia de la Waterloo, în Belgia?',
    choices: ['1805', '1812', '1815', '1821'],
    answer: '1815',
  ),
  CultureQuestion(
    question: 'Cine a pictat "Coborârea de pe cruce", aflată la catedrala din Antwerpen?',
    choices: ['Rembrandt', 'Peter Paul Rubens', 'Jan van Eyck', 'Pieter Bruegel'],
    answer: 'Peter Paul Rubens',
  ),
  CultureQuestion(
    question: 'Cum se numește statuia unui băiețel, simbolul orașului Bruxelles?',
    choices: ['Manneken Pis', 'Little Julien', 'Piccolo', 'Le Gamin'],
    answer: 'Manneken Pis',
  ),
  CultureQuestion(
    question: 'Cine este considerat cel mai mare ciclist belgian din istorie, supranumit "Canibalul"?',
    choices: ['Eddy Merckx', 'Tom Boonen', 'Philippe Gilbert', 'Remco Evenepoel'],
    answer: 'Eddy Merckx',
  ),
  CultureQuestion(
    question: 'Care este cel mai înalt punct din Belgia?',
    choices: ['Signal de Botrange', 'Mont Rigi', 'Baraque Michel', 'Mont Saint-Aubert'],
    answer: 'Signal de Botrange',
  ),
  CultureQuestion(
    question: 'Cu care dintre următoarele țări NU se învecinează Belgia?',
    choices: ['Franța', 'Germania', 'Elveția', 'Olanda'],
    answer: 'Elveția',
  ),
  CultureQuestion(
    question: 'Cine a pictat tabloul "Fiul omului" (bărbat cu pălărie melon și un măr în fața feței)?',
    choices: ['Salvador Dalí', 'René Magritte', 'Paul Delvaux', 'James Ensor'],
    answer: 'René Magritte',
  ),
  CultureQuestion(
    question: 'Care sunt cele trei regiuni oficiale ale Belgiei?',
    choices: ['Flandra, Valonia și Bruxelles-Capitală', 'Nord, Sud și Est', 'Anvers, Gent și Bruges', 'Flandra, Ardeni și Bruxelles'],
    answer: 'Flandra, Valonia și Bruxelles-Capitală',
  ),
  CultureQuestion(
    question: 'Ce fel de mâncare este, contestat, o invenție belgiană, deși numele îi indică altă origine?',
    choices: ['Cartofii prăjiți (frites)', 'Crema brulée', 'Quiche-ul', 'Ratatouille'],
    answer: 'Cartofii prăjiți (frites)',
  ),
  CultureQuestion(
    question: 'Care era moneda oficială a Belgiei înainte de trecerea la euro?',
    choices: ['Francul belgian', 'Guldenul', 'Coroana', 'Marca'],
    answer: 'Francul belgian',
  ),
  CultureQuestion(
    question: 'Ce râu important trece prin Bruxelles?',
    choices: ['Meusa (Meuse)', 'Escaut (Scheldt)', 'Senne', 'Rin'],
    answer: 'Senne',
  ),
  CultureQuestion(
    question: 'Ce structură celebră din Bruxelles reprezintă un atom de fier mărit de 165 miliarde de ori, construită pentru Expoziția Universală din 1958?',
    choices: ['Atomium', 'Turnul Belgian', 'Cristalul', 'Sfera Europei'],
    answer: 'Atomium',
  ),
  CultureQuestion(
    question: 'Cine este regele actual al belgienilor?',
    choices: ['Albert al II-lea', 'Filip', 'Leopold al III-lea', 'Baudouin'],
    answer: 'Filip',
  ),
  CultureQuestion(
    question: 'Ce sport este cel mai popular în Belgia, cu echipa națională supranumită "Diavolii Roșii"?',
    choices: ['Baschetul', 'Fotbalul', 'Rugby-ul', 'Hocheiul'],
    answer: 'Fotbalul',
  ),
  CultureQuestion(
    question: 'Cine este creatorul benzii desenate "Lucky Luke"?',
    choices: ['Morris', 'Hergé', 'Peyo', 'André Franquin'],
    answer: 'Morris',
  ),
  CultureQuestion(
    question: 'Orașul Bruges, cunoscut pentru canale și dantelărie, se află în ce regiune a Belgiei?',
    choices: ['Flandra', 'Valonia', 'Bruxelles-Capitală', 'Ardeni'],
    answer: 'Flandra',
  ),
  CultureQuestion(
    question: 'Ce tip de bere, produsă tradițional de călugări, este o specialitate a Belgiei?',
    choices: ['Berea trapistă', 'Berea de orz', 'Berea neagră irlandeză', 'Berea de grâu germană'],
    answer: 'Berea trapistă',
  ),
  CultureQuestion(
    question: 'În ce an a obținut Belgia independența?',
    choices: ['1815', '1830', '1848', '1918'],
    answer: '1830',
  ),
  CultureQuestion(
    question: 'Care este limba oficială predominantă în regiunea Flandra?',
    choices: ['Franceza', 'Neerlandeza (olandeza)', 'Germana', 'Italiana'],
    answer: 'Neerlandeza (olandeza)',
  ),
  CultureQuestion(
    question: 'Care este limba oficială predominantă în regiunea Valonia?',
    choices: ['Neerlandeza', 'Franceza', 'Germana', 'Spaniola'],
    answer: 'Franceza',
  ),
  CultureQuestion(
    question: 'Ce alianță militară internațională își are sediul principal la Bruxelles?',
    choices: ['ONU', 'NATO', 'UNESCO', 'OMS'],
    answer: 'NATO',
  ),
  CultureQuestion(
    question: 'Cine este pictorul flamand cunoscut pentru scenele de iarnă, precum "Vânătorii în zăpadă"?',
    choices: ['Peter Paul Rubens', 'Pieter Bruegel cel Bătrân', 'Jan van Eyck', 'René Magritte'],
    answer: 'Pieter Bruegel cel Bătrân',
  ),
  CultureQuestion(
    question: 'Cum se numește piața centrală istorică a Bruxelles-ului, declarată patrimoniu UNESCO?',
    choices: ['Grote Markt', 'Grand-Place', 'Place Royale', 'Sablon'],
    answer: 'Grand-Place',
  ),
  CultureQuestion(
    question: 'Ce inventator belgian este creditat cu inventarea saxofonului?',
    choices: ['Adolphe Sax', 'Léon Theremin', 'Antoine Courtois', 'Charles Wheatstone'],
    answer: 'Adolphe Sax',
  ),
  CultureQuestion(
    question: 'Ce cântăreț și compozitor belgian celebru a scris "Ne me quitte pas"?',
    choices: ['Charles Aznavour', 'Jacques Brel', 'Serge Gainsbourg', 'Édith Piaf'],
    answer: 'Jacques Brel',
  ),
  CultureQuestion(
    question: 'Ce oraș belgian este supranumit "Veneția Nordului" datorită canalelor sale?',
    choices: ['Gent', 'Anvers', 'Bruges', 'Namur'],
    answer: 'Bruges',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare port al Belgiei și al doilea cel mai mare din Europa?',
    choices: ['Portul Bruxelles', 'Portul Anvers', 'Portul Gent', 'Portul Ostend'],
    answer: 'Portul Anvers',
  ),
  CultureQuestion(
    question: 'Orașul Anvers este cunoscut internațional pentru comerțul cu ce piatră prețioasă?',
    choices: ['Rubine', 'Diamante', 'Smaralde', 'Safire'],
    answer: 'Diamante',
  ),
  CultureQuestion(
    question: 'Kevin De Bruyne și Eden Hazard sunt fotbaliști celebri din ce țară?',
    choices: ['Olanda', 'Franța', 'Belgia', 'Germania'],
    answer: 'Belgia',
  ),
  CultureQuestion(
    question: 'Cine a fost primul rege al belgienilor, după independența din 1830?',
    choices: ['Leopold I', 'Leopold al II-lea', 'Albert I', 'Baudouin'],
    answer: 'Leopold I',
  ),
  CultureQuestion(
    question: 'Ce cursă ciclistă clasică de o zi, cunoscută drept "De Ronde", se desfășoară în Flandra?',
    choices: ['Milano–Sanremo', 'Turul Flandrei', 'Paris–Roubaix', 'Liège–Bastogne–Liège'],
    answer: 'Turul Flandrei',
  ),
  CultureQuestion(
    question: 'Ce tip de dantelă tradițională este faimoasă în orașul Bruges?',
    choices: ['Dantela de Calais', 'Dantela de Bruges', 'Dantela de Chantilly', 'Dantela venețiană'],
    answer: 'Dantela de Bruges',
  ),
  CultureQuestion(
    question: 'Care este cea mai veche universitate din Belgia, fondată în 1425?',
    choices: ['Universitatea din Gent', 'KU Leuven', 'Universitatea Liberă din Bruxelles', 'Universitatea din Liège'],
    answer: 'KU Leuven',
  ),
  CultureQuestion(
    question: 'Ce tip de vafe (gofre) belgiene este mai dens și mai dulce, originar din orașul Liège?',
    choices: ['Vafele de Bruxelles', 'Vafele de Liège', 'Vafele de Gent', 'Vafele de Namur'],
    answer: 'Vafele de Liège',
  ),
  CultureQuestion(
    question: 'Ce competiție ciclistă clasică, una dintre cele mai vechi din lume, se desfășoară în jurul orașului Liège?',
    choices: ['Liège–Bastogne–Liège', 'Milano–Sanremo', 'Amstel Gold Race', 'Gent–Wevelgem'],
    answer: 'Liège–Bastogne–Liège',
  ),
  CultureQuestion(
    question: 'Ce planetă are cele mai vizibile inele din Sistemul Solar?',
    choices: ['Saturn', 'Jupiter', 'Uranus', 'Neptun'],
    answer: 'Saturn',
  ),
  CultureQuestion(
    question: 'Cum se numește stația spațială permanent locuită, aflată pe orbita Pământului?',
    choices: ['Stația Spațială Internațională', 'Mir', 'Skylab', 'Tiangong'],
    answer: 'Stația Spațială Internațională',
  ),
  CultureQuestion(
    question: 'Ce agenție spațială americană a coordonat misiunile Apollo?',
    choices: ['ESA', 'NASA', 'Roscosmos', 'JAXA'],
    answer: 'NASA',
  ),
  CultureQuestion(
    question: 'În ce constelație se află Steaua Polară?',
    choices: ['Ursa Mare', 'Ursa Mică', 'Orion', 'Casiopeea'],
    answer: 'Ursa Mică',
  ),
  CultureQuestion(
    question: 'Cum se numea prima navă spațială cu echipaj uman, lansată în 1961?',
    choices: ['Vostok 1', 'Apollo 11', 'Soyuz 1', 'Sputnik 1'],
    answer: 'Vostok 1',
  ),
  CultureQuestion(
    question: 'Ce planetă are cea mai mare lună din Sistemul Solar (Ganymede)?',
    choices: ['Saturn', 'Jupiter', 'Uranus', 'Neptun'],
    answer: 'Jupiter',
  ),
  CultureQuestion(
    question: 'Care este cel mai mic os din corpul uman?',
    choices: ['Scărița', 'Rotula', 'Falanga', 'Clavicula'],
    answer: 'Scărița',
  ),
  CultureQuestion(
    question: 'Ce vitamină este cunoscută și ca acid ascorbic?',
    choices: ['Vitamina A', 'Vitamina C', 'Vitamina D', 'Vitamina K'],
    answer: 'Vitamina C',
  ),
  CultureQuestion(
    question: 'Câte camere are inima umană?',
    choices: ['2', '3', '4', '5'],
    answer: '4',
  ),
  CultureQuestion(
    question: 'Ce parte a creierului controlează echilibrul și coordonarea mișcărilor?',
    choices: ['Cerebelul', 'Hipotalamusul', 'Talamusul', 'Bulbul rahidian'],
    answer: 'Cerebelul',
  ),
  CultureQuestion(
    question: 'Ce celule ale sistemului imunitar luptă împotriva infecțiilor?',
    choices: ['Globulele roșii', 'Globulele albe', 'Trombocitele', 'Neuronii'],
    answer: 'Globulele albe',
  ),
  CultureQuestion(
    question: 'Câți litri de sânge are, în medie, un adult?',
    choices: ['2-3 litri', '5-6 litri', '8-9 litri', '10-12 litri'],
    answer: '5-6 litri',
  ),
  CultureQuestion(
    question: 'Care este capitala Elveției?',
    choices: ['Zurich', 'Geneva', 'Berna', 'Basel'],
    answer: 'Berna',
  ),
  CultureQuestion(
    question: 'Care este capitala Suediei?',
    choices: ['Göteborg', 'Malmö', 'Stockholm', 'Uppsala'],
    answer: 'Stockholm',
  ),
  CultureQuestion(
    question: 'Care este capitala Norvegiei?',
    choices: ['Bergen', 'Oslo', 'Trondheim', 'Stavanger'],
    answer: 'Oslo',
  ),
  CultureQuestion(
    question: 'Care este capitala Finlandei?',
    choices: ['Turku', 'Tampere', 'Helsinki', 'Oulu'],
    answer: 'Helsinki',
  ),
  CultureQuestion(
    question: 'Care este capitala Danemarcei?',
    choices: ['Aarhus', 'Odense', 'Copenhaga', 'Aalborg'],
    answer: 'Copenhaga',
  ),
  CultureQuestion(
    question: 'Care este capitala Irlandei?',
    choices: ['Cork', 'Galway', 'Dublin', 'Limerick'],
    answer: 'Dublin',
  ),
  CultureQuestion(
    question: 'Care este capitala Cehiei?',
    choices: ['Brno', 'Praga', 'Ostrava', 'Plzeň'],
    answer: 'Praga',
  ),
  CultureQuestion(
    question: 'Care este capitala Ucrainei?',
    choices: ['Harkov', 'Odesa', 'Kiev', 'Lviv'],
    answer: 'Kiev',
  ),
  CultureQuestion(
    question: 'Care este capitala Mexicului?',
    choices: ['Guadalajara', 'Monterrey', 'Ciudad de Mexico', 'Cancún'],
    answer: 'Ciudad de Mexico',
  ),
  CultureQuestion(
    question: 'Care este capitala Argentinei?',
    choices: ['Córdoba', 'Rosario', 'Buenos Aires', 'Mendoza'],
    answer: 'Buenos Aires',
  ),
  CultureQuestion(
    question: 'Care este capitala Coreei de Sud?',
    choices: ['Busan', 'Seul', 'Incheon', 'Daegu'],
    answer: 'Seul',
  ),
  CultureQuestion(
    question: 'Care este capitala Thailandei?',
    choices: ['Chiang Mai', 'Phuket', 'Bangkok', 'Pattaya'],
    answer: 'Bangkok',
  ),
  CultureQuestion(
    question: 'Care este capitala Noii Zeelande?',
    choices: ['Auckland', 'Wellington', 'Christchurch', 'Hamilton'],
    answer: 'Wellington',
  ),
  CultureQuestion(
    question: 'Care este cel mai lung fluviu din Europa?',
    choices: ['Dunărea', 'Volga', 'Rinul', 'Ronul'],
    answer: 'Volga',
  ),
  CultureQuestion(
    question: 'Care este cea mai mare insulă din lume?',
    choices: ['Madagascar', 'Groenlanda', 'Borneo', 'Noua Guinee'],
    answer: 'Groenlanda',
  ),
  CultureQuestion(
    question: 'Care este cel mai populat continent?',
    choices: ['Africa', 'Asia', 'Europa', 'America de Nord'],
    answer: 'Asia',
  ),
  CultureQuestion(
    question: 'Care este cel mai mic ocean de pe Glob?',
    choices: ['Oceanul Indian', 'Oceanul Atlantic', 'Oceanul Arctic', 'Oceanul Pacific'],
    answer: 'Oceanul Arctic',
  ),
  CultureQuestion(
    question: 'Care este cea mai mare peninsulă din lume?',
    choices: ['Peninsula Arabică', 'Peninsula Scandinavă', 'Peninsula Iberică', 'Peninsula Balcanică'],
    answer: 'Peninsula Arabică',
  ),
  CultureQuestion(
    question: 'Pe ce continent se află cea mai mare parte a teritoriului Rusiei?',
    choices: ['Europa', 'Asia', 'Ambele în mod egal', 'Nici una'],
    answer: 'Asia',
  ),
  CultureQuestion(
    question: 'Cine a fost primul președinte al Statelor Unite ale Americii?',
    choices: ['Thomas Jefferson', 'Abraham Lincoln', 'George Washington', 'John Adams'],
    answer: 'George Washington',
  ),
  CultureQuestion(
    question: 'În ce an a căzut Zidul Berlinului?',
    choices: ['1987', '1989', '1991', '1993'],
    answer: '1989',
  ),
  CultureQuestion(
    question: 'Cine a condus expediția care a realizat primul înconjur al globului, finalizat în 1522?',
    choices: ['Vasco da Gama', 'Fernando Magellan', 'Cristofor Columb', 'James Cook'],
    answer: 'Fernando Magellan',
  ),
  CultureQuestion(
    question: 'Cine a fost liderul roman ucis în anul 44 î.Hr., într-un celebru complot?',
    choices: ['Augustus', 'Iulius Cezar', 'Nero', 'Marc Antoniu'],
    answer: 'Iulius Cezar',
  ),
  CultureQuestion(
    question: 'Ce civilizație antică a construit piramidele de la Giza?',
    choices: ['Grecii antici', 'Egiptenii antici', 'Romanii antici', 'Babilonienii'],
    answer: 'Egiptenii antici',
  ),
  CultureQuestion(
    question: 'În ce secol a început Renașterea europeană?',
    choices: ['Secolul XII', 'Secolul XIV', 'Secolul XVII', 'Secolul XIX'],
    answer: 'Secolul XIV',
  ),
  CultureQuestion(
    question: 'Ce tratat a pus capăt oficial Primului Război Mondial?',
    choices: ['Tratatul de la Versailles', 'Tratatul de la Yalta', 'Tratatul de la Paris', 'Tratatul de la Viena'],
    answer: 'Tratatul de la Versailles',
  ),
  CultureQuestion(
    question: 'Cine a sculptat statuia "David", expusă la Florența?',
    choices: ['Donatello', 'Michelangelo', 'Bernini', 'Rodin'],
    answer: 'Michelangelo',
  ),
  CultureQuestion(
    question: 'Ce muzeu celebru din Paris găzduiește Mona Lisa?',
    choices: ['Muzeul d\'Orsay', 'Luvru', 'Centrul Pompidou', 'Petit Palais'],
    answer: 'Luvru',
  ),
  CultureQuestion(
    question: 'Cine a compus opera "Flautul fermecat"?',
    choices: ['Ludwig van Beethoven', 'Wolfgang Amadeus Mozart', 'Johann Strauss', 'Giuseppe Verdi'],
    answer: 'Wolfgang Amadeus Mozart',
  ),
  CultureQuestion(
    question: 'Ce scriitor britanic a creat personajul detectiv Sherlock Holmes?',
    choices: ['Agatha Christie', 'Arthur Conan Doyle', 'Charles Dickens', 'Oscar Wilde'],
    answer: 'Arthur Conan Doyle',
  ),
  CultureQuestion(
    question: 'Cine a scris romanul "Război și pace"?',
    choices: ['Fiodor Dostoievski', 'Lev Tolstoi', 'Anton Cehov', 'Nikolai Gogol'],
    answer: 'Lev Tolstoi',
  ),
  CultureQuestion(
    question: 'Cine a scris "Micul Prinț"?',
    choices: ['Victor Hugo', 'Antoine de Saint-Exupéry', 'Albert Camus', 'Jules Verne'],
    answer: 'Antoine de Saint-Exupéry',
  ),
  CultureQuestion(
    question: 'Cine este creditat cu inventarea World Wide Web?',
    choices: ['Bill Gates', 'Tim Berners-Lee', 'Steve Jobs', 'Larry Page'],
    answer: 'Tim Berners-Lee',
  ),
  CultureQuestion(
    question: 'Ce companie a dezvoltat sistemul de operare Android?',
    choices: ['Apple', 'Microsoft', 'Google', 'Samsung'],
    answer: 'Google',
  ),
  CultureQuestion(
    question: 'Ce companie a creat consola de jocuri PlayStation?',
    choices: ['Nintendo', 'Microsoft', 'Sony', 'Sega'],
    answer: 'Sony',
  ),
  CultureQuestion(
    question: 'În ce an a fost lansat primul iPhone?',
    choices: ['2005', '2007', '2009', '2011'],
    answer: '2007',
  ),
  CultureQuestion(
    question: 'Ce metal este cel mai bun conductor electric la temperatura camerei?',
    choices: ['Cuprul', 'Aurul', 'Argintul', 'Aluminiul'],
    answer: 'Argintul',
  ),
  CultureQuestion(
    question: 'Ce limbaj de programare a fost creat special pentru site-uri web interactive, în 1995?',
    choices: ['Python', 'Java', 'JavaScript', 'C++'],
    answer: 'JavaScript',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare pește din lume?',
    choices: ['Rechinul alb', 'Rechinul balenă', 'Tonul albastru', 'Manta'],
    answer: 'Rechinul balenă',
  ),
  CultureQuestion(
    question: 'Ce animal este singurul mamifer capabil de zbor propulsat, nu doar planat?',
    choices: ['Veverița zburătoare', 'Liliacul', 'Lemurul zburător', 'Pterozaurul'],
    answer: 'Liliacul',
  ),
  CultureQuestion(
    question: 'Câte inimi are o caracatiță?',
    choices: ['1', '2', '3', '4'],
    answer: '3',
  ),
  CultureQuestion(
    question: 'Ce animal își schimbă culoarea pielii pentru a se camufla?',
    choices: ['Iguana', 'Cameleonul', 'Salamandra', 'Broasca'],
    answer: 'Cameleonul',
  ),
  CultureQuestion(
    question: 'Care este cea mai mare reptilă din lume?',
    choices: ['Varanul de Komodo', 'Crocodilul de apă sărată', 'Anaconda', 'Broasca țestoasă Galapagos'],
    answer: 'Crocodilul de apă sărată',
  ),
  CultureQuestion(
    question: 'Ce mamifer marin este cunoscut ca fiind unul dintre cele mai inteligente animale?',
    choices: ['Foca', 'Delfinul', 'Balena', 'Vidra de mare'],
    answer: 'Delfinul',
  ),
  CultureQuestion(
    question: 'În ce oraș s-au desfășurat primele Jocuri Olimpice moderne, în 1896?',
    choices: ['Roma', 'Paris', 'Atena', 'Londra'],
    answer: 'Atena',
  ),
  CultureQuestion(
    question: 'Câți jucători are o echipă de baschet pe teren, în același timp?',
    choices: ['4', '5', '6', '7'],
    answer: '5',
  ),
  CultureQuestion(
    question: 'Câți jucători are o echipă de volei pe teren, în același timp?',
    choices: ['5', '6', '7', '8'],
    answer: '6',
  ),
  CultureQuestion(
    question: 'La ce sport excelează gimnasta Simone Biles?',
    choices: ['Înot', 'Atletism', 'Gimnastică', 'Scrimă'],
    answer: 'Gimnastică',
  ),
  CultureQuestion(
    question: 'Câte seturi trebuie câștigate, de regulă, pentru a câștiga un meci de tenis masculin la Grand Slam?',
    choices: ['2 din 3', '3 din 5', '4 din 7', '1 din 1'],
    answer: '3 din 5',
  ),
  CultureQuestion(
    question: 'Ce sărbătoare creștină celebrează nașterea lui Iisus?',
    choices: ['Paștele', 'Rusaliile', 'Crăciunul', 'Boboteaza'],
    answer: 'Crăciunul',
  ),
  CultureQuestion(
    question: 'Câte zerouri are un milion, scris cu cifre?',
    choices: ['4', '5', '6', '7'],
    answer: '6',
  ),
];

const List<CultureQuestion> _cultureQuestionsMaghiara = [
  CultureQuestion(
    question: 'Cum se numește orașul rezultat din unirea orașelor Buda, Pest și Óbuda, în 1873?',
    choices: ['Budapesta', 'Debrecen', 'Szeged', 'Pécs'],
    answer: 'Budapesta',
  ),
  CultureQuestion(
    question: 'Ce pod istoric celebru unește Buda și Pesta peste Dunăre?',
    choices: ['Podul cu Lanțuri', 'Podul Elisabeta', 'Podul Libertății', 'Podul Margareta'],
    answer: 'Podul cu Lanțuri',
  ),
  CultureQuestion(
    question: 'Ce clădire impresionantă de pe malul Dunării, din Budapesta, este sediul Parlamentului Ungariei?',
    choices: ['Parlamentul Ungariei', 'Castelul Buda', 'Bazilica Sfântul Ștefan', 'Opera Maghiară'],
    answer: 'Parlamentul Ungariei',
  ),
  CultureQuestion(
    question: 'Ce lac din vestul Ungariei este cel mai mare lac de apă dulce din Europa Centrală, supranumit "Marea Maghiară"?',
    choices: ['Lacul Balaton', 'Lacul Velence', 'Lacul Tisza', 'Lacul Fertő'],
    answer: 'Lacul Balaton',
  ),
  CultureQuestion(
    question: 'Ce fluviu major traversează Budapesta, împărțind orașul în Buda și Pesta?',
    choices: ['Tisa', 'Dunărea', 'Rinul', 'Drava'],
    answer: 'Dunărea',
  ),
  CultureQuestion(
    question: 'Ce fel de tocană tradițională maghiară, cu carne și boia, a devenit cunoscută în toată lumea?',
    choices: ['Gulașul', 'Paprikașul', 'Lecsó', 'Töltött káposzta'],
    answer: 'Gulașul',
  ),
  CultureQuestion(
    question: 'Ce condiment roșu, esențial în bucătăria maghiară, este considerat simbolul culinar al Ungariei?',
    choices: ['Boiaua (paprika)', 'Cardamomul', 'Șofranul', 'Turmericul'],
    answer: 'Boiaua (paprika)',
  ),
  CultureQuestion(
    question: 'Cine a fost primul rege al Ungariei, încoronat în anul 1000, mai târziu declarat sfânt?',
    choices: ['Ștefan I', 'Matia Corvin', 'Andrei II', 'Béla IV'],
    answer: 'Ștefan I',
  ),
  CultureQuestion(
    question: 'Ce rege maghiar din secolul al XV-lea, supranumit "cel Drept", a fost cunoscut pentru curtea sa renascentistă?',
    choices: ['Matia Corvin', 'Ștefan I', 'Ludovic cel Mare', 'Sigismund de Luxemburg'],
    answer: 'Matia Corvin',
  ),
  CultureQuestion(
    question: 'Cum se numește limba oficială a Ungariei, care aparține familiei de limbi fino-ugrice?',
    choices: ['Maghiara', 'Slovaca', 'Croata', 'Slovena'],
    answer: 'Maghiara',
  ),
  CultureQuestion(
    question: 'Ce compozitor maghiar celebru a compus "Rapsodiile Ungare"?',
    choices: ['Franz Liszt', 'Béla Bartók', 'Zoltán Kodály', 'Johannes Brahms'],
    answer: 'Franz Liszt',
  ),
  CultureQuestion(
    question: 'Ce compozitor și etnomuzicolog maghiar a colecționat cântece populare și a compus "Concertul pentru orchestră"?',
    choices: ['Béla Bartók', 'Franz Liszt', 'Zoltán Kodály', 'Ferenc Erkel'],
    answer: 'Béla Bartók',
  ),
  CultureQuestion(
    question: 'Ce oraș din sud-estul Ungariei, cunoscut pentru salam și boia, este supranumit "Orașul Soarelui"?',
    choices: ['Szeged', 'Debrecen', 'Pécs', 'Győr'],
    answer: 'Szeged',
  ),
  CultureQuestion(
    question: 'Cum se numesc celebrele băi termale istorice din Budapesta, printre cele mai mari complexe balneare din Europa?',
    choices: ['Băile Széchenyi', 'Băile Gellért', 'Termele Caracalla', 'Băile Turcești'],
    answer: 'Băile Széchenyi',
  ),
  CultureQuestion(
    question: 'La ce sport acvatic de echipă este Ungaria una dintre cele mai titrate națiuni din istoria Jocurilor Olimpice?',
    choices: ['Înot', 'Polo pe apă', 'Canotaj', 'Scrimă'],
    answer: 'Polo pe apă',
  ),
  CultureQuestion(
    question: 'Cine este inginerul maghiar creditat cu inventarea Cubului Rubik, în 1974?',
    choices: ['Ernő Rubik', 'László Bíró', 'Erik Weisz', 'Tivadar Puskás'],
    answer: 'Ernő Rubik',
  ),
  CultureQuestion(
    question: 'Ce jurnalist maghiar este creditat cu inventarea stiloului cu bilă modern (pixul)?',
    choices: ['László Bíró', 'Ernő Rubik', 'Tivadar Puskás', 'Ottó Bláthy'],
    answer: 'László Bíró',
  ),
  CultureQuestion(
    question: 'Ce matematician și fizician maghiar-american este considerat unul dintre fondatorii informaticii moderne?',
    choices: ['John von Neumann', 'Alan Turing', 'Alonzo Church', 'Claude Shannon'],
    answer: 'John von Neumann',
  ),
  CultureQuestion(
    question: 'În ce an a avut loc Revoluția anticomunistă din Ungaria, înăbușită de trupele sovietice?',
    choices: ['1953', '1956', '1968', '1989'],
    answer: '1956',
  ),
  CultureQuestion(
    question: 'Ce tratat din 1920, semnat după Primul Război Mondial, a dus la pierderea a două treimi din teritoriul istoric al Ungariei?',
    choices: ['Tratatul de la Trianon', 'Tratatul de la Versailles', 'Tratatul de la Saint-Germain', 'Tratatul de la Neuilly'],
    answer: 'Tratatul de la Trianon',
  ),
  CultureQuestion(
    question: 'Care este moneda oficială a Ungariei, țară care nu a adoptat euro?',
    choices: ['Forintul', 'Coroana', 'Leul', 'Zlotul'],
    answer: 'Forintul',
  ),
  CultureQuestion(
    question: 'Sub conducerea cui s-au stabilit triburile maghiare în Bazinul Carpatic, la finalul secolului al IX-lea?',
    choices: ['Árpád', 'Attila', 'Ștefan I', 'Béla IV'],
    answer: 'Árpád',
  ),
  CultureQuestion(
    question: 'Ce oraș, al doilea ca populație din Ungaria, este renumit pentru universitate și pentru Marea Biserică Reformată?',
    choices: ['Debrecen', 'Pécs', 'Győr', 'Miskolc'],
    answer: 'Debrecen',
  ),
  CultureQuestion(
    question: 'Ce tort celebru, cu straturi glazurate cu caramel, a fost creat de cofetarul József Dobos în 1885?',
    choices: ['Tortul Dobos', 'Tortul Sacher', 'Tortul Esterházy', 'Tortul Linzer'],
    answer: 'Tortul Dobos',
  ),
  CultureQuestion(
    question: 'Ce festival muzical de vară, desfășurat pe o insulă din Budapesta, este unul dintre cele mai mari din Europa?',
    choices: ['Sziget Festival', 'Tomorrowland', 'Glastonbury', 'Exit Festival'],
    answer: 'Sziget Festival',
  ),
  CultureQuestion(
    question: 'Ferenc Puskás este considerat una dintre cele mai mari legende din istoria...?',
    choices: ['fotbalului maghiar', 'șahului maghiar', 'boxului maghiar', 'atletismului maghiar'],
    answer: 'fotbalului maghiar',
  ),
  CultureQuestion(
    question: 'Cine a scris poemul "Nemzeti dal" ("Cântecul Național"), simbol al Revoluției din 1848?',
    choices: ['Sándor Petőfi', 'Endre Ady', 'Attila József', 'Mihály Vörösmarty'],
    answer: 'Sándor Petőfi',
  ),
  CultureQuestion(
    question: 'Versurile imnului național al Ungariei, "Himnusz", au fost scrise de cine?',
    choices: ['Ferenc Kölcsey', 'Sándor Petőfi', 'János Arany', 'Mihály Vörösmarty'],
    answer: 'Ferenc Kölcsey',
  ),
  CultureQuestion(
    question: 'Ce compromis din 1867 a transformat Imperiul Austriac în dubla monarhie Austro-Ungară?',
    choices: ['Compromisul Austro-Ungar', 'Tratatul de la Trianon', 'Congresul de la Viena', 'Pacea de la Westfalia'],
    answer: 'Compromisul Austro-Ungar',
  ),
  CultureQuestion(
    question: 'Ce castel medieval domină Buda, oferind o panoramă asupra Dunării și a Parlamentului?',
    choices: ['Castelul Buda', 'Cetatea Eger', 'Castelul Vajdahunyad', 'Cetatea Visegrád'],
    answer: 'Castelul Buda',
  ),
  CultureQuestion(
    question: 'Ce instrument tradițional cu coarde, ciocănit cu baghete, este folosit în muzica populară maghiară?',
    choices: ['Țambalul', 'Cimpoiul', 'Naiul', 'Vioara'],
    answer: 'Țambalul',
  ),
  CultureQuestion(
    question: 'Ce oraș istoric din nordul Ungariei este renumit pentru fortăreața sa și pentru vinul roșu "Egri Bikavér" (Sângele Taurului)?',
    choices: ['Eger', 'Tokaj', 'Sopron', 'Kecskemét'],
    answer: 'Eger',
  ),
  CultureQuestion(
    question: 'Ce regiune din nord-estul Ungariei este renumită pentru vinurile albe dulci, printre cele mai vechi vinuri denumite de origine din lume?',
    choices: ['Tokaj', 'Eger', 'Villány', 'Balaton'],
    answer: 'Tokaj',
  ),
  CultureQuestion(
    question: 'Ce planetă este cunoscută pentru vânturile sale extrem de puternice și pentru culoarea albastră intensă?',
    choices: ['Neptun', 'Uranus', 'Saturn', 'Jupiter'],
    answer: 'Neptun',
  ),
  CultureQuestion(
    question: 'Cum se numește fenomenul prin care Luna acoperă complet Soarele, văzut de pe Pământ?',
    choices: ['Eclipsă totală de Soare', 'Eclipsă de Lună', 'Solstițiu', 'Echinocțiu'],
    answer: 'Eclipsă totală de Soare',
  ),
  CultureQuestion(
    question: 'Ce telescop spațial, lansat în 1990, a revoluționat astronomia cu imagini de înaltă rezoluție?',
    choices: ['Telescopul Hubble', 'Telescopul James Webb', 'Telescopul Kepler', 'Telescopul Spitzer'],
    answer: 'Telescopul Hubble',
  ),
  CultureQuestion(
    question: 'Cine a fost primul câine trimis în spațiu, la bordul satelitului Sputnik 2, în 1957?',
    choices: ['Laika', 'Belka', 'Strelka', 'Ham'],
    answer: 'Laika',
  ),
  CultureQuestion(
    question: 'Ce planetă din Sistemul Solar are o zi mai lungă decât anul ei?',
    choices: ['Venus', 'Mercur', 'Marte', 'Uranus'],
    answer: 'Venus',
  ),
  CultureQuestion(
    question: 'Cum se numește ultima planetă vizitată de misiunea Voyager 2, înainte de a ieși din Sistemul Solar?',
    choices: ['Neptun', 'Uranus', 'Pluto', 'Saturn'],
    answer: 'Neptun',
  ),
  CultureQuestion(
    question: 'Ce organ este responsabil pentru filtrarea sângelui și producerea urinei?',
    choices: ['Rinichii', 'Ficatul', 'Plămânii', 'Splina'],
    answer: 'Rinichii',
  ),
  CultureQuestion(
    question: 'Câte perechi de coaste are, de obicei, un adult?',
    choices: ['10', '11', '12', '13'],
    answer: '12',
  ),
  CultureQuestion(
    question: 'Ce simț este controlat de nervul optic?',
    choices: ['Vederea', 'Auzul', 'Mirosul', 'Gustul'],
    answer: 'Vederea',
  ),
  CultureQuestion(
    question: 'Ce vitamină este produsă cu ajutorul ficatului și este esențială pentru coagularea sângelui?',
    choices: ['Vitamina A', 'Vitamina K', 'Vitamina E', 'Vitamina B6'],
    answer: 'Vitamina K',
  ),
  CultureQuestion(
    question: 'Câte oase are, la naștere, un bebeluș uman — mai multe decât un adult?',
    choices: ['Aproximativ 206', 'Aproximativ 250', 'Aproximativ 300', 'Aproximativ 350'],
    answer: 'Aproximativ 300',
  ),
  CultureQuestion(
    question: 'Ce parte a ochiului controlează cantitatea de lumină care intră?',
    choices: ['Irisul (pupila)', 'Retina', 'Corneea', 'Cristalinul'],
    answer: 'Irisul (pupila)',
  ),
  CultureQuestion(
    question: 'Care este capitala Croației?',
    choices: ['Zagreb', 'Split', 'Dubrovnik', 'Rijeka'],
    answer: 'Zagreb',
  ),
  CultureQuestion(
    question: 'Care este capitala Serbiei?',
    choices: ['Belgrad', 'Novi Sad', 'Niš', 'Subotica'],
    answer: 'Belgrad',
  ),
  CultureQuestion(
    question: 'Care este capitala Bulgariei?',
    choices: ['Sofia', 'Plovdiv', 'Varna', 'Burgas'],
    answer: 'Sofia',
  ),
  CultureQuestion(
    question: 'Care este capitala Slovaciei?',
    choices: ['Bratislava', 'Košice', 'Nitra', 'Žilina'],
    answer: 'Bratislava',
  ),
  CultureQuestion(
    question: 'Care este capitala Sloveniei?',
    choices: ['Ljubljana', 'Maribor', 'Celje', 'Koper'],
    answer: 'Ljubljana',
  ),
  CultureQuestion(
    question: 'Care este capitala Islandei?',
    choices: ['Reykjavik', 'Akureyri', 'Selfoss', 'Kópavogur'],
    answer: 'Reykjavik',
  ),
  CultureQuestion(
    question: 'Care este capitala Letoniei?',
    choices: ['Riga', 'Daugavpils', 'Liepāja', 'Jūrmala'],
    answer: 'Riga',
  ),
  CultureQuestion(
    question: 'Care este capitala Lituaniei?',
    choices: ['Vilnius', 'Kaunas', 'Klaipėda', 'Šiauliai'],
    answer: 'Vilnius',
  ),
  CultureQuestion(
    question: 'Care este capitala Estoniei?',
    choices: ['Tallinn', 'Tartu', 'Narva', 'Pärnu'],
    answer: 'Tallinn',
  ),
  CultureQuestion(
    question: 'Care este capitala statului Peru?',
    choices: ['Lima', 'Cusco', 'Arequipa', 'Trujillo'],
    answer: 'Lima',
  ),
  CultureQuestion(
    question: 'Care este capitala statului Chile?',
    choices: ['Santiago', 'Valparaíso', 'Concepción', 'Antofagasta'],
    answer: 'Santiago',
  ),
  CultureQuestion(
    question: 'Care este capitala Indoneziei?',
    choices: ['Jakarta', 'Bali', 'Surabaya', 'Bandung'],
    answer: 'Jakarta',
  ),
  CultureQuestion(
    question: 'Care este cel mai adânc lac din lume?',
    choices: ['Lacul Baikal', 'Lacul Tanganyika', 'Lacul Superior', 'Marea Caspică'],
    answer: 'Lacul Baikal',
  ),
  CultureQuestion(
    question: 'Ce strat al atmosferei conține stratul de ozon care ne protejează de radiațiile UV?',
    choices: ['Troposfera', 'Stratosfera', 'Mezosfera', 'Termosfera'],
    answer: 'Stratosfera',
  ),
  CultureQuestion(
    question: 'Ce ocean separă America de Europa și Africa?',
    choices: ['Oceanul Atlantic', 'Oceanul Pacific', 'Oceanul Indian', 'Oceanul Arctic'],
    answer: 'Oceanul Atlantic',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare arhipelag din lume, ca număr de insule?',
    choices: ['Indonezia', 'Filipine', 'Japonia', 'Insulele Maldive'],
    answer: 'Indonezia',
  ),
  CultureQuestion(
    question: 'Ce munți separă Europa de Asia, considerați o frontieră naturală?',
    choices: ['Munții Ural', 'Munții Caucaz', 'Alpii', 'Carpații'],
    answer: 'Munții Ural',
  ),
  CultureQuestion(
    question: 'Cine a fost prima femeie care a câștigat un Premiu Nobel?',
    choices: ['Marie Curie', 'Rosalind Franklin', 'Ada Lovelace', 'Florence Nightingale'],
    answer: 'Marie Curie',
  ),
  CultureQuestion(
    question: 'Ce imperiu antic, condus de Alexandru Macedon, s-a extins din Grecia până în India?',
    choices: ['Imperiul Roman', 'Imperiul Macedonean', 'Imperiul Persan', 'Imperiul Otoman'],
    answer: 'Imperiul Macedonean',
  ),
  CultureQuestion(
    question: 'În ce an a început Revoluția Franceză?',
    choices: ['1776', '1789', '1799', '1804'],
    answer: '1789',
  ),
  CultureQuestion(
    question: 'Cine a fost liderul care a condus Uniunea Sovietică în timpul Celui de-al Doilea Război Mondial?',
    choices: ['Vladimir Lenin', 'Iosif Stalin', 'Nikita Hrusciov', 'Leonid Brejnev'],
    answer: 'Iosif Stalin',
  ),
  CultureQuestion(
    question: 'Ce structură antică din China, vizibilă parțial din spațiu, a fost construită pentru apărare?',
    choices: ['Marele Zid Chinezesc', 'Marele Canal', 'Marea Piramidă', 'Marele Baraj'],
    answer: 'Marele Zid Chinezesc',
  ),
  CultureQuestion(
    question: 'Ce explorator norvegian a fost primul om care a ajuns la Polul Sud, în 1911?',
    choices: ['Roald Amundsen', 'Robert Scott', 'Ernest Shackleton', 'Richard Byrd'],
    answer: 'Roald Amundsen',
  ),
  CultureQuestion(
    question: 'Cine a compus baletul "Lacul Lebedelor"?',
    choices: ['Piotr Ilici Ceaikovski', 'Serghei Prokofiev', 'Igor Stravinski', 'Nikolai Rimski-Korsakov'],
    answer: 'Piotr Ilici Ceaikovski',
  ),
  CultureQuestion(
    question: 'Ce arhitect spaniol este creatorul catedralei nefinalizate Sagrada Família din Barcelona?',
    choices: ['Antoni Gaudí', 'Pablo Picasso', 'Salvador Dalí', 'Joan Miró'],
    answer: 'Antoni Gaudí',
  ),
  CultureQuestion(
    question: 'Cine a scris romanul "1984"?',
    choices: ['George Orwell', 'Aldous Huxley', 'Ray Bradbury', 'H.G. Wells'],
    answer: 'George Orwell',
  ),
  CultureQuestion(
    question: 'Cine a pictat "Persistența memoriei" (tabloul cu ceasurile moi)?',
    choices: ['Salvador Dalí', 'René Magritte', 'Max Ernst', 'Joan Miró'],
    answer: 'Salvador Dalí',
  ),
  CultureQuestion(
    question: 'Cine a scris piesa de teatru "Hamlet"?',
    choices: ['William Shakespeare', 'Christopher Marlowe', 'Ben Jonson', 'Oscar Wilde'],
    answer: 'William Shakespeare',
  ),
  CultureQuestion(
    question: 'Ce muzeu din Madrid găzduiește opere de Velázquez și Goya?',
    choices: ['Muzeul Prado', 'Muzeul Reina Sofía', 'Luvru', 'Muzeul Van Gogh'],
    answer: 'Muzeul Prado',
  ),
  CultureQuestion(
    question: 'Ce companie a lansat, în 1977, consola de jocuri video Atari 2600?',
    choices: ['Atari', 'Nintendo', 'Sega', 'Sony'],
    answer: 'Atari',
  ),
  CultureQuestion(
    question: 'Ce rețea socială a fost fondată de Mark Zuckerberg în 2004?',
    choices: ['Facebook', 'Twitter', 'Instagram', 'LinkedIn'],
    answer: 'Facebook',
  ),
  CultureQuestion(
    question: 'Ce companie deține cel mai folosit motor de căutare din lume, Google Search?',
    choices: ['Google', 'Yahoo', 'Microsoft', 'Amazon'],
    answer: 'Google',
  ),
  CultureQuestion(
    question: 'Ce înseamnă termenul "hardware" în informatică?',
    choices: ['Componentele fizice ale unui calculator', 'Programele instalate', 'Sistemul de operare', 'Conexiunea la internet'],
    answer: 'Componentele fizice ale unui calculator',
  ),
  CultureQuestion(
    question: 'Ce tip de memorie a calculatorului își pierde datele când se închide alimentarea?',
    choices: ['RAM', 'Hard Disk', 'SSD', 'ROM'],
    answer: 'RAM',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare animal terestru din lume?',
    choices: ['Elefantul african', 'Girafa', 'Rinocerul', 'Hipopotamul'],
    answer: 'Elefantul african',
  ),
  CultureQuestion(
    question: 'Ce insectă produce miere și trăiește în colonii organizate în jurul unei regine?',
    choices: ['Albina', 'Furnica', 'Viespea', 'Fluturele'],
    answer: 'Albina',
  ),
  CultureQuestion(
    question: 'Care dintre următoarele animale NU poate sări?',
    choices: ['Elefantul', 'Cangurul', 'Broasca', 'Iepurele'],
    answer: 'Elefantul',
  ),
  CultureQuestion(
    question: 'Ce animal are cel mai lung gât dintre toate mamiferele?',
    choices: ['Girafa', 'Cămila', 'Struțul', 'Calul'],
    answer: 'Girafa',
  ),
  CultureQuestion(
    question: 'Câte picioare are un crab, în total?',
    choices: ['6', '8', '10', '12'],
    answer: '10',
  ),
  CultureQuestion(
    question: 'Ce pasăre este cunoscută ca fiind cea mai rapidă din lume, în picaj?',
    choices: ['Șoimul călător', 'Vulturul auriu', 'Albatrosul', 'Colibrii'],
    answer: 'Șoimul călător',
  ),
  CultureQuestion(
    question: 'La ce sport este folosit termenul "eagle" (vultur) pentru un scor cu 2 sub par pe o gaură?',
    choices: ['Golf', 'Tenis', 'Baschet', 'Popice'],
    answer: 'Golf',
  ),
  CultureQuestion(
    question: 'Câte seturi are, de regulă, un meci de tenis feminin la Grand Slam?',
    choices: ['2 din 3', '3 din 5', '4 din 7', '1 din 1'],
    answer: '2 din 3',
  ),
  CultureQuestion(
    question: 'Ce țară a găzduit Campionatul Mondial de Fotbal din 2014?',
    choices: ['Brazilia', 'Germania', 'Africa de Sud', 'Rusia'],
    answer: 'Brazilia',
  ),
  CultureQuestion(
    question: 'Câte runde durează, de regulă, un meci profesionist de box la nivel de campionat mondial?',
    choices: ['8', '10', '12', '15'],
    answer: '12',
  ),
  CultureQuestion(
    question: 'Ce sărbătoare se celebrează pe 1 ianuarie în majoritatea lumii?',
    choices: ['Anul Nou', 'Crăciunul', 'Paștele', 'Ziua Recoltei'],
    answer: 'Anul Nou',
  ),
  CultureQuestion(
    question: 'Câte litere are alfabetul latin de bază, folosit în limba engleză?',
    choices: ['24', '25', '26', '27'],
    answer: '26',
  ),
  CultureQuestion(
    question: 'Ce unitate de măsură este folosită pentru a exprima greutatea, în sistemul metric?',
    choices: ['Kilogramul', 'Litrul', 'Metrul', 'Newtonul'],
    answer: 'Kilogramul',
  ),
  CultureQuestion(
    question: 'Câte zile durează, în medie, un ciclu lunar (de la Lună nouă la Lună nouă)?',
    choices: ['Aproximativ 21 zile', 'Aproximativ 25 zile', 'Aproximativ 29,5 zile', 'Aproximativ 35 zile'],
    answer: 'Aproximativ 29,5 zile',
  ),
  CultureQuestion(
    question: 'Ce material este folosit tradițional pentru medaliile de locul 1 la Jocurile Olimpice?',
    choices: ['Aurul (aliaj placat)', 'Platina', 'Titanul', 'Bronzul'],
    answer: 'Aurul (aliaj placat)',
  ),
  CultureQuestion(
    question: 'Câte coarde are, de obicei, o chitară clasică?',
    choices: ['4', '5', '6', '7'],
    answer: '6',
  ),
  CultureQuestion(
    question: 'Ce parte a plantei absoarbe apa și substanțele nutritive din sol?',
    choices: ['Rădăcina', 'Tulpina', 'Floarea', 'Fructul'],
    answer: 'Rădăcina',
  ),
  CultureQuestion(
    question: 'Ce gaz folosesc plantele pentru fotosinteză, eliberând oxigen?',
    choices: ['Dioxidul de carbon', 'Azotul', 'Hidrogenul', 'Metanul'],
    answer: 'Dioxidul de carbon',
  ),
  CultureQuestion(
    question: 'Câte zile are, în total, luna aprilie?',
    choices: ['28', '29', '30', '31'],
    answer: '30',
  ),
  CultureQuestion(
    question: 'Ce fenomen optic colorat apare pe cer după ploaie, când lumina soarelui se refractă prin picăturile de apă?',
    choices: ['Curcubeul', 'Aurora boreală', 'Halo-ul lunar', 'Mirajul'],
    answer: 'Curcubeul',
  ),
  CultureQuestion(
    question: 'Ce oraș din vestul Ungariei, aproape de frontiera cu Austria, este renumit pentru arhitectura sa barocă bine conservată?',
    choices: ['Sopron', 'Győr', 'Veszprém', 'Kecskemét'],
    answer: 'Sopron',
  ),
];

/// Categoriile disponibile pentru panoul de pe Home — fiecare cu propriul
/// pool de [cultureQuizQuestionCount] întrebări. Prima din listă e selectată
/// implicit când deschizi Home.
const List<CultureCategory> cultureCategories = [
  CultureCategory(id: 'romania', title: 'România', flag: '🇷🇴', questions: _cultureQuestionsRomania),
  CultureCategory(id: 'belgia', title: 'Belgia', flag: '🇧🇪', questions: _cultureQuestionsBelgia),
  CultureCategory(id: 'maghiara', title: 'Ungaria', flag: '🇭🇺', questions: _cultureQuestionsMaghiara),
];
