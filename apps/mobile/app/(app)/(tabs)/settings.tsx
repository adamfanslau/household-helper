import { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, Share, StyleSheet, Text, View } from 'react-native';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../../../lib/auth';
import { useHousehold } from '../../../lib/household';
import { supabase } from '../../../lib/supabase';
import { colors, radius, spacing } from '../../../lib/theme';

function randomCode() {
  return Array.from({ length: 8 }, () =>
    'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[Math.floor(Math.random() * 32)],
  ).join('');
}

export default function SettingsScreen() {
  const router = useRouter();
  const { session, signOut } = useAuth();
  const { current, households, setCurrent } = useHousehold();
  const [code, setCode] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!current) return;
    setLoading(true);
    supabase
      .from('household_invites')
      .select('code')
      .eq('household_id', current.id)
      .is('revoked_at', null)
      .order('created_at', { ascending: false })
      .limit(1)
      .then(({ data }) => {
        setCode(data?.[0]?.code ?? null);
        setLoading(false);
      });
  }, [current]);

  async function ensureCode(): Promise<string | null> {
    if (code) return code;
    if (!current || !session) return null;
    const newCode = randomCode();
    const { error } = await supabase
      .from('household_invites')
      .insert({ household_id: current.id, code: newCode, created_by: session.user.id });
    if (error) {
      Alert.alert('Could not create invite', error.message);
      return null;
    }
    setCode(newCode);
    return newCode;
  }

  async function shareInvite() {
    const c = await ensureCode();
    if (!c) return;
    await Share.share({
      message: `Join our household "${current?.name}" in Household Helper. Invite code: ${c}`,
    });
  }

  if (!current) return null;

  return (
    <View style={styles.container}>
      <Text style={styles.sectionLabel}>Household</Text>
      <View style={styles.card}>
        <Text style={styles.householdName}>{current.name}</Text>
        <Text style={styles.muted}>Signed in as {session?.user.email ?? 'you'}</Text>
      </View>

      <Text style={styles.sectionLabel}>Invite code</Text>
      <View style={styles.card}>
        {loading ? (
          <ActivityIndicator color={colors.primary} />
        ) : (
          <>
            <Text style={styles.code}>{code ?? 'No code yet'}</Text>
            <Text style={styles.muted}>Share this so others can join and see the same list.</Text>
            <Pressable style={styles.button} onPress={shareInvite}>
              <Ionicons name="share-outline" size={18} color={colors.primaryText} />
              <Text style={styles.buttonText}>Share invite</Text>
            </Pressable>
          </>
        )}
      </View>

      {households.length > 1 && (
        <>
          <Text style={styles.sectionLabel}>Switch household</Text>
          <View style={styles.card}>
            {households.map((h) => (
              <Pressable key={h.id} style={styles.switchRow} onPress={() => setCurrent(h)}>
                <Text style={styles.switchText}>{h.name}</Text>
                {h.id === current.id && (
                  <Ionicons name="checkmark" size={20} color={colors.primary} />
                )}
              </Pressable>
            ))}
          </View>
        </>
      )}

      <Pressable
        style={styles.addHousehold}
        onPress={() => router.push('/onboarding')}
      >
        <Ionicons name="add" size={18} color={colors.primary} />
        <Text style={styles.addHouseholdText}>Create or join another household</Text>
      </Pressable>

      <Pressable style={styles.signOut} onPress={() => signOut()}>
        <Text style={styles.signOutText}>Sign out</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg, padding: spacing.lg },
  sectionLabel: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    marginTop: spacing.lg,
    marginBottom: spacing.sm,
  },
  card: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    padding: spacing.lg,
    gap: spacing.sm,
  },
  householdName: { fontSize: 20, fontWeight: '700', color: colors.text },
  muted: { fontSize: 14, color: colors.muted },
  code: { fontSize: 28, fontWeight: '800', letterSpacing: 4, color: colors.primary },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: 12,
    marginTop: spacing.xs,
  },
  buttonText: { color: colors.primaryText, fontWeight: '600', fontSize: 15 },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: spacing.sm,
  },
  switchText: { fontSize: 16, color: colors.text },
  addHousehold: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, marginTop: spacing.lg },
  addHouseholdText: { color: colors.primary, fontWeight: '600', fontSize: 15 },
  signOut: { marginTop: 'auto', alignItems: 'center', paddingVertical: spacing.lg },
  signOutText: { color: colors.danger, fontSize: 16, fontWeight: '600' },
});
