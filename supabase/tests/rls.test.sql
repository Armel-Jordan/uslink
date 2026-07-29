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

-- Le « aujourd'hui » est désormais celui du LIEN, jamais celui du client ni
-- current_date (UTC). Les fixtures s'y plient comme le fera l'app.
insert into _fxt select 'TODAY', public.link_today((select v from _fx where k = 'L1'))::text;

-- P1 : la question du jour, insérée par Alice (repli client, policy
-- daily_prompts_insert), à laquelle Alice répond.
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
insert into public.daily_prompts (link_id, prompt_date, question, category, source)
select v, (select v::date from _fxt where k = 'TODAY'), 'Question du jour ?', 'test', 'library'
from _fx where k = 'L1';
insert into _fx select 'P1', id from public.daily_prompts
  where link_id = (select v from _fx where k = 'L1')
    and prompt_date = (select v::date from _fxt where k = 'TODAY');

insert into public.answers (prompt_id, author_id, body)
select v, '11111111-1111-1111-1111-111111111111', 'Réponse d''Alice, assez longue pour compter.' from _fx where k = 'P1';
insert into _fx select 'A_ALICE', id from public.answers
  where prompt_id = (select v from _fx where k = 'P1')
    and author_id = '11111111-1111-1111-1111-111111111111';

-- P2 : la question d'hier, encore dans la fenêtre d'écriture, à laquelle SEUL
-- Bob a répondu. C'est le seul contexte où l'édition est encore permise, donc
-- le seul où l'immutabilité des clés est observable.
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
insert into public.daily_prompts (link_id, prompt_date, question, category, source)
select v, (select v::date from _fxt where k = 'TODAY') - 1, 'Question d''hier ?', 'test', 'library'
from _fx where k = 'L1';
insert into _fx select 'P2', id from public.daily_prompts
  where link_id = (select v from _fx where k = 'L1')
    and prompt_date = (select v::date from _fxt where k = 'TODAY') - 1;
insert into public.answers (prompt_id, author_id, body)
select v, '22222222-2222-2222-2222-222222222222', 'Réponse de Bob à hier' from _fx where k = 'P2';

-- P3 : une vieille question, hors fenêtre. Insérée hors RLS: la policy
-- l'interdit désormais, et c'est justement ce qu'on vérifie plus bas.
reset role;
insert into public.daily_prompts (link_id, prompt_date, question, category, source)
select v, (select v::date from _fxt where k = 'TODAY') - 60, 'Vieille question ?', 'test', 'library'
from _fx where k = 'L1';
insert into _fx select 'P3', id from public.daily_prompts
  where link_id = (select v from _fx where k = 'L1')
    and prompt_date = (select v::date from _fxt where k = 'TODAY') - 60;
insert into public.answers (prompt_id, author_id, body)
select v, '11111111-1111-1111-1111-111111111111', 'Vieille réponse d''Alice' from _fx where k = 'P3';
set local role authenticated;

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
   select v, ''22222222-2222-2222-2222-222222222222'', ''Réponse de Bob, assez longue pour compter.'' from _fx where k = ''P1''');

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
   select v, ''44444444-4444-4444-4444-444444444444'', ''intrusion, avec assez de caractères.'' from _fx where k = ''P1''',
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

-- Sur P2, Alice n'a pas répondu : Bob peut donc encore éditer.
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');

