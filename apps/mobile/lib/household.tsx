import React, { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { supabase } from './supabase';
import { useAuth } from './auth';
import type { Household } from '../types/database';

type HouseholdContextValue = {
  households: Household[];
  current: Household | null;
  loading: boolean;
  setCurrent: (h: Household) => void;
  createHousehold: (name: string) => Promise<Household>;
  joinHousehold: (code: string) => Promise<void>;
  refresh: () => Promise<void>;
};

const HouseholdContext = createContext<HouseholdContextValue | undefined>(undefined);

export function HouseholdProvider({ children }: { children: React.ReactNode }) {
  const { session } = useAuth();
  const [households, setHouseholds] = useState<Household[]>([]);
  const [current, setCurrent] = useState<Household | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    if (!session) {
      setHouseholds([]);
      setCurrent(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    // RLS restricts this to households the caller is a member of.
    const { data, error } = await supabase
      .from('households')
      .select('*')
      .order('created_at', { ascending: true });

    if (!error && data) {
      setHouseholds(data);
      setCurrent((prev) => data.find((h) => h.id === prev?.id) ?? data[0] ?? null);
    }
    setLoading(false);
  }, [session]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  async function createHousehold(name: string) {
    const { data, error } = await supabase.rpc('create_household', { p_name: name });
    if (error) throw error;
    await refresh();
    const created = data as Household;
    setCurrent(created);
    return created;
  }

  async function joinHousehold(code: string) {
    const { error } = await supabase.rpc('join_household', { p_code: code });
    if (error) throw error;
    await refresh();
  }

  return (
    <HouseholdContext.Provider
      value={{ households, current, loading, setCurrent, createHousehold, joinHousehold, refresh }}
    >
      {children}
    </HouseholdContext.Provider>
  );
}

export function useHousehold() {
  const ctx = useContext(HouseholdContext);
  if (!ctx) throw new Error('useHousehold must be used within a HouseholdProvider');
  return ctx;
}
