import AsyncStorage from '@react-native-async-storage/async-storage';

import { ITEM_KINDS, pickLibraryDay } from '@/lib/prompt-library';
import type {
  Answer,
  DailyPrompt,
  HistoryEntry,
  ItemKind,
  ItemState,
  Link,
  Profile,
  Session,
  Stance,
  TodayState,
} from '@/lib/types';

import { locale as appLocale } from '@/lib/strings';

import { DataError, deviceTimeZone, type DataAdapter } from './adapter';

/**
 * Local-only adapter so the app is fully usable before any backend exists.
 * State lives in AsyncStorage; a scripted partner ("Camille") answers a beat
 * after you do, which is what makes the reveal mechanic demonstrable solo.
 */

const KEY = 'uslink.demo.v1';
const ME = 'demo-me';
const PARTNER = 'demo-partner';

const PARTNER_PROFILE: Profile = { id: PARTNER, displayName: 'Camille', avatarEmoji: '🌙' };

const PARTNER_REPLIES = [
  "J'y ai pensé toute la journée en fait. Ce matin quand tu as préparé le café sans rien dire — c'est bête mais ça m'a fait du bien.",
  "Franchement je ne savais pas quoi répondre au début, et puis c'est venu d'un coup. Merci de poser la question.",
  "Je crois que je ne te l'ai jamais dit comme ça. J'ai besoin de plus de moments sans écran avec toi, juste marcher.",
  'Ça me touche que tu demandes. Il y a des jours où je fais semblant que tout va bien alors que non.',
  'Je repense souvent à ce week-end sous la pluie. On était trempés et on riait bêtement.',
];

type DemoState = {
  session: Session | null;
  profile: Profile;
  link: Link | null;
  prompts: DailyPrompt[];
  answers: Answer[];
  seeded: boolean;
};

function id(prefix: string) {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}`;
}

function code() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < 6; i++) out += alphabet[Math.floor(Math.random() * alphabet.length)];
  return out;
}

/** Bascule à 4 h, comme `links.day_start_hour` côté serveur. */
const DAY_START_HOUR = 4;

/**
 * Copie privée, assumée : la démo n'a pas de serveur, donc pas d'horloge
 * partagée, donc aucun désaccord possible entre deux appareils. Côté Supabase
 * cette fonction n'existe plus — le jour vient de `link_today()`.
 */
function localDate(d: Date = new Date()): string {
  // `setHours` fait de l'arithmétique d'heure murale, comme
  // `(now() at time zone tz) - make_interval(hours => n)` côté SQL. Retrancher
  // 4 h à l'instant (`getTime() - 4 * 3600e3`) décalerait la bascule d'une
  // heure les jours de changement d'heure.
  const shifted = new Date(d);
  shifted.setHours(shifted.getHours() - DAY_START_HOUR);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${shifted.getFullYear()}-${pad(shifted.getMonth() + 1)}-${pad(shifted.getDate())}`;
}

function daysAgo(n: number) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return localDate(d);
}

function demoLink(partial: Omit<Link, 'timeZone' | 'today' | 'dayStartHour' | 'locale'>): Link {
  return {
    ...partial,
    timeZone: deviceTimeZone(),
    today: localDate(),
    dayStartHour: DAY_START_HOUR,
    locale: appLocale,
  };
}

function emptyState(): DemoState {
  return {
    session: null,
    profile: { id: ME, displayName: 'Vous', avatarEmoji: '☀️' },
    link: null,
    prompts: [],
    answers: [],
    seeded: false,
  };
}

let cache: DemoState | null = null;
const listeners = new Set<(s: Session | null) => void>();

async function read(): Promise<DemoState> {
  if (cache) return cache;
  try {
    const raw = await AsyncStorage.getItem(KEY);
    cache = raw ? { ...emptyState(), ...(JSON.parse(raw) as DemoState) } : emptyState();
  } catch {
    cache = emptyState();
  }
  return cache;
}

async function write(next: DemoState) {
  cache = next;
  await AsyncStorage.setItem(KEY, JSON.stringify(next));
}

function requireSession(state: DemoState): Session {
  if (!state.session) throw new DataError('auth', 'Session absente.');
  return state.session;
}

function requireLink(state: DemoState): Link {
  if (!state.link) throw new DataError('no_link', 'Aucun lien actif.');
  return state.link;
}

function answerFor(state: DemoState, promptId: string, authorId: string): Answer | null {
  return state.answers.find((a) => a.promptId === promptId && a.authorId === authorId) ?? null;
}

const KIND_ORDER: Record<ItemKind, number> = { debate: 0, question: 1, challenge: 2 };

