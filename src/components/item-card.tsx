import { useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { AnswerBubble } from '@/components/answer-bubble';
import { StanceChoice } from '@/components/stance-choice';
import { ThemedText } from '@/components/themed-text';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Field } from '@/components/ui/field';
import { Radius, Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { MIN_ANSWER_LENGTH } from '@/lib/prompt-library';
import { t } from '@/lib/strings';
import type { AnswerInput, ItemKind, ItemState, Stance } from '@/lib/types';

const KIND_LABEL: Record<ItemKind, string> = {
  debate: t.today.kindDebate,
  question: t.today.kindQuestion,
  challenge: t.today.kindChallenge,
};

type Props = {
  item: ItemState;
  partnerName: string;
  partnerEmoji: string;
  myEmoji: string;
  sending: boolean;
  onSubmit: (input: AnswerInput) => void;
  onReact: (answerId: string, emoji: string) => void;
};

export function ItemCard({ item, partnerName, partnerEmoji, myEmoji, sending, onSubmit, onReact }: Props) {
  const theme = useTheme();
  const { prompt, mine, theirs, revealed } = item;

  const [draft, setDraft] = useState(mine?.body ?? '');
  const [stance, setStance] = useState<Stance | null>(mine?.stance ?? null);

  const needsText = prompt.kind !== 'challenge';
  const missing = MIN_ANSWER_LENGTH - draft.trim().length;
  // Le gel est une règle de base : dès que l'autre a répondu, la ligne est
  // figée. Proposer une modification ne produirait qu'une erreur RLS brute.
  const frozen = Boolean(theirs);

  const send = () => {
    if (prompt.kind === 'challenge') return;
    if (missing > 0) return;
    onSubmit(
      prompt.kind === 'debate' && stance
        ? { kind: 'debate', stance, body: draft.trim() }
        : { kind: 'question', body: draft.trim() },
    );
  };

  return (
    <Card style={[styles.card, { borderColor: mine ? theme.border : theme.accent }]}>
      <View style={styles.header}>
        <View style={[styles.badge, { backgroundColor: theme.accentSoft }]}>
          <ThemedText type="small" style={{ color: theme.accent }}>
            {KIND_LABEL[prompt.kind]}
          </ThemedText>
        </View>
        <ThemedText type="small" themeColor="textSecondary">
          {prompt.category}
          {prompt.kind === 'challenge' && prompt.options && 'durationMin' in prompt.options
            ? ` · ${t.today.duration(prompt.options.durationMin)}`
            : ''}
        </ThemedText>
      </View>

      <ThemedText style={styles.question}>{prompt.question}</ThemedText>

      {/* ---------------------------------------------------------- répondre */}
      {!mine ? (
        prompt.kind === 'challenge' ? (
          <View style={styles.challengeActions}>
            <Button
              label={t.today.challengeDo}
              loading={sending}
              onPress={() => onSubmit({ kind: 'challenge', done: true })}
            />
            <Button
              label={t.today.challengeSkip}
              variant="ghost"
              onPress={() => onSubmit({ kind: 'challenge', done: false })}
            />
          </View>
        ) : (
          <>
            {prompt.kind === 'debate' && prompt.options && 'low' in prompt.options ? (
              <>
                <ThemedText type="smallBold" themeColor="textSecondary">
                  {t.today.yourStance}
                </ThemedText>
                <StanceChoice
                  low={prompt.options.low}
                  high={prompt.options.high}
                  value={stance}
                  onChange={setStance}
                />
              </>
            ) : null}
            <Field
              label={prompt.kind === 'debate' ? t.today.whyStance : t.today.yourAnswer}
              placeholder={t.today.placeholder}
              value={draft}
              onChangeText={setDraft}
              multiline
              maxLength={4000}
            />
            {missing > 0 && draft.length > 0 ? (
              <ThemedText type="small" themeColor="textSecondary">
                {t.today.tooShort(missing)}
              </ThemedText>
            ) : null}
            <Button
              label={t.today.send}
              onPress={send}
              loading={sending}
              disabled={missing > 0 || (prompt.kind === 'debate' && !stance)}
            />
          </>
        )
      ) : null}

      {/* ------------------------------------------------------------ révélé */}
      {mine ? (
        <View style={styles.answers}>
          {prompt.kind === 'debate' && prompt.options && 'low' in prompt.options ? (
            <StanceChoice
              low={prompt.options.low}
              high={prompt.options.high}
              value={mine.stance}
              partner={revealed ? theirs?.stance : null}
              disabled
            />
          ) : null}

          {prompt.kind === 'challenge' ? (
            <ThemedText type="smallBold" themeColor={mine.done ? 'success' : 'textSecondary'}>
              {mine.done ? t.today.challengeDone : t.today.challengeMissed}
            </ThemedText>
          ) : (
            <AnswerBubble author={t.today.you} emoji={myEmoji} answer={mine} voice="mine" />
          )}

          {revealed && theirs ? (
            prompt.kind === 'challenge' ? (
              <ThemedText type="small" themeColor="textSecondary">
                {partnerEmoji} {partnerName} · {theirs.done ? t.today.challengeDone : t.today.challengeMissed}
              </ThemedText>
            ) : (
              <AnswerBubble
                author={partnerName}
                emoji={partnerEmoji}
                answer={theirs}
                voice="theirs"
                onReact={(emoji) => onReact(theirs.id, emoji)}
              />
            )
          ) : (
            <ThemedText type="small" themeColor="textSecondary">
              ⏳ {t.today.waitingPartner(partnerName)}
            </ThemedText>
          )}

          {frozen && prompt.kind !== 'challenge' ? (
            <ThemedText type="small" themeColor="textSecondary">
              {t.today.frozen(partnerName)}
            </ThemedText>
          ) : null}
        </View>
      ) : null}
    </Card>
  );
}

const styles = StyleSheet.create({
  card: {
    borderWidth: 1,
    gap: Spacing.three,
  },
  header: {
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
    fontSize: 20,
    lineHeight: 28,
    fontWeight: '600',
  },
  challengeActions: {
    gap: Spacing.two,
  },
  answers: {
    gap: Spacing.three,
  },
});
