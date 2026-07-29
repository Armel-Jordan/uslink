import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/couleurs.dart';
import '../design/pieces.dart';
import '../design/typographie.dart';
import '../i18n/fr.dart';

/// Les quatre étapes : qui vous êtes, ce que vous voulez travailler, comment
/// vous vous reliez, et le code.
///
/// Rien n'y est obligatoire. Un onboarding qu'on ne peut pas franchir est un
/// mur, et les contenus fonctionnent sans ces données.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.onFini});
  final VoidCallback onFini;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  static const _total = 4;
  int _etape = 1;

  final _prenom = TextEditingController();
  final _age = TextEditingController();
  final _ville = TextEditingController();
  final _naissance = TextEditingController();
  final _debut = TextEditingController();
  final _code = TextEditingController();

  final _objectifs = <String>{};
  String _mode = 'couple';

  @override
  void dispose() {
    for (final c in [_prenom, _age, _ville, _naissance, _debut, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  void _suivant() {
    if (_etape < _total) {
      setState(() => _etape++);
    } else {
      widget.onFini();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Material sans Scaffold : TextField et Slider exigent cet ancetre, mais
    // un Scaffold apporterait son propre chrome.
    return Material(
      color: Couleurs.nuit,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Mesures.marge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Progression(etape: _etape, total: _total),
              const SizedBox(height: 12),
              Text(Fr.etape(_etape, _total), style: Typo.etiquette),
              Expanded(
                child: SingleChildScrollView(
                  child: switch (_etape) {
                    1 => _Identite(
                        prenom: _prenom,
                        age: _age,
                        ville: _ville,
                        naissance: _naissance,
                        debut: _debut,
                      ),
                    2 => _Objectifs(
                        choisis: _objectifs,
                        onBascule: (o) => setState(() {
                          _objectifs.contains(o) ? _objectifs.remove(o) : _objectifs.add(o);
                        }),
                      ),
                    3 => _Mode(choisi: _mode, onChoisir: (m) => setState(() => _mode = m)),
                    _ => _Appairage(code: _code),
                  },
                ),
              ),
              Aplat(
                libelle: _etape == _total ? Fr.rejoindre : Fr.continuer,
                onTap: _suivant,
              ),
              const SizedBox(height: 12),
              // Rien n'est obligatoire.
              Center(
                child: GestureDetector(
                  onTap: widget.onFini,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    child: Text(Fr.plusTard, style: Typo.secondaire),
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

class _Identite extends StatelessWidget {
  const _Identite({
    required this.prenom,
    required this.age,
    required this.ville,
    required this.naissance,
    required this.debut,
  });

  final TextEditingController prenom, age, ville, naissance, debut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // Voix de l'app : serif. C'est elle qui s'adresse à vous.
        Text(Fr.faisonsConnaissance, style: Typo.enonce),
        const SizedBox(height: 40),
        Champ(
          etiquette: Fr.prenom,
          controleur: prenom,
          autoMajuscule: TextCapitalization.words,
          longueurMax: 40,
        ),
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 96 + 28 + 210 = 334 : la gouttière EST la marge. Il n'y a qu'une
            // seule mesure horizontale dans toute l'app.
            SizedBox(
              width: 96,
              child: Champ(
                etiquette: Fr.age,
                controleur: age,
                clavier: TextInputType.number,
                longueurMax: 3,
              ),
            ),
            const SizedBox(width: Mesures.marge),
            Expanded(
              child: Champ(
                etiquette: Fr.ville,
                controleur: ville,
                autoMajuscule: TextCapitalization.words,
                longueurMax: 60,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Champ(
          etiquette: Fr.anniversaire,
          controleur: naissance,
          indice: '14 / 03 / 1998',
          clavier: TextInputType.datetime,
          longueurMax: 14,
        ),
        const SizedBox(height: 32),
        Champ(
          etiquette: Fr.debutRelation,
          controleur: debut,
          indice: '02 / 06 / 2022',
          clavier: TextInputType.datetime,
          longueurMax: 14,
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _Objectifs extends StatelessWidget {
  const _Objectifs({required this.choisis, required this.onBascule});
  final Set<String> choisis;
  final ValueChanged<String> onBascule;

  @override
  Widget build(BuildContext context) {
    const options = {'complicite': Fr.complicite, 'decouverte': Fr.decouverte, 'fun': Fr.fun};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(Fr.vosObjectifs, style: Typo.enonce),
        const SizedBox(height: 40),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final e in options.entries)
              Puce(
                libelle: e.value,
                choisi: choisis.contains(e.key),
                onTap: () => onBascule(e.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _Mode extends StatelessWidget {
  const _Mode({required this.choisi, required this.onChoisir});
  final String choisi;
  final ValueChanged<String> onChoisir;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(Fr.votreMode, style: Typo.enonce),
        const SizedBox(height: 40),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Puce(
              libelle: Fr.modeCouple,
              choisi: choisi == 'couple',
              onTap: () => onChoisir('couple'),
            ),
            Puce(
              libelle: Fr.modeAmis,
              choisi: choisi == 'amis',
              onTap: () => onChoisir('amis'),
            ),
            // Mettre deux inconnus en relation demande une modération que la
            // règle de révélation rend difficile : une réponse abusive devient
            // lisible dès que la victime a répondu.
            Puce(
              libelle: Fr.modeAleatoire,
              mention: Fr.bientot,
              choisi: false,
              actif: false,
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _Appairage extends StatelessWidget {
  const _Appairage({required this.code});
  final TextEditingController code;

  @override
  Widget build(BuildContext context) {
    const monCode = 'LOVE42';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(Fr.reliezVosComptes, style: Typo.enonce),
        const SizedBox(height: 40),
        Text(Fr.votreCode, style: Typo.etiquette),
        const SizedBox(height: 16),
        // Le seul endroit de l'app où des caractères sont le sujet et non le
        // moyen. Ils sont donc traités comme tels : grands, espacés, en braise.
        Text(
          monCode.split('').join(' '),
          style: Typo.enonce.copyWith(
            color: Couleurs.braise,
            fontFamily: Polices.humain,
            fontSize: 34,
            letterSpacing: 4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Clipboard.setData(const ClipboardData(text: monCode)),
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 44,
            alignment: Alignment.centerLeft,
            child: Text(
              Fr.copier,
              style: Typo.secondaire.copyWith(
                color: Couleurs.braise,
                decoration: TextDecoration.underline,
                decorationColor: Couleurs.braise,
              ),
            ),
          ),
        ),
        Text(Fr.partagezLe, style: Typo.secondaire),
        const SizedBox(height: 40),
        Row(
          children: [
            const Expanded(child: ColoredBox(color: Couleurs.trait, child: SizedBox(height: 1))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(Fr.ou, style: Typo.secondaire),
            ),
            const Expanded(child: ColoredBox(color: Couleurs.trait, child: SizedBox(height: 1))),
          ],
        ),
        const SizedBox(height: 40),
        Champ(
          etiquette: Fr.jaiUnCode,
          controleur: code,
          indice: '– – – – – –',
          longueurMax: 6,
          autoMajuscule: TextCapitalization.characters,
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
