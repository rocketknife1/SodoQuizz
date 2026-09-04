// Unelte de verificare: fără blur, vezi răspunsul, provoacă un crash.
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos): panoul de Admin era
// un singur fișier de peste 3.000 de linii, imposibil de ținut în cap. E
// împărțit pe tab-uri, nu pe tipuri de clase, fiindcă asta e granița după
// care se lucrează la el în practică.
part of '../admin_screen.dart';

/// Unelte de debug/test — mutate 1:1 din SettingsScreen (acolo erau vizibile
/// oricui, fără nicio filtrare de cont). TEST verifică doar pozele
/// înlocuite manual (TestImagesScreen.testQuestionIds), fără să afecteze
/// scorul real; UNLIMITED umple resursele la maxim, pentru testare rapidă.
class _DebugTab extends StatefulWidget {
  const _DebugTab();

  @override
  State<_DebugTab> createState() => _DebugTabState();
}

class _DebugTabState extends State<_DebugTab> {
  final _coinPreviewKey = GlobalKey();
  final _xpPreviewKey = GlobalKey();
  final _livesPreviewKey = GlobalKey();
  final _hintsPreviewKey = GlobalKey();
  final _gemsPreviewKey = GlobalKey();

  bool _noBlur = false;
  bool _noBlurLoaded = false;
  bool _revealAnswers = false;
  bool _revealAnswersLoaded = false;

  @override
  void initState() {
    super.initState();
    StorageService.getNoBlurMode().then((value) {
      if (!mounted) return;
      setState(() {
        _noBlur = value;
        _noBlurLoaded = true;
      });
    });
    StorageService.getAdminAnswerReveal().then((value) {
      if (!mounted) return;
      setState(() {
        _revealAnswers = value;
        _revealAnswersLoaded = true;
      });
    });
  }

  Future<void> _toggleNoBlur(bool value) async {
    setState(() => _noBlur = value);
    await StorageService.setNoBlurMode(value);
  }

  Future<void> _toggleRevealAnswers(bool value) async {
    setState(() => _revealAnswers = value);
    await setAdminAnswerReveal(value);
  }

  /// Rulează, pe rând, aceeași animație de zbor (CoinRewardOverlay) folosită
  /// la colectarea reală de monede/XP/vieți/hints/gems — dar fără să scrie
  /// nimic în storage, doar ca previzualizare vizuală rapidă.
  Future<void> _previewRewardAnimations(BuildContext context) async {
    Future<void> stage({
      required int amount,
      required IconData icon,
      required Color color,
      required GlobalKey targetKey,
    }) async {
      final impactCompleter = Completer<void>();
      CoinRewardOverlay.show(
        context,
        amount: amount,
        targetKey: targetKey,
        icon: icon,
        color: color,
        onImpact: () {
          if (!impactCompleter.isCompleted) impactCompleter.complete();
        },
      );
      await impactCompleter.future;
      await Future.delayed(const Duration(milliseconds: 280));
    }

    await stage(amount: 25, icon: Icons.monetization_on_rounded, color: AppColors.coin, targetKey: _coinPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 40, icon: Icons.star_rounded, color: AppColors.purple, targetKey: _xpPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 4, icon: Icons.favorite_rounded, color: AppColors.life, targetKey: _livesPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 3, icon: Icons.tips_and_updates_rounded, color: AppColors.hint, targetKey: _hintsPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 3, icon: Icons.diamond_rounded, color: const Color(0xFF5EC8F2), targetKey: _gemsPreviewKey);
  }

