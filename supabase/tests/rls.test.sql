-- Harnais de test RLS — étape 1. Voir docs/architecture.md §4.10.
--
-- POURQUOI. `tsc` ne compile pas une ligne de SQL, et la règle centrale du
-- produit — on ne voit la réponse de l'autre qu'après avoir répondu — est une
-- policy. Les migrations à venir la déplacent. Sans ces assertions, ce sont
-- des paris.
--
-- COMMENT LE LANCER. Aucune dépendance, aucune extension. Colle ce fichier
-- dans l'éditeur SQL d'un projet Supabase de DÉVELOPPEMENT, ou:
--     psql "$DATABASE_URL" -f supabase/tests/rls.test.sql
-- Tout s'exécute dans une transaction terminée par ROLLBACK: rien n'est écrit.
-- Le script échoue avec un code d'erreur si une assertion tombe, ce qui suffit
-- comme portail de CI.
--
-- NE PAS le lancer sur la base de production: il crée des utilisateurs de test
-- et, même annulé, il pose des verrous sur des lignes réelles.

begin;

-- ------------------------------------------------------------------ harnais

create temporary table _results (
  ord    serial primary key,
  ok     boolean not null,
  name   text not null,
  detail text
) on commit drop;

-- Les helpers tournent en SECURITY INVOKER (sinon ils contourneraient la RLS
-- qu'ils sont censés éprouver), donc sous le rôle testé: il lui faut le droit
-- d'écrire le journal. `anon` en fait partie — on éprouve aussi ce qu'un
-- visiteur non authentifié peut lire.
grant insert on _results to authenticated, anon;
grant usage, select on sequence _results_ord_seq to authenticated, anon;

create function pg_temp.t_ok(p_name text, p_cond boolean, p_detail text default null)
returns void language plpgsql as $fn$
begin
  insert into _results (ok, name, detail) values (coalesce(p_cond, false), p_name, p_detail);
end $fn$;

/** Le compte de lignes visibles doit être exactement `p_expected`. */
create function pg_temp.t_rows(p_name text, p_sql text, p_expected int)
returns void language plpgsql as $fn$
declare v_n int;
begin
  execute 'select count(*) from (' || p_sql || ') _q' into v_n;
  insert into _results (ok, name, detail)
  values (v_n = p_expected, p_name, format('attendu %s, obtenu %s', p_expected, v_n));
exception when others then
  insert into _results (ok, name, detail) values (false, p_name, format('erreur %s: %s', sqlstate, sqlerrm));
end $fn$;

/** L'instruction doit passer. */
create function pg_temp.t_allow(p_name text, p_sql text)
returns void language plpgsql as $fn$
begin
  execute p_sql;
  insert into _results (ok, name) values (true, p_name);
exception when others then
  insert into _results (ok, name, detail) values (false, p_name, format('refusé: %s %s', sqlstate, sqlerrm));
end $fn$;

/** L'instruction doit lever, et le message doit contenir `p_expect`. */
create function pg_temp.t_raise(p_name text, p_sql text, p_expect text)
returns void language plpgsql as $fn$
begin
  execute p_sql;
  insert into _results (ok, name, detail) values (false, p_name, 'aucune erreur levée');
exception when others then
  insert into _results (ok, name, detail)
  values (position(p_expect in sqlerrm) > 0 or sqlstate = p_expect, p_name, format('%s %s', sqlstate, sqlerrm));
end $fn$;

/** Un UPDATE bloqué par un USING de policy ne lève pas: il touche 0 ligne. */
create function pg_temp.t_touches(p_name text, p_sql text, p_expected int)
returns void language plpgsql as $fn$
declare v_n int;
begin
  execute p_sql;
  get diagnostics v_n = row_count;
  insert into _results (ok, name, detail)
  values (v_n = p_expected, p_name, format('attendu %s ligne(s), touché %s', p_expected, v_n));
exception when others then
  insert into _results (ok, name, detail) values (false, p_name, format('erreur %s: %s', sqlstate, sqlerrm));
end $fn$;

create function pg_temp.as_user(p_uid uuid)
returns void language plpgsql as $fn$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $fn$;

grant execute on function
  pg_temp.t_ok(text, boolean, text), pg_temp.t_rows(text, text, int),
  pg_temp.t_allow(text, text), pg_temp.t_raise(text, text, text),
  pg_temp.t_touches(text, text, int), pg_temp.as_user(uuid)
to authenticated, anon;

-- ----------------------------------------------------------------- fixtures

create temporary table _fx (k text primary key, v uuid) on commit drop;
create temporary table _fxt (k text primary key, v text) on commit drop;
grant select, insert on _fx, _fxt to authenticated, anon;

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{"display_name":"Alice"}'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local',   '{"display_name":"Bob"}'),
  ('33333333-3333-3333-3333-333333333333', 'carol@test.local', '{"display_name":"Carol"}'),
  ('44444444-4444-4444-4444-444444444444', 'dave@test.local',  '{"display_name":"Dave"}');

set local role authenticated;

