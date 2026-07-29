import { Pressable, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { Radius, Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { t } from '@/lib/strings';
import type { Stance } from '@/lib/types';

const STANCES: Stance[] = [1, 2, 3, 4, 5];

type Props = {
  low: string;
  high: string;
  value: Stance | null;
  onChange?: (stance: Stance) => void;
  /** Position du partenaire, affichée une fois la révélation faite. */
  partner?: Stance | null;
  disabled?: boolean;
};

/**
 * Cinq boutons radio, pas un curseur.
 *
 * Un curseur React Native exige `accessibilityRole="adjustable"`,
 * `accessibilityValue` et des `accessibilityActions` pour être atteignable sous
 * VoiceOver et TalkBack ; cinq radios le sont par construction, et réutilisent
 * le patron déjà en place ailleurs dans l'app.
 */
export function StanceChoice({ low, high, value, onChange, partner, disabled }: Props) {
  const theme = useTheme();

  return (
    <View style={styles.wrap}>
      <View
        accessibilityRole="radiogroup"
        accessibilityLabel={`${low} — ${high}`}
        style={styles.row}>
        {STANCES.map((stance) => {
          const selected = value === stance;
          const partnerHere = partner === stance;
          return (
            <Pressable
              key={stance}
              accessibilityRole="radio"
              accessibilityState={{ selected, disabled: Boolean(disabled) }}
              accessibilityLabel={t.today.stanceLabel(stance, low, high)}
              disabled={disabled}
              onPress={() => onChange?.(stance)}
              style={({ pressed }) => [
                styles.dot,
                {
                  backgroundColor: selected ? theme.mine : theme.backgroundElement,
                  borderColor: selected ? theme.mine : partnerHere ? theme.theirs : theme.border,
                  // La position du partenaire se marque par une bordure épaisse
                  // et non par une simple couleur : la révélation ne doit pas
                  // reposer sur la seule distinction chromatique.
                  borderWidth: partnerHere ? 3 : 1,
                  opacity: disabled && !selected && !partnerHere ? 0.5 : 1,
                  transform: [{ scale: pressed ? 0.94 : 1 }],
                },
              ]}>
              <ThemedText
                type="smallBold"
                style={{ color: selected ? theme.accentText : theme.textSecondary }}>
                {stance}
              </ThemedText>
            </Pressable>
          );
        })}
      </View>

      <View style={styles.poles}>
        <ThemedText type="small" themeColor="textSecondary" style={styles.pole}>
          {low}
        </ThemedText>
        <ThemedText type="small" themeColor="textSecondary" style={[styles.pole, styles.poleEnd]}>
          {high}
        </ThemedText>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    gap: Spacing.two,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: Spacing.two,
  },
  dot: {
    flex: 1,
    // 48 pt : au-dessus de la cible tactile minimale, et la hauteur suit le
    // texte agrandi plutôt que d'être figée.
    minHeight: 48,
    borderRadius: Radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  poles: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: Spacing.three,
  },
  pole: {
    flex: 1,
  },
  poleEnd: {
    textAlign: 'right',
  },
});
