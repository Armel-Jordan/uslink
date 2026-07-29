# UsLink

Une app de couple : deux personnes reliées reçoivent chaque jour les mêmes trois
contenus, chacune répond de son côté, et **la réponse de l'autre ne devient
visible qu'une fois qu'on a répondu soi-même**. Tout le produit sert ce moment.

## Structure

```
app/        Flutter (Dart 3.12, Flutter 3.44)
supabase/   schéma, migrations, tests RLS
docs/       maquettes et décisions
```

## Avant de commiter

```
cd app && flutter analyze && flutter test
```

## La direction visuelle : « Braise »

**Il n'y a pas de thème clair, et ce n'est pas un oubli.** La mécanique centrale
est une révélation ; une révélation qui « éclaire » sur fond blanc ne révèle
rien. Le fond sombre est le support de la métaphore, pas un habillage. Ne pas
ajouter `darkTheme` ni `themeMode`.

**Ni noir absolu, ni blanc pur.** `#000` durcit l'image, `#FFF` bave sur fond
sombre (halation), surtout pour les astigmates. On reste à l'intérieur des deux
côtés — voir `app/lib/design/couleurs.dart`, où chaque valeur porte son ratio
recalculé.

**Une seule couleur chaude.** La braise n'est autorisée que sur trois choses :
nommer le contenu, déclencher l'action, signer la révélation. Le jour où
quelqu'un ajoute « juste un vert pour le défi réussi », la direction meurt. La
seule exception admise est l'erreur bloquante, qui utilise la braise et un filet
pleine largeur — jamais un rouge.

**La règle de voix.** Le serif (Newsreader) est la voix de l'app : la question,
l'affirmation, le défi à relever. La sans-serif (Inter) est la voix des deux
personnes et de l'interface. Aucune exception : c'est cette règle qui fait qu'on
sait qui parle sans avoir à l'écrire.

**Pas de carte, pas d'ombre, pas de coin arrondi** sauf les cercles. Le texte est
posé à même la nuit.

**L'écart entre les deux voix est en luminance pure** (2,18:1). Il doit donc
toujours être doublé d'une étiquette textuelle **des deux côtés** — jamais d'un
seul, sinon l'asymétrie laisse deviner en niveaux de gris comme en lecture
d'écran.

## La règle de révélation est une règle de base de données

Elle vit dans une policy RLS Postgres, jamais dans le client. Un client modifié,
ou `curl` avec le jeton extrait du trousseau, contourne n'importe quelle
condition écrite en Dart. La seule frontière que l'utilisateur ne franchit pas
est le `USING` d'une policy, évalué par Postgres après authentification.

Corollaire : toute règle de VISIBILITÉ appartient à la base. Les niveaux
d'intimité aussi — et par un trigger plutôt qu'une policy, parce que le
générateur tourne en `service_role` et ne passe pas par la RLS.

## Le jour est une notion serveur

Le jour civil vient du fuseau du LIEN, pas de l'appareil. Deux partenaires dans
deux fuseaux différents doivent voir la même question : si chaque appareil
calcule sa date, ils créent deux contenus distincts dont la révélation ne peut
jamais devenir vraie. Ne jamais dater quoi que ce soit avec `DateTime.now()`
côté client.

## L'IA

`IAService`, une seule implémentation, configuration externe, prompts dans des
fichiers séparés. Pas de routeur tiers : le contenu est intime, et la
portabilité qu'un routeur achète se paie une seule fois, le jour où on en a
besoin.

Le modèle n'est appelé que côté serveur. Il ne voit jamais un prénom, un e-mail,
une ville, ni le texte d'une réponse sans consentement explicite.

Tout chemin d'échec retombe sur la banque de contenus locale plutôt que de
laisser un jour sans question.

## Langues

Français, anglais, espagnol au lancement. L'arabe viendra : ne pas prendre de
décision qui rende le RTL coûteux, et remettre l'interlettrage à zéro pour `ar`
(il casse le liage).

Les pluriels passent par les catégories CLDR, jamais par `n <= 1` — juste en
français, faux en arabe qui en a six.

## Contenu

`docs/` garde les décisions de conception. La banque de contenus (débats,
questions, défis) est du travail éditorial : elle se relit, elle ne s'improvise
pas. Un débat dont les deux pôles ne sont pas également défendables n'est pas un
débat, c'est un sondage — et la statistique d'accord ne dit alors rien.
