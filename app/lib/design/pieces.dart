import 'package:flutter/material.dart';

import 'couleurs.dart';
import 'typographie.dart';

/// Un champ, c'est trois objets et jamais un contenant : une étiquette, une
/// valeur, un filet. Pas de boîte, pas de fond, pas de coin arrondi — le texte
/// se pose à même la nuit, comme partout ailleurs.
class Champ extends StatelessWidget {
  const Champ({
    super.key,
    required this.etiquette,
    required this.controleur,
    this.indice,
    this.clavier,
    this.longueurMax,
    this.autoMajuscule = TextCapitalization.none,
  });

  final String etiquette;
  final TextEditingController controleur;
  final String? indice;
  final TextInputType? clavier;
  final int? longueurMax;
  final TextCapitalization autoMajuscule;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiquette, style: Typo.etiquette),
        const SizedBox(height: 8),
        TextField(
          controller: controleur,
          style: Typo.saisie,
          keyboardType: clavier,
          maxLength: longueurMax,
          textCapitalization: autoMajuscule,
          cursorColor: Couleurs.braise,
          cursorWidth: 1.5,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: indice,
            hintStyle: Typo.saisie.copyWith(color: Couleurs.texteEteint),
            contentPadding: const EdgeInsets.only(bottom: 10),
            // Le filet EST le champ. Il passe en braise au focus : c'est le
            // seul moment où la couleur chaude touche un contrôle, parce que
            // c'est là que l'action se prépare.
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Couleurs.trait, width: 1),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Couleurs.braise, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// L'action principale : un aplat de braise, sans rayon de coin.
///
/// La grammaire est stricte — **un aplat de braise fait avancer**, un mot
/// souligné en braise fait autre chose. C'est ce qui empêche de confondre
/// « Répondre » avec l'action d'un bandeau d'erreur.
class Aplat extends StatelessWidget {
  const Aplat({super.key, required this.libelle, required this.onTap, this.prete = true});

  final String libelle;
  final VoidCallback onTap;
  final bool prete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: prete,
      label: libelle,
      child: GestureDetector(
        onTap: prete ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: Mesures.hauteurAction,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: prete ? Couleurs.braise : null,
            border: prete ? null : const Border.fromBorderSide(BorderSide(color: Couleurs.trait)),
          ),
          child: Text(
            libelle,
            style: prete
                ? Typo.action
                : Typo.action.copyWith(color: Couleurs.texteEteint),
          ),
        ),
      ),
    );
  }
}

/// La progression de l'onboarding.
///
/// Pas une rangée de pastilles : un filet qui s'allonge. Une pastille est un
/// objet décoratif de plus ; un filet appartient déjà au vocabulaire — c'est la
/// même matière que le rail de l'échelle et que le soulignement des champs.
class Progression extends StatelessWidget {
  const Progression({super.key, required this.etape, required this.total});

  final int etape;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'étape $etape sur $total',
      child: SizedBox(
        height: 1,
        child: Row(
          children: [
            Expanded(
              flex: etape,
              child: const ColoredBox(color: Couleurs.braise),
            ),
            Expanded(
              flex: total - etape,
              child: const ColoredBox(color: Couleurs.trait),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une puce sélectionnable : centres d'intérêt, objectifs, mode.
///
/// Un cercle est une forme du vocabulaire ; un rectangle arrondi serait une
/// carte miniature, donc un contenant, donc interdit.
class Puce extends StatelessWidget {
  const Puce({
    super.key,
    required this.libelle,
    required this.choisi,
    required this.onTap,
    this.mention,
    this.actif = true,
  });

  final String libelle;
  final bool choisi;
  final VoidCallback onTap;

  /// Seconde ligne discrète, pour « bientôt ».
  final String? mention;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: choisi,
      enabled: actif,
      label: mention == null ? libelle : '$libelle, $mention',
      child: GestureDetector(
        onTap: actif ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              BorderSide(color: choisi ? Couleurs.braise : Couleurs.trait),
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Opacity(
            opacity: actif ? 1 : 0.5,
            child: Text(
              mention == null ? libelle : '$libelle · $mention',
              style: Typo.secondaire.copyWith(
                color: choisi ? Couleurs.texte : Couleurs.texteEteint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une ligne de réglage. Pas de chevron : le mot de droite EST la valeur, et
/// une ligne entière tactile n'a pas besoin qu'on lui dessine une flèche.
class LigneReglage extends StatelessWidget {
  const LigneReglage({super.key, required this.libelle, this.valeur, required this.onTap});

  final String libelle;
  final String? valeur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: valeur == null ? libelle : '$libelle, $valeur',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(child: Text(libelle, style: Typo.saisie)),
              if (valeur != null)
                Text(valeur!, style: Typo.secondaire),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un titre de section dans les réglages. Bas de casse, éteint : il classe, il
/// ne crie pas.
class Section extends StatelessWidget {
  const Section(this.titre, {super.key});
  final String titre;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 32, bottom: 4),
        child: Text(titre, style: Typo.etiquette),
      );
}
