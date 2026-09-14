import 'dart:async';

import 'package:flutter/material.dart';

import '../core/breadcrumbs.dart';
import '../core/chat_filter.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/player_profile_service.dart';
import '../data/storage_service.dart';
import '../widgets/space_background.dart';
import 'home_screen.dart';

const int _minNameLength = 2;
const int _maxNameLength = 16;

/// Mesajul de eroare pentru un nume, sau `null` dacă e bun.
String? chooseNameError(String raw) {
  final name = raw.trim();
  if (name.length < _minNameLength) {
    return tr('Minim $_minNameLength caractere.', 'At least $_minNameLength characters.');
  }
  if (name.length > _maxNameLength) {
    return tr('Maxim $_maxNameLength caractere.', 'At most $_maxNameLength characters.');
  }
  if (containsProfanity(name)) {
    return tr('Alege alt nume.', 'Pick another name.');
  }
  return null;
}

/// Prima pornire, imediat după tutorial: jucătorul își alege numele înainte
/// de meniu, altfel apare în clasament și în multiplayer ca „JucatorXXX".
///
/// Tutorialul se marchează ca văzut abia AICI, după salvare — cine închide
/// aplicația pe ecranul ăsta e întrebat din nou la pornirea următoare.
class ChooseNameScreen extends StatefulWidget {
  const ChooseNameScreen({super.key});

  @override
  State<ChooseNameScreen> createState() => _ChooseNameScreenState();
}

class _ChooseNameScreenState extends State<ChooseNameScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Breadcrumbs.drop('ecran: alege numele');
    StorageService.getChosenDisplayName().then((name) {
      if (mounted && name.isNotEmpty && _controller.text.isEmpty) _controller.text = name;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final error = chooseNameError(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    await StorageService.setChosenDisplayName(_controller.text.trim());
    await StorageService.setIntroSeen();
    // Rețeaua nu are voie să țină omul pe loc: profilul public se aliniază în fundal.
    unawaited(PlayerProfileService.instance.ensureProfileHeartbeat());
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SpaceBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 52),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('👋', style: TextStyle(fontSize: 64)),
                      const SizedBox(height: 16),
                      Text(
                        tr('Cum te cheamă?', "What's your name?"),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Așa te văd ceilalți în clasament și în multiplayer.',
                            'This is how others see you in the leaderboard and multiplayer.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, fontSize: 15),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        maxLength: _maxNameLength,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        onSubmitted: (_) => _save(),
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          hintText: tr('Numele tău', 'Your name'),
                          hintStyle: const TextStyle(color: Colors.white30, fontWeight: FontWeight.w600),
                          errorText: _error,
                          counterStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withAlpha(15),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: Colors.white.withAlpha(30)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: Colors.white.withAlpha(30)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(color: AppColors.purple, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.play,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                                )
                              : Text(
                                  tr('HAI SĂ JUCĂM!', "LET'S PLAY!"),
                                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
