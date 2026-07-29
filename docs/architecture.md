## 4. Architecture technique

Expo SDK 57 / expo-router / React 19.2 / RN 0.86 côté client ; Supabase (Postgres + RLS + Auth + Edge Functions Deno) côté serveur ; `claude-opus-5` appelé exclusivement depuis `supabase/functions`, en Batch API, jamais sur le chemin de lecture. Principe directeur : **le serveur décide, la base garantit, le client affiche** — aucune date, aucun contenu et aucune règle de visibilité ne naissent sur l'appareil.

L'ossature retenue est celle de la proposition à delta minimal, pour une raison vérifiable dans le fichier : `answers_select` (`supabase/schema.sql:359`) est indexée sur `prompt_id`, pas sur `(link_id, prompt_date)`. Multiplier les lignes de `daily_prompts` fait donc passer la révélation de « par jour » à « par contenu » **sans toucher au `USING`**, et laisse `reactions` et `can_see_answer` (`supabase/schema.sql:124`) intactes — les deux autres propositions créent de nouvelles tables de contenu et laissent la reprise de `reactions.answer_id` en une ligne d'`alter table`. Y sont greffés : de la proposition « modèle de contenu », la clé étrangère composite qui verrouille le type dénormalisé et le jsonb fermé ; de la proposition « pipeline IA », toute la couche serveur (pool, jobs, rattrapage, mémoire, notifications), qui est la meilleure des trois et qui est orthogonale au choix de schéma.

Préalable de plomberie, à trancher avant la première ligne : `supabase/migrations/` **n'existe pas** dans ce dépôt, et `supabase/schema.sql:2` s'annonce comme le script idempotent unique. On crée `supabase/migrations/`, on y met les huit étapes ci-dessous, et `schema.sql` cesse d'être le chemin d'application : il devient un dump de référence régénéré par `supabase db dump`. Sans cette décision, deux sources de vérité divergent dès l'étape 1.

---

### 4.1 Le modèle de données

#### Le lien porte l'horloge, la langue et l'état du couple

```sql
-- supabase/migrations/0002_server_day.sql
alter table public.links
  add column if not exists time_zone text not null default 'Europe/Paris',
  add column if not exists day_start_hour smallint not null default 4
    check (day_start_hour between 0 and 8),
  add column if not exists time_zone_changed_at timestamptz,
  add column if not exists notify_hour smallint not null default 20
    check (notify_hour between 6 and 23),
  add column if not exists closed_at timestamptz,
  add column if not exists locale text not null default 'fr';

-- supabase/migrations/0004_onboarding.sql
alter table public.links
  add column if not exists started_on date,
  add column if not exists objectives text[] not null default '{}'
    check (objectives <@ array['complicite','decouverte','fun']),
  add column if not exists interests text[] not null default '{}',
  add column if not exists intimacy smallint not null default 1 check (intimacy between 1 and 3),
  add column if not exists intimacy_cap smallint not null default 3 check (intimacy_cap between 1 and 3),
  add column if not exists profile_doc text check (char_length(profile_doc) <= 900),
  add column if not exists profile_doc_at timestamptz;
```

`day_start_hour = 4` : la journée bascule à 4 h locales et non à minuit — sans ça, la réponse de 00 h 30 tombe dans le lendemain et casse une série à tort. `locale` sur le lien et non sur la personne, par cohérence avec le fuseau : deux personnes partagent un contenu, donc une langue. `profile_doc` sur `links` parce que c'est un profil de **couple** ; un membre qui part n'en emporte rien.

#### Le contenu : une seule table, trois types, le type rendu infalsifiable

```sql
-- supabase/migrations/0003_three_items.sql
alter table public.daily_prompts
  add column if not exists kind text not null default 'question'
    check (kind in ('question','debate','challenge')),
  add column if not exists options jsonb not null default '{}'::jsonb,
  add column if not exists intimacy_level smallint not null default 1
    check (intimacy_level between 1 and 3),
  add column if not exists bundle text,
  add column if not exists locale text not null default 'fr';

-- Cible de la clé étrangère composite de answers (voir plus bas).
alter table public.daily_prompts add constraint daily_prompts_id_kind unique (id, kind);

-- Un item par (lien, jour, type). Les items de date night portent un bundle
-- et échappent volontairement à l'unicité quotidienne.
alter table public.daily_prompts drop constraint if exists daily_prompts_link_id_prompt_date_key;
create unique index if not exists daily_prompts_one_per_kind
  on public.daily_prompts (link_id, prompt_date, kind) where bundle is null;

-- Le jsonb est FERMÉ : aucune clé surnuméraire n'est acceptée. C'est ce qui
-- empêche `options` de dériver vers un fourre-tout.
alter table public.daily_prompts add constraint daily_prompts_options_shape check (
  case kind
    when 'question'  then options = '{}'::jsonb
    when 'debate'    then jsonb_typeof(options->'low') = 'string'
                      and jsonb_typeof(options->'high') = 'string'
                      and (options - 'low' - 'high') = '{}'::jsonb
    when 'challenge' then jsonb_typeof(options->'duration_min') = 'number'
                      and (options - 'duration_min') = '{}'::jsonb
  end
);
```

Table unique plutôt que trois tables : la règle de révélation, l'archive (`src/app/(app)/(tabs)/history.tsx`), les réactions et le streak sont écrits une fois contre une seule table ; trois tables, ce serait trois copies de la policy la plus sensible du produit, donc trois occasions de diverger. Le nom `daily_prompts` ment désormais (ce sont des items, dont un seul est une question) : renommage refusé, coût de diff traversant pour zéro valeur, mais l'en-tête de `supabase/schema.sql:4` doit être corrigé pour que le nom ne trompe personne.

Le débat ne porte **pas** sa position : il porte une affirmation clivante dans `question` et les deux libellés d'extrémité dans `options`. La position vit sur la réponse.

#### Les réponses : une colonne scalaire, une forme par type, un type non falsifiable

```sql
alter table public.answers add column if not exists kind text;
update public.answers set kind = 'question' where kind is null;
alter table public.answers alter column kind set not null;

-- Le type de la réponse EST celui de l'item : Postgres le garantit, pas un trigger.
alter table public.answers drop constraint if exists answers_prompt_id_fkey;
alter table public.answers
  add constraint answers_prompt_fk
  foreign key (prompt_id, kind) references public.daily_prompts (id, kind) on delete cascade;

alter table public.answers
  add column if not exists stance smallint check (stance between 1 and 5),
  add column if not exists done boolean;

alter table public.answers alter column body drop not null;
alter table public.answers drop constraint if exists answers_body_check;
alter table public.answers add constraint answers_shape check (
  case kind
    when 'question'  then stance is null and done is null
                      and char_length(btrim(body)) between 1 and 4000
    when 'debate'    then stance between 1 and 5 and done is null
                      and char_length(btrim(body)) between 1 and 4000
    when 'challenge' then stance is null and done is not null and body is null
  end
);
```

Trois choix non évidents.

**La clé étrangère composite remplace le trigger.** Un `CHECK` ne peut pas lire la table parente, donc `kind` doit être dénormalisé sur la réponse. La proposition delta-minimal le remplissait par un trigger `security definer` faisant un `SELECT` par insertion ; `(prompt_id, kind) → (id, kind)` fait le même travail en intégrité déclarative, sans I/O et sans code à auditer.

**Le plancher de longueur reste à 1 caractère dans le `CHECK`.** C'est délibéré et c'est l'écueil sur lequel les deux autres propositions échouent : `answers.body` accepte 1 caractère depuis le premier commit (`supabase/schema.sql:62`), donc tout `CHECK` à 8 ou 10 caractères fait **avorter le backfill** sur la première réponse historique courte. La substance est exigée dans `has_answered` (§4.2), avec une clause de grand-père sur les lignes antérieures à la bascule — pas dans une contrainte de table qui valide le passé.

