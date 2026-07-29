-- UsLink schema.
-- Run once in the Supabase SQL editor (or `supabase db push`) for a fresh project.
--
-- Model: two people share a "link". A link gets one prompt per calendar day.
-- Each person writes one answer. The partner's answer is only readable once you
-- have written yours — that gate is enforced in RLS, not in the client.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- tables

create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default 'Moi',
  avatar_emoji text not null default '☀️',
  created_at timestamptz not null default now()
);

create table if not exists public.links (
  id uuid primary key default gen_random_uuid(),
  mode text not null default 'couple' check (mode in ('couple', 'friends', 'random')),
  created_by uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  -- Le fuseau vit sur le LIEN et non sur la personne : le jour est l'unité de
  -- co-présence. Si chacun avait le sien, deux partenaires dans deux fuseaux
  -- auraient deux journées, donc deux questions, et la révélation ne
  -- deviendrait jamais vraie.
  time_zone text not null default 'Europe/Paris',
  -- La journée bascule à 4 h locales, pas à minuit : sans ça une réponse à
  -- 00 h 30 tombe dans le lendemain et casse une série à tort.
  day_start_hour smallint not null default 4
    constraint links_day_start_hour_check check (day_start_hour between 0 and 8),
  time_zone_changed_at timestamptz
);

create table if not exists public.link_members (
  link_id uuid not null references public.links on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (link_id, user_id)
);

-- v1 rule: a person belongs to at most one link at a time.
create unique index if not exists link_members_one_per_user on public.link_members (user_id);

create table if not exists public.invites (
  code text primary key,
  link_id uuid not null references public.links on delete cascade,
  created_by uuid not null references auth.users on delete cascade,
  expires_at timestamptz not null default now() + interval '7 days',
  created_at timestamptz not null default now()
);

create table if not exists public.daily_prompts (
  id uuid primary key default gen_random_uuid(),
  link_id uuid not null references public.links on delete cascade,
  prompt_date date not null,
  question text not null,
  category text not null default 'général',
  source text not null default 'library' check (source in ('ai', 'library')),
  created_at timestamptz not null default now(),
  unique (link_id, prompt_date)
);

create index if not exists daily_prompts_link_date_idx
  on public.daily_prompts (link_id, prompt_date desc);

create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  prompt_id uuid not null references public.daily_prompts on delete cascade,
  author_id uuid not null references auth.users on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (prompt_id, author_id)
);

create index if not exists answers_prompt_idx on public.answers (prompt_id);

create table if not exists public.reactions (
  id uuid primary key default gen_random_uuid(),
  answer_id uuid not null references public.answers on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  -- Borné : sans longueur maximale, « emoji » est un champ de texte libre
  -- affiché dans les Souvenirs de l'autre. Nommée explicitement pour que ce
  -- fichier et 0001_hardening.sql produisent le même schéma.
  emoji text not null
    constraint reactions_emoji_shape check (char_length(emoji) between 1 and 8),
  created_at timestamptz not null default now(),
  unique (answer_id, user_id, emoji)
);

-- ------------------------------------------------------- helper functions
-- All security definer so RLS policies can call them without recursing into
-- the policies of the tables they read.

create or replace function public.my_link_id()
returns uuid language sql stable security definer set search_path = public as $$
  select link_id from public.link_members where user_id = auth.uid() limit 1;
$$;

create or replace function public.is_link_member(p_link uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.link_members
    where link_id = p_link and user_id = auth.uid()
  );
$$;

create or replace function public.shares_link_with(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.link_members me
    join public.link_members other on other.link_id = me.link_id
    where me.user_id = auth.uid() and other.user_id = p_user
  );
$$;

create or replace function public.can_see_prompt(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.daily_prompts p
    join public.link_members m on m.link_id = p.link_id
    where p.id = p_prompt and m.user_id = auth.uid()
  );
$$;

