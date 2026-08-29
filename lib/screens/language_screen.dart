import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import 'home_screen.dart';
import 'loading_screen.dart';

/// Alegerea limbii interfeței. Vezi [L10n] pentru cum e tradus jocul și ce
/// anume rămâne, deliberat, în română.
///
/// După alegere se pleacă în meniul principal, prin ecranul de încărcare —
/// același drum folosit după un reset de progres. Nu e o scurtătură: ecranele
/// deja deschise în spate își țin textele construite, deci o simplă întoarcere
/// le-ar fi lăsat în limba veche. Trecerea prin meniu garantează că tot jocul
/// e reconstruit, iar pentru jucător arată exact ca o aplicare de setare.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  Future<void> _select(AppLanguage language) async {
    Sfx.tileSelect();
    if (language == L10n.current) {
      Navigator.pop(context);
      return;
    }
    await L10n.setLanguage(language);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoadingScreen(nextBuilder: (_) => const HomeScreen(), duration: const Duration(milliseconds: 700)),
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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  Text(tr('Limbă', 'Language'),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final language in AppLanguage.values) ...[
                    _LanguageRow(
                      language: language,
                      selected: language == L10n.current,
                      onTap: () => _select(language),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withAlpha(24),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.blue.withAlpha(80)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: AppColors.blue, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            // Spus din capul locului, nu descoperit după
                            // instalare: meniurile sunt traduse, întrebările nu.
                            tr(
                              'Meniurile, butoanele și multiplayer-ul se traduc. Întrebările din joc '
                              '(răspunsurile la poze, Cultura Generală, Higher or Lower) rămân scrise în română.',
                              L10n.contentLanguageNotice,
                            ),
                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageRow({required this.language, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.play : Colors.white10, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Text(language.flag, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                language.label,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: AppColors.play, size: 22)
            else
              const Icon(Icons.circle_outlined, color: Colors.white24, size: 22),
          ],
        ),
      ),
    );
  }
}
