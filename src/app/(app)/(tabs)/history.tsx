import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { AnswerBubble } from '@/components/answer-bubble';
import { ThemedText } from '@/components/themed-text';
import { Card } from '@/components/ui/card';
import { Screen } from '@/components/ui/screen';
import { Spacing } from '@/constants/theme';
import { data } from '@/lib/data';
import { useSession } from '@/lib/session';
import { t } from '@/lib/strings';
import type { HistoryEntry } from '@/lib/types';

function formatDate(iso: string) {
  const [year, month, day] = iso.split('-').map(Number);
  return new Date(year, month - 1, day).toLocaleDateString('fr-FR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
}

export default function HistoryScreen() {
  const { profile, link } = useSession();
  const [entries, setEntries] = useState<HistoryEntry[]>([]);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      setEntries(await data.getHistory());
    } catch {
      setEntries([]);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  const onRefresh = async () => {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  };

  return (
    <Screen refreshing={refreshing} onRefresh={onRefresh} withTabInset>
      <ThemedText type="subtitle">{t.history.title}</ThemedText>

      {entries.length === 0 ? (
        <Card>
          <ThemedText type="small" themeColor="textSecondary">
            {t.history.empty}
          </ThemedText>
        </Card>
      ) : (
        entries.map((entry) => (
          <Card key={entry.prompt.id} style={styles.entry}>
            <ThemedText type="small" themeColor="textSecondary" style={styles.date}>
              {formatDate(entry.prompt.date)}
            </ThemedText>
            <ThemedText type="smallBold" style={styles.question}>
              {entry.prompt.question}
            </ThemedText>

            {entry.mine ? (
              <AnswerBubble
                author={t.today.you}
                emoji={profile?.avatarEmoji ?? '☀️'}
                answer={entry.mine}
                voice="mine"
              />
            ) : (
              <ThemedText type="small" themeColor="textSecondary">
                {t.history.unanswered}
              </ThemedText>
            )}

            {entry.theirs ? (
              <AnswerBubble
                author={link?.partner?.displayName ?? '…'}
                emoji={link?.partner?.avatarEmoji ?? '🌙'}
                answer={entry.theirs}
                voice="theirs"
              />
            ) : entry.mine ? (
              <ThemedText type="small" themeColor="textSecondary">
                {t.history.onlyYou}
              </ThemedText>
            ) : null}
          </Card>
        ))
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  entry: {
    gap: Spacing.three,
  },
  date: {
    textTransform: 'capitalize',
  },
  question: {
    fontSize: 18,
    lineHeight: 26,
  },
});
