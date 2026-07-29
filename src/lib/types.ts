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
};

export type DailyPrompt = {
  id: string;
  /** ISO date, `YYYY-MM-DD`, in the link's local day. */
  date: string;
  question: string;
  category: string;
  source: PromptSource;
};

export type Answer = {
  id: string;
  promptId: string;
  authorId: string;
  body: string;
  createdAt: string;
  reactions: string[];
};

/**
 * The whole state of the Today screen. `revealed` is true only when both
 * people have answered — that gate is the core of the product.
 */
export type TodayState = {
  prompt: DailyPrompt;
  mine: Answer | null;
  theirs: Answer | null;
  revealed: boolean;
};

export type HistoryEntry = {
  prompt: DailyPrompt;
  mine: Answer | null;
  theirs: Answer | null;
};

export type Session = {
  userId: string;
  email: string | null;
};
