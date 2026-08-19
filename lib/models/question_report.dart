import '../core/lang.dart';

/// Motivul unei raportări de întrebare — listă scurtă și fixă, ca la
/// [ReportReason] din moderation.dart, din același motiv: un câmp liber ar
/// deveni un chat nemoderat direct în colecția de raportări.
enum QuestionReportReason {
  intrebareGresita('Întrebare greșită', 'Wrong question'),
  raspunsGresit('Răspuns greșit', 'Wrong answer'),
  pozaNecorespunzatoare('Poză necorespunzătoare', 'Inappropriate image');

  const QuestionReportReason(this._labelRo, this._labelEn);
  final String _labelRo;
  final String _labelEn;

  String get label => tr(_labelRo, _labelEn);
}
