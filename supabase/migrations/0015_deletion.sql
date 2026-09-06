-- Delete a household outright. Admin-only, and only once you are the
-- last member — otherwise you would be deleting other people's data.
-- Every child table cascades from households.id, so one delete is enough.
create or replace function public.delete_household()
returns void language plpgsql security definer set search_path = public as $$
declare v_hh uuid := public.current_household_id();
begin
  if not public.is_admin() then raise exception 'not_admin'; end if;
  if v_hh is null then raise exception 'not_in_household'; end if;
  if (select count(*) from public.profiles where household_id = v_hh) > 1 then
    raise exception 'household_not_empty';
  end if;

  perform set_config('kharcha.allow_membership_change', 'on', true);
  update public.profiles
     set household_id = null, role = 'member', joined_at = null
   where household_id = v_hh;

  delete from public.households where id = v_hh;
end;
$$;

-- Everything this user personally wrote, inside their current household.
-- Called by the account-deletion Edge Function before it removes the
-- auth user (expenses.user_id is ON DELETE RESTRICT, so the rows must
-- go first). Also usable on its own as "erase my contributions".
create or replace function public.delete_my_records()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_e int; v_i int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  delete from public.attachments a
   where a.expense_id in (select id from public.expenses where user_id = v_uid);
  with d as (delete from public.expenses where user_id = v_uid returning 1)
    select count(*) into v_e from d;
  with d as (delete from public.incomes  where user_id = v_uid returning 1)
    select count(*) into v_i from d;
  delete from public.budgets        where user_id = v_uid;
  delete from public.recurring_rules where user_id = v_uid;

  return jsonb_build_object('expenses_deleted', v_e, 'incomes_deleted', v_i);
end;
$$;

revoke all on function public.delete_household(), public.delete_my_records()
  from public, anon;
grant execute on function public.delete_household(), public.delete_my_records()
  to authenticated;
