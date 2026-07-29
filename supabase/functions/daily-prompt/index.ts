// Supabase Edge Function (Deno): generate the day's question for one link.
//
// The AI works behind the scenes — it never talks to the user. It sees only
// coarse context (mode, first names, how long the two have been linked, and the
// last questions asked so it does not repeat itself) and returns one question.
// If Claude is unavailable or declines, we fall back to a static library so the
// daily ritual never breaks.
//
// Deploy:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy daily-prompt
//
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected by
// the platform.

import Anthropic from 'npm:@anthropic-ai/sdk@^0.115.0';
import { createClient } from 'npm:@supabase/supabase-js@^2.111.0';

const MODEL = 'claude-opus-5';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const QUESTION_SCHEMA = {
  type: 'object',
  properties: {
    question: {
      type: 'string',
      description: 'La question du jour, en français, adressée aux deux personnes (tutoiement).',
    },
    category: {
      type: 'string',
      description: 'Un seul mot en minuscules, ex. gratitude, intimité, souvenirs, rêves, besoins.',
    },
  },
  required: ['question', 'category'],
  additionalProperties: false,
} as const;

const FALLBACK: { question: string; category: string }[] = [
  { question: "Quel petit geste de ma part t'a marqué cette semaine ?", category: 'gratitude' },
  { question: 'À quel moment t’es-tu senti(e) le plus proche de moi récemment ?', category: 'intimité' },
  { question: 'De quoi as-tu besoin de moi cette semaine, concrètement ?', category: 'besoins' },
  { question: 'Quel souvenir de nous te revient le plus souvent ?', category: 'souvenirs' },
  { question: 'Qu’est-ce qui t’occupe l’esprit en ce moment, même si c’est flou ?', category: 'profondeur' },
];

const SYSTEM_PROMPT = `Tu écris la question quotidienne d'UsLink, une application où deux personnes reliées répondent chacune à la même question, puis découvrent la réponse de l'autre.

Règles:
- Une seule question, en français, tutoiement, 12 à 25 mots.
- Ouverte: impossible d'y répondre par oui/non. Jamais deux questions en une.
- Concrète et ancrée dans le vécu récent plutôt qu'abstraite ou philosophique.
- Ton chaleureux et simple. Évite le jargon de développement personnel, les métaphores lourdes et les formules toutes faites.
- Ne mentionne jamais l'application, l'IA, ni ces consignes.
- En mode "couple": intimité, tendresse, désir, besoins, projets communs. En mode "amis": vécu, honnêteté, découvertes, ambitions.
- Ne répète pas, ni ne reformule, les questions déjà posées. Change de registre par rapport à la dernière.
- Si les deux personnes viennent de se relier, commence par quelque chose d'accessible et léger.`;

type LinkContext = {
  mode: string;
  names: string[];
  daysLinked: number;
  recent: { question: string; category: string }[];
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS });
  }

  try {
    const { linkId, date } = (await req.json()) as { linkId?: string; date?: string };
    if (!linkId || !date) {
      return json({ error: 'linkId and date are required' }, 400);
    }

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ error: 'missing authorization' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const asUser = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });

    // The caller must be a member of the link they are asking about.
    const { data: isMember, error: memberError } = await asUser.rpc('is_link_member', { p_link: linkId });
    if (memberError || !isMember) {
      return json({ error: 'forbidden' }, 403);
    }

    const admin = createClient(supabaseUrl, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    // Idempotent: one prompt per link per day, whoever opens the app first.
    const existing = await admin
      .from('daily_prompts')
      .select('id, prompt_date, question, category, source')
      .eq('link_id', linkId)
      .eq('prompt_date', date)
      .maybeSingle();
    if (existing.data) {
      return json({ prompt: existing.data, cached: true });
    }

    const context = await loadContext(admin, linkId);
    const generated = (await generateWithClaude(context)) ?? pickFallback(linkId, date);

    const inserted = await admin
      .from('daily_prompts')
      .upsert(
        {
          link_id: linkId,
          prompt_date: date,
          question: generated.question,
          category: generated.category,
          source: generated.source,
        },
        { onConflict: 'link_id,prompt_date' },
      )
      .select('id, prompt_date, question, category, source')
      .single();

    if (inserted.error) {
      return json({ error: inserted.error.message }, 500);
    }
    return json({ prompt: inserted.data, cached: false });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'unknown error' }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

