-- Étape 0 — durcissement. Voir docs/architecture.md §4.10.
--
-- Corrige cinq des sept défauts connus, sans aucun changement d'UI et sans
-- dépendre d'un choix produit. À passer sur une base existante ; `schema.sql`
-- porte les mêmes changements pour une installation neuve.
--
-- Défaut 2 — answers_update ne vérifiait que l'auteur.
-- Défaut 4 — leaveLink laissait un lien orphelin et un code d'invitation vivant.
-- Défaut 5 — l'upsert client sur daily_prompts ne peut pas passer en UPDATE.
-- Défaut 7 — race TOCTOU dans join_link.

begin;

-- ------------------------------------------------------- défaut 2 : answers
-- Un ex-membre gardait un droit d'écriture à vie sur ses anciennes réponses,
-- et prompt_id étant modifiable il pouvait repointer sa réponse vers le prompt
-- d'un autre lien, où elle s'affichait comme « la réponse du partenaire ».

drop policy if exists answers_update on public.answers;
create policy answers_update on public.answers for update to authenticated
  using (author_id = auth.uid() and public.can_see_prompt(prompt_id))
  with check (author_id = auth.uid() and public.can_see_prompt(prompt_id));

-- Un WITH CHECK valide la ligne finale ; il n'empêche pas de repointer une clé.
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

-- --------------------------------------------------- défaut 4 : quitter un lien
-- La suppression ne portait que sur link_members : le lien, les prompts, les
-- réponses et surtout les invites survivaient. Le code restait valide sept
-- jours sur un lien redevenu à un membre, donc rejoignable par un tiers.

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

  -- Sérialise contre un join_link concurrent sur le même lien.
  perform 1 from public.links where id = v_link for update;
  if not found then
    return; -- le lien a déjà disparu : rien à nettoyer
  end if;

  delete from public.link_members where user_id = v_uid and link_id = v_link;

  -- Le code doit mourir avec le départ, sinon il rouvre un lien à un membre.
  delete from public.invites where link_id = v_link;

  select count(*) into v_left from public.link_members where link_id = v_link;
  if v_left = 0 then
    -- cascade : invites, daily_prompts, answers, reactions
    delete from public.links where id = v_link;
  end if;
end $$;

grant execute on function public.leave_link() to authenticated;

-- NOTE: la policy link_members_delete n'est PAS supprimée ici. Un build déjà
-- installé qui exécute encore `.from('link_members').delete()` recevrait un 204
-- à zéro ligne, donc AUCUNE erreur : l'utilisateur croirait avoir quitté alors
-- que son adhésion et son code sont intacts. Elle tombe dans 0002, une fois les
-- anciens builds éteints.

-- Un code est consommé à l'appairage et purgé au départ d'un membre. Sans ce
-- chemin, le membre restant se retrouve sur l'écran d'invitation sans rien à
-- partager, et sa seule sortie est de détruire l'archive.
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

grant execute on function public.regenerate_invite() to authenticated;

-- ------------------------------------------- défaut 2 (suite) : les réactions
-- can_see_answer accorde l'accès dès `author_id = auth.uid()`, sans condition
-- d'appartenance : un ex-membre pouvait donc encore écrire des « réactions »
-- sur ses propres anciennes réponses, rendues telles quelles dans les Souvenirs
-- du partenaire resté. Emoji sans contrainte de longueur = canal de texte libre.

drop policy if exists reactions_insert on public.reactions;
create policy reactions_insert on public.reactions for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.can_see_answer(answer_id)
    and public.can_see_prompt((select a.prompt_id from public.answers a where a.id = answer_id))
  );

alter table public.reactions drop constraint if exists reactions_emoji_shape;
alter table public.reactions
  add constraint reactions_emoji_shape check (char_length(emoji) between 1 and 8);

-- ------------------------------------------------- défaut 7 : join_link TOCTOU
-- `count(*) >= 2` n'était protégé par aucun verrou et aucune contrainte ne
-- plafonnait link_members par lien : deux sessions rejouant le même code
-- simultanément faisaient entrer un troisième membre. Le code n'était pas non
-- plus consommé à l'appairage.

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

  -- Verrou : tout ce qui suit est sérialisé par lien. Si la ligne a disparu
  -- entre-temps, `for update` ne verrouille rien : sans ce test on poursuit sur
  -- un lien inexistant jusqu'à une violation de clé étrangère 23503, affichée
  -- brute et en anglais à l'utilisateur.
  perform 1 from public.links where id = v_link for update;
  if not found then
    raise exception 'invalid_code';
  end if;

  select count(*) into v_members from public.link_members where link_id = v_link;
  if v_members >= 2 then
    raise exception 'link_full';
  end if;

  insert into public.link_members (link_id, user_id) values (v_link, v_uid);

  -- Le code est consommé : un lien complet n'est plus rejoignable, même si
  -- la capture d'écran circule encore.
  delete from public.invites where link_id = v_link;

  return v_link;
end $$;

commit;
