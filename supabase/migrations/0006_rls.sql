alter table public.households      enable row level security;
alter table public.profiles        enable row level security;
alter table public.categories      enable row level security;
alter table public.payment_methods enable row level security;
alter table public.expenses        enable row level security;
alter table public.incomes         enable row level security;
alter table public.attachments     enable row level security;
alter table public.budgets         enable row level security;
alter table public.recurring_rules enable row level security;
-- app_releases RLS is enabled in 0010_app_releases.sql, where the table is created.

-- ── households ────────────────────────────────────────────────
create policy hh_select on public.households for select to authenticated
  using (id = public.current_household_id());
create policy hh_update on public.households for update to authenticated
  using (id = public.current_household_id() and public.is_admin());

-- ── profiles ──────────────────────────────────────────────────
create policy pr_select on public.profiles for select to authenticated
  using (household_id = public.current_household_id());
create policy pr_update_self on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (household_id = public.current_household_id());

-- ── categories & payment_methods: read all, write admin-only ──
create policy cat_select on public.categories for select to authenticated
  using (household_id = public.current_household_id());
create policy cat_write on public.categories for all to authenticated
  using (household_id = public.current_household_id() and public.is_admin())
  with check (household_id = public.current_household_id() and public.is_admin());

create policy pm_select on public.payment_methods for select to authenticated
  using (household_id = public.current_household_id());
create policy pm_write on public.payment_methods for all to authenticated
  using (household_id = public.current_household_id() and public.is_admin())
  with check (household_id = public.current_household_id() and public.is_admin());

-- ── expenses: see all, write own (admin writes all) ───────────
create policy exp_select on public.expenses for select to authenticated
  using (household_id = public.current_household_id());
create policy exp_insert on public.expenses for insert to authenticated
  with check (household_id = public.current_household_id()
              and (user_id = auth.uid() or public.is_admin()));
create policy exp_update on public.expenses for update to authenticated
  using (household_id = public.current_household_id()
         and (user_id = auth.uid() or public.is_admin()))
  with check (household_id = public.current_household_id());
create policy exp_delete on public.expenses for delete to authenticated
  using (household_id = public.current_household_id()
         and (user_id = auth.uid() or public.is_admin()));

-- ── incomes: identical shape to expenses ──────────────────────
create policy inc_select on public.incomes for select to authenticated
  using (household_id = public.current_household_id());
create policy inc_insert on public.incomes for insert to authenticated
  with check (household_id = public.current_household_id()
              and (user_id = auth.uid() or public.is_admin()));
create policy inc_update on public.incomes for update to authenticated
  using (household_id = public.current_household_id()
         and (user_id = auth.uid() or public.is_admin()))
  with check (household_id = public.current_household_id());
create policy inc_delete on public.incomes for delete to authenticated
  using (household_id = public.current_household_id()
         and (user_id = auth.uid() or public.is_admin()));

-- ── attachments: follow the parent expense's owner ─────────────
create policy att_select on public.attachments for select to authenticated
  using (household_id = public.current_household_id());
create policy att_write on public.attachments for all to authenticated
  using (household_id = public.current_household_id()
         and (uploaded_by = auth.uid() or public.is_admin()))
  with check (household_id = public.current_household_id());

-- ── budgets: household-scoped budgets are admin-only;
--             a member may manage budgets that target themselves ──
create policy bud_select on public.budgets for select to authenticated
  using (household_id = public.current_household_id());
create policy bud_write on public.budgets for all to authenticated
  using (household_id = public.current_household_id()
         and (public.is_admin() or user_id = auth.uid()))
  with check (household_id = public.current_household_id()
              and (public.is_admin() or user_id = auth.uid()));

-- ── recurring rules: own or admin ─────────────────────────────
create policy rec_select on public.recurring_rules for select to authenticated
  using (household_id = public.current_household_id());
create policy rec_write on public.recurring_rules for all to authenticated
  using (household_id = public.current_household_id()
         and (user_id = auth.uid() or public.is_admin()))
  with check (household_id = public.current_household_id()
              and (user_id = auth.uid() or public.is_admin()));

-- app_releases RLS policy is created in 0010_app_releases.sql, where the table is created.
