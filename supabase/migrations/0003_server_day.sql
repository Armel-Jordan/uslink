-- Étape 2 — le jour devient une notion serveur. Voir docs/architecture.md §4.3.
--
-- Défaut 1 : trois horloges. `localDate()` renvoyait le jour civil de
-- l'APPAREIL et servait de clé à daily_prompts.prompt_date, pendant que
-- link_streak comptait en current_date (UTC serveur). Deux partenaires dans
-- deux fuseaux créaient deux lignes distinctes dont la révélation ne devenait
-- JAMAIS vraie, et la série se cassait sur un jour où les deux avaient répondu.
--
-- Défaut 3, première moitié : answers_insert n'avait aucune fenêtre temporelle,
-- donc répondre aujourd'hui à un prompt d'il y a trois mois déverrouillait
-- rétroactivement toute l'archive du partenaire ; et answers_update laissait
-- réécrire sa réponse après avoir lu celle de l'autre. La substance exigée
-- (« . » ne compte pas comme une réponse) reste pour l'étape 3.

begin;

-- ------------------------------------------------------------------ horloge
-- Le fuseau vit sur le LIEN et non sur la personne : le jour est l'unité de
-- co-présence. Si chacun avait le sien, on retomberait exactement sur le
-- défaut qu'on ferme. Contrepartie assumée : un couple à distance vit sur une
-- seule horloge, et l'app doit le dire.

alter table public.links
  add column if not exists time_zone text not null default 'Europe/Paris',
  -- La journée bascule à 4 h locales, pas à minuit : sans ça une réponse à
  -- 00 h 30 tombe dans le lendemain et casse une série à tort.
  add column if not exists day_start_hour smallint not null default 4,
  add column if not exists time_zone_changed_at timestamptz;

alter table public.links drop constraint if exists links_day_start_hour_check;
alter table public.links
  add constraint links_day_start_hour_check check (day_start_hour between 0 and 8);

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

/**
 * Le jour civil du lien. Seule définition du « aujourd'hui » du produit.
 *
 * `now() at time zone tz` rend l'heure murale locale sous forme de timestamp
 * sans fuseau ; en retrancher un intervalle fixe puis tronquer est monotone,
 * donc le décalage de bascule ne peut ni sauter ni dupliquer un jour.
 * Vérifié sur Postgres 18 en balayant les transitions d'heure d'été et d'hiver
 * à Paris toutes les 7 minutes, pour chaque valeur autorisée de
 * day_start_hour (0 à 8) : suite de jours strictement consécutifs dans tous
 * les cas. Vérifié aussi aux décalages non entiers (Asia/Kolkata +5:30,
 * Australia/Eucla +8:45) et aux extrêmes (Pacific/Kiritimati +14,
 * Pacific/Midway −11).
 */
create or replace function public.link_today(p_link uuid)
returns date language sql stable security definer set search_path = public as $$
  select ((now() at time zone l.time_zone) - make_interval(hours => l.day_start_hour))::date
  from public.links l where l.id = p_link;
$$;

grant execute on function public.link_today(uuid) to authenticated;

-- ------------------------------------------------- fenêtre d'écriture

/** Le partenaire a-t-il déjà répondu ? Sert à geler ma propre réponse. */
create or replace function public.partner_answered(p_prompt uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.answers
    where prompt_id = p_prompt and author_id <> auth.uid()
  );
$$;

grant execute on function public.partner_answered(uuid) to authenticated;

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

grant execute on function public.prompt_is_open(uuid) to authenticated;

-- Fenêtre à l'insertion : ferme le déverrouillage rétroactif de l'archive.
drop policy if exists answers_insert on public.answers;
create policy answers_insert on public.answers for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.can_see_prompt(prompt_id)
    and public.prompt_is_open(prompt_id)
  );

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

-- Le repli client ne peut plus fabriquer une question hors de la fenêtre.
drop policy if exists daily_prompts_insert on public.daily_prompts;
create policy daily_prompts_insert on public.daily_prompts for insert to authenticated
  with check (
    public.is_link_member(link_id)
    and prompt_date between public.link_today(link_id) - 1 and public.link_today(link_id)
  );

-- --------------------------------------------------------------- la série

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

-- ------------------------------------------------------------------- RPCs

-- Le fuseau est choisi à la création, depuis l'appareil du créateur.
drop function if exists public.create_link(text);
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

grant execute on function public.set_link_time_zone(text) to authenticated;

-- my_link() porte désormais le jour et le fuseau : le client n'a plus aucune
-- raison de calculer une date, et n'en a plus le droit.
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

grant execute on function public.my_link() to authenticated;
grant execute on function public.create_link(text, text) to authenticated;

commit;
