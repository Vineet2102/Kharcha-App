-- Every function here is SECURITY DEFINER. That is deliberate: they are the
-- only sanctioned way to change membership, and they run with rights the
-- caller does not have. Each one re-derives the caller from auth.uid() and
-- never trusts a caller-supplied user id.

-- ── invite code generation ───────────────────────────────────
-- 31-character alphabet, no O/0/I/1/L — these are read aloud and
-- retyped by hand, so ambiguity costs real support time.
create or replace function public.gen_invite_code()
returns text language plpgsql volatile set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_out text := '';
  i int;
begin
  -- `out` is a plpgsql parameter-mode keyword; do not name the variable that.
  for i in 1..8 loop
    v_out := v_out || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return v_out;
end;
$$;

create or replace function public.normalise_invite_code(p text)
returns text language sql immutable as $$
  select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g'))
$$;

-- ── per-household defaults (replaces the global 0009 seed) ───
create or replace function public.seed_household_defaults(p_household uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.categories (id, household_id, name, kind, icon_key, colour_hex, sort_order)
  select gen_random_uuid(), p_household, d.name, d.kind::public.category_kind,
         d.icon, d.colour, d.sort
  from (values
    ('Groceries',            'expense','shopping_cart',     '#4CAF50', 10),
    ('Eating Out',           'expense','restaurant',        '#FF9800', 20),
    ('Transport & Fuel',     'expense','local_gas_station', '#795548', 30),
    ('Utilities',            'expense','bolt',              '#03A9F4', 40),
    ('Rent / EMI',           'expense','home',              '#9C27B0', 50),
    ('Medical',              'expense','local_hospital',    '#E91E63', 60),
    ('Education',            'expense','school',            '#3F51B5', 70),
    ('Shopping',             'expense','shopping_bag',      '#F44336', 80),
    ('Entertainment',        'expense','movie',             '#009688', 90),
    ('Household Help',       'expense','cleaning_services', '#8BC34A',100),
    ('Gifts & Festivals',    'expense','card_giftcard',     '#FFC107',110),
    ('Subscriptions',        'expense','subscriptions',     '#673AB7',120),
    ('Travel',               'expense','flight',            '#00BCD4',130),
    ('Insurance',            'expense','shield',            '#607D8B',140),
    ('Miscellaneous',        'expense','more_horiz',        '#9E9E9E',999),
    ('Salary',               'income', 'payments',          '#4CAF50', 10),
    ('Business',             'income', 'business',          '#3F51B5', 20),
    ('Interest & Dividends', 'income', 'savings',           '#009688', 30),
    ('Rent Received',        'income', 'apartment',         '#795548', 40),
    ('Other Income',         'income', 'more_horiz',        '#9E9E9E',999)
  ) as d(name, kind, icon, colour, sort)
  on conflict do nothing;

  insert into public.payment_methods (id, household_id, name, type, sort_order)
  select gen_random_uuid(), p_household, d.name, d.type::public.pay_method_type, d.sort
  from (values
    ('Cash',        'cash',  10),
    ('UPI',         'upi',   20),
    ('Credit Card', 'card',  30),
    ('Debit Card',  'card',  40),
    ('Net Banking', 'bank',  50),
    ('Wallet',      'wallet',60)
  ) as d(name, type, sort)
  on conflict do nothing;
end;
$$;

-- ── internal: mint an invite ─────────────────────────────────
create or replace function public.create_invite_internal(
  p_household uuid, p_by uuid, p_days int default 30, p_max_uses int default 20
) returns text language plpgsql security definer set search_path = public as $$
declare v_code text; v_try int := 0;
begin
  loop
    v_try := v_try + 1;
    v_code := public.gen_invite_code();
    begin
      insert into public.household_invites (household_id, code, created_by, expires_at, max_uses)
      values (p_household, v_code, p_by, now() + (p_days || ' days')::interval, p_max_uses);
      return v_code;
    exception when unique_violation then
      if v_try >= 10 then raise exception 'could_not_generate_invite_code'; end if;
    end;
  end loop;
end;
$$;

-- ── create a household ───────────────────────────────────────
create or replace function public.create_household(p_name text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_hh uuid; v_code text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name_required'; end if;
  if length(trim(p_name)) > 60 then raise exception 'name_too_long'; end if;
  if (select household_id from public.profiles where id = v_uid) is not null then
    raise exception 'already_in_household';
  end if;

  insert into public.households (name, created_by)
  values (trim(p_name), v_uid)
  returning id into v_hh;

  perform set_config('kharcha.allow_membership_change', 'on', true);
  update public.profiles
     set household_id = v_hh, role = 'admin', joined_at = now(), updated_at = now()
   where id = v_uid;

  perform public.seed_household_defaults(v_hh);
  v_code := public.create_invite_internal(v_hh, v_uid);

  return jsonb_build_object('household_id', v_hh, 'name', trim(p_name), 'invite_code', v_code);
end;
$$;

-- ── join a household ─────────────────────────────────────────
create or replace function public.join_household(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_inv public.household_invites%rowtype; v_name text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if (select household_id from public.profiles where id = v_uid) is not null then
    raise exception 'already_in_household';
  end if;

  select * into v_inv
    from public.household_invites
   where code = public.normalise_invite_code(p_code)
     and is_active and revoked_at is null
     and expires_at > now()
     and use_count < max_uses
   for update;

  if not found then raise exception 'invalid_invite'; end if;

  select name into v_name from public.households
   where id = v_inv.household_id and is_active;
  if v_name is null then raise exception 'household_inactive'; end if;

  perform set_config('kharcha.allow_membership_change', 'on', true);
  update public.profiles
     set household_id = v_inv.household_id, role = 'member',
         joined_at = now(), updated_at = now()
   where id = v_uid;

  update public.household_invites set use_count = use_count + 1 where id = v_inv.id;

  return jsonb_build_object('household_id', v_inv.household_id, 'name', v_name);
end;
$$;

-- ── leave ────────────────────────────────────────────────────
-- The member's transactions stay with the household (§1.5). Only the
-- last admin is blocked, and only while other members remain.
create or replace function public.leave_household()
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_hh uuid; v_role public.member_role;
begin
  select household_id, role into v_hh, v_role from public.profiles where id = v_uid;
  if v_hh is null then raise exception 'not_in_household'; end if;

  if v_role = 'admin'
     and (select count(*) from public.profiles
           where household_id = v_hh and role = 'admin') = 1
     and (select count(*) from public.profiles where household_id = v_hh) > 1 then
    raise exception 'last_admin';
  end if;

  perform set_config('kharcha.allow_membership_change', 'on', true);
  update public.profiles
     set household_id = null, role = 'member', joined_at = null, updated_at = now()
   where id = v_uid;
end;
$$;

-- ── admin: change a member's role ────────────────────────────
create or replace function public.set_member_role(p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
declare v_hh uuid := public.current_household_id();
begin
  if not public.is_admin() then raise exception 'not_admin'; end if;
  if p_role not in ('admin','member') then raise exception 'bad_role'; end if;
  if v_hh is null then raise exception 'not_in_household'; end if;
  if (select household_id from public.profiles where id = p_user) is distinct from v_hh then
    raise exception 'not_a_member';
  end if;

  if p_role = 'member'
     and (select count(*) from public.profiles
           where household_id = v_hh and role = 'admin') = 1
     and (select role from public.profiles where id = p_user) = 'admin' then
    raise exception 'last_admin';
  end if;

  perform set_config('kharcha.allow_membership_change', 'on', true);
  update public.profiles
     set role = p_role::public.member_role, updated_at = now()
   where id = p_user;
end;
$$;

-- ── admin: deactivate/reactivate a member (T-14.3) ───────────
create or replace function public.set_member_active(p_user uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_hh uuid := public.current_household_id();
begin
  if not public.is_admin() then raise exception 'not_admin'; end if;
  if (select household_id from public.profiles where id = p_user) is distinct from v_hh then
    raise exception 'not_a_member';
  end if;
  if p_user = auth.uid() then raise exception 'cannot_deactivate_self'; end if;
  update public.profiles set is_active = p_active, updated_at = now() where id = p_user;
end;
$$;

-- ── admin: remove a member ───────────────────────────────────
create or replace function public.remove_member(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_hh uuid := public.current_household_id();
begin
  if not public.is_admin() then raise exception 'not_admin'; end if;
  if p_user = auth.uid() then raise exception 'use_leave_household'; end if;
  if (select household_id from public.profiles where id = p_user) is distinct from v_hh then
    raise exception 'not_a_member';
  end if;

  perform set_config('kharcha.allow_membership_change', 'on', true);
  update public.profiles
     set household_id = null, role = 'member', joined_at = null, updated_at = now()
   where id = p_user;
end;
$$;

-- ── admin: invite management ─────────────────────────────────
create or replace function public.create_invite(p_days int default 30, p_max_uses int default 20)
returns text language plpgsql security definer set search_path = public as $$
declare v_hh uuid := public.current_household_id();
begin
  if not public.is_admin() then raise exception 'not_admin'; end if;
  if v_hh is null then raise exception 'not_in_household'; end if;
  if p_days not between 1 and 365 then raise exception 'bad_expiry'; end if;
  -- one live code at a time keeps the UI honest about which code is "the" code
  update public.household_invites
     set is_active = false, revoked_at = now()
   where household_id = v_hh and is_active;
  return public.create_invite_internal(v_hh, auth.uid(), p_days, p_max_uses);
end;
$$;

create or replace function public.revoke_invites()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not_admin'; end if;
  update public.household_invites
     set is_active = false, revoked_at = now()
   where household_id = public.current_household_id() and is_active;
end;
$$;

-- ── liveness (D21) ───────────────────────────────────────────
create or replace function public.touch_activity()
returns void language plpgsql security definer set search_path = public as $$
declare v_hh uuid := public.current_household_id();
begin
  update public.profiles set last_seen_at = now() where id = auth.uid();
  if v_hh is not null then
    update public.households set last_active_at = now() where id = v_hh;
  end if;
end;
$$;