**Le défi ne porte pas de texte.** `body is null` pour `kind = 'challenge'`. Sans ça, un simple tap sur « fait » déverrouille le commentaire écrit du partenaire, ce qu'aucune contrainte SQL ne sait empêcher. Le commentaire d'un défi se fait par réaction emoji — mécanique déjà en place (`reactions`, `supabase/schema.sql:70`) et déjà soumise à `can_see_answer`.

#### Onboarding : la personne d'abord, le couple ensuite

La vision impose l'ordre onboarding → appairage. Les données de couple ne peuvent donc pas être écrites sur `links` à la saisie.

```sql
create table if not exists public.profile_onboarding (
  id uuid primary key references auth.users on delete cascade,
  birth_date date,
  city text check (char_length(city) <= 60),
  region text,
  interests text[] not null default '{}' check (coalesce(array_length(interests,1),0) <= 8),
  goals text[] not null default '{}' check (goals <@ array['complicite','decouverte','fun']),
  relationship_started_on date,
  updated_at timestamptz not null default now()
);
alter table public.profile_onboarding enable row level security;
create policy profile_onboarding_own on public.profile_onboarding for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

alter table public.profiles
  add column if not exists birth_date date,          -- visible du partenaire : rappel d'anniversaire
  add column if not exists ai_text_opt_in boolean not null default false;
```

Deux tables plutôt qu'une, parce que **la RLS Postgres est par ligne et non par colonne** : ajouter `city` à `profiles` l'exposerait au partenaire via `profiles_select` (`supabase/schema.sql:322`). Cette séparation rend inutiles les vues `security definer` acrobatiques que les deux autres propositions construisent pour filtrer des colonnes. La ville est collectée (elle est dans la vision) et n'est transmise nulle part en v1 ; seule `region`, dérivée côté serveur, sort vers le modèle.

`join_link` recopie ensuite `interests` et `goals` (union des deux) sur `links`, et `started_on` prend la valeur du créateur. **Si les deux ont saisi des dates de début différentes, l'écran d'appairage affiche les deux et demande de choisir** — le compteur « Ensemble depuis X jours » est affiché aux deux personnes, sa provenance ne peut pas être un « dernier écrivain gagne » silencieux.

#### Les tables de service

```sql
-- Contenu générique, partagé entre couples. Aucune policy : service_role seul.
create table if not exists public.pool_items (
  id uuid primary key default gen_random_uuid(),
  locale text not null default 'fr',
  mode text not null check (mode in ('couple','friends')),
  kind text not null check (kind in ('question','debate','challenge')),
  intimacy_level smallint not null check (intimacy_level between 1 and 3),
  tenure_bucket text not null check (tenure_bucket in ('0-6m','6m-3a','3a+')),
  tags text[] not null default '{}',
  question text not null,
  category text not null default 'général',
  options jsonb not null default '{}'::jsonb,
  bundle_theme text,                     -- non null = item de date night
  used_count int not null default 0,
  retired_at timestamptz
);
create index on public.pool_items (locale, mode, kind, intimacy_level, tenure_bucket, used_count)
  where retired_at is null;
create index on public.pool_items using gin (tags);
alter table public.pool_items enable row level security;

-- Le repli ultime, LISIBLE PAR POSTGRES. src/lib/prompt-library.ts est un
-- fichier TypeScript : ni Deno ni le SQL ne peuvent le lire. Il reste la
-- source de vérité de demo.ts et alimente cette table par un script de seed.
create table if not exists public.library_items (like public.pool_items including all);

create table if not exists public.generation_jobs (
  link_id uuid not null references public.links on delete cascade,
  week_start date not null,
  status text not null default 'pending'
    check (status in ('pending','claimed','submitted','done','failed')),
  batch_id text, custom_id text, claimed_at timestamptz,
  attempts smallint not null default 0, last_error text,
  primary key (link_id, week_start)
);

create table if not exists public.job_runs (
  id bigserial primary key,
  job text not null, started_at timestamptz not null default now(),
  finished_at timestamptz, ok boolean, rows_touched int, error text
);

create table if not exists public.recaps (
  link_id uuid not null references public.links on delete cascade,
  week_start date not null,
  body text not null check (char_length(body) between 40 and 1200),
  stats jsonb not null default '{}'::jsonb,
  source text not null check (source in ('ai','library')),
  primary key (link_id, week_start)
);
alter table public.recaps enable row level security;
create policy recaps_select on public.recaps for select to authenticated
  using (public.is_link_member(link_id));

create table if not exists public.link_events (
  id uuid primary key default gen_random_uuid(),
  link_id uuid not null references public.links on delete cascade,
  kind text not null check (kind in ('anniversary','birthday','custom')),
  label text not null check (char_length(label) between 1 and 60),
  on_date date not null,
  created_by uuid not null references auth.users on delete cascade
);
alter table public.link_events enable row level security;
create policy link_events_select on public.link_events for select to authenticated
  using (public.is_link_member(link_id));
create policy link_events_write on public.link_events for insert to authenticated
  with check (public.is_link_member(link_id) and created_by = auth.uid());
create policy link_events_delete on public.link_events for delete to authenticated
  using (public.is_link_member(link_id));
```

`daily_prompts.pool_item_id uuid references public.pool_items on delete set null` est ajoutée à l'**étape 4**, pas à l'étape 3 : poser la clé étrangère avant l'existence de `pool_items` fait échouer la migration au premier `psql`.

---

### 4.2 La règle de révélation

Elle ne peut pas vivre dans le client pour une raison qui n'a rien de doctrinal : le client détient une clé `anon` et parle à PostgREST. Toute condition évaluée en JavaScript est une suggestion — un binaire patché, ou simplement `curl` avec le JWT extrait du trousseau, contourne l'écran et lit la table. La seule frontière que l'utilisateur ne franchit pas est le `USING` d'une policy, évalué par Postgres après authentification. C'est pour ça que la règle est un prédicat SQL et pas une branche de rendu.

**Décision : la révélation est par contenu, pas globale.** Trois raisons. C'est déjà le comportement écrit — `answers_select` est indexée sur `prompt_id`, donc la granularité devient l'item par simple multiplication des lignes, sans nouvelle fonction. Le défi se relève le soir : une révélation globale rendrait le débat et la question du matin invisibles jusqu'à la nuit, et la boucle ne se fermerait presque jamais. Enfin trois micro-révélations valent mieux qu'une différée.

Le `USING` de `answers_select` **n'est pas modifié**, littéralement :

```sql
-- inchangée, supabase/schema.sql:359-364
create policy answers_select on public.answers for select to authenticated
  using (
    author_id = auth.uid()
    or (public.can_see_prompt(prompt_id) and public.has_answered(prompt_id))
  );
```

Ce qui change, c'est la substance exigée par `has_answered` (étape 3) :

```sql
create or replace function public.has_answered(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.answers a
    join public.daily_prompts p on p.id = a.prompt_id
    where a.prompt_id = p_prompt and a.author_id = auth.uid()
      and (
        a.created_at < '2026-09-01'::timestamptz      -- clause de grand-père : les
                                                       -- archives déjà révélées le restent
        or (p.kind = 'question'  and char_length(btrim(a.body)) >= 15)
        or (p.kind = 'debate'    and a.stance is not null and char_length(btrim(a.body)) >= 15)
        or (p.kind = 'challenge' and a.done is not null)
      )
  );
$$;
```

La clause de grand-père est indispensable : sans elle, toute réponse historique de moins de 15 caractères cesse de satisfaire `has_answered`, et **des souvenirs déjà lus se re-verrouillent**. Le débat exige la position **et** quinze caractères de justification : sans ça, un tap sur le curseur ouvre le texte écrit de l'autre.

Les trois écritures, elles, se durcissent :

