import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/category_unlock_animation.dart';
import '../widgets/coin_reward_overlay.dart';
import 'home_screen.dart';
import 'loading_screen.dart';
import 'test_images_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _noBlur = false;
  bool _musicEnabled = true;
  double _musicVolume = 0.5;
  bool _loaded = false;

  // Ținte fixe pentru butonul de test "PREVIEW RECOMPENSE" — imită pastilele
  // reale din header-ul Home, dar fără să depindă de starea reală a jocului.
  final _coinPreviewKey = GlobalKey();
  final _xpPreviewKey = GlobalKey();
  final _livesPreviewKey = GlobalKey();
  final _hintsPreviewKey = GlobalKey();
  final _gemsPreviewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    Future.wait([
      StorageService.getNoBlurMode(),
      StorageService.getMusicEnabled(),
      StorageService.getMusicVolume(),
    ]).then((values) {
      if (!mounted) return;
      setState(() {
        _noBlur = values[0] as bool;
        _musicEnabled = values[1] as bool;
        _musicVolume = values[2] as double;
        _loaded = true;
      });
    });
  }

  Future<void> _toggleNoBlur(bool value) async {
    setState(() => _noBlur = value);
    await StorageService.setNoBlurMode(value);
  }

  Future<void> _toggleMusic(bool value) async {
    setState(() => _musicEnabled = value);
    await Music.setEnabled(value);
  }

  Future<void> _changeMusicVolume(double value) async {
    setState(() => _musicVolume = value);
    await Music.setVolume(value);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Resetezi tot progresul?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Se șterg scorul, monedele, nivelul, vieți, quest-urile și întrebările marcate ca răspunse. Nu poate fi anulat.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resetează', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await StorageService.resetAll();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoadingScreen(nextBuilder: (_) => const HomeScreen(), duration: const Duration(milliseconds: 900)),
      ),
      (route) => false,
    );
  }

  /// Rulează, pe rând, aceeași animație de zbor (CoinRewardOverlay) folosită
  /// la colectarea reală de monede/XP/vieți/hints/gems — dar fără să scrie
  /// nimic în storage, doar ca previzualizare vizuală rapidă (vezi și
  /// [CategoryUnlockAnimation] preview de mai sus).
  Future<void> _previewRewardAnimations(BuildContext context) async {
    Future<void> stage({required int amount, required IconData icon, required Color color, required GlobalKey targetKey}) async {
      final impactCompleter = Completer<void>();
      CoinRewardOverlay.show(
        context,
        amount: amount,
        targetKey: targetKey,
        icon: icon,
        color: color,
        flightDuration: const Duration(milliseconds: 1000),
        serpentine: true,
        onImpact: () {
          if (!impactCompleter.isCompleted) impactCompleter.complete();
        },
      );
      await impactCompleter.future;
      await Future.delayed(const Duration(milliseconds: 120));
    }

    await stage(amount: 25, icon: Icons.monetization_on_rounded, color: AppColors.coin, targetKey: _coinPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 40, icon: Icons.star_rounded, color: AppColors.purple, targetKey: _xpPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 1, icon: Icons.favorite_rounded, color: AppColors.life, targetKey: _livesPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 1, icon: Icons.tips_and_updates_rounded, color: AppColors.hint, targetKey: _hintsPreviewKey);
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
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('999 vieți, 999 hint-uri, +99999 monede, +9999 gems (test)'), duration: Duration(milliseconds: 1500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 12),
              child: Row(
                children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                  const SizedBox(width: 4),
                  const Text('Setări', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
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
                              Text('Pozele apar 100% clare, din prima', style: TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _loaded
                            ? CupertinoSwitch(
                                value: _noBlur,
                                activeTrackColor: AppColors.play,
                                onChanged: _toggleNoBlur,
                              )
                            : const SizedBox(width: 51, height: 31),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: AppColors.play.withAlpha(40),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _musicEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
                                color: AppColors.play,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Muzică de fundal', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                                  SizedBox(height: 2),
                                  Text('Separată de sunetele de buton', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _loaded
                                ? CupertinoSwitch(
                                    value: _musicEnabled,
                                    activeTrackColor: AppColors.play,
                                    onChanged: _toggleMusic,
                                  )
                                : const SizedBox(width: 51, height: 31),
                          ],
                        ),
                        if (_loaded) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.volume_down_rounded, color: Colors.white38, size: 18),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: AppColors.play,
                                    inactiveTrackColor: Colors.white12,
                                    thumbColor: AppColors.play,
                                    overlayColor: AppColors.play.withAlpha(40),
                                    trackHeight: 3,
                                  ),
                                  child: Slider(
                                    value: _musicVolume,
                                    onChanged: _musicEnabled ? _changeMusicVolume : null,
                                  ),
                                ),
                              ),
                              const Icon(Icons.volume_up_rounded, color: Colors.white38, size: 18),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => _confirmReset(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withAlpha(30),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.danger.withAlpha(120)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.restart_alt_rounded, color: AppColors.danger),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text('Resetează tot progresul', style: TextStyle(color: AppColors.danger, fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
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
                    onTap: () => CategoryUnlockAnimation.show(context, categoryTitle: 'Categorie de test', unlockedCount: 15),
                  ),
                  const SizedBox(height: 12),
                  // ținte fixe pentru animația de zbor de mai jos — trebuie
                  // să existe deja pe ecran (randate) când pornește zborul,
                  // la fel ca pastilele reale din header-ul Home.
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
                  const SizedBox(height: 20),
                  const Text('Guess It — v1.0.0', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Butoane de test — la fel de vizibile ca butoanele de meniu (culoare
  /// solidă + iconiță), nu chip-uri mici de colț.
  /// TEST: verifica doar pozele inlocuite manual (vezi
  /// TestImagesScreen.testQuestionIds), fara sa afecteze scorul real.
  /// UNLIMITED: umple vieti + hint-uri la 999, pentru testare rapida.
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
}