/**
 * Le jour civil du lien. Seule définition du « aujourd'hui » du produit.
 *
 * `now() at time zone tz` rend l'heure murale locale sous forme de timestamp
 * sans fuseau ; en retrancher un intervalle fixe puis tronquer est monotone,
 * donc le décalage de bascule ne peut ni sauter ni dupliquer un jour. Vérifié
 * en balayant les transitions d'heure d'été et d'hiver toutes les 7 minutes,
 * pour chaque valeur autorisée de day_start_hour, ainsi qu'aux décalages non
 * entiers (+5:30, +8:45) et aux extrêmes (+14, −11).
 */
create or replace function public.link_today(p_link uuid)
returns date language sql stable security definer set search_path = public as $$
  select ((now() at time zone l.time_zone) - make_interval(hours => l.day_start_hour))::date
  from public.links l where l.id = p_link;
$$;

/** Le partenaire a-t-il déjà répondu ? Sert à geler ma propre réponse. */
create or replace function public.partner_answered(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.answers
    where prompt_id = p_prompt and author_id <> auth.uid()
  );
$$;

/**
 * Fenêtre d'écriture : J−1, J, J+1. Au-delà, l'archive est close.
 *
 * J−1 est la tolérance de celui qui répond juste après la bascule. J+1 est la
 * tolérance à un DÉPLACEMENT D'HORLOGE : `set_link_time_zone` vers l'ouest
 * recule link_today d'un jour, et sans cette borne la question déjà ouverte —
 * peut-être déjà à moitié répondue — sortirait de la fenêtre et deviendrait
 * non répondable POUR LES DEUX membres, pendant que le verrou de 24 h
 * interdirait de revenir en arrière. J+1 n'ouvre rien : une question datée de
 * demain n'existe que si l'horloge a reculé, `daily_prompts_insert` restant
 * borné à [J−1, J].
 */
create or replace function public.prompt_is_open(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.daily_prompts p
    where p.id = p_prompt
      and p.prompt_date between public.link_today(p.link_id) - 1
                            and public.link_today(p.link_id) + 1
  );
$$;

create or replace function public.has_answered(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.answers
    where prompt_id = p_prompt and author_id = auth.uid()
  );
$$;

create or replace function public.can_see_answer(p_answer uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.answers a
    where a.id = p_answer
      and (
        a.author_id = auth.uid()
        or (public.can_see_prompt(a.prompt_id) and public.has_answered(a.prompt_id))
      )
  );
$$;

-- --------------------------------------------------------------- triggers

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Moi'))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Un CHECK ne peut pas interroger pg_timezone_names : la validation passe par
-- un trigger.
--
-- Et il faut bien interroger pg_timezone_names : `at time zone` ne valide
-- RIEN d'utilisable. Il accepte les spécifications POSIX en INVERSANT leur
-- signe — 'GMT+02:00' installe une horloge à UTC−2, 'UTC-5' à UTC+5 — et il
-- accepte même 'FOO7'. Un couple se retrouverait avec une horloge fausse de
-- plusieurs heures, sans changement d'heure, et sans la moindre erreur.
create or replace function public.links_check_time_zone()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from pg_timezone_names where name = new.time_zone) then
    raise exception 'invalid_time_zone';
  end if;
  return new;
end $$;

drop trigger if exists links_validate_time_zone on public.links;
create trigger links_validate_time_zone
  before insert or update of time_zone on public.links
  for each row execute function public.links_check_time_zone();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists answers_touch_updated_at on public.answers;
create trigger answers_touch_updated_at
  before update on public.answers
  for each row execute function public.touch_updated_at();

-- Un WITH CHECK valide la ligne finale ; il n'empêche pas de repointer une clé.
-- Sans ce garde-fou, un membre peut déplacer sa propre réponse vers le prompt
-- d'un autre lien, où elle s'affiche comme la réponse du partenaire.
create or replace function public.answers_freeze_keys()
returns trigger language plpgsql as $$
begin
  if new.id is distinct from old.id
     or new.prompt_id is distinct from old.prompt_id
     or new.author_id is distinct from old.author_id
     or new.created_at is distinct from old.created_at then
    raise exception 'immutable_answer_key';
  end if;
  return new;
