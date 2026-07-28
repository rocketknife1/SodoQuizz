import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';

/// Popup de introducere arătat automat la prima intrare în joc — explică
/// pe scurt conceptul (categorii, deblocare treptată, monede/gems, vieți,
/// roata cu bundle-uri, Cultura Generală, clasament) unei audiențe de
/// ~13 ani. Bifa "Nu mai arăta asta" e per-dispozitiv (StorageService) și
/// odată bifată nu mai reapare niciodată.
class IntroTutorialDialog extends StatefulWidget {
  const IntroTutorialDialog({super.key});

  /// Verifică flag-ul salvat și arată popup-ul o singură dată dacă nu a
  /// fost deja văzut/bifat "nu mai arăta". Se apelează din home screen,
  /// după primul frame, ca să nu concureze cu construcția ecranului.
  static Future<void> maybeShow(BuildContext context) async {
    final seen = await StorageService.getIntroSeen();
    if (seen || !context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const IntroTutorialDialog(),
    );
  }

  @override
  State<IntroTutorialDialog> createState() => _IntroTutorialDialogState();
}

class _IntroPage {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _IntroPage({required this.icon, required this.color, required this.title, required this.body});
}

class _IntroTutorialDialogState extends State<IntroTutorialDialog> {
  final _controller = PageController();
  int _page = 0;
  bool _dontShowAgain = false;

  static final _pages = [
    const _IntroPage(
      icon: Icons.emoji_events_rounded,
      color: AppColors.purple,
      title: 'Bun venit la Sodo Quizz!',
      body: 'Răspunzi la întrebări din categorii diferite, câștigi monede, '
          'gems, XP și urci în nivel. Cu cât știi mai multe, cu atât '
          'deblochezi mai mult din joc!',
    ),
    const _IntroPage(
      icon: Icons.category_rounded,
      color: AppColors.blue,
      title: 'Categorii și deblocare',
      body: 'Fiecare categorie are propriul set de întrebări. Nu sunt toate '
          'deblocate deodată: pe măsură ce răspunzi corect, deblochezi '
          'următorul lot de întrebări cu gems, câte puțin câte puțin.',
    ),
    const _IntroPage(
      icon: Icons.favorite_rounded,
      color: AppColors.life,
      title: 'Vieți și gems',
      body: 'Ai un număr limitat de vieți — pierzi una la un răspuns greșit '
          'și se reface singură cu timpul. Gems sunt moneda specială cu care '
          'deblochezi întrebări noi sau cumperi vieți în plus.',
    ),
    const _IntroPage(
      icon: Icons.donut_large_rounded,
      color: AppColors.orange,
      title: 'Roata norocului',
      body: 'O dată pe zi poți învârti roata și poți câștiga monede, XP, '
          'hint-uri, gems sau chiar vieți — iar dacă ai mare noroc, poți '
          'lovi jackpot-ul: vieți nelimitate timp de 24 de ore!',
    ),
    const _IntroPage(
      icon: Icons.public_rounded,
      color: AppColors.teal,
      title: 'Cultură Generală și Clasament',
      body: 'Categoria Cultură Generală se poate juca de maximum 3 ori la '
          'fiecare 15 minute. Punctele tale contează și pentru Clasament, '
          'care se resetează la fiecare 48 de ore — încearcă să prinzi '
          'podiumul!',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await StorageService.setIntroSeen(_dontShowAgain);
    if (mounted) Navigator.of(context).pop();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    final isLast = _page == _pages.length - 1;
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 250,
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _buildPage(_pages[i]),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active ? page.color : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Checkbox(
                      value: _dontShowAgain,
                      onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
                      activeColor: AppColors.purple,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    const Expanded(
                      child: Text(
                        'Nu mai arăta asta din nou',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _next,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [page.color.withAlpha(230), page.color],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: page.color.withAlpha(110), blurRadius: 12, offset: const Offset(0, 5)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  isLast ? 'Am înțeles, hai să joc!' : 'Mai departe',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_IntroPage page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: page.color.withAlpha(45),
            shape: BoxShape.circle,
            border: Border.all(color: page.color.withAlpha(140), width: 2),
          ),
          child: Icon(page.icon, color: page.color, size: 34),
        ),
        const SizedBox(height: 18),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
