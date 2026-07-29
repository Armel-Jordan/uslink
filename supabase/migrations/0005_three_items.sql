-- Étape 3 — trois contenus par jour. Voir docs/architecture.md §4.1.
--
-- Débat, question, défi ne sont pas trois fonctionnalités : ce sont trois
-- instances de la même primitive (un contenu, deux réponses, révélation,
-- archive). Une seule table, donc une seule copie de la policy la plus
-- sensible du produit — trois tables, ce serait trois occasions de diverger.
--
-- Ferme aussi la seconde moitié du défaut 3 : `has_answered` exige désormais
-- de la SUBSTANCE. Un point ne déverrouille plus la réponse de l'autre.

begin;

-- ------------------------------------------------------------- les contenus

alter table public.daily_prompts
  add column if not exists kind text not null default 'question',
  add column if not exists options jsonb not null default '{}'::jsonb,
  add column if not exists intimacy_level smallint not null default 1,
  -- Non nul = contenu de soirée thématique, hors du rythme quotidien.
  add column if not exists bundle text;

alter table public.daily_prompts drop constraint if exists daily_prompts_kind_check;
alter table public.daily_prompts
  add constraint daily_prompts_kind_check check (kind in ('question', 'debate', 'challenge'));

alter table public.daily_prompts drop constraint if exists daily_prompts_intimacy_check;
alter table public.daily_prompts
  add constraint daily_prompts_intimacy_check check (intimacy_level between 1 and 3);

-- Le jsonb est FERMÉ : aucune clé surnuméraire n'est acceptée. C'est ce qui
-- empêche `options` de dériver vers un fourre-tout au fil des étapes.
--
-- `?&` et `?` d'abord, et ce n'est pas cosmétique : un CHECK qui s'évalue à
-- NULL est SATISFAIT. Sur une clé absente, `jsonb_typeof(options -> 'high')`
-- vaut NULL, la comparaison vaut NULL, et un débat sans pôle passerait.
alter table public.daily_prompts drop constraint if exists daily_prompts_options_shape;
alter table public.daily_prompts add constraint daily_prompts_options_shape check (
  case kind
    when 'question' then options = '{}'::jsonb
    when 'debate' then options ?& array['low', 'high']
                   and jsonb_typeof(options -> 'low') = 'string'
                   and jsonb_typeof(options -> 'high') = 'string'
                   and (options - 'low' - 'high') = '{}'::jsonb
    when 'challenge' then options ? 'duration_min'
                      and jsonb_typeof(options -> 'duration_min') = 'number'
                      and (options - 'duration_min') = '{}'::jsonb
  end
);

-- Cible de la clé étrangère composite d'answers (voir plus bas).
alter table public.daily_prompts drop constraint if exists daily_prompts_id_kind;
alter table public.daily_prompts add constraint daily_prompts_id_kind unique (id, kind);

-- Un contenu par (lien, jour, type). Les items de soirée portent un bundle et
-- échappent volontairement à l'unicité quotidienne.
alter table public.daily_prompts drop constraint if exists daily_prompts_link_id_prompt_date_key;
drop index if exists public.daily_prompts_one_per_kind;
create unique index daily_prompts_one_per_kind
  on public.daily_prompts (link_id, prompt_date, kind) where bundle is null;

-- ------------------------------------------------------------- les réponses

alter table public.answers add column if not exists kind text;
update public.answers set kind = 'question' where kind is null;
alter table public.answers alter column kind set not null;
-- Le défaut compte autant que le NOT NULL : sans lui, un insert sans `kind`
-- passe sur une installation neuve (où schema.sql le déclare) et échoue sur
-- une base migrée. Deux chemins, deux comportements.
alter table public.answers alter column kind set default 'question';

-- Le type de la réponse EST celui de son contenu, garanti par Postgres et non
-- par un trigger qui ferait un SELECT à chaque insertion. Un CHECK ne peut pas
-- lire la table parente, d'où la dénormalisation de `kind`.
alter table public.answers drop constraint if exists answers_prompt_id_fkey;
alter table public.answers drop constraint if exists answers_prompt_fk;
alter table public.answers
  add constraint answers_prompt_fk foreign key (prompt_id, kind)
  references public.daily_prompts (id, kind) on delete cascade;

alter table public.answers
  add column if not exists stance smallint,
  add column if not exists done boolean;

alter table public.answers alter column body drop not null;
alter table public.answers drop constraint if exists answers_body_check;
alter table public.answers drop constraint if exists answers_shape;
alter table public.answers add constraint answers_shape check (
  case kind
    when 'question' then stance is null and done is null
                     and char_length(btrim(body)) between 1 and 4000
    when 'debate' then stance between 1 and 5 and done is null
                   and char_length(btrim(body)) between 1 and 4000
    -- Un défi ne porte AUCUN texte. Sans ça, un simple appui sur « fait »
    -- déverrouillerait le commentaire écrit du partenaire.
    when 'challenge' then stance is null and done is not null and body is null
  end
);

-- Le plancher reste à 1 caractère ici, délibérément : answers.body accepte
-- 1 caractère depuis le premier commit, et un CHECK plus strict ferait AVORTER
-- la migration sur la première réponse historique courte. La substance est
-- exigée dans has_answered, qui juge le présent, pas le passé.

-- ------------------------------------------- défaut 3 : la substance

/**
 * Avoir répondu, c'est avoir répondu QUELQUE CHOSE. Auparavant l'existence
 * d'une ligne suffisait : on écrivait « . », on lisait la réponse de l'autre,
 * on réécrivait.
 *
 * La clause de grand-père est indispensable : sans elle, toute réponse
 * historique de moins de 15 caractères cesse de satisfaire has_answered, et
 * des souvenirs déjà lus se re-verrouilleraient.
 */
create or replace function public.has_answered(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.answers a
    join public.daily_prompts p on p.id = a.prompt_id
    where a.prompt_id = p_prompt and a.author_id = auth.uid()
      and (
        a.created_at < '2026-07-29'::timestamptz
        or (p.kind = 'question' and char_length(btrim(a.body)) >= 15)
        or (p.kind = 'debate' and a.stance is not null and char_length(btrim(a.body)) >= 15)
        or (p.kind = 'challenge' and a.done is not null)
      )
  );
$$;

-- La journée compte dès que les deux ont répondu à AU MOINS un des contenus :
-- exiger les trois ferait tomber toutes les séries existantes à zéro, et
-- punirait un soir chargé plus que ne le mérite un rituel.
create or replace function public.link_streak(p_link_id uuid)
returns integer language plpgsql stable security definer set search_path = public as $$
declare
  v_streak int := 0;
  v_today  date;
  v_date   date;
  v_done   boolean;
begin
  if not public.is_link_member(p_link_id) then
    return 0;
  end if;

  v_today := public.link_today(p_link_id);
  v_date := v_today;

  loop
    select count(distinct a.author_id) >= 2 into v_done
    from public.daily_prompts p
    join public.answers a on a.prompt_id = p.id
    where p.link_id = p_link_id and p.prompt_date = v_date and p.bundle is null;

    if coalesce(v_done, false) then
      v_streak := v_streak + 1;
    elsif v_date < v_today then
      exit;
    end if;

    v_date := v_date - 1;
    exit when v_streak > 365;
  end loop;

  return v_streak;
end $$;

commit;
