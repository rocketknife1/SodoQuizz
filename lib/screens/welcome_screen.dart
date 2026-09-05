import 'package:flutter/material.dart';

import '../core/analytics.dart';
import '../core/breadcrumbs.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/space_background.dart';
import 'home_screen.dart';

// ─── Primele zece secunde ─────────────────────────────────────────────────
//
// Până acum, un jucător nou pica direct în meniul principal, cu paisprezece
// categorii, roată, planetă, quest-uri și multiplayer deodată. Cine n-a mai
// văzut jocul nu are de unde să știe ce se cere de la el.
//
// Contează mai mult decât pare: reperul public din industrie e că sub 20%
// retenție la ziua 1 se repară onboarding-ul ÎNAINTEA oricărui alt lucru.
// Cine nu înțelege în primele secunde nu se mai întoarce a doua zi.
//
// REGULILE pe care le respectă, cerute explicit („ușor și rapid, ca pentru
// un copil" + „mult mai amplu, treci prin ferestre și moduri RAPID, fără să
// joci în timp real"):
//   1. O propoziție mare pe pagină, plus cel mult un rând mic cu cifra sau
//      regula concretă. Niciodată un paragraf.
//   2. Se ARATĂ, nu se explică — fiecare pas e o machetă din piesele reale
//      ale jocului, ca omul să RECUNOASCĂ lucrul când dă peste el.
//   3. NU se joacă nimic pe bune: totul e desenat, deci trecerea e instant.
//   4. Se poate sări oricând, din primul ecran.
//   5. La prima pornire vine singur; pe urmă se poate revedea oricând din
//      Setări → „Revezi tutorialul".
//
// Douăsprezece pagini, în patru grupe: cum se joacă (3), resursele (2), ce e
// pe ecranul principal (3), multiplayer și puteri (4).

class WelcomeScreen extends StatefulWidget {
  /// `true` cand e deschis din Setari („Revezi tutorialul"), nu la prima
  /// pornire. Schimba DOAR ce se intampla la final: se intoarce de unde a
  /// venit, in loc sa arunce omul in meniu peste ecranul din care a plecat.
  final bool asReplay;
  const WelcomeScreen({super.key, this.asReplay = false});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  int _index = 0;

  /// Indexul ultimei pagini. Se ține aici, nu numărat din `children`, ca
  /// bulinele de jos și textul butonului să nu se desincronizeze niciodată
  /// de conținut — dacă adaugi o pagină, schimbi ȘI cifra asta.
  static const _last = 11;

