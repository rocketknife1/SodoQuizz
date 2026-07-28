/// Dataset pentru modul "Higher or Lower" — perechi aleatorii de subiecte
/// comparate după un singur criteriu: cât de mult se caută pe internet.
/// Fără nicio logică de "ce merge cu ce" (un animal poate fi comparat cu un
/// brand sau o țară) — doar popularitatea contează, exact ca la conceptul
/// original (higherlowergame.com), care compară volumul lunar de căutări
/// Google al doi termeni oarecare.
///
/// [popularity] e o ESTIMARE orientativă (milioane de căutări/lună), nu o
/// cifră live/verificată — aplicația nu are acces la date Google Trends în
/// timp real. Valorile sunt alese ca ordine relativă plauzibilă (subiecte
/// foarte cunoscute > subiecte de nișă), suficient de variate ca jocul să
/// fie corect, nu ca un raport statistic real.
class HigherLowerItem {
  final String name;
  final String emoji;
  final double popularity;
  const HigherLowerItem(this.name, this.emoji, this.popularity);
}

/// Id opac folosit peste tot unde acest mod se comportă ca un "gamemod"
/// pentru infrastructura existentă (high score per mod + puncte de
/// Clasament pe ciclul de 48h) — vezi StorageService.updateModeHighScore /
/// addLeaderboardPoints, care tratează orice gameModeId ca string opac.
const String higherLowerModeId = 'higher_lower';

/// Peste subiecte pe scară de căutare orientativă din milioane pe lună —
/// afișare rotunjită potrivit mărimii ("1,5 mld", "82 mil.", "300 mii").
String formatSearchVolume(double millions) {
  if (millions >= 1000) {
    final b = millions / 1000;
    return '${b.toStringAsFixed(b >= 10 ? 0 : 1)} mld/lună';
  }
  if (millions >= 1) {
    return '${millions >= 10 ? millions.round() : millions.toStringAsFixed(1)} mil/lună';
  }
  final k = millions * 1000;
  return '${k.round()} mii/lună';
}

