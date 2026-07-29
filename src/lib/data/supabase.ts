import { ITEM_KINDS, pickLibraryDay } from '@/lib/prompt-library';
import { FALLBACK_LOCALE, LOCALES, locale as appLocale, t, type Locale } from '@/lib/strings';
import { requireSupabase } from '@/lib/supabase';
import { GOALS, INTERESTS } from '@/lib/types';
import type {
  Answer,
  Goal,
  Interest,
  DailyPrompt,
  HistoryEntry,
  ItemKind,
  ItemState,
  Link,
  LinkMode,
  Onboarding,
  Profile,
  Session,
  Stance,
  TodayState,
} from '@/lib/types';

import { DataError, deviceTimeZone, type DataAdapter, type DataErrorCode } from './adapter';

type AnswerRow = {
  id: string;
  prompt_id: string;
  author_id: string;
  kind: string;
  body: string | null;
  stance: number | null;
  done: boolean | null;
  created_at: string;
  reactions?: { emoji: string }[] | null;
};

type PromptRow = {
  id: string;
  prompt_date: string;
  kind: string;
  question: string;
  category: string;
  options: Record<string, unknown> | null;
  source: string;
  answers?: AnswerRow[] | null;
};

type MyLinkRow = {
  link_id: string;
  mode: string;
  created_at: string;
  invite_code: string | null;
  time_zone: string;
  day_start_hour: number;
  today: string;
  locale: string;
  started_on: string | null;
  days_together: number | null;
  partner_started_on: string | null;
  partner_id: string | null;
  partner_name: string | null;
  partner_emoji: string | null;
};

const ITEM_COLUMNS = 'id, prompt_date, kind, question, category, options, source';
const ANSWER_COLUMNS = 'id, prompt_id, author_id, kind, body, stance, done, created_at, reactions(emoji)';
const PROMPT_SELECT = `${ITEM_COLUMNS}, answers(${ANSWER_COLUMNS})`;

function toKind(value: string): ItemKind {
  return value === 'debate' || value === 'challenge' ? value : 'question';
}

/** Le jsonb est fermé côté base ; on le referme côté client au même endroit. */
function toOptions(kind: ItemKind, raw: Record<string, unknown> | null): DailyPrompt['options'] {
  if (kind === 'debate' && raw && typeof raw.low === 'string' && typeof raw.high === 'string') {
    return { low: raw.low, high: raw.high };
  }
  if (kind === 'challenge' && raw && typeof raw.duration_min === 'number') {
    return { durationMin: raw.duration_min };
  }
  return null;
}

function toPrompt(row: PromptRow): DailyPrompt {
  const kind = toKind(row.kind);
  return {
    id: row.id,
    date: row.prompt_date,
    kind,
    question: row.question,
    category: row.category,
    options: toOptions(kind, row.options),
    source: row.source === 'ai' ? 'ai' : 'library',
  };
}

function toAnswer(row: AnswerRow): Answer {
  return {
    id: row.id,
    promptId: row.prompt_id,
    authorId: row.author_id,
    kind: toKind(row.kind),
    body: row.body,
    stance: row.stance === null ? null : (Math.min(5, Math.max(1, row.stance)) as Stance),
    done: row.done,
    createdAt: row.created_at,
    reactions: (row.reactions ?? []).map((r) => r.emoji),
  };
}

/** Assemble un contenu et les réponses visibles. La RLS a déjà filtré. */
function toItemState(prompt: DailyPrompt, answers: Answer[], userId: string): ItemState {
  const mine = answers.find((a) => a.authorId === userId) ?? null;
  const theirs = answers.find((a) => a.authorId !== userId) ?? null;
  return { prompt, mine, theirs, revealed: Boolean(mine && theirs) };
}

