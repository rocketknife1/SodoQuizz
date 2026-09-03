import 'package:flutter/material.dart';

/// Ce se vede în locul pozei la întrebările de Matematică: enunțul sus și
/// formula scrisă MARE dedesubt.
///
/// ## De ce nu se aplică blur aici
///
/// Toate celelalte categorii ascund poza și o limpezesc cu hint-uri. La o
/// formulă asta n-ar merge: o poză neclară e o întrebare mai grea, dar o
/// formulă neclară e o întrebare IMPOSIBILĂ — nu poți răspunde „cine a scris
/// asta" dacă nu poți citi ce scrie. Dificultatea vine din matematică.
/// Hint-urile rămân neatinse (text, 50/50, procent de șansă), doar ceața
/// vizuală lipsește — de-aia ecranul de joc ascunde și rândul „Claritate"
/// pentru întrebările astea.
///
/// ## Cum încap formulele lungi
///
/// [FittedBox] cu `scaleDown` micșorează formula EXACT cât trebuie ca să
/// intre, iar `softWrap: false` o ține pe un singur rând în loc s-o rupă la
/// mijloc — cerință explicită a userului. O formulă mică e mai bună decât una
/// tăiată sau frântă între „= a²" și „+ b²".
///
/// Formulele scrise pe mai multe rânduri (numele unui matematician sub o
/// dată, de exemplu) își pun singure separatorul de rând în JSON; acele rânduri
/// se păstrează, iar FittedBox scalează tot blocul deodată.
///
/// Aceeași cutie 4:3 și aceeași lățime maximă ca [BlurImage], ca trecerea de
/// la o întrebare cu poză la una cu formulă (se amestecă în aceeași categorie)
/// să nu mute nimic pe ecran.
class FormulaCard extends StatelessWidget {
  final Color color;

  /// Întrebarea propriu-zisă („Cine a demonstrat această relație?").
  final String prompt;

  /// Textul matematic, scris cu simboluri Unicode (α, √, ∑, ², π...).
  final String formula;

  /// Răspunsul, arătat peste card după ce s-a răspuns — la fel ca la poze.
  final String answer;
  final bool revealed;

  const FormulaCard({
    super.key,
    required this.color,
    required this.prompt,
    required this.formula,
    required this.answer,
    required this.revealed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withAlpha(110)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withAlpha(55),
                  Colors.black.withAlpha(190),
                ],
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (prompt.isNotEmpty) ...[
                        Text(
                          prompt,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formula,
                            textAlign: TextAlign.center,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(blurRadius: 12, color: Colors.black54),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (revealed)
                  Container(
                    color: Colors.black.withAlpha(196),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        answer,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
