alter table public.household_invites enable row level security;
alter table public.feedback          enable row level security;

-- ── the guard that makes D17 real ────────────────────────────
-- Without this, `update profiles set household_id = '<someone else>'`
-- passes pr_update_self's WITH CHECK and hands the caller a whole
-- household. Every legitimate change sets the config flag first.
create or replace function public.guard_profile_membership()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('kharcha.allow_membership_change', true), 'off') <> 'on' then
    if new.household_id is distinct from old.household_id then
      raise exception 'household_id_immutable'
        using hint = 'Use create_household / join_household / leave_household.';
    end if;
    if new.role is distinct from old.role then
      raise exception 'role_immutable'
        using hint = 'Use set_member_role().';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_profile_membership on public.profiles;
create trigger trg_guard_profile_membership
  before update on public.profiles
  for each row execute function public.guard_profile_membership();

-- ── households: read your own; admins rename; never insert directly ──
drop policy if exists hh_select on public.households;
create policy hh_select on public.households for select to authenticated
  using (id = public.current_household_id());

drop policy if exists hh_update on public.households;
create policy hh_update on public.households for update to authenticated
  using (id = public.current_household_id() and public.is_admin())
  with check (id = public.current_household_id() and public.is_admin());
-- deliberately NO insert or delete policy: create_household() and
-- delete_household() are SECURITY DEFINER and bypass RLS.

-- ── profiles ─────────────────────────────────────────────────
-- A profile is visible to you if it is yours, if it is a current member
-- of your household, or if it authored a transaction that still lives in
-- your household (so a departed member's name still renders on old rows).
-- SECURITY DEFINER, so the subqueries cannot recurse through RLS.
create or replace function public.profile_visible_to_me(p_profile uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_profile = auth.uid()
      or exists (select 1 from public.profiles pr
                  where pr.id = p_profile
                    and pr.household_id is not null
                    and pr.household_id = public.current_household_id())
      or exists (select 1 from public.expenses e
                  where e.user_id = p_profile
                    and e.household_id = public.current_household_id())
      or exists (select 1 from public.incomes i
                  where i.user_id = p_profile
                    and i.household_id = public.current_household_id());
$$;

drop policy if exists pr_select on public.profiles;
create policy pr_select on public.profiles for select to authenticated
  using (public.profile_visible_to_me(id));

-- Only your own row, and only its non-membership fields (the trigger
-- above blocks household_id and role). is_active for others goes
-- through set_member_active().
drop policy if exists pr_update_self on public.profiles;
create policy pr_update_self on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ── invites: members read their household's live code; writes are RPC-only ──
drop policy if exists inv_select on public.household_invites;
create policy inv_select on public.household_invites for select to authenticated
  using (household_id = public.current_household_id());
-- no insert/update/delete policy: create_invite() and revoke_invites()
-- are SECURITY DEFINER and bypass RLS.

-- ── feedback: write your own, read your own ──────────────────
drop policy if exists fb_insert on public.feedback;
create policy fb_insert on public.feedback for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists fb_select on public.feedback;
create policy fb_select on public.feedback for select to authenticated
  using (user_id = auth.uid());

-- ── grants: RPCs are callable by signed-in users only ────────
revoke all on function
  public.create_household(text), public.join_household(text),
  public.leave_household(), public.set_member_role(uuid, text),
  public.set_member_active(uuid, boolean), public.remove_member(uuid),
  public.create_invite(int, int), public.revoke_invites(),
  public.touch_activity()
from public, anon;

grant execute on function
  public.create_household(text), public.join_household(text),
  public.leave_household(), public.set_member_role(uuid, text),
  public.set_member_active(uuid, boolean), public.remove_member(uuid),
  public.create_invite(int, int), public.revoke_invites(),
  public.touch_activity()
to authenticated;

-- internals must never be callable from a client
revoke all on function
  public.seed_household_defaults(uuid),
  public.create_invite_internal(uuid, uuid, int, int),
  public.gen_invite_code()
from public, anon, authenticated;
