import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uslink/design/couleurs.dart';
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
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.brightness, Brightness.dark);
    expect(app.theme!.scaffoldBackgroundColor, Couleurs.nuit);
  });

  testWidgets('la braise ne sert qu\u2019\u00e0 nommer le contenu', (tester) async {
    await tester.pumpWidget(const UsLink());

    final rubrique = tester.widget<Text>(find.text('braise'));
    expect(rubrique.style!.color, Couleurs.braise);
  });

  group('arbitrages', arbitrages);
}

// Ces trois tests gardent des décisions, pas du comportement. Ils échouent si
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

  test('la r\u00e9serve est compressible', () {
    // Déclarée « non compressible » par la spec. C'était la seule décision
    // décorative de la direction, et elle faisait déborder l'espagnol.
    expect(Mesures.reserveMin, lessThan(Mesures.reserve));
    expect(Mesures.reserveMin, 96.0);
  });

  test('le flou de r\u00e9v\u00e9lation est d\u00e9sactiv\u00e9 par d\u00e9faut', () {
    // Une passe de rendu hors écran par ligne et par frame, sur le moment le
    // plus important de l'app. Le repli est fluide partout.
    expect(Mouvement.flouParDefaut, isFalse);
  });
}