/** Les trois contenus du jour, créés une seule fois puis relus. */
function ensureDay(state: DemoState, link: Link, date: string): DailyPrompt[] {
  const existing = state.prompts.filter((p) => p.date === date);
  if (existing.length >= ITEM_KINDS.length) return sortByKind(existing);

  const picked = pickLibraryDay(link.mode, link.id, date, link.locale);
  const manquants = picked.filter(({ kind }) => !existing.some((p) => p.kind === kind));
  const crees: DailyPrompt[] = manquants.map(({ kind, item }) => ({
    id: id('item'),
    date,
    kind,
    question: item.question,
    category: item.category,
    options:
      kind === 'debate' && item.options && 'low' in item.options
        ? { low: item.options.low, high: item.options.high }
        : kind === 'challenge' && item.options && 'durationMin' in item.options
          ? { durationMin: item.options.durationMin }
          : null,
    source: 'library',
  }));
  state.prompts = [...state.prompts, ...crees];
  return sortByKind([...existing, ...crees]);
}

function sortByKind(prompts: DailyPrompt[]): DailyPrompt[] {
  return [...prompts].sort((x, y) => KIND_ORDER[x.kind] - KIND_ORDER[y.kind]);
}

/**
 * Ce que Camille répond. Sa position sur un débat est DÉRIVÉE de la vôtre et
 * non tirée au hasard : on obtient environ 70 % d'accord avec de vraies
 * divergences, donc un écran de statistiques qui montre quelque chose plutôt
 * qu'un nuage de points sans forme.
 */
function partnerAnswer(prompt: DailyPrompt, mine: Answer | null, index: number): Answer {
  const ecart = [0, 0, 1, -1, 2][hashOf(prompt.id) % 5];
  const stance =
    prompt.kind === 'debate' && mine?.stance
      ? (Math.min(5, Math.max(1, mine.stance + ecart)) as Stance)
      : null;
  return {
    id: id('ans'),
    promptId: prompt.id,
    authorId: PARTNER,
    kind: prompt.kind,
    body: prompt.kind === 'challenge' ? null : PARTNER_REPLIES[index % PARTNER_REPLIES.length],
    stance,
    done: prompt.kind === 'challenge' ? hashOf(prompt.id) % 4 !== 0 : null,
    createdAt: new Date().toISOString(),
    reactions: [],
  };
}

