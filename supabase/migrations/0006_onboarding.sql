-- Étape 4a — l'onboarding et le compteur de relation.
--
-- DEUX TABLES, PAS UNE, et c'est le point de conception central : la RLS
-- Postgres filtre par LIGNE, pas par colonne. Ajouter `city` ou la date de
-- naissance exacte à `profiles` les exposerait au partenaire via
-- `profiles_select`, qu'on le veuille ou non. Ce qui est personnel vit donc
-- dans une table que seul son propriétaire lit ; ce qui est partagé (le
-- prénom, le jour d'anniversaire) reste sur `profiles`.

begin;

-- ------------------------------------------------------- données personnelles

create table if not exists public.profile_onboarding (
  id uuid primary key references auth.users on delete cascade,
  birth_date date,
  city text check (char_length(city) <= 60),
  -- Dérivée côté serveur de la ville : c'est `region` qui part vers le
  -- modèle, jamais la ville elle-même.
  region text check (char_length(region) <= 60),
  interests text[] not null default '{}',
  goals text[] not null default '{}',
  relationship_started_on date,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.profile_onboarding drop constraint if exists profile_onboarding_interests_check;
alter table public.profile_onboarding add constraint profile_onboarding_interests_check
  check (
    coalesce(array_length(interests, 1), 0) <= 12
    and interests <@ array['cuisine','voyage','sport','musique','cinema','lecture',
                           'jeux','nature','art','tech','bienetre','sorties']
  );

alter table public.profile_onboarding drop constraint if exists profile_onboarding_goals_check;
alter table public.profile_onboarding add constraint profile_onboarding_goals_check
  check (goals <@ array['complicite','decouverte','fun']);

-- Une date de relation dans le futur n'a pas de sens, et rendrait le compteur
-- négatif sur l'accueil.
alter table public.profile_onboarding drop constraint if exists profile_onboarding_dates_check;
alter table public.profile_onboarding add constraint profile_onboarding_dates_check
  check (
    (birth_date is null or birth_date < current_date)
    and (relationship_started_on is null or relationship_started_on <= current_date)
  );

alter table public.profile_onboarding enable row level security;

-- Personne d'autre. Pas même le partenaire.
drop policy if exists profile_onboarding_own on public.profile_onboarding;
create policy profile_onboarding_own on public.profile_onboarding for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Le jour d'anniversaire, lui, est partagé : il sert au rappel côté partenaire.
-- Il vit donc sur `profiles`, que `profiles_select` expose au conjoint.
alter table public.profiles add column if not exists birth_date date;
alter table public.profiles drop constraint if exists profiles_birth_date_check;
alter table public.profiles add constraint profiles_birth_date_check
  check (birth_date is null or birth_date < current_date);

-- ------------------------------------------------------------ le couple

alter table public.links
  add column if not exists started_on date,
  add column if not exists interests text[] not null default '{}',
  add column if not exists objectives text[] not null default '{}';

alter table public.links drop constraint if exists links_started_on_check;
alter table public.links add constraint links_started_on_check
  check (started_on is null or started_on <= current_date);

/** Jours ensemble. Calculé serveur : `new Date()` côté client réintroduirait
    l'horloge d'appareil que l'étape 2 a supprimée. */
create or replace function public.days_together(p_link uuid)
returns integer language sql stable security definer set search_path = public as $$
  select case when l.started_on is null then null
              else greatest(0, (public.link_today(l.id) - l.started_on))::int end
  from public.links l where l.id = p_link;
$$;

grant execute on function public.days_together(uuid) to authenticated;

/**
 * Choisir la date de début du couple. Les deux membres ont pu saisir des dates
 * différentes à l'onboarding : le compteur est affiché aux DEUX, sa provenance
 * ne peut pas être un « dernier écrivain gagne » silencieux. L'écran d'appairage
 * montre les deux et demande de trancher.
 */
create or replace function public.set_link_started_on(p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare v_link uuid := public.my_link_id();
begin
  if v_link is null then
    raise exception 'no_link';
  end if;
  if p_date > current_date then
    raise exception 'invalid_date';
  end if;
  update public.links set started_on = p_date where id = v_link;
end $$;

grant execute on function public.set_link_started_on(date) to authenticated;

-- ------------------------------------------- réconciliation à l'appairage

/**
 * Au moment où le second membre rejoint, on fusionne ce que chacun a déclaré :
 * l'UNION des centres d'intérêt et des objectifs (si l'un veut du fun et
 * l'autre de la profondeur, la semaine contient les deux plutôt que rien), et
 * la date de relation du créateur — que l'écran d'appairage laisse corriger.
 */
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

  perform 1 from public.links where id = v_link for update;
  if not found then
    raise exception 'invalid_code';
  end if;

  select count(*) into v_members from public.link_members where link_id = v_link;
  if v_members >= 2 then
    raise exception 'link_full';
  end if;

  insert into public.link_members (link_id, user_id) values (v_link, v_uid);
  delete from public.invites where link_id = v_link;

  -- Fusion des déclarations des deux membres.
  update public.links l
  set interests = (
        select coalesce(array_agg(distinct x), '{}')
        from public.profile_onboarding po
        join public.link_members m on m.user_id = po.id and m.link_id = l.id,
             unnest(po.interests) x
      ),
      objectives = (
        select coalesce(array_agg(distinct x), '{}')
        from public.profile_onboarding po
        join public.link_members m on m.user_id = po.id and m.link_id = l.id,
             unnest(po.goals) x
      ),
      started_on = coalesce(
        l.started_on,
        (select po.relationship_started_on from public.profile_onboarding po
          where po.id = v_creator),
        (select po.relationship_started_on from public.profile_onboarding po
          where po.id = v_uid)
      )
  where l.id = v_link;

  return v_link;
end $$;

-- my_link() porte le compteur, comme elle porte le jour et le fuseau.
drop function if exists public.my_link();
create or replace function public.my_link()
returns table (
  link_id uuid,
  mode text,
  created_at timestamptz,
  invite_code text,
  time_zone text,
  day_start_hour smallint,
  today date,
  locale text,
  started_on date,
  days_together integer,
  partner_started_on date,
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
    l.locale,
    l.started_on,
    public.days_together(l.id),
    -- Ce que l'AUTRE a déclaré, pour que l'écran puisse proposer de trancher
    -- quand les deux dates diffèrent. Rien d'autre de sa table personnelle.
    (select po.relationship_started_on from public.profile_onboarding po where po.id = p.id),
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

grant execute on function public.my_link() to authenticated;

commit;
