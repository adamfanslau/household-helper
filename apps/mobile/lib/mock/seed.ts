// Seed data for mock mode (EXPO_PUBLIC_USE_MOCK=1). Dev-only — this module is
// never evaluated in real mode and is dead-code-eliminated from release builds.
import type { Session } from '@supabase/supabase-js';
import type { Database } from '../../types/database';

export type TableName = keyof Database['public']['Tables'];
export type Tables = { [T in TableName]: Database['public']['Tables'][T]['Row'][] };

export const MOCK_USER_ID = '00000000-0000-4000-8000-000000000001';
export const MOCK_USER_EMAIL = 'dev@mock.local';

const HOUSEHOLD_ID = 'mock-household-1';
const NEIGHBOR_HOUSEHOLD_ID = 'mock-household-2';
const NEIGHBOR_USER_ID = '00000000-0000-4000-8000-000000000002';
const SHOP_TJ = 'mock-shop-tj';
const SHOP_COSTCO = 'mock-shop-costco';
const SHOP_PHARMACY = 'mock-shop-pharmacy';
const CATALOG_MILK = 'mock-catalog-milk';

// Fixed timestamps keep created_at ordering deterministic across reloads.
const t = (offsetMinutes: number) =>
  new Date(Date.parse('2026-01-01T10:00:00Z') + offsetMinutes * 60_000).toISOString();

// Typed as Session (not cast) so drift in supabase-js's shape fails typecheck.
export function makeMockSession(email: string = MOCK_USER_EMAIL): Session {
  return {
    access_token: 'mock-access-token',
    refresh_token: 'mock-refresh-token',
    token_type: 'bearer',
    expires_in: 3600 * 24 * 365,
    expires_at: Math.floor(Date.now() / 1000) + 3600 * 24 * 365,
    user: {
      id: MOCK_USER_ID,
      email,
      aud: 'authenticated',
      role: 'authenticated',
      app_metadata: { provider: 'mock' },
      user_metadata: {},
      created_at: t(0),
    },
  };
}

export function makeSeedTables(): Tables {
  return {
    households: [
      { id: HOUSEHOLD_ID, name: 'Mock Household', created_by: MOCK_USER_ID, created_at: t(0), updated_at: t(0) },
      // The mock user is NOT a member — join via invite code JOIN5678 in onboarding.
      { id: NEIGHBOR_HOUSEHOLD_ID, name: 'The Neighbors', created_by: NEIGHBOR_USER_ID, created_at: t(1), updated_at: t(1) },
    ],
    household_members: [
      { household_id: HOUSEHOLD_ID, user_id: MOCK_USER_ID, role: 'owner', joined_at: t(0) },
      { household_id: NEIGHBOR_HOUSEHOLD_ID, user_id: NEIGHBOR_USER_ID, role: 'owner', joined_at: t(1) },
    ],
    household_invites: [
      {
        id: 'mock-invite-1',
        household_id: HOUSEHOLD_ID,
        code: 'MOCK1234',
        created_by: MOCK_USER_ID,
        created_at: t(2),
        expires_at: null,
        revoked_at: null,
      },
      {
        id: 'mock-invite-2',
        household_id: NEIGHBOR_HOUSEHOLD_ID,
        code: 'JOIN5678',
        created_by: NEIGHBOR_USER_ID,
        created_at: t(2),
        expires_at: null,
        revoked_at: null,
      },
    ],
    shops: [
      { id: SHOP_TJ, household_id: HOUSEHOLD_ID, name: "Trader Joe's", sort_order: 0, created_at: t(3), updated_at: t(3) },
      { id: SHOP_COSTCO, household_id: HOUSEHOLD_ID, name: 'Costco', sort_order: 1, created_at: t(4), updated_at: t(4) },
      { id: SHOP_PHARMACY, household_id: HOUSEHOLD_ID, name: 'Pharmacy', sort_order: 2, created_at: t(5), updated_at: t(5) },
    ],
    catalog_items: [
      { id: CATALOG_MILK, shop_id: SHOP_TJ, name: 'Milk', default_unit: '1 gal', created_at: t(6), updated_at: t(6) },
      { id: 'mock-catalog-eggs', shop_id: SHOP_TJ, name: 'Eggs', default_unit: null, created_at: t(7), updated_at: t(7) },
      { id: 'mock-catalog-bananas', shop_id: SHOP_TJ, name: 'Bananas', default_unit: null, created_at: t(8), updated_at: t(8) },
      { id: 'mock-catalog-towels', shop_id: SHOP_COSTCO, name: 'Paper towels', default_unit: null, created_at: t(9), updated_at: t(9) },
      { id: 'mock-catalog-chicken', shop_id: SHOP_COSTCO, name: 'Chicken breast', default_unit: null, created_at: t(10), updated_at: t(10) },
    ],
    shopping_list_items: [
      {
        id: 'mock-item-milk',
        household_id: HOUSEHOLD_ID,
        name: 'Milk',
        shop_id: SHOP_TJ,
        catalog_item_id: CATALOG_MILK,
        quantity: '1 gal',
        status: 'needed',
        added_by: MOCK_USER_ID,
        created_at: t(11),
        updated_at: t(11),
        bought_at: null,
      },
      {
        id: 'mock-item-bananas',
        household_id: HOUSEHOLD_ID,
        name: 'Bananas',
        shop_id: SHOP_TJ,
        catalog_item_id: null,
        quantity: null,
        status: 'needed',
        added_by: MOCK_USER_ID,
        created_at: t(12),
        updated_at: t(12),
        bought_at: null,
      },
      {
        id: 'mock-item-towels',
        household_id: HOUSEHOLD_ID,
        name: 'Paper towels',
        shop_id: SHOP_COSTCO,
        catalog_item_id: null,
        quantity: null,
        status: 'needed',
        added_by: MOCK_USER_ID,
        created_at: t(13),
        updated_at: t(13),
        bought_at: null,
      },
      // shop_id null → exercises the "Unsorted" section on the list screen.
      {
        id: 'mock-item-batteries',
        household_id: HOUSEHOLD_ID,
        name: 'Batteries',
        shop_id: null,
        catalog_item_id: null,
        quantity: null,
        status: 'needed',
        added_by: MOCK_USER_ID,
        created_at: t(14),
        updated_at: t(14),
        bought_at: null,
      },
      // Already bought → exercises the "Recently bought" section.
      {
        id: 'mock-item-eggs',
        household_id: HOUSEHOLD_ID,
        name: 'Eggs',
        shop_id: SHOP_TJ,
        catalog_item_id: 'mock-catalog-eggs',
        quantity: null,
        status: 'bought',
        added_by: MOCK_USER_ID,
        created_at: t(15),
        updated_at: t(16),
        bought_at: t(16),
      },
    ],
  };
}
