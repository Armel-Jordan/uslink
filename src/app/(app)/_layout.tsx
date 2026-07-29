import { Stack } from 'expo-router';

import { useSession } from '@/lib/session';

/**
 * Trois portes, dans cet ordre : on se présente, on se relie, on vit le rituel.
 *
 * L'onboarding passe AVANT l'appairage parce que ce qu'on y déclare — date de
 * début, centres d'intérêt, objectifs — est réconcilié entre les deux membres
 * au moment où le second rejoint. Le demander après, ce serait n'avoir rien à
 * fusionner.
 */
export default function AppLayout() {
  const { link, onboarding } = useSession();
  const introduced = Boolean(onboarding?.completed);
  const paired = Boolean(link?.partner);

  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Protected guard={!introduced}>
        <Stack.Screen name="onboarding" />
      </Stack.Protected>

      <Stack.Protected guard={introduced && !paired}>
        <Stack.Screen name="pair" />
      </Stack.Protected>

      <Stack.Protected guard={introduced && paired}>
        <Stack.Screen name="(tabs)" />
      </Stack.Protected>
    </Stack>
  );
}
