import { useCallback, useEffect, useState } from 'react';
import type { RealtimePostgresChangesPayload } from '@supabase/supabase-js';
import { supabase } from './supabase';

type Row = { id: string };

function applyChange<T extends Row>(
  prev: T[],
  payload: RealtimePostgresChangesPayload<T>,
  sort?: (a: T, b: T) => number,
): T[] {
  switch (payload.eventType) {
    case 'INSERT': {
      const row = payload.new as T;
      const next = [...prev.filter((r) => r.id !== row.id), row];
      return sort ? next.sort(sort) : next;
    }
    case 'UPDATE': {
      const row = payload.new as T;
      const next = prev.map((r) => (r.id === row.id ? row : r));
      return sort ? next.sort(sort) : next;
    }
    case 'DELETE': {
      const old = payload.old as Partial<Row>;
      return prev.filter((r) => r.id !== old.id);
    }
    default:
      return prev;
  }
}

// Loads a household-scoped table and keeps it live via Supabase Realtime.
// Requires REPLICA IDENTITY FULL on the table so DELETE events carry the
// filtered column (see migration 0003_realtime.sql).
export function useRealtimeTable<T extends Row>(opts: {
  table: 'shopping_list_items' | 'shops' | 'catalog_items';
  filterColumn: string;
  filterValue: string | null | undefined;
  orderBy?: { column: string; ascending?: boolean };
  sort?: (a: T, b: T) => number;
}) {
  const { table, filterColumn, filterValue, orderBy, sort } = opts;
  const [rows, setRows] = useState<T[]>([]);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    if (!filterValue) {
      setRows([]);
      setLoading(false);
      return;
    }
    let query = supabase.from(table).select('*').eq(filterColumn, filterValue);
    if (orderBy) query = query.order(orderBy.column, { ascending: orderBy.ascending ?? true });
    const { data } = await query;
    setRows((data as unknown as T[]) ?? []);
    setLoading(false);
    // orderBy/sort are stable enough for our usage; intentionally narrow deps.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [table, filterColumn, filterValue]);

  useEffect(() => {
    reload();
    if (!filterValue) return;

    const channel = supabase
      .channel(`${table}:${filterColumn}:${filterValue}`)
      .on<T>(
        'postgres_changes',
        { event: '*', schema: 'public', table, filter: `${filterColumn}=eq.${filterValue}` },
        (payload) => setRows((prev) => applyChange(prev, payload, sort)),
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [table, filterColumn, filterValue]);

  return { rows, loading, reload, setRows };
}
