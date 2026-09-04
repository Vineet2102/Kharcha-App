-- Monthly totals for the whole household
create or replace view public.v_month_household
with (security_invoker = true) as
select
  e.household_id,
  date_trunc('month', e.spent_on)::date as period_month,
  sum(e.amount_paise)::bigint            as expense_paise,
  count(*)                               as txn_count
from public.expenses e
where e.deleted_at is null
group by 1, 2;

-- Monthly totals per member
create or replace view public.v_month_user
with (security_invoker = true) as
select
  e.household_id,
  e.user_id,
  date_trunc('month', e.spent_on)::date as period_month,
  sum(e.amount_paise)::bigint            as expense_paise,
  count(*)                               as txn_count
from public.expenses e
where e.deleted_at is null
group by 1, 2, 3;

-- Monthly totals per category
create or replace view public.v_month_category
with (security_invoker = true) as
select
  e.household_id,
  e.category_id,
  date_trunc('month', e.spent_on)::date as period_month,
  sum(e.amount_paise)::bigint            as expense_paise,
  count(*)                               as txn_count
from public.expenses e
where e.deleted_at is null
group by 1, 2, 3;

-- Monthly income
create or replace view public.v_month_income
with (security_invoker = true) as
select
  i.household_id,
  i.user_id,
  date_trunc('month', i.received_on)::date as period_month,
  sum(i.amount_paise)::bigint              as income_paise
from public.incomes i
where i.deleted_at is null
group by 1, 2, 3;

-- One-call dashboard payload
create or replace function public.get_dashboard(p_month date)
returns jsonb
language sql stable security invoker
as $$
  with m as (select date_trunc('month', p_month)::date as pm),
       hh as (select public.current_household_id() as id)
  select jsonb_build_object(
    'period_month',   (select pm from m),
    'expense_paise',  coalesce((select expense_paise from public.v_month_household
                                 where household_id = (select id from hh)
                                   and period_month = (select pm from m)), 0),
    'income_paise',   coalesce((select sum(income_paise) from public.v_month_income
                                 where household_id = (select id from hh)
                                   and period_month = (select pm from m)), 0),
    'by_user',        coalesce((select jsonb_agg(jsonb_build_object(
                                  'user_id', user_id, 'expense_paise', expense_paise, 'txn_count', txn_count)
                                ) from public.v_month_user
                                 where household_id = (select id from hh)
                                   and period_month = (select pm from m)), '[]'::jsonb),
    'by_category',    coalesce((select jsonb_agg(jsonb_build_object(
                                  'category_id', category_id, 'expense_paise', expense_paise, 'txn_count', txn_count)
                                ) from public.v_month_category
                                 where household_id = (select id from hh)
                                   and period_month = (select pm from m)), '[]'::jsonb)
  );
$$;
