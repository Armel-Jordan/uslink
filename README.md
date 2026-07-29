# UsLink

Une question par jour, rien que pour vous deux.

UsLink est une app mobile (iOS + Android) de connexion quotidienne pour les couples : chaque jour, les deux personnes reliées reçoivent **la même question**, y répondent chacune de leur côté, et ne découvrent la réponse de l'autre **qu'une fois les deux réponses écrites**. L'IA travaille en coulisses — elle génère et personnalise la question, sans jamais parler à l'utilisateur.

Modes : **couple** (principal), **amis** (secondaire), **aléatoire** (à venir).

## Stack

| Couche | Choix |
| --- | --- |
| App | Expo SDK 57 (expo-router, React Native 0.86, React 19, TypeScript) |
| Backend | Supabase — Auth, Postgres, RLS |
| IA | Claude (`claude-opus-5`) via une Supabase Edge Function (Deno) |
| Session | AsyncStorage |

## Démarrer

```sh
npm install
npm start          # puis « a » pour Android, « i » pour iOS, « w » pour le web
```

Sans variables d'environnement, l'app démarre en **mode démo** : tout est local à l'appareil, avec une partenaire scriptée (« Camille ») qui répond juste après vous — c'est ce qui permet de tester le mécanisme de révélation en solo. Aucun backend requis.

### Brancher Supabase

1. Créer un projet sur [supabase.com](https://supabase.com).
2. Exécuter [`supabase/schema.sql`](supabase/schema.sql) dans le SQL editor (tables, RLS, RPC).
3. Copier `.env.example` vers `.env.local` et renseigner :

```sh
EXPO_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

4. Relancer avec `npm start -- --clear`. L'app basculera automatiquement du mode démo vers Supabase.

### Déployer la fonction IA

```sh
supabase link --project-ref <ref>
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy daily-prompt
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont injectés par la plateforme — rien à configurer.

Sans clé Anthropic (ou si la fonction n'est pas déployée), l'app retombe sur la bibliothèque de questions locale : le rituel quotidien ne casse jamais, seul le badge change (« Question personnalisée par IA » → « Question de notre sélection »).

## Architecture

```
src/
  app/                        routes expo-router
    _layout.tsx               SessionProvider + garde « connecté ? »
    sign-in.tsx               connexion / inscription (ou entrée démo)
    (app)/_layout.tsx         garde « relié à quelqu'un ? »
    (app)/pair.tsx            choix du mode, code d'invitation, rejoindre
    (app)/(tabs)/index.tsx    Aujourd'hui — question, réponse, révélation
    (app)/(tabs)/history.tsx  Souvenirs
    (app)/(tabs)/profile.tsx  profil, lien, déconnexion
  lib/
    data/adapter.ts           l'interface que l'UI consomme
    data/supabase.ts          implémentation Supabase
    data/demo.ts              implémentation locale (mode démo)
    session.tsx               contexte session + profil + lien
    prompt-library.ts         questions de secours (déterministes par jour)
    strings.ts                toute la copie FR
supabase/
  schema.sql                  tables, RLS, RPC (create_link, join_link, link_streak…)
  functions/daily-prompt/     Edge Function Claude
```

Les écrans ne savent jamais s'il y a un backend : `src/lib/data/index.ts` choisit l'adaptateur une fois au démarrage, selon la présence des variables d'environnement.

### La règle centrale vit dans la base, pas dans le client

La réponse du partenaire n'est lisible qu'une fois la vôtre écrite — c'est une policy RLS, pas une condition d'affichage :

```sql
create policy answers_select on public.answers for select to authenticated
  using (
    author_id = auth.uid()
    or (public.can_see_prompt(prompt_id) and public.has_answered(prompt_id))
  );
```

Un client modifié ne peut donc pas lire la réponse de l'autre en avance.

### La question du jour

`daily-prompt` est idempotente : une seule question par lien et par jour, quel que soit celui qui ouvre l'app en premier (`unique (link_id, prompt_date)` + upsert).

Le contexte envoyé à Claude est volontairement pauvre : mode du lien, prénoms, nombre de jours depuis la mise en relation, et les 10 dernières questions posées (pour éviter les répétitions). **Aucune réponse des utilisateurs n'est envoyée au modèle.**

La sortie est contrainte par un JSON schema (`output_config.format`), la fonction n'a donc pas à deviner le format :

```ts
{ question: string, category: string }
```

## Sécurité

- Une personne appartient à un seul lien à la fois (`link_members_one_per_user`).
- Les codes d'invitation expirent au bout de 7 jours ; rejoindre son propre code ou un lien déjà complet est refusé côté Postgres (`join_link`).
- La clé Anthropic ne vit que dans les secrets Supabase, jamais dans l'app (aucun préfixe `EXPO_PUBLIC_`).
- `.env.local` est ignoré par git.

## Scripts

```sh
npm start          # serveur de dev Expo
npm run android    # ouvrir sur Android
npm run ios        # ouvrir sur iOS
npm run web        # ouvrir dans le navigateur
npm run typecheck  # tsc --noEmit
npm run lint       # expo lint
```

## Prochaines étapes

- Notifications push quotidiennes (`expo-notifications`) à une heure choisie par le couple.
- Realtime Supabase sur `answers` pour révéler la réponse du partenaire sans rafraîchir.
- Mode aléatoire (mise en relation avec un inconnu autour d'une question).
- Builds EAS pour TestFlight / Play Console (ni JDK ni Xcode requis en local).
- Anglais : dupliquer `src/lib/strings.ts` et typer le résultat avec `Dictionary`.
