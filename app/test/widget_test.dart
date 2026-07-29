import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uslink/design/couleurs.dart';
import 'package:uslink/design/lisiere.dart';
import 'package:uslink/design/mouvement.dart';
import 'package:uslink/design/typographie.dart';
import 'package:uslink/main.dart';

void main() {
  testWidgets('le produit est nocturne et le reste', (tester) async {
    await tester.pumpWidget(const UsLink());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    // Pas de thème clair, pas de bascule automatique : la métaphore de la
    // révélation ne tient que si le fond est toujours sombre.
    expect(app.darkTheme, isNull);
    expect(app.theme!.brightness, Brightness.dark);
    expect(app.theme!.scaffoldBackgroundColor, Couleurs.nuit);
  });

  testWidgets('la lisière porte quatre mots, aucun en braise', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Lisiere(actif: Lieu.jour, onAller: (_) {}),
      ),
    );

    for (final lieu in Lieu.values) {
      expect(find.text(lieu.mot), findsOneWidget);
      final t = tester.widget<Text>(find.text(lieu.mot));
      // Une barre qui brille en permanence concurrencerait la révélation :
      // l'état actif se lit à la luminosité, jamais à la braise.
      expect(t.style!.color, isNot(Couleurs.braise));
    }

    // Le lieu courant se distingue, mais par le seul contraste.
    final actif = tester.widget<Text>(find.text(Lieu.jour.mot));
    expect(actif.style!.color, Couleurs.texte);
  });

  group('arbitrages', arbitrages);
}

// Ces tests gardent des décisions, pas du comportement. Ils échouent si
// quelqu'un « améliore » un arbitrage sans savoir pourquoi il avait été pris.
void arbitrages() {
  test('le texte courant n\u2019est PAS au contraste maximal', () {
    // Sur fond noir, le contraste maximal produit le halation maximal.
    // #EDE6DE (16,19:1) bave ; #D6CFC7 (12,98:1) non, et reste AA.
    expect(Couleurs.texte, const Color(0xFFD6CFC7));
    // Mais la voix de l'autre garde son plafond : c'est l'écart qui porte la
    // métaphore, et on n'a abaissé que le sol.
    expect(Couleurs.voixAutre, const Color(0xFFFFF1E6));
  });

  test('la reserve est compressible', () {
    expect(Mesures.reserveMin, lessThan(Mesures.reserve));
    expect(Mesures.reserveMin, 96.0);
  });

  test('la luminosite ne deplace que le sol', () {
    // Le fond ET les lignes de structure montent — le trait porte l'anneau de
    // focus, qui tomberait à 2,95:1 sinon, sous le seuil AA.
    expect(Couleurs.fond(0), Couleurs.nuit);
    expect(Couleurs.fond(1), Couleurs.nuitJour);
    expect(Couleurs.traitSelon(1), Couleurs.traitJour);
    // Ces trois-là n'ont AUCUNE variante, et c'est tout le point.
    expect(Couleurs.braise, const Color(0xFFFF9256));
    expect(Couleurs.voixAutre, const Color(0xFFFFF1E6));
    expect(Couleurs.texte, const Color(0xFFD6CFC7));
  });

  test('le flou de revelation est desactive par defaut', () {
    expect(Mouvement.flouParDefaut, isFalse);
  });
}
