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
import { DataError, deviceTimeZone, type DataErrorCode } from '@/lib/data';
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
  const { profile, link, isDemo, updateProfile, setTimeZone, signOut, leaveLink } = useSession();
  const [name, setName] = useState(profile?.displayName ?? '');
  const [emoji, setEmoji] = useState(profile?.avatarEmoji ?? '☀️');
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Les DataError portent un code : sans ce mappage, c'est le texte PostgREST
  // en anglais qui atterrit dans une UI française.
  const MESSAGES: Partial<Record<DataErrorCode, string>> = {
    time_zone_cooldown: t.profile.timeZoneCooldown,
    invalid_time_zone: t.profile.timeZoneInvalid,
    no_link: t.profile.noLink,
  };

  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      return true;
    } catch (e) {
      if (e instanceof DataError) setError(MESSAGES[e.code] ?? t.common.error);
      else setError(e instanceof Error ? e.message : t.common.error);
      return false;
    } finally {
      setBusy(false);
    }
  };

  const save = async () => {
    const ok = await run(() => updateProfile({ displayName: name.trim() || 'Moi', avatarEmoji: emoji }));
    if (ok) setSaved(true);
  };

  // `leave_link` supprime le lien dès qu'il ne reste personne, et la cascade
  // emporte les souvenirs : jamais sans confirmation, web compris.
  const confirmLeave = () =>
    confirmDestructive(t.profile.leave, t.profile.leaveConfirm, t.profile.leave, t.profile.cancel, () =>
      void run(leaveLink),
    );

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
          {/* Pas de code d'invitation ici : cet écran n'est atteignable qu'une
              fois relié, et `join_link` consomme l'invite à l'appairage. Le
              code, et sa régénération, vivent sur l'écran d'appairage. */}

          <ThemedText type="smallBold">{t.profile.timeZone}</ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {t.profile.timeZoneHint(link.timeZone, link.dayStartHour)}
          </ThemedText>
          {link.timeZone !== deviceTimeZone() ? (
            <Button
              label={t.profile.timeZoneUse}
              variant="secondary"
              loading={busy}
              onPress={() => void run(() => setTimeZone(deviceTimeZone()))}
            />
          ) : null}
        </Card>
      ) : null}

      <Card>
        <ThemedText type="smallBold" themeColor="danger">
          {t.profile.danger}
        </ThemedText>
        {link ? (
          <Button label={t.profile.leave} variant="secondary" onPress={confirmLeave} loading={busy} />
        ) : null}
        <Button label={t.profile.signOut} variant="ghost" onPress={() => void run(signOut)} />
        {error ? (
          <ThemedText type="small" themeColor="danger">
            {error}
          </ThemedText>
        ) : null}
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
