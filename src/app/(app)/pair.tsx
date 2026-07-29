import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Field } from '@/components/ui/field';
import { Screen } from '@/components/ui/screen';
import { Radius, Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { confirmDestructive } from '@/lib/confirm';
import { DataError } from '@/lib/data';
import { useSession } from '@/lib/session';
import { t } from '@/lib/strings';
import type { LinkMode } from '@/lib/types';

type Step = 'mode' | 'join';

const MODES: { mode: LinkMode; label: string; hint: string; emoji: string; enabled: boolean }[] = [
  { mode: 'couple', label: t.pairing.modeCouple, hint: t.pairing.modeCoupleHint, emoji: '💞', enabled: true },
  { mode: 'friends', label: t.pairing.modeFriends, hint: t.pairing.modeFriendsHint, emoji: '🤝', enabled: true },
  { mode: 'random', label: t.pairing.modeRandom, hint: t.pairing.modeRandomHint, emoji: '🎲', enabled: false },
];

export default function PairScreen() {
  const theme = useTheme();
  const { link, createLink, joinLink, leaveLink, regenerateInvite, refresh, signOut } = useSession();
  const [step, setStep] = useState<Step>('mode');
  const [mode, setMode] = useState<LinkMode>('couple');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (e) {
      if (e instanceof DataError) {
        const map: Record<string, string> = {
          invalid_code: t.pairing.invalidCode,
          own_code: t.pairing.ownCode,
          link_full: t.pairing.full,
          already_linked: t.pairing.full,
        };
        setError(map[e.code] ?? e.message);
      } else {
        setError(e instanceof Error ? e.message : t.common.error);
      }
    } finally {
      setBusy(false);
    }
  };

  // A link exists but the partner has not joined yet: show the invite code.
  if (link && !link.partner) {
    const code = link.inviteCode;

    const copyCode = async () => {
      if (!code) return;
      await Clipboard.setStringAsync(code);
      setCopied(true);
    };

    return (
      <Screen>
        <View style={styles.header}>
          <ThemedText type="subtitle">{t.pairing.invite}</ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {code ? t.pairing.inviteHint : t.pairing.noCode}
          </ThemedText>
        </View>

        <Card>
          {/* Un code est consommé à l'appairage et purgé quand un membre part :
              sans ce chemin, le membre restant n'a plus rien à partager et sa
              seule sortie est le bouton destructeur plus bas. */}
          {code ? (
            <>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={t.pairing.copy}
                onPress={copyCode}
                style={[styles.codeBox, { backgroundColor: theme.accentSoft, borderColor: theme.border }]}>
                <ThemedText style={[styles.code, { color: theme.accent }]}>{code}</ThemedText>
              </Pressable>
              <Button label={copied ? t.pairing.copied : t.pairing.copy} variant="secondary" onPress={copyCode} />
            </>
          ) : (
            <Button
              label={t.pairing.regenerate}
              onPress={() =>
                void run(async () => {
                  await regenerateInvite();
                  await refresh();
                  setCopied(false);
                })
              }
              loading={busy}
            />
          )}
          <ThemedText type="small" themeColor="textSecondary" style={styles.center}>
            {t.pairing.waiting}
          </ThemedText>
          <Button label={t.common.retry} variant="ghost" onPress={() => void run(refresh)} loading={busy} />
          {error ? (
            <ThemedText type="small" themeColor="danger">
              {error}
            </ThemedText>
          ) : null}
        </Card>

        <Button
          label={t.profile.leave}
          variant="ghost"
          onPress={() =>
            confirmDestructive(t.profile.leave, t.profile.leaveConfirm, t.profile.leave, t.profile.cancel, () =>
              void run(leaveLink),
            )
          }
        />
      </Screen>
    );
  }

  if (step === 'join') {
    return (
      <Screen>
        <View style={styles.header}>
          <ThemedText type="subtitle">{t.pairing.haveCode}</ThemedText>
        </View>
        <Card>
          <Field
            label={t.pairing.codeLabel}
            value={code}
            onChangeText={(value) => setCode(value.toUpperCase())}
            autoCapitalize="characters"
            autoCorrect={false}
            maxLength={6}
            style={styles.codeInput}
          />
          <Button
            label={t.pairing.join}
            onPress={() => void run(() => joinLink(code))}
            loading={busy}
            disabled={code.trim().length !== 6}
          />
          {error ? (
            <ThemedText type="small" themeColor="danger">
              {error}
            </ThemedText>
          ) : null}
        </Card>
        <Button label={t.pairing.back} variant="ghost" onPress={() => setStep('mode')} />
      </Screen>
    );
  }

  return (
    <Screen>
      <View style={styles.header}>
        <ThemedText type="subtitle">{t.pairing.title}</ThemedText>
        <ThemedText type="small" themeColor="textSecondary">
          {t.pairing.subtitle}
        </ThemedText>
      </View>

      <View style={styles.modes}>
        {MODES.map((option) => {
          const selected = option.mode === mode;
          return (
            <Pressable
              key={option.mode}
              accessibilityRole="radio"
              accessibilityState={{ selected, disabled: !option.enabled }}
              disabled={!option.enabled}
              onPress={() => setMode(option.mode)}
              style={({ pressed }) => [
                styles.mode,
                {
                  backgroundColor: selected ? theme.accentSoft : theme.backgroundElement,
                  borderColor: selected ? theme.accent : theme.border,
                  opacity: option.enabled ? (pressed ? 0.85 : 1) : 0.45,
                },
              ]}>
              <ThemedText style={styles.modeEmoji}>{option.emoji}</ThemedText>
              <View style={styles.modeText}>
                <ThemedText type="smallBold">
                  {option.label}
                  {option.enabled ? '' : ` · ${t.pairing.comingSoon}`}
                </ThemedText>
                <ThemedText type="small" themeColor="textSecondary">
                  {option.hint}
                </ThemedText>
              </View>
            </Pressable>
          );
        })}
      </View>

      <View style={styles.actions}>
        <Button label={t.pairing.invite} onPress={() => void run(() => createLink(mode))} loading={busy} />
        <Button label={t.pairing.haveCode} variant="secondary" onPress={() => setStep('join')} />
        {error ? (
          <ThemedText type="small" themeColor="danger">
            {error}
          </ThemedText>
        ) : null}
      </View>

      <Button label={t.profile.signOut} variant="ghost" onPress={() => void signOut()} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  header: {
    gap: Spacing.two,
  },
  center: {
    textAlign: 'center',
  },
  modes: {
    gap: Spacing.three,
  },
  mode: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.three,
    padding: Spacing.three,
    borderRadius: Radius.lg,
    borderWidth: 1,
  },
  modeEmoji: {
    fontSize: 28,
    lineHeight: 34,
  },
  modeText: {
    flex: 1,
    gap: Spacing.half,
  },
  actions: {
    gap: Spacing.three,
  },
  codeBox: {
    alignItems: 'center',
    paddingVertical: Spacing.four,
    borderRadius: Radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
  },
  code: {
    fontSize: 40,
    lineHeight: 48,
    fontWeight: '700',
    letterSpacing: 6,
  },
  codeInput: {
    fontSize: 28,
    letterSpacing: 6,
    textAlign: 'center',
  },
});