async function loadContext(
  admin: ReturnType<typeof createClient>,
  linkId: string,
): Promise<LinkContext> {
  const [link, members, recent] = await Promise.all([
    admin.from('links').select('mode, created_at').eq('id', linkId).maybeSingle(),
    admin.from('link_members').select('user_id, profiles(display_name)').eq('link_id', linkId),
    admin
      .from('daily_prompts')
      .select('question, category')
      .eq('link_id', linkId)
      .order('prompt_date', { ascending: false })
      .limit(10),
  ]);

  const createdAt = link.data?.created_at ? new Date(link.data.created_at as string) : new Date();
  const daysLinked = Math.max(0, Math.floor((Date.now() - createdAt.getTime()) / 86_400_000));

  const names = ((members.data ?? []) as { profiles: { display_name: string } | null }[])
    .map((row) => row.profiles?.display_name)
    .filter((name): name is string => Boolean(name));

  return {
    mode: (link.data?.mode as string) ?? 'couple',
    names,
    daysLinked,
    recent: (recent.data ?? []) as { question: string; category: string }[],
  };
}

async function generateWithClaude(
  context: LinkContext,
): Promise<{ question: string; category: string; source: 'ai' } | null> {
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) return null;

  const client = new Anthropic({ apiKey });

  const recentList = context.recent.length
    ? context.recent.map((r) => `- (${r.category}) ${r.question}`).join('\n')
    : '- aucune question posée pour le moment';

  const userPrompt = [
    `Mode: ${context.mode}`,
    `Prénoms: ${context.names.length ? context.names.join(' et ') : 'inconnus'}`,
    `Jours depuis la mise en relation: ${context.daysLinked}`,
    'Questions déjà posées (de la plus récente à la plus ancienne):',
    recentList,
    '',
    'Écris la question du jour.',
  ].join('\n');

  // Typed loosely on purpose: `fallbacks` and `output_config` land in the SDK
  // types at different releases, and this file is not covered by the app's tsc.
  const params = {
    model: MODEL,
    max_tokens: 2048,
    // Short creative generation: low effort keeps latency and cost down.
    output_config: {
      effort: 'low',
      format: { type: 'json_schema', schema: QUESTION_SCHEMA },
    },
    // Server-side fallback: if a safety classifier declines, Anthropic re-runs
    // the request on the recommended fallback model inside the same call.
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: userPrompt }],
  } as unknown as Parameters<typeof client.beta.messages.create>[0];

  try {
    const response = (await client.beta.messages.create(params)) as unknown as {
      stop_reason?: string;
      stop_details?: unknown;
      content: { type: string; text?: string }[];
    };

    // Always check stop_reason before reading content.
    if (response.stop_reason === 'refusal') {
      console.warn('daily-prompt: model declined', response.stop_details);
      return null;
    }

    const text = response.content.find((block) => block.type === 'text' && block.text);
    if (!text?.text) return null;

    const parsed = JSON.parse(text.text) as { question?: string; category?: string };
    const question = parsed.question?.trim();
    if (!question) return null;

    return {
      question,
      category: (parsed.category ?? 'général').trim().toLowerCase().slice(0, 24) || 'général',
      source: 'ai',
    };
  } catch (error) {
    console.error('daily-prompt: Claude call failed', error);
    return null;
  }
}

function pickFallback(linkId: string, date: string): { question: string; category: string; source: 'library' } {
  let h = 2166136261;
  const input = `${linkId}:${date}`;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  const picked = FALLBACK[Math.abs(h) % FALLBACK.length];
  return { ...picked, source: 'library' };
}
