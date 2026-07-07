// In-memory fake of the exact Supabase client surface this app uses. Dev-only:
// reached exclusively via the EXPO_PUBLIC_USE_MOCK branch in lib/supabase.ts.
//
// When a screen starts using a new call shape (e.g. .neq(), .insert().select()),
// extend this mock to match — drift shows up as an undefined method in dev.
import type { AuthChangeEvent, Session, SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../../types/database';
import {
  type AnyRow,
  type ChangeEvent,
  type TableName,
  emitChange,
  getRows,
  getSession,
  nextId,
  nowIso,
  onAuth,
  signIn as storeSignIn,
  signOut as storeSignOut,
  subscribeChanges,
} from './store';

type MockError = { message: string; code?: string };
type MockResult = { data: unknown; error: MockError | null };

function isMember(householdId: unknown, userId: string): boolean {
  return getRows('household_members').some(
    (m) => m.household_id === householdId && m.user_id === userId,
  );
}

function withInsertDefaults(table: TableName, row: AnyRow): AnyRow {
  const now = nowIso();
  switch (table) {
    case 'households':
      return { id: nextId('household'), created_by: null, created_at: now, updated_at: now, ...row };
    case 'household_members':
      return { role: 'member', joined_at: now, ...row };
    case 'household_invites':
      return {
        id: nextId('invite'),
        created_by: null,
        expires_at: null,
        revoked_at: null,
        created_at: now,
        ...row,
      };
    case 'shops':
      return { id: nextId('shop'), sort_order: 0, created_at: now, updated_at: now, ...row };
    case 'catalog_items':
      return { id: nextId('catalog'), default_unit: null, created_at: now, updated_at: now, ...row };
    case 'shopping_list_items':
      return {
        id: nextId('item'),
        shop_id: null,
        catalog_item_id: null,
        quantity: null,
        status: 'needed',
        added_by: null,
        bought_at: null,
        created_at: now,
        updated_at: now,
        ...row,
      };
  }
}

class MockQueryBuilder implements PromiseLike<MockResult> {
  private predicates: Array<(row: AnyRow) => boolean> = [];
  private orders: Array<{ column: string; ascending: boolean }> = [];
  private limitN: number | null = null;
  private singleMode = false;

  constructor(
    private readonly table: TableName,
    private readonly op: 'select' | 'insert' | 'update' | 'delete',
    private readonly payload: AnyRow | null = null,
  ) {}

  // Projection strings are ignored: full rows are a superset of any selection.
  select(_columns?: string): this {
    return this;
  }

  eq(column: string, value: unknown): this {
    this.predicates.push((row) => row[column] === value);
    return this;
  }

  is(column: string, value: unknown): this {
    this.predicates.push((row) => row[column] === value);
    return this;
  }

  order(column: string, opts?: { ascending?: boolean }): this {
    this.orders.push({ column, ascending: opts?.ascending ?? true });
    return this;
  }

  limit(n: number): this {
    this.limitN = n;
    return this;
  }

  single(): this {
    this.singleMode = true;
    return this;
  }

  // Execution is deferred until await/.then so chains built across statements
  // (and re-assigned chains, as in useRealtimeTable) see every modifier. Two
  // call sites use .then() without await, so this must be a real PromiseLike.
  then<TResult1 = MockResult, TResult2 = never>(
    onfulfilled?: ((value: MockResult) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve()
      .then(() => this.execute())
      .then(onfulfilled, onrejected);
  }

  private matches(row: AnyRow): boolean {
    return this.predicates.every((p) => p(row));
  }

  private compare(a: AnyRow, b: AnyRow): number {
    for (const { column, ascending } of this.orders) {
      const av = a[column];
      const bv = b[column];
      let cmp = 0;
      if (av == null && bv == null) cmp = 0;
      else if (av == null) cmp = 1; // nulls last
      else if (bv == null) cmp = -1;
      else if (typeof av === 'string' && typeof bv === 'string') cmp = av.localeCompare(bv);
      else cmp = (av as number) < (bv as number) ? -1 : (av as number) > (bv as number) ? 1 : 0;
      if (cmp !== 0) return ascending ? cmp : -cmp;
    }
    return 0;
  }

  private execute(): MockResult {
    switch (this.op) {
      case 'select':
        return this.runSelect();
      case 'insert':
        return this.runInsert();
      case 'update':
        return this.runUpdate();
      case 'delete':
        return this.runDelete();
    }
  }

  private runSelect(): MockResult {
    let rows = getRows(this.table).filter((r) => this.matches(r));

    // RLS-lite: like the real policies, only show households the current user
    // is a member of — keeps HouseholdProvider.refresh() and join flows honest.
    if (this.table === 'households') {
      const uid = getSession()?.user.id;
      rows = uid ? rows.filter((h) => isMember(h.id, uid)) : [];
    }

    if (this.orders.length > 0) rows = [...rows].sort((a, b) => this.compare(a, b));
    if (this.limitN !== null) rows = rows.slice(0, this.limitN);

    if (this.singleMode) {
      if (rows.length !== 1) {
        return {
          data: null,
          error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' },
        };
      }
      return { data: { ...rows[0] }, error: null };
    }
    return { data: rows.map((r) => ({ ...r })), error: null };
  }

  private runInsert(): MockResult {
    if (!this.payload) return { data: null, error: { message: 'Mock insert: missing payload' } };
    const row = withInsertDefaults(this.table, this.payload);
    getRows(this.table).push(row);
    emitChange({ table: this.table, eventType: 'INSERT', new: { ...row }, old: null });
    // Matches the real client when no .select() is chained (the app never chains one).
    return { data: null, error: null };
  }

  private runUpdate(): MockResult {
    if (!this.payload) return { data: null, error: { message: 'Mock update: missing payload' } };
    for (const row of getRows(this.table)) {
      if (!this.matches(row)) continue;
      const old = { ...row };
      Object.assign(row, this.payload);
      if ('updated_at' in row) row.updated_at = nowIso();
      emitChange({ table: this.table, eventType: 'UPDATE', new: { ...row }, old });
    }
    return { data: null, error: null };
  }

  private runDelete(): MockResult {
    const rows = getRows(this.table);
    const removed = rows.filter((r) => this.matches(r));
    for (const row of removed) {
      rows.splice(rows.indexOf(row), 1);
      // Full old row mirrors REPLICA IDENTITY FULL, which useRealtimeTable
      // relies on for the filter column and old.id.
      emitChange({ table: this.table, eventType: 'DELETE', new: null, old: { ...row } });
    }
    return { data: null, error: null };
  }
}

type PostgresChangesPayload = {
  schema: string;
  table: string;
  commit_timestamp: string;
  eventType: ChangeEvent['eventType'];
  new: AnyRow;
  old: AnyRow;
  errors: string[] | null;
};
type PostgresChangesCallback = (payload: PostgresChangesPayload) => void;

class MockChannel {
  private bindings: Array<{
    table: string;
    column: string | null;
    value: string | null;
    cb: PostgresChangesCallback;
  }> = [];
  private detach: (() => void) | null = null;

  on(
    _type: string,
    spec: { event?: string; schema?: string; table?: string; filter?: string },
    cb: PostgresChangesCallback,
  ): this {
    let column: string | null = null;
    let value: string | null = null;
    if (spec.filter) {
      // Split on the first '=eq.' — filter values are opaque strings.
      const idx = spec.filter.indexOf('=eq.');
      if (idx > 0) {
        column = spec.filter.slice(0, idx);
        value = spec.filter.slice(idx + '=eq.'.length);
      }
    }
    this.bindings.push({ table: spec.table ?? '', column, value, cb });
    return this;
  }

  subscribe(): this {
    this.detach = subscribeChanges((evt) => this.dispatch(evt));
    return this;
  }

  unsubscribe(): Promise<string> {
    this.detach?.();
    this.detach = null;
    return Promise.resolve('ok');
  }

  private dispatch(evt: ChangeEvent): void {
    for (const b of this.bindings) {
      if (b.table !== evt.table) continue;
      if (b.column !== null) {
        // Check old too, or DELETE events never reach their subscribers.
        const hit =
          (evt.new !== null && evt.new[b.column] === b.value) ||
          (evt.old !== null && evt.old[b.column] === b.value);
        if (!hit) continue;
      }
      b.cb({
        schema: 'public',
        table: evt.table,
        commit_timestamp: nowIso(),
        eventType: evt.eventType,
        new: evt.new ?? {},
        old: evt.old ?? {},
        errors: null,
      });
    }
  }
}

async function rpc(fn: string, args: Record<string, unknown> = {}): Promise<MockResult> {
  const session = getSession();
  if (!session) return { data: null, error: { message: 'Not signed in' } };
  const uid = session.user.id;

  if (fn === 'create_household') {
    const now = nowIso();
    const household = {
      id: nextId('household'),
      name: String(args.p_name ?? 'New household'),
      created_by: uid,
      created_at: now,
      updated_at: now,
    };
    getRows('households').push(household);
    getRows('household_members').push({
      household_id: household.id,
      user_id: uid,
      role: 'owner',
      joined_at: now,
    });
    emitChange({ table: 'households', eventType: 'INSERT', new: { ...household }, old: null });
    return { data: { ...household }, error: null };
  }

  if (fn === 'join_household') {
    const invite = getRows('household_invites').find(
      (i) => i.code === args.p_code && i.revoked_at === null,
    );
    if (!invite) return { data: null, error: { message: 'Invalid or expired invite code' } };
    if (!isMember(invite.household_id, uid)) {
      getRows('household_members').push({
        household_id: invite.household_id,
        user_id: uid,
        role: 'member',
        joined_at: nowIso(),
      });
    }
    return { data: invite.household_id, error: null };
  }

  if (fn === 'is_household_member') {
    return { data: isMember(args.hid, uid), error: null };
  }

  return { data: null, error: { message: `Mock rpc not implemented: ${fn}` } };
}

const auth = {
  async getSession() {
    return { data: { session: getSession() }, error: null };
  },
  onAuthStateChange(cb: (event: AuthChangeEvent, session: Session | null) => void) {
    const unsubscribe = onAuth(cb);
    return { data: { subscription: { unsubscribe } } };
  },
  async setSession(_tokens: { access_token: string; refresh_token: string }) {
    // Deep-link auth callbacks never fire in mock mode; keep the current session.
    return { data: { session: getSession(), user: getSession()?.user ?? null }, error: null };
  },
  async signInWithOAuth(_opts: unknown) {
    storeSignIn();
    // url: null → auth.tsx skips the browser flow; the session arrives via the listener.
    return { data: { provider: 'google', url: null }, error: null };
  },
  async signInWithOtp(opts: { email: string }) {
    storeSignIn(opts.email);
    return { data: { user: null, session: null }, error: null };
  },
  async signOut() {
    storeSignOut();
    return { error: null };
  },
};

// The exact surface the app consumes; typing the object against it (before the
// single cast below) keeps the mock itself honest under strict mode.
type MockClientShape = {
  auth: typeof auth;
  from(table: TableName): {
    select(columns?: string): MockQueryBuilder;
    insert(row: AnyRow): MockQueryBuilder;
    update(patch: AnyRow): MockQueryBuilder;
    delete(): MockQueryBuilder;
  };
  rpc(fn: string, args?: Record<string, unknown>): Promise<MockResult>;
  channel(name: string): MockChannel;
  removeChannel(channel: MockChannel): Promise<string>;
};

export function createMockClient(): SupabaseClient<Database> {
  const client: MockClientShape = {
    auth,
    from(table: TableName) {
      return {
        select: (_columns?: string) => new MockQueryBuilder(table, 'select'),
        insert: (row: AnyRow) => new MockQueryBuilder(table, 'insert', row),
        update: (patch: AnyRow) => new MockQueryBuilder(table, 'update', patch),
        delete: () => new MockQueryBuilder(table, 'delete'),
      };
    },
    rpc,
    channel: (_name: string) => new MockChannel(),
    removeChannel: (channel: MockChannel) => channel.unsubscribe(),
  };
  // Single deliberate cast: reproducing supabase-js's generic machinery in a
  // shared interface buys nothing at runtime and breaks on minor bumps.
  return client as unknown as SupabaseClient<Database>;
}