function toLink(row: MyLinkRow): Link {
  return {
    id: row.link_id,
    mode: (['couple', 'friends', 'random'] as LinkMode[]).includes(row.mode as LinkMode)
      ? (row.mode as LinkMode)
      : 'couple',
    createdAt: row.created_at,
    inviteCode: row.invite_code,
    timeZone: row.time_zone,
    today: row.today,
    dayStartHour: row.day_start_hour,
    locale: (LOCALES as string[]).includes(row.locale) ? (row.locale as Locale) : FALLBACK_LOCALE,
    startedOn: row.started_on,
    daysTogether: row.days_together,
    partnerStartedOn: row.partner_started_on,
    partner:
      row.partner_id && row.partner_name
        ? {
            id: row.partner_id,
            displayName: row.partner_name,
            avatarEmoji: row.partner_emoji || '🌙',
          }
        : null,
  };
}

/** `join_link`, `leave_link` and `regenerate_invite` raise these as Postgres exception messages. */
function toDataError(message: string): DataError {
  const known: DataErrorCode[] = [
    'invalid_code',
    'own_code',
    'link_full',
    'already_linked',
    'no_link',
    'invalid_time_zone',
    'time_zone_cooldown',
    'invalid_locale',
    'invalid_date',
    'auth',
  ];
  const hit = known.find((code) => message.includes(code));
  return hit ? new DataError(hit, message) : new DataError('unknown', message);
}

async function currentUserId(): Promise<string> {
  const { data } = await requireSupabase().auth.getUser();
  if (!data.user) throw new DataError('auth', 'Utilisateur non connecté.');
  return data.user.id;
}

