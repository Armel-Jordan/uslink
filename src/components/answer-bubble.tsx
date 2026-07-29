import { Pressable, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { Radius, Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { REACTIONS } from '@/lib/prompt-library';
import type { Answer } from '@/lib/types';

type Props = {
  author: string;
  emoji: string;
  answer: Answer;
  /** 'mine' and 'theirs' get different accent colors so the two voices read apart. */
  voice: 'mine' | 'theirs';
  onReact?: (emoji: string) => void;
};

export function AnswerBubble({ author, emoji, answer, voice, onReact }: Props) {
  const theme = useTheme();
  const accent = voice === 'mine' ? theme.mine : theme.theirs;

  return (
    <View style={[styles.bubble, { backgroundColor: theme.backgroundElement, borderColor: theme.border }]}>
      <View style={[styles.stripe, { backgroundColor: accent }]} />
      <View style={styles.body}>
        <View style={styles.header}>
          <ThemedText type="small">{emoji}</ThemedText>
          <ThemedText type="smallBold" style={{ color: accent }}>
            {author}
          </ThemedText>
        </View>
        <ThemedText>{answer.body}</ThemedText>

        {answer.reactions.length > 0 ? (
          <View style={styles.reactionRow}>
            {answer.reactions.map((r, index) => (
              <ThemedText key={`${r}-${index}`} type="small">
                {r}
              </ThemedText>
            ))}
          </View>
        ) : null}

        {onReact ? (
          <View style={styles.reactionRow}>
            {REACTIONS.map((r) => (
              <Pressable
                key={r}
                accessibilityRole="button"
                accessibilityLabel={`Réagir avec ${r}`}
                onPress={() => onReact(r)}
                style={({ pressed }) => [
                  styles.reactionButton,
                  {
                    backgroundColor: answer.reactions.includes(r) ? theme.accentSoft : 'transparent',
                    borderColor: theme.border,
                    opacity: pressed ? 0.6 : 1,
                  },
                ]}>
                <ThemedText type="small">{r}</ThemedText>
              </Pressable>
            ))}
          </View>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  bubble: {
    flexDirection: 'row',
    borderRadius: Radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  stripe: {
    width: 4,
  },
  body: {
    flex: 1,
    padding: Spacing.three,
    gap: Spacing.two,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.two,
  },
  reactionRow: {
    flexDirection: 'row',
    gap: Spacing.two,
    flexWrap: 'wrap',
  },
  reactionButton: {
    paddingHorizontal: Spacing.two,
    paddingVertical: Spacing.one,
    borderRadius: Radius.pill,
    borderWidth: StyleSheet.hairlineWidth,
  },
});
