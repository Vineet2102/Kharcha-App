-- Keep updated_at honest. LWW-safe: never lets updated_at go backwards.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := greatest(now(), coalesce(new.updated_at, now()));
  return new;
end;
$$;

-- Derive the IST calendar date. A GENERATED column cannot be used here because
-- `timestamptz AT TIME ZONE ...` is STABLE, not IMMUTABLE, and Postgres rejects it
-- in a generation expression. A BEFORE trigger is the correct equivalent.
create or replace function public.set_ist_date()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'expenses' then
    new.spent_on := (new.spent_at at time zone 'Asia/Kolkata')::date;
  else
    new.received_on := (new.received_at at time zone 'Asia/Kolkata')::date;
  end if;
  return new;
end;
$$;

create trigger trg_ist_date_expenses before insert or update on public.expenses
  for each row execute function public.set_ist_date();
create trigger trg_ist_date_incomes before insert or update on public.incomes
  for each row execute function public.set_ist_date();

do $$
declare t text;
begin
  foreach t in array array[
    'households','profiles','categories','payment_methods',
    'expenses','incomes','attachments','budgets','recurring_rules'
  ] loop
    execute format(
      'create trigger trg_touch_%1$s before insert or update on public.%1$s
       for each row execute function public.touch_updated_at();', t);
  end loop;
end $$;

-- ── Authorisation helpers (SECURITY DEFINER avoids RLS recursion) ──
create or replace function public.current_household_id()
returns uuid language sql stable security definer set search_path = public as $$
  select household_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false)
$$;

-- ── Recurring rule scheduling ──
create or replace function public.advance_due_date(
  p_from date, p_freq public.recur_frequency, p_interval int,
  p_dom int, p_weekday int
) returns date language plpgsql immutable as $$
declare nxt date;
begin
  case p_freq
    when 'daily'   then nxt := (p_from + (p_interval || ' days')::interval)::date;
    when 'weekly'  then nxt := (p_from + (p_interval || ' weeks')::interval)::date;
    when 'monthly' then
      nxt := (date_trunc('month', p_from) + (p_interval || ' months')::interval)::date;
      -- clamp day-of-month to the last valid day (e.g. 31 → 28/29/30)
      nxt := nxt + least(
               coalesce(p_dom, extract(day from p_from)::int),
               extract(day from (date_trunc('month', nxt) + interval '1 month' - interval '1 day'))::int
             ) - 1;
    when 'yearly'  then nxt := (p_from + (p_interval || ' years')::interval)::date;
  end case;
  return nxt;
end;
$$;
