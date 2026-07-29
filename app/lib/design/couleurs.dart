import 'package:flutter/material.dart';

/// Les couleurs de « Braise ».
///
/// Il n'y a pas de thème clair. Ce n'est pas un oubli : la mécanique centrale
/// du produit est une révélation, et une révélation qui « éclaire » sur fond
/// blanc ne révèle rien. Le fond sombre n'est pas un habillage, c'est le
/// support de la métaphore.
///
/// Deux règles gouvernent tout ce fichier :
///
/// 1. **Ni noir absolu, ni blanc pur.** `#000` durcit l'image et `#FFF` bave
///    sur fond sombre (halation), particulièrement pour les astigmates. On
///    reste à l'intérieur, des deux côtés.
/// 2. **Une seule couleur chaude**, la braise, autorisée sur trois choses et
///    trois seulement : nommer le contenu, déclencher l'action, signer la
///    révélation. Le jour où quelqu'un ajoute « juste un vert pour le défi
///    réussi », la direction commence à mourir.
///
/// Les ratios en commentaire sont recalculés, pas repris de la spécification —
/// celle-ci les sous-estimait de 3 à 6 %.
abstract final class Couleurs {
  /// Fond unique de toute l'app. Noir bleuté, jamais un gris, jamais un
  /// dégradé, jamais une image.
  static const nuit = Color(0xFF07080B);

  /// Le fond descend ici pendant le souffle retenu de la révélation, puis
  /// remonte. C'est le seul moment où il bouge.
  static const nuitCreuse = Color(0xFF030407);

  /// Seule élévation du produit, pour les surfaces modales (Souvenirs,
  /// Profil). À 1,07:1 elle ne se détache PAS du fond : il lui faut
  /// obligatoirement un filet [trait] sur son arête, sinon le rideau n'a
  /// pas de bord pendant sa transition.
  static const nuitVeille = Color(0xFF101218);

  /// Texte courant. **12,98:1**, mesuré.
  ///
  /// Volontairement PAS le contraste maximal. Sur fond noir, le contraste
  /// maximal produit le halation maximal : à 16:1 le texte bave, surtout pour
  /// les astigmates, et cette app se lit le soir, fatigué, souvent sans
  /// lunettes.
  ///
  /// On abaisse le sol, pas le plafond : [voixAutre] reste à 18,10:1, donc
  /// l'écart lumineux qui porte toute la métaphore est intact. On ne perd que
  /// l'éblouissement.
  ///
  /// Ne pas « améliorer » cette valeur vers #EDE6DE (16,19:1) : ce serait
  /// revenir au problème en croyant le corriger.
  static const texte = Color(0xFFD6CFC7);

  /// Compteur, dates, pôles de l'échelle, invites. 5,16:1.
  static const texteEteint = Color(0xFF7C8191);

  /// La seule couleur du produit. 9,06:1.
  static const braise = Color(0xFFFF9256);

  /// Point d'arrivée des halos et des lavis. Jamais du texte, jamais un aplat.
  static const braiseProfonde = Color(0xFF7A2E12);

  /// Ma propre réponse, APRÈS l'avoir envoyée. 8,29:1.
  ///
  /// Elle se refroidit au moment de l'envoi : je la connais déjà. C'est ce
  /// refroidissement qui donne à la voix de l'autre sa place de chose la plus
  /// lumineuse de l'écran.
  static const voixMoi = Color(0xFF9FA7B8);

  /// La réponse de l'autre. 18,10:1 — l'objet le plus clair de l'app, et le
  /// seul usage de cette valeur.
  ///
  /// L'écart entre les deux voix n'est que de 2,18:1 et repose sur la seule
  /// luminance. Il DOIT donc être doublé par une étiquette textuelle des deux
  /// côtés — pas d'un seul, sinon l'asymétrie laisse deviner en niveaux de
  /// gris comme en lecture d'écran.
  static const voixAutre = Color(0xFFFFF1E6);

  /// Filets porteurs de sens : rail de l'échelle, soulignement des champs.
  /// 3,27:1, au-dessus du seuil des éléments non textuels.
  static const trait = Color(0xFF5A6273);

  /// Indicateur de station inactif. Corrigé : la spécification proposait
  /// #2A2F3A, soit 1,49:1 — invisible. Or c'est la seule chose qui dit qu'il
  /// y a trois contenus et pas un. 3,03:1.
  static const stationEteinte = Color(0xFF535D72);

  /// Texte posé SUR la braise (libellé d'action). 8,95:1.
  static const surBraise = Color(0xFF0B0A08);
}
