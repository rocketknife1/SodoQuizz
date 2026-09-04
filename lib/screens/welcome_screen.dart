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
// REGULILE pe care le respectă ecranul ăsta, cerute explicit („ușor și rapid,
// ca pentru un copil"):
//   1. TREI pași, nu mai mulți. O propoziție fiecare.
//   2. Se ARATĂ, nu se explică — fiecare pas e o mică machetă din piesele
//      reale ale jocului, ca omul să RECUNOASCĂ ce vede când începe.
//   3. Se poate sări oricând.
//   4. Apare O SINGURĂ DATĂ în viața contului.

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _last = 2;

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
    await StorageService.setIntroSeen();
    Analytics.instance.tutorialFinished(pasi: _index + 1);
    if (!mounted) return;
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
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 26 : 8,
                      height: 8,
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
                      _index >= _last
                          ? tr('HAI SĂ JUCĂM!', "LET'S PLAY!")
                          : tr('Mai departe', 'Next'),
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
  const _Step({required this.art, required this.text, required this.textEn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          art,
          const SizedBox(height: 40),
          Text(
            tr(text, textEn),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ],
      ),
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
