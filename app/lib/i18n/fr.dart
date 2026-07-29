/// Français. Anglais et espagnol suivront ; la structure est déjà celle qu'il
/// faut pour qu'une langue manquante ne compile pas.
///
/// Rien de visible à l'écran ne doit être écrit ailleurs qu'ici.
abstract final class Fr {
  static const appName = 'UsLink';

  // ------------------------------------------------------------ les contenus

  static const debat = 'débat';
  static const question = 'question';
  static const defi = 'défi';

  static const parceQue = 'parce que';
  static const repondre = 'Répondre';
  static const jeLaiFait = 'je l’ai fait';
  static const pasCetteFois = 'pas cette fois';

  static String joursEnsemble(int n) => n <= 1 ? '$n jour ensemble' : '$n jours ensemble';

  // ------------------------------------------------------ ACCESSIBILITÉ
  //
  // L'échelle du débat n'affiche AUCUN chiffre : « on ne se note pas, on se
  // place ». C'est juste pour l'œil, et c'est vide pour l'oreille — un lecteur
  // d'écran ne perçoit ni le halo, ni le nœud, ni le segment tracé entre les
  // deux positions. Sans ces chaînes, la station Débat n'a littéralement aucun
  // contenu après la révélation pour un utilisateur aveugle.
  //
  // On assume donc la contradiction : pas de chiffre à l'écran, un chiffre pour
  // la voix. Le parti pris sert l'émotion des voyants, il ne doit priver
  // personne du contenu.

  /// Chaque nœud de l'échelle, pendant qu'on choisit.
  static String positionChoix(int position, String poleBas, String poleHaut) =>
      'Position $position sur 5, de « $poleBas » à « $poleHaut »';

  /// L'échelle une fois ma position posée, avant que l'autre ait répondu.
  static String positionPosee(int moi, String poleBas, String poleHaut) =>
      'Vous êtes à $moi sur 5, de « $poleBas » à « $poleHaut ». '
      'Votre partenaire n’a pas encore répondu.';

  /// L'échelle après révélation. C'est la chaîne qui remplace, pour l'oreille,
  /// tout ce que le segment tracé raconte à l'œil.
  static String positionsRevelees(int moi, int autre, String prenom) {
    if (moi == autre) {
      return 'Vous êtes au même endroit, à $moi sur 5, $prenom et vous.';
    }
    final ecart = (moi - autre).abs();
    return 'Vous êtes à $moi sur 5, $prenom est à $autre sur 5. '
        '${ecart == 1 ? 'Un cran' : '$ecart crans'} d’écart.';
  }

  /// Étiquettes de voix. Présentes des DEUX côtés, jamais d'un seul : l'écart
  /// entre ma voix et la sienne est en luminance pure, il lui faut un doublon
  /// textuel pour exister en niveaux de gris comme à l'oreille.
  static const vous = 'vous';

  /// La série, dont les pastilles de 6 pt restent difficiles à distinguer pour
  /// une vision moyenne : la voix dit ce que la forme peine à dire.
  static String serie(int faits, int total) =>
      '$faits ${faits <= 1 ? 'nuit' : 'nuits'} sur $total';

  /// Le défi, qui n'a ni texte ni couleur sémantique.
  static const defiReleve = 'relevé';
  static const defiManque = 'pas cette fois';

  // ------------------------------------------------------------ onboarding
  //
  // Aucun emoji. Trois classes de traitement:
  //   A — l'emoji redit son libellé: on supprime, la suppression est le dessin.
  //   B — il porte une fonction que le mot ne porte pas: il devient un MOT.
  //   C — il porte un ÉTAT: il devient une forme déjà du vocabulaire (filet,
  //       cercle, pastille), jamais le dessin d'une chose.
  // Un mot passe l'espagnol ; un pictogramme demande d'être dessiné, documenté
  // et deviné.

  static String etape(int n, int total) => 'étape $n sur $total';

  static const faisonsConnaissance = 'Faisons connaissance';
  static const prenom = 'prénom';
  static const age = 'âge';
  static const ville = 'ville';
  static const anniversaire = 'date d’anniversaire';
  static const debutRelation = 'début de votre relation';
  static const continuer = 'Continuer';
  static const plusTard = 'Plus tard';

