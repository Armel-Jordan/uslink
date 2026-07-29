import AsyncStorage from '@react-native-async-storage/async-storage';

import { pickLibraryPrompt } from '@/lib/prompt-library';
import type { Answer, DailyPrompt, HistoryEntry, Link, LinkMode, Profile, Session, TodayState } from '@/lib/types';

import { DataError, localDate, type DataAdapter } from './adapter';

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

function daysAgo(n: number) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return localDate(d);
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

function ensurePrompt(state: DemoState, link: Link, date: string): DailyPrompt {
  const existing = state.prompts.find((p) => p.date === date);
  if (existing) return existing;
  const picked = pickLibraryPrompt(link.mode, link.id, date);
  const prompt: DailyPrompt = {
    id: id('prompt'),
    date,
    question: picked.question,
    category: picked.category,
    source: 'library',
  };
  state.prompts = [...state.prompts, prompt];
  return prompt;
}

/** Give a new demo link three days of history so Souvenirs isn't empty. */
function seedHistory(state: DemoState, link: Link) {
  if (state.seeded) return;
  const mineSamples = [
    "Ce moment où on n'a rien dit pendant dix minutes et c'était très bien comme ça.",
    "J'ai besoin qu'on planifie moins et qu'on improvise plus, je crois.",
    "Je suis fier de nous pour la façon dont on a géré la semaine dernière.",
  ];
  [3, 2, 1].forEach((n, i) => {
    const date = daysAgo(n);
    const prompt = ensurePrompt(state, link, date);
    state.answers = [
      ...state.answers,
      {
        id: id('ans'),
        promptId: prompt.id,
        authorId: ME,
        body: mineSamples[i],
        createdAt: new Date().toISOString(),
        reactions: [],
      },
      {
        id: id('ans'),
        promptId: prompt.id,
        authorId: PARTNER,
        body: PARTNER_REPLIES[i % PARTNER_REPLIES.length],
        createdAt: new Date().toISOString(),
        reactions: i === 0 ? ['❤️'] : [],
      },
    ];
  });
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
    return (await read()).link;
  },

  async createLink(mode) {
    const state = await read();
    requireSession(state);
    // In demo the partner joins immediately — otherwise there is nothing to reveal.
    const link: Link = {
      id: id('link'),
      mode,
      createdAt: new Date().toISOString(),
      partner: PARTNER_PROFILE,
      inviteCode: code(),
    };
    const next = { ...state, link };
    seedHistory(next, link);
    await write(next);
    return link;
  },

  async joinLink(input) {
    const state = await read();
    requireSession(state);
    if (input.trim().length !== 6) throw new DataError('invalid_code', 'Code invalide.');
    const link: Link = {
      id: id('link'),
      mode: 'couple',
      createdAt: new Date().toISOString(),
      partner: PARTNER_PROFILE,
      inviteCode: input.trim().toUpperCase(),
    };
    const next = { ...state, link };
    seedHistory(next, link);
    await write(next);
    return link;
  },

  async leaveLink() {
    const state = await read();
    await write({ ...state, link: null, prompts: [], answers: [], seeded: false });
  },

  async getToday() {
    const state = await read();
    requireSession(state);
    if (!state.link) return null;
    const date = localDate();
    const prompt = ensurePrompt(state, state.link, date);
    await write(state);
    const mine = answerFor(state, prompt.id, ME);
    const theirs = answerFor(state, prompt.id, PARTNER);
    return { prompt, mine, theirs, revealed: Boolean(mine && theirs) };
  },

  async submitAnswer(promptId, body) {
    const state = await read();
    requireSession(state);
    requireLink(state);
    const existing = answerFor(state, promptId, ME);
    const mine: Answer = existing
      ? { ...existing, body }
      : {
          id: id('ans'),
          promptId,
          authorId: ME,
          body,
          createdAt: new Date().toISOString(),
          reactions: [],
        };
    let answers = existing
      ? state.answers.map((a) => (a.id === existing.id ? mine : a))
      : [...state.answers, mine];

    // Scripted partner reply so the reveal can be experienced solo.
    if (!answerFor(state, promptId, PARTNER)) {
      const index = state.prompts.findIndex((p) => p.id === promptId);
      answers = [
        ...answers,
        {
          id: id('ans'),
          promptId,
          authorId: PARTNER,
          body: PARTNER_REPLIES[(index + 1) % PARTNER_REPLIES.length],
          createdAt: new Date().toISOString(),
          reactions: [],
        },
      ];
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
    return state.prompts
      .filter((p) => p.date < today)
      .sort((a, b) => (a.date < b.date ? 1 : -1))
      .map<HistoryEntry>((prompt) => ({
        prompt,
        mine: answerFor(state, prompt.id, ME),
        theirs: answerFor(state, prompt.id, PARTNER),
      }));
  },

  async getStreak() {
    const state = await read();
    if (!state.link) return 0;
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