```sql
create or replace function public.partner_answered(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.answers
                 where prompt_id = p_prompt and author_id <> auth.uid());
$$;
grant execute on function public.partner_answered(uuid) to authenticated;

create or replace function public.prompt_is_open(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.daily_prompts p
    where p.id = p_prompt
      and (
        (p.bundle is null and p.prompt_date between public.link_today(p.link_id) - 1
                                                and public.link_today(p.link_id))
        or (p.bundle is not null and p.created_at > now() - interval '12 hours')
      )
  );
$$;

drop policy if exists answers_insert on public.answers;
create policy answers_insert on public.answers for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.can_see_prompt(prompt_id)
    and public.prompt_is_open(prompt_id)      -- ferme le déverrouillage rétroactif de l'archive
  );

drop policy if exists answers_update on public.answers;
create policy answers_update on public.answers for update to authenticated
  using (
    author_id = auth.uid()
    and public.can_see_prompt(prompt_id)      -- un ex-membre perd l'écriture
    and public.prompt_is_open(prompt_id)
    and not public.partner_answered(prompt_id) -- gel à la révélation
  )
  with check (author_id = auth.uid() and public.can_see_prompt(prompt_id));

-- Un WITH CHECK valide la ligne finale, il n'empêche pas de repointer une clé.
create or replace function public.answers_freeze_keys()
returns trigger language plpgsql as $$
begin
  if new.prompt_id is distinct from old.prompt_id
     or new.author_id is distinct from old.author_id
     or new.kind is distinct from old.kind then
    raise exception 'immutable_answer_key';
  end if;
  return new;
end $$;
drop trigger if exists answers_no_repoint on public.answers;
create trigger answers_no_repoint before update on public.answers
  for each row execute function public.answers_freeze_keys();
```

Le verrou qui compte n'est pas le seuil de caractères — on tape quinze caractères au hasard — c'est **l'irréversibilité** : dès que le partenaire a répondu, votre ligne est figée. Tricher coûte définitivement votre propre réponse du jour, affichée à l'autre et archivée. On remplace une impossibilité technique inatteignable par un coût social ; c'est la bonne conception ici, et il faut le dire au lieu de prétendre à l'étanchéité.

Enfin, **le client cesse d'écrire du contenu** : `daily_prompts_insert` (`supabase/schema.sql:355`) est supprimée à l'étape 4, dès que le pool sert de repli serveur. Tant qu'elle existe, un membre peut fabriquer une « question du jour » avec le texte de son choix — l'index unique est partiel (`where bundle is null`), donc rien ne limite les insertions à `bundle` renseigné.

Toute vue exposée à `authenticated` porte obligatoirement `with (security_invoker = true)`. Sans lui, une vue s'exécute avec les droits de son propriétaire, PostgREST l'expose, et `GET /rest/v1/<vue>` rend lisibles les réponses de tous les couples : c'est l'annulation complète de la règle sur tout l'historique. Cette contrainte est à ajouter à `AGENTS.md`, avec sa jumelle : **toute fonction `security definer` accordée à `authenticated` commence par un `is_link_member` en garde de sortie anticipée**, jamais par un prédicat placé dans une CTE — une sous-requête scalaire indépendante n'est pas filtrée par le `WHERE` d'une CTE voisine.

---

### 4.3 Le jour, les fuseaux et la série

**Le fuseau vit sur le lien, pas sur l'utilisateur.** Le jour est l'unité de co-présence : si chaque personne avait le sien, deux partenaires en fuseaux différents auraient deux jours différents, deux lignes distinctes, et la révélation ne deviendrait jamais vraie — c'est exactement le défaut n°1. Un couple partage un rituel, donc une horloge. Contrepartie assumée : un couple longue distance vit sur l'horloge de celui qui a créé le lien, et l'écran Profil doit le dire en toutes lettres (« Votre journée commence à 4 h, heure de Paris »).

```sql
create or replace function public.link_today(p_link uuid)
returns date language sql stable security definer set search_path = public as $$
  select ((now() at time zone l.time_zone) - make_interval(hours => l.day_start_hour))::date
  from public.links l where l.id = p_link;
$$;
grant execute on function public.link_today(uuid) to authenticated;
```

`localDate()` (`src/lib/data/adapter.ts:53`) est **supprimée**, ainsi que son ré-export (`src/lib/data/index.ts:10`). `src/lib/data/demo.ts` en garde une copie privée — il l'utilise quatre fois (`src/lib/data/demo.ts:51,249,313`) et n'a pas de serveur, donc pas de bug possible. Les trois sites d'appel côté Supabase disparaissent : `src/lib/data/supabase.ts:198` (le jour vient de `my_link()`, étendue à `today date` et `time_zone text`), `src/lib/data/supabase.ts:263` (`.lt('prompt_date', link.today)`), `src/lib/data/supabase.ts:307` (le corps envoyé à l'Edge Function ne contient plus de date — puis l'appel disparaît entièrement à l'étape 5).

`prompt_date` reste une **colonne écrite une fois et jamais recalculée**. `link_today()` ne sert qu'au présent : ouvrir la journée, borner la fenêtre d'écriture, cadencer les crons. C'est ce qui limite les dégâts d'un voyage — au pire une bascule sautée ou dupliquée au moment du changement, pas une réécriture de l'histoire. `links.time_zone_changed_at` borne le changement à un par 24 h et permet au streak de tolérer un trou d'un jour dans les 48 h qui suivent.

**`link_streak` devient un balayage dans le fuseau du lien, et un jour compte dès que les deux ont répondu à au moins un des trois contenus.**

```sql
create or replace function public.link_streak(p_link_id uuid)
returns integer language plpgsql stable security definer set search_path = public as $$
declare v_streak int := 0; v_today date; v_date date; v_done boolean; v_tz_at timestamptz;
begin
  if not public.is_link_member(p_link_id) then return 0; end if;
  select public.link_today(p_link_id), l.time_zone_changed_at
    into v_today, v_tz_at from public.links l where l.id = p_link_id;
  v_date := v_today;
  loop
    select count(distinct a.author_id) >= 2 into v_done
    from public.daily_prompts p
    join public.answers a on a.prompt_id = p.id
    where p.link_id = p_link_id and p.prompt_date = v_date and p.bundle is null;

    if coalesce(v_done, false) then
      v_streak := v_streak + 1;
    elsif v_date < v_today
      and not (v_tz_at is not null and v_tz_at > now() - interval '48 hours') then
      exit;                      -- tolérance d'un trou après un changement de fuseau
    end if;
    v_date := v_date - 1;
    exit when v_streak > 730;
  end loop;
  return v_streak;
end $$;
```

Exiger les trois contenus serait une régression double : c'est une corvée pour l'utilisateur, et surtout **les jours historiques n'ont qu'un item** — un seuil à 3 remettrait à zéro le streak de tous les couples existants le jour de la migration. « Participer », c'est répondre ; la vision ne dit pas « répondre à tout ».

---

### 4.4 Le pipeline de génération

**Par lot planifié, jamais à la demande. Le modèle n'est jamais sur le chemin de lecture.** `supabase.functions.invoke` disparaît de `src/lib/data/supabase.ts` (`generatePrompt`, lignes 303-334, et `fetchPrompt`, 287-296, sont supprimées) : c'est aussi le correctif définitif du défaut n°6 côté client, par suppression plutôt que par garde-fou. Le repli synchrone IA n'existe pas. Trois raisons, dans l'ordre : une notification suivie d'un spinner de douze secondes tue le rituel ; le Batch API divise le coût par deux et le lot a des heures de mou ; un lot planifié n'a pas de course.

#### Ordonnancement

```
pg_cron  03:00 UTC   pool-refill      6 appels Batch → public.pool_items      (coût FIXE)
pg_cron  horaire :05 plan_week()      insère les jobs des couples actifs
pg_cron  horaire :10 couple-week      claim_jobs() → lot Batch (profil + résumé)
pg_cron  */5         collect          poll du lot → links.profile_doc, public.recaps
pg_cron  horaire :15 open_days()      ouverture SQL des journées qui basculent  (0 appel LLM)
pg_cron  horaire :20 fill_gaps()      tout jour sans 3 items à T−45 min → pool, puis library_items
pg_cron  horaire :30 enqueue_reminders()
pg_cron  */1         push_drain()  ·  */15 push_receipts()
```