export const supabaseAdapter: DataAdapter = {
  isDemo: false,

  async getSession() {
    const { data } = await requireSupabase().auth.getSession();
    if (!data.session) return null;
    return { userId: data.session.user.id, email: data.session.user.email ?? null };
  },

  onSessionChange(listener) {
    const { data } = requireSupabase().auth.onAuthStateChange((_event, session) => {
      listener(session ? { userId: session.user.id, email: session.user.email ?? null } : null);
    });
    return () => data.subscription.unsubscribe();
  },

  async signIn(email, password) {
    const { error } = await requireSupabase().auth.signInWithPassword({ email, password });
    if (error) throw new DataError('auth', error.message);
  },

  async signUp(email, password, displayName) {
    const { data, error } = await requireSupabase().auth.signUp({
      email,
      password,
      options: { data: { display_name: displayName } },
    });
    if (error) throw new DataError('auth', error.message);
    return { needsConfirmation: !data.session };
  },

  async signOut() {
    await requireSupabase().auth.signOut();
  },

  async getOnboarding() {
    const supabase = requireSupabase();
    const userId = await currentUserId();
    const { data, error } = await supabase
      .from('profile_onboarding')
      .select('birth_date, city, interests, goals, relationship_started_on, completed_at')
      .eq('id', userId)
      .maybeSingle();
    if (error) throw new DataError('unknown', error.message);
    return {
      birthDate: data?.birth_date ?? null,
      city: data?.city ?? null,
      // On referme les listes ici aussi : la base les contraint, mais rien
      // n'oblige une ligne écrite avant une évolution à s'y conformer.
      interests: ((data?.interests ?? []) as string[]).filter((x): x is Interest =>
        (INTERESTS as readonly string[]).includes(x),
      ),
      goals: ((data?.goals ?? []) as string[]).filter((x): x is Goal =>
        (GOALS as readonly string[]).includes(x),
      ),
      relationshipStartedOn: data?.relationship_started_on ?? null,
      completed: Boolean(data?.completed_at),
    };
  },

  async saveOnboarding(patch) {
    const supabase = requireSupabase();
    const userId = await currentUserId();
    const { error } = await supabase.from('profile_onboarding').upsert(
      {
        id: userId,
        ...(patch.birthDate !== undefined ? { birth_date: patch.birthDate } : {}),
        ...(patch.city !== undefined ? { city: patch.city } : {}),
        ...(patch.interests !== undefined ? { interests: patch.interests } : {}),
        ...(patch.goals !== undefined ? { goals: patch.goals } : {}),
        ...(patch.relationshipStartedOn !== undefined
          ? { relationship_started_on: patch.relationshipStartedOn }
          : {}),
        ...(patch.completed ? { completed_at: new Date().toISOString() } : {}),
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'id' },
    );
    if (error) throw new DataError('unknown', error.message);

    // La date de naissance est le seul champ volontairement partagé : le
    // partenaire en a besoin pour le rappel d'anniversaire.
    if (patch.birthDate !== undefined) {
      const { error: profileError } = await supabase
        .from('profiles')
        .update({ birth_date: patch.birthDate })
        .eq('id', userId);
      if (profileError) throw new DataError('unknown', profileError.message);
    }
    return supabaseAdapter.getOnboarding();
  },

  async setStartedOn(date) {
    const { error } = await requireSupabase().rpc('set_link_started_on', { p_date: date });
    if (error) throw toDataError(error.message);
    const link = await supabaseAdapter.getLink();
    if (!link) throw new DataError('no_link', t.profile.noLink);
    return link;
  },

  async getProfile() {
    const supabase = requireSupabase();
    const userId = await currentUserId();
    const { data, error } = await supabase
      .from('profiles')
      .select('id, display_name, avatar_emoji')
      .eq('id', userId)
      .maybeSingle();
    if (error) throw new DataError('unknown', error.message);
    if (data) {
      return { id: data.id, displayName: data.display_name, avatarEmoji: data.avatar_emoji || '☀️' };
    }
    // The signup trigger normally creates this row; heal it if it is missing.
    const fallback = { id: userId, display_name: 'Moi', avatar_emoji: '☀️' };
    const { error: upsertError } = await supabase.from('profiles').upsert(fallback);
    if (upsertError) throw new DataError('unknown', upsertError.message);
    return { id: userId, displayName: fallback.display_name, avatarEmoji: fallback.avatar_emoji };
  },

  async updateProfile(patch) {
    const supabase = requireSupabase();
    const userId = await currentUserId();
    const { data, error } = await supabase
      .from('profiles')
      .update({
        ...(patch.displayName !== undefined ? { display_name: patch.displayName } : {}),
        ...(patch.avatarEmoji !== undefined ? { avatar_emoji: patch.avatarEmoji } : {}),
      })
      .eq('id', userId)
      .select('id, display_name, avatar_emoji')
      .single();
    if (error) throw new DataError('unknown', error.message);
    return { id: data.id, displayName: data.display_name, avatarEmoji: data.avatar_emoji || '☀️' };
  },

  async getLink() {
    const { data, error } = await requireSupabase().rpc('my_link');
    if (error) throw new DataError('unknown', error.message);
    const rows = (data ?? []) as MyLinkRow[];
    return rows.length ? toLink(rows[0]) : null;
  },

  async createLink(mode) {
    // Le fuseau de l'appareil n'est proposé qu'ici : ensuite c'est le lien qui
    // porte l'horloge, et il ne bouge que sur action explicite.
    const { error } = await requireSupabase().rpc('create_link', {
      p_mode: mode,
      p_time_zone: deviceTimeZone(),
      p_locale: appLocale,
    });
    if (error) throw toDataError(error.message);
    const link = await supabaseAdapter.getLink();
    if (!link) throw new DataError('unknown', 'Lien créé mais introuvable.');
    return link;
  },

  async joinLink(code) {
    const { error } = await requireSupabase().rpc('join_link', {
      p_code: code.trim().toUpperCase(),
    });
    if (error) throw toDataError(error.message);
    const link = await supabaseAdapter.getLink();
    if (!link) throw new DataError('unknown', 'Lien rejoint mais introuvable.');
    return link;
  },

  async regenerateInvite() {
    const { data, error } = await requireSupabase().rpc('regenerate_invite');
    if (error) throw toDataError(error.message);
    if (typeof data !== 'string') throw new DataError('unknown', 'Code non généré.');
    return data;
  },

  async setTimeZone(timeZone) {
    const { error } = await requireSupabase().rpc('set_link_time_zone', { p_time_zone: timeZone });
    if (error) throw toDataError(error.message);
    const link = await supabaseAdapter.getLink();
    if (!link) throw new DataError('no_link', t.profile.noLink);
    return link;
  },

  async setLocale(next) {
    const { error } = await requireSupabase().rpc('set_link_locale', { p_locale: next });
    if (error) throw toDataError(error.message);
    const link = await supabaseAdapter.getLink();
    if (!link) throw new DataError('no_link', t.profile.noLink);
    return link;
  },

  async leaveLink() {
    // Passe par la RPC : elle seule purge les invites (sinon le code rouvre un
    // lien redevenu à un membre) et supprime un lien devenu vide.
    const { error } = await requireSupabase().rpc('leave_link');
    if (error) throw toDataError(error.message);
  },

  async getToday() {
    const supabase = requireSupabase();
    const link = await supabaseAdapter.getLink();
    if (!link) return null;
    const userId = await currentUserId();
    // Le jour vient du serveur, dérivé du fuseau du lien. Le calculer ici avec
    // `new Date()` rendrait les deux appareils désaccordés.
    const date = link.today;

    let prompts = await fetchDay(link.id, date);
    if (prompts.length < ITEM_KINDS.length) {
      prompts = await openDay(link, date, prompts);
    }

    const { data, error } = await supabase
      .from('answers')
      .select(ANSWER_COLUMNS)
      .in('prompt_id', prompts.map((p) => p.id));
    if (error) throw new DataError('unknown', error.message);
    const answers = ((data ?? []) as AnswerRow[]).map(toAnswer);

    return {
      date,
      items: sortByKind(prompts).map((prompt) =>
        toItemState(prompt, answers.filter((a) => a.promptId === prompt.id), userId),
      ),
    };
  },

  async submitAnswer(promptId, input) {
    const supabase = requireSupabase();
    const userId = await currentUserId();
    // La forme est décidée par le type : le CHECK answers_shape refuse toute
    // combinaison impossible, et l'union AnswerInput l'interdit déjà ici.
    // Type uniforme et non union : PostgREST n'infère pas sur une union, et
    // c'est `answers_shape` en base qui reste l'autorité sur la forme.
    const row: {
      prompt_id: string;
      author_id: string;
      kind: ItemKind;
      body: string | null;
      stance: number | null;
      done: boolean | null;
    } =
      input.kind === 'challenge'
        ? { prompt_id: promptId, author_id: userId, kind: input.kind, done: input.done, body: null, stance: null }
        : input.kind === 'debate'
          ? { prompt_id: promptId, author_id: userId, kind: input.kind, body: input.body, stance: input.stance, done: null }
          : { prompt_id: promptId, author_id: userId, kind: input.kind, body: input.body, stance: null, done: null };

    const { data, error } = await supabase
      .from('answers')
      // Pas d'`updated_at` : le défaut de colonne le pose à l'insertion et le
      // trigger answers_touch_updated_at à la mise à jour. L'envoyer depuis le
      // client laisserait écrire un horodatage arbitraire.
      .upsert(row, { onConflict: 'prompt_id,author_id' })
      .select('id, prompt_id, author_id, kind, body, stance, done, created_at')
      .single();
    if (error) throw new DataError('unknown', error.message);
    return toAnswer(data as AnswerRow);
  },

  async toggleReaction(answerId, emoji) {
    const supabase = requireSupabase();
    const userId = await currentUserId();
    const { data, error } = await supabase
      .from('reactions')
      .select('id')
      .eq('answer_id', answerId)
      .eq('user_id', userId)
      .eq('emoji', emoji)
      .maybeSingle();
    if (error) throw new DataError('unknown', error.message);
    if (data) {
      const { error: delError } = await supabase.from('reactions').delete().eq('id', data.id);
      if (delError) throw new DataError('unknown', delError.message);
      return;
    }
    const { error: insError } = await supabase
      .from('reactions')
      .insert({ answer_id: answerId, user_id: userId, emoji });
    if (insError) throw new DataError('unknown', insError.message);
  },

  async getHistory() {
    const supabase = requireSupabase();
    const link = await supabaseAdapter.getLink();
    if (!link) return [];
    const userId = await currentUserId();
    const { data, error } = await supabase
      .from('daily_prompts')
      .select(PROMPT_SELECT)
      .eq('link_id', link.id)
      .lt('prompt_date', link.today)
      .is('bundle', null)
      .order('prompt_date', { ascending: false })
      .limit(180);
    if (error) throw new DataError('unknown', error.message);

    // Groupé par jour : une journée est l'unité de souvenir, pas un contenu.
    const days = new Map<string, ItemState[]>();
    for (const row of (data ?? []) as PromptRow[]) {
      const prompt = toPrompt(row);
      const answers = (row.answers ?? []).map(toAnswer);
      const list = days.get(prompt.date) ?? [];
      list.push(toItemState(prompt, answers, userId));
      days.set(prompt.date, list);
    }
    return [...days.entries()].map<HistoryEntry>(([date, items]) => ({ date, items: sortByKind2(items) }));
  },

  async getStreak() {
    const link = await supabaseAdapter.getLink();
    if (!link) return 0;
    const { data, error } = await requireSupabase().rpc('link_streak', { p_link_id: link.id });
    if (error) throw new DataError('unknown', error.message);
    return typeof data === 'number' ? data : 0;
  },
};

