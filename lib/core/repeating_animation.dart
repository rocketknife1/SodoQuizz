import 'package:flutter/animation.dart';

/// `AnimationController` cu un parametru [restValue] în plus — poziția în care
/// widget-ul vrea ca animația să pară „liniștită" dacă vreodată e oprită.
/// Azi animația rulează mereu, deci [restValue] e doar păstrat pentru
/// compatibilitatea apelurilor existente; nu mai există nicio logică de
/// pornire/oprire în funcție de vreo setare.
class RepeatingAnimationController extends AnimationController {
  RepeatingAnimationController({
    required super.vsync,
    required super.duration,
    this.restValue = 0.0,
  });

  final double restValue;
}