-- Alice ouvre un lien, Bob le rejoint. Dave ouvre un lien à part. Carol reste
-- seule: c'est notre témoin « étranger au lien ».
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
insert into _fx select 'L1', link_id from public.create_link('couple');
insert into _fxt
  select 'C1', i.code from public.invites i join _fx f on f.v = i.link_id and f.k = 'L1';

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select public.join_link((select v from _fxt where k = 'C1'));

select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
insert into _fx select 'L2', link_id from public.create_link('friends');

-- La question du jour de L1, insérée par Alice (repli client, policy
-- daily_prompts_insert), puis la réponse d'Alice.
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
insert into public.daily_prompts (link_id, prompt_date, question, category, source)
select v, current_date, 'Question de test ?', 'test', 'library' from _fx where k = 'L1';
insert into _fx select 'P1', id from public.daily_prompts where prompt_date = current_date
  and link_id = (select v from _fx where k = 'L1');

insert into public.answers (prompt_id, author_id, body)
select v, '11111111-1111-1111-1111-111111111111', 'Réponse d''Alice' from _fx where k = 'P1';
insert into _fx select 'A_ALICE', id from public.answers
  where prompt_id = (select v from _fx where k = 'P1')
    and author_id = '11111111-1111-1111-1111-111111111111';

-- ======================================================= LA RÈGLE DE RÉVÉLATION

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');

select pg_temp.t_rows(
  'Bob voit la question du jour de son lien',
  'select 1 from public.daily_prompts where id = (select v from _fx where k = ''P1'')', 1);

select pg_temp.t_rows(
  'RÉVÉLATION: Bob ne voit PAS la réponse d''Alice avant d''avoir répondu',
  'select 1 from public.answers where prompt_id = (select v from _fx where k = ''P1'')', 0);

select pg_temp.t_allow(
  'Bob peut répondre à la question de son lien',
  'insert into public.answers (prompt_id, author_id, body)
   select v, ''22222222-2222-2222-2222-222222222222'', ''Réponse de Bob'' from _fx where k = ''P1''');

select pg_temp.t_rows(
  'RÉVÉLATION: après avoir répondu, Bob voit les deux réponses',
  'select 1 from public.answers where prompt_id = (select v from _fx where k = ''P1'')', 2);

select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_rows(
  'RÉVÉLATION: Alice, qui a répondu, voit les deux réponses',
  'select 1 from public.answers where prompt_id = (select v from _fx where k = ''P1'')', 2);

-- ======================================================== ISOLATION ENTRE LIENS

select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.t_rows(
  'Dave ne voit pas la question d''un autre lien',
  'select 1 from public.daily_prompts where id = (select v from _fx where k = ''P1'')', 0);
select pg_temp.t_rows(
  'Dave ne voit aucune réponse d''un autre lien',
  'select 1 from public.answers where prompt_id = (select v from _fx where k = ''P1'')', 0);
select pg_temp.t_raise(
  'Dave ne peut pas répondre sur le prompt d''un autre lien',
  'insert into public.answers (prompt_id, author_id, body)
   select v, ''44444444-4444-4444-4444-444444444444'', ''intrusion'' from _fx where k = ''P1''',
  'row-level security');

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select pg_temp.t_rows(
  'Carol, sans lien, ne voit aucune question',
  'select 1 from public.daily_prompts', 0);
select pg_temp.t_raise(
  'Carol ne peut pas insérer une question dans le lien d''autrui',
  'insert into public.daily_prompts (link_id, prompt_date, question, category, source)
   select v, current_date + 1, ''forgé'', ''test'', ''library'' from _fx where k = ''L1''',
  'row-level security');

-- ============================================ DÉFAUT 2 — IMMUTABILITÉ DES CLÉS

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');

select pg_temp.t_touches(
  'Bob peut corriger le corps de sa propre réponse',
  'update public.answers set body = ''Réponse corrigée''
     where author_id = ''22222222-2222-2222-2222-222222222222''', 1);

select pg_temp.t_raise(
  'DÉFAUT 2: repointer prompt_id est refusé',
  'update public.answers set prompt_id = gen_random_uuid()
     where author_id = ''22222222-2222-2222-2222-222222222222''',
  'immutable_answer_key');

select pg_temp.t_raise(
  'DÉFAUT 2: changer author_id est refusé',
  'update public.answers set author_id = ''11111111-1111-1111-1111-111111111111''
     where author_id = ''22222222-2222-2222-2222-222222222222''',
  'immutable_answer_key');

