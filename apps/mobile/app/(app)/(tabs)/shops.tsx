import { useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useHousehold } from '../../../lib/household';
import { useRealtimeTable } from '../../../lib/useRealtimeTable';
import { supabase } from '../../../lib/supabase';
import { colors, radius, spacing } from '../../../lib/theme';
import type { Shop } from '../../../types/database';

export default function ShopsScreen() {
  const router = useRouter();
  const { current } = useHousehold();
  const [draft, setDraft] = useState('');

  const shops = useRealtimeTable<Shop>({
    table: 'shops',
    filterColumn: 'household_id',
    filterValue: current?.id,
    orderBy: { column: 'sort_order', ascending: true },
  });

  async function addShop() {
    const name = draft.trim();
    if (!name || !current) return;
    setDraft('');
    await supabase.from('shops').insert({
      household_id: current.id,
      name,
      sort_order: shops.rows.length,
    });
  }

  if (shops.loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.addRow}>
        <TextInput
          style={styles.input}
          placeholder="Add a shop (e.g. Trader Joe's)"
          placeholderTextColor={colors.muted}
          value={draft}
          onChangeText={setDraft}
          onSubmitEditing={addShop}
          returnKeyType="done"
        />
        <Pressable style={styles.addButton} onPress={addShop}>
          <Ionicons name="add" size={26} color={colors.primaryText} />
        </Pressable>
      </View>

      <FlatList
        data={shops.rows}
        keyExtractor={(s) => s.id}
        contentContainerStyle={styles.listContent}
        renderItem={({ item }) => (
          <Pressable style={styles.row} onPress={() => router.push(`/(app)/shop/${item.id}`)}>
            <View style={styles.rowMain}>
              <Ionicons name="storefront-outline" size={22} color={colors.primary} />
              <Text style={styles.rowText}>{item.name}</Text>
            </View>
            <Ionicons name="chevron-forward" size={20} color={colors.muted} />
          </Pressable>
        )}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyEmoji}>🏬</Text>
            <Text style={styles.emptyText}>No shops yet.</Text>
            <Text style={styles.emptyMeta}>Add the stores your household buys from.</Text>
          </View>
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.bg },
  addRow: { flexDirection: 'row', gap: spacing.sm, padding: spacing.lg, paddingBottom: spacing.sm },
  input: {
    flex: 1,
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: 12,
    fontSize: 16,
    color: colors.text,
  },
  addButton: {
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    width: 48,
    alignItems: 'center',
    justifyContent: 'center',
  },
  listContent: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xl },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: 16,
    marginBottom: spacing.sm,
  },
  rowMain: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  rowText: { fontSize: 16, color: colors.text },
  empty: { alignItems: 'center', paddingTop: 80, gap: spacing.xs },
  emptyEmoji: { fontSize: 44 },
  emptyText: { fontSize: 17, fontWeight: '600', color: colors.text },
  emptyMeta: { fontSize: 14, color: colors.muted },
});