function hashOf(input: string): number {
  let h = 2166136261;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

function itemState(state: DemoState, prompt: DailyPrompt): ItemState {
  const mine = answerFor(state, prompt.id, ME);
  const theirs = answerFor(state, prompt.id, PARTNER);
  return { prompt, mine, theirs, revealed: Boolean(mine && theirs) };
}

/** Sème trente jours pour que Souvenirs, la série et les statistiques aient de quoi montrer. */
function seedHistory(state: DemoState, link: Link) {
  if (state.seeded) return;
  const mineSamples = [
    "Ce moment où on n'a rien dit pendant dix minutes et c'était très bien comme ça.",
    "J'ai besoin qu'on planifie moins et qu'on improvise plus, je crois.",
    'Je suis fier de nous pour la façon dont on a géré la semaine dernière.',
    "Franchement, la soirée d'hier m'a fait plus de bien que je ne pensais.",
    "Je crois que je n'ai pas encore vraiment digéré cette semaine, mais ça va.",
  ];

  for (let n = 30; n >= 1; n--) {
    const date = daysAgo(n);
    const prompts = ensureDay(state, link, date);
    // Un jour sur sept sans réponse: une série qui n'a jamais de trou ne
    // ressemble à rien, et l'écran Souvenirs doit savoir le montrer.
    if (n % 7 === 3) continue;

    for (const prompt of prompts) {
      const mine: Answer = {
        id: id('ans'),
        promptId: prompt.id,
        authorId: ME,
        kind: prompt.kind,
        body: prompt.kind === 'challenge' ? null : mineSamples[(n + KIND_ORDER[prompt.kind]) % mineSamples.length],
        stance: prompt.kind === 'debate' ? (((hashOf(prompt.id + 'me') % 5) + 1) as Stance) : null,
        done: prompt.kind === 'challenge' ? hashOf(prompt.id + 'me') % 5 !== 0 : null,
        createdAt: new Date().toISOString(),
        reactions: [],
      };
      state.answers = [...state.answers, mine, partnerAnswer(prompt, mine, n)];
    }
  }
  state.seeded = true;
}

function notify(session: Session | null) {
  listeners.forEach((l) => l(session));
}

export const demoAdapter: DataAdapter = {
  isDemo: true,

  async getSession() {
    return (await read()).session;
  },

  onSessionChange(listener) {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },

  async signIn(email) {
    const state = await read();
    const session: Session = { userId: ME, email: email || 'demo@uslink.app' };
    await write({ ...state, session });
    notify(session);
  },

  async signUp(email, _password, displayName) {
    const state = await read();
    const session: Session = { userId: ME, email: email || 'demo@uslink.app' };
    await write({
      ...state,
      session,
      profile: { ...state.profile, displayName: displayName || state.profile.displayName },
    });
    notify(session);
    return { needsConfirmation: false };
  },

  async signOut() {
    const state = await read();
    await write({ ...state, session: null });
    notify(null);
  },

  async getProfile() {
    const state = await read();
    requireSession(state);
    return state.profile;
  },

  async updateProfile(patch) {
    const state = await read();
    requireSession(state);
    const profile = { ...state.profile, ...patch };
    await write({ ...state, profile });
    return profile;
  },

  async getLink() {
    const link = (await read()).link;
    // `today` est recalculé à chaque lecture: le stocker le figerait au jour de
    // l'appairage, et la démo passerait minuit sans changer de question.
    return link ? { ...link, today: localDate() } : null;
  },

  async createLink(mode) {
    const state = await read();
    requireSession(state);
    // In demo the partner joins immediately — otherwise there is nothing to reveal.
    const link = demoLink({
      id: id('link'),
      mode,
      createdAt: new Date().toISOString(),
      partner: PARTNER_PROFILE,
      inviteCode: code(),
    });
    const next = { ...state, link };
    seedHistory(next, link);
    await write(next);
    return link;
  },

  async joinLink(input) {
    const state = await read();
    requireSession(state);
    if (input.trim().length !== 6) throw new DataError('invalid_code', 'Code invalide.');
    const link = demoLink({
      id: id('link'),
      mode: 'couple',
      createdAt: new Date().toISOString(),
      partner: PARTNER_PROFILE,
      // Le code est consommé à l'appairage, comme côté Supabase.
      inviteCode: null,
    });
    const next = { ...state, link };
    seedHistory(next, link);
    await write(next);
    return link;
  },

  async regenerateInvite() {
    const state = await read();
    const link = requireLink(state);
    if (link.partner) throw new DataError('link_full', 'Ce lien est déjà complet.');
    const next = code();
    await write({ ...state, link: { ...link, inviteCode: next } });
    return next;
  },

  async setLocale(next) {
    const state = await read();
    const link = requireLink(state);
    const updated = { ...link, locale: next };
    await write({ ...state, link: updated });
    return updated;
  },

  async setTimeZone(timeZone) {
    const state = await read();
    const link = requireLink(state);
    const next = { ...link, timeZone, today: localDate() };
    await write({ ...state, link: next });
    return next;
  },

  async leaveLink() {
    const state = await read();
    requireSession(state);
    // Le partenaire de démo est scripté : partir, c'est partir à deux. C'est
    // donc bien le cas « plus personne dans le lien » côté Supabase, où la
    // cascade emporte prompts, réponses et réactions.
    await write({ ...state, link: null, prompts: [], answers: [], seeded: false });
  },

  async getToday() {
    const state = await read();
    requireSession(state);
    if (!state.link) return null;
    const date = localDate();
    const prompts = ensureDay(state, state.link, date);
    await write(state);
    return { date, items: prompts.map((p) => itemState(state, p)) };
  },

  async submitAnswer(promptId, input) {
    const state = await read();
    requireSession(state);
    requireLink(state);
    const prompt = state.prompts.find((p) => p.id === promptId);
    if (!prompt) throw new DataError('no_prompt', 'Contenu introuvable.');

    const existing = answerFor(state, promptId, ME);
    const mine: Answer = {
      id: existing?.id ?? id('ans'),
      promptId,
      authorId: ME,
      kind: input.kind,
      body: input.kind === 'challenge' ? null : input.body,
      stance: input.kind === 'debate' ? input.stance : null,
      done: input.kind === 'challenge' ? input.done : null,
      createdAt: existing?.createdAt ?? new Date().toISOString(),
      reactions: existing?.reactions ?? [],
    };
    let answers = existing
      ? state.answers.map((x) => (x.id === existing.id ? mine : x))
      : [...state.answers, mine];

    // Camille répond CONTENU PAR CONTENU, après vous : c'est ce qui rend la
    // révélation par contenu visible en solo, et c'est la mécanique la plus
    // difficile à comprendre sans la voir.
    if (!answerFor(state, promptId, PARTNER)) {
      answers = [...answers, partnerAnswer(prompt, mine, state.prompts.indexOf(prompt))];
    }
    await write({ ...state, answers });
    return mine;
  },

  async toggleReaction(answerId, emoji) {
    const state = await read();
    const answers = state.answers.map((a) =>
      a.id === answerId
        ? {
            ...a,
            reactions: a.reactions.includes(emoji)
              ? a.reactions.filter((e) => e !== emoji)
              : [...a.reactions, emoji],
          }
        : a,
    );
    await write({ ...state, answers });
  },

  async getHistory() {
    const state = await read();
    if (!state.link) return [];
    const today = localDate();
    const dates = [...new Set(state.prompts.filter((p) => p.date < today).map((p) => p.date))].sort(
      (x, y) => (x < y ? 1 : -1),
    );
    return dates.map<HistoryEntry>((date) => ({
      date,
      items: sortByKind(state.prompts.filter((p) => p.date === date)).map((p) => itemState(state, p)),
    }));
  },

  async getStreak() {
    const state = await read();
    if (!state.link) return 0;
    // Aligné sur link_streak: AU MOINS un contenu répondu des deux côtés.
    const completed = new Set(
      state.prompts
        .filter((p) => answerFor(state, p.id, ME) && answerFor(state, p.id, PARTNER))
        .map((p) => p.date),
    );
    let streak = 0;
    for (let i = 0; i < 400; i++) {
      const date = daysAgo(i);
      if (completed.has(date)) streak++;
      else if (i > 0) break;
    }
    return streak;
  },
};
