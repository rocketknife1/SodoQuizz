/// Întrebare de cultură generală — text simplu, fără imagine, 4 variante.
/// Folosită doar de [CultureQuizPanel] de pe Home, nu de GameScreen.
/// Pool mare (150+ întrebări); fiecare lot (beta, nelimitat) alege
/// [cultureQuizQuestionCount] aleatorii din el.
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

const int cultureQuizQuestionCount = 10;
const int cultureSecondsPerQuestion = 35;

const List<CultureQuestion> cultureQuestions = [
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
    question: 'Câte continente are Pământul?',
    choices: ['5', '6', '7', '8'],
    answer: '7',
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
    question: 'Câte zile are un an bisect?',
    choices: ['365', '364', '366', '367'],
    answer: '366',
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
    question: 'Câte minute are o oră și jumătate?',
    choices: ['80', '90', '100', '120'],
    answer: '90',
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
    question: 'Ce gaz este esențial pentru respirația omului?',
    choices: ['Azot', 'Oxigen', 'Hidrogen', 'Heliu'],
    answer: 'Oxigen',
  ),
  CultureQuestion(
    question: 'Care este capitala Japoniei?',
    choices: ['Osaka', 'Kyoto', 'Tokyo', 'Hiroshima'],
    answer: 'Tokyo',
  ),
  CultureQuestion(
    question: 'Câte laturi are un hexagon?',
    choices: ['5', '6', '7', '8'],
    answer: '6',
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
    question: 'Câte secunde are un minut?',
    choices: ['30', '60', '90', '100'],
    answer: '60',
  ),
  CultureQuestion(
    question: 'Care este cel mai rapid animal terestru?',
    choices: ['Leul', 'Ghepardul', 'Antilopa', 'Calul'],
    answer: 'Ghepardul',
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
    question: 'Câte zile are februarie într-un an obișnuit (nebisect)?',
    choices: ['27', '28', '29', '30'],
    answer: '28',
  ),
  CultureQuestion(
    question: 'Cine a compus "Rapsodia Română"?',
    choices: ['George Enescu', 'Ciprian Porumbescu', 'Dinu Lipatti', 'Gheorghe Zamfir'],
    answer: 'George Enescu',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare deșert cald din lume?',
    choices: ['Gobi', 'Sahara', 'Kalahari', 'Atacama'],
    answer: 'Sahara',
  ),
  CultureQuestion(
    question: 'Ce vitamină produce corpul expus la soare?',
    choices: ['Vitamina A', 'Vitamina C', 'Vitamina D', 'Vitamina B12'],
    answer: 'Vitamina D',
  ),
  CultureQuestion(
    question: 'Câte picioare are un păianjen?',
    choices: ['6', '8', '10', '12'],
    answer: '8',
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
    question: 'Ce substanță are formula chimică H2O?',
    choices: ['Sarea', 'Apa', 'Zahărul', 'Oțetul'],
    answer: 'Apa',
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
    question: 'Care este capitala Statelor Unite ale Americii?',
    choices: ['New York', 'Los Angeles', 'Washington D.C.', 'Chicago'],
    answer: 'Washington D.C.',
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
    question: 'Câte corzi are o vioară?',
    choices: ['3', '4', '5', '6'],
    answer: '4',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare organ al corpului uman?',
    choices: ['Ficatul', 'Creierul', 'Pielea', 'Plămânii'],
    answer: 'Pielea',
  ),
  CultureQuestion(
    question: 'Din ce cereală se face în mod tradițional pâinea?',
    choices: ['Porumb', 'Orez', 'Grâu', 'Ovăz'],
    answer: 'Grâu',
  ),
  CultureQuestion(
    question: 'Care este capitala Rusiei?',
    choices: ['Sankt Petersburg', 'Moscova', 'Kiev', 'Minsk'],
    answer: 'Moscova',
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
    question: 'Care este capitala Egiptului?',
    choices: ['Alexandria', 'Cairo', 'Luxor', 'Giza'],
    answer: 'Cairo',
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
    question: 'Care este cea mai mare țară din lume ca suprafață?',
    choices: ['Canada', 'China', 'Rusia', 'SUA'],
    answer: 'Rusia',
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
  CultureQuestion(
    question: 'Cum se numește galaxia în care se află Sistemul Solar?',
    choices: ['Andromeda', 'Calea Lactee', 'Triunghiul', 'Omega Centauri'],
    answer: 'Calea Lactee',
  ),
  CultureQuestion(
    question: 'Ce forță ține planetele pe orbită în jurul Soarelui?',
    choices: ['Magnetismul', 'Gravitația', 'Presiunea', 'Frecarea'],
    answer: 'Gravitația',
  ),
  CultureQuestion(
    question: 'Care e cea mai apropiată stea de Pământ, în afară de Soare?',
    choices: ['Sirius', 'Proxima Centauri', 'Polaris', 'Vega'],
    answer: 'Proxima Centauri',
  ),
  CultureQuestion(
    question: 'Care este unitatea de măsură pentru distanțe astronomice mari?',
    choices: ['Kilometrul', 'Anul-lumină', 'Mila marină', 'Parsecul'],
    answer: 'Anul-lumină',
  ),
  CultureQuestion(
    question: 'Câte oase are un nou-născut, aproximativ (mai multe decât adultul)?',
    choices: ['206', '270', '150', '350'],
    answer: '270',
  ),
  CultureQuestion(
    question: 'Care este cel mai mic os din corpul uman?',
    choices: ['Scărița (din ureche)', 'Falanga', 'Rotula', 'Claviculă'],
    answer: 'Scărița (din ureche)',
  ),
  CultureQuestion(
    question: 'Ce organ produce insulina?',
    choices: ['Ficatul', 'Rinichiul', 'Pancreasul', 'Splina'],
    answer: 'Pancreasul',
  ),
  CultureQuestion(
    question: 'Câte camere are inima umană?',
    choices: ['2', '3', '4', '5'],
    answer: '4',
  ),
  CultureQuestion(
    question: 'Ce tip de celule transportă oxigenul în sânge?',
    choices: ['Globulele albe', 'Trombocitele', 'Globulele roșii', 'Neuronii'],
    answer: 'Globulele roșii',
  ),
  CultureQuestion(
    question: 'Care este simbolul chimic al argintului?',
    choices: ['Ar', 'Ag', 'Au', 'Al'],
    answer: 'Ag',
  ),
  CultureQuestion(
    question: 'Care este simbolul chimic al fierului?',
    choices: ['Fe', 'Fr', 'Fi', 'Ir'],
    answer: 'Fe',
  ),
  CultureQuestion(
    question: 'Câte elemente chimice are, aproximativ, tabelul periodic?',
    choices: ['~90', '~118', '~150', '~200'],
    answer: '~118',
  ),
  CultureQuestion(
    question: 'La ce temperatură (Celsius) îngheață apa?',
    choices: ['-10°C', '0°C', '10°C', '100°C'],
    answer: '0°C',
  ),
  CultureQuestion(
    question: 'La ce temperatură (Celsius) fierbe apa la nivelul mării?',
    choices: ['90°C', '100°C', '110°C', '212°C'],
    answer: '100°C',
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
    question: 'Ce a inventat Guglielmo Marconi?',
    choices: ['Telefonul', 'Radioul', 'Becul', 'Televizorul'],
    answer: 'Radioul',
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
    question: 'Cine a scris "Război și pace"?',
    choices: ['Fiodor Dostoievski', 'Lev Tolstoi', 'Anton Cehov', 'Alexandr Pușkin'],
    answer: 'Lev Tolstoi',
  ),
  CultureQuestion(
    question: 'Cine este autorul piesei "Hamlet"?',
    choices: ['Christopher Marlowe', 'William Shakespeare', 'Oscar Wilde', 'George Orwell'],
    answer: 'William Shakespeare',
  ),
  CultureQuestion(
    question: 'Cine a scris "Ion"?',
    choices: ['Mihail Sadoveanu', 'Liviu Rebreanu', 'Camil Petrescu', 'Ioan Slavici'],
    answer: 'Liviu Rebreanu',
  ),
  CultureQuestion(
    question: 'Cine este autorul poeziei "Scrisoarea III"?',
    choices: ['George Coșbuc', 'Mihai Eminescu', 'Vasile Alecsandri', 'Tudor Arghezi'],
    answer: 'Mihai Eminescu',
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
    question: 'În ce an a avut loc Revoluția Română?',
    choices: ['1987', '1989', '1991', '1993'],
    answer: '1989',
  ),
  CultureQuestion(
    question: 'Cine a fost primul președinte al României post-comuniste?',
    choices: ['Emil Constantinescu', 'Ion Iliescu', 'Traian Băsescu', 'Petre Roman'],
    answer: 'Ion Iliescu',
  ),
  CultureQuestion(
    question: 'În ce an a intrat România în Uniunea Europeană?',
    choices: ['2004', '2005', '2007', '2010'],
    answer: '2007',
  ),
  CultureQuestion(
    question: 'Care este cel mai vechi oraș atestat documentar din România?',
    choices: ['Sibiu', 'Cluj-Napoca', 'Iași', 'Alba Iulia'],
    answer: 'Alba Iulia',
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
    question: 'Cine a fost primul împărat roman?',
    choices: ['Iulius Cezar', 'August', 'Nero', 'Traian'],
    answer: 'August',
  ),
  CultureQuestion(
    question: 'Care civilizație antică a construit piramidele de la Giza?',
    choices: ['Sumeriană', 'Egipteană', 'Babiloniană', 'Feniciană'],
    answer: 'Egipteană',
  ),
  CultureQuestion(
    question: 'În ce an a căzut Zidul Berlinului?',
    choices: ['1987', '1989', '1991', '1993'],
    answer: '1989',
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
    question: 'La câți ani se organizează Jocurile Olimpice de vară?',
    choices: ['2', '3', '4', '5'],
    answer: '4',
  ),
  CultureQuestion(
    question: 'Câți jucători are o echipă de fotbal pe teren, fără portar?',
    choices: ['9', '10', '11', '12'],
    answer: '10',
  ),
  CultureQuestion(
    question: 'Câte seturi trebuie câștigate pentru a câștiga un meci de tenis (Grand Slam masculin)?',
    choices: ['2', '3', '4', '5'],
    answer: '3',
  ),
  CultureQuestion(
    question: 'În ce sport se folosește termenul "eagle"?',
    choices: ['Tenis', 'Golf', 'Baseball', 'Rugby'],
    answer: 'Golf',
  ),
  CultureQuestion(
    question: 'Câte inele are simbolul Jocurilor Olimpice?',
    choices: ['4', '5', '6', '7'],
    answer: '5',
  ),
  CultureQuestion(
    question: 'Care este cea mai mare felină din lume?',
    choices: ['Leul', 'Jaguarul', 'Tigrul', 'Leopardul'],
    answer: 'Tigrul',
  ),
  CultureQuestion(
    question: 'Care este cel mai rapid animal marin?',
    choices: ['Rechinul alb', 'Peștele-spadă', 'Delfinul', 'Tonul'],
    answer: 'Peștele-spadă',
  ),
  CultureQuestion(
    question: 'Câte inimi are o caracatiță?',
    choices: ['1', '2', '3', '4'],
    answer: '3',
  ),
  CultureQuestion(
    question: 'Ce mănâncă în principal un panda gigant?',
    choices: ['Fructe', 'Bambus', 'Pește', 'Insecte'],
    answer: 'Bambus',
  ),
  CultureQuestion(
    question: 'Care este cel mai mare animal terestru?',
    choices: ['Girafa', 'Rinocerul', 'Elefantul african', 'Hipopotamul'],
    answer: 'Elefantul african',
  ),
  CultureQuestion(
    question: 'Câți ani poate trăi, în medie, o broască țestoasă gigantă?',
    choices: ['~30 de ani', '~50 de ani', '~100 de ani', '~150 de ani'],
    answer: '~150 de ani',
  ),
  CultureQuestion(
    question: 'Ce tip de animal este un delfin?',
    choices: ['Pește', 'Mamifer', 'Amfibian', 'Reptilă'],
    answer: 'Mamifer',
  ),
  CultureQuestion(
    question: 'Care este singurul mamifer capabil de zbor real?',
    choices: ['Veverița zburătoare', 'Liliacul', 'Petrelul', 'Vulpea zburătoare'],
    answer: 'Liliacul',
  ),
  CultureQuestion(
    question: 'Câte picioare are un crab?',
    choices: ['6', '8', '10', '12'],
    answer: '10',
  ),
  CultureQuestion(
    question: 'Care este limba oficială a Braziliei?',
    choices: ['Spaniola', 'Portugheza', 'Franceza', 'Italiana'],
    answer: 'Portugheza',
  ),
  CultureQuestion(
    question: 'Care este cea mai vorbită limbă maternă din lume?',
    choices: ['Engleza', 'Spaniola', 'Chineza mandarină', 'Hindi'],
    answer: 'Chineza mandarină',
  ),
  CultureQuestion(
    question: 'Din câte litere este format alfabetul limbii române?',
    choices: ['26', '28', '31', '33'],
    answer: '31',
  ),
  CultureQuestion(
    question: 'Ce instrument muzical are, de obicei, 88 de clape?',
    choices: ['Acordeonul', 'Orga', 'Pianul', 'Xilofonul'],
    answer: 'Pianul',
  ),
  CultureQuestion(
    question: 'Câte coarde are o chitară clasică?',
    choices: ['4', '5', '6', '7'],
    answer: '6',
  ),
  CultureQuestion(
    question: 'Care este cea mai populată țară din lume?',
    choices: ['SUA', 'China', 'India', 'Indonezia'],
    answer: 'India',
  ),
  CultureQuestion(
    question: 'Care este cea mai folosită rețea de socializare din lume?',
    choices: ['Instagram', 'TikTok', 'Facebook', 'X (Twitter)'],
    answer: 'Facebook',
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
    question: 'Ce înseamnă prescurtarea "www"?',
    choices: ['World Wide Web', 'World Web Wide', 'Web World Wide', 'Wide World Web'],
    answer: 'World Wide Web',
  ),
  CultureQuestion(
    question: 'Care a fost primul telefon mobil comercial din lume?',
    choices: ['Nokia 3310', 'Motorola DynaTAC', 'iPhone', 'Samsung Galaxy'],
    answer: 'Motorola DynaTAC',
  ),
  CultureQuestion(
    question: 'Câte zile are o săptămână?',
    choices: ['5', '6', '7', '8'],
    answer: '7',
  ),
  CultureQuestion(
    question: 'Câte ore are o zi?',
    choices: ['12', '20', '24', '30'],
    answer: '24',
  ),
  CultureQuestion(
    question: 'Ce culoare rezultă din amestecul galben și albastru?',
    choices: ['Portocaliu', 'Verde', 'Violet', 'Maro'],
    answer: 'Verde',
  ),
  CultureQuestion(
    question: 'Câte fețe are un cub?',
    choices: ['4', '6', '8', '12'],
    answer: '6',
  ),
  CultureQuestion(
    question: 'Care este cea mai lungă zi din an (emisfera nordică)?',
    choices: ['21 martie', '21 iunie', '21 septembrie', '21 decembrie'],
    answer: '21 iunie',
  ),
  CultureQuestion(
    question: 'Ce sărbătoare se ține pe 1 decembrie în România?',
    choices: ['Ziua Independenței', 'Ziua Marii Uniri', 'Ziua Culturii', 'Ziua Copilului'],
    answer: 'Ziua Marii Uniri',
  ),
];
