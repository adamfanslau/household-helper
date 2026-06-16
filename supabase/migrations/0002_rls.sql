-- Household Helper — Row-Level Security
-- Everything is scoped to households the caller belongs to. Membership mutations
-- (create / join) go through SECURITY DEFINER functions so direct inserts stay locked.

-- ---------------------------------------------------------------------------
-- Membership helper. SECURITY DEFINER so it can read household_members WITHOUT
-- triggering household_members' own RLS policy (avoids infinite recursion).
-- ---------------------------------------------------------------------------
create or replace function public.is_household_member(hid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.household_members m
    where m.household_id = hid
      and m.user_id = auth.uid()
  );
$$;

revoke all on function public.is_household_member(uuid) from public;
grant execute on function public.is_household_member(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- create_household: make a household, add the caller as owner, mint an invite.
-- ---------------------------------------------------------------------------
create or replace function public.create_household(p_name text)
returns public.households
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household public.households;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  insert into public.households (name, created_by)
  values (p_name, v_uid)
  returning * into v_household;

  insert into public.household_members (household_id, user_id, role)
  values (v_household.id, v_uid, 'owner');

  insert into public.household_invites (household_id, code, created_by)
  values (
    v_household.id,
    upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 8)),
    v_uid
  );

  return v_household;
end;
$$;

revoke all on function public.create_household(text) from public;
grant execute on function public.create_household(text) to authenticated;

-- ---------------------------------------------------------------------------
-- join_household: validate an invite code and add the caller as a member.
-- ---------------------------------------------------------------------------
create or replace function public.join_household(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.household_invites;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into v_invite
  from public.household_invites
  where code = upper(trim(p_code))
    and revoked_at is null
    and (expires_at is null or expires_at > now());

  if v_invite.id is null then
    raise exception 'invalid or expired invite code';
  end if;

  insert into public.household_members (household_id, user_id, role)
  values (v_invite.household_id, v_uid, 'member')
  on conflict (household_id, user_id) do nothing;

  return v_invite.household_id;
end;
$$;

revoke all on function public.join_household(text) from public;
grant execute on function public.join_household(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Table-level grants. RLS controls *which rows*; these grants control *access
-- at all*. Explicit here so the schema is self-contained on a hosted project.
-- ---------------------------------------------------------------------------
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------
alter table public.households          enable row level security;
alter table public.household_members   enable row level security;
alter table public.household_invites   enable row level security;
alter table public.shops               enable row level security;
alter table public.catalog_items       enable row level security;
alter table public.shopping_list_items enable row level security;

-- households -----------------------------------------------------------------
create policy "households: members read"
  on public.households for select to authenticated
  using (public.is_household_member(id));

create policy "households: members update"
  on public.households for update to authenticated
  using (public.is_household_member(id));

-- (insert handled by create_household; no direct insert policy)

-- household_members ----------------------------------------------------------
create policy "members: read co-members"
  on public.household_members for select to authenticated
  using (public.is_household_member(household_id));

create policy "members: leave household"
  on public.household_members for delete to authenticated
  using (user_id = auth.uid());

-- (insert handled by create_household / join_household)

-- household_invites ----------------------------------------------------------
create policy "invites: members read"
  on public.household_invites for select to authenticated
  using (public.is_household_member(household_id));

create policy "invites: members create"
  on public.household_invites for insert to authenticated
  with check (public.is_household_member(household_id) and created_by = auth.uid());

create policy "invites: members revoke"
  on public.household_invites for update to authenticated
  using (public.is_household_member(household_id));

-- shops ----------------------------------------------------------------------
create policy "shops: members read"
  on public.shops for select to authenticated
  using (public.is_household_member(household_id));

create policy "shops: members write"
  on public.shops for insert to authenticated
  with check (public.is_household_member(household_id));

create policy "shops: members update"
  on public.shops for update to authenticated
  using (public.is_household_member(household_id));

create policy "shops: members delete"
  on public.shops for delete to authenticated
  using (public.is_household_member(household_id));

-- catalog_items (scoped through their shop's household) ----------------------
create policy "catalog: members read"
  on public.catalog_items for select to authenticated
  using (exists (
    select 1 from public.shops s
    where s.id = catalog_items.shop_id and public.is_household_member(s.household_id)
  ));

create policy "catalog: members write"
  on public.catalog_items for insert to authenticated
  with check (exists (
    select 1 from public.shops s
    where s.id = catalog_items.shop_id and public.is_household_member(s.household_id)
  ));

create policy "catalog: members update"
  on public.catalog_items for update to authenticated
  using (exists (
    select 1 from public.shops s
    where s.id = catalog_items.shop_id and public.is_household_member(s.household_id)
  ));

create policy "catalog: members delete"
  on public.catalog_items for delete to authenticated
  using (exists (
    select 1 from public.shops s
    where s.id = catalog_items.shop_id and public.is_household_member(s.household_id)
  ));

-- shopping_list_items --------------------------------------------------------
create policy "list: members read"
  on public.shopping_list_items for select to authenticated
  using (public.is_household_member(household_id));

create policy "list: members add"
  on public.shopping_list_items for insert to authenticated
  with check (public.is_household_member(household_id) and added_by = auth.uid());

create policy "list: members update"
  on public.shopping_list_items for update to authenticated
  using (public.is_household_member(household_id));

create policy "list: members delete"
  on public.shopping_list_items for delete to authenticated
  using (public.is_household_member(household_id));
