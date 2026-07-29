/**
 * All user-facing copy lives here (French). To add a locale, copy this file,
 * keep the same shape, and type it as `Dictionary`.
 */

export const fr = {
  appName: 'UsLink',
  tagline: 'Une question par jour, rien que pour vous deux.',

  tabs: {
    today: "Aujourd'hui",
    history: 'Souvenirs',
    profile: 'Profil',
  },

  auth: {
    signInTitle: 'Bon retour',
    signUpTitle: 'Créer votre espace',
    email: 'E-mail',
    password: 'Mot de passe',
    displayName: 'Votre prénom',
    signIn: 'Se connecter',
    signUp: "S'inscrire",
    toSignUp: "Pas encore de compte ? S'inscrire",
    toSignIn: 'Déjà un compte ? Se connecter',
    demoNotice: 'Mode démo : aucune configuration Supabase détectée.',
    demoContinue: 'Entrer en mode démo',
    checkEmail: 'Vérifiez votre boîte mail pour confirmer votre adresse.',
  },

  pairing: {
    title: 'Reliez-vous',
    subtitle: 'UsLink se vit à deux. Choisissez comment vous connecter.',
    modeCouple: 'En couple',
    modeCoupleHint: 'Des questions intimes pour vous deux, chaque jour.',
    modeFriends: 'Entre amis',
    modeFriendsHint: 'Le même rituel, sur un ton plus léger.',
    modeRandom: 'Aléatoire',
    modeRandomHint: 'Bientôt : découvrez quelqu’un via une question.',
    comingSoon: 'Bientôt',
    invite: 'Inviter mon partenaire',
    inviteHint: 'Partagez ce code, il est valable 7 jours.',
    haveCode: "J'ai un code d'invitation",
    codeLabel: 'Code à 6 caractères',
    join: 'Rejoindre',
    copy: 'Copier le code',
    copied: 'Code copié',
    share: 'Partager',
    waiting: 'En attente de votre partenaire…',
    joined: 'Vous êtes reliés !',
    invalidCode: 'Ce code est invalide ou expiré.',
    ownCode: 'Ce code est le vôtre — partagez-le à votre partenaire.',
    full: 'Ce lien est déjà complet.',
    back: 'Retour',
    noCode: "Ce lien n'a plus de code d'invitation actif.",
    regenerate: 'Générer un nouveau code',
  },

  today: {
    greeting: (name: string) => `Salut ${name}`,
    questionOf: "La question du jour",
    generating: 'Votre question du jour arrive…',
    yourAnswer: 'Votre réponse',
    placeholder: 'Écrivez ce qui vous vient, sans filtre…',
    send: 'Envoyer ma réponse',
    edit: 'Modifier',
    save: 'Enregistrer',
    waitingPartner: (name: string) => `${name} n'a pas encore répondu. On garde le suspense.`,
    revealed: 'Vos deux réponses',
    frozen: (name: string) => `${name} a répondu : votre réponse est figée. C'est ce qui la rend sincère.`,
    you: 'Vous',
    streak: (n: number) => (n <= 1 ? `${n} jour de suite` : `${n} jours de suite`),
    noStreak: 'Commencez votre série aujourd’hui',
    aiHint: 'Question personnalisée par IA',
    libraryHint: 'Question de notre sélection',
    alone: 'Reliez-vous à quelqu’un pour commencer.',
    reactionSent: 'Réaction envoyée',
  },

  history: {
    title: 'Vos souvenirs',
    empty: 'Vos échanges apparaîtront ici, jour après jour.',
    unanswered: 'Sans réponse',
    onlyYou: 'Vous seul(e) avez répondu',
  },

  profile: {
    title: 'Profil',
    displayName: 'Prénom affiché',
    avatar: 'Votre emoji',
    save: 'Enregistrer',
    saved: 'Enregistré',
    link: 'Votre lien',
    noLink: "Vous n'avez pas de lien actif.",
    linkedWith: (name: string) => `Relié(e) à ${name}`,
    timeZone: 'Fuseau du lien',
    // L'identifiant IANA est affiché tel quel : le découper donnerait « heure
    // de London » ou « heure de UTC ». Un nom de ville en anglais mal accordé
    // est pire qu'un identifiant assumé.
    timeZoneHint: (zone: string, hour: number) =>
      `Votre journée commence à ${hour} h (${zone}). Vous partagez une seule horloge : c'est ce qui fait que vous voyez la même question au même moment.`,
    timeZoneUse: 'Utiliser le fuseau de cet appareil',
    timeZoneCooldown: 'Le fuseau ne peut être changé qu’une fois par 24 heures.',
    timeZoneInvalid: 'Ce fuseau horaire est inconnu.',
    inviteCode: "Code d'invitation",
    mode: 'Mode',
    signOut: 'Se déconnecter',
    leave: 'Quitter ce lien',
    leaveConfirm:
      "Quitter ce lien ? Le code d'invitation sera révoqué. Si vous partez tous les deux, vos souvenirs seront supprimés.",
    danger: 'Zone sensible',
    demoBanner: 'Mode démo — les données restent sur cet appareil.',
    cancel: 'Annuler',
  },

  common: {
    loading: 'Chargement…',
    retry: 'Réessayer',
    error: 'Une erreur est survenue.',
    noPrompt: "La question du jour n'a pas pu être ouverte. Réessayez dans un instant.",
    ok: 'OK',
  },
} as const;

export type Dictionary = typeof fr;

export const t = fr;
