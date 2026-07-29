import type { Locale } from '@/lib/strings';

export type LinkMode = 'couple' | 'friends' | 'random';

export type PromptSource = 'ai' | 'library';

export type Profile = {
  id: string;
  displayName: string;
  avatarEmoji: string;
};

/** A "link" is the pair of people sharing a daily question (a couple, or two friends). */
export type Link = {
  id: string;
  mode: LinkMode;
  createdAt: string;
  /** Null while waiting for the second person to join. */
  partner: Profile | null;
  inviteCode: string | null;
  /**
   * IANA time zone of the link, and the civil day derived from it by the
   * server. The couple shares one clock: if each device kept its own, two
   * partners in two zones would work on two different questions and the
   * reveal would never happen. The client never computes this.
   */
  timeZone: string;
  today: string;
  /** Hour at which the link's day rolls over, so a 00:30 answer still counts. */
  dayStartHour: number;
  /**
   * Langue du lien. Comme l'horloge : deux personnes partagent un contenu,
   * donc une langue. C'est elle qui décide de la langue des questions, pas le
   * réglage du téléphone de chacun.
   */
  locale: Locale;
  /** Date de début de la relation, null tant que personne ne l'a dite. */
  startedOn: string | null;
  /** Jours ensemble, calculé SERVEUR : `new Date()` ici rouvrirait l'horloge d'appareil. */
  daysTogether: number | null;
  /** Ce que l'autre a déclaré à l'onboarding, pour trancher quand les deux dates diffèrent. */
  partnerStartedOn: string | null;
};

/** Liste fermée, contrainte aussi en base. */
export const INTERESTS = [
  'cuisine', 'voyage', 'sport', 'musique', 'cinema', 'lecture',
  'jeux', 'nature', 'art', 'tech', 'bienetre', 'sorties',
] as const;
export type Interest = (typeof INTERESTS)[number];

export const GOALS = ['complicite', 'decouverte', 'fun'] as const;
export type Goal = (typeof GOALS)[number];

/**
 * Ce que chacun déclare pour soi. Ville et date de naissance exacte vivent
 * dans une table que le partenaire ne lit pas — la RLS filtre par ligne, pas
 * par colonne, donc la séparation est physique et non déclarative.
 */
export type Onboarding = {
  birthDate: string | null;
  city: string | null;
  interests: Interest[];
  goals: Goal[];
  relationshipStartedOn: string | null;
  completed: boolean;
};

/**
 * Trois types, une seule primitive. Un débat porte une position mesurable —
 * c'est ce qui rend le « vous êtes d'accord à 72 % » calculable ailleurs qu'à
 * coups d'appels au modèle. Un défi se relève d'un geste et ne porte aucun
 * texte : sinon un appui sur « fait » déverrouillerait le commentaire écrit du
 * partenaire.
 */
export type ItemKind = 'question' | 'debate' | 'challenge';

/** Position sur l'échelle d'un débat : 1 = pôle bas, 5 = pôle haut. */
export type Stance = 1 | 2 | 3 | 4 | 5;

export type DailyPrompt = {
  id: string;
  /** ISO date, `YYYY-MM-DD`, in the link's local day. */
  date: string;
  kind: ItemKind;
  question: string;
  category: string;
  /** Les deux pôles d'un débat, ou la durée indicative d'un défi. */
  options: { low: string; high: string } | { durationMin: number } | null;
  source: PromptSource;
};

export type Answer = {
  id: string;
  promptId: string;
  authorId: string;
  kind: ItemKind;
  /** Null pour un défi, qui ne porte aucun texte. */
  body: string | null;
  stance: Stance | null;
  done: boolean | null;
  createdAt: string;
  reactions: string[];
};

/** Ce qu'un écran envoie pour répondre. Le type interdit les combinaisons impossibles. */
export type AnswerInput =
  | { kind: 'question'; body: string }
  | { kind: 'debate'; stance: Stance; body: string }
  | { kind: 'challenge'; done: boolean };

/**
 * Un contenu et son état. `revealed` est vrai seulement quand les deux ont
 * répondu — c'est le cœur du produit, et la révélation est PAR CONTENU : on
 * voit son débat dès qu'on a débattu, sans attendre le défi du soir.
 */
export type ItemState = {
  prompt: DailyPrompt;
  mine: Answer | null;
  theirs: Answer | null;
  revealed: boolean;
};

export type TodayState = {
  date: string;
  /** Ordonnés débat → question → défi. Trois au maximum, moins si la journée s'ouvre mal. */
  items: ItemState[];
};

export type HistoryEntry = {
  date: string;
  items: ItemState[];
};

export type Session = {
  userId: string;
  email: string | null;
};
