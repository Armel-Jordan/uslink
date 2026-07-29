import { useState } from 'react';
import { KeyboardAvoidingView, Platform, Pressable, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Field } from '@/components/ui/field';
import { Screen } from '@/components/ui/screen';
import { Radius, Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { useSession } from '@/lib/session';
import { t } from '@/lib/strings';
import { GOALS, INTERESTS, type Goal, type Interest } from '@/lib/types';

const GOAL_LABEL: Record<Goal, string> = {
  complicite: t.onboarding.goalCloseness,
  decouverte: t.onboarding.goalDiscovery,
  fun: t.onboarding.goalFun,
};

/** `YYYY-MM-DD`, ou null. Saisie libre plutôt qu'un sélecteur natif : une
 *  date approximative suffit, et un sélecteur de date impose un jour précis
 *  à quelqu'un qui ne s'en souvient pas. */
function parseDate(input: string): string | null {
  const m = input.trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return null;
  const [, y, mo, d] = m;
  const date = new Date(Number(y), Number(mo) - 1, Number(d));
  if (date.getFullYear() !== Number(y) || date.getMonth() !== Number(mo) - 1) return null;
  if (date.getTime() > Date.now()) return null;
  return `${y}-${mo}-${d}`;
}

export default function OnboardingScreen() {
  const theme = useTheme();
  const { profile, onboarding, updateProfile, saveOnboarding } = useSession();

  const [name, setName] = useState(profile?.displayName === 'Moi' ? '' : (profile?.displayName ?? ''));
  const [birth, setBirth] = useState(onboarding?.birthDate ?? '');
  const [city, setCity] = useState(onboarding?.city ?? '');
  const [started, setStarted] = useState(onboarding?.relationshipStartedOn ?? '');
  const [interests, setInterests] = useState<Interest[]>(onboarding?.interests ?? []);
  const [goals, setGoals] = useState<Goal[]>(onboarding?.goals ?? []);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = <T,>(list: T[], value: T): T[] =>
    list.includes(value) ? list.filter((x) => x !== value) : [...list, value];

  const save = async (completed: boolean) => {
    setBusy(true);
    setError(null);
    try {
      if (name.trim()) await updateProfile({ displayName: name.trim() });
      await saveOnboarding({
        birthDate: parseDate(birth),
        city: city.trim() || null,
        interests,
        goals,
        relationshipStartedOn: parseDate(started),
        completed,
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : t.common.error);
    } finally {
      setBusy(false);
    }
  };

  const chip = (selected: boolean) => [
    styles.chip,
    {
      backgroundColor: selected ? theme.accentSoft : theme.backgroundElement,
      borderColor: selected ? theme.accent : theme.border,
    },
  ];

  return (
    <Screen>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View style={styles.header}>
          <ThemedText type="subtitle">{t.onboarding.title}</ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {t.onboarding.subtitle}
          </ThemedText>
        </View>

        <Card>
          <Field label={t.onboarding.firstName} value={name} onChangeText={setName} autoCapitalize="words" />
          <Field
            label={t.onboarding.birthDate}
            value={birth}
            onChangeText={setBirth}
            placeholder="1990-05-04"
            keyboardType="numbers-and-punctuation"
            maxLength={10}
          />
          <Field
            label={t.onboarding.city}
            value={city}
            onChangeText={setCity}
            autoCapitalize="words"
            maxLength={60}
          />
          {/* Promesse tenue par la base, pas par la copie : `profile_onboarding`
              n'est lisible que par son propriétaire. */}
          <ThemedText type="small" themeColor="textSecondary">
            {t.onboarding.cityHint}
          </ThemedText>
        </Card>

        <Card>
          <Field
            label={t.onboarding.startedOn}
            value={started}
            onChangeText={setStarted}
            placeholder="2019-09-01"
            keyboardType="numbers-and-punctuation"
            maxLength={10}
          />
          <ThemedText type="small" themeColor="textSecondary">
            {t.onboarding.startedOnHint}
          </ThemedText>
        </Card>

        <Card>
          <ThemedText type="smallBold">{t.onboarding.interests}</ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {t.onboarding.interestsHint}
          </ThemedText>
          <View style={styles.chips}>
            {INTERESTS.map((key) => {
              const selected = interests.includes(key);
              return (
                <Pressable
                  key={key}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: selected }}
                  accessibilityLabel={t.interests[key]}
                  onPress={() => setInterests(toggle(interests, key))}
                  style={chip(selected)}>
                  <ThemedText type="small">{t.interests[key]}</ThemedText>
                </Pressable>
              );
            })}
          </View>
        </Card>

        <Card>
          <ThemedText type="smallBold">{t.onboarding.goals}</ThemedText>
          <View style={styles.chips}>
            {GOALS.map((key) => {
              const selected = goals.includes(key);
              return (
                <Pressable
                  key={key}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: selected }}
                  accessibilityLabel={GOAL_LABEL[key]}
                  onPress={() => setGoals(toggle(goals, key))}
                  style={chip(selected)}>
                  <ThemedText type="small">{GOAL_LABEL[key]}</ThemedText>
                </Pressable>
              );
            })}
          </View>
        </Card>

        <View style={styles.actions}>
          <Button label={t.onboarding.continue} loading={busy} onPress={() => void save(true)} />
          {/* Rien n'est obligatoire : un onboarding qu'on ne peut pas passer est
              un mur, et les contenus fonctionnent sans. */}
          <Button label={t.onboarding.later} variant="ghost" onPress={() => void save(true)} />
          {error ? (
            <ThemedText type="small" themeColor="danger">
              {error}
            </ThemedText>
          ) : null}
        </View>
      </KeyboardAvoidingView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  header: {
    gap: Spacing.two,
    marginBottom: Spacing.three,
  },
  chips: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.two,
  },
  chip: {
    paddingHorizontal: Spacing.three,
    // La hauteur vient du padding, pas d'une valeur figée : la cible tactile
    // survit ainsi à un texte agrandi.
    paddingVertical: Spacing.three,
    borderRadius: Radius.pill,
    borderWidth: 1,
  },
  actions: {
    gap: Spacing.two,
    marginTop: Spacing.three,
  },
});
