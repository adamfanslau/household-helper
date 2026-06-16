import { useEffect, useState } from 'react';
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
import { Stack, useLocalSearchParams } from 'expo-router';
import { useAuth } from '../../../lib/auth';
import { useHousehold } from '../../../lib/household';
import { useRealtimeTable } from '../../../lib/useRealtimeTable';
import { supabase } from '../../../lib/supabase';
import { colors, radius, spacing } from '../../../lib/theme';
import type { CatalogItem } from '../../../types/database';

export default function ShopDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const { current } = useHousehold();
  const [shopName, setShopName] = useState('Shop');
  const [draft, setDraft] = useState('');
  const [added, setAdded] = useState<Record<string, boolean>>({});

  const catalog = useRealtimeTable<CatalogItem>({
    table: 'catalog_items',
    filterColumn: 'shop_id',
    filterValue: id,
    orderBy: { column: 'name', ascending: true },
  });

  useEffect(() => {
    if (!id) return;
    supabase
      .from('shops')
      .select('name')
      .eq('id', id)
      .single()
      .then(({ data }) => data?.name && setShopName(data.name));
  }, [id]);

  async function addCatalogItem() {
    const name = draft.trim();
    if (!name || !id) return;
    setDraft('');
    await supabase.from('catalog_items').insert({ shop_id: id, name });
  }

  async function addToList(item: CatalogItem) {
    if (!current || !session) return;
    await supabase.from('shopping_list_items').insert({
      household_id: current.id,
      name: item.name,
      shop_id: id,
      catalog_item_id: item.id,
      added_by: session.user.id,
    });
    setAdded((prev) => ({ ...prev, [item.id]: true }));
    setTimeout(() => setAdded((prev) => ({ ...prev, [item.id]: false })), 1500);
  }

  async function removeCatalogItem(item: CatalogItem) {
    await supabase.from('catalog_items').delete().eq('id', item.id);
  }

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: shopName }} />

      <View style={styles.addRow}>
        <TextInput
          style={styles.input}
          placeholder="Add an item this shop sells"
          placeholderTextColor={colors.muted}
          value={draft}
          onChangeText={setDraft}
          onSubmitEditing={addCatalogItem}
          returnKeyType="done"
        />
        <Pressable style={styles.addButton} onPress={addCatalogItem}>
          <Ionicons name="add" size={26} color={colors.primaryText} />
        </Pressable>
      </View>

      {catalog.loading ? (
        <View style={styles.center}>
          <ActivityIndicator color={colors.primary} />
        </View>
      ) : (
        <FlatList
          data={catalog.rows}
          keyExtractor={(c) => c.id}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <View style={styles.row}>
              <Text style={styles.rowText}>{item.name}</Text>
              <View style={styles.rowActions}>
                <Pressable
                  style={[styles.pill, added[item.id] && styles.pillDone]}
                  onPress={() => addToList(item)}
                >
                  <Ionicons
                    name={added[item.id] ? 'checkmark' : 'add'}
                    size={16}
                    color={added[item.id] ? colors.primaryText : colors.primary}
                  />
                  <Text style={[styles.pillText, added[item.id] && styles.pillTextDone]}>
                    {added[item.id] ? 'Added' : 'To list'}
                  </Text>
                </Pressable>
                <Pressable onPress={() => removeCatalogItem(item)} hitSlop={8}>
                  <Ionicons name="trash-outline" size={20} color={colors.muted} />
                </Pressable>
              </View>
            </View>
          )}
          ListEmptyComponent={
            <View style={styles.empty}>
              <Text style={styles.emptyEmoji}>🧺</Text>
              <Text style={styles.emptyText}>No items for this shop yet.</Text>
              <Text style={styles.emptyMeta}>Add the things you usually buy here.</Text>
            </View>
          }
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
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
    paddingVertical: 14,
    marginBottom: spacing.sm,
  },
  rowText: { fontSize: 16, color: colors.text, flex: 1 },
  rowActions: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm,
    paddingVertical: 6,
  },
  pillDone: { backgroundColor: colors.primary, borderColor: colors.primary },
  pillText: { color: colors.primary, fontWeight: '600', fontSize: 13 },
  pillTextDone: { color: colors.primaryText },
  empty: { alignItems: 'center', paddingTop: 80, gap: spacing.xs },
  emptyEmoji: { fontSize: 44 },
  emptyText: { fontSize: 17, fontWeight: '600', color: colors.text },
  emptyMeta: { fontSize: 14, color: colors.muted },
});
