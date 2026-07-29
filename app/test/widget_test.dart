import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uslink/design/couleurs.dart';
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
}
