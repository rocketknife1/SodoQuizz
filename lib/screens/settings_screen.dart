import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/ads_service.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/storage_service.dart';
import 'home_screen.dart';
import 'loading_screen.dart';

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
  bool _privacyOptionsRequired = false;

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
    // separat de restul (nu tine incarcarea ecranului) - vizibil doar pentru
    // useri din UE/UK/state americane reglementate, vezi AdsService.
    AdsService.instance.privacyOptionsRequired().then((required) {
      if (mounted && required) setState(() => _privacyOptionsRequired = true);
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

  /// Ștergerea definitivă de cont, disponibilă pentru ORICINE — inclusiv
  /// pentru un Guest, care până acum n-avea nicio cale să-și scoată datele
  /// din cloud (vezi AuthService.deleteAccount). Butonul stă lângă resetul
  /// de progres fiindcă amândouă sunt acțiuni distructive de cont, dar textul
  /// dialogului diferă: la Guest dispare și progresul de pe telefon, la un
  /// cont cu login rămâne.
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    // `AuthService.currentUser` întoarce null și pentru identitatea anonimă,
    // nu doar când chiar nu e nimeni — deci null aici înseamnă exact "Guest".
    final eGuest = AuthService.instance.currentUser == null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Ștergi contul definitiv?', style: TextStyle(color: Colors.white)),
        content: Text(
          eGuest
              ? 'Se șterg definitiv profilul public, prietenii, clasamentul, progresul salvat în cloud ȘI progresul '
                  'de pe acest telefon. Fiind cont de Guest, nu există unde să te reconectezi ca să-l recuperezi. '
                  'Acțiunea nu poate fi anulată.'
              : 'Se șterg definitiv profilul public, prietenii, clasamentul și progresul salvat în cloud pentru acest cont. '
                  'Progresul de pe acest telefon rămâne neatins. Acțiunea nu poate fi anulată.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anulează')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Șterge contul', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.purple)),
    );
    try {
      await AuthService.instance.deleteAccount();
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ștergerea a eșuat. Încearcă din nou.')),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    // Aceeași ieșire ca la reset: se pleacă de la zero, deci nu are sens să
    // rămână în spate ecrane construite pe datele vechi.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoadingScreen(nextBuilder: (_) => const HomeScreen(), duration: const Duration(milliseconds: 900)),
      ),
      (route) => false,
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
                  if (_privacyOptionsRequired) ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => AdsService.instance.showPrivacyOptionsForm(),
                      child: Container(
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
                              child: const Icon(Icons.privacy_tip_rounded, color: AppColors.purple, size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Confidențialitate reclame',
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _confirmDeleteAccount(context),
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
                          Icon(Icons.person_remove_rounded, color: AppColors.danger),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text('Șterge contul definitiv', style: TextStyle(color: AppColors.danger, fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('SodoQuizz — v1.0.0', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
