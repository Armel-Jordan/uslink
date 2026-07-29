import type { Locale } from '@/lib/strings';
import type {
  Answer,
  AnswerInput,
  DailyPrompt,
  HistoryEntry,
  ItemKind,
  Link,
  LinkMode,
  Goal,
  Interest,
  Onboarding,
  Profile,
  Session,
  TodayState,
} from '@/lib/types';

export type DataErrorCode =
  | 'invalid_code'
  | 'own_code'
  | 'link_full'
  | 'already_linked'
  | 'no_link'
  | 'no_prompt'
  | 'invalid_time_zone'
  | 'time_zone_cooldown'
  | 'invalid_locale'
  | 'invalid_date'
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

  getOnboarding(): Promise<Onboarding>;
  saveOnboarding(patch: Partial<Onboarding>): Promise<Onboarding>;
  /** Fixe la date de début du couple. Les deux ont pu en déclarer deux différentes. */
  setStartedOn(date: string): Promise<Link>;

  getProfile(): Promise<Profile>;
  updateProfile(patch: Partial<Pick<Profile, 'displayName' | 'avatarEmoji'>>): Promise<Profile>;

  getLink(): Promise<Link | null>;
  createLink(mode: LinkMode): Promise<Link>;
  joinLink(code: string): Promise<Link>;
  /** Un code est consommé à l'appairage et purgé au départ : il faut pouvoir en refaire un. */
  regenerateInvite(): Promise<string>;
  /** Déplace l'horloge du couple. Explicite : un voyage ne bouge pas la journée de l'autre tout seul. */
  setTimeZone(timeZone: string): Promise<Link>;
  /** Change la langue des questions. Le lien en a une seule, comme il n'a qu'une horloge. */
  setLocale(locale: Locale): Promise<Link>;
  leaveLink(): Promise<void>;

  getToday(): Promise<TodayState | null>;
  /** L'union `AnswerInput` interdit à la compilation les formes qu'`answers_shape` refuse à l'exécution. */
  submitAnswer(promptId: string, input: AnswerInput): Promise<Answer>;
  toggleReaction(answerId: string, emoji: string): Promise<void>;

  getHistory(): Promise<HistoryEntry[]>;
  getStreak(): Promise<number>;
};

/**
 * IANA time zone of the device — proposé au serveur à la création d'un lien,
 * jamais utilisé pour dater quoi que ce soit. Le jour vient de `Link.today`.
 */
export function deviceTimeZone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'Europe/Paris';
  } catch {
    return 'Europe/Paris';
  }
}

export function makePrompt(
  id: string,
  date: string,
  kind: ItemKind,
  question: string,
  category: string,
  options: DailyPrompt['options'],
  source: DailyPrompt['source'],
): DailyPrompt {
  return { id, date, kind, question, category, options, source };
}