**Un seul appel là où il y en a un.** Le remplissage du pool produit les trois types dans une requête, avec `output_config.format` (JSON schema) : trois appels séparés paieraient trois fois le contexte et trois fois la réflexion, et produiraient régulièrement un débat et une question sur le même thème.

**Où passe la frontière du pool.** Le pool ne sait rien d'un couple : il ne voit qu'un segment `(locale, mode, kind, intimacy_level, tenure_bucket, tags)`. La couche couple ne fait que **sélectionner**, en SQL pur, zéro appel modèle — hachage déterministe contre les items non encore servis à ce lien, plus une affinité `tags && link tags`. La personnalisation du texte lui-même ne se fait pas item par item : elle se fait en amont, par le profil de couple qui oriente les tags et l'intimité (§4.5). Un item de pool est réutilisable par des milliers de couples ; deux couples ne se parlent pas, et le produit n'a — et ne doit pas avoir — de fil social.

#### Concurrence

Trois verrous superposés, aucun applicatif. `pg_advisory_xact_lock(hashtextextended(link_id::text, 0))` en tête d'`open_day()` sérialise client, cron et partenaire ; `daily_prompts_one_per_kind` est un index unique ; `generation_jobs` a pour clé primaire `(link_id, week_start)`, ce qui fait de la table elle-même la sérialisation. Le worker réclame en `for update skip locked` et récupère les jobs orphelins d'un worker mort (`claimed_at < now() - interval '20 minutes'`). L'`upsert` actuel de l'Edge Function (`supabase/functions/daily-prompt/index.ts:113-124`) est remplacé par `insert ... on conflict do nothing` suivi d'une relecture : il écrase aujourd'hui `question`/`category` en gardant le même `id`, ce qui change le contenu sous les yeux d'un utilisateur qui a peut-être déjà répondu.

#### Repli — l'invariant rendu exécutable

`open_day()` compte les items insérés ; s'il en manque un, il tire dans `library_items`. `fill_gaps()` repasse toutes les heures et garantit trois items 45 minutes avant l'heure de rappel du lien. **Règle produit : on ne remplace jamais un contenu déjà affiché.** Si le repli bibliothèque a servi, il reste ; substituer un contenu IA après coup permettrait à l'un de répondre au contenu bibliothèque pendant que l'autre voit le contenu IA — la révélation comparerait deux choses différentes.

`src/lib/prompt-library.ts` reste la source de vérité, et un script de seed le déverse dans `library_items` : c'est un fichier TypeScript, ni Deno ni Postgres ne peuvent le lire, donc « repli sur la banque locale » côté serveur n'est réalisable qu'à cette condition.

#### Paramètres d'appel, et le défaut n°8

`supabase/functions/daily-prompt/index.ts:200` pose `max_tokens: 2048` sans champ `thinking`. Sur `claude-opus-5` la réflexion est **active par défaut**, et `max_tokens` plafonne réflexion **plus** texte. Une génération qui réfléchit un peu trop tronque le JSON, `JSON.parse` (ligne 230) lève, le `catch` (ligne 240) active le repli, et le couple n'a jamais de contenu IA sans que personne ne le voie. Correctif : `max_tokens: 8192` pour un lot d'items, en **gardant la réflexion active** à `effort: 'low'` — la désactiver a ses propres modes d'échec, dont la fuite de balises dans la sortie visible, ce qui recréerait précisément le bug qu'on répare.

Deux autres points à écrire en commentaire dans la fonction : le `cache_control` posé à `supabase/functions/daily-prompt/index.ts:210` **ne cache rien**, le `SYSTEM_PROMPT` (ligne 51) faisant ~370 tokens sous le minimum de 512 d'Opus 5 — il repassera le seuil en portant les règles des trois types ; et le Batch API **rejette** `fallbacks` ainsi que le préchauffage `max_tokens: 0`, or le code livré utilise déjà `fallbacks: 'default'` (lignes 208-209). Un item revenu en `stop_reason: 'refusal'` doit être rejoué sur le chemin synchrone, ou retomber sur le pool. Enfin `new Anthropic({ apiKey, timeout: 20_000, maxRetries: 1 })` — millisecondes.

#### Coûts

Tarifs : 5 $/MTok en entrée, 25 $/MTok en sortie ; lecture de cache ×0,1 ; Batch −50 %. Les volumes en tokens sont des ordres de grandeur pour du français et **doivent être ré-étalonnés avec `messages.count_tokens` avant tout engagement budgétaire** — jamais avec un tokenizer tiers.

| Poste | Cadence | Tokens | Coût unitaire (Batch) | 10 000 couples |
|---|---|---|---|---|
| `pool-refill`, 6 segments | quotidien | 2 000 in / ~9 000 out | 0,118 $ | **21 $/mois — fixe** |
| `open_days` + `fill_gaps` | horaire | — | **0 $** (SQL) | 0 $ |
| `couple-week` (profil + résumé, un appel) | hebdo, couples actifs | 1 800 cachés + 2 500 in / ~2 000 out | 0,032 $ | 554 $ (40 % actifs) |
| Statistiques, % d'accord, divergences | à la demande | — | **0 $** (SQL) | 0 $ |

- **Par couple actif et par jour : 0,0045 $.**
- **À 10 000 couples, 40 % actifs : ~575 $/mois.** Tous actifs : ~1 407 $/mois.
- **À 1 couple : ~21,10 $/mois.** Le plancher, c'est le pool, pas le couple — d'où la décision de ne construire le pool qu'à l'étape 4 : en dessous de ~1 000 couples il coûte plus qu'il ne rapporte.
- Ligne de base naïve (3 appels/jour/couple, `effort: 'low'`, réflexion comprise, tarif synchrone) : ~0,12 $/couple/jour, soit **~36 000 $/mois à 10 000 couples**. Facteur 25 à 60.

L'ordre des leviers, à retenir avant d'optimiser quoi que ce soit : nombre d'appels par couple ≫ `effort` et réflexion ≫ Batch ≫ porte « couples actifs » ≫ cache de prompt. **Le cache ne vaut que ~8 % de la facture** (il économise 45 % de l'entrée, mais l'entrée ne pèse que 18 % du total). Cadence quotidienne pour le pool et hebdomadaire pour le profil : le sinistre maximal d'une panne est ainsi d'un jour de contenu générique, pas d'une semaine.

---

### 4.5 La mémoire de personnalisation

Renvoyer l'historique complet est intenable — 90 jours × 3 items × 2 réponses ≈ 43 000 tokens d'entrée par appel — et c'est la pire façon de dépenser ces tokens : le modèle re-dérive chaque semaine les mêmes conclusions. La mémoire est un **document réécrit, jamais concaténé** : `links.profile_doc`, 900 caractères maximum, plus une liste de tags.

**Qui l'écrit** : `supabase/functions/couple-week`, le même appel hebdomadaire qui produit le résumé (§4.7), en `service_role`. Aucune policy d'écriture ne l'expose au client. **Quand** : une fois par semaine, et uniquement pour les liens ayant au moins une réponse révélée dans les sept derniers jours — un lien dormant ne coûte rien. **Lisible par le couple** : oui, en lecture seule dans `src/app/(app)/(tabs)/profile.tsx`, avec un bouton d'effacement. Un document de mémoire invisible écrit par une IA sur la vie intime d'un couple est un problème de confiance, pas une fonctionnalité.

**Une seule fonction construit la charge utile envoyée à l'API**, et l'Edge Function n'envoie rien d'autre. C'est auditable en un écran, ce qui est le seul moyen que la règle tienne dans six mois.

