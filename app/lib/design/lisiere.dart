import 'package:flutter/material.dart';

import 'couleurs.dart';
import 'typographie.dart';

/// Les quatre destinations. Des mots, pas des icônes : un mot passe l'espagnol,
/// un pictogramme demande d'être dessiné, documenté et deviné.
enum Lieu {
  jour('jour'),
  souvenirs('souvenirs'),
  ensemble('ensemble'),
  profil('profil');

  const Lieu(this.mot);
  final String mot;
}

/// **La lisière.** Quatre mots posés sur l'arête basse de la nuit.
///
/// C'est une barre, et c'en est une volontairement : « pas de barre » était une
/// conclusion tirée trop tôt. Ce que la direction interdit réellement, c'est le
/// conteneur, l'élévation, l'icône polychrome et le point chaud permanent qui
/// concurrencerait la révélation. Une barre Material viole les quatre ; celle-ci
/// n'en viole aucune.
///
/// Le refus coûtait plus qu'il ne rapportait : sans elle, quatre destinations
/// demandent quatre titres, quatre flèches de retour et deux gestes que
/// personne ne devine — six éléments de chrome contre un.
///
/// Deux écarts assumés par rapport à la proposition d'origine :
///
/// 1. **Quatre colonnes égales**, et non un alignement à gauche laissant 124 pt
///    de nuit à droite. L'asymétrie « prouvait » qu'il ne s'agissait pas d'une
///    barre — au prix de la faire lire comme un ours de magazine. On assume
///    l'objet plutôt que de le déguiser.
/// 2. **Elle ne s'efface pas pendant l'écriture.** Seulement pendant la
///    révélation, qui dure 2,3 secondes et le mérite. L'écriture dure des
///    minutes, et c'est là qu'un débutant hésite et cherche la sortie : un
///    écran sans issue visible pendant qu'on écrit n'est pas élégant, c'est un
///    piège.
class Lisiere extends StatelessWidget {
  const Lisiere({
    super.key,
    required this.actif,
    required this.onAller,
    this.visible = true,
  });

  final Lieu actif;
  final ValueChanged<Lieu> onAller;

  /// Faux uniquement pendant la séquence de révélation.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              for (final lieu in Lieu.values)
                Expanded(
                  child: _Mot(
                    lieu: lieu,
                    actif: lieu == actif,
                    onTap: () => onAller(lieu),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mot extends StatelessWidget {
  const _Mot({required this.lieu, required this.actif, required this.onTap});

  final Lieu lieu;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: actif,
      label: lieu.mot,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Text(
            lieu.mot,
            // L'état actif se lit à la LUMINOSITÉ, pas à la braise : la braise
            // nomme le contenu du jour, et un écran n'a qu'un point d'allumage.
            // Une barre qui brille en permanence concurrencerait la révélation.
            style: Typo.secondaire.copyWith(
              color: actif ? Couleurs.texte : Couleurs.texteEteint,
              fontWeight: actif ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ossature commune aux quatre lieux : la nuit, le contenu, la lisière.
///
/// Aucun des quatre n'a de titre ni de flèche de retour — c'est précisément ce
/// que la lisière fait gagner. Le nom du lieu est déjà en gras dans la lisière.
class Lieu4 extends StatelessWidget {
  const Lieu4({
    super.key,
    required this.lieu,
    required this.onAller,
    required this.enfant,
    this.lisiereVisible = true,
    this.luminosite = 0,
  });

  final Lieu lieu;
  final ValueChanged<Lieu> onAller;
  final Widget enfant;
  final bool lisiereVisible;
  final double luminosite;

  @override
  Widget build(BuildContext context) {
    // Material sans Scaffold : les champs et le curseur exigent cet ancetre.
    return Material(
      color: Couleurs.fond(luminosite),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(child: enfant),
            Lisiere(actif: lieu, onAller: onAller, visible: lisiereVisible),
            const SizedBox(height: Mesures.marge / 2),
          ],
        ),
      ),
    );
  }
}
