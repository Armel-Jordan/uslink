import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, AppState, KeyboardAvoidingView, Platform, StyleSheet, View } from 'react-native';

import { ItemCard } from '@/components/item-card';
import { ThemedText } from '@/components/themed-text';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Screen } from '@/components/ui/screen';
import { Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { data } from '@/lib/data';
import { useSession } from '@/lib/session';
import { t } from '@/lib/strings';
import type { AnswerInput, TodayState } from '@/lib/types';

export default function TodayScreen() {
  const theme = useTheme();
  const { profile, link } = useSession();
  const [today, setToday] = useState<TodayState | null>(null);
  const [streak, setStreak] = useState(0);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [sending, setSending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      // La journée seule d'abord : la série est décorative, son échec ne doit
      // pas emporter la question du jour avec lui.
      setToday(await data.getToday());
    } catch (e) {
      setError(e instanceof Error ? e.message : t.common.error);
    }
    data
      .getStreak()
      .then(setStreak)
      .catch(() => setStreak(0));
  }, []);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      (async () => {
        await load();
        if (active) setLoading(false);
      })();

      // `useFocusEffect` ne se réarme pas au retour de veille : une app laissée
      // ouverte traverserait la bascule de journée en affichant celle d'hier.
      const sub = AppState.addEventListener('change', (next) => {
        if (next === 'active' && active) void load();
      });

      return () => {
        active = false;
        sub.remove();
      };
    }, [load]),
  );

  const onRefresh = async () => {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  };

  const submit = async (promptId: string, input: AnswerInput) => {
    setSending(promptId);
    setError(null);
    try {
      await data.submitAnswer(promptId, input);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : t.common.error);
    } finally {
      setSending(null);
    }
  };

  const react = async (answerId: string, emoji: string) => {
    try {
      await data.toggleReaction(answerId, emoji);
      await load();
    } catch {
      // Une réaction ratée ne vaut pas la peine d'interrompre le moment.
    }
  };

  if (loading) {
    return (
      <Screen scroll={false} withTabInset>
        <View style={styles.loading}>
          <ActivityIndicator color={theme.accent} />
          <ThemedText type="small" themeColor="textSecondary">
            {t.today.generating}
          </ThemedText>
        </View>
      </Screen>
    );
  }

  const partnerName = link?.partner?.displayName ?? '…';
  const partnerEmoji = link?.partner?.avatarEmoji ?? '🌙';
  const items = today?.items ?? [];
  const allAnswered = items.length > 0 && items.every((i) => i.mine);

  return (
    <Screen refreshing={refreshing} onRefresh={onRefresh} withTabInset>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View style={styles.header}>
          <ThemedText type="smallBold" themeColor="textSecondary">
            {t.today.greeting(profile?.displayName ?? '')}
          </ThemedText>
          {/* Le compteur vient du serveur (`days_together`), calculé dans le
              fuseau du lien : le recalculer ici avec `new Date()` rouvrirait
              l'horloge d'appareil que l'étape 2 a fermée. */}
          {link?.daysTogether !== null && link?.daysTogether !== undefined ? (
            <ThemedText type="smallBold" style={{ color: theme.accent }}>
              {t.today.together(link.daysTogether)}
            </ThemedText>
          ) : null}
          <ThemedText type="small" themeColor="textSecondary">
            {streak > 0 ? `🔥 ${t.today.streak(streak)}` : t.today.noStreak}
          </ThemedText>
        </View>

        {items.length > 0 ? (
          <View style={styles.items}>
            {items.map((item) => (
              <ItemCard
                // La clé porte l'état de réponse : sans elle, le brouillon
                // local d'une carte survivrait à sa propre soumission.
                key={`${item.prompt.id}:${item.mine ? 'a' : 'n'}:${item.theirs ? 'r' : 'w'}`}
                item={item}
                partnerName={partnerName}
                partnerEmoji={partnerEmoji}
                myEmoji={profile?.avatarEmoji ?? '☀️'}
                sending={sending === item.prompt.id}
                onSubmit={(input) => void submit(item.prompt.id, input)}
                onReact={react}
              />
            ))}
            {allAnswered ? (
              <ThemedText type="small" themeColor="textSecondary" style={styles.center}>
                {t.today.allAnswered}
              </ThemedText>
            ) : null}
          </View>
        ) : (
          <Card>
            <ThemedText type="small" themeColor="textSecondary">
              {t.today.alone}
            </ThemedText>
          </Card>
        )}

        {error ? (
          <View style={styles.error}>
            <ThemedText type="small" themeColor="danger">
              {error}
            </ThemedText>
            <Button label={t.common.retry} variant="ghost" onPress={() => void load()} />
          </View>
        ) : null}
      </KeyboardAvoidingView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: Spacing.three,
  },
  header: {
    gap: Spacing.half,
    marginBottom: Spacing.three,
  },
  items: {
    gap: Spacing.three,
  },
  center: {
    textAlign: 'center',
  },
  error: {
    gap: Spacing.two,
    marginTop: Spacing.three,
  },
});
