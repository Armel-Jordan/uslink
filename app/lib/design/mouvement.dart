import 'package:flutter/widgets.dart';

/// Le mouvement de « Braise ».
///
/// Une seule séquence compte dans toute l'app : la révélation. Le reste ne
/// bouge pas. Un produit qui anime partout n'a plus rien à souligner.
abstract final class Mouvement {
  /// **Le flou par ligne est DÉSACTIVÉ par défaut, et c'est délibéré.**
  ///
  /// La spécification proposait l'inverse : flou en standard, repli sur les
  /// appareils faibles. C'est le mauvais sens. `ImageFiltered` avec un sigma
  /// animé est une passe de rendu hors écran **par ligne et par frame** ; cinq
  /// lignes en chevauchement font cinq passes pleine largeur à 60 fps.
  ///
  /// Ça saccade sur un milieu de gamme — c'est-à-dire précisément sur le
  /// moment le plus important du produit. Une saccade sur l'instant d'émotion
  /// tue l'instant, et aucune beauté de transition ne rachète ça.
  ///
  /// Le repli (opacité + translation) est fluide partout et raconte la même
  /// chose. Le flou s'active appareil par appareil, une fois mesuré.
  static const flouParDefaut = false;

  /// Le souffle retenu : le fond descend, ma réponse se refroidit, et pendant
  /// environ une demi-seconde il n'y a plus AUCUNE trace de chaleur à l'écran.
  /// C'est ce vide qui donne sa valeur à ce qui suit.
  static const retrait = Duration(milliseconds: 500);

  /// L'allumage du halo, après le souffle.
  static const allumage = Duration(milliseconds: 900);

  /// Décalage entre deux lignes de la réponse de l'autre. Jamais mot à mot :
  /// une machine à écrire ferait d'elle une animation, pas une apparition.
  static const decalageLigne = Duration(milliseconds: 60);

  /// Apparition d'une ligne.
  static const ligne = Duration(milliseconds: 700);

  /// Le retour au repos. Après quoi le halo ne bouge plus jamais : il ne pulse
  /// pas, il ne respire pas. Une lumière qui palpite demande qu'on la regarde ;
  /// celle-ci est là pour qu'on lise ce qu'elle éclaire.
  static const repos = Duration(milliseconds: 600);

  /// Courbe d'allumage : sortie très amortie, l'inverse d'un rebond.
  static const courbeAllumage = Cubic(0.16, 1, 0.3, 1);

  /// Courbe de retrait.
  static const courbeRetrait = Cubic(0.2, 0, 0, 1);

  /// Au bout de 30 révélations, la séquence se raccourcit : le souffle retenu
  /// saute. Ce qui émeut la première fois agace la trentième.
  static const revelationsAvantRaccourci = 30;
  static const dureeRaccourcie = Duration(milliseconds: 900);

  /// Respecte « Réduire les animations ». Sans flou, sans assombrissement du
  /// fond, sans dépassement : un fondu croisé et un halo statique.
  static Duration selonAccessibilite(BuildContext context, Duration normale) {
    return MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 200)
        : normale;
  }
}
