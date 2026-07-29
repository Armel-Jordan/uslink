import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/couleurs.dart';
import 'design/lisiere.dart';
import 'design/typographie.dart';
import 'ecrans/onboarding.dart';
import 'ecrans/profil.dart';
import 'ecrans/reglages.dart';
import 'i18n/fr.dart';

void main() {
  // L'app est nocturne : les icônes système sont claires, toujours.
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const UsLink());
}

class UsLink extends StatelessWidget {
  const UsLink({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Fr.appName,
      debugShowCheckedModeBanner: false,
      // Un seul thème. Pas de themeMode, pas de darkTheme : voir couleurs.dart.
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
      home: const Racine(),
    );
  }
}

class Racine extends StatefulWidget {
  const Racine({super.key});

  @override
  State<Racine> createState() => _RacineState();
}

class _RacineState extends State<Racine> {
  bool _presente = false;
  Lieu _lieu = Lieu.jour;
  double _luminosite = 0;

  @override
  Widget build(BuildContext context) {
    if (!_presente) {
      return Onboarding(onFini: () => setState(() => _presente = true));
    }
    return Lieu4(
      lieu: _lieu,
      luminosite: _luminosite,
      onAller: (l) => setState(() => _lieu = l),
      enfant: switch (_lieu) {
        Lieu.jour => const _Provisoire('le jour'),
        Lieu.souvenirs => const _Provisoire('les souvenirs'),
        Lieu.ensemble => const Profil(),
        Lieu.profil => Reglages(
            luminosite: _luminosite,
            onLuminosite: (v) => setState(() => _luminosite = v),
          ),
      },
    );
  }
}

/// Les deux lieux qui restent à écrire.
class _Provisoire extends StatelessWidget {
  const _Provisoire(this.nom);
  final String nom;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Mesures.marge),
        child: Text(nom, style: Typo.enonce),
      ),
    );
  }
}
