import type { Answer, DailyPrompt, HistoryEntry, Link, LinkMode, Profile, Session, TodayState } from '@/lib/types';

export type DataErrorCode =
  | 'invalid_code'
  | 'own_code'
  | 'link_full'
  | 'already_linked'
  | 'no_link'
  | 'no_prompt'
  | 'auth'
  | 'unknown';

export class DataError extends Error {
  code: DataErrorCode;

  constructor(code: DataErrorCode, message: string) {
    super(message);
    this.code = code;
    this.name = 'DataError';
  }
}

/**
 * Everything the UI needs. Two implementations exist — Supabase and a local
 * demo store — so screens never branch on whether a backend is configured.
 */
export type DataAdapter = {
  readonly isDemo: boolean;

  getSession(): Promise<Session | null>;
  /** Returns an unsubscribe function. */
  onSessionChange(listener: (session: Session | null) => void): () => void;
  signIn(email: string, password: string): Promise<void>;
  signUp(email: string, password: string, displayName: string): Promise<{ needsConfirmation: boolean }>;
  signOut(): Promise<void>;

  getProfile(): Promise<Profile>;
  updateProfile(patch: Partial<Pick<Profile, 'displayName' | 'avatarEmoji'>>): Promise<Profile>;

  getLink(): Promise<Link | null>;
  createLink(mode: LinkMode): Promise<Link>;
  joinLink(code: string): Promise<Link>;
  /** Un code est consommé à l'appairage et purgé au départ : il faut pouvoir en refaire un. */
  regenerateInvite(): Promise<string>;
  leaveLink(): Promise<void>;

  getToday(): Promise<TodayState | null>;
  submitAnswer(promptId: string, body: string): Promise<Answer>;
  toggleReaction(answerId: string, emoji: string): Promise<void>;

  getHistory(): Promise<HistoryEntry[]>;
  getStreak(): Promise<number>;
};

/** Local calendar day of the device, `YYYY-MM-DD`. */
export function localDate(d: Date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function makePrompt(
  id: string,
  date: string,
  question: string,
  category: string,
  source: DailyPrompt['source'],
): DailyPrompt {
  return { id, date, question, category, source };
}
