import 'react-native-url-polyfill/auto';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AppState } from 'react-native';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';

function createRealClient(): SupabaseClient<Database> {
  // These are injected at build time by Expo from .env (EXPO_PUBLIC_* vars are
  // inlined and safe to ship — the anon key is meant to be public; RLS protects data).
  const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error(
      'Missing EXPO_PUBLIC_SUPABASE_URL / EXPO_PUBLIC_SUPABASE_ANON_KEY. Copy .env.example to .env and fill them in.',
    );
  }

  const client = createClient<Database>(supabaseUrl, supabaseAnonKey, {
    auth: {
      // AsyncStorage avoids the 2 KB size limit of expo-secure-store, which can
      // truncate JWT sessions. Anon-key + RLS is the security boundary here.
      storage: AsyncStorage,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  });

  // Keep tokens fresh only while the app is in the foreground.
  AppState.addEventListener('change', (state) => {
    if (state === 'active') {
      client.auth.startAutoRefresh();
    } else {
      client.auth.stopAutoRefresh();
    }
  });

  return client;
}

let client: SupabaseClient<Database>;

// Dev-only mock mode: an in-memory fake client so the app runs with no Supabase
// at all (npm run ios:mock / android:mock). The literal __DEV__ check keeps this
// branch — and the require'd mock modules — out of release bundles entirely.
if (__DEV__ && process.env.EXPO_PUBLIC_USE_MOCK === '1') {
  console.warn(
    '[MOCK MODE] Using an in-memory fake Supabase client — no backend, data resets on reload. ' +
      'Unset EXPO_PUBLIC_USE_MOCK to use the real client.',
  );
  const { createMockClient } = require('./mock/supabaseMock') as typeof import('./mock/supabaseMock');
  client = createMockClient();
} else {
  client = createRealClient();
}

export const supabase = client;
