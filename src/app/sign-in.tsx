import { useState } from 'react';
import { KeyboardAvoidingView, Platform, StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Field } from '@/components/ui/field';
import { Screen } from '@/components/ui/screen';
import { Spacing } from '@/constants/theme';
import { useSession } from '@/lib/session';
import { t } from '@/lib/strings';

export default function SignInScreen() {
  const { signIn, signUp, isDemo } = useSession();
  const [mode, setMode] = useState<'signIn' | 'signUp'>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const submit = async () => {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      if (isDemo) {
        await signIn(email || 'demo@uslink.app', password || 'demo');
        return;
      }
      if (mode === 'signIn') {
        await signIn(email.trim(), password);
      } else {
        const { needsConfirmation } = await signUp(email.trim(), password, displayName.trim() || 'Moi');
        if (needsConfirmation) setMessage(t.auth.checkEmail);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : t.common.error);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen scroll={false}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={styles.flex}>
        <View style={styles.hero}>
          <ThemedText style={styles.logo}>💞</ThemedText>
          <ThemedText type="subtitle">{t.appName}</ThemedText>
          <ThemedText type="small" themeColor="textSecondary" style={styles.center}>
            {t.tagline}
          </ThemedText>
        </View>

        <Card>
          <ThemedText type="smallBold">
            {isDemo ? t.appName : mode === 'signIn' ? t.auth.signInTitle : t.auth.signUpTitle}
          </ThemedText>

          {isDemo ? (
            <>
              <ThemedText type="small" themeColor="textSecondary">
                {t.auth.demoNotice}
              </ThemedText>
              <Button label={t.auth.demoContinue} onPress={submit} loading={busy} />
            </>
          ) : (
            <>
              {mode === 'signUp' ? (
                <Field
                  label={t.auth.displayName}
                  value={displayName}
                  onChangeText={setDisplayName}
                  autoCapitalize="words"
                  autoComplete="name"
                />
              ) : null}

              <Field
                label={t.auth.email}
                value={email}
                onChangeText={setEmail}
                autoCapitalize="none"
                autoComplete="email"
                keyboardType="email-address"
                inputMode="email"
              />
              <Field
                label={t.auth.password}
                value={password}
                onChangeText={setPassword}
                secureTextEntry
                autoComplete={mode === 'signIn' ? 'current-password' : 'new-password'}
              />

              <Button
                label={mode === 'signIn' ? t.auth.signIn : t.auth.signUp}
                onPress={submit}
                loading={busy}
                disabled={!email.trim() || password.length < 6}
              />
              <Button
                label={mode === 'signIn' ? t.auth.toSignUp : t.auth.toSignIn}
                variant="ghost"
                onPress={() => {
                  setMode(mode === 'signIn' ? 'signUp' : 'signIn');
                  setError(null);
                  setMessage(null);
                }}
              />
            </>
          )}

          {message ? (
            <ThemedText type="small" themeColor="success">
              {message}
            </ThemedText>
          ) : null}
          {error ? (
            <ThemedText type="small" themeColor="danger">
              {error}
            </ThemedText>
          ) : null}
        </Card>
      </KeyboardAvoidingView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: {
    flex: 1,
    justifyContent: 'center',
    gap: Spacing.five,
  },
  hero: {
    alignItems: 'center',
    gap: Spacing.two,
  },
  logo: {
    fontSize: 56,
    lineHeight: 64,
  },
  center: {
    textAlign: 'center',
  },
});
