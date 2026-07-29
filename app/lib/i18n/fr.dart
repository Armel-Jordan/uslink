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

  // ------------------------------------------------------------- les erreurs

  static const erreurReseau = 'Votre réponse n’est pas partie.';
  static const erreurReseauAction = 'Réessayer';
  static const erreurGenerique = 'Quelque chose n’a pas fonctionné.';
  static const erreurJournee =
      'La journée n’a pas pu s’ouvrir. Réessayez dans un instant.';
}
