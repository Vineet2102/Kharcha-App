-- ─────────────────────────────────────────────────────────────
-- budgets
--   scope = 'household'      → whole family, all categories
--   scope = 'user'           → one member, all categories
--   scope = 'category'       → one category, whole family
--   scope = 'user_category'  → one member, one category
-- ─────────────────────────────────────────────────────────────
create table public.budgets (
  id                  uuid primary key,
  household_id        uuid        not null references public.households(id) on delete cascade,
  scope               public.budget_scope not null,
  user_id             uuid        references public.profiles(id) on delete cascade,
  category_id         uuid        references public.categories(id) on delete cascade,
  amount_paise        bigint      not null check (amount_paise > 0),
  period_month        date        not null,   -- always the 1st of the month
  is_rollover         boolean     not null default false,
  alert_threshold_pct int         not null default 80 check (alert_threshold_pct between 1 and 100),
  created_by          uuid        not null references public.profiles(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  constraint budgets_scope_shape check (
    (scope = 'household'     and user_id is null     and category_id is null) or
    (scope = 'user'          and user_id is not null and category_id is null) or
    (scope = 'category'      and user_id is null     and category_id is not null) or
    (scope = 'user_category' and user_id is not null and category_id is not null)
  )
);
create unique index budgets_unique_scope
  on public.budgets(household_id, period_month, scope,
                    coalesce(user_id, '00000000-0000-0000-0000-000000000000'::uuid),
                    coalesce(category_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where deleted_at is null;
create index budgets_sync_idx on public.budgets(household_id, updated_at);

-- ─────────────────────────────────────────────────────────────
-- recurring_rules
-- ─────────────────────────────────────────────────────────────
create table public.recurring_rules (
  id                uuid primary key,
  household_id      uuid        not null references public.households(id) on delete cascade,
  user_id           uuid        not null references public.profiles(id) on delete cascade,
  kind              public.txn_kind not null default 'expense',
  title             text        not null,
  amount_paise      bigint      not null check (amount_paise > 0),
  category_id       uuid        references public.categories(id) on delete set null,
  payment_method_id uuid        references public.payment_methods(id) on delete set null,
  note              text        not null default '',
  frequency         public.recur_frequency not null,
  interval_n        int         not null default 1 check (interval_n between 1 and 60),
  day_of_month      int         check (day_of_month between 1 and 31),
  weekday           int         check (weekday between 0 and 6),   -- 0 = Sunday
  month_of_year     int         check (month_of_year between 1 and 12),
  start_date        date        not null,
  end_date          date,
  next_due_date     date        not null,
  auto_post         boolean     not null default false,  -- false = ask for confirmation
  is_active         boolean     not null default true,
  last_posted_on    date,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index recurring_due_idx  on public.recurring_rules(household_id, next_due_date) where is_active and deleted_at is null;
create index recurring_sync_idx on public.recurring_rules(household_id, updated_at);

alter table public.expenses
  add constraint expenses_recurring_fk
  foreign key (recurring_rule_id) references public.recurring_rules(id) on delete set null;
alter table public.incomes
  add constraint incomes_recurring_fk
  foreign key (recurring_rule_id) references public.recurring_rules(id) on delete set null;
