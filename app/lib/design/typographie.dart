import 'package:flutter/widgets.dart';

import 'couleurs.dart';

/// La règle de voix, qui est la décision la plus structurante du design.
///
/// **Le serif est la voix de l'app. La sans-serif est la voix des deux
/// personnes.** On ne met jamais une réponse humaine en serif, et l'app ne
/// parle jamais en sans-serif. Cette règle n'a aucune exception : c'est elle
/// qui fait qu'on sait qui parle sans qu'on ait à l'écrire.
///
/// Newsreader est choisi expressément pour son faible contraste de graisse :
/// une Didone verrait ses déliées disparaître et scintiller sur fond noir.
/// Jamais en dessous de 400 — le halation mange les traits fins.
abstract final class Polices {
  /// Voix de l'app : la question, l'affirmation du débat, l'action à faire.
  static const app = 'Newsreader';

  /// Voix des personnes, et toute l'interface.
  static const humain = 'Inter';
}

/// Échelle typographique, en points logiques.
///
/// L'interlettrage positif sur la sans-serif compense le halation du fond
/// sombre. Il doit être remis à zéro pour l'arabe, où il casserait le liage.
abstract final class Typo {
  /// L'affirmation du débat et la question du jour. 4 lignes au maximum.
  static const enonce = TextStyle(
    fontFamily: Polices.app,
    fontSize: 30,
    height: 38 / 30,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    color: Couleurs.texte,
  );

  /// Le mot qui nomme le contenu : « débat », « question », « défi ».
  /// Bas de casse — la direction refuse les capitales, ce qui la rend au
  /// passage la plus robuste à l'arabe.
  static const rubrique = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.44, // +0.12em
    color: Couleurs.braise,
  );

  /// Ce que j'écris, pendant que je l'écris.
  static const saisie = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 17,
    height: 26 / 17,
    fontWeight: FontWeight.w400,
    color: Couleurs.texte,
  );

  /// Ma réponse, une fois envoyée : refroidie.
  static const maVoix = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 18,
    height: 28 / 18,
    fontWeight: FontWeight.w400,
    color: Couleurs.voixMoi,
  );

  /// Sa réponse. Même corps que la mienne — la hiérarchie est portée par la
  /// couleur et par le halo, pas par la taille.
  static const saVoix = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 18,
    height: 28 / 18,
    fontWeight: FontWeight.w400,
    color: Couleurs.voixAutre,
  );

  /// Étiquette d'auteur. Présente des DEUX côtés, jamais d'un seul : l'écart
  /// entre les deux voix est en luminance pure, il lui faut un doublon textuel.
  static const etiquette = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.44,
    color: Couleurs.texteEteint,
  );

  /// Idem, pour l'autre : la seule différence est la braise.
  static const signature = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.44,
    color: Couleurs.braise,
  );

  /// Compteur « 843 jours ensemble ». Chiffres tabulaires, sinon le nombre
  /// danse d'un jour à l'autre.
  static const compteur = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
    color: Couleurs.texte,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Pôles de l'échelle, dates, invites.
  static const secondaire = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w500,
    color: Couleurs.texteEteint,
  );

  /// Le libellé de l'action, posé sur la braise.
  static const action = TextStyle(
    fontFamily: Polices.humain,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Couleurs.surBraise,
  );
}

/// Mesures. Une seule marge latérale dans toute l'app, aucun rayon de coin
/// sauf les cercles.
abstract final class Mesures {
  static const marge = 28.0;

  /// Le vide de tête au-dessus de la rubrique. Il fait partie du produit.
  static const videTete = 96.0;

  /// La réserve entre le champ et l'action, là où la réponse de l'autre vient
  /// s'inscrire.
  ///
  /// La spécification la déclarait « non compressible ». C'est la seule
  /// décision purement décorative de la direction, et elle bloque la seule
  /// marge disponible : en espagnol, un débat de 20 mots déborde le gabarit.
  /// Elle est donc compressible sous contrainte, jusqu'à [reserveMin].
  static const reserve = 217.0;
  static const reserveMin = 96.0;

  static const hauteurAction = 54.0;

  /// Cible tactile minimale. Les nœuds de l'échelle sont dessinés à 7 pt mais
  /// touchés sur 56.
  static const cible = 56.0;

  /// Pastilles de série. 6 pt et non 4 : en dessous, l'anneau vide et le
  /// disque plein sont indiscernables, et c'est le seul signal de complétude
  /// de l'app.
  static const pastille = 6.0;
}