/**
 * Doit rester AU-DESSUS du budget serveur (`timeout` × `maxRetries` du SDK
 * Anthropic dans supabase/functions/daily-prompt), sans quoi le client écrit
 * ses contenus de bibliothèque en premier et l'écriture `do nothing` de la
 * fonction devient un no-op : l'IA perdrait la course tous les jours.
 */
const EDGE_TIMEOUT_MS = 20_000;

const KIND_ORDER: Record<ItemKind, number> = { debate: 0, question: 1, challenge: 2 };

/** Débat, puis question, puis défi : on débat, on répond, on relève le soir. */
function sortByKind(prompts: DailyPrompt[]): DailyPrompt[] {
  return [...prompts].sort((a, b) => KIND_ORDER[a.kind] - KIND_ORDER[b.kind]);
}

function sortByKind2(items: ItemState[]): ItemState[] {
  return [...items].sort((a, b) => KIND_ORDER[a.prompt.kind] - KIND_ORDER[b.prompt.kind]);
}

async function fetchDay(linkId: string, date: string): Promise<DailyPrompt[]> {
  const { data, error } = await requireSupabase()
    .from('daily_prompts')
    .select(ITEM_COLUMNS)
    .eq('link_id', linkId)
    .eq('prompt_date', date)
    .is('bundle', null);
  if (error) throw new DataError('unknown', error.message);
  return ((data ?? []) as PromptRow[]).map(toPrompt);
}

