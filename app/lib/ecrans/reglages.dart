import 'package:flutter/material.dart';

import '../design/couleurs.dart';
import '../design/pieces.dart';
import '../design/typographie.dart';
import '../i18n/fr.dart';

/// Les réglages.
///
/// Un écran de réglages est du chrome par nature — c'est ici la bonne
/// exception, parce que le seul moyen de le rendre « non-chrome » serait de le
/// rendre introuvable. On enlève donc tout ce qui peut l'être (chevrons,
/// icônes, séparateurs, fonds) et on garde ce qui sert : des mots, des valeurs,
/// du vide entre les groupes.
///
/// Deux lignes que tu ne trouveras pas ici, et c'est délibéré :
///
/// - **« Thème »** n'existe pas. Il n'y a pas de mode clair, seulement une
///   luminosité qui éclaircit le fond. La révélation garde son éclat aux deux
///   extrémités de la course.
/// - **« Chiffrement »** tout court n'existe pas non plus. On dit précisément
///   ce qu'on fait, plutôt que de brandir un mot qui promettrait un
///   bout-en-bout qu'on ne tient pas.
class Reglages extends StatefulWidget {
  const Reglages({
    super.key,
    required this.luminosite,
    required this.onLuminosite,
  });

  final double luminosite;
  final ValueChanged<double> onLuminosite;

  @override
  State<Reglages> createState() => _ReglagesState();
}

class _ReglagesState extends State<Reglages> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Mesures.marge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),

          const Section(Fr.compte),
          LigneReglage(libelle: Fr.monProfil, onTap: () {}),
          LigneReglage(libelle: Fr.gererLeCouple, onTap: () {}),

          const Section(Fr.preferences),
          LigneReglage(libelle: Fr.langue, valeur: 'Français', onTap: () {}),
          LigneReglage(libelle: Fr.notifications, onTap: () {}),

          // Une luminosité, pas un thème : le curseur déplace le sol, jamais la
          // lumière. La braise et la voix de l'autre ne bougent d'aucun cran,
          // donc l'écart qui porte la révélation est identique partout sur la
          // course.
          const SizedBox(height: 12),
          Text(Fr.luminosite, style: Typo.saisie),
          const SizedBox(height: 4),
          Text(Fr.luminositeAide, style: Typo.secondaire),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 1,
              activeTrackColor: Couleurs.braise,
              inactiveTrackColor: Couleurs.traitSelon(widget.luminosite),
              thumbColor: Couleurs.braise,
              overlayColor: Couleurs.braise.withValues(alpha: 0.18),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: widget.luminosite,
              onChanged: widget.onLuminosite,
              // Une valeur continue mérite un geste continu — c'est le seul
              // autre endroit de l'app, avec l'échelle du débat, où c'est vrai.
              semanticFormatterCallback: (v) => '${(v * 100).round()} %',
            ),
          ),

          const Section(Fr.contenu),
          LigneReglage(libelle: Fr.niveauIntimite, valeur: 'profond', onTap: () {}),

          const Section(Fr.confidentialite),
          const SizedBox(height: 8),
          Text(Fr.confidentialiteTitre, style: Typo.saisie),
          const SizedBox(height: 6),
          Text(Fr.confidentialiteCorps, style: Typo.secondaire),
          const SizedBox(height: 24),
          Text(Fr.iaTitre, style: Typo.saisie),
          const SizedBox(height: 6),
          Text(Fr.iaCorps, style: Typo.secondaire),

          const SizedBox(height: 32),
          LigneReglage(libelle: Fr.supprimerMesDonnees, onTap: () {}),
          LigneReglage(libelle: Fr.seDeconnecter, onTap: () {}),

          const SizedBox(height: 56),
        ],
      ),
    );
  }
}