select pg_temp.t_touches(
  'Bob peut corriger sa réponse tant que le partenaire n''a pas répondu',
  'update public.answers set body = ''Réponse corrigée, toujours assez longue.''
     where author_id = ''22222222-2222-2222-2222-222222222222''
       and prompt_id = (select v from _fx where k = ''P2'')', 1);

select pg_temp.t_raise(
  'DÉFAUT 2: repointer prompt_id est refusé',
  'update public.answers set prompt_id = (select v from _fx where k = ''P1'')
     where author_id = ''22222222-2222-2222-2222-222222222222''
       and prompt_id = (select v from _fx where k = ''P2'')',
  'immutable_answer_key');

select pg_temp.t_raise(
  'DÉFAUT 2: changer author_id est refusé',
  'update public.answers set author_id = ''11111111-1111-1111-1111-111111111111''
     where author_id = ''22222222-2222-2222-2222-222222222222''
       and prompt_id = (select v from _fx where k = ''P2'')',
  'immutable_answer_key');

select pg_temp.t_touches(
  'Bob ne peut pas modifier la réponse d''Alice',
  'update public.answers set body = ''détourné, avec assez de caractères.''
     where author_id = ''11111111-1111-1111-1111-111111111111''', 0);

-- ============================== DÉFAUT 3 (1re moitié) — FENÊTRE ET GEL

select pg_temp.t_touches(
  'DÉFAUT 3: une fois le partenaire ayant répondu, ma réponse est GELÉE',
  'update public.answers set body = ''réécrit après avoir lu la réponse de l''''autre''
     where author_id = ''22222222-2222-2222-2222-222222222222''
       and prompt_id = (select v from _fx where k = ''P1'')', 0);

select pg_temp.t_raise(
  'DÉFAUT 3: répondre à une vieille question ne déverrouille plus l''archive',
  'insert into public.answers (prompt_id, author_id, body)
   select v, ''22222222-2222-2222-2222-222222222222'', ''déverrouillage rétroactif de toute l''''archive''
   from _fx where k = ''P3''',
  'row-level security');

select pg_temp.t_rows(
  'DÉFAUT 3: la vieille réponse d''Alice reste invisible',
  'select 1 from public.answers where prompt_id = (select v from _fx where k = ''P3'')', 0);

-- La substance. Alice répond « . » à P2 : la ligne existe, mais ce n'est pas
-- répondre. Et comme Bob a déjà répondu, elle est GELÉE avec son point —
-- c'est tout le prix de la triche, et il est définitif.
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_allow(
  'Une réponse d''un caractère est acceptée en écriture',
  'insert into public.answers (prompt_id, author_id, body)
   select v, ''11111111-1111-1111-1111-111111111111'', ''.'' from _fx where k = ''P2''');
select pg_temp.t_rows(
  'DÉFAUT 3: « . » ne déverrouille PAS la réponse du partenaire',
  'select 1 from public.answers
     where prompt_id = (select v from _fx where k = ''P2'')
       and author_id = ''22222222-2222-2222-2222-222222222222''', 0);
select pg_temp.t_touches(
  'DÉFAUT 3: et on ne peut plus se rattraper — la réponse est gelée',
  'update public.answers set body = ''je rallonge après coup pour tricher''
     where author_id = ''11111111-1111-1111-1111-111111111111''
       and prompt_id = (select v from _fx where k = ''P2'')', 0);

-- Le seuil ne dépend pas du type : un défi se valide d'un tap, sans texte.
reset role;
insert into public.daily_prompts (link_id, prompt_date, kind, question, category, options, source)
select v, (select v::date from _fxt where k = 'TODAY'), 'challenge',
       'Envoie-lui une photo de ce que tu vois.', 'quotidien',
       '{"duration_min": 2}'::jsonb, 'library'
from _fx where k = 'L1';
insert into _fx select 'P_DEFI', id from public.daily_prompts
  where link_id = (select v from _fx where k = 'L1') and kind = 'challenge';
insert into public.answers (prompt_id, kind, author_id, done)
select v, 'challenge', '11111111-1111-1111-1111-111111111111', true from _fx where k = 'P_DEFI';
set local role authenticated;

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select pg_temp.t_rows(
  'Un défi non relevé ne montre pas celui de l''autre',
  'select 1 from public.answers where prompt_id = (select v from _fx where k = ''P_DEFI'')', 0);
-- Ces deux refus se testent AVANT la vraie réponse de Bob : l'unicité
-- (prompt_id, author_id) lèverait sinon en premier et masquerait la contrainte
-- qu'on veut éprouver.
select pg_temp.t_raise(
  'Un défi ne peut pas porter de texte',
  'insert into public.answers (prompt_id, kind, author_id, done, body)
   select v, ''challenge'', ''22222222-2222-2222-2222-222222222222'', true, ''commentaire interdit''
   from _fx where k = ''P_DEFI''',
  'answers_shape');

-- Le type de la réponse est celui du contenu, garanti par la clé composite.
select pg_temp.t_raise(
  'Une réponse ne peut pas mentir sur son type',
  'insert into public.answers (prompt_id, kind, author_id, stance, body)
   select v, ''debate'', ''22222222-2222-2222-2222-222222222222'', 3, ''prétendre que c''''est un débat''
   from _fx where k = ''P_DEFI''',
  'answers_prompt_fk');

select pg_temp.t_allow(
  'Relever un défi ne demande aucun texte',
  'insert into public.answers (prompt_id, kind, author_id, done)
   select v, ''challenge'', ''22222222-2222-2222-2222-222222222222'', true from _fx where k = ''P_DEFI''');
select pg_temp.t_rows(
  'Un défi relevé révèle celui de l''autre',
  'select 1 from public.answers where prompt_id = (select v from _fx where k = ''P_DEFI'')', 2);

-- Le jsonb est fermé: une clé surnuméraire est refusée.
reset role;
select pg_temp.t_raise(
  'Le payload d''un contenu refuse toute clé surnuméraire',
  'insert into public.daily_prompts (link_id, prompt_date, kind, question, category, options, source)
   select v, (select v::date from _fxt where k = ''TODAY''), ''debate'', ''Axe de test'', ''test'',
          ''{"low":"a","high":"b","piege":"x"}''::jsonb, ''library'' from _fx where k = ''L1''',
  'daily_prompts_options_shape');
select pg_temp.t_raise(
  'Un débat sans ses deux pôles est refusé',
  'insert into public.daily_prompts (link_id, prompt_date, kind, question, category, options, source)
   select v, (select v::date from _fxt where k = ''TODAY'') - 1, ''debate'', ''Axe de test'', ''test'',
          ''{"low":"a"}''::jsonb, ''library'' from _fx where k = ''L1''',
  'daily_prompts_options_shape');
set local role authenticated;

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select pg_temp.t_raise(
  'Un membre ne peut pas fabriquer une question hors de la fenêtre du jour',
  'insert into public.daily_prompts (link_id, prompt_date, question, category, source)
   select v, (select v::date from _fxt where k = ''TODAY'') + 3, ''forgée'', ''test'', ''library''
   from _fx where k = ''L1''',
  'row-level security');

-- ==================================== DÉFAUT 1 — LE JOUR EST UNE NOTION SERVEUR

reset role;
select pg_temp.t_ok(
  'DÉFAUT 1: link_today suit le fuseau du lien, pas celui du serveur',
  (select public.link_today(v) is not null from _fx where k = 'L1'));

-- Deux fuseaux aux extrémités du globe: le jour du lien doit bouger avec eux.
update public.links set time_zone = 'Pacific/Kiritimati' where id = (select v from _fx where k = 'L2');
select pg_temp.t_ok(
  'DÉFAUT 1: à UTC+14 le jour du lien est en avance sur UTC',
  (select public.link_today(v) >= (now() at time zone 'UTC')::date from _fx where k = 'L2'));

update public.links set time_zone = 'Pacific/Midway' where id = (select v from _fx where k = 'L2');
select pg_temp.t_ok(
  'DÉFAUT 1: à UTC−11 le jour du lien est en retard sur UTC',
  (select public.link_today(v) <= (now() at time zone 'UTC')::date from _fx where k = 'L2'));

select pg_temp.t_raise(
  'Un fuseau inconnu est refusé',
  'update public.links set time_zone = ''Mars/Olympus'' where id = (select v from _fx where k = ''L2'')',
  'invalid_time_zone');

-- `at time zone` accepte les specs POSIX en inversant leur signe, et accepte
-- même 'FOO7' : seul pg_timezone_names est un vrai contrôle. Sans lui, un
-- couple installe une horloge fausse de plusieurs heures sans aucune erreur.
select pg_temp.t_raise(
  'Une spécification POSIX est refusée (elle inverserait le signe)',
  'update public.links set time_zone = ''GMT+02:00'' where id = (select v from _fx where k = ''L2'')',
  'invalid_time_zone');
select pg_temp.t_raise(
  'Une chaîne arbitraire acceptée par at-time-zone est refusée',
  'update public.links set time_zone = ''FOO7'' where id = (select v from _fx where k = ''L2'')',
  'invalid_time_zone');

-- Un déplacement d'horloge vers l'ouest recule link_today d'un jour : la
-- question déjà ouverte ne doit pas devenir non répondable pour les deux.
update public.links set time_zone = 'Pacific/Kiritimati' where id = (select v from _fx where k = 'L1');
select pg_temp.t_ok(
  'Après un saut d''horloge, la question du jour reste répondable',
  (select public.prompt_is_open(v) from _fx where k = 'P1'));
update public.links set time_zone = 'Pacific/Midway' where id = (select v from _fx where k = 'L1');
select pg_temp.t_ok(
  'Après un saut d''horloge en sens inverse, elle reste répondable',
  (select public.prompt_is_open(v) from _fx where k = 'P1'));
select pg_temp.t_ok(
  'Un saut d''horloge ne rouvre pas pour autant l''archive',
  (select not public.prompt_is_open(v) from _fx where k = 'P3'));
update public.links set time_zone = 'Europe/Paris' where id = (select v from _fx where k = 'L1');

set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select pg_temp.t_allow('Un membre peut choisir le fuseau de son lien',
  'select public.set_link_time_zone(''America/Montreal'')');
select pg_temp.t_raise(
  'Changer de fuseau deux fois de suite est refusé (une fois par 24 h)',
  'select public.set_link_time_zone(''Europe/Paris'')', 'time_zone_cooldown');

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select pg_temp.t_raise('Sans lien, on ne choisit aucun fuseau',
  'select public.set_link_time_zone(''Europe/Paris'')', 'no_link');

-- ================================ ONBOARDING — CE QUE LE PARTENAIRE NE VOIT PAS

-- Toute la raison d'être de la table séparée : la RLS filtre par LIGNE, donc
-- une ville posée sur `profiles` serait lisible par le conjoint.
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_allow(
  'Chacun écrit ses propres données d''onboarding',
  'insert into public.profile_onboarding (id, birth_date, city, interests, goals, relationship_started_on)
   values (''11111111-1111-1111-1111-111111111111'', ''1990-05-04'', ''Montréal'',
           array[''cuisine'',''voyage''], array[''complicite''], ''2019-09-01'')');

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select pg_temp.t_rows(
  'CONFIDENTIALITÉ: le partenaire ne voit PAS la ville ni la date de naissance',
  'select 1 from public.profile_onboarding
     where id = ''11111111-1111-1111-1111-111111111111''', 0);
select pg_temp.t_touches(
  'CONFIDENTIALITÉ: le partenaire ne peut pas écrire dans ces données',
  'update public.profile_onboarding set city = ''détourné''
     where id = ''11111111-1111-1111-1111-111111111111''', 0);
select pg_temp.t_allow(
  'Bob écrit les siennes, avec une autre date de début',
  'insert into public.profile_onboarding (id, interests, goals, relationship_started_on)
   values (''22222222-2222-2222-2222-222222222222'', array[''sport'',''musique''],
           array[''fun''], ''2019-10-15'')');

reset role;
select pg_temp.t_raise(
  'Un centre d''intérêt hors liste est refusé',
  'insert into public.profile_onboarding (id, interests)
   values (''33333333-3333-3333-3333-333333333333'', array[''cryptomonnaie''])',
  'profile_onboarding_interests_check');
select pg_temp.t_raise(
  'Une date de relation dans le futur est refusée',
  'update public.profile_onboarding set relationship_started_on = current_date + 30
     where id = ''11111111-1111-1111-1111-111111111111''',
  'profile_onboarding_dates_check');
set local role authenticated;

-- ----------------------------------------- le compteur « ensemble depuis »

select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_allow('On peut fixer la date de début du couple',
  'select public.set_link_started_on(''2019-09-01''::date)');
select pg_temp.t_ok(
  'Le compteur est calculé côté serveur, dans le fuseau du lien',
  (select public.days_together(v) > 2000 from _fx where k = 'L1'));
select pg_temp.t_raise(
  'Une date de début dans le futur est refusée',
  'select public.set_link_started_on((current_date + 1)::date)', 'invalid_date');
select pg_temp.t_ok(
  'my_link() expose le compteur et la date déclarée par l''autre',
  (select count(*) = 1 from public.my_link()
    where days_together is not null and started_on = '2019-09-01'
      and partner_started_on = '2019-10-15'));

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select pg_temp.t_raise('Sans lien, on ne fixe aucune date de début',
  'select public.set_link_started_on(''2020-01-01''::date)', 'no_link');

-- ============================================ LA LANGUE DU COUPLE

select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_allow('Un membre peut choisir la langue du lien',
  'select public.set_link_locale(''ja'')');
select pg_temp.t_ok('La langue choisie est bien celle du lien',
  (select locale = 'ja' from public.links where id = (select v from _fx where k = 'L1')));
select pg_temp.t_raise('Une langue non servie est refusée',
  'select public.set_link_locale(''klingon'')', 'invalid_locale');
select pg_temp.t_ok('Un refus ne change pas la langue en place',
  (select locale = 'ja' from public.links where id = (select v from _fx where k = 'L1')));

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select pg_temp.t_raise('Sans lien, on ne choisit aucune langue',
  'select public.set_link_locale(''es'')', 'no_link');

select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select pg_temp.t_ok('my_link() porte la langue, le jour et le fuseau',
  (select count(*) = 1 from public.my_link()
    where locale = 'ja' and time_zone is not null and today is not null));
select pg_temp.t_allow('Le lien revient au français', 'select public.set_link_locale(''fr'')');

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
  'update public.answers set body = ''réécrit après le départ, assez long.''
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
