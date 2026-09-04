-- ─────────────────────────────────────────────────────────────
-- households
-- ─────────────────────────────────────────────────────────────
create table public.households (
  id            uuid primary key default gen_random_uuid(),
  name          text        not null,
  currency_code text        not null default 'INR',
  timezone      text        not null default 'Asia/Kolkata',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────
-- profiles  (1:1 with auth.users)
-- ─────────────────────────────────────────────────────────────
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  household_id  uuid        not null references public.households(id) on delete restrict,
  display_name  text        not null,
  role          public.member_role not null default 'member',
  colour_hex    text        not null default '#6750A4',
  is_active     boolean     not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index profiles_household_idx on public.profiles(household_id);

-- Auto-create a profile row whenever an auth user is created.
-- Assumes a single household; picks the first (and only) one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare hh uuid;
begin
  select id into hh from public.households order by created_at limit 1;
  insert into public.profiles (id, household_id, display_name)
  values (new.id, hh, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- categories
-- ─────────────────────────────────────────────────────────────
create table public.categories (
  id            uuid primary key,
  household_id  uuid        not null references public.households(id) on delete cascade,
  name          text        not null,
  kind          public.category_kind not null default 'expense',
  icon_key      text        not null default 'category',
  colour_hex    text        not null default '#607D8B',
  sort_order    int         not null default 100,
  is_archived   boolean     not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create unique index categories_unique_name
  on public.categories(household_id, kind, lower(name))
  where deleted_at is null;
create index categories_household_idx on public.categories(household_id, updated_at);

-- ─────────────────────────────────────────────────────────────
-- payment_methods
-- ─────────────────────────────────────────────────────────────
create table public.payment_methods (
  id            uuid primary key,
  household_id  uuid        not null references public.households(id) on delete cascade,
  name          text        not null,
  type          public.pay_method_type not null default 'other',
  is_archived   boolean     not null default false,
  sort_order    int         not null default 100,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create unique index payment_methods_unique_name
  on public.payment_methods(household_id, lower(name))
  where deleted_at is null;
create index payment_methods_household_idx on public.payment_methods(household_id, updated_at);
