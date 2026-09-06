/// Alegerea adversarilor la Meci Rapid — logica pură, fără Firestore, ca să
/// poată fi verificată în teste. Vezi `MultiplayerService.attemptFormMatch`
/// pentru partea care citește coada și scrie oferta.
library;

/// Indicii adversarilor aleși dintr-o coadă, cei mai apropiaţi ca rating.
///
/// [candidateRatings] e lista celorlalţi din coadă, **în ordinea intrării**
/// (cel mai vechi primul); indicii întorşi se referă la ea. Cine cheamă
/// funcţia e capul cozii — cel care aşteaptă de cel mai mult timp — deci
/// nimeni nu poate fi înfometat: candidaţii nu sunt excluşi, doar ordonaţi,
/// iar cine aşteaptă mult ajunge el însuşi cap de coadă.
///
/// La rating egal câştigă cine e mai demult în coadă. Departajarea e
/// EXPLICITĂ fiindcă `List.sort` din Dart nu e stabilă: fără ea, doi
/// adversari cu acelaşi rating s-ar alege la întâmplare.
List<int> pickOpponentsByRating({
  required int myRating,
  required List<int> candidateRatings,
  required int count,
}) {
  if (count <= 0) return const [];
  final order = [for (var i = 0; i < candidateRatings.length; i++) i];
  order.sort((a, b) {
    final da = (candidateRatings[a] - myRating).abs();
    final db = (candidateRatings[b] - myRating).abs();
    return da != db ? da - db : a - b;
  });
  return order.take(count).toList();
}