```sql
create or replace function public.ai_context(p_link uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'mode',           l.mode,
    'locale',         l.locale,
    'tranches_age',   (select coalesce(jsonb_agg((extract(year from age(p.birth_date))::int / 5) * 5), '[]'::jsonb)
                         from link_members m join profiles p on p.id = m.user_id
                        where m.link_id = l.id and p.birth_date is not null),
    'region',         (select po.region from link_members m join profile_onboarding po on po.id = m.user_id
                        where m.link_id = l.id limit 1),
    'mois_ensemble',  case when l.started_on is null then null
                      else (extract(year from age(l.started_on))*12
                          + extract(month from age(l.started_on)))::int end,
    'objectifs',      l.objectives,
    'interets',       l.interests,
    'intimite',       least(l.intimacy, l.intimacy_cap),
    'profil',         l.profile_doc,
    'occasions',      public.upcoming_occasions(l.id, 14),
    'deja_vus',       (select coalesce(jsonb_agg(jsonb_build_object('k',kind,'c',category,'q',left(question,60))), '[]'::jsonb)
                         from (select kind, category, question from daily_prompts
                                where link_id = l.id order by prompt_date desc limit 30) r),
    'semaine',        (select coalesce(jsonb_agg(jsonb_build_object(
                          'k', p.kind, 'c', p.category, 'niv', p.intimacy_level,
                          'positions', s.stances, 'ecart', s.gap, 'fait', s.done,
                          'extrait', case when p.intimacy_level < 3 and s.both_opted_in
                                          then left(btrim(s.body), 40) end)), '[]'::jsonb)
                         from daily_prompts p join public.week_signals s on s.prompt_id = p.id
                        where p.link_id = l.id
                          and p.prompt_date >= public.link_today(l.id) - 7)
  ) from public.links l where l.id = p_link;
$$;
revoke all on function public.ai_context(uuid) from public, anon, authenticated;
```

**Ce que le modèle voit** : le mode, la langue, des tranches d'âge de cinq ans, une région, des mois d'ancienneté, les objectifs, le niveau d'intimité, le document de profil, les occasions à venir, les trente derniers titres (anti-répétition), et pour la semaine écoulée des catégories, des positions numériques, des écarts et des extraits de 40 caractères.

**Ce qu'il ne voit jamais** : un prénom (`supabase/functions/daily-prompt/index.ts:188` l'envoie aujourd'hui, sans aucune contrepartie de qualité), un e-mail, un identifiant, une ville, une date de naissance exacte, un texte d'item de niveau 3, un texte de plus de quatorze jours, et **aucun texte du tout si l'un des deux membres n'a pas activé `profiles.ai_text_opt_in`**.

Le consentement est **par personne et en `default false`** : envoyer du texte intime à une API tierce ne peut pas être un choix par défaut, ni un choix qu'un membre fait pour deux. Le produit continue de fonctionner sans texte — les signaux dérivés (catégories, positions, complétion) suffisent à la personnalisation promise par la vision ; la case à cocher n'éteint rien, elle affine.

La troncature de l'extrait est faite **en SQL**. Une troncature côté client est une suggestion ; côté serveur, c'est une garantie.

---

### 4.6 Notifications

`expo-notifications` n'est pas encore une dépendance ; l'installer via `npx expo install expo-notifications` pour respecter la version épinglée par le SDK 57.

```sql
create table if not exists public.push_tokens (
  token text primary key,
  user_id uuid not null references auth.users on delete cascade,
  platform text not null check (platform in ('ios','android')),
  fail_count smallint not null default 0,
  updated_at timestamptz not null default now()
);
create index on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
-- Un jeton Expo Push est une CAPACITÉ : le partenaire ne doit jamais pouvoir
-- l'exfiltrer et pousser des notifications arbitraires. Aucune lecture croisée.
create policy push_tokens_own on public.push_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.notification_outbox (
  id bigserial primary key,
  user_id uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('daily','partner_answered','occasion','recap')),
  dedup_key text not null unique,
  body_key text not null,            -- CLÉ de strings.ts, jamais du texte, jamais du contenu
  ticket_id text, sent_at timestamptz, receipt_checked_at timestamptz,
  attempts smallint not null default 0,
  created_at timestamptz not null default now()
);
create index on public.notification_outbox (created_at) where sent_at is null;
alter table public.notification_outbox enable row level security;   -- aucune policy : service_role
```

**Déclencheurs.** Le rappel quotidien est un `pg_cron` horaire qui sélectionne les liens dont `extract(hour from (now() at time zone l.time_zone))::int = l.notify_hour` et dont un membre n'a pas fini sa journée : un seul job couvre les 24 fuseaux, bénéfice direct de `links.time_zone`. Le « ton partenaire a répondu » est un trigger `after insert on public.answers` qui **écrit dans l'outbox**, jamais un appel HTTP — un `pg_net` qui échoue dans un trigger peut annuler l'insertion de la réponse, et la réponse d'un utilisateur ne doit jamais dépendre de la disponibilité d'Expo. Un cron `*/1` draine, un cron `*/15` relit les accusés.

**Contenu des messages, et la règle.** Le corps ne contient **jamais** de contenu, **jamais** le type d'item, **jamais** d'horodatage précis. `body_key` porte une clé, pas un texte : la garantie devient vérifiable en lisant le schéma au lieu d'être une discipline de code.

| Notification | Corps | Ce qu'elle tait |
|---|---|---|
| Rappel quotidien | « Vos trois contenus du jour vous attendent. » | Le débat, la question, le défi |
| Partenaire a répondu | « Camille a répondu. À toi. » | **À quel contenu** — savoir qu'elle a traité le débat sur l'argent en premier est une information |
| Occasion | « Une date compte aujourd'hui. » | Laquelle |

Le `dedup_key` unique par jour et par personne sert autant l'anti-spam que la confidentialité : trois notifications successives dans la journée diffusent le rythme de réponse du partenaire. Le modèle de menace est concret — sur iOS le corps s'affiche sur l'écran verrouillé, potentiellement sous les yeux de l'autre.

**Cycle de vie des jetons.** Expo est en deux temps : `/push/send` ne renvoie qu'un ticket, et c'est le reçu, récupérable une quinzaine de minutes plus tard, qui rapporte `DeviceNotRegistered`. Sans purge, `push_tokens` accumule les désinstallations, le taux d'échec monte, Expo limite puis bloque l'expéditeur — et la panne est **globale et silencieuse**. `push_receipts` supprime sur `DeviceNotRegistered` et après trois échecs consécutifs.

**Frontière des chaînes.** `supabase/functions` est du Deno, exclu de `tsconfig.json` par choix : il ne peut pas importer `src/lib/strings.ts`. Un second dictionnaire `supabase/functions/_shared/strings.ts` porte les seuls gabarits de notification, et un script `npm run check:strings` compare les jeux de clés et échoue sur divergence. `AGENTS.md` devient : *aucune chaîne française littérale dans un composant ni dans une Edge Function ; deux dictionnaires, un test qui les tient synchronisés.*

---

### 4.7 Statistiques et résumés hebdomadaires

**Les statistiques sont en SQL, entièrement. Le modèle ne calcule rien, il raconte.** Trois raisons : un LLM qui calcule un pourcentage est une régression déterministe et un coût récurrent ; le chiffre est comparé par deux personnes qui regardent leurs écrans côte à côte, donc deux appels renvoyant 72 % et 74 % sont inacceptables ; et l'écran doit s'ouvrir instantanément.

```sql
create or replace view public.debate_pairs with (security_invoker = true) as
select p.link_id, p.id as prompt_id, p.prompt_date, p.category,
       abs(a.stance - b.stance) as gap,
       (abs(a.stance - b.stance) <= 1) as agree
from public.daily_prompts p
join public.answers a on a.prompt_id = p.id
join public.answers b on b.prompt_id = p.id and b.author_id > a.author_id
where p.kind = 'debate';

create or replace function public.link_stats(p_link uuid, p_days int default 90)
returns table (agreement_pct int, debates int, completion_pct int, top_divergence jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_link_member(p_link) then return; end if;   -- garde en SORTIE ANTICIPÉE
  return query
  with scoped as (
    select * from public.debate_pairs
     where link_id = p_link and prompt_date >= public.link_today(p_link) - p_days)
  select round(100 * coalesce(avg(agree::int), 0))::int,
         count(*)::int,
         (select round(100 * coalesce(avg((cnt >= 2)::int), 0))::int
            from (select count(distinct a.author_id) cnt
                    from public.daily_prompts p left join public.answers a on a.prompt_id = p.id
                   where p.link_id = p_link and p.bundle is null
                     and p.prompt_date >= public.link_today(p_link) - p_days
                   group by p.id) t),
         (select coalesce(jsonb_agg(jsonb_build_object('categorie', category,
                    'ecart', round(g,2), 'n', n) order by g desc), '[]'::jsonb)
            from (select category, avg(gap) g, count(*) n from scoped
                   group by category having count(*) >= 3 order by avg(gap) desc limit 3) d)
  from scoped;
end $$;
grant execute on function public.link_stats(uuid, int) to authenticated;
```

