import 'package:flutter/material.dart';

class Question {
  final String id;
  final String answer;
  final String hint1;
  final String hint2;
  final String hint3;
  final String categoryId; // id-ul GameMode-ului (vezi core/gamemodes.dart)
  final String category; // nume afișat (badge-ul din joc)
  final List<String> choices; // cele 4 variante posibile de răspuns
  final Color color;
  final int maxPoints;
  final String? imageAssetPath;

  /// Enunțul propriu-zis, când întrebarea NU e implicit „ce e în poza asta?".
  /// Gol la categoriile pe poze — acolo întrebarea se înțelege din context, iar
  /// [hint1] ține loc de indiciu (vezi GameScreen._buildClue).
  final String prompt;

  /// Textul matematic afișat MARE în locul pozei (categoria Matematică).
  ///
  /// Când e non-null, ecranul de joc randează un card de formulă în loc de
  /// [BlurImage] — și fără blur: o poză neclară e o întrebare mai grea, dar o
  /// FORMULĂ neclară e o întrebare imposibilă. Dificultatea vine din
  /// matematică, nu din ceață.
  ///
  /// O întrebare din aceeași categorie care are poză (un matematician de
  /// ghicit) lasă câmpul null și se comportă exact ca oriunde altundeva —
  /// de-aia amestecul celor două tipuri nu cere niciun cod special.
  final String? formula;

  const Question({
    required this.id,
    required this.answer,
    required this.hint1,
    required this.hint2,
    required this.hint3,
    required this.categoryId,
    required this.category,
    this.choices = const [],
    required this.color,
    required this.maxPoints,
    this.imageAssetPath,
    this.prompt = '',
    this.formula,
  });
}
