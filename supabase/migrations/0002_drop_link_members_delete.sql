-- Étape 0, seconde passe. À NE PASSER QU'UNE FOIS LES ANCIENS BUILDS ÉTEINTS.
--
-- 0001 a introduit la RPC leave_link(), et le client corrigé l'utilise. Tant
-- qu'un build antérieur circule, il exécute encore un DELETE direct sur
-- link_members. Si on retire la policy en même temps que 0001, ce DELETE
-- renvoie 204 avec zéro ligne supprimée et AUCUNE erreur : l'utilisateur voit
-- l'écran se mettre à jour, croit avoir quitté le lien, alors que son adhésion
-- et son code d'invitation sont intacts. C'est le seul mode d'échec silencieux
-- de cette étape, donc celui qu'il faut ordonnancer.
--
-- Ordre : 0001 -> publier le client corrigé -> attendre l'extinction des
-- anciens builds -> 0002.

begin;

drop policy if exists link_members_delete on public.link_members;

commit;