end $$;

drop trigger if exists answers_no_repoint on public.answers;
create trigger answers_no_repoint
  before update on public.answers
  for each row execute function public.answers_freeze_keys();

-- ------------------------------------------------------------------- RPCs

create or replace function public.new_invite_code()
returns text language plpgsql security definer set search_path = public as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no I/O/0/1
  candidate text;
  attempt int := 0;
begin
  loop
    candidate := '';
    for i in 1..6 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.invites where code = candidate);
    attempt := attempt + 1;
    if attempt > 20 then
      raise exception 'could not allocate invite code';
    end if;
  end loop;
  return candidate;
end $$;

create or replace function public.create_link(p_mode text default 'couple', p_time_zone text default null)
returns table (link_id uuid, invite_code text)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_link uuid;
  v_code text;
  v_mode text := coalesce(p_mode, 'couple');
  v_tz text := coalesce(nullif(btrim(p_time_zone), ''), 'Europe/Paris');
begin
  if v_uid is null then
    raise exception 'auth';
  end if;
  if exists (select 1 from public.link_members where user_id = v_uid) then
    raise exception 'already_linked';
  end if;
  if v_mode not in ('couple', 'friends', 'random') then
    v_mode := 'couple';
  end if;

  insert into public.links (mode, created_by, time_zone)
  values (v_mode, v_uid, v_tz) returning id into v_link;
  insert into public.link_members (link_id, user_id) values (v_link, v_uid);
  v_code := public.new_invite_code();
  insert into public.invites (code, link_id, created_by) values (v_code, v_link, v_uid);

  return query select v_link, v_code;
end $$;