  Widget _buildPreviewBadge(GlobalKey key, IconData icon, Color color) {
    return Container(
      key: key,
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: color.withAlpha(50), shape: BoxShape.circle, border: Border.all(color: color)),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 17),
    );
  }

  Future<void> _grantUnlimited(BuildContext context) async {
    await StorageService.setLives(999);
    final currentHints = await StorageService.getHints();
    if (currentHints < 999) await StorageService.addHintsUncapped(999 - currentHints);
    await StorageService.addCoins(99999);
    await StorageService.addGems(9999);
    await StorageService.debugUnlockAllQuestsAndAchievements();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('999 vieți, 999 hint-uri, +99999 monede, +9999 gems, toate quest-urile + realizările gata de revendicat (test)'),
          duration: Duration(milliseconds: 2200)),
    );
  }

  /// Butoane de test — la fel de vizibile ca butoanele de meniu (culoare
  /// solidă + iconiță), nu chip-uri mici de colț.
  Widget _buildDevToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withAlpha(210)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withAlpha(100), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDevToolButton(
                  icon: Icons.image_search_rounded,
                  label: 'TEST',
                  color: AppColors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TestImagesScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDevToolButton(
                  icon: Icons.all_inclusive_rounded,
                  label: 'UNLIMITED',
                  color: AppColors.orange,
                  onTap: () => _grantUnlimited(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDevToolButton(
            icon: Icons.lock_open_rounded,
            label: 'PREVIEW ANIMAȚIE DEBLOCARE',
            color: AppColors.purple,
            onTap: () => CategoryUnlockAnimation.show(
              context,
              categoryTitle: 'Categorie de test',
              unlockedCount: 15,
              color: AppColors.teal,
              icon: Icons.public_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPreviewBadge(_coinPreviewKey, Icons.monetization_on_rounded, AppColors.coin),
              _buildPreviewBadge(_xpPreviewKey, Icons.star_rounded, AppColors.purple),
              _buildPreviewBadge(_livesPreviewKey, Icons.favorite_rounded, AppColors.life),
              _buildPreviewBadge(_hintsPreviewKey, Icons.tips_and_updates_rounded, AppColors.hint),
              _buildPreviewBadge(_gemsPreviewKey, Icons.diamond_rounded, const Color(0xFF5EC8F2)),
            ],
          ),
          const SizedBox(height: 8),
          _buildDevToolButton(
            icon: Icons.auto_awesome_rounded,
            label: 'PREVIEW RECOMPENSE',
            color: AppColors.teal,
            onTap: () => _previewRewardAnimations(context),
          ),
          const SizedBox(height: 16),
          _buildNoBlurCard(),
          const SizedBox(height: 10),
          _buildRevealAnswersCard(),
          const SizedBox(height: 16),
          _buildDevToolButton(
            icon: Icons.bolt_rounded,
            label: 'TEST: PROVOACĂ UN CRASH',
            color: AppColors.danger,
            onTap: () => _confirmTestCrash(context),
          ),
        ],
      ),
    );
  }

  /// Crapă aplicația DINADINS, ca să se poată verifica lanțul de raportare.
  ///
  /// DE CE E PERMANENT, nu o unealtă de o dată: raportarea crash-urilor e
  /// singurul sistem care nu se poate proba altfel — nu poți ști că merge
  /// decât provocând un crash real. Iar ea se poate strica tăcut la orice
  /// upgrade de SDK sau schimbare de chei, exact când ai nevoie de ea.
  /// După orice modificare mare, se apasă aici și se verifică în consola
  /// Firebase → Crashlytics că a apărut.
  ///
  /// Crash-ul e ADEVĂRAT: aplicația chiar moare. Progresul nesalvat se pierde,
  /// de-aia întreabă întâi.
  Future<void> _confirmTestCrash(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Închizi aplicația dinadins?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Aplicația se va închide pe loc. E singurul mod de a verifica dacă '
          'raportarea crash-urilor chiar funcționează.\n\n'
          'Raportul apare în Firebase → Crashlytics în câteva minute. La '
          'următoarea pornire se trimite singur.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Renunță')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crapă acum',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // O firimitură înainte, ca raportul să arate că a fost intenționat — și
    // ca să se vadă în el că urma de acțiuni chiar ajunge la Crashlytics.
    Breadcrumbs.drop('TEST: crash provocat din panoul de Admin');
    FirebaseCrashlytics.instance.crash();
  }

  /// „Vezi răspunsul corect" — cât e pornit, varianta corectă a oricărei
  /// întrebări cu 4 variante e conturată cu chihlimbar, ORIUNDE în joc
  /// (singleplayer, multiplayer, Cultură Generală, Planeta hologramelor).
  /// Doar pentru contul de admin — vezi core/admin_reveal.dart pentru al
  /// doilea gard (pref-ul singur nu ajunge).
  Widget _buildRevealAnswersCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107).withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.visibility_rounded, color: Color(0xFFFFC107), size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vezi răspunsul corect', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Varianta corectă e conturată cu chihlimbar, oriunde în joc — doar pentru tine',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _revealAnswersLoaded
              ? CupertinoSwitch(
                  value: _revealAnswers,
                  activeTrackColor: AppColors.play,
                  onChanged: _toggleRevealAnswers,
                )
              : const SizedBox(width: 51, height: 31),
        ],
      ),
    );
  }

  /// „Fără blur" — mutat aici din SettingsScreen, unde îl vedea orice
  /// jucător. Acolo nu era o setare de accesibilitate, ci un buton care
  /// desființa jocul: pozele apăreau clare din prima, deci nu mai era nimic
  /// de ghicit. Ca unealtă de verificat pozele adăugate manual, în schimb,
  /// e exact ce trebuie — de-aia stă lângă TEST.
  Widget _buildNoBlurCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.purple.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.blur_off_rounded, color: AppColors.purple, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fără blur', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Pozele apar 100% clare, din prima — pentru verificarea lor',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _noBlurLoaded
              ? CupertinoSwitch(
                  value: _noBlur,
                  activeTrackColor: AppColors.play,
                  onChanged: _toggleNoBlur,
                )
              : const SizedBox(width: 51, height: 31),
        ],
      ),
    );
  }
}