/**
 * Ouvre la journée : demande les contenus personnalisés à l'Edge Function, et
 * complète depuis la banque locale ce qui manque encore. Écrit toujours en
 * `on conflict do nothing` — daily_prompts n'a pas de policy UPDATE, et le
 * premier arrivé doit gagner pour que le texte ne change pas sous les yeux de
 * quelqu'un qui a déjà répondu.
 */
async function openDay(link: Link, date: string, existing: DailyPrompt[]): Promise<DailyPrompt[]> {
  const supabase = requireSupabase();
  let invoked = false;
  try {
    const { data, error } = await supabase.functions.invoke('daily-prompt', {
      body: { linkId: link.id },
      timeout: EDGE_TIMEOUT_MS,
    });
    invoked = !error && Boolean(data?.items);
  } catch {
    // on complète depuis la banque locale
  }

  const after = invoked ? await fetchDay(link.id, date) : existing;
  const manquants = ITEM_KINDS.filter((kind) => !after.some((p) => p.kind === kind));
  if (manquants.length === 0) return after;

  const picked = pickLibraryDay(link.mode, link.id, date, link.locale);
  const rows = picked
    .filter(({ kind }) => manquants.includes(kind))
    .map(({ kind, item }) => ({
      link_id: link.id,
      prompt_date: date,
      kind,
      question: item.question,
      category: item.category,
      options:
        kind === 'debate' && item.options && 'low' in item.options
          ? { low: item.options.low, high: item.options.high }
          : kind === 'challenge' && item.options && 'durationMin' in item.options
            ? { duration_min: item.options.durationMin }
            : {},
      source: 'library' as const,
    }));

  const { error } = await supabase
    .from('daily_prompts')
    .upsert(rows, { onConflict: 'link_id,prompt_date,kind', ignoreDuplicates: true });
  if (error) throw new DataError('unknown', error.message);

  const final = await fetchDay(link.id, date);
  if (final.length === 0) throw new DataError('no_prompt', t.common.noPrompt);
  return final;
}