  @override
  void initState() {
    super.initState();
    Breadcrumbs.drop('a intrat in tutorial');
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    // Se marcheaza si la revizionare: e oricum deja marcat, iar asa nu conteaza
    // pe ce cale a ajuns aici.
    await StorageService.setIntroSeen();
    Analytics.instance.tutorialFinished(pasi: _index + 1);
    if (!mounted) return;
    if (widget.asReplay) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              // „Sari peste" stă sus, mereu la vedere: cine a mai jucat nu
              // trebuie să treacă prin nimic.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, top: 6),
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(
                      tr('Sari peste', 'Skip'),
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: const [
                    // ── Cum se joacă (3) ──
                    _Step(
                      art: _BlurredPhotoArt(),
                      text: 'Vezi o poză neclară.',
                      textEn: 'You see a blurry photo.',
                    ),
                    _Step(
                      art: _AnswersArt(),
                      text: 'Alegi una din patru.',
                      textEn: 'You pick one of four.',
                    ),
                    _Step(
                      art: _CoinsArt(),
                      text: 'Ai ghicit? Iei monede.',
                      textEn: 'Got it right? You earn coins.',
                      sub: 'Cu cât poza e mai neclară când răspunzi, cu atât iei mai mult.',
                      subEn: 'The blurrier the photo when you answer, the more you get.',
                    ),
                    // ── Resurse (2) ──
                    _Step(
                      art: _ResourcesArt(),
                      text: 'Astea sunt cele patru resurse.',
                      textEn: 'These are your four resources.',
                      sub: 'Începi cu 173 monede, 7 vieți și 9 hint-uri.',
                      subEn: 'You start with 173 coins, 7 lives and 9 hints.',
                    ),
                    _Step(
                      art: _HintArt(),
                      text: 'Nu știi? Cere un hint.',
                      textEn: 'Stuck? Buy a hint.',
                      sub: 'Costă monede și limpezește poza. O viață se pierde la răspuns greșit.',
                      subEn: 'It costs coins and clears the photo. A wrong answer costs a life.',
                    ),
                    // ── Ce e pe ecranul principal (3) ──
                    _Step(
                      art: _WheelArt(),
                      text: 'Roata Norocului — o dată pe zi.',
                      textEn: 'Lucky Wheel — once a day.',
                      sub: 'Cel mai mare premiu dintr-o singură apăsare. Merită să revii.',
                      subEn: 'The biggest prize from a single tap. Worth coming back for.',
                    ),
                    _Step(
                      art: _ClippyArt(),
                      text: 'Clippy îți dă ceva la 5 minute.',
                      textEn: 'Clippy gives you something every 5 minutes.',
                      sub: 'Agrafa din colț. Când are bulină, te așteaptă un bonus.',
                      subEn: 'The paperclip in the corner. A dot means a bonus is waiting.',
                    ),
                    _Step(
                      art: _PlanetArt(),
                      text: 'Planeta hologramelor.',
                      textEn: 'The hologram planet.',
                      sub: '17 întrebări clare, fără blur. Două rulări, apoi pauză 12 ore.',
                      subEn: '17 clear questions, no blur. Two runs, then a 12-hour break.',
                    ),
                    // ── Multiplayer (2) ──
                    _Step(
                      art: _ModesArt(),
                      text: 'Șase moduri în multiplayer.',
                      textEn: 'Six multiplayer modes.',
                      sub: 'De la Clasic la tancuri, cursă cu obstacole și scaunul electric.',
                      subEn: 'From Classic to tanks, obstacle race and the electric chair.',
                    ),
                    _Step(
                      art: _StakeArt(),
                      text: 'Mizezi monede. Câștigi, iei tot.',
                      textEn: 'You bet coins. Win and take the pot.',
                      sub: 'Miza o alege cine face camera. Poți juca și cu prietenii, pe cod.',
                      subEn: 'The host sets the stake. You can play friends with a code.',
                    ),
                    // ── Puterile (2) ──
                    _Step(
                      art: _PowerUpsArt(),
                      text: 'În meci pică puteri.',
                      textEn: 'Power-ups drop during matches.',
                      sub: 'Apar ca iconițe. Le apeși când vrei să le folosești.',
                      subEn: 'They show up as icons. Tap one to use it.',
                    ),
                    _Step(
                      art: _PowerUpListArt(),
                      text: 'Ce face fiecare.',
                      textEn: 'What each one does.',
                      titleFirst: true,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i <= _last; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: i == _index ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.purple : Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton(
                    onPressed: () {
                      if (_index >= _last) {
                        _finish();
                      } else {
                        _pages.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _index >= _last
                          ? AppColors.play
                          : AppColors.purple,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    child: Text(
                      _index < _last
                          ? tr('Mai departe', 'Next')
                          : widget.asReplay
                              ? tr('Gata', 'Done')
                              : tr('HAI SĂ JUCĂM!', "LET'S PLAY!"),
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final Widget art;
  final String text;
  final String textEn;

  /// Al doilea rând, mai mic — cifra sau regula concretă. Opțional dinadins:
  /// paginile de la început n-au nevoie de el, iar un tutorial în care fiecare
  /// pas are două paragrafe nu se mai citește.
  final String? sub;
  final String? subEn;

  /// Titlul ÎNAINTEA ilustrației. Implicit e invers (arată, apoi explică),
  /// dar la o pagină-listă titlul de dedesubt se citește ca o notă de subsol.
  final bool titleFirst;

  const _Step({
    required this.art,
    required this.text,
    required this.textEn,
    this.sub,
    this.subEn,
    this.titleFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    // Derulabil: paginile cu multe iconițe (puterile) sunt mai înalte decât
    // ecranul pe telefoanele mici, iar un tutorial care dă overflow galben-negru
    // e mai rău decât niciun tutorial.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!titleFirst) ...[art, const SizedBox(height: 32)],
          Text(
            tr(text, textEn),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 12),
            Text(
              tr(sub!, subEn ?? sub!),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
          if (titleFirst) ...[const SizedBox(height: 26), art],
        ],
      ),
    );
  }
}

/// Un cerc colorat cu iconiță — cărămida din care sunt făcute majoritatea
/// ilustrațiilor de mai jos.
class _Bubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _Bubble(this.icon, this.color, {this.size = 64});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withAlpha(38),
          border: Border.all(color: color, width: 2.5),
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// Cele patru resurse, în ordinea din bara de sus a jocului.
class _ResourcesArt extends StatelessWidget {
  const _ResourcesArt();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.favorite_rounded, AppColors.life, 'vieți', 'lives'),
      (Icons.tips_and_updates_rounded, AppColors.hint, 'hint-uri', 'hints'),
      (Icons.diamond_rounded, Color(0xFF5EC8F2), 'gems', 'gems'),
      (Icons.monetization_on_rounded, AppColors.coin, 'monede', 'coins'),
    ];
    return Wrap(
      spacing: 18,
      runSpacing: 14,
      alignment: WrapAlignment.center,
      children: [
        for (final (icon, color, ro, en) in items)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Bubble(icon, color, size: 58),
              const SizedBox(height: 6),
              Text(tr(ro, en),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
      ],
    );
  }
}

class _HintArt extends StatelessWidget {
  const _HintArt();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _Bubble(Icons.blur_on_rounded, Colors.white30, size: 62),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.arrow_forward_rounded,
                color: AppColors.hint, size: 28),
          ),
          const _Bubble(Icons.image_rounded, AppColors.hint, size: 62),
        ],
      );
}

class _WheelArt extends StatelessWidget {
  const _WheelArt();

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(colors: [
                AppColors.orange,
                AppColors.coin,
                AppColors.play,
                AppColors.teal,
                AppColors.purple,
                AppColors.orange,
              ]),
            ),
          ),
          Container(
            width: 66,
            height: 66,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFF0F172A)),
            child: const Icon(Icons.star_rounded,
                color: AppColors.coin, size: 34),
          ),
        ],
      );
}