select pg_temp.t_touches(
  'Bob ne peut pas modifier la réponse d''Alice',
  'update public.answers set body = ''détourné''
     where author_id = ''11111111-1111-1111-1111-111111111111''', 0);

-- ================================================== DÉFAUT 7 — APPAIRAGE

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select pg_temp.t_raise(
  'DÉFAUT 7: le code est consommé à l''appairage, il ne peut plus servir',
  'select public.join_link((select v from _fxt where k = ''C1''))', 'invalid_code');

select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_raise(
  'Rejoindre alors qu''on a déjà un lien est refusé',
  'select public.join_link(''ABCDEF'')', 'already_linked');
select pg_temp.t_raise(
  'Créer un second lien est refusé',
  'select public.create_link(''couple'')', 'already_linked');
select pg_temp.t_raise(
  'regenerate_invite est refusé quand le lien est complet',
  'select public.regenerate_invite()', 'link_full');

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select pg_temp.t_raise(
  'regenerate_invite est refusé sans lien',
  'select public.regenerate_invite()', 'no_link');

-- ==================================================== RÉACTIONS

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select pg_temp.t_allow(
  'Bob peut réagir à la réponse révélée d''Alice',
  'insert into public.reactions (answer_id, user_id, emoji)
   select v, ''22222222-2222-2222-2222-222222222222'', ''❤️'' from _fx where k = ''A_ALICE''');
select pg_temp.t_raise(
  'Un « emoji » de plus de 8 caractères est refusé',
  'insert into public.reactions (answer_id, user_id, emoji)
   select v, ''22222222-2222-2222-2222-222222222222'', ''texte libre de harcèlement'' from _fx where k = ''A_ALICE''',
  'reactions_emoji_shape');

-- ============================================= DÉFAUT 4 — QUITTER UN LIEN

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select pg_temp.t_allow('Bob quitte le lien', 'select public.leave_link()');

reset role;
select pg_temp.t_ok('DÉFAUT 4: le lien survit tant qu''Alice y reste',
  (select count(*) = 1 from public.links where id = (select v from _fx where k = 'L1')));
select pg_temp.t_ok('DÉFAUT 4: les invites du lien sont purgées au départ',
  (select count(*) = 0 from public.invites where link_id = (select v from _fx where k = 'L1')));
select pg_temp.t_ok('Les souvenirs survivent tant qu''un membre reste',
  (select count(*) = 1 from public.daily_prompts where id = (select v from _fx where k = 'P1')));
set local role authenticated;

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select pg_temp.t_rows(
  'Un ex-membre ne voit plus les questions du lien',
  'select 1 from public.daily_prompts where id = (select v from _fx where k = ''P1'')', 0);
select pg_temp.t_rows(
  'Un ex-membre ne voit plus la réponse de son ex-partenaire',
  'select 1 from public.answers where author_id = ''11111111-1111-1111-1111-111111111111''', 0);
select pg_temp.t_touches(
  'DÉFAUT 2: un ex-membre ne peut plus réécrire son ancienne réponse',
  'update public.answers set body = ''réécrit après le départ''
     where author_id = ''22222222-2222-2222-2222-222222222222''', 0);
select pg_temp.t_raise(
  'DÉFAUT 2: un ex-membre ne peut plus réagir dans le fil de son ex-partenaire',
  'insert into public.reactions (answer_id, user_id, emoji)
   select v, ''22222222-2222-2222-2222-222222222222'', ''🔪'' from _fx where k = ''A_ALICE''',
  'row-level security');

-- Alice part à son tour: plus personne, le lien et ses souvenirs disparaissent.
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_allow('Alice quitte le lien à son tour', 'select public.leave_link()');

reset role;
select pg_temp.t_ok('DÉFAUT 4: le lien vide est supprimé',
  (select count(*) = 0 from public.links where id = (select v from _fx where k = 'L1')));
select pg_temp.t_ok('La cascade emporte les questions du lien supprimé',
  (select count(*) = 0 from public.daily_prompts where id = (select v from _fx where k = 'P1')));
select pg_temp.t_ok('La cascade emporte les réponses du lien supprimé',
  (select count(*) = 0 from public.answers where prompt_id = (select v from _fx where k = 'P1')));
set local role authenticated;

-- Alice, redevenue libre, peut repartir de zéro.
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_allow('Après son départ, Alice peut créer un nouveau lien',
  'select public.create_link(''couple'')');
select pg_temp.t_allow('Alice peut régénérer un code sur un lien à un membre',
  'select public.regenerate_invite()');

-- =========================================================== ANONYME

reset role;
set local role anon;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_rows('Le rôle anon ne voit aucune question', 'select 1 from public.daily_prompts', 0);
select pg_temp.t_rows('Le rôle anon ne voit aucune réponse', 'select 1 from public.answers', 0);
select pg_temp.t_rows('Le rôle anon ne voit aucun profil', 'select 1 from public.profiles', 0);

-- ------------------------------------------------------------------ verdict

reset role;

do $report$
declare
  r record;
  v_fail int;
  v_all  int;
begin
  select count(*) filter (where not ok), count(*) into v_fail, v_all from _results;
  for r in select * from _results order by ord loop
    raise notice '%  %  %', case when r.ok then ' ok ' else 'FAIL' end, r.name,
      coalesce('— ' || r.detail, '');
  end loop;
  raise notice '----------------------------------------';
  if v_fail > 0 then
    raise exception '% assertion(s) en échec sur %', v_fail, v_all;
  end if;
  raise notice '% assertions, toutes vertes', v_all;
end $report$;

rollback;
