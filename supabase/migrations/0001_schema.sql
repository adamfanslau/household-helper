-- Household Helper — Iteration 1 schema
-- Shared shopping list: households, members, invites, shops, catalog items, list items.

create extension if not exists "pgcrypto"; -- gen_random_uuid()

-- Updates an `updated_at` column on row modification.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- households
-- ---------------------------------------------------------------------------
create table public.households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 100),
  created_by  uuid not null references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger households_set_updated_at
  before update on public.households
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- household_members  (user <-> household join)
-- ---------------------------------------------------------------------------
create table public.household_members (
  household_id  uuid not null references public.households (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  role          text not null default 'member' check (role in ('owner', 'member')),
  joined_at     timestamptz not null default now(),
  primary key (household_id, user_id)
);

create index household_members_user_id_idx on public.household_members (user_id);

-- ---------------------------------------------------------------------------
-- household_invites  (shareable join codes)
-- ---------------------------------------------------------------------------
create table public.household_invites (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households (id) on delete cascade,
  code          text not null unique,
  created_by    uuid not null references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz,
  revoked_at    timestamptz
);

create index household_invites_household_id_idx on public.household_invites (household_id);

-- ---------------------------------------------------------------------------
-- shops  (stores belonging to a household)
-- ---------------------------------------------------------------------------
create table public.shops (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households (id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 100),
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index shops_household_id_idx on public.shops (household_id);

create trigger shops_set_updated_at
  before update on public.shops
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- catalog_items  (reusable items available at a shop)
-- ---------------------------------------------------------------------------
create table public.catalog_items (
  id            uuid primary key default gen_random_uuid(),
  shop_id       uuid not null references public.shops (id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 100),
  default_unit  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index catalog_items_shop_id_idx on public.catalog_items (shop_id);

create trigger catalog_items_set_updated_at
  before update on public.catalog_items
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- shopping_list_items  (the live "need to buy" list)
-- ---------------------------------------------------------------------------
create table public.shopping_list_items (
  id               uuid primary key default gen_random_uuid(),
  household_id     uuid not null references public.households (id) on delete cascade,
  name             text not null check (char_length(name) between 1 and 200),
  shop_id          uuid references public.shops (id) on delete set null,
  catalog_item_id  uuid references public.catalog_items (id) on delete set null,
  quantity         text,
  status           text not null default 'needed' check (status in ('needed', 'bought')),
  added_by         uuid references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  bought_at        timestamptz
);

create index shopping_list_items_household_id_idx on public.shopping_list_items (household_id);
create index shopping_list_items_status_idx on public.shopping_list_items (household_id, status);
create index shopping_list_items_shop_id_idx on public.shopping_list_items (shop_id);

create trigger shopping_list_items_set_updated_at
  before update on public.shopping_list_items
  for each row execute function public.set_updated_at();
