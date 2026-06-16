import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useAuth } from '../lib/auth';
import { colors, radius, spacing } from '../lib/theme';

export default function SignIn() {
  const { signInWithGoogle, signInWithMagicLink } = useAuth();
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState<null | 'google' | 'magic'>(null);
  const [sent, setSent] = useState(false);

  async function handleGoogle() {
    try {
      setBusy('google');
      await signInWithGoogle();
    } catch (e) {
      Alert.alert('Sign-in failed', e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setBusy(null);
    }
  }

  async function handleMagicLink() {
    if (!email.trim()) {
      Alert.alert('Enter your email first');
      return;
    }
    try {
      setBusy('magic');
      await signInWithMagicLink(email.trim());
      setSent(true);
    } catch (e) {
      Alert.alert('Could not send link', e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setBusy(null);
    }
  }

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <View style={styles.header}>
          <Text style={styles.emoji}>🛒</Text>
          <Text style={styles.title}>Household Helper</Text>
          <Text style={styles.subtitle}>Share one shopping list with your home.</Text>
        </View>

        <Pressable
          style={[styles.button, styles.googleButton]}
          onPress={handleGoogle}
          disabled={busy !== null}
        >
          {busy === 'google' ? (
            <ActivityIndicator color={colors.text} />
          ) : (
            <Text style={styles.googleText}>Continue with Google</Text>
          )}
        </Pressable>

        <View style={styles.divider}>
          <View style={styles.line} />
          <Text style={styles.dividerText}>or</Text>
          <View style={styles.line} />
        </View>

        {sent ? (
          <Text style={styles.sent}>
            Check your email for a magic link to {email.trim()}.
          </Text>
        ) : (
          <>
            <TextInput
              style={styles.input}
              placeholder="you@example.com"
              placeholderTextColor={colors.muted}
              autoCapitalize="none"
              keyboardType="email-address"
              autoComplete="email"
              value={email}
              onChangeText={setEmail}
            />
            <Pressable
              style={[styles.button, styles.primaryButton]}
              onPress={handleMagicLink}
              disabled={busy !== null}
            >
              {busy === 'magic' ? (
                <ActivityIndicator color={colors.primaryText} />
              ) : (
                <Text style={styles.primaryText}>Email me a magic link</Text>
              )}
            </Pressable>
          </>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.bg },
  container: { flex: 1, justifyContent: 'center', padding: spacing.xl, gap: spacing.md },
  header: { alignItems: 'center', marginBottom: spacing.xl, gap: spacing.xs },
  emoji: { fontSize: 56 },
  title: { fontSize: 28, fontWeight: '700', color: colors.text },
  subtitle: { fontSize: 15, color: colors.muted, textAlign: 'center' },
  button: { borderRadius: radius.md, paddingVertical: 14, alignItems: 'center', justifyContent: 'center' },
  googleButton: { backgroundColor: colors.card, borderWidth: 1, borderColor: colors.border },
  googleText: { fontSize: 16, fontWeight: '600', color: colors.text },
  primaryButton: { backgroundColor: colors.primary },
  primaryText: { fontSize: 16, fontWeight: '600', color: colors.primaryText },
  divider: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginVertical: spacing.sm },
  line: { flex: 1, height: 1, backgroundColor: colors.border },
  dividerText: { color: colors.muted },
  input: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    padding: 14,
    fontSize: 16,
    color: colors.text,
  },
  sent: { textAlign: 'center', color: colors.text, fontSize: 15 },
});
