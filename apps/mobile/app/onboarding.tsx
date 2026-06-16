import { useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useHousehold } from '../lib/household';
import { useAuth } from '../lib/auth';
import { colors, radius, spacing } from '../lib/theme';

type Mode = 'create' | 'join';

export default function Onboarding() {
  const router = useRouter();
  const { createHousehold, joinHousehold } = useHousehold();
  const { signOut } = useAuth();
  const [mode, setMode] = useState<Mode>('create');
  const [value, setValue] = useState('');
  const [busy, setBusy] = useState(false);

  async function handleSubmit() {
    if (!value.trim()) {
      Alert.alert(mode === 'create' ? 'Name your household' : 'Enter an invite code');
      return;
    }
    try {
      setBusy(true);
      if (mode === 'create') {
        await createHousehold(value.trim());
      } else {
        await joinHousehold(value.trim());
      }
      router.replace('/(app)/(tabs)');
    } catch (e) {
      Alert.alert('Something went wrong', e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setBusy(false);
    }
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.container}>
        <Text style={styles.title}>Set up your household</Text>
        <Text style={styles.subtitle}>Create a new home or join one with an invite code.</Text>

        <View style={styles.toggle}>
          <Pressable
            style={[styles.toggleItem, mode === 'create' && styles.toggleItemActive]}
            onPress={() => setMode('create')}
          >
            <Text style={[styles.toggleText, mode === 'create' && styles.toggleTextActive]}>Create</Text>
          </Pressable>
          <Pressable
            style={[styles.toggleItem, mode === 'join' && styles.toggleItemActive]}
            onPress={() => setMode('join')}
          >
            <Text style={[styles.toggleText, mode === 'join' && styles.toggleTextActive]}>Join</Text>
          </Pressable>
        </View>

        <TextInput
          style={styles.input}
          placeholder={mode === 'create' ? 'e.g. The Smith Home' : 'Invite code (e.g. AB12CD34)'}
          placeholderTextColor={colors.muted}
          autoCapitalize={mode === 'create' ? 'words' : 'characters'}
          value={value}
          onChangeText={setValue}
        />

        <Pressable style={styles.button} onPress={handleSubmit} disabled={busy}>
          {busy ? (
            <ActivityIndicator color={colors.primaryText} />
          ) : (
            <Text style={styles.buttonText}>{mode === 'create' ? 'Create household' : 'Join household'}</Text>
          )}
        </Pressable>

        <Pressable onPress={() => signOut()} style={styles.signOut}>
          <Text style={styles.signOutText}>Sign out</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.bg },
  container: { flex: 1, justifyContent: 'center', padding: spacing.xl, gap: spacing.md },
  title: { fontSize: 26, fontWeight: '700', color: colors.text },
  subtitle: { fontSize: 15, color: colors.muted, marginBottom: spacing.sm },
  toggle: { flexDirection: 'row', backgroundColor: colors.card, borderRadius: radius.md, padding: spacing.xs, borderWidth: 1, borderColor: colors.border },
  toggleItem: { flex: 1, paddingVertical: 10, alignItems: 'center', borderRadius: radius.sm },
  toggleItemActive: { backgroundColor: colors.primary },
  toggleText: { fontSize: 15, fontWeight: '600', color: colors.muted },
  toggleTextActive: { color: colors.primaryText },
  input: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    padding: 14,
    fontSize: 16,
    color: colors.text,
  },
  button: { backgroundColor: colors.primary, borderRadius: radius.md, paddingVertical: 14, alignItems: 'center' },
  buttonText: { fontSize: 16, fontWeight: '600', color: colors.primaryText },
  signOut: { alignItems: 'center', marginTop: spacing.sm },
  signOutText: { color: colors.muted, fontSize: 14 },
});
