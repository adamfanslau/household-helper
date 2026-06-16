-- Smoke test for RLS + household functions. Run against the LOCAL dev DB:
--   psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f supabase/tests/rls_smoke_test.sql
-- Each `expect ...` row below should show the commented value.

\set ON_ERROR_STOP on
\set ua '11111111-1111-1111-1111-111111111111'
\set ub '22222222-2222-2222-2222-222222222222'
\set uc '33333333-3333-3333-3333-333333333333'

-- Three auth users (as superuser).
insert into auth.users (id, email, aud, role)
values (:'ua', 'a@test.com', 'authenticated', 'authenticated'),
       (:'ub', 'b@test.com', 'authenticated', 'authenticated'),
       (:'uc', 'c@test.com', 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- ===== USER A: create a household, capture its id + invite code, add an item =====
set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :'ua', 'role', 'authenticated')::text, false);

select (create_household('Test Home')).id as hh \gset
select code as invite from household_invites where household_id = :'hh' \gset

insert into shopping_list_items (household_id, name, added_by) values (:'hh', 'Milk', :'ua');

select count(*) as a_sees_households from households;      -- expect 1
select count(*) as a_sees_items from shopping_list_items;  -- expect 1

-- ===== USER C (outsider): must see nothing =====
reset role; set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :'uc', 'role', 'authenticated')::text, false);

select count(*) as c_sees_households from households;      -- expect 0
select count(*) as c_sees_items from shopping_list_items;  -- expect 0

-- ===== USER B: join via the invite code, then must see A's data =====
reset role; set role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :'ub', 'role', 'authenticated')::text, false);

select join_household(:'invite') as joined_household;
select count(*) as b_sees_households from households;      -- expect 1
select name  as b_sees_item from shopping_list_items;      -- expect 'Milk'

-- ===== Invalid invite code must raise =====
\set ON_ERROR_STOP off
select join_household('BOGUS123');  -- expect ERROR: invalid or expired invite code
\set ON_ERROR_STOP on

reset role;
