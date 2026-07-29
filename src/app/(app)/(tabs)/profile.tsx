import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { Alert, Platform, Pressable, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Field } from '@/components/ui/field';
import { Screen } from '@/components/ui/screen';
import { Radius, Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { useSession } from '@/lib/session';
import { t } from '@/lib/strings';

const EMOJIS = ['☀️', '🌙', '🌿', '🌸', '🔥', '🌊', '⭐️', '🍯'];

const MODE_LABELS: Record<string, string> = {
  couple: t.pairing.modeCouple,
  friends: t.pairing.modeFriends,
  random: t.pairing.modeRandom,
};

export default function ProfileScreen() {
  const theme = useTheme();
  const { profile, link, isDemo, updateProfile, signOut, leaveLink } = useSession();
  const [name, setName] = useState(profile?.displayName ?? '');
  const [emoji, setEmoji] = useState(profile?.avatarEmoji ?? '☀️');
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);

  const save = async () => {
    setBusy(true);
    try {
      await updateProfile({ displayName: name.trim() || 'Moi', avatarEmoji: emoji });
      setSaved(true);
    } finally {
      setBusy(false);
    }
  };

  const confirmLeave = () => {
    if (Platform.OS === 'web') {
      void leaveLink();
      return;
    }
    Alert.alert(t.profile.leave, t.profile.leaveConfirm, [
      { text: t.profile.cancel, style: 'cancel' },
      { text: t.profile.leave, style: 'destructive', onPress: () => void leaveLink() },
    ]);
  };

  return (
    <Screen withTabInset>
      <ThemedText type="subtitle">{t.profile.title}</ThemedText>

      {isDemo ? (
        <Card style={{ backgroundColor: theme.accentSoft }}>
          <ThemedText type="small" themeColor="textSecondary">
            {t.profile.demoBanner}
          </ThemedText>
        </Card>
      ) : null}

      <Card>
        <Field
          label={t.profile.displayName}
          value={name}
          onChangeText={(value) => {
            setName(value);
            setSaved(false);
          }}
        />

        <ThemedText type="smallBold" themeColor="textSecondary">
          {t.profile.avatar}
        </ThemedText>
        <View style={styles.emojiRow}>
          {EMOJIS.map((option) => (
            <Pressable
              key={option}
              accessibilityRole="radio"
              accessibilityState={{ selected: option === emoji }}
              onPress={() => {
                setEmoji(option);
                setSaved(false);
              }}
              style={[
                styles.emoji,
                {
                  backgroundColor: option === emoji ? theme.accentSoft : theme.background,
                  borderColor: option === emoji ? theme.accent : theme.border,
                },
              ]}>
              <ThemedText style={styles.emojiText}>{option}</ThemedText>
            </Pressable>
          ))}
        </View>

        <Button label={saved ? t.profile.saved : t.profile.save} onPress={save} loading={busy} />
      </Card>

      {link ? (
        <Card>
          <ThemedText type="smallBold">{t.profile.link}</ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {link.partner ? t.profile.linkedWith(link.partner.displayName) : t.pairing.waiting}
          </ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {t.profile.mode} · {MODE_LABELS[link.mode] ?? link.mode}
          </ThemedText>

          {link.inviteCode ? (
            <Pressable
              accessibilityRole="button"
              onPress={async () => {
                await Clipboard.setStringAsync(link.inviteCode as string);
                setCopied(true);
              }}>
              <ThemedText type="small" themeColor="textSecondary">
                {t.profile.inviteCode}
              </ThemedText>
              <ThemedText type="smallBold" style={{ color: theme.accent, letterSpacing: 4 }}>
                {link.inviteCode} {copied ? `· ${t.pairing.copied}` : ''}
              </ThemedText>
            </Pressable>
          ) : null}
        </Card>
      ) : null}

      <Card>
        <ThemedText type="smallBold" themeColor="danger">
          {t.profile.danger}
        </ThemedText>
        {link ? <Button label={t.profile.leave} variant="secondary" onPress={confirmLeave} /> : null}
        <Button label={t.profile.signOut} variant="ghost" onPress={() => void signOut()} />
      </Card>
    </Screen>
  );
}

const styles = StyleSheet.create({
  emojiRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: Spacing.two,
  },
  emoji: {
    width: 48,
    height: 48,
    borderRadius: Radius.pill,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emojiText: {
    fontSize: 22,
    lineHeight: 28,
  },
});