`security_invoker = true` sur la vue est **la** condition de correction : sans lui, la vue s'exécute avec les droits de son propriétaire, PostgREST l'expose, et les positions de tous les couples deviennent lisibles sur des items auxquels on n'a jamais répondu. Avec, une ligne n'apparaît que si les deux réponses sont lisibles pour l'appelant : la statistique **hérite** de la règle de révélation au lieu de la contourner. Le `is_link_member` en sortie anticipée, et non dans une CTE, est la seconde condition : une sous-requête scalaire indépendante n'est pas filtrée par le `WHERE` d'une CTE voisine, et la fonction est `definer`. Le `having count(*) >= 3` évite d'annoncer « vous divergez sur l'argent » à partir d'un seul débat. Ni vue matérialisée ni cache : un couple accumule ~365 débats par an et l'agrégat en touche 90 par l'index `(link_id, prompt_date desc)`.

**Le résumé hebdomadaire est produit par le même appel que le profil de couple** (`couple-week`) : les deux partagent exactement le même contexte, les séparer le renverrait deux fois. Le modèle reçoit `ai_context()`, plus les chiffres **déjà calculés** — c'est ce qui garantit que le texte et le tableau de bord disent la même chose, et le modèle ne peut pas les contredire. Il ne reçoit aucun texte non révélé, rien au-delà de sept jours, rien de niveau 3, et rien du tout si l'un des deux n'a pas opté pour l'envoi de texte.

Repli : un gabarit purement SQL (`source = 'library'`) — « Cette semaine : 6 jours sur 7, 78 % d'accord, votre plus grand écart sur "projets". » Une semaine sans résumé, jamais ; une semaine sans activité ne produit pas de ligne du tout plutôt qu'un résumé creux (`check (char_length(body) >= 40)`).

---

### 4.8 Niveaux d'intimité, date night, dates clés

**Niveaux d'intimité.** Déblocage au **cumul de contenus complétés par les deux**, pas au streak : une série se casse, et reverrouiller du contenu déjà mérité est exactement le mauvais signal pour un produit dont la promesse est la douceur. Niveau 2 à 21 contenus complétés, niveau 3 à 60. `links.intimacy_cap` ne peut que **baisser**, et seul un accord des deux le relève — un membre ne doit pas pouvoir pousser l'autre vers l'intime.

Où la règle vit : ce n'est pas une règle de visibilité (un item de niveau 3 n'est jamais créé pour un couple de niveau 1, il n'y a rien à cacher), c'est une règle de **production**. Elle vit donc en base sous forme de **trigger**, et non de policy RLS — parce que `service_role` ne passe pas par la RLS, et que `service_role` **est** le générateur.

```sql
create or replace function public.enforce_item_intimacy()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_max smallint;
begin
  select least(l.intimacy, l.intimacy_cap) into v_max from public.links l where l.id = new.link_id;
  if new.intimacy_level > coalesce(v_max, 1) then raise exception 'intimacy_above_link_level'; end if;
  return new;
end $$;
create trigger daily_prompts_intimacy before insert or update on public.daily_prompts
  for each row execute function public.enforce_item_intimacy();
```

L'enum du schéma JSON contraint le modèle, le prompt système lui explique le niveau, le trigger refuse tout ce qui passe. Les deux premiers sont des optimisations ; seul le troisième est une garantie. L'UI n'applique aucune règle : elle affiche ce qu'elle reçoit.

**Date night.** Aucune table, aucune policy, aucune méthode d'écran nouvelle au-delà de `startDateNight(theme)` : une soirée est N items portant le même `bundle`. L'index unique est partiel (`where bundle is null`), donc les items de bundle échappent à la règle « un par type par jour » ; le streak les ignore pour la même raison (une date night ne compte pas comme journée quotidienne). `prompt_is_open` a une branche « 12 heures glissantes » pour les bundles, parce qu'une soirée déborde minuit. La révélation, l'archive et les réactions fonctionnent sans une ligne de code supplémentaire.

Trois bornes que le modèle seul ne donne pas et qu'il faut poser explicitement : **une date night s'ajoute à la journée, elle ne remplace jamais un item** (a fortiori jamais un item déjà répondu — supprimer un item cascade sur les réponses) ; **une par semaine et par lien** (`link_events`-style compteur, sinon un client en boucle vide le pool) ; et le lancement est unilatéral mais **notifie l'autre**, une soirée étant par définition bilatérale. Le contenu vient du pool, segment `bundle_theme is not null`, généré dans le même `pool-refill` — c'est une ligne de coût, elle est dans les 21 $/mois fixes.

**Dates clés.** `link_events` pour ce que le couple ajoute lui-même ; l'anniversaire de relation et les anniversaires de naissance sont **dérivés**, pas stockés (`links.started_on`, `profiles.birth_date`), par `upcoming_occasions(link_id, days)`. Un seul calcul, deux usages : `ai_context()` le transmet au générateur, qui peut faire converger la semaine vers l'occasion, et le cron de rappel l'interroge au passage — pas de cron supplémentaire. Le compteur « Ensemble depuis X jours » est `link_today(id) - started_on`, calculé **serveur** et renvoyé par la RPC du jour : le calculer côté client avec `new Date()` réintroduirait exactement l'horloge d'appareil que §4.3 supprime.

---

### 4.9 La frontière client

`src/lib/types.ts` :

```ts
export type ItemKind = 'question' | 'debate' | 'challenge';

export type DailyItem = {
  id: string; date: string;            // fournie par le serveur, jamais calculée
  kind: ItemKind; question: string; category: string;
  intimacyLevel: 1 | 2 | 3;
  options: { low?: string; high?: string; durationMin?: number };
  source: 'ai' | 'pool' | 'library';
  bundle: string | null;
};

export type Answer = {
  id: string; itemId: string; authorId: string; kind: ItemKind;
  body: string | null; stance: 1|2|3|4|5 | null; done: boolean | null;
  createdAt: string; reactions: string[];
};

/** La révélation est PAR item. */
export type ItemState = { item: DailyItem; mine: Answer | null; theirs: Answer | null; revealed: boolean };

export type TodayState = {
  date: string; streak: number; daysTogether: number | null;
  items: ItemState[];                  // 3, ordonnés débat → question → défi
  dateNight: ItemState[] | null;
};

export type AnswerInput =
  | { kind: 'question';  body: string }
  | { kind: 'debate';    stance: 1|2|3|4|5; body: string }
  | { kind: 'challenge'; done: boolean };
```

`src/lib/data/adapter.ts` — méthodes ajoutées, une seule signature modifiée :

```ts
  // modifiée
  submitAnswer(itemId: string, input: AnswerInput): Promise<Answer>;   // était (promptId, body: string)

  // onboarding et réglages
  getOnboarding(): Promise<OnboardingState>;
  saveOnboarding(patch: Partial<OnboardingState>): Promise<void>;
  updateLink(patch: { timeZone?: string; notifyHour?: number; intimacyCap?: 1|2|3; startedOn?: string }): Promise<Link>;
  setAiTextOptIn(on: boolean): Promise<void>;

  // statistiques, souvenirs, mémoire
  getStats(days?: number): Promise<LinkStats>;
  getRecaps(limit?: number): Promise<Recap[]>;
  getProfileDoc(): Promise<string | null>;
  clearProfileDoc(): Promise<void>;

  // notifications
  registerPushToken(token: string, platform: 'ios' | 'android'): Promise<void>;
  unregisterPushToken(token: string): Promise<void>;

  // dates clés et date night
  getLinkEvents(): Promise<LinkEvent[]>;
  addLinkEvent(input: NewLinkEvent): Promise<LinkEvent>;
  removeLinkEvent(id: string): Promise<void>;
  startDateNight(theme: string): Promise<ItemState[]>;

  // compte
  exportData(): Promise<ExportBundle>;
  deleteAccount(mode: 'anonymize' | 'erase'): Promise<void>;
```