const List<HigherLowerItem> higherLowerItems = [
  // ─── Tehnologie & Internet ─────────────────────────────────────────────
  HigherLowerItem('Google', '🔍', 1600),
  HigherLowerItem('YouTube', '▶️', 1500),
  HigherLowerItem('Facebook', '📘', 1000),
  HigherLowerItem('WhatsApp', '💬', 920),
  HigherLowerItem('Instagram', '📷', 860),
  HigherLowerItem('TikTok', '🎵', 800),
  HigherLowerItem('Amazon', '📦', 720),
  HigherLowerItem('ChatGPT', '🤖', 640),
  HigherLowerItem('Gmail', '📧', 600),
  HigherLowerItem('Netflix', '🎬', 560),
  HigherLowerItem('Wikipedia', '📖', 480),
  HigherLowerItem('X (Twitter)', '🐦', 430),
  HigherLowerItem('Spotify', '🎧', 340),
  HigherLowerItem('Minecraft', '⛏️', 310),
  HigherLowerItem('Fortnite', '🪂', 290),
  HigherLowerItem('Roblox', '🧱', 270),
  HigherLowerItem('PayPal', '💳', 250),
  HigherLowerItem('Zoom', '💻', 230),
  HigherLowerItem('Yahoo', '📰', 210),
  HigherLowerItem('LinkedIn', '🧑‍💼', 190),
  HigherLowerItem('Snapchat', '👻', 175),
  HigherLowerItem('Pinterest', '📌', 160),
  HigherLowerItem('Reddit', '👽', 150),
  HigherLowerItem('Discord', '🎮', 140),
  HigherLowerItem('Telegram', '✈️', 130),
  HigherLowerItem('eBay', '🛒', 120),
  HigherLowerItem('Uber', '🚗', 95),
  HigherLowerItem('Airbnb', '🏠', 85),
  HigherLowerItem('Bitcoin', '₿', 260),
  HigherLowerItem('Inteligența Artificială', '🧠', 220),
  HigherLowerItem('iPhone', '📱', 300),

  // ─── Branduri ───────────────────────────────────────────────────────────
  HigherLowerItem('Coca-Cola', '🥤', 220),
  HigherLowerItem('Pepsi', '🥤', 110),
  HigherLowerItem('McDonald\'s', '🍔', 250),
  HigherLowerItem('KFC', '🍗', 140),
  HigherLowerItem('Starbucks', '☕', 160),
  HigherLowerItem('Nike', '👟', 230),
  HigherLowerItem('Adidas', '👟', 190),
  HigherLowerItem('IKEA', '🛋️', 150),
  HigherLowerItem('Disney', '🏰', 200),
  HigherLowerItem('Samsung', '📱', 240),
  HigherLowerItem('Apple', '🍏', 320),
  HigherLowerItem('Sony', '🎮', 130),
  HigherLowerItem('LEGO', '🧱', 100),
  HigherLowerItem('Barbie', '👱‍♀️', 90),
  HigherLowerItem('Gucci', '👜', 80),
  HigherLowerItem('Rolex', '⌚', 70),
  HigherLowerItem('Ferrari', '🏎️', 110),
  HigherLowerItem('Lamborghini', '🏎️', 95),
  HigherLowerItem('BMW', '🚙', 150),
  HigherLowerItem('Mercedes-Benz', '🚗', 140),
  HigherLowerItem('Toyota', '🚙', 160),
  HigherLowerItem('Tesla', '⚡', 210),

  // ─── Celebrități & Personalități ───────────────────────────────────────
  HigherLowerItem('Cristiano Ronaldo', '⚽', 230),
  HigherLowerItem('Lionel Messi', '⚽', 220),
  HigherLowerItem('Neymar', '⚽', 90),
  HigherLowerItem('Kylian Mbappé', '⚽', 85),
  HigherLowerItem('LeBron James', '🏀', 100),
  HigherLowerItem('Taylor Swift', '🎤', 240),
  HigherLowerItem('Kim Kardashian', '💄', 170),
  HigherLowerItem('Elon Musk', '🚀', 200),
  HigherLowerItem('Justin Bieber', '🎤', 140),
  HigherLowerItem('Beyoncé', '🎤', 130),
  HigherLowerItem('Drake', '🎤', 150),
  HigherLowerItem('Rihanna', '🎤', 145),
  HigherLowerItem('Ariana Grande', '🎤', 135),
  HigherLowerItem('Selena Gomez', '🎤', 125),
  HigherLowerItem('The Weeknd', '🎤', 90),
  HigherLowerItem('Ed Sheeran', '🎤', 100),
  HigherLowerItem('Billie Eilish', '🎤', 95),
  HigherLowerItem('Dua Lipa', '🎤', 80),
  HigherLowerItem('Kanye West', '🎤', 120),
  HigherLowerItem('MrBeast', '🎥', 160),
  HigherLowerItem('PewDiePie', '🎥', 75),
  HigherLowerItem('Lady Gaga', '🎤', 85),
  HigherLowerItem('Michael Jackson', '🕺', 110),
  HigherLowerItem('Barack Obama', '🇺🇸', 130),
  HigherLowerItem('Donald Trump', '🇺🇸', 280),
  HigherLowerItem('Vladimir Putin', '🏛️', 150),
  HigherLowerItem('Papa Francisc', '⛪', 60),
  HigherLowerItem('Will Smith', '🎬', 90),
  HigherLowerItem('Johnny Depp', '🎬', 100),
  HigherLowerItem('Leonardo DiCaprio', '🎬', 80),
  HigherLowerItem('Dwayne Johnson', '🎬', 95),
  HigherLowerItem('Keanu Reeves', '🎬', 70),
  HigherLowerItem('Tom Cruise', '🎬', 65),
  HigherLowerItem('Brad Pitt', '🎬', 60),
  HigherLowerItem('Angelina Jolie', '🎬', 65),
  HigherLowerItem('Jennifer Lopez', '🎤', 75),
  HigherLowerItem('Shakira', '🎤', 70),
  HigherLowerItem('Adele', '🎤', 60),
  HigherLowerItem('Eminem', '🎤', 85),
  HigherLowerItem('Bad Bunny', '🎤', 110),
  HigherLowerItem('Novak Djokovic', '🎾', 45),
  HigherLowerItem('Usain Bolt', '🏃', 40),
  HigherLowerItem('Roger Federer', '🎾', 42),
  HigherLowerItem('Serena Williams', '🎾', 38),

  // ─── Filme, Jocuri & Seriale ───────────────────────────────────────────
  HigherLowerItem('GTA 5', '🎮', 160),
  HigherLowerItem('FIFA', '⚽', 140),
  HigherLowerItem('League of Legends', '🎮', 130),
  HigherLowerItem('Among Us', '🚀', 70),
  HigherLowerItem('Pokémon', '⚡', 180),
  HigherLowerItem('Marvel', '🦸', 190),
  HigherLowerItem('Avengers', '🦸', 150),
  HigherLowerItem('Star Wars', '🚀', 170),
  HigherLowerItem('Harry Potter', '⚡', 200),
  HigherLowerItem('Game of Thrones', '🐉', 140),
  HigherLowerItem('Stranger Things', '🚲', 110),
  HigherLowerItem('Squid Game', '🦑', 130),
  HigherLowerItem('Friends', '☕', 90),
  HigherLowerItem('The Simpsons', '🍩', 80),
  HigherLowerItem('Spider-Man', '🕷️', 160),
  HigherLowerItem('Batman', '🦇', 150),
  HigherLowerItem('Wednesday', '🖤', 100),
  HigherLowerItem('La Casa de Papel', '🎭', 85),
  HigherLowerItem('Breaking Bad', '🧪', 75),

  // ─── Țări ───────────────────────────────────────────────────────────────
  HigherLowerItem('SUA', '🇺🇸', 260),
  HigherLowerItem('China', '🇨🇳', 190),
  HigherLowerItem('India', '🇮🇳', 200),
  HigherLowerItem('Brazilia', '🇧🇷', 140),
  HigherLowerItem('Germania', '🇩🇪', 150),
  HigherLowerItem('Franța', '🇫🇷', 145),
  HigherLowerItem('Marea Britanie', '🇬🇧', 155),
  HigherLowerItem('Japonia', '🇯🇵', 160),
  HigherLowerItem('Rusia', '🇷🇺', 130),
  HigherLowerItem('România', '🇷🇴', 45),
  HigherLowerItem('Italia', '🇮🇹', 135),
  HigherLowerItem('Spania', '🇪🇸', 140),
  HigherLowerItem('Canada', '🇨🇦', 110),
  HigherLowerItem('Australia', '🇦🇺', 100),
  HigherLowerItem('Mexic', '🇲🇽', 120),
  HigherLowerItem('Coreea de Sud', '🇰🇷', 115),
  HigherLowerItem('Turcia', '🇹🇷', 90),
  HigherLowerItem('Egipt', '🇪🇬', 70),
  HigherLowerItem('Grecia', '🇬🇷', 65),
  HigherLowerItem('Portugalia', '🇵🇹', 60),

  // ─── Animale ────────────────────────────────────────────────────────────
  HigherLowerItem('Câine', '🐶', 150),
  HigherLowerItem('Pisică', '🐱', 145),
  HigherLowerItem('Leu', '🦁', 60),
  HigherLowerItem('Tigru', '🐯', 65),
  HigherLowerItem('Elefant', '🐘', 55),
  HigherLowerItem('Panda', '🐼', 70),
  HigherLowerItem('Rechin', '🦈', 50),
  HigherLowerItem('Vultur', '🦅', 30),
  HigherLowerItem('Lup', '🐺', 40),
  HigherLowerItem('Cal', '🐴', 45),
  HigherLowerItem('Iepure', '🐰', 35),
  HigherLowerItem('Șarpe', '🐍', 42),
  HigherLowerItem('Păianjen', '🕷️', 38),
  HigherLowerItem('Pinguin', '🐧', 32),
  HigherLowerItem('Delfin', '🐬', 28),
  HigherLowerItem('Gorilă', '🦍', 20),
  HigherLowerItem('Girafă', '🦒', 22),
  HigherLowerItem('Cangur', '🦘', 18),
  HigherLowerItem('Koala', '🐨', 25),
  HigherLowerItem('Hamster', '🐹', 15),
  HigherLowerItem('Papagal', '🦜', 14),
  HigherLowerItem('Crocodil', '🐊', 24),
  HigherLowerItem('Găină', '🐔', 20),
  HigherLowerItem('Vacă', '🐄', 18),
  HigherLowerItem('Porc', '🐷', 16),
  HigherLowerItem('Albină', '🐝', 26),
  HigherLowerItem('Furnică', '🐜', 12),
  HigherLowerItem('Fluture', '🦋', 19),
  HigherLowerItem('Caracatiță', '🐙', 10),
  HigherLowerItem('Balenă', '🐋', 17),

  // ─── Mâncare & Băuturi ─────────────────────────────────────────────────
  HigherLowerItem('Pizza', '🍕', 130),
  HigherLowerItem('Sushi', '🍣', 90),
  HigherLowerItem('Burger', '🍔', 100),
  HigherLowerItem('Paste', '🍝', 70),
  HigherLowerItem('Ciocolată', '🍫', 80),
  HigherLowerItem('Cafea', '☕', 110),
  HigherLowerItem('Ceai', '🍵', 60),
  HigherLowerItem('Înghețată', '🍦', 65),
  HigherLowerItem('Sandviș', '🥪', 40),
  HigherLowerItem('Tacos', '🌮', 55),
  HigherLowerItem('Salată', '🥗', 35),
  HigherLowerItem('Pâine', '🍞', 30),
  HigherLowerItem('Brânză', '🧀', 32),
  HigherLowerItem('Vin', '🍷', 45),
  HigherLowerItem('Bere', '🍺', 50),
  HigherLowerItem('Măr', '🍎', 28),
  HigherLowerItem('Banană', '🍌', 26),
  HigherLowerItem('Pepene verde', '🍉', 20),
  HigherLowerItem('Shaorma', '🌯', 15),

  // ─── Sport ──────────────────────────────────────────────────────────────
  HigherLowerItem('Fotbal', '⚽', 240),
  HigherLowerItem('Baschet', '🏀', 120),
  HigherLowerItem('Tenis', '🎾', 90),
  HigherLowerItem('Box', '🥊', 70),
  HigherLowerItem('Formula 1', '🏎️', 150),
  HigherLowerItem('Jocurile Olimpice', '🥇', 130),
  HigherLowerItem('NBA', '🏀', 140),
  HigherLowerItem('Cupa Mondială FIFA', '🏆', 200),
  HigherLowerItem('UFC', '🥋', 100),
  HigherLowerItem('Cricket', '🏏', 110),
  HigherLowerItem('Golf', '⛳', 60),
  HigherLowerItem('Înot', '🏊', 45),
  HigherLowerItem('Volei', '🏐', 35),
  HigherLowerItem('Rugby', '🏉', 40),
  HigherLowerItem('Champions League', '🏆', 160),

  // ─── Concepte generale ──────────────────────────────────────────────────
  HigherLowerItem('Vremea', '🌦️', 300),
  HigherLowerItem('Dragoste', '❤️', 90),
  HigherLowerItem('Muzică', '🎵', 250),
  HigherLowerItem('Filme', '🎬', 220),
  HigherLowerItem('Știri', '📰', 210),
  HigherLowerItem('Rețete', '🍳', 140),
  HigherLowerItem('Glume', '😂', 60),
  HigherLowerItem('Meme', '🤣', 130),
  HigherLowerItem('Horoscop', '🔮', 100),
  HigherLowerItem('Loto', '🎰', 70),
  HigherLowerItem('Semnificația viselor', '💭', 45),
  HigherLowerItem('Astrologie', '✨', 55),
];
