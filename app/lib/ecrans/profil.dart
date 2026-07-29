import 'package:flutter/widgets.dart';

import '../design/couleurs.dart';
import '../design/typographie.dart';
import '../i18n/fr.dart';

/// Le profil.
///
/// Sans carte : la direction refuse les contenants, et l'information se groupe
/// par le VIDE et par le rythme typographique, pas par un rectangle. Sans
/// emoji : ils redisaient leur propre libellé.
///
/// Et sans métrique qui compare. Pas de record — un pic passé qu'on n'atteint
/// plus dit « vous faites moins bien qu'avant ». Pas de « réussis » — un défi
/// non fait deviendrait un échec. On garde ce qui monte ou ce qui décrit.
class Profil extends StatelessWidget {
  const Profil({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Mesures.marge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 56),

          // La personne, en voix de l'app : c'est elle qui vous nomme.
          Text('Léa', style: Typo.enonce),
          const SizedBox(height: 8),
          Text('27 ans · Montréal', style: Typo.secondaire),

          const SizedBox(height: 56),

          // Le lien. Groupé par le vide, pas par une carte.
          Text('votre lien', style: Typo.etiquette),
          const SizedBox(height: 16),
          Text('Avec Marc', style: Typo.maVoix.copyWith(color: Couleurs.texte)),
          const SizedBox(height: 6),
          Text('Depuis le 2 juin 2022', style: Typo.secondaire),
          const SizedBox(height: 6),
          Text('Son anniversaire, le 14 mars', style: Typo.secondaire),

          const SizedBox(height: 56),

          // Le seul chiffre qui a le droit d'être grand : il ne fait que monter.
          Text(
            Fr.joursEnsemble(843),
            style: Typo.enonce.copyWith(color: Couleurs.braise),
          ),

          const SizedBox(height: 40),

          Text('vos traces', style: Typo.etiquette),
          const SizedBox(height: 16),
          _Trace(Fr.serieEnCours(12)),
          _Trace(Fr.echanges(328)),
          _Trace(Fr.defisReleves(45)),

          const SizedBox(height: 56),

          Text('niveaux ouverts', style: Typo.etiquette),
          const SizedBox(height: 16),
          const _Niveaux(ouverts: 3, total: 4),
          const SizedBox(height: 12),
          Text('léger → profond', style: Typo.secondaire),

          const SizedBox(height: 56),
        ],
      ),
    );
  }
}

class _Trace extends StatelessWidget {
  const _Trace(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(texte, style: Typo.maVoix.copyWith(color: Couleurs.texte)),
      );
}

/// Les niveaux : la même forme que la série et que l'échelle. Un cercle plein
/// est ouvert, un cercle vide ne l'est pas encore. Aucune icône.
class _Niveaux extends StatelessWidget {
  const _Niveaux({required this.ouverts, required this.total});
  final int ouverts, total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$ouverts niveaux ouverts sur $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < ouverts ? Couleurs.braise : null,
                  border: i < ouverts
                      ? null
                      : const Border.fromBorderSide(BorderSide(color: Couleurs.trait)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
