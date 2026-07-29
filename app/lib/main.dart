import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/couleurs.dart';
import 'design/typographie.dart';

void main() {
  // L'app est nocturne : les icônes système doivent être claires, toujours.
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const UsLink());
}

class UsLink extends StatelessWidget {
  const UsLink({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UsLink',
      debugShowCheckedModeBanner: false,
      // Un seul thème. Pas de themeMode, pas de thème clair : voir couleurs.dart.
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Couleurs.nuit,
        fontFamily: Polices.humain,
        colorScheme: const ColorScheme.dark(
          surface: Couleurs.nuit,
          primary: Couleurs.braise,
          onPrimary: Couleurs.surBraise,
          onSurface: Couleurs.texte,
        ),
      ),
      home: const _Provisoire(),
    );
  }
}

/// Écran d'attente, le temps que les vrais écrans arrivent. Il ne sert qu'à
/// vérifier que les tokens sont bien câblés.
class _Provisoire extends StatelessWidget {
  const _Provisoire();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Mesures.marge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('braise', style: Typo.rubrique),
              SizedBox(height: 20),
              Text(
                'Toute l\u2019interface est \u00e9teinte pour qu\u2019une seule chose puisse s\u2019allumer.',
                style: Typo.enonce,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
