import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/player_profile_service.dart';
import '../data/storage_service.dart';

/// Dialogul de schimbare a numelui afișat — comun tuturor locurilor din
/// aplicație unde poate fi editat (Profil, Multiplayer, shortcut-ul din
/// Home), ca jucătorul să găsească exact același dialog oriunde apasă pe
/// numele lui, nu variante ținute manual în sincron (cum erau înainte).
///
/// [nameSetByAdmin] ridică automat numele impus de administrator ÎNAINTE de
/// salvare (vezi PlayerProfileService.releaseMyForcedName) — altfel primul
/// heartbeat l-ar pune la loc, iar salvarea ar fi părut că n-a făcut nimic.
///
/// Întoarce noul nume dacă a fost chiar schimbat, `null` altfel — ca
/// apelantul să-și poată actualiza propriul state fără o citire în plus.
Future<String?> editDisplayName(
  BuildContext context, {
  required String currentName,
  required bool nameSetByAdmin,
}) async {
  final controller = TextEditingController(text: currentName);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF141B36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withAlpha(30)),
      ),
      title: Text(tr('Numele tău', 'Your name'),
          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
      content: TextField(
        controller: controller,
        maxLength: 16,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          counterStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: Colors.white.withAlpha(15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withAlpha(30))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withAlpha(30))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.purple)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Anulează', 'Cancel'))),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.purple,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(tr('Salvează', 'Save'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty || !context.mounted) return null;
  if (nameSetByAdmin) {
    await PlayerProfileService.instance.releaseMyForcedName();
  }
  await StorageService.setDisplayName(result);
  // fără asta, numele nou ar rămâne doar local — clasamentul și profilul
  // public ar arăta în continuare numele vechi până la următoarea pornire a
  // aplicației.
  await PlayerProfileService.instance.ensureProfileHeartbeat();
  return result;
}