class _ClippyArt extends StatelessWidget {
  const _ClippyArt();

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          const _Bubble(Icons.attach_file_rounded, Colors.white70, size: 110),
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.danger),
              child: const Center(
                child: Text('1',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
              ),
            ),
          ),
        ],
      );
}

class _PlanetArt extends StatelessWidget {
  const _PlanetArt();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [
                  Color(0xFFE08A3C),
                  Color(0xFF9C5A22),
                ]),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.orange.withAlpha(70), blurRadius: 26),
                ],
              ),
            ),
            for (final o in const [
              (Offset(-72, -34), Icons.pets_rounded, AppColors.teal),
              (Offset(70, -12), Icons.flag_rounded, AppColors.purple),
              (Offset(-52, 46), Icons.directions_car_rounded, AppColors.danger),
            ])
              Transform.translate(
                offset: o.$1,
                child: _Bubble(o.$2, o.$3, size: 40),
              ),
          ],
        ),
      );
}

class _ModesArt extends StatelessWidget {
  const _ModesArt();

  @override
  Widget build(BuildContext context) {
    const modes = [
      (Icons.quiz_rounded, AppColors.purple, 'Clasic', 'Classic'),
      (Icons.swap_vert_rounded, AppColors.teal, 'Higher & Lower', 'Higher & Lower'),
      (Icons.military_tech_rounded, AppColors.danger, 'Tancuri', 'Tanks'),
      (Icons.terrain_rounded, AppColors.play, 'Obby', 'Obby'),
      (Icons.electric_bolt_rounded, AppColors.coin, 'Scaunul Electric', 'Electric Chair'),
      (Icons.back_hand_rounded, AppColors.orange, 'Piatră-Hârtie', 'Rock-Paper'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        for (final (icon, color, ro, en) in modes)
          SizedBox(
            width: 92,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Bubble(icon, color, size: 50),
                const SizedBox(height: 6),
                Text(tr(ro, en),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11, height: 1.25)),
              ],
            ),
          ),
      ],
    );
  }
}

class _StakeArt extends StatelessWidget {
  const _StakeArt();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _Bubble(Icons.person_rounded,
                      i == 1 ? AppColors.play : Colors.white38,
                      size: i == 1 ? 62 : 48),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.coin.withAlpha(30),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.coin, width: 2),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monetization_on_rounded,
                    color: AppColors.coin, size: 22),
                SizedBox(width: 8),
                Text('miza',
                    style: TextStyle(
                        color: AppColors.coin,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ],
            ),
          ),
        ],
      );
}