`localDate` sort de l'export public (`src/lib/data/index.ts:10`). `getToday()` garde sa signature et n'envoie plus de date. Aucun écran n'importe `@/lib/supabase` ; le choix d'implémentation reste fait une seule fois (`src/lib/data/index.ts:8`).

**`demo.ts` reste jouable, et c'est lui qui prouve que la frontière est propre.** Quatre changements. (1) `ensurePrompt` devient `ensureItems(state, link, date)` et tire trois items de `src/lib/prompt-library.ts`, étendue à trois banques, avec le même hachage déterministe qu'aujourd'hui. (2) Camille répond **un item à la fois**, après un délai simulé, ce qui rend la révélation par contenu visible — c'est la mécanique la plus difficile à comprendre sans la voir. (3) Sa position est **dérivée** de la vôtre et non tirée au hasard (`stance = clamp(vous + [0,0,1,-1,2][hash(itemId) % 5])`), ce qui produit un taux d'accord d'environ 70 % avec de vraies divergences sur deux catégories : l'écran statistiques montre un graphe réel, pas des zéros. (4) `seedHistory` sème 30 jours au lieu de 3, pour que le premier résumé et le niveau 2 soient atteignables en démo. `getStats()` recalcule le même taux en TypeScript, `getRecaps()` sert un résumé de la banque locale, `registerPushToken` est un no-op. La génération étant devenue entièrement serveur, `demo.ts` **simplifie** : il n'a plus à simuler ni un `invoke` ni un repli, il n'a qu'à servir du contenu.

---

### 4.10 Plan de migration

Huit étapes, chacune déployable seule et laissant l'app fonctionnelle. `npm run typecheck` à chaque étape.

**Étape 0 — `0001_hardening.sql` — aucun changement d'UI, livrable aujourd'hui.** Le lot le plus urgent : ce sont des trous de sécurité sur des données déjà en production, et il ne dépend d'aucun choix produit. RPC `leave_link()` (retire l'adhésion, purge `invites`, supprime le lien s'il ne reste personne) et suppression de `link_members_delete` (`supabase/schema.sql:341`) ; `join_link` avec `perform 1 from links where id = v_link for update` avant le comptage et `delete from invites` à l'appairage ; `answers_update` avec `can_see_prompt` dans le `USING` ; trigger `answers_freeze_keys` ; `Anthropic({ timeout: 20_000, maxRetries: 1 })`. Côté client, **deux diffs** : `src/lib/data/supabase.ts:186` passe en `rpc('leave_link')`, et l'upsert de `src/lib/data/supabase.ts:320` passe en `ignoreDuplicates: true` (donc `on conflict do nothing`, qui ne requiert que le privilège INSERT). Zéro diff de type. Corriger au passage `src/lib/strings.ts:96`, qui promet « Vos souvenirs resteront » et devient un mensonge dès que `leave_link` supprime un lien vide : « Quitter ce lien ? Le code d'invitation sera révoqué. Si vous partez tous les deux, vos souvenirs seront supprimés. »

**Étape 1 — harnais de test RLS, bloquante.** Deux utilisateurs de test, `set local role authenticated` + `set local request.jwt.claims`, une vingtaine d'assertions (« B ne voit pas la réponse de A avant d'avoir répondu », « un ex-membre ne voit rien », « une réponse d'il y a trois mois n'est pas insérable », « aucune vue de `public` n'est lisible sans `security_invoker` »), exécutées en CI. `tsc --noEmit` ne compile pas une ligne de SQL, et les sept migrations qui suivent déplacent la règle centrale du produit. Sans ce harnais, ce sont sept paris.

**Étape 2 — `0002_server_day.sql`.** `links.time_zone`, `day_start_hour`, `notify_hour`, `locale` ; `link_today()` ; `link_streak` réécrite ; `my_link()` étendue à `today` et `time_zone` ; `prompt_is_open()` ; fenêtre J−1 sur `answers_insert` et gel `not partner_answered` sur `answers_update`. Suppression de `localDate()`, copie privée dans `demo.ts`. `max_tokens: 8192` et réflexion maintenue à `effort: 'low'` dans l'Edge Function. Migration de données : la valeur par défaut suffit, l'app pousse le fuseau réel à la première ouverture.

**Étape 3 — `0003_three_items.sql`.** `kind`, `options`, `intimacy_level`, `bundle`, `locale` sur `daily_prompts` ; `unique (id, kind)` ; `stance`, `done`, `kind` + FK composite sur `answers` ; `has_answered` substantielle avec clause de grand-père. Backfill : `kind = 'question'` partout, une seule instruction. **L'archive reste lisible telle quelle** — un jour passé à un seul item est un cas valide du nouveau modèle, et c'est le bénéfice principal de ne pas avoir refondu. Client : `ItemState[]`, `src/components/item-card.tsx`, `src/components/stance-choice.tsx`, accueil en liste de trois cartes, `history.tsx` groupé par date. `prompt-library.ts` gagne deux banques.

**Étape 4 — `0004_pool.sql` + `0005_onboarding.sql`.** `pool_items`, `library_items` (+ script de seed), `generation_jobs`, `job_runs`, `open_day()`, `fill_gaps()`, `pool-refill`, crons. `daily_prompts_insert` et `daily_prompts.pool_item_id` en même temps. `profile_onboarding`, `profiles.birth_date`/`ai_text_opt_in`, `links.started_on`/`objectives`/`interests`, réconciliation à l'appairage, écran `src/app/(app)/onboarding.tsx` placé sous la porte session mais avant la porte lien.

**Étape 5 — `0006_memory.sql`.** `ai_context()`, `couple-week`, `links.profile_doc`, suppression de `supabase/functions/daily-prompt` et de `functions.invoke` côté client.

**Étape 6 — `0007_push.sql`.** `push_tokens`, `notification_outbox`, trigger, `push_drain`, `push_receipts`, `_shared/strings.ts`, `npm run check:strings`, dépendance `expo-notifications`.

**Étape 7 — `0008_stats_recaps.sql`, puis `0009_events.sql`.** `debate_pairs`, `link_stats()`, `recaps`, écran statistiques ; `enforce_item_intimacy`, `links.intimacy`/`intimacy_cap` ; `link_events`, `upcoming_occasions()`, `src/app/(app)/date-night.tsx`.

#### Où tombe chacun des sept défauts

