import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/ads_service.dart';
import '../core/audio.dart';
import '../core/eco_mode.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/storage_service.dart';
import 'blocked_players_screen.dart';
import 'home_screen.dart';
import 'language_screen.dart';
import 'loading_screen.dart';
import 'music_screen.dart';

/// Setările vizibile oricui.
///
/// „Fără blur" NU mai e aici: era un comutator care făcea toate pozele clare
/// din prima, adică desființa jocul pentru oricine îl apăsa din curiozitate.
/// A fost mutat în panoul de Admin (tab Debug), unde îi e locul ca unealtă de
/// verificare a pozelor — vezi admin_screen.dart.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _musicEnabled = true;
  double _musicVolume = 0.5;
  bool _eco = EcoMode.on;
  bool _loaded = false;
  bool _privacyOptionsRequired = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      StorageService.getMusicEnabled(),
      StorageService.getMusicVolume(),
    ]).then((values) {
      if (!mounted) return;
      setState(() {
        _musicEnabled = values[0] as bool;
        _musicVolume = values[1] as double;
        _loaded = true;
      });
    });
    // separat de restul (nu tine incarcarea ecranului) - vizibil doar pentru
    // useri din UE/UK/state americane reglementate, vezi AdsService.
    AdsService.instance.privacyOptionsRequired().then((required) {
      if (mounted && required) setState(() => _privacyOptionsRequired = true);
    });
  }

  Future<void> _toggleMusic(bool value) async {
    setState(() => _musicEnabled = value);
    await Music.setEnabled(value);
  }

  Future<void> _changeMusicVolume(double value) async {
    setState(() => _musicVolume = value);
    await Music.setVolume(value);
  }

  Future<void> _toggleEco(bool value) async {
    setState(() => _eco = value);
    await EcoMode.setEnabled(value);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Resetezi tot progresul?', 'Reset all progress?'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          tr(
            'Se șterg scorul, monedele, nivelul, vieți, quest-urile și întrebările marcate ca răspunse. Nu poate fi anulat.',
            'Your score, coins, level, lives, quests and answered questions are all wiped. This cannot be undone.',
          ),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Renunță', 'Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Resetează', 'Reset'), style: const TextStyle(color: AppColors.danger)),
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
        title: Text(tr('Ștergi contul definitiv?', 'Delete your account permanently?'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          eGuest
              ? tr(
                  'Se șterg definitiv profilul public, prietenii, clasamentul, progresul salvat în cloud ȘI progresul '
                      'de pe acest telefon. Fiind cont de Guest, nu există unde să te reconectezi ca să-l recuperezi. '
                      'Acțiunea nu poate fi anulată.',
                  'This permanently deletes your public profile, friends, leaderboard entry, cloud save AND the progress '
                      'on this phone. As a Guest account there is nowhere to sign back in to recover it. '
                      'This cannot be undone.',
                )
              : tr(
                  'Se șterg definitiv profilul public, prietenii, clasamentul și progresul salvat în cloud pentru acest cont. '
                      'Progresul de pe acest telefon rămâne neatins. Acțiunea nu poate fi anulată.',
                  'This permanently deletes your public profile, friends, leaderboard entry and cloud save for this account. '
                      'The progress on this phone is left untouched. This cannot be undone.',
                ),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Anulează', 'Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Șterge contul', 'Delete account'), style: const TextStyle(color: AppColors.danger)),
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
        SnackBar(content: Text(tr('Ștergerea a eșuat. Încearcă din nou.', 'Deletion failed. Please try again.'))),
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
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  Text(tr('Setări', 'Settings'),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Limba stă exact unde era înainte „Fără blur" — primul
                  // rând din Setări. E cea mai importantă setare pentru
                  // cineva care tocmai a instalat jocul și nu înțelege nimic
                  // din ecran.
                  _navRow(
                    icon: Icons.language_rounded,
                    color: AppColors.blue,
                    title: tr('Limbă / Language', 'Language / Limbă'),
                    subtitle: '${L10n.current.flag}  ${L10n.current.label}',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageScreen())),
                  ),
                  const SizedBox(height: 14),
                  _navRow(
                    icon: Icons.library_music_rounded,
                    color: AppColors.purple,
                    title: tr('Muzică', 'Music'),
                    subtitle: '${Music.track.emoji}  ${Music.track.name}',
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const MusicScreen()));
                      if (!mounted) return;
                      // Piesa și comutatorul se pot schimba acolo — rândul de
                      // aici și cardul de volum de mai jos trebuie să arate
                      // starea nouă la întoarcere.
                      setState(() {
                        _musicEnabled = Music.isEnabled;
                        _musicVolume = Music.volume;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildEcoCard(),
                  const SizedBox(height: 14),
                  _buildMusicCard(context),
                  if (_privacyOptionsRequired) ...[
                    const SizedBox(height: 14),
                    _navRow(
                      icon: Icons.privacy_tip_rounded,
                      color: AppColors.purple,
                      title: tr('Confidențialitate reclame', 'Ad privacy'),
                      onTap: () => AdsService.instance.showPrivacyOptionsForm(),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Singurul loc din joc de unde se poate DA ÎNAPOI o blocare
                  // — blocarea în sine se face din chat (vezi
                  // widgets/moderation_sheet.dart), unde te și deranjează
                  // cineva, dar acolo nu mai ajungi după ce i-ai ascuns
                  // mesajele.
                  _navRow(
                    icon: Icons.block_rounded,
                    color: AppColors.danger,
                    title: tr('Jucători blocați', 'Blocked players'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BlockedPlayersScreen()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _dangerRow(
                    icon: Icons.restart_alt_rounded,
                    label: tr('Resetează tot progresul', 'Reset all progress'),
                    onTap: () => _confirmReset(context),
                  ),
                  const SizedBox(height: 10),
                  _dangerRow(
                    icon: Icons.person_remove_rounded,
                    label: tr('Șterge contul definitiv', 'Delete account permanently'),
                    onTap: () => _confirmDeleteAccount(context),
                  ),
                  const SizedBox(height: 20),
                  const Text('SodoQuizz — v1.0.0', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cardul Modului Eco. Textul spune ce face CONCRET (animații oprite,
  /// ecran mai stins), nu „optimizează performanța" — jucătorul trebuie să
  /// poată prevedea ce se schimbă înainte să apese, altfel primul lui gând la
  /// vederea meniului nemișcat e că s-a stricat jocul.
  Widget _buildEcoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _eco ? AppColors.play.withAlpha(120) : Colors.white10),
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
                child: const Icon(Icons.eco_rounded, color: AppColors.play, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Mod Eco', 'Eco mode'),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      tr('Mai puțină baterie, telefon mai rece', 'Less battery, cooler phone'),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoSwitch(
                value: _eco,
                activeTrackColor: AppColors.play,
                onChanged: _toggleEco,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tr(
                'Cât e pornit: ecranul jocului stă mai stins, animațiile de fundal '
                '(mascote, planetă, sclipiri) se opresc, iar trecerea dintre ecrane e instantanee. '
                'Se aplică din clipa în care intri în joc, de fiecare dată.',
                'While it is on: the game screen stays dimmer, background animations '
                '(mascots, planet, glows) stop, and screen transitions are instant. '
                'It applies from the moment you open the game, every time.',
              ),
              style: const TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMusicCard(BuildContext context) {
    return Container(
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Muzică de fundal', 'Background music'),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(tr('Separată de sunetele de buton', 'Separate from button sounds'),
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
                const Icon(Icons.volume_down_rounded, color: Colors.white38, size: 18),
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
    );
  }

  /// Rând obișnuit de setare care duce în alt ecran.
  Widget _navRow({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                color: color.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _dangerRow({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.danger.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.danger.withAlpha(120)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppColors.danger, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
