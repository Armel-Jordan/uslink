import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';

import { AnswerBubble } from '@/components/answer-bubble';
import { ThemedText } from '@/components/themed-text';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Field } from '@/components/ui/field';
import { Screen } from '@/components/ui/screen';
import { Radius, Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { data } from '@/lib/data';
import { useSession } from '@/lib/session';
import { t } from '@/lib/strings';
import type { TodayState } from '@/lib/types';

export default function TodayScreen() {
  const theme = useTheme();
  const { profile, link } = useSession();
  const [today, setToday] = useState<TodayState | null>(null);
  const [streak, setStreak] = useState(0);
  const [draft, setDraft] = useState('');
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [next, nextStreak] = await Promise.all([data.getToday(), data.getStreak()]);
      setToday(next);
      setStreak(nextStreak);
      if (next?.mine && !editing) setDraft(next.mine.body);
    } catch (e) {
      setError(e instanceof Error ? e.message : t.common.error);
    }
  }, [editing]);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      (async () => {
        await load();
        if (active) setLoading(false);
      })();
      return () => {
        active = false;
      };
    }, [load]),
  );

  const onRefresh = async () => {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  };

  const send = async () => {
    if (!today || !draft.trim()) return;
    setSending(true);
    setError(null);
    try {
      await data.submitAnswer(today.prompt.id, draft.trim());
      setEditing(false);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : t.common.error);
    } finally {
      setSending(false);
    }
  };

  const react = async (answerId: string, emoji: string) => {
    try {
      await data.toggleReaction(answerId, emoji);
      await load();
    } catch {
      // A failed reaction is not worth interrupting the moment for.
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

  return (
    <Screen refreshing={refreshing} onRefresh={onRefresh} withTabInset>
      <View style={styles.header}>
        <View style={styles.headerText}>
          <ThemedText type="smallBold" themeColor="textSecondary">
            {t.today.greeting(profile?.displayName ?? '')}
          </ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {streak > 0 ? `🔥 ${t.today.streak(streak)}` : t.today.noStreak}
          </ThemedText>
        </View>
      </View>

      {today ? (
        <>
          <Card style={[styles.questionCard, { borderColor: theme.accent }]}>
            <View style={styles.badgeRow}>
              <View style={[styles.badge, { backgroundColor: theme.accentSoft }]}>
                <ThemedText type="small" style={{ color: theme.accent }}>
                  {today.prompt.category}
                </ThemedText>
              </View>
              <ThemedText type="small" themeColor="textSecondary">
                {today.prompt.source === 'ai' ? t.today.aiHint : t.today.libraryHint}
              </ThemedText>
            </View>
            <ThemedText style={styles.question}>{today.prompt.question}</ThemedText>
          </Card>

          {!today.mine || editing ? (
            <Card>
              <Field
                label={t.today.yourAnswer}
                placeholder={t.today.placeholder}
                value={draft}
                onChangeText={setDraft}
                multiline
              />
              <Button
                label={editing ? t.today.save : t.today.send}
                onPress={send}
                loading={sending}
                disabled={!draft.trim()}
              />
            </Card>
          ) : null}

          {today.mine && !editing ? (
            <View style={styles.answers}>
              {today.revealed ? (
                <ThemedText type="smallBold" themeColor="textSecondary">
                  {t.today.revealed}
                </ThemedText>
              ) : null}

              <AnswerBubble
                author={t.today.you}
                emoji={profile?.avatarEmoji ?? '☀️'}
                answer={today.mine}
                voice="mine"
              />

              {today.revealed && today.theirs ? (
                <AnswerBubble
                  author={partnerName}
                  emoji={partnerEmoji}
                  answer={today.theirs}
                  voice="theirs"
                  onReact={(emoji) => void react(today.theirs!.id, emoji)}
                />
              ) : (
                <Card style={styles.waiting}>
                  <ThemedText type="small" themeColor="textSecondary">
                    ⏳ {t.today.waitingPartner(partnerName)}
                  </ThemedText>
                </Card>
              )}

              <Button
                label={t.today.edit}
                variant="ghost"
                onPress={() => {
                  setDraft(today.mine?.body ?? '');
                  setEditing(true);
                }}
              />
            </View>
          ) : null}
        </>
      ) : (
        <Card>
          <ThemedText type="small" themeColor="textSecondary">
            {t.today.alone}
          </ThemedText>
        </Card>
      )}

      {error ? (
        <ThemedText type="small" themeColor="danger">
          {error}
        </ThemedText>
      ) : null}
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
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  headerText: {
    gap: Spacing.half,
  },
  questionCard: {
    borderWidth: 1,
  },
  badgeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: Spacing.two,
  },
  badge: {
    paddingHorizontal: Spacing.two,
    paddingVertical: Spacing.one,
    borderRadius: Radius.pill,
  },
  question: {
    fontSize: 24,
    lineHeight: 32,
    fontWeight: '600',
  },
  answers: {
    gap: Spacing.three,
  },
  waiting: {
    padding: Spacing.three,
  },
});