| # | Défaut | Étape | Mécanisme |
|---|---|---|---|
| 1 | Trois horloges | **2** | `links.time_zone` + `link_today()` ; `localDate()` supprimée ; `link_streak` en fuseau du lien |
| 2 | `answers_update` sans garde | **0** | `can_see_prompt` dans le `USING` + trigger `answers_freeze_keys` (anti-repointage) |
| 3 | Révélation contournable | **2** (gel + fenêtre J−1) puis **3** (substance) | `not partner_answered` et `prompt_is_open` ne dépendent que de `link_today` : le trou le plus exploitable est fermé une étape avant la refonte d'UI |
| 4 | Lien orphelin, code vivant | **0** | RPC `leave_link()` + `drop policy link_members_delete` |
| 5 | Upsert 42501 / écrasement | **0** (client, `ignoreDuplicates`) puis **4** (`daily_prompts_insert` supprimée, `on conflict do nothing` côté fonction) |
| 6 | Aucun timeout | **0** (SDK Anthropic) puis **5** (l'`invoke` disparaît : le problème est réglé par suppression) |
| 7 | TOCTOU `join_link` | **0** | `for update` sur `links` + `delete from invites` à l'appairage |
| *8* | *`max_tokens: 2048` avec réflexion active* | **2** | *défaut non listé, diagnostiqué en §4.4 : `max_tokens: 8192`, réflexion conservée* |

Cinq défauts sur sept tombent à l'étape 0, qui ne touche pas une ligne d'UI. La sécurité ne doit pas attendre le produit.

---

### 4.11 Ce que cette architecture ne traite pas

**Reporté — à faire, mais pas dans ces huit étapes.**

- **Suppression de compte, export, RGPD.** `answers.author_id ... on delete cascade` (`supabase/schema.sql:61`) est conservé tel quel : **quand un membre supprime son compte, il détruit la moitié de la capsule souvenirs de l'autre**, silencieusement. `deleteAccount(mode)` et `exportData()` sont dans le `DataAdapter` (§4.9) mais sans implémentation ni écran. La décision à prendre est produit avant d'être technique : suppression = anonymisation (`author_id` → tombstone, `body` conservé) ou destruction ? Et le `profile_doc` est une donnée personnelle exportable, pas seulement effaçable. À traiter avant la mise en production publique, pas après.
- **Le lien après une rupture.** `link_members_one_per_user` (`supabase/schema.sql:34`) + `already_linked` dans `create_link` et `join_link` + `leave_link` qui supprime le lien vide produisent une impasse : la personne qui reste ne peut ni créer ni rejoindre un lien, et sa seule sortie détruit l'archive. *Garder ses souvenirs* et *refaire sa vie dans l'app* sont mutuellement exclusifs. Correctif prévu mais non chiffré : `links.closed_at` (la colonne existe déjà, §4.1) + un lien actif et N liens archivés en lecture seule, donc la fin de l'index unique par utilisateur. Chantier de schéma non trivial.
- **Mode hors ligne.** L'app devient strictement dépendante du réseau, y compris pour relire l'archive. `submitAnswer` est un aller-retour sans file d'attente ni écriture optimiste ; une réponse perdue dans le métro casse le streak et bloque la révélation pour le partenaire, sans qu'il puisse savoir pourquoi. Décision à prendre : file locale avec rejeu (et alors, que fait `prompt_is_open` quand le rejeu arrive tard ?) ou assumer par écrit « il faut du réseau pour répondre ». Le comportement actuel — échouer silencieusement — n'est ni l'un ni l'autre.
- **Changement de fuseau en voyage.** `link_today()` est évaluée en direct : un Paris → Auckland peut sauter une bascule, un retour peut la dupliquer. Atténué (dates figées en colonne, tolérance de 48 h dans le streak, un changement par 24 h) mais pas résolu. La version propre est un historique `link_tz_periods(link_id, tz, from_date)`.
- **Coût Supabase.** Toute l'architecture transfère du travail d'Anthropic vers Postgres, et pas une ligne de facture Supabase n'est chiffrée. Le cron de rappel est un balayage non indexable de `links` (`extract(hour from (now() at time zone l.time_zone))` n'est pas indexable) : à 10 000 liens et 24 passages par jour, c'est un seq scan complet plus une sous-requête corrélée par ligne, en permanence. Correctif connu et non appliqué : une colonne `notify_slot smallint` indexée, calculée à l'écriture. À dimensionner avant les 1 000 premiers couples.
- **Observabilité.** `job_runs` est créée à l'étape 4 mais aucune alerte n'est branchée dessus. Or le repli bibliothèque rend toute panne **invisible** : si un `pg_cron` cesse de se déclencher, le symptôme est un contenu qui a exactement l'air normal. Deux métriques minimales à définir avec un seuil : taux de repli bibliothèque par jour, et nombre de liens sans contenu à l'heure du rappel.

**Hors périmètre — décidé, argumenté, non regretté.**

- **Le mode aléatoire.** Il reste un stub désactivé (`src/lib/strings.ts:39`). Ce n'est pas une valeur d'enum de plus, c'est un produit distinct qui partage une primitive : file d'appariement, signalement, blocage (et `blocks` devrait s'insérer dans `shares_link_with`, `supabase/schema.sql:96` — donc modifier la fonction dont dépend toute la visibilité des profils), vérification d'âge, et surtout **modération**. Le point dur est structurel : la révélation étant une règle de base de données, une réponse abusive est lisible dès que la victime a répondu. Modérer avant révélation contredit l'invariant ; modérer après ne protège personne. Aucune option n'est gratuite. Par ailleurs la mémoire de personnalisation, le compteur « ensemble depuis » et le résumé hebdomadaire n'ont aucun sens entre deux inconnus. Recommandation : laisser « Bientôt » et ne rien construire dessus tant que la boucle couple n'est pas rentable.
- **L'internationalisation réelle.** `locale` est posée maintenant sur `links`, `pool_items` et `daily_prompts` — c'est une colonne aujourd'hui et une repartition complète plus tard, parce que le pool est segmenté et sélectionné par ces colonnes. Mais la copie visible vivra dans cinq endroits (`src/lib/strings.ts`, `_shared/strings.ts`, le `SYSTEM_PROMPT`, le pool, `prompt-library.ts`) et rien n'est prévu pour les tenir cohérents au-delà du `check:strings`. Décision : UsLink est francophone en v1 ; la colonne existe pour que l'anglais ne soit pas une refonte.
- **Le curseur d'accessibilité.** Trancé plutôt qu'ignoré : la position du débat se saisit en **cinq boutons radio**, pas en curseur. Un curseur React Native exige `accessibilityRole="adjustable"`, `accessibilityValue` et des `accessibilityActions`, sans quoi il est inatteignable sous VoiceOver et TalkBack ; cinq radios sont accessibles par construction et réutilisent le patron déjà en place (`src/app/(app)/pair.tsx:142`, `src/app/(app)/(tabs)/profile.tsx:82`). À ajouter à `AGENTS.md` au même titre que la clause light/dark, sinon la règle ne survivra pas aux huit étapes. La révélation ne doit pas non plus reposer sur la seule couleur (`src/constants/theme.ts` distingue `mine` et `theirs`) : le libellé de l'auteur reste obligatoire.

**À trancher par le propriétaire — trois décisions que l'architecture ne peut pas prendre à sa place.**

1. **Le contenu est-il daté ou séquencé ?** Toute la §4.3 défend un jour civil serveur, et trois des sujets reportés ci-dessus (voyage, falaise de minuit, fenêtre d'écriture) en découlent. L'alternative existe : une séquence `(link_id, seq)`, le lot *n* s'ouvrant quand le lot *n−1* est bouclé, le streak calculé dans le fuseau de chaque personne. Le défaut n°1 disparaîtrait sans horloge partagée. Ce n'est pas retenu parce que le rappel du soir, le journal daté et le compteur sont des notions calendaires dans la vision — mais c'est la décision la plus structurante du dossier, et elle mérite d'être prise consciemment plutôt que héritée du schéma existant.
2. **Le « % d'accord » vaut-il le modèle polymorphe ?** C'est la première source de complexité de tout ce qui précède : `stance`, `kind` dénormalisé, clé étrangère composite, `CHECK` discriminé, colonnes nullables. Dans la vision, « statistiques fun » est le sixième point d'une liste de huit et le seul explicitement qualifié de *fun*. Il existe une v1 beaucoup moins chère : après révélation, une question à un tap — « d'accord ? » — répondue par le couple lui-même. Position retenue ici : garder le curseur, parce qu'un débat sans position mesurable n'est pas un débat, c'est une seconde question, et le type perd sa raison d'être. Mais si le propriétaire coupe le débat de la v1, **la moitié de la §4.1 disparaît**.
3. **Le consentement à l'envoi de texte est en `default false`.** Cela veut dire qu'à l'installation, la personnalisation repose sur les signaux dérivés (catégories, positions, complétion) et pas sur les mots. C'est le seul défaut défendable pour l'envoi de texte intime à une API tierce, et il n'éteint aucune fonctionnalité — mais il rend la priorité n°2 de la vision moins spectaculaire tant que les deux membres n'ont pas coché. Un `default true` avec un écran d'explication à l'onboarding est un choix possible ; c'est un arbitrage produit et juridique, pas technique.