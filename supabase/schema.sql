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
  created_at timestamptz not null default now()
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
  emoji text not null,
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

create or replace function public.create_link(p_mode text default 'couple')
returns table (link_id uuid, invite_code text)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_link uuid;
  v_code text;
  v_mode text := coalesce(p_mode, 'couple');
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

  insert into public.links (mode, created_by) values (v_mode, v_uid) returning id into v_link;
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

  select count(*) into v_members from public.link_members where link_id = v_link;
  if v_members >= 2 then
    raise exception 'link_full';
  end if;

  insert into public.link_members (link_id, user_id) values (v_link, v_uid);
  return v_link;
end $$;

create or replace function public.my_link()
returns table (
  link_id uuid,
  mode text,
  created_at timestamptz,
  invite_code text,
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
 * Consecutive days (ending today or yesterday) where both members answered.
 * Yesterday still counts so the streak does not "break" before today's answer.
 */
create or replace function public.link_streak(p_link_id uuid)
returns integer language plpgsql stable security definer set search_path = public as $$
declare
  v_streak int := 0;
  v_date date := current_date;
  v_done boolean;
begin
  if not public.is_link_member(p_link_id) then
    return 0;
  end if;

  loop
    select count(distinct a.author_id) >= 2 into v_done
    from public.daily_prompts p
    join public.answers a on a.prompt_id = p.id
    where p.link_id = p_link_id and p.prompt_date = v_date;

    if coalesce(v_done, false) then
      v_streak := v_streak + 1;
    elsif v_date < current_date then
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

drop policy if exists link_members_delete on public.link_members;
create policy link_members_delete on public.link_members for delete to authenticated
  using (user_id = auth.uid());

drop policy if exists invites_select on public.invites;
create policy invites_select on public.invites for select to authenticated
  using (public.is_link_member(link_id));

drop policy if exists daily_prompts_select on public.daily_prompts;
create policy daily_prompts_select on public.daily_prompts for select to authenticated
  using (public.is_link_member(link_id));

-- Members may insert the day's prompt themselves: that is the client-side
-- fallback when the Edge Function is unavailable.
drop policy if exists daily_prompts_insert on public.daily_prompts;
create policy daily_prompts_insert on public.daily_prompts for insert to authenticated
  with check (public.is_link_member(link_id));

drop policy if exists answers_select on public.answers;
create policy answers_select on public.answers for select to authenticated
  using (
    author_id = auth.uid()
    or (public.can_see_prompt(prompt_id) and public.has_answered(prompt_id))
  );

drop policy if exists answers_insert on public.answers;
create policy answers_insert on public.answers for insert to authenticated
  with check (author_id = auth.uid() and public.can_see_prompt(prompt_id));

drop policy if exists answers_update on public.answers;
create policy answers_update on public.answers for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());

drop policy if exists reactions_select on public.reactions;
create policy reactions_select on public.reactions for select to authenticated
  using (public.can_see_answer(answer_id));

drop policy if exists reactions_insert on public.reactions;
create policy reactions_insert on public.reactions for insert to authenticated
  with check (user_id = auth.uid() and public.can_see_answer(answer_id));

drop policy if exists reactions_delete on public.reactions;
create policy reactions_delete on public.reactions for delete to authenticated
  using (user_id = auth.uid());

-- ------------------------------------------------------------------ grants

revoke all on function public.new_invite_code() from public, anon, authenticated;

grant execute on function public.create_link(text) to authenticated;
grant execute on function public.join_link(text) to authenticated;
grant execute on function public.my_link() to authenticated;
grant execute on function public.link_streak(uuid) to authenticated;
grant execute on function public.my_link_id() to authenticated;
grant execute on function public.is_link_member(uuid) to authenticated;
grant execute on function public.shares_link_with(uuid) to authenticated;
grant execute on function public.can_see_prompt(uuid) to authenticated;
grant execute on function public.has_answered(uuid) to authenticated;
grant execute on function public.can_see_answer(uuid) to authenticated;