class _PowerUpsArt extends StatelessWidget {
  const _PowerUpsArt();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _Bubble(Icons.rocket_launch_rounded, AppColors.danger, size: 56),
              SizedBox(width: 12),
              _Bubble(Icons.shield_rounded, AppColors.teal, size: 56),
              SizedBox(width: 12),
              _Bubble(Icons.content_cut_rounded, AppColors.purple, size: 56),
            ],
          ),
          const SizedBox(height: 14),
          Icon(Icons.touch_app_rounded,
              color: Colors.white.withAlpha(140), size: 32),
        ],
      );
}

/// Lista completă a puterilor. Numele și descrierile sunt scurtate dinadins
/// față de `powerUpNames`/`powerUpDescriptions` — aici omul le vede prima
/// dată, nu are nevoie de nuanțe, ci să recunoască iconița în meci.
class _PowerUpListArt extends StatelessWidget {
  const _PowerUpListArt();

  @override
  Widget build(BuildContext context) {
    const list = [
      (Icons.content_cut_rounded, AppColors.purple, 'Două variante greșite dispar', 'Two wrong answers vanish'),
      (Icons.visibility_rounded, AppColors.teal, 'Vezi ce a răspuns altcineva', "See someone else's answer"),
      (Icons.shield_rounded, AppColors.teal, 'Blochezi loviturile o rundă', 'Block hits for a round'),
      (Icons.health_and_safety_rounded, AppColors.play, 'Aperi pe altcineva 2 runde', 'Protect someone 2 rounds'),
      (Icons.flip_camera_android_rounded, AppColors.orange, 'Cine te lovește încasează el', 'Attackers take it instead'),
      (Icons.rocket_launch_rounded, AppColors.danger, 'Lovitură imposibil de evitat', 'A hit nobody can dodge'),
      (Icons.filter_2_rounded, AppColors.danger, 'Două proiectile deodată', 'Two shots at once'),
      (Icons.bolt_rounded, AppColors.coin, 'Trece prin scut', 'Goes through shields'),
      (Icons.build_rounded, AppColors.play, 'Recuperezi viață', 'Recover life'),
      (Icons.rocket_rounded, AppColors.purple, 'Treci obstacolul automat', 'Clear the obstacle'),
      (Icons.dangerous_rounded, AppColors.orange, 'Strici placa cuiva', "Ruin someone's platform"),
    ];
    return Column(
      children: [
        for (final (icon, color, ro, en) in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                _Bubble(icon, color, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr(ro, en),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13.5, height: 1.3)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Pasul 1 — o „poză" neclară cu semn de întrebare. Nu o imagine reală: nu
/// vrem să ardem o întrebare adevărată în tutorial.
class _BlurredPhotoArt extends StatelessWidget {
  const _BlurredPhotoArt();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      height: 175,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B4A7A), Color(0xFF6C4AA8), Color(0xFF2E6B7A)],
        ),
        border: Border.all(color: Colors.white24, width: 2),
      ),
      child: const Center(
        child: Text('?',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 82,
                fontWeight: FontWeight.w900)),
      ),
    );
  }
}

/// Pasul 2 — patru variante, a treia bifată. Aceleași forme ca în joc, ca
/// omul să le recunoască imediat.
class _AnswersArt extends StatelessWidget {
  const _AnswersArt();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 250,
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: i == 2 ? AppColors.play.withAlpha(55) : Colors.white10,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: i == 2 ? AppColors.play : Colors.white24,
                width: i == 2 ? 2.5 : 1.5,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Text(
                  String.fromCharCode(65 + i), // A B C D
                  style: TextStyle(
                    color: i == 2 ? AppColors.play : Colors.white38,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: i == 2 ? AppColors.play.withAlpha(120) : Colors.white24,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                if (i == 2)
                  const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(Icons.check_circle_rounded,
                        color: AppColors.play, size: 22),
                  ),
                const SizedBox(width: 14),
              ],
            ),
          ),
      ],
    );
  }
}

/// Pasul 3 — recompensa. Moneda mare, cu „+" ca la încasare.
class _CoinsArt extends StatelessWidget {
  const _CoinsArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 175,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.coin.withAlpha(38),
              border: Border.all(color: AppColors.coin, width: 4),
            ),
            child: const Icon(Icons.monetization_on_rounded,
                color: AppColors.coin, size: 74),
          ),
          Positioned(
            top: 14,
            right: 24,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.play,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text('+100',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }
}
