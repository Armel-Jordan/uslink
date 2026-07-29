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
