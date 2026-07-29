import { Stack } from 'expo-router';

import { useSession } from '@/lib/session';

/**
 * Second gate: the daily ritual only exists once two people are linked. A link
 * that is created but still waiting for its partner keeps the user on `pair`,
 * where the invite code lives.
 */
export default function AppLayout() {
  const { link } = useSession();
  const paired = Boolean(link?.partner);

  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Protected guard={paired}>
        <Stack.Screen name="(tabs)" />
      </Stack.Protected>

      <Stack.Protected guard={!paired}>
        <Stack.Screen name="pair" />
      </Stack.Protected>
    </Stack>
  );
}
