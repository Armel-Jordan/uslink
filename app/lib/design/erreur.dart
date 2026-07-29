import 'package:flutter/widgets.dart';

import 'couleurs.dart';
import 'typographie.dart';

/// **L'unique exception à la règle de la couleur.**
///
/// La règle dit : une seule couleur chaude, autorisée sur trois choses —
/// nommer le contenu, déclencher l'action, signer la révélation. Elle interdit
/// explicitement d'ajouter un vert ou un rouge sémantique.
///
/// Mais une app à 85 % noire, sans rouge ni vert, a un problème réel : le jour
/// où le réseau tombe pendant que quelqu'un envoie sa réponse, **rien ne se
/// voit**, et la personne croit que c'est parti. Le silence n'est pas une
/// option pour une erreur bloquante.
///
/// L'exception est donc écrite ici, une fois, plutôt que bricolée en panique :
///
/// 1. **L'erreur emprunte la braise**, elle n'introduit pas de couleur. « Quelque
///    chose ne va pas, agis » entre dans la grammaire d'une couleur qui nomme,
///    agit et signe. On ne trahit pas la règle, on l'étend d'un usage.
/// 2. **Elle se distingue par la FORME, pas par la teinte** : un bandeau pleine
///    largeur, adossé au bas de l'écran, avec un filet de braise sur son arête
///    haute. Aucun rayon de coin, comme partout ailleurs. Un bouton d'action est
///    un aplat de braise ; une erreur est un fond sombre barré de braise. On ne
///    peut pas les confondre.
/// 3. **Elle porte toujours un verbe.** Une erreur qui ne dit pas quoi faire est
///    une erreur qui accuse. « Votre réponse n'est pas partie » + « Réessayer ».
/// 4. **Elle ne disparaît jamais toute seule.** Un toast qui s'efface au bout de
///    trois secondes, dans une app qu'on consulte le soir en diagonale, n'a pas
///    été vu.
///
/// Ce qui reste interdit : le rouge, le vert, l'orange sémantique, une seconde
/// couleur chaude « juste pour cette fois ».
class BandeauErreur extends StatelessWidget {
  const BandeauErreur({
    super.key,
    required this.message,
    required this.libelleAction,
    required this.onAction,
  });

  final String message;
  final String libelleAction;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Couleurs.nuitVeille,
          border: Border(top: BorderSide(color: Couleurs.braise, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Mesures.marge,
            18,
            Mesures.marge,
            18,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  message,
                  style: Typo.saisie.copyWith(color: Couleurs.texte),
                ),
              ),
              const SizedBox(width: Mesures.marge),
              // L'action n'est pas un aplat de braise : ce serait la confondre
              // avec le bouton « Répondre ». Du texte en braise, souligné.
              GestureDetector(
                onTap: onAction,
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  child: Center(
                    child: Text(
                      libelleAction,
                      style: Typo.secondaire.copyWith(
                        color: Couleurs.braise,
                        fontSize: 15,
                        decoration: TextDecoration.underline,
                        decorationColor: Couleurs.braise,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
