-- Reproduit le strict minimum de ce que Supabase fournit autour du schéma
-- applicatif, pour pouvoir passer `schema.sql` et les tests RLS dans un
-- Postgres nu (ici PGlite, en WebAssembly).
--
-- Ce fichier n'est JAMAIS appliqué à un vrai projet Supabase : là-bas, tout ce
-- qui suit existe déjà. Il ne sert qu'au harnais local.

create schema if not exists auth;

-- Seules les colonnes dont le schéma applicatif dépend réellement : la clé
-- étrangère depuis profiles/links/link_members/answers/reactions, et
-- raw_user_meta_data que lit le trigger handle_new_user.
create table if not exists auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb
);

-- Définition Supabase : lit le claim `sub` du JWT injecté par PostgREST.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(
    coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ),
    ''
  )::uuid
$$;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;

grant usage on schema public, auth to anon, authenticated, service_role;

-- Supabase accorde les privilèges de table à anon/authenticated : c'est la RLS,
-- et elle seule, qui restreint ensuite. Sans ces grants on testerait les
-- GRANT plutôt que les policies, et tout passerait pour de mauvaises raisons.
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated;
