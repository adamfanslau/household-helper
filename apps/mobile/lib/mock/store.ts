// In-memory backing store for mock mode: fake tables, session state, and a
// change bus that stands in for Supabase Realtime.
//
// Lifetime: module-level state survives Fast Refresh of other files; a full
// reload (or editing the mock files themselves) resets everything to seed.
import type { AuthChangeEvent, Session } from '@supabase/supabase-js';
import { makeMockSession, makeSeedTables, type TableName, type Tables } from './seed';

export type { TableName } from './seed';

export type AnyRow = Record<string, unknown>;

export type ChangeEvent = {
  table: TableName;
  eventType: 'INSERT' | 'UPDATE' | 'DELETE';
  new: AnyRow | null;
  old: AnyRow | null;
};

const tables: Tables = makeSeedTables();

export function getRows(table: TableName): AnyRow[] {
  return tables[table] as AnyRow[];
}

let idCounter = 0;

// Counter-based ids: crypto.randomUUID isn't guaranteed under Hermes, and the
// app only ever compares ids as opaque strings.
export function nextId(prefix: string): string {
  idCounter += 1;
  return `mock-${prefix}-${idCounter}`;
}

export function nowIso(): string {
  return new Date().toISOString();
}

// --- Change bus (fake realtime) ---

type ChangeListener = (evt: ChangeEvent) => void;
const changeListeners = new Set<ChangeListener>();

export function subscribeChanges(fn: ChangeListener): () => void {
  changeListeners.add(fn);
  return () => changeListeners.delete(fn);
}

// Microtask dispatch avoids re-entrancy while the triggering mutation is still
// being awaited, and matches the async feel of real Realtime.
export function emitChange(evt: ChangeEvent): void {
  queueMicrotask(() => {
    for (const fn of changeListeners) fn(evt);
  });
}

// --- Auth state ---

type AuthListener = (event: AuthChangeEvent, session: Session | null) => void;
const authListeners = new Set<AuthListener>();

// Boot pre-signed-in so `npm run ios:mock` lands in the app with zero taps.
let currentSession: Session | null = makeMockSession();

export function getSession(): Session | null {
  return currentSession;
}

export function signIn(email?: string): Session {
  currentSession = makeMockSession(email);
  const session = currentSession;
  queueMicrotask(() => {
    for (const fn of authListeners) fn('SIGNED_IN', session);
  });
  return session;
}

export function signOut(): void {
  currentSession = null;
  queueMicrotask(() => {
    for (const fn of authListeners) fn('SIGNED_OUT', null);
  });
}

export function onAuth(fn: AuthListener): () => void {
  authListeners.add(fn);
  return () => authListeners.delete(fn);
}