create or replace function public.join_link(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_link uuid;
  v_creator uuid;
  v_members int;
begin
  if v_uid is null then
    raise exception 'auth';
  end if;
  if exists (select 1 from public.link_members where user_id = v_uid) then
    raise exception 'already_linked';
  end if;

  select i.link_id, i.created_by into v_link, v_creator
  from public.invites i
  where i.code = upper(btrim(p_code)) and i.expires_at > now();

  if v_link is null then
    raise exception 'invalid_code';
  end if;
  if v_creator = v_uid then
    raise exception 'own_code';
  end if;

  -- Verrou : sans lui, deux sessions rejouant le même code passent toutes les
  -- deux le comptage et font entrer un troisième membre. Si la ligne a disparu
  -- entre-temps, `for update` ne verrouille rien — d'où le test.
  perform 1 from public.links where id = v_link for update;
  if not found then
    raise exception 'invalid_code';
  end if;

  select count(*) into v_members from public.link_members where link_id = v_link;
  if v_members >= 2 then
    raise exception 'link_full';
  end if;

  insert into public.link_members (link_id, user_id) values (v_link, v_uid);

  -- Le code est consommé : un lien complet n'est plus rejoignable, même si la
  -- capture d'écran circule encore.
  delete from public.invites where link_id = v_link;

  return v_link;
end $$;

/**
 * Quitter son lien. Passe obligatoirement par ici plutôt que par un DELETE
 * client sur link_members : seule cette fonction purge les invites (sinon le
 * code rouvre un lien redevenu à un membre) et ramasse un lien vide.
 */
create or replace function public.leave_link()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_link uuid;
  v_left int;
begin
  if v_uid is null then
    raise exception 'auth';
  end if;

  select link_id into v_link from public.link_members where user_id = v_uid;
  if v_link is null then
    return; -- déjà sans lien : idempotent
  end if;

  perform 1 from public.links where id = v_link for update;
  if not found then
    return; -- le lien a déjà disparu : rien à nettoyer
  end if;

  delete from public.link_members where user_id = v_uid and link_id = v_link;
  delete from public.invites where link_id = v_link;

  select count(*) into v_left from public.link_members where link_id = v_link;
  if v_left = 0 then
    -- cascade : invites, daily_prompts, answers, reactions
    delete from public.links where id = v_link;
  end if;
end $$;

/**
 * Un code est consommé à l'appairage et purgé au départ d'un membre. Sans ce
 * chemin, le membre restant se retrouve sur l'écran d'invitation sans rien à
 * partager, et sa seule sortie est de détruire l'archive.
 */
create or replace function public.regenerate_invite()
returns text language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_link uuid;
  v_members int;
  v_code text;
begin
  if v_uid is null then
    raise exception 'auth';
  end if;

  select link_id into v_link from public.link_members where user_id = v_uid;
  if v_link is null then
    raise exception 'no_link';
  end if;

  perform 1 from public.links where id = v_link for update;
  if not found then
    raise exception 'no_link';
  end if;

  select count(*) into v_members from public.link_members where link_id = v_link;
  if v_members >= 2 then
    raise exception 'link_full';
  end if;

  delete from public.invites where link_id = v_link;
  v_code := public.new_invite_code();
  insert into public.invites (code, link_id, created_by) values (v_code, v_link, v_uid);
  return v_code;
end $$;

/**
 * Changer l'horloge du couple. Explicite, jamais automatique : un voyage ne
 * doit pas déplacer la journée de l'autre sans qu'il l'ait voulu. Une fois par
 * 24 h, pour qu'un aller-retour ne puisse pas fabriquer ou effacer des jours.
 */
create or replace function public.set_link_time_zone(p_time_zone text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_link uuid := public.my_link_id();
  v_last timestamptz;
begin
  if v_link is null then
    raise exception 'no_link';
  end if;

  select time_zone_changed_at into v_last from public.links where id = v_link;
  if v_last is not null and v_last > now() - interval '24 hours' then
    raise exception 'time_zone_cooldown';
  end if;

  update public.links
  set time_zone = p_time_zone, time_zone_changed_at = now()
  where id = v_link;
end $$;

-- Porte le jour et le fuseau : le client n'a plus aucune raison de calculer
-- une date, et n'en a plus le droit.
create or replace function public.my_link()
returns table (
  link_id uuid,
  mode text,
  created_at timestamptz,
  invite_code text,
  time_zone text,
  day_start_hour smallint,
  today date,
  partner_id uuid,
  partner_name text,
  partner_emoji text
)
language sql stable security definer set search_path = public as $$
  select
    l.id,
    l.mode,
    l.created_at,
    (select i.code from public.invites i where i.link_id = l.id order by i.created_at desc limit 1),
    l.time_zone,
    l.day_start_hour,
    public.link_today(l.id),
    p.id,
    p.display_name,
    p.avatar_emoji
  from public.link_members me
  join public.links l on l.id = me.link_id
  left join public.link_members other
    on other.link_id = l.id and other.user_id <> me.user_id
  left join public.profiles p on p.id = other.user_id
  where me.user_id = auth.uid()
  limit 1;
$$;

/**
 * Jours consécutifs, DANS LE FUSEAU DU LIEN, où les deux ont répondu. Hier
 * compte encore pour que la série ne casse pas avant la réponse du jour ;
 * ancrée sur current_date (UTC), cette grâce était consommée par le décalage
 * et un utilisateur nord-américain voyait 0 dès la fin d'après-midi.
 */
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
    where p.link_id = p_link_id and p.prompt_date = v_date;

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

-- --------------------------------------------------------------------- RLS

alter table public.profiles enable row level security;
alter table public.links enable row level security;
alter table public.link_members enable row level security;
alter table public.invites enable row level security;
alter table public.daily_prompts enable row level security;
alter table public.answers enable row level security;
alter table public.reactions enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_link_with(id));

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists links_select on public.links;
create policy links_select on public.links for select to authenticated
  using (public.is_link_member(id));

drop policy if exists link_members_select on public.link_members;
create policy link_members_select on public.link_members for select to authenticated
  using (link_id = public.my_link_id());

-- Pas de policy DELETE sur link_members : quitter un lien passe par la RPC
-- leave_link(), qui seule purge les invites et supprime un lien devenu vide.
drop policy if exists link_members_delete on public.link_members;

drop policy if exists invites_select on public.invites;
create policy invites_select on public.invites for select to authenticated
  using (public.is_link_member(link_id));

drop policy if exists daily_prompts_select on public.daily_prompts;
create policy daily_prompts_select on public.daily_prompts for select to authenticated
  using (public.is_link_member(link_id));

-- Members may insert the day's prompt themselves: that is the client-side
-- fallback when the Edge Function is unavailable. Borné à la fenêtre du jour :
-- sans ça un membre fabrique des questions à n'importe quelle date.
drop policy if exists daily_prompts_insert on public.daily_prompts;
create policy daily_prompts_insert on public.daily_prompts for insert to authenticated
  with check (
    public.is_link_member(link_id)
    and prompt_date between public.link_today(link_id) - 1 and public.link_today(link_id)
  );

drop policy if exists answers_select on public.answers;
create policy answers_select on public.answers for select to authenticated
  using (
    author_id = auth.uid()
    or (public.can_see_prompt(prompt_id) and public.has_answered(prompt_id))
  );

-- Fenêtre à l'insertion : ferme le déverrouillage rétroactif de l'archive.
drop policy if exists answers_insert on public.answers;
create policy answers_insert on public.answers for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.can_see_prompt(prompt_id)
    and public.prompt_is_open(prompt_id)
  );

