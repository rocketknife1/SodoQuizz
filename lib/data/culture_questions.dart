/// Întrebare de cultură generală — text simplu, fără imagine, 4 variante.
/// Folosită doar de [CultureQuizPanel] de pe Home, nu de GameScreen.
/// Pool curatoriat de 60 de întrebări; fiecare lot (beta, nelimitat) alege
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
];
