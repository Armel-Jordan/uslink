import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { AnswerBubble } from '@/components/answer-bubble';
import { StanceChoice } from '@/components/stance-choice';
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
        // Une journée est l'unité de souvenir, pas un contenu : on relit un
        // jour de sa vie, pas une question isolée.
        entries.map((entry) => (
          <Card key={entry.date} style={styles.entry}>
            <View style={styles.dayHeader}>
              <ThemedText type="small" themeColor="textSecondary" style={styles.date}>
                {formatDate(entry.date)}
              </ThemedText>
              <ThemedText type="small" themeColor="textSecondary">
                {t.history.dayItems(entry.items.length)}
              </ThemedText>
            </View>

            {entry.items.map(({ prompt, mine, theirs }) => (
              <View key={prompt.id} style={styles.item}>
                <ThemedText type="smallBold" style={styles.question}>
                  {prompt.question}
                </ThemedText>

                {prompt.kind === 'challenge' ? (
                  <ThemedText type="small" themeColor="textSecondary">
                    {mine
                      ? `${t.today.you} · ${mine.done ? t.today.challengeDone : t.today.challengeMissed}`
                      : t.history.unanswered}
                    {theirs
                      ? `   ${link?.partner?.displayName ?? '…'} · ${theirs.done ? t.today.challengeDone : t.today.challengeMissed}`
                      : ''}
                  </ThemedText>
                ) : (
                  <>
                    {prompt.kind === 'debate' && prompt.options && 'low' in prompt.options ? (
                      <StanceChoice
                        low={prompt.options.low}
                        high={prompt.options.high}
                        value={mine?.stance ?? null}
                        partner={theirs?.stance ?? null}
                        disabled
                      />
                    ) : null}

                    {mine ? (
                      <AnswerBubble
                        author={t.today.you}
                        emoji={profile?.avatarEmoji ?? '☀️'}
                        answer={mine}
                        voice="mine"
                      />
                    ) : (
                      <ThemedText type="small" themeColor="textSecondary">
                        {t.history.unanswered}
                      </ThemedText>
                    )}

                    {theirs ? (
                      <AnswerBubble
                        author={link?.partner?.displayName ?? '…'}
                        emoji={link?.partner?.avatarEmoji ?? '🌙'}
                        answer={theirs}
                        voice="theirs"
                      />
                    ) : mine ? (
                      <ThemedText type="small" themeColor="textSecondary">
                        {t.history.onlyYou}
                      </ThemedText>
                    ) : null}
                  </>
                )}
              </View>
            ))}
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
  dayHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: Spacing.two,
  },
  item: {
    gap: Spacing.two,
  },
  date: {
    textTransform: 'capitalize',
  },
  question: {
    fontSize: 18,
    lineHeight: 26,
  },
});
