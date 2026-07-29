# Expo HAS CHANGED

Read the exact versioned docs at https://docs.expo.dev/versions/v57.0.0/ before writing any code.

# UsLink conventions

- **Routing**: expo-router with `Stack.Protected` guards. Two gates: session (`src/app/_layout.tsx`) then link (`src/app/(app)/_layout.tsx`). Tabs come from `expo-router/js-tabs` — the bare `Tabs` export from `expo-router` is deprecated in SDK 57.
- **Data access**: screens only ever call `data` from `@/lib/data`. Two implementations satisfy `DataAdapter` (`data/supabase.ts`, `data/demo.ts`) and the choice is made once at startup from `EXPO_PUBLIC_SUPABASE_URL`. Never import `@/lib/supabase` from a screen, and never branch on "is there a backend" in UI code.
- **Copy**: all user-facing French strings live in `src/lib/strings.ts`. No literal French in components.
- **Styling**: `StyleSheet` + tokens from `src/constants/theme.ts` (`Colors`, `Spacing`, `Radius`). Colours come from `useTheme()`, never hardcoded, and every key exists in both light and dark.
- **The reveal rule is a database rule.** A partner's answer becomes readable only once you have answered, enforced by the `answers_select` RLS policy in `supabase/schema.sql`. Do not re-implement or weaken it in the client.
- **AI stays server-side.** The Anthropic key lives in Supabase secrets; the model is called only from `supabase/functions/daily-prompt`. Model id is `claude-opus-5` with `output_config.format` (JSON schema). Any failure path must fall back to `prompt-library.ts` rather than leaving a day without a question.
- **Before committing**: `npm run typecheck`. `supabase/functions` is Deno and excluded from `tsconfig.json` on purpose.
