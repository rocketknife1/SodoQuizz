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
  });
}
