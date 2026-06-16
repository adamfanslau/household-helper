// Hand-written to mirror supabase/migrations. Regenerate the authoritative
// version any time the schema changes with:
//   npx supabase gen types typescript --local > types/database.ts

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type ItemStatus = 'needed' | 'bought';
export type MemberRole = 'owner' | 'member';

export interface Database {
  public: {
    Tables: {
      households: {
        Row: { id: string; name: string; created_by: string | null; created_at: string; updated_at: string };
        Insert: { id?: string; name: string; created_by?: string | null };
        Update: { name?: string };
        Relationships: [];
      };
      household_members: {
        Row: { household_id: string; user_id: string; role: MemberRole; joined_at: string };
        Insert: { household_id: string; user_id: string; role?: MemberRole };
        Update: { role?: MemberRole };
        Relationships: [];
      };
      household_invites: {
        Row: {
          id: string;
          household_id: string;
          code: string;
          created_by: string | null;
          created_at: string;
          expires_at: string | null;
          revoked_at: string | null;
        };
        Insert: { household_id: string; code: string; created_by?: string | null; expires_at?: string | null };
        Update: { revoked_at?: string | null; expires_at?: string | null };
        Relationships: [];
      };
      shops: {
        Row: { id: string; household_id: string; name: string; sort_order: number; created_at: string; updated_at: string };
        Insert: { id?: string; household_id: string; name: string; sort_order?: number };
        Update: { name?: string; sort_order?: number };
        Relationships: [];
      };
      catalog_items: {
        Row: { id: string; shop_id: string; name: string; default_unit: string | null; created_at: string; updated_at: string };
        Insert: { id?: string; shop_id: string; name: string; default_unit?: string | null };
        Update: { name?: string; default_unit?: string | null };
        Relationships: [];
      };
      shopping_list_items: {
        Row: {
          id: string;
          household_id: string;
          name: string;
          shop_id: string | null;
          catalog_item_id: string | null;
          quantity: string | null;
          status: ItemStatus;
          added_by: string | null;
          created_at: string;
          updated_at: string;
          bought_at: string | null;
        };
        Insert: {
          id?: string;
          household_id: string;
          name: string;
          shop_id?: string | null;
          catalog_item_id?: string | null;
          quantity?: string | null;
          status?: ItemStatus;
          added_by?: string | null;
        };
        Update: { name?: string; shop_id?: string | null; quantity?: string | null; status?: ItemStatus; bought_at?: string | null };
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: {
      create_household: {
        Args: { p_name: string };
        Returns: Database['public']['Tables']['households']['Row'];
      };
      join_household: {
        Args: { p_code: string };
        Returns: string;
      };
      is_household_member: {
        Args: { hid: string };
        Returns: boolean;
      };
    };
    Enums: Record<string, never>;
  };
}

// Convenience row aliases used across the app.
export type Household = Database['public']['Tables']['households']['Row'];
export type Shop = Database['public']['Tables']['shops']['Row'];
export type CatalogItem = Database['public']['Tables']['catalog_items']['Row'];
export type ShoppingListItem = Database['public']['Tables']['shopping_list_items']['Row'];
export type HouseholdInvite = Database['public']['Tables']['household_invites']['Row'];
