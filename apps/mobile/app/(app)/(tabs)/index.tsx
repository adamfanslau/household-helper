import { useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SectionList,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../../../lib/auth';
import { useHousehold } from '../../../lib/household';
import { useRealtimeTable } from '../../../lib/useRealtimeTable';
import { supabase } from '../../../lib/supabase';
import { colors, radius, spacing } from '../../../lib/theme';
import type { Shop, ShoppingListItem } from '../../../types/database';

const UNSORTED = '__unsorted__';

export default function ShoppingListScreen() {
  const { session } = useAuth();
  const { current } = useHousehold();
  const [draft, setDraft] = useState('');
  const [showBought, setShowBought] = useState(false);

  const items = useRealtimeTable<ShoppingListItem>({
    table: 'shopping_list_items',
    filterColumn: 'household_id',
    filterValue: current?.id,
    orderBy: { column: 'created_at', ascending: true },
  });

  const shops = useRealtimeTable<Shop>({
    table: 'shops',
    filterColumn: 'household_id',
    filterValue: current?.id,
    orderBy: { column: 'sort_order', ascending: true },
  });

  const shopName = useMemo(() => {
    const map = new Map<string, string>();
    shops.rows.forEach((s) => map.set(s.id, s.name));
    return map;
  }, [shops.rows]);

  // Group "needed" items by shop into SectionList sections.
  const sections = useMemo(() => {
    const needed = items.rows.filter((i) => i.status === 'needed');
    const byShop = new Map<string, ShoppingListItem[]>();
    for (const item of needed) {
      const key = item.shop_id ?? UNSORTED;
      if (!byShop.has(key)) byShop.set(key, []);
      byShop.get(key)!.push(item);
    }
    const ordered = shops.rows
      .filter((s) => byShop.has(s.id))
      .map((s) => ({ key: s.id, title: s.name, data: byShop.get(s.id)! }));
    if (byShop.has(UNSORTED)) {
      ordered.push({ key: UNSORTED, title: 'Unsorted', data: byShop.get(UNSORTED)! });
    }
    return ordered;
  }, [items.rows, shops.rows]);

  const boughtItems = useMemo(
    () => items.rows.filter((i) => i.status === 'bought'),
    [items.rows],
  );

  async function addItem() {
    const name = draft.trim();
    if (!name || !current || !session) return;
    setDraft('');
    await supabase.from('shopping_list_items').insert({
      household_id: current.id,
      name,
      added_by: session.user.id,
    });
  }

  async function toggle(item: ShoppingListItem) {
    const next = item.status === 'needed' ? 'bought' : 'needed';
    await supabase
      .from('shopping_list_items')
      .update({ status: next, bought_at: next === 'bought' ? new Date().toISOString() : null })
      .eq('id', item.id);
  }

  async function remove(item: ShoppingListItem) {
    await supabase.from('shopping_list_items').delete().eq('id', item.id);
  }

  if (items.loading) {
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
          placeholder="Add something we ran out of…"
          placeholderTextColor={colors.muted}
          value={draft}
          onChangeText={setDraft}
          onSubmitEditing={addItem}
          returnKeyType="done"
        />
        <Pressable style={styles.addButton} onPress={addItem}>
          <Ionicons name="add" size={26} color={colors.primaryText} />
        </Pressable>
      </View>

      <SectionList
        sections={sections}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContent}
        stickySectionHeadersEnabled={false}
        renderSectionHeader={({ section }) => (
          <Text style={styles.sectionHeader}>{section.title}</Text>
        )}
        renderItem={({ item }) => (
          <View style={styles.itemRow}>
            <Pressable style={styles.itemMain} onPress={() => toggle(item)} hitSlop={8}>
              <Ionicons name="ellipse-outline" size={22} color={colors.muted} />
              <View>
                <Text style={styles.itemText}>{item.name}</Text>
                {item.quantity ? <Text style={styles.itemMeta}>{item.quantity}</Text> : null}
              </View>
            </Pressable>
            <Pressable onPress={() => remove(item)} hitSlop={8}>
              <Ionicons name="trash-outline" size={20} color={colors.muted} />
            </Pressable>
          </View>
        )}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyEmoji}>🎉</Text>
            <Text style={styles.emptyText}>Nothing to buy right now.</Text>
            <Text style={styles.emptyMeta}>Add items as they run out at home.</Text>
          </View>
        }
        ListFooterComponent={
          boughtItems.length > 0 ? (
            <View style={styles.boughtSection}>
              <Pressable style={styles.boughtToggle} onPress={() => setShowBought((s) => !s)}>
                <Ionicons
                  name={showBought ? 'chevron-down' : 'chevron-forward'}
                  size={16}
                  color={colors.muted}
                />
                <Text style={styles.boughtToggleText}>Recently bought ({boughtItems.length})</Text>
              </Pressable>
              {showBought &&
                boughtItems.map((item) => (
                  <View key={item.id} style={styles.itemRow}>
                    <Pressable style={styles.itemMain} onPress={() => toggle(item)} hitSlop={8}>
                      <Ionicons name="checkmark-circle" size={22} color={colors.primary} />
                      <Text style={[styles.itemText, styles.itemTextDone]}>{item.name}</Text>
                    </Pressable>
                    <Pressable onPress={() => remove(item)} hitSlop={8}>
                      <Ionicons name="trash-outline" size={20} color={colors.muted} />
                    </Pressable>
                  </View>
                ))}
            </View>
          ) : null
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
  sectionHeader: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.muted,
    textTransform: 'uppercase',
    marginTop: spacing.lg,
    marginBottom: spacing.xs,
  },
  itemRow: {
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
  itemMain: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, flex: 1 },
  itemText: { fontSize: 16, color: colors.text },
  itemTextDone: { textDecorationLine: 'line-through', color: colors.muted },
  itemMeta: { fontSize: 13, color: colors.muted, marginTop: 2 },
  empty: { alignItems: 'center', paddingTop: 80, gap: spacing.xs },
  emptyEmoji: { fontSize: 44 },
  emptyText: { fontSize: 17, fontWeight: '600', color: colors.text },
  emptyMeta: { fontSize: 14, color: colors.muted },
  boughtSection: { marginTop: spacing.lg },
  boughtToggle: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, paddingVertical: spacing.sm },
  boughtToggleText: { fontSize: 14, fontWeight: '600', color: colors.muted },
});
