import { pickLibraryPrompt } from '@/lib/prompt-library';
import { t } from '@/lib/strings';
import { requireSupabase } from '@/lib/supabase';
import type { Answer, DailyPrompt, HistoryEntry, Link, LinkMode, Profile, Session, TodayState } from '@/lib/types';

import { DataError, deviceTimeZone, type DataAdapter, type DataErrorCode } from './adapter';

type AnswerRow = {
  id: string;
  prompt_id: string;
  author_id: string;
  body: string;
  created_at: string;
  reactions?: { emoji: string }[] | null;
};

type PromptRow = {
  id: string;
  prompt_date: string;
  question: string;
  category: string;
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
  partner_id: string | null;
  partner_name: string | null;
  partner_emoji: string | null;
};

const PROMPT_SELECT =
  'id, prompt_date, question, category, source, answers(id, prompt_id, author_id, body, created_at, reactions(emoji))';

function toPrompt(row: PromptRow): DailyPrompt {
  return {
    id: row.id,
    date: row.prompt_date,
    question: row.question,
    category: row.category,
    source: row.source === 'ai' ? 'ai' : 'library',
  };
}

function toAnswer(row: AnswerRow): Answer {
  return {
    id: row.id,
    promptId: row.prompt_id,
    authorId: row.author_id,
    body: row.body,
    createdAt: row.created_at,
    reactions: (row.reactions ?? []).map((r) => r.emoji),
  };
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

    let prompt = await fetchPrompt(link.id, date);
    if (!prompt) {
      prompt = await generatePrompt(link, date);
    }

    const { data, error } = await supabase
      .from('answers')
      .select('id, prompt_id, author_id, body, created_at, reactions(emoji)')
      .eq('prompt_id', prompt.id);
    if (error) throw new DataError('unknown', error.message);

    const answers = ((data ?? []) as AnswerRow[]).map(toAnswer);
    const mine = answers.find((a) => a.authorId === userId) ?? null;
    const theirs = answers.find((a) => a.authorId !== userId) ?? null;
    return { prompt, mine, theirs, revealed: Boolean(mine && theirs) };
  },

  async submitAnswer(promptId, body) {
    const supabase = requireSupabase();
    const userId = await currentUserId();
    const { data, error } = await supabase
      .from('answers')
      // Pas d'`updated_at` : le défaut de colonne le pose à l'insertion et le
      // trigger answers_touch_updated_at à la mise à jour. L'envoyer depuis le
      // client laisserait écrire un horodatage arbitraire.
      .upsert({ prompt_id: promptId, author_id: userId, body }, { onConflict: 'prompt_id,author_id' })
      .select('id, prompt_id, author_id, body, created_at')
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
      .order('prompt_date', { ascending: false })
      .limit(60);
    if (error) throw new DataError('unknown', error.message);

    return ((data ?? []) as PromptRow[]).map<HistoryEntry>((row) => {
      const answers = (row.answers ?? []).map(toAnswer);
      return {
        prompt: toPrompt(row),
        mine: answers.find((a) => a.authorId === userId) ?? null,
        theirs: answers.find((a) => a.authorId !== userId) ?? null,
      };
    });
  },

  async getStreak() {
    const link = await supabaseAdapter.getLink();
    if (!link) return 0;
    const { data, error } = await requireSupabase().rpc('link_streak', { p_link_id: link.id });
    if (error) throw new DataError('unknown', error.message);
    return typeof data === 'number' ? data : 0;
  },
};

async function fetchPrompt(linkId: string, date: string): Promise<DailyPrompt | null> {
  const { data, error } = await requireSupabase()
    .from('daily_prompts')
    .select('id, prompt_date, question, category, source')
    .eq('link_id', linkId)
    .eq('prompt_date', date)
    .maybeSingle();
  if (error) throw new DataError('unknown', error.message);
  return data ? toPrompt(data as PromptRow) : null;
}

/**
 * Doit rester AU-DESSUS du budget serveur (`timeout` x `maxRetries` du SDK
 * Anthropic dans supabase/functions/daily-prompt), sans quoi le client écrit sa
 * question de bibliothèque en premier et l'écriture `do nothing` de la fonction
 * devient un no-op : l'IA perdrait la course tous les jours, en silence.
 */
const EDGE_TIMEOUT_MS = 20_000;

/**
 * Ask the Edge Function for an AI-personalised question. If it is not deployed
 * or Claude is unavailable, fall back to the local library so the daily ritual
 * never breaks — the user only sees a different `source` badge.
 */
async function generatePrompt(link: Link, date: string): Promise<DailyPrompt> {
  const supabase = requireSupabase();
  // `invoke` ne lève pas : un timeout revient en `{ error }`. Le catch ne couvre
  // donc que l'imprévu, et surtout pas `fetchPrompt`, dont l'erreur doit remonter.
  let invoked = false;
  try {
    // Pas de `date` dans le corps : la fonction la dérive elle-même du fuseau
    // du lien. Une date choisie par le client rate le cache à chaque nouvelle
    // valeur et facture un appel Anthropic pour chacune.
    const { data, error } = await supabase.functions.invoke('daily-prompt', {
      body: { linkId: link.id },
      timeout: EDGE_TIMEOUT_MS,
    });
    invoked = !error && Boolean(data?.prompt);
  } catch {
    // fall through to the library
  }
  if (invoked) {
    const fresh = await fetchPrompt(link.id, date);
    if (fresh) return fresh;
  }

  // `on conflict do nothing` et non un UPDATE : daily_prompts n'a pas de policy
  // UPDATE, donc un upsert en conflit échouerait en 42501 — c'est le seul
  // chemin qui laissait réellement une journée sans question. Premier arrivé
  // gagne, et on relit ce qui est en base plutôt que ce qu'on voulait écrire.
  const picked = pickLibraryPrompt(link.mode, link.id, date);
  const { error } = await supabase.from('daily_prompts').upsert(
    {
      link_id: link.id,
      prompt_date: date,
      question: picked.question,
      category: picked.category,
      source: 'library',
    },
    { onConflict: 'link_id,prompt_date', ignoreDuplicates: true },
  );
  if (error) throw new DataError('unknown', error.message);

  const stored = await fetchPrompt(link.id, date);
  if (!stored) throw new DataError('no_prompt', t.common.noPrompt);
  return stored;
}
