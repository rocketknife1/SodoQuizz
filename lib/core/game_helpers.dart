import 'dart:math';
import 'package:flutter/material.dart';

const int maxHintsPerQuestion = 4;
const double hintPenaltyRatio = 0.2;
const double hintPenaltyCapRatio = 0.4;

/// Claritatea imaginii, ca fracție 0..1, indexată DIRECT după numărul de
/// hint-uri folosite (index 0 = fără niciun hint). Începe deja foarte
/// clară (90%), ca poza să fie ușor de distins de la start, apoi crește
/// progresiv cu fiecare hint. Claritate 100% strictă doar după răspuns
/// (vezi [BlurImage.revealed]).
const List<double> hintExposureStages = [0.90, 0.93, 0.95, 0.97, 0.98];
double get maxHintExposure => hintExposureStages.last;

/// Cât de "expusă" (clară) e imaginea, ca fracție 0..maxHintExposure —
/// indexată direct după [hintsUsed] (0 = fără hint = claritatea de start).
double resolveHintExposure(int hintsUsed) {
  final i = hintsUsed.clamp(0, hintExposureStages.length - 1);
  return hintExposureStages[i];
}

int calculateHintPenalty(int questionReward, int maxPoints) {
  final cappedPenalty = (maxPoints * hintPenaltyCapRatio).round();
  final proportionalPenalty = (questionReward * hintPenaltyRatio).round();
  return proportionalPenalty.clamp(1, cappedPenalty).clamp(1, 999999);
}

int calculateAwardedPoints(int questionReward, int hintsUsed, int maxPoints) {
  final penalty = calculateHintPenalty(questionReward, maxPoints);
  return (questionReward - penalty * hintsUsed).clamp(0, questionReward);
}

/// Unlimited Quiz nu are risc de inimă (spre deosebire de GameScreen) — ca
/// să nu fie niciodată mai eficient decât modul cu risc, plătește sub
/// baseline: 0,6× sub plafonul zilnic de răspunsuri corecte, 0,2× peste.
/// Vezi reproiectarea economiei.
const double unlimitedQuizFullRate = 0.6;
const double unlimitedQuizReducedRate = 0.2;
const int unlimitedQuizFullRateDailyCap = 40;

/// Cultură Generală ("Daily Challenge"): primele [cultureFullRateDailyBatchCap]
/// loturi din zi (adică primele [cultureFullRateDailyCorrectCap] întrebări
/// corecte) plătesc rata normală; peste, rata scade mult — altfel numele
/// "Daily Challenge" nu reflectă realitatea (rula nelimitat).
const int cultureFullRateDailyCorrectCap = 30;
const int cultureFullRateDailyBatchCap = 3;
const int cultureReducedCoinsPerCorrect = 5;
const int cultureReducedXpPerCorrect = 10;

int calculateSessionQuestionReward(int maxPoints, Random random) {
  final minimumReward = (maxPoints * 0.7).round().clamp(100, maxPoints);
  final maximumReward = maxPoints;
  if (minimumReward >= maximumReward) {
    return maximumReward;
  }
  return random.nextInt(maximumReward - minimumReward + 1) + minimumReward;
}

const double _maxBlurSigma = 34.0;

/// Sigma de blur pentru imaginea întrebării — blur foarte puternic la
/// început (aproape imposibil de distins ce e în poză), se limpezește
/// treptat cu fiecare hint, dar rămâne mereu vizibil neclar până se
/// răspunde.
double resolveBlurSigma(int hintsUsed, {required bool revealed}) {
  if (revealed) {
    return 0.0;
  }
  final exposure = resolveHintExposure(hintsUsed);
  final sigma = _maxBlurSigma * (1 - exposure);
  return sigma.clamp(_maxBlurSigma * (1 - maxHintExposure), _maxBlurSigma);
}

LinearGradient buildQuestionGradient(String seed, Color baseColor) {
  final accent = HSLColor.fromColor(baseColor)
      .withHue((seed.hashCode.abs() % 360).toDouble())
      .toColor();

  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      baseColor.withAlpha(230),
      accent.withAlpha(220),
      const Color(0xFF0F172A),
    ],
  );
}
