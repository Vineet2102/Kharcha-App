-- ─────────────────────────────────────────────────────────────
-- expenses
-- ─────────────────────────────────────────────────────────────
create table public.expenses (
  id                uuid primary key,
  household_id      uuid        not null references public.households(id) on delete cascade,
  user_id           uuid        not null references public.profiles(id) on delete restrict,
  amount_paise      bigint      not null check (amount_paise > 0),
  category_id       uuid        references public.categories(id) on delete set null,
  payment_method_id uuid        references public.payment_methods(id) on delete set null,
  spent_at          timestamptz not null,
  spent_on          date        not null,   -- IST calendar date of spent_at; set by trigger (see 0005)
  note              text        not null default '',
  merchant          text        not null default '',
  has_receipt       boolean     not null default false,
  recurring_rule_id uuid,                      -- FK added in 0004 (circular)
  occurrence_date   date,                      -- idempotency key for recurring posts
  created_by_device text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create index expenses_household_month_idx on public.expenses(household_id, spent_on desc) where deleted_at is null;
create index expenses_user_month_idx      on public.expenses(household_id, user_id, spent_on desc) where deleted_at is null;
create index expenses_category_idx        on public.expenses(household_id, category_id, spent_on desc) where deleted_at is null;
create index expenses_sync_idx            on public.expenses(household_id, updated_at);
create index expenses_note_trgm_idx       on public.expenses using gin (note gin_trgm_ops);

-- Prevents two devices posting the same recurring occurrence twice.
create unique index expenses_recurrence_unique
  on public.expenses(recurring_rule_id, occurrence_date)
  where recurring_rule_id is not null and deleted_at is null;

-- ─────────────────────────────────────────────────────────────
-- incomes
-- ─────────────────────────────────────────────────────────────
create table public.incomes (
  id                uuid primary key,
  household_id      uuid        not null references public.households(id) on delete cascade,
  user_id           uuid        not null references public.profiles(id) on delete restrict,
  amount_paise      bigint      not null check (amount_paise > 0),
  category_id       uuid        references public.categories(id) on delete set null,  -- kind='income'
  received_at       timestamptz not null,
  received_on       date        not null,   -- IST calendar date of received_at; set by trigger (see 0005)
  note              text        not null default '',
  source            text        not null default '',
  recurring_rule_id uuid,
  occurrence_date   date,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index incomes_household_month_idx on public.incomes(household_id, received_on desc) where deleted_at is null;
create index incomes_sync_idx            on public.incomes(household_id, updated_at);
create unique index incomes_recurrence_unique
  on public.incomes(recurring_rule_id, occurrence_date)
  where recurring_rule_id is not null and deleted_at is null;

-- ─────────────────────────────────────────────────────────────
-- attachments (receipt images)
-- ─────────────────────────────────────────────────────────────
create table public.attachments (
  id            uuid primary key,
  household_id  uuid        not null references public.households(id) on delete cascade,
  expense_id    uuid        not null references public.expenses(id) on delete cascade,
  storage_path  text        not null,     -- '<household_id>/<expense_id>/<attachment_id>.jpg'
  mime_type     text        not null default 'image/jpeg',
  size_bytes    int         not null default 0,
  width_px      int,
  height_px     int,
  uploaded_by   uuid        not null references public.profiles(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index attachments_expense_idx on public.attachments(expense_id) where deleted_at is null;
create index attachments_sync_idx    on public.attachments(household_id, updated_at);
