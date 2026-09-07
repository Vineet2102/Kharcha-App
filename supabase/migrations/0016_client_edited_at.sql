-- Decouple "true client edit time" (used for cross-device LWW conflict
-- resolution) from `updated_at` (used for selectSince()'s cursor pagination
-- and kept monotonic by touch_updated_at()'s GREATEST(now(), incoming)).
--
-- Bug (docs/DECISIONS.md, Gate 4 / T-M2.11 2026-09-07): after any real
-- offline stretch, touch_updated_at() always advances `updated_at` past a
-- client's genuine edit time to the server's receipt time (now() is later
-- than any already-happened edit, by construction). Comparing `updated_at`
-- across two devices to decide "which edit is newer" therefore actually
-- decides "whichever device's push reached the server later" — sensitive
-- to each device's own reconnect delay, not the real edit order.
--
-- Fix: `client_edited_at` carries the client's claimed edit timestamp
-- through completely untouched (no trigger, no floor/ceiling), so the
-- client's conflict-resolution code (`_updatedAtOf` in
-- entity_sync_adapters.dart) can compare genuine edit times, while
-- `updated_at` keeps doing its existing, unrelated job for the pull
-- cursor. Simply clamping touch_updated_at() against the row's own
-- previous `updated_at` instead of `now()` was considered and rejected:
-- it would reopen a lost-update bug on the *pull* side — an offline
-- device's edit could still land with a timestamp behind another
-- device's already-advanced pull cursor, and that device would never see
-- it. Keeping `updated_at` server-clock-monotonic avoids that; a separate
-- column avoids conflating the two jobs.
do $$
declare t text;
begin
  foreach t in array array[
    'households','profiles','categories','payment_methods',
    'expenses','incomes','attachments','budgets','recurring_rules'
  ] loop
    execute format('alter table public.%1$s add column if not exists client_edited_at timestamptz;', t);
    execute format('update public.%1$s set client_edited_at = updated_at where client_edited_at is null;', t);
    execute format('alter table public.%1$s alter column client_edited_at set not null;', t);
    execute format('alter table public.%1$s alter column client_edited_at set default now();', t);
  end loop;
end $$;

-- The membership RPCs (0012_household_functions.sql) write `profiles`
-- directly, outside the client's normal outbox/CAS push path — no payload
-- from a device, so nothing else will ever stamp `client_edited_at` for
-- these writes. Left unstamped, a stale `client_edited_at` here could
-- make a genuinely older, still-unpushed local profile edit compare as
-- "newer" than one of these authoritative, unambiguously-now RPC changes
-- (e.g. an admin's deactivate) once the device holding that stale edit
-- reconnects — the same class of bug this migration exists to fix,
-- just via the RPC path instead of the reconnect-delay one. Re-declaring
-- each function (`create or replace`) to add the one extra assignment;
-- everything else is byte-identical to 0012.

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
     set household_id = v_hh, role = 'admin', joined_at = now(),
         updated_at = now(), client_edited_at = now()
   where id = v_uid;

  perform public.seed_household_defaults(v_hh);
  v_code := public.create_invite_internal(v_hh, v_uid);

  return jsonb_build_object('household_id', v_hh, 'name', trim(p_name), 'invite_code', v_code);
end;
$$;

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
         joined_at = now(), updated_at = now(), client_edited_at = now()
   where id = v_uid;

  update public.household_invites set use_count = use_count + 1 where id = v_inv.id;

  return jsonb_build_object('household_id', v_inv.household_id, 'name', v_name);
end;
$$;

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
     set household_id = null, role = 'member', joined_at = null,
         updated_at = now(), client_edited_at = now()
   where id = v_uid;
end;
$$;

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
     set role = p_role::public.member_role, updated_at = now(), client_edited_at = now()
   where id = p_user;
end;
$$;

create or replace function public.set_member_active(p_user uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_hh uuid := public.current_household_id();
begin
  if not public.is_admin() then raise exception 'not_admin'; end if;
  if (select household_id from public.profiles where id = p_user) is distinct from v_hh then
    raise exception 'not_a_member';
  end if;
  if p_user = auth.uid() then raise exception 'cannot_deactivate_self'; end if;
  update public.profiles
     set is_active = p_active, updated_at = now(), client_edited_at = now()
   where id = p_user;
end;
$$;

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
     set household_id = null, role = 'member', joined_at = null,
         updated_at = now(), client_edited_at = now()
   where id = p_user;
end;
$$;