  static const reliezVosComptes = 'Reliez vos comptes';
  static const votreCode = 'votre code';
  static const copier = 'Copier';
  static const codeCopie = 'Copié';
  static const partagezLe = 'Partagez-le avec votre partenaire.';
  static const ou = 'ou';
  static const jaiUnCode = 'j’ai déjà un code';
  static const rejoindre = 'Rejoindre';

  static const vosObjectifs = 'Ce que vous voulez travailler';
  static const complicite = 'complicité';
  static const decouverte = 'découverte';
  static const fun = 'fun';

  static const votreMode = 'Comment vous vous reliez';
  static const modeCouple = 'en couple';
  static const modeAmis = 'entre amis';
  static const modeAleatoire = 'aléatoire';
  static const bientot = 'bientôt';

  // ---------------------------------------------------------- les réglages

  static const compte = 'compte';
  static const preferences = 'préférences';
  static const contenu = 'contenu';
  static const confidentialite = 'confidentialité';

  static const monProfil = 'Mon profil';
  static const gererLeCouple = 'Gérer le couple';
  static const langue = 'Langue';
  static const notifications = 'Notifications';
  static const luminosite = 'Luminosité';
  // Pas « Thème » : il n'y a pas de thème clair. Ce réglage éclaircit le fond,
  // il ne bascule pas vers un autre design.
  static const luminositeAide =
      'Éclaircit le fond pour la lecture de jour. La révélation garde son éclat.';
  static const niveauIntimite = 'Niveau d’intimité';
  static const supprimerMesDonnees = 'Supprimer mes données';
  static const seDeconnecter = 'Se déconnecter';

  // ---------------------------------------------------------- les métriques
  //
  // RÈGLE: on garde ce qui MONTE ou ce qui DÉCRIT, on retire ce qui COMPARE.
  //
  // Le problème n'est pas le chiffre, c'est la comparaison. « Série 12 j » à
  // côté de « Record 21 j » dit littéralement « vous faites moins bien
  // qu'avant » ; « Ensemble depuis 843 jours » ne fait pas mal parce qu'il ne
  // monte que.
  //
  // Donc: pas de record, pas de « réussis » (un défi non fait deviendrait un
  // échec). Comme sur l'échelle du débat — on se place, on ne se note pas.

  static String serieEnCours(int n) => n <= 1 ? '$n jour de suite' : '$n jours de suite';
  static String echanges(int n) => n <= 1 ? '$n échange' : '$n échanges';

  /// « relevés », jamais « réussis » : un couple qui a ouvert un défi sans le
  /// finir n'a rien raté.
  static String defisReleves(int n) => n <= 1 ? '$n défi relevé' : '$n défis relevés';

  // ------------------------------------------------------ la confidentialité
  //
  // On dit précisément ce qu'on fait, plutôt que de brandir le mot
  // « chiffrement ». Un vrai bout-en-bout empêcherait le serveur de lire —
  // donc supprimerait la personnalisation, les statistiques et les résumés.
  // Ce serait un argument marketing qui vide la maison.

  static const confidentialiteTitre = 'Vos réponses';
  static const confidentialiteCorps =
      'Vos échanges voyagent chiffrés et sont stockés chiffrés. '
      'Aucun autre couple ne peut les lire, jamais — c’est une règle de la '
      'base de données, pas un réglage.';
  static const iaTitre = 'Ce que l’IA voit';
  static const iaCorps =
      'Elle écrit la question du jour à partir de votre mode, de vos centres '
      'd’intérêt et des thèmes déjà abordés. '
      'Elle ne voit jamais votre prénom, votre ville, ni votre adresse e-mail.';

  // ------------------------------------------------------------- les erreurs

  static const erreurReseau = 'Votre réponse n’est pas partie.';
  static const erreurReseauAction = 'Réessayer';
  static const erreurGenerique = 'Quelque chose n’a pas fonctionné.';
  static const erreurJournee =
      'La journée n’a pas pu s’ouvrir. Réessayez dans un instant.';
}
