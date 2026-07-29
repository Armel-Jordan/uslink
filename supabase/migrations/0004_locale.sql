-- Étape 2b — la langue du couple.
--
-- Le lien porte déjà une horloge ; il porte maintenant une langue, pour la même
-- raison : deux personnes partagent un contenu, donc une langue. Sans elle,
-- l'Edge Function écrirait la question du jour en français sous une interface
-- en japonais.

begin;

alter table public.links
  add column if not exists locale text not null default 'fr';

alter table public.links drop constraint if exists links_locale_check;
alter table public.links
  add constraint links_locale_check check (locale in ('fr', 'es', 'pt', 'it', 'ar', 'zh', 'ja'));

/** Changer la langue du couple. Comme le fuseau : explicite, jamais deviné. */
create or replace function public.set_link_locale(p_locale text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_link uuid := public.my_link_id();
begin
  if v_link is null then
    raise exception 'no_link';
  end if;
  update public.links set locale = p_locale where id = v_link;
exception when check_violation then
  raise exception 'invalid_locale';
end $$;

grant execute on function public.set_link_locale(text) to authenticated;

-- La langue est choisie à la création, depuis l'appareil du créateur.
drop function if exists public.create_link(text, text);
create or replace function public.create_link(
  p_mode text default 'couple',
  p_time_zone text default null,
  p_locale text default null
)
returns table (link_id uuid, invite_code text)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_link uuid;
  v_code text;
  v_mode text := coalesce(p_mode, 'couple');
  v_tz text := coalesce(nullif(btrim(p_time_zone), ''), 'Europe/Paris');
  v_locale text := coalesce(nullif(btrim(p_locale), ''), 'fr');
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
  if v_locale not in ('fr', 'es', 'pt', 'it', 'ar', 'zh', 'ja') then
    v_locale := 'fr';
  end if;

  insert into public.links (mode, created_by, time_zone, locale)
  values (v_mode, v_uid, v_tz, v_locale) returning id into v_link;
  insert into public.link_members (link_id, user_id) values (v_link, v_uid);
  v_code := public.new_invite_code();
  insert into public.invites (code, link_id, created_by) values (v_code, v_link, v_uid);

  return query select v_link, v_code;
end $$;

grant execute on function public.create_link(text, text, text) to authenticated;

-- my_link() porte la langue au même titre que le jour et le fuseau.
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
