-- Données écrites sous l'ANCIEN schéma, avant les migrations : c'est sur elles
-- qu'une migration casse, pas sur une base vide. Notamment une réponse d'un
-- seul caractère (answers.body acceptait 1 caractère depuis le premier commit)
-- et une réaction écrite quand `emoji` n'était pas encore borné.
--
-- Utilisé uniquement par scripts/rls/run.mjs --baseline=<ref>.

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'legacy1@test.local', '{"display_name":"Legacy1"}'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'legacy2@test.local', '{"display_name":"Legacy2"}');

set local role authenticated;

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);
create temporary table _legacy on commit drop as select * from public.create_link('couple');

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-000000000002","role":"authenticated"}', true);
select public.join_link((select invite_code from _legacy));

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);
insert into public.daily_prompts (link_id, prompt_date, question, category, source)
  select link_id, current_date - 1, 'Vieille question ?', 'test', 'library' from _legacy;

-- Une réponse d'un seul caractère : exactement ce sur quoi un CHECK de longueur
-- introduit plus tard ferait avorter la migration.
insert into public.answers (prompt_id, author_id, body)
  select p.id, 'aaaaaaaa-0000-0000-0000-000000000001', '.'
  from public.daily_prompts p join _legacy l on l.link_id = p.link_id;

select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-000000000002","role":"authenticated"}', true);
insert into public.answers (prompt_id, author_id, body)
  select p.id, 'aaaaaaaa-0000-0000-0000-000000000002', 'une vraie réponse un peu plus longue'
  from public.daily_prompts p join _legacy l on l.link_id = p.link_id;

insert into public.reactions (answer_id, user_id, emoji)
  select a.id, 'aaaaaaaa-0000-0000-0000-000000000002', '❤️'
  from public.answers a where a.author_id = 'aaaaaaaa-0000-0000-0000-000000000001';

reset role;

commit;
