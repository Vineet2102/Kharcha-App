-- ─────────────────────────────────────────────────────────────
-- households: ownership, lifecycle, liveness
-- ─────────────────────────────────────────────────────────────
alter table public.households
  add column if not exists created_by     uuid references public.profiles(id) on delete set null,
  add column if not exists is_active      boolean     not null default true,
  add column if not exists last_active_at timestamptz not null default now();

-- ─────────────────────────────────────────────────────────────
-- profiles: membership becomes optional and mutable
-- ─────────────────────────────────────────────────────────────
alter table public.profiles alter column household_id drop not null;

-- v1.0 used ON DELETE RESTRICT, which makes deleting a household impossible.
alter table public.profiles drop constraint if exists profiles_household_id_fkey;
alter table public.profiles
  add constraint profiles_household_id_fkey
  foreign key (household_id) references public.households(id) on delete set null;

alter table public.profiles
  add column if not exists joined_at    timestamptz,
  add column if not exists last_seen_at timestamptz;

create index if not exists profiles_active_household_idx
  on public.profiles(household_id) where household_id is not null;

-- A new account starts with NO household. v1.0's "pick the first household"
-- would have dropped every new signup straight into the Panicker family.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, household_id, display_name, role)
  values (
    new.id,
    null,
    coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
             split_part(new.email, '@', 1)),
    'member'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- household_invites
--   code is stored as 8 uppercase chars with NO dash; the UI
--   renders it as ABCD-EFGH and accepts any punctuation on input.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.household_invites (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  code         text not null check (code ~ '^[A-Z0-9]{8}$'),
  created_by   uuid not null references public.profiles(id) on delete cascade,
  expires_at   timestamptz not null default (now() + interval '30 days'),
  max_uses     int  not null default 20 check (max_uses between 1 and 100),
  use_count    int  not null default 0,
  is_active    boolean not null default true,
  revoked_at   timestamptz,
  created_at   timestamptz not null default now()
);
create unique index if not exists household_invites_code_key
  on public.household_invites(code);
create index if not exists household_invites_household_idx
  on public.household_invites(household_id, created_at desc);

-- ─────────────────────────────────────────────────────────────
-- feedback (F-17)
-- ─────────────────────────────────────────────────────────────
create table if not exists public.feedback (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  household_id uuid references public.households(id) on delete set null,
  rating       int  check (rating between 1 and 5),
  category     text not null default 'general'
               check (category in ('general','bug','idea','confusing','praise')),
  message      text not null check (length(message) between 1 and 2000),
  app_version  text,
  platform     text,
  created_at   timestamptz not null default now()
);
create index if not exists feedback_created_idx on public.feedback(created_at desc);