-- can_see_prompt des deux côtés : un ex-membre perd l'écriture sur ses
-- anciennes réponses, et ne peut pas les déplacer vers un autre lien.
-- Gel à la révélation : une fois que l'autre a répondu, ma réponse est figée.
-- C'est ce qui rend le contournement coûteux — tricher coûte définitivement sa
-- propre réponse du jour, affichée à l'autre et archivée.
drop policy if exists answers_update on public.answers;
create policy answers_update on public.answers for update to authenticated
  using (
    author_id = auth.uid()
    and public.can_see_prompt(prompt_id)
    and public.prompt_is_open(prompt_id)
    and not public.partner_answered(prompt_id)
  )
  with check (author_id = auth.uid() and public.can_see_prompt(prompt_id));

drop policy if exists reactions_select on public.reactions;
create policy reactions_select on public.reactions for select to authenticated
  using (public.can_see_answer(answer_id));

-- can_see_answer accorde l'accès dès `author_id = auth.uid()`, sans condition
-- d'appartenance : sans can_see_prompt, un ex-membre peut encore écrire des
-- « réactions » sur ses propres anciennes réponses, rendues telles quelles dans
-- les Souvenirs du partenaire resté.
drop policy if exists reactions_insert on public.reactions;
create policy reactions_insert on public.reactions for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.can_see_answer(answer_id)
    and public.can_see_prompt((select a.prompt_id from public.answers a where a.id = answer_id))
  );

drop policy if exists reactions_delete on public.reactions;
create policy reactions_delete on public.reactions for delete to authenticated
  using (user_id = auth.uid());

-- ------------------------------------------------------------------ grants

revoke all on function public.new_invite_code() from public, anon, authenticated;

grant execute on function public.create_link(text, text) to authenticated;
grant execute on function public.join_link(text) to authenticated;
grant execute on function public.leave_link() to authenticated;
grant execute on function public.regenerate_invite() to authenticated;
grant execute on function public.set_link_time_zone(text) to authenticated;
grant execute on function public.my_link() to authenticated;
grant execute on function public.link_today(uuid) to authenticated;
grant execute on function public.partner_answered(uuid) to authenticated;
grant execute on function public.prompt_is_open(uuid) to authenticated;
grant execute on function public.link_streak(uuid) to authenticated;
grant execute on function public.my_link_id() to authenticated;
grant execute on function public.is_link_member(uuid) to authenticated;
grant execute on function public.shares_link_with(uuid) to authenticated;
grant execute on function public.can_see_prompt(uuid) to authenticated;
grant execute on function public.has_answered(uuid) to authenticated;
grant execute on function public.can_see_answer(uuid) to authenticated;
