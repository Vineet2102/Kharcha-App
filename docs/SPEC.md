# Kharcha — Family Expense Tracker
## Complete Technical Specification & Build Plan (Spec-Driven Development Document)

| Field | Value |
|---|---|
| Document version | 1.0 |
| Date | 2026-09-03 |
| Owner | Vineet Panicker |
| Project codename | `kharcha` |
| Target platforms | Android 8.0+ (3 devices), iOS 15.0+ (2 devices) |
| Framework | Flutter (stable channel) |
| Backend | Supabase (hosted Postgres + Auth + Storage + Realtime) |
| Distribution | Private sideload only — no Play Store, no App Store |
| Build machine | MacBook Air M2 (Apple Silicon, India variant, USB-C only) |
| Locale / currency | India, INR (₹) only |
| Timezone | Asia/Kolkata (IST, UTC+5:30) |

---

## 0. How To Use This Document

> **This section is addressed to the AI coding agent (Claude Code) that will build this project.**

1. **Read the whole document before writing any code.** Sections 1–12 are the specification. Section 17 is the executable task backlog.
2. **Build strictly in phase order.** Phase N must be complete and verified before Phase N+1 begins. Each phase ends with a verification gate that must pass.
3. **Every task in Section 17 has the form:**
   - `ID` — stable identifier, referenced elsewhere in this doc
   - `Task` — what to do
   - `Files` — files created or modified
   - `Acceptance criteria` — objective, checkable conditions
   - `Verify` — the exact command or manual step that proves it works
4. **Do not invent features that are not in this document.** If something is genuinely ambiguous, choose the simplest option that satisfies the acceptance criteria, and record the choice in `docs/DECISIONS.md` with a short rationale.
5. **Do not skip the verification step of a task.** If a verification fails, fix it before moving on. Never mark a task done with failing tests or a failing build.
6. **Visual design is deliberately out of scope.** Use Flutter Material 3 defaults with a single seed colour. Do not spend effort on custom visual design, animations, or illustrations. Layout must be functional, readable, and accessible — nothing more.
7. **Progress tracking:** maintain `docs/PROGRESS.md` in the repo. After each task, append a line: `TASK-ID | status | date | notes`.
8. **Secrets:** never commit real Supabase keys, keystores, or `.env` files. Use the patterns in §5.6 and §16.
9. **Commit discipline:** one commit per task, message format `[TASK-ID] short description`. Never commit code that does not compile.

---

## 1. Project Overview

### 1.1 Problem statement
A five-member family wants a single shared record of household spending. Today expenses are scattered across individual UPI apps, bank SMS, and memory. There is no answer to simple questions like "how much did we spend on groceries last month?" or "who has spent the most this month?".

### 1.2 Solution
A private cross-platform mobile app, installed manually on five family phones, backed by one shared cloud database. Every member logs their own expenses in a few taps. The app aggregates everything into household-level and per-person views, tracks budgets, handles recurring bills, stores receipts, and exports reports.

### 1.3 Goals
| # | Goal | Success measure |
|---|---|---|
| G1 | Logging an expense takes under 10 seconds | Add-expense flow ≤ 4 taps + amount entry from app launch |
| G2 | Everyone can see total family spend for any month | Dashboard shows current-month household total on launch |
| G3 | Per-person spend is comparable at a glance | Dashboard shows a per-member breakdown for the selected month |
| G4 | Works on patchy mobile data | Expenses can be created fully offline and sync automatically later |
| G5 | Zero server maintenance | No machine at home needs to stay powered on |
| G6 | Installable without any app store | Documented, repeatable install procedure for Android and iOS |

### 1.4 Non-goals (explicitly out of scope for v1)
- Play Store / App Store publication
- Bank, SMS, or email auto-import of transactions
- Multi-currency, foreign exchange
- Splitwise-style split & settle-up between members (deliberately deselected)
- Custom visual design system, theming beyond Material 3 defaults, dark-mode fine-tuning beyond the built-in switch
- Web or desktop builds
- More than one household per database (single-tenant by design, but schema is multi-tenant-ready)

### 1.5 Users
| Role | Who | Capabilities |
|---|---|---|
| `admin` | Vineet (1 person) | Everything a member can do, plus: manage members, manage categories & payment methods, edit or delete *any* record, manage household budgets, export all data |
| `member` | 4 family members | Create/edit/delete **their own** expenses and income; view **all** household data; view all analytics; set personal budgets; export |

**Visibility rule (locked decision):** every member can *see* everything in the household. Every member can only *edit or delete* their own records. The admin can edit or delete anything.

---

## 2. Locked Decisions

These were decided before drafting and must not be re-litigated during the build.

| ID | Decision | Choice | Consequence |
|---|---|---|---|
| D1 | Backend | **Supabase** (hosted Postgres, region `ap-south-1` Mumbai) | Real SQL for reporting; RLS for authorisation; free tier is ample for 5 users |
| D2 | Auth | **Email + password, accounts pre-created by admin** | No public sign-up screen is built. A sign-up flow is explicitly *not* implemented |
| D3 | iOS distribution | **Free Apple ID sideload** (personal team, 7-day signing) | Re-install required every 7 days; max 3 sideloaded apps per device; **remote push notifications are impossible** (see D6) |
| D4 | Android distribution | **Self-signed release APK**, shared as a file | One keystore, kept forever, so updates install over previous versions |
| D5 | Offline support | **Offline-first with local mirror + outbox sync queue** | Local SQLite (Drift) is the source of truth for the UI; Supabase is the source of truth for the household |
| D6 | Notifications | **On-device local notifications only** (no FCM/APNs in v1) | Works on both platforms without a paid Apple Developer account. Reminders, budget alerts, and monthly summaries are scheduled/evaluated on-device |
| D7 | Currency | **INR only**, stored as integer paise | No floating-point money anywhere. Indian digit grouping (lakh/crore) in formatting |
| D8 | Categories & payment methods | **User-editable in-app**, seeded with sensible defaults | Stored in DB, not hardcoded |
| D9 | Income tracking | **Included** | Dashboard shows net savings, not just spend |
| D10 | Receipts | **Included**, Supabase Storage private bucket | Client-side compression before upload; upload deferred while offline |
| D11 | Tests & CI | **Included** — unit, widget, integration tests + GitHub Actions | Protects against regressions during rapid AI-assisted iteration |
| D12 | Conflict resolution | **Last-write-wins on `updated_at`** | Acceptable for a 5-person family app; documented limitation |
| D13 | State management | **Riverpod (code-generated)** | Chosen for testability and compile-time safety |
| D14 | Routing | **go_router** | Declarative, deep-link ready |
| D15 | Local DB | **Drift** (SQLite) | Type-safe SQL, reactive streams, good migration story |

### 2.1 Known conflict and its resolution
> **Push notifications vs free iOS sideloading.** Remote push (APNs) requires a paid Apple Developer Program membership ($99/yr) and a provisioning profile with the Push Notifications entitlement. A free personal team cannot create one. Therefore **v1 uses `flutter_local_notifications` exclusively** — daily logging reminders, budget threshold alerts, and monthly summaries are all computed and scheduled on-device. This delivers ~90% of the practical value with zero cost and zero platform friction. Section 18.4 documents the optional upgrade path to Firebase Cloud Messaging if a paid account is purchased later.

---

## 3. Constraints & Environment Facts

| Constraint | Detail | Implication for the build |
|---|---|---|
| Build machine | MacBook Air M2, Apple Silicon, 8 GB or 16 GB RAM | Use arm64 toolchains. CocoaPods must be installed for arm64. Rosetta not required for Flutter 3.x |
| Ports | USB-C only, no USB-A, no HDMI | Physical iPhone connection needs the right cable — see §16.3.1 |
| iPhones | 2 devices, iOS 15+ | If iPhone 15 or newer → USB-C-to-USB-C. If iPhone 14 or older → **USB-C-to-Lightning cable required**. Wireless debugging works after one wired pairing |
| Androids | 3 devices, Android 8.0 (API 26)+ | Sideload APK; user must enable "Install unknown apps" for the sharing app |
| Network | Indian mobile data, intermittent | Offline-first is mandatory (D5) |
| Apple account | Free Apple ID | 7-day app expiry; 3 sideloaded apps per device; 10 app IDs per 7 days |
| Budget | ₹0 recurring cost target | Supabase free tier: 500 MB DB, 1 GB storage, 50k MAU — vastly more than 5 users need |

---

## 4. Development Environment Setup (macOS, Apple Silicon)

> **Phase 0 of the build. Execute these in order. Every command is run in Terminal.**

### 4.1 Baseline tooling

```bash
# 1. Xcode Command Line Tools
xcode-select --install

# 2. Homebrew (Apple Silicon installs to /opt/homebrew)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# 3. Core utilities
brew install git cocoapods
brew install --cask android-studio
```

### 4.2 Flutter via FVM (version pinning)

Pinning the Flutter version prevents "it worked yesterday" breakage during long AI-assisted sessions.

```bash
brew tap leoafarias/fvm
brew install fvm

# From the project root, after §4.6
fvm install stable
fvm use stable
```

After `fvm use`, **all Flutter commands in this project are prefixed with `fvm`**: `fvm flutter run`, `fvm dart run`, etc. Add `.fvm/` to `.gitignore` except `.fvm/fvm_config.json`.

Record the exact pinned version in `docs/DECISIONS.md` on first setup.

### 4.3 Xcode

1. Install Xcode from the Mac App Store (large download — start it early).
2. Accept the licence and install additional components:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   sudo xcodebuild -license accept
   ```
3. Open Xcode → **Settings → Accounts → +** → add the free Apple ID. This creates the "Personal Team" used for signing in §16.3.
4. Install an iOS simulator runtime: Xcode → Settings → Components → iOS Simulator.

### 4.4 Android toolchain

1. Open Android Studio once; complete the setup wizard (installs SDK, platform-tools, emulator).
2. Android Studio → Settings → Languages & Frameworks → Android SDK → **SDK Tools** tab → tick **Android SDK Command-line Tools (latest)** → Apply.
3. Install JDK 17 (required by recent Android Gradle Plugin):
   ```bash
   brew install --cask temurin@17
   ```
4. Accept licences:
   ```bash
   fvm flutter doctor --android-licenses
   ```
5. Add to `~/.zshrc`:
   ```bash
   export ANDROID_HOME="$HOME/Library/Android/sdk"
   export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
   ```

### 4.5 Verify the toolchain

```bash
fvm flutter doctor -v
```

**Gate:** every line must be a green tick except "Chrome" (not needed) and any VS Code / IntelliJ line. Do not proceed to Phase 1 with a red X on Flutter, Android toolchain, or Xcode.

### 4.6 Create the project

```bash
cd ~/Developer   # or wherever you keep code
fvm flutter create \
  --org com.panicker \
  --project-name kharcha \
  --platforms=android,ios \
  --org-name "Panicker Family" \
  kharcha
cd kharcha
fvm use stable
git init && git add -A && git commit -m "[T-0.6] Flutter project scaffold"
```

**Bundle identifier / application ID:** `com.panicker.kharcha`
> ⚠️ For free-Apple-ID sideloading the bundle ID must be globally unique and is registered to your Apple ID for 7 days at a time. Keep it stable — changing it later means the app installs as a *different* app and loses its local cache (cloud data is unaffected).

### 4.7 Repository hygiene

Create `.gitignore` additions:

```gitignore
# Secrets
config/*.json
!config/example.json
android/key.properties
android/app/*.jks
*.keystore
.env
.env.*

# FVM
.fvm/flutter_sdk

# Generated
*.g.dart
*.freezed.dart
*.mocks.dart
```

> **Note on generated files:** they are gitignored here because `build_runner` regenerates them. If CI build time becomes a problem, commit them instead and remove these lines.

Create these documentation files in the repo on day one:
- `docs/SPEC.md` — this document, copied verbatim
- `docs/DECISIONS.md` — running log of implementation decisions
- `docs/PROGRESS.md` — task completion log
- `README.md` — how to build and install, written last (T-16.6)
---

## 5. Supabase Backend Setup

### 5.1 Create the project
1. Sign up at `supabase.com` with the admin's email.
2. **New project** → Name `kharcha` → Database password: generate a strong one and store it in the Mac's Keychain / a password manager. **You cannot recover it later.**
3. Region: **`ap-south-1` (Mumbai)** — lowest latency from India.
4. Plan: Free.

### 5.2 Collect credentials
From Project Settings → API:
- `Project URL` → e.g. `https://abcdefgh.supabase.co`
- `anon` / `publishable` key → safe to ship inside the app (RLS is what protects data)
- `service_role` key → **NEVER put this in the app.** Admin/CLI use only.

### 5.3 Local Supabase CLI (for migrations)

```bash
brew install supabase/tap/supabase
cd ~/Developer/kharcha
supabase init                 # creates supabase/ directory
supabase login                # opens browser
supabase link --project-ref <your-project-ref>
```

All schema changes are written as migration files under `supabase/migrations/` and applied with:

```bash
supabase db push
```

> **Rule:** never edit the schema by hand in the Supabase dashboard SQL editor once migrations exist. Always write a migration file. This keeps the schema reproducible.

### 5.4 Migration file order

| File | Contents |
|---|---|
| `0001_extensions.sql` | Extensions and enums |
| `0002_core_tables.sql` | households, profiles, categories, payment_methods |
| `0003_transactions.sql` | expenses, incomes, attachments |
| `0004_budgets_recurring.sql` | budgets, recurring_rules |
| `0005_functions_triggers.sql` | `updated_at` trigger, helper functions, recurring poster |
| `0006_rls.sql` | Row Level Security policies for every table |
| `0007_views.sql` | Reporting views and RPCs |
| `0008_storage.sql` | Receipts bucket + storage policies |
| `0009_seed.sql` | Default categories and payment methods |
| `0010_app_releases.sql` | In-app update check table |

### 5.5 Creating the five user accounts

There is **no sign-up screen in the app** (D2). Accounts are created by the admin, once, via the Supabase dashboard:

1. Authentication → Users → **Add user** → *Create new user*.
2. Enter email + a temporary password. **Tick "Auto Confirm User"** (otherwise the member must click an email link).
3. Repeat for all 5 members.
4. After creating each user, insert their profile row (see §6.3 — a trigger does this automatically, but the display name and role must be set):
   ```sql
   update public.profiles
      set display_name = 'Amma', role = 'member'
    where id = '<uuid-from-auth-users>';
   ```
5. Authentication → Providers → Email → **turn OFF "Enable Sign Ups"**. This hard-locks the household.
6. Give each member their email + password in person. They change it later from Settings (§11.14) if they wish.

### 5.6 App configuration & secrets

Do **not** use `flutter_dotenv` (it ships the file as a readable asset). Use compile-time defines.

Create `config/dev.json` (gitignored):
```json
{
  "SUPABASE_URL": "https://<ref>.supabase.co",
  "SUPABASE_ANON_KEY": "<anon-key>",
  "APP_ENV": "dev"
}
```
And a committed `config/example.json` with placeholder values.

Read them in Dart:
```dart
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static void assertValid() {
    assert(supabaseUrl.isNotEmpty, 'SUPABASE_URL missing — pass --dart-define-from-file');
    assert(supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY missing');
  }
}
```

Run and build with:
```bash
fvm flutter run --dart-define-from-file=config/dev.json
fvm flutter build apk --release --dart-define-from-file=config/prod.json
```

> The anon key being visible in the APK is expected and safe. **All security comes from Row Level Security policies (§7).** If RLS is wrong, the anon key is a data leak — so §7 is the most safety-critical section in this document.

---

## 6. Database Schema

### 6.1 Conventions
- All primary keys are `uuid`, **generated on the client** (`uuid` v4) so records can be created offline and keep their identity after sync.
- All money is `bigint` **paise** (₹1 = 100 paise). Never `float`, never `numeric` in app code.
- All timestamps are `timestamptz` stored in UTC. The app converts to `Asia/Kolkata` for display.
- Soft delete everywhere: `deleted_at timestamptz null`. Rows are never hard-deleted, so sync can propagate tombstones.
- Every syncable table has `created_at`, `updated_at`, `deleted_at`.
- Table and column names are `snake_case`.

### 6.2 `0001_extensions.sql`

```sql
create extension if not exists "pgcrypto";      -- gen_random_uuid()
create extension if not exists "pg_trgm";       -- fuzzy note search

create type public.member_role      as enum ('admin', 'member');
create type public.category_kind    as enum ('expense', 'income');
create type public.pay_method_type  as enum ('cash', 'upi', 'card', 'bank', 'wallet', 'other');
create type public.budget_scope     as enum ('household', 'user', 'category', 'user_category');
create type public.recur_frequency  as enum ('daily', 'weekly', 'monthly', 'yearly');
create type public.txn_kind         as enum ('expense', 'income');
```

### 6.3 `0002_core_tables.sql`

```sql
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
```

### 6.4 `0003_transactions.sql`

```sql
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
```

### 6.5 `0004_budgets_recurring.sql`

```sql
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
```

### 6.6 `0005_functions_triggers.sql`

```sql
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
```

### 6.7 `0007_views.sql` — reporting

All views are `security_invoker` so RLS applies to the caller.

```sql
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
```

> **Note:** the dashboard RPC is a convenience for the *online* path. Because the app is offline-first (D5), the canonical dashboard numbers are computed locally in Drift from the mirrored rows (§9.5). The RPC exists for cross-checking and for the monthly-summary notification.

### 6.8 `0010_app_releases.sql` — in-app update check

```sql
create table public.app_releases (
  id            uuid primary key default gen_random_uuid(),
  platform      text not null check (platform in ('android','ios')),
  version_name  text not null,      -- '1.2.0'
  build_number  int  not null,      -- 14
  min_supported int  not null default 1,
  download_url  text,               -- Google Drive / iCloud link for the APK
  release_notes text not null default '',
  released_at   timestamptz not null default now()
);
create index app_releases_latest_idx on public.app_releases(platform, build_number desc);
```

---

## 7. Row Level Security (Most Safety-Critical Section)

`0006_rls.sql`. **Enable RLS on every table. A table without RLS is world-readable with the anon key.**

```sql
alter table public.households      enable row level security;
alter table public.profiles        enable row level security;
alter table public.categories      enable row level security;
alter table public.payment_methods enable row level security;
alter table public.expenses        enable row level security;
alter table public.incomes         enable row level security;
alter table public.attachments     enable row level security;
alter table public.budgets         enable row level security;
alter table public.recurring_rules enable row level security;
alter table public.app_releases    enable row level security;

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

-- ── app_releases: everyone reads, nobody writes from the app ──
create policy rel_select on public.app_releases for select to authenticated using (true);
```

### 7.1 RLS verification checklist (must be executed — task T-1.8)
Run each of these in the Supabase SQL editor **impersonating a member** (dashboard → SQL editor → role selector → `authenticated` with a member's JWT, or via the app in debug):

| # | Test | Expected |
|---|---|---|
| RLS-1 | Member selects all expenses | Sees all household rows |
| RLS-2 | Member updates another member's expense | `0 rows updated` / error |
| RLS-3 | Member deletes another member's expense | `0 rows deleted` / error |
| RLS-4 | Member inserts an expense with `user_id` of someone else | Rejected by `with check` |
| RLS-5 | Member inserts a category | Rejected (admin-only) |
| RLS-6 | Admin updates any member's expense | Succeeds |
| RLS-7 | Unauthenticated (anon) select on `expenses` | 0 rows / permission denied |
| RLS-8 | Member selects a row with a forged `household_id` | 0 rows |

---

## 8. Storage — Receipts

`0008_storage.sql`

```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- Path convention: <household_id>/<expense_id>/<attachment_id>.jpg
create policy "receipts read own household"
on storage.objects for select to authenticated
using (bucket_id = 'receipts'
       and (storage.foldername(name))[1] = public.current_household_id()::text);

create policy "receipts insert own household"
on storage.objects for insert to authenticated
with check (bucket_id = 'receipts'
            and (storage.foldername(name))[1] = public.current_household_id()::text);

create policy "receipts update own household"
on storage.objects for update to authenticated
using (bucket_id = 'receipts'
       and (storage.foldername(name))[1] = public.current_household_id()::text);

create policy "receipts delete own or admin"
on storage.objects for delete to authenticated
using (bucket_id = 'receipts'
       and (storage.foldername(name))[1] = public.current_household_id()::text
       and (owner = auth.uid() or public.is_admin()));
```

**Client rules:**
- Compress before upload: longest edge ≤ 1600 px, JPEG quality 80. Target < 400 KB.
- Images are fetched with **signed URLs** (`createSignedUrl`, 1 hour TTL), never public URLs.
- A local file-system cache under `<app-docs>/receipts/<attachment_id>.jpg` avoids repeat downloads.
- While offline, the image is copied to the local cache immediately and an outbox `upload` job is queued.

### 8.1 `0009_seed.sql` — defaults

```sql
-- Run ONCE, after creating the household.
insert into public.households (id, name) values
  ('11111111-1111-1111-1111-111111111111', 'Panicker Family')
on conflict do nothing;

insert into public.categories (id, household_id, name, kind, icon_key, colour_hex, sort_order) values
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Groceries',      'expense','shopping_cart','#4CAF50',10),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Eating Out',     'expense','restaurant',   '#FF9800',20),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Transport & Fuel','expense','local_gas_station','#795548',30),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Utilities',      'expense','bolt',         '#03A9F4',40),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Rent / EMI',     'expense','home',         '#9C27B0',50),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Medical',        'expense','local_hospital','#E91E63',60),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Education',      'expense','school',       '#3F51B5',70),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Shopping',       'expense','shopping_bag', '#F44336',80),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Entertainment',  'expense','movie',        '#009688',90),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Household Help', 'expense','cleaning_services','#8BC34A',100),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Gifts & Festivals','expense','card_giftcard','#FFC107',110),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Subscriptions',  'expense','subscriptions','#673AB7',120),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Travel',         'expense','flight',       '#00BCD4',130),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Insurance',      'expense','shield',       '#607D8B',140),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Miscellaneous',  'expense','more_horiz',   '#9E9E9E',999),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Salary',         'income','payments',      '#4CAF50',10),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Business',       'income','business',      '#3F51B5',20),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Interest & Dividends','income','savings',  '#009688',30),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Rent Received',  'income','apartment',     '#795548',40),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Other Income',   'income','more_horiz',    '#9E9E9E',999);

insert into public.payment_methods (id, household_id, name, type, sort_order) values
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Cash',        'cash',  10),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','UPI',         'upi',   20),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Credit Card', 'card',  30),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Debit Card',  'card',  40),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Net Banking', 'bank',  50),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Wallet',      'wallet',60);
```
---

## 9. Application Architecture

### 9.1 Layering

```
┌──────────────────────────────────────────────────────────┐
│  Presentation   screens/ + widgets/  (Flutter, Material 3)│
│                 consumes Riverpod providers only          │
├──────────────────────────────────────────────────────────┤
│  Application    controllers/ (Riverpod Notifiers)         │
│                 use-cases, validation, formatting         │
├──────────────────────────────────────────────────────────┤
│  Domain         models/ (freezed), pure Dart, no I/O      │
├──────────────────────────────────────────────────────────┤
│  Data           repositories/  ← THE ONLY LAYER THE UI    │
│                                  TALKS TO FOR DATA        │
│      ┌────────────────┐        ┌──────────────────┐       │
│      │ LocalDataSource│        │ RemoteDataSource │       │
│      │  (Drift/SQLite)│        │ (supabase_flutter)│      │
│      └────────────────┘        └──────────────────┘       │
│                    ▲  SyncEngine  ▼                       │
├──────────────────────────────────────────────────────────┤
│  Core           config, errors, result types, logging,    │
│                 money, date, formatters, connectivity     │
└──────────────────────────────────────────────────────────┘
```

**Iron rule:** the UI **never** reads from Supabase directly. Every read is a Drift stream. Every write goes to Drift **plus** an outbox row. The `SyncEngine` is the only component that touches `RemoteDataSource`. This single rule is what makes the app work offline.

### 9.2 Folder structure

```
lib/
├── main.dart
├── app.dart                          # MaterialApp.router, theme, locale
├── core/
│   ├── config/app_config.dart
│   ├── constants/app_constants.dart
│   ├── db/
│   │   ├── app_database.dart         # Drift database + tables
│   │   ├── app_database.g.dart
│   │   ├── tables/                   # Drift table definitions
│   │   └── daos/                     # ExpenseDao, BudgetDao, ...
│   ├── errors/failure.dart
│   ├── errors/error_mapper.dart
│   ├── result/result.dart            # sealed Ok/Err
│   ├── logging/app_logger.dart
│   ├── money/money.dart              # paise <-> display, INR grouping
│   ├── time/app_time.dart            # IST helpers, month boundaries
│   ├── network/connectivity_service.dart
│   └── extensions/
├── data/
│   ├── local/                        # thin wrappers over DAOs
│   ├── remote/
│   │   ├── supabase_client_provider.dart
│   │   ├── expense_remote_ds.dart
│   │   ├── income_remote_ds.dart
│   │   └── ...
│   ├── sync/
│   │   ├── sync_engine.dart
│   │   ├── outbox_processor.dart
│   │   ├── pull_service.dart
│   │   ├── sync_state.dart
│   │   └── realtime_listener.dart
│   └── repositories/
│       ├── auth_repository.dart
│       ├── expense_repository.dart
│       ├── income_repository.dart
│       ├── category_repository.dart
│       ├── payment_method_repository.dart
│       ├── budget_repository.dart
│       ├── recurring_repository.dart
│       ├── attachment_repository.dart
│       └── report_repository.dart
├── domain/
│   └── models/                       # freezed models + enums
├── features/
│   ├── auth/          {screens, controllers, widgets}
│   ├── dashboard/
│   ├── expenses/
│   ├── income/
│   ├── categories/
│   ├── payment_methods/
│   ├── budgets/
│   ├── recurring/
│   ├── receipts/
│   ├── analytics/
│   ├── export/
│   ├── notifications/
│   └── settings/
└── routing/
    ├── app_router.dart
    └── routes.dart

test/
├── unit/
├── widget/
└── integration/
integration_test/
```

### 9.3 Package list

Add with `fvm flutter pub add <pkg>` (this picks the newest compatible version), then **commit `pubspec.lock`** so builds are reproducible.

| Purpose | Package |
|---|---|
| Backend client | `supabase_flutter` |
| State management | `flutter_riverpod`, `riverpod_annotation` + dev `riverpod_generator`, `custom_lint`, `riverpod_lint` |
| Routing | `go_router` |
| Local DB | `drift`, `sqlite3_flutter_libs`, `path_provider`, `path` + dev `drift_dev` |
| Models | `freezed_annotation`, `json_annotation` + dev `freezed`, `json_serializable`, `build_runner` |
| IDs | `uuid` |
| Charts | `fl_chart` |
| Images | `image_picker`, `flutter_image_compress`, `cached_network_image` |
| Notifications | `flutter_local_notifications`, `timezone`, `permission_handler` |
| Export | `csv`, `pdf`, `printing`, `share_plus` |
| Connectivity | `connectivity_plus` |
| Secure storage | `flutter_secure_storage` |
| Prefs | `shared_preferences` |
| Formatting | `intl` |
| Device info | `device_info_plus`, `package_info_plus` |
| Launching URLs | `url_launcher` |
| Testing | dev: `mocktail`, `drift_dev`, `integration_test`, `flutter_lints` |

### 9.4 Money handling (non-negotiable)

```dart
/// All monetary values in this app are integer paise.
extension type const Money(int paise) {
  static Money fromRupees(num rupees) => Money((rupees * 100).round());
  double get rupees => paise / 100.0;

  /// '₹1,23,456.78'  (Indian digit grouping)
  String format({bool withSymbol = true, bool compact = false}) => ...;
  Money operator +(Money o) => Money(paise + o.paise);
  Money operator -(Money o) => Money(paise - o.paise);
}
```
- Parsing user input: accept `1234`, `1234.5`, `1,234.50`, `1234.567` (round to 2 dp). Reject negative and zero.
- Use `NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)` from `intl` for the base, with a compact variant producing `₹1.2L` / `₹3.4Cr` for chart labels.
- **Unit tests are mandatory** for parse and format (T-15.2), including 1 lakh, 1 crore, and 99.995 rounding.

### 9.5 Local database (Drift)

Every remote table has a mirror table with three extra columns:

| Column | Purpose |
|---|---|
| `sync_status` | `synced` \| `pending` \| `failed` |
| `local_updated_at` | device clock at the time of the local edit |
| `is_dirty` | boolean shortcut for "has unpushed changes" |

Plus two sync-only tables:

```dart
// Queue of local mutations waiting to be pushed.
class OutboxEntries extends Table {
  TextColumn get id => text()();                       // uuid
  TextColumn get entity => text()();                   // 'expense' | 'income' | ...
  TextColumn get entityId => text()();
  TextColumn get op => text()();                       // 'upsert' | 'delete' | 'upload'
  TextColumn get payload => text()();                  // JSON
  DateTimeColumn get createdAt => dateTime()();
  IntColumn  get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

// Per-table incremental pull cursors.
class SyncMeta extends Table {
  TextColumn get entity => text()();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {entity};
}
```

**Drift migration policy:** `schemaVersion` starts at 1 and increments with every table change. Write a `MigrationStrategy` step for each bump. Never ship a change that requires wiping local data unless the version is still in development.

### 9.6 Sync engine

**Trigger points**
1. App start, after auth resolves
2. App resumes from background (`AppLifecycleState.resumed`), throttled to once per 30 s
3. Connectivity transitions from offline → online
4. Manual pull-to-refresh on Dashboard and Expense List
5. Immediately after any local write, if online
6. Periodic timer every 5 minutes while the app is foregrounded

**Algorithm**

```
sync():
  if syncing: return                      # single-flight lock
  if offline: set state = offline; return
  set state = syncing
  try:
    pushOutbox()                          # local → remote, FIFO
    pullChanges()                         # remote → local, per entity
    postDueRecurring()                    # §11.8
    evaluateBudgetAlerts()                # §11.7
    set state = idle(lastSyncedAt: now)
  catch e:
    set state = error(e); scheduleRetry()
```

**pushOutbox()**
- Read outbox ordered by `created_at`, where `next_attempt_at is null or <= now`.
- Dependency ordering: `category` and `payment_method` before `expense`/`income`; `expense` before `attachment`.
- For `upsert`: `supabase.from(table).upsert(payload, onConflict: 'id')`.
- For `delete`: soft delete → `update({'deleted_at': now, 'updated_at': now})`.
- For `upload`: upload the cached image file to Storage, then upsert the `attachments` row.
- On success: delete the outbox row, mark the local row `synced`, `is_dirty = false`.
- On failure:
  - **Permanent** (HTTP 4xx other than 408/429 — e.g. RLS denial, constraint violation): mark the entry `failed`, keep it, surface it in Settings → Sync issues. Do not retry automatically.
  - **Transient** (network, 5xx, 429, timeout): `attempts++`, `next_attempt_at = now + backoff`, where backoff = `min(2^attempts seconds, 15 minutes)` with ±20% jitter. Give up surfacing errors to the user until `attempts >= 5`.

**pullChanges()**
For each entity, in dependency order:
```sql
select * from <table>
 where household_id = :hh
   and updated_at > :cursor
 order by updated_at asc
 limit 500;
```
- `:cursor` = `sync_meta.last_pulled_at - 5 seconds` (overlap absorbs clock skew; upserts are idempotent).
- Page until fewer than 500 rows return; advance the cursor to the max `updated_at` seen.
- Rows with `deleted_at != null` are tombstones → delete the local row (and its cached receipt file).
- **Conflict rule (D12):** if the local row `is_dirty` and `local_updated_at > remote.updated_at`, keep the local row (it is still in the outbox and will win on push). Otherwise the remote row overwrites the local one.

**Realtime**
Subscribe to Postgres changes on `expenses`, `incomes`, `budgets` filtered by `household_id`. On any event, debounce 2 s and run `pullChanges()` for that entity only. Realtime is an *optimisation*, never a correctness requirement — the app must be fully correct with realtime disabled.

**Sync state exposed to the UI**
```dart
sealed class SyncState {}
class SyncIdle    extends SyncState { final DateTime? lastSyncedAt; }
class SyncRunning extends SyncState { final String? step; }
class SyncOffline extends SyncState { final int pendingCount; }
class SyncError   extends SyncState { final String message; final int pendingCount; }
```
Render as a slim banner under the app bar: `Offline — 3 changes waiting`, `Syncing…`, or nothing when idle and clean.

### 9.7 Error handling

```dart
sealed class Failure {
  const Failure(this.message);
  final String message;
}
class NetworkFailure   extends Failure {}
class AuthFailure      extends Failure {}
class PermissionFailure extends Failure {}   // RLS denial
class ValidationFailure extends Failure {}
class StorageFailure   extends Failure {}
class UnknownFailure   extends Failure {}
```
- Repositories return `Result<T, Failure>`; they never throw across the layer boundary.
- `ErrorMapper` converts `PostgrestException`, `AuthException`, `StorageException`, `SocketException` into the right `Failure` with a **human-readable Indian-English message** (e.g. "You can only edit expenses you added yourself.").
- Never show a raw exception string to the user. Log the full detail with `AppLogger`.

### 9.8 Logging
`AppLogger` wraps `dart:developer` `log()`. Levels: `debug`, `info`, `warn`, `error`. In release builds, `debug` is compiled out. Sync operations log every push/pull with counts. A ring buffer of the last 500 log lines is kept in memory and can be exported from Settings → Diagnostics (T-14.5) — this is the debugging lifeline for phones you don't have in your hand.

---

## 10. Screens & Navigation

Visual design is out of scope. Use Material 3, `useMaterial3: true`, `ColorScheme.fromSeed(seedColor: Colors.indigo)`, light + dark following the system setting.

### 10.1 Route map (go_router)

| Route | Screen | Notes |
|---|---|---|
| `/splash` | Splash / bootstrap | Init Supabase, Drift, timezone; decide auth redirect |
| `/login` | Login | Email + password only. No sign-up link |
| `/` | Shell with bottom nav | 4 tabs |
| `/` → tab 0 | Dashboard | Default landing |
| `/expenses` → tab 1 | Expense list | Filters, search, infinite scroll |
| `/analytics` → tab 2 | Analytics | Charts |
| `/settings` → tab 3 | Settings | Profile, categories, budgets, recurring, export, diagnostics |
| `/expense/new` | Add expense | Full-screen modal, also reachable from FAB |
| `/expense/:id` | Expense detail / edit | |
| `/income/new`, `/income/:id` | Income add / edit | |
| `/budgets`, `/budgets/new`, `/budgets/:id` | Budgets | |
| `/recurring`, `/recurring/new`, `/recurring/:id` | Recurring rules | |
| `/categories` | Category management | Admin-only actions |
| `/payment-methods` | Payment method management | Admin-only actions |
| `/members` | Member list | Admin sees roles |
| `/export` | Export screen | |
| `/receipt/:attachmentId` | Full-screen receipt viewer | Pinch-zoom |
| `/diagnostics` | Logs, sync queue, failed items | |

**Auth redirect:** a `redirect` callback on the router sends unauthenticated users to `/login` and authenticated users away from `/login`. The splash route is exempt.

### 10.2 Bottom navigation
`Dashboard | Expenses | Analytics | Settings`, with a centre FAB on Dashboard and Expenses that opens Add Expense. Long-press the FAB → Add Income.

---

## 11. Feature Specifications

Each feature has an ID used by the task backlog in §17.

### 11.1 F-01 Authentication

**Screens:** Splash, Login.

**Login screen**
- Fields: Email (keyboard `emailAddress`, autofill), Password (obscured, visibility toggle).
- "Remember me" is implicit — Supabase persists the session; `flutter_secure_storage` holds nothing extra.
- Actions: **Sign in**; **Forgot password?** → sends a Supabase reset email and shows "Check your email".
- **There is no Sign Up button.** (D2)
- Errors: invalid credentials → "Email or password is incorrect."; no network → "You're offline. Sign in needs an internet connection the first time."

**Session behaviour**
- `supabase.auth.onAuthStateChange` drives an `authStateProvider`.
- Sessions refresh automatically. If a refresh fails while offline, **the app stays usable in read-only-from-cache mode** and shows the offline banner; it must not force a logout.
- Force logout only on explicit sign-out or a hard `AuthException` while online.
- On sign-out: **wipe the local Drift database and the receipt cache** (privacy on a shared phone).

**Bootstrap sequence (splash)**
1. `WidgetsFlutterBinding.ensureInitialized()`
2. `AppConfig.assertValid()`
3. `tz.initializeTimeZones()`; set local location to `Asia/Kolkata`
4. `Supabase.initialize(...)`
5. Open Drift DB, run migrations
6. Init notifications plugin & request permission (Android 13+ `POST_NOTIFICATIONS`, iOS alert/badge/sound)
7. Resolve session → route to `/login` or `/`
8. Kick off first sync in the background (never block the UI on it)

**Acceptance:** a member can sign in, force-quit, reopen, and land straight on the dashboard without re-entering credentials, including in aeroplane mode.

---

### 11.2 F-02 Add / Edit Expense (the most-used screen — optimise ruthlessly)

**Fields**
| Field | Widget | Rules |
|---|---|---|
| Amount | Large numeric field, autofocused, custom numeric keypad or `TextInputType.numberWithOptions(decimal: true)` | Required, > 0, ≤ ₹10,00,00,000. Shows formatted preview under the field |
| Category | Horizontal chip row of the 8 most-used + "More" sheet | Required |
| Payment method | Chip row | Required; defaults to the last one used |
| Date & time | Defaults to **now**; chips for Today / Yesterday + a date picker | Cannot be more than 1 day in the future |
| Note | Single-line text, with autocomplete from the user's last 20 distinct notes | Optional, ≤ 200 chars |
| Merchant | Optional text with autocomplete | Optional, ≤ 100 chars |
| Paid by | Member selector | **Admin only.** Members always see themselves, non-editable |
| Receipt | "Add photo" → camera / gallery | Optional, see F-09 |

**Behaviour**
- **Save is instant and local.** Write to Drift + outbox, pop the screen, show a snackbar `Saved ✓` with an **Undo** action (5 s window; undo performs a local soft delete and removes the outbox entry if it hasn't been pushed).
- The screen must be fully usable offline. Never disable Save because of connectivity.
- Duplicate guard: if an expense with the same amount, category, and a `spent_at` within 2 minutes already exists for this user, show a non-blocking "Looks like a possible duplicate — save anyway?" confirmation.
- Edit mode: same form, pre-filled; the **Paid by** field is locked for non-admins; a Delete action in the app bar (confirm dialog → soft delete).
- Target: ≤ 10 seconds from launcher icon to saved expense (G1).

**Validation messages** are inline under the field, never dialogs.

---

### 11.3 F-03 Expense List

- Reverse-chronological, **grouped by date** with a sticky date header showing that day's total.
- Row: category icon + colour, note or category name, member's name chip, payment-method icon, amount right-aligned, a small cloud-off badge if `is_dirty`.
- **Infinite scroll**, page size 50, driven by a Drift `Stream` with `limit/offset`.
- **Filters** (bottom sheet, multi-select, combinable):
  - Month / custom date range (default: current month)
  - Member(s)
  - Category(ies)
  - Payment method(s)
  - Amount range
  - Only mine / only with receipts
- **Search:** free text across `note` and `merchant`, debounced 300 ms, local `LIKE '%q%'` on Drift.
- Header shows the total of the **currently filtered** set — this is the feature people actually use.
- Swipe left on a row → Delete (only if the row is editable by this user); swipe right → Duplicate (opens Add form pre-filled with today's date).
- Empty state: "No expenses match these filters." + a Clear filters button.

---

### 11.4 F-04 Dashboard

Month selector in the app bar (`◀ September 2026 ▶`, tappable to open a month/year picker; cannot go past the current month).

Cards, top to bottom:
1. **Household summary** — total spent this month, total income, net saved, and a % change vs the previous month (green/red arrow).
2. **Budget progress** — if a household budget exists for the month: a progress bar, amount spent / budget, amount left, and days remaining in the month with an implied daily allowance.
3. **Per-member breakdown** — horizontal bars, each member's name, amount, and % of household total, sorted descending. Tapping a member filters the Expense List to them.
4. **Top categories** — top 5 by spend with amounts and percentages; "See all" → Analytics.
5. **Recent activity** — last 5 expenses across the household, with the member's name. Tapping opens the detail.
6. **Pending recurring** — if any rule is due and `auto_post = false`, a card listing them with **Post** / **Skip** buttons (§11.8).
7. **Sync/offline banner** — pinned under the app bar when not idle.

Pull-to-refresh triggers a full sync.

---

### 11.5 F-05 Categories & Payment Methods

- List with drag-to-reorder (`sort_order`), archive toggle, and edit.
- Create/edit: name, kind (expense/income, category only), icon (pick from a fixed set of ~40 Material icon keys), colour (fixed 16-swatch palette).
- **Admin-only writes** (enforced by RLS *and* by hiding the controls for members).
- Archiving hides a category from pickers but keeps it on historical expenses.
- Deleting is a **soft delete** and is blocked with a clear message if the category is used by any non-deleted expense — offer "Archive instead".

---

### 11.6 F-06 Income

- Same shape as expenses: amount, income category, date, source, note, member.
- Separate list at `/income`, reachable from Settings and from the Dashboard's income figure.
- Feeds `net saved = income − expense` on the Dashboard and Analytics.
- Income is **not** included in expense totals anywhere. Every summary query filters by table, never by sign.

---

### 11.7 F-07 Budgets & Alerts

**Creating a budget:** choose scope (Household / Member / Category / Member+Category), amount, month, alert threshold % (default 80), and optional "copy to every following month" (which creates rows for the next 12 months).

**Rules**
- One budget per (scope, member, category, month) — enforced by the unique index in §6.5.
- A member may create/edit budgets that target themselves; only the admin may create Household or Category-wide budgets. (RLS enforces this.)
- Rollover (`is_rollover`): if on, unspent amount from the previous month is added to this month's effective budget. Compute this locally; do not store the derived number.

**Budget status computation (local, in Drift):**
```
spent   = Σ expenses in the month matching the scope
budget  = amount + (rollover ? max(0, prevMonthBudget - prevMonthSpent) : 0)
pct     = spent / budget
status  = pct < threshold      → ok
          threshold ≤ pct < 1  → warning
          pct ≥ 1              → exceeded
```

**Alerts (local notifications, D6)**
- Evaluated after every expense save and on every app resume.
- Fire at most **once per budget per status transition per month** — persist the last notified status in `shared_preferences` keyed `budget_alert_<budgetId>_<yyyyMM>` so members are not spammed.
- Copy: `"Groceries budget 82% used — ₹4,500 left for 11 days"` / `"Household budget exceeded by ₹2,300"`.

**Budgets screen:** list of the month's budgets with progress bars, grouped by scope; a summary at the top of how many are ok / warning / exceeded.

---

### 11.8 F-08 Recurring Expenses & Income

**Rule editor:** title, kind (expense/income), amount, category, payment method, note, frequency (daily / weekly / monthly / yearly) + interval (`every 2 months`), day-of-month or weekday, start date, optional end date, and **Auto-post** toggle.

**Posting engine (client-side, runs inside `sync()`):**
```
for each active rule where next_due_date <= today (in IST):
    occurrence = next_due_date
    if rule.auto_post:
        create expense/income with recurring_rule_id = rule.id,
                                   occurrence_date   = occurrence
        (unique index guarantees only one device wins; a duplicate-key
         error from another device is caught and ignored as success)
    else:
        add to the "pending confirmations" list shown on the Dashboard
    advance next_due_date via advance_due_date(); repeat until it is in the future
    (cap at 24 catch-up occurrences per rule per run, to avoid a runaway
     loop if a rule was dormant for years)
```
- Month-end clamping: a rule set to the 31st posts on the 28th/29th/30th in shorter months (handled by `advance_due_date`).
- Deleting a rule never deletes already-posted transactions; it only stops future ones.
- The rule editor shows a live preview: "Next 3 occurrences: 5 Oct, 5 Nov, 5 Dec".
- Pending confirmations expire after 30 days and are silently skipped.

---

### 11.9 F-09 Receipt Photos

**Capture:** `image_picker` (camera or gallery) → `flutter_image_compress` (longest edge 1600 px, quality 80) → save to `<app-docs>/receipts/<attachmentId>.jpg` → insert an `attachments` row locally → enqueue an `upload` outbox job.

**Display:** thumbnail on the expense detail; tap → `/receipt/:id` full-screen with pinch-zoom and a share button. Resolution order: **local cache file → signed URL download → cache it**.

**Constraints:** max 3 receipts per expense; max 5 MB per file (bucket-enforced); permitted MIME types jpeg/png/webp.

**Deleting an expense** soft-deletes its attachments and enqueues storage deletions. Orphaned storage objects are cleaned by a manual admin action in Settings → Diagnostics (v1 does not run a scheduled job).

**Offline:** everything above works offline except the upload, which is queued. The thumbnail shows an "upload pending" badge.

---

### 11.10 F-10 Analytics

Month/range selector shared with the Dashboard. All charts use `fl_chart` and read from local Drift aggregates.

| Chart | Detail |
|---|---|
| Monthly trend | Line chart, last 12 months, expense line + income line, tap a point for the exact value |
| Category donut | Current period, top 8 categories + "Other", legend with amounts and % |
| Member comparison | Grouped bar chart, last 6 months × members |
| Payment method split | Horizontal bar, current period |
| Day-of-week pattern | Bar chart, average spend by weekday |
| Top merchants | Simple ranked list, top 10 by total |
| Month-over-month table | Category × last 3 months with Δ% and colour coding |

**Rules:** every chart must handle the empty state ("No data for this period") and must render legibly in both light and dark mode. Currency labels use the compact format (`₹1.2L`). No chart animation longer than 300 ms.

---

### 11.11 F-11 Export

**Screen:** choose date range (month presets + custom), members, categories, and format.

**CSV** — one row per expense, UTF-8 with BOM (so Excel on Windows opens it correctly):
```
date,time,member,amount_inr,category,payment_method,merchant,note,has_receipt,id
2026-09-03,19:42,Vineet,450.00,Groceries,UPI,Reliance Fresh,weekly veg,false,7f3c...
```
A second CSV for income when income is included.

**PDF** — a simple report built with the `pdf` package:
- Title, household name, period, generation timestamp
- Summary block: total expense, total income, net
- Table: spend by category with %
- Table: spend by member with %
- Optional appendix: the full transaction list
- No images, no receipts embedded (keeps the file small)

**Delivery:** `share_plus` → WhatsApp / email / Files. Filenames: `kharcha_2026-09_expenses.csv`, `kharcha_2026-09_report.pdf`.

**Full backup export (admin only):** a single JSON file containing every table's rows for the household — the disaster-recovery escape hatch. Store it in Google Drive periodically.

---

### 11.12 F-12 Notifications (local only — D6)

| Notification | Schedule | Logic |
|---|---|---|
| Daily logging reminder | Every day at a user-set time (default 21:00 IST) | Skipped if the user already logged ≥ 1 expense today |
| Budget warning | Event-driven, on threshold crossing | §11.7, deduplicated per month |
| Budget exceeded | Event-driven | §11.7 |
| Monthly summary | 1st of each month, 10:00 IST | "August: family spent ₹84,320, saved ₹21,000" |
| Recurring due | On the due date, 09:00 IST, if `auto_post = false` | "3 recurring items are waiting for confirmation" |
| Sync stuck | If the outbox has entries older than 24 h | "Some expenses haven't synced. Open the app on Wi-Fi." |

**Implementation notes**
- `flutter_local_notifications` with `zonedSchedule` and `tz` set to `Asia/Kolkata`.
- Android 13+: request `POST_NOTIFICATIONS` at first launch. Android 12+: exact alarms need `SCHEDULE_EXACT_ALARM` — **use inexact scheduling** (`androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle`) to avoid the special-access permission prompt. A reminder arriving at 21:07 instead of 21:00 is fine.
- iOS: request alert/badge/sound permission at first launch.
- Recurring notifications must be **re-scheduled on every app start**, because Android clears alarms on reboot and the app cannot run in the background.
- Every notification type has an on/off switch in Settings, persisted in `shared_preferences`.
- Tapping a notification deep-links to the relevant screen via `go_router`.

---

### 11.13 F-13 Settings

Sections:
1. **Profile** — display name, colour, change password (Supabase `updateUser`), sign out.
2. **Household** — name (admin), members list with roles, currency (read-only ₹).
3. **Manage** — Categories, Payment methods, Budgets, Recurring rules.
4. **Notifications** — per-type toggles, daily reminder time picker.
5. **Data** — Export, Full backup (admin), "Sync now", "Clear local cache and re-download".
6. **About** — app version, build number, Supabase project region, **Check for updates** (§11.14).
7. **Diagnostics** — sync queue contents, failed items with retry/discard, log viewer, "Share logs".

---

### 11.14 F-14 In-app update check (important for sideloaded apps)

Because there is no store, the app must tell people when a new build exists.

- On launch (max once per 24 h), read the newest `app_releases` row for the current platform.
- If `build_number > current build`, show a dismissible banner on the Dashboard: "Version 1.3 is available" + **Get it** → opens `download_url` (a Google Drive / iCloud link to the APK) via `url_launcher`.
- If `min_supported > current build`, show a **blocking** dialog: "This version is too old to sync safely. Please update." — this is the emergency brake if a schema change breaks old clients.
- iOS builds show the same banner but the link points to instructions (a sideloaded iOS app cannot be updated from a URL).

---

## 12. Non-Functional Requirements

| ID | Requirement | Target / verification |
|---|---|---|
| NFR-1 | Cold start to interactive dashboard | ≤ 2.5 s on a mid-range Android (from local cache, no network wait) |
| NFR-2 | Add-expense save latency | ≤ 100 ms perceived (local write only) |
| NFR-3 | Offline capability | 100% of read and write features except: first sign-in, receipt download, export of unsynced others' data |
| NFR-4 | Data safety | No hard deletes; every mutation is soft and reversible from the DB for 90 days |
| NFR-5 | Security | RLS on every table; no `service_role` key in the app; receipts via signed URLs only |
| NFR-6 | Local DB size | < 50 MB for 5 years of 5-member data (est. ~30k rows) |
| NFR-7 | Accessibility | All tap targets ≥ 48 dp; text scales with system font size up to 1.3×; every icon-only button has a semantic label |
| NFR-8 | Android min SDK | 26 (Android 8.0) |
| NFR-9 | iOS min version | 15.0 |
| NFR-10 | Crash-free rate | No unhandled exception in the golden-path integration test |
| NFR-11 | Battery | No background isolates, no foreground services, no periodic wake-ups |
---

## 13. Testing Strategy

| Layer | Tool | What is tested | Coverage target |
|---|---|---|---|
| Unit — pure logic | `flutter_test` | Money parse/format, date & month helpers, `advance_due_date` Dart mirror, budget status computation, CSV row builder, duplicate detection | ≥ 90% of `core/` and `domain/` |
| Unit — data | `flutter_test` + in-memory Drift (`NativeDatabase.memory()`) | DAO queries, aggregate queries, migrations from v(n-1) to v(n) | All DAOs |
| Unit — sync | `flutter_test` + `mocktail` | Outbox ordering, backoff, permanent vs transient classification, conflict resolution both directions, tombstone handling, cursor advancement | 100% of `sync/` branches |
| Widget | `flutter_test` | Add-expense form validation, expense list grouping and filters, dashboard renders from a seeded DB, empty states, offline banner states | Key screens |
| Integration | `integration_test` | Golden path: sign in → add expense → appears in list → appears in dashboard total → toggle offline → add another → back online → both sync | 1 end-to-end suite |

**Mandatory test cases that have historically broken this kind of app — write these explicitly:**
1. Amount `0.1 + 0.2` never produces `0.30000000000000004` (integer paise proves it).
2. An expense created at 23:55 IST on the 30th belongs to that month, not the next (timezone boundary).
3. A recurring monthly rule on the 31st posts correctly in February.
4. Two devices posting the same recurring occurrence result in exactly one expense.
5. Editing offline, then receiving a newer remote edit, resolves per D12 without data loss on the losing side (the losing version is logged).
6. Deleting a category that is in use is blocked.
7. A member's attempt to edit another member's expense is rejected and shows a friendly message.
8. Signing out wipes the local database.

**Commands**
```bash
fvm flutter test                                   # unit + widget
fvm flutter test integration_test --device-id=<id> # integration, on a real device or emulator
fvm flutter analyze                                # must be zero issues
fvm dart format --set-exit-if-changed .            # must be clean
```

---

## 14. CI/CD — GitHub Actions

Repository: private GitHub repo. Two workflows.

### 14.1 `.github/workflows/ci.yml` — on every push and PR

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: dart format --set-exit-if-changed .
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage
      - uses: actions/upload-artifact@v4
        with: { name: coverage, path: coverage/lcov.info }
```

> `config/dev.json` is gitignored, so CI must not need real keys. Tests use a fake Supabase client; if any test needs the defines, pass dummy values via `--dart-define`.

### 14.2 `.github/workflows/release.yml` — on a version tag

```yaml
name: Release APK
on:
  push:
    tags: ['v*']
jobs:
  build-apk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - name: Restore keystore
        run: echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/upload-keystore.jks
      - name: Write key.properties
        run: |
          cat > android/key.properties <<EOF
          storePassword=${{ secrets.KEYSTORE_PASSWORD }}
          keyPassword=${{ secrets.KEY_PASSWORD }}
          keyAlias=${{ secrets.KEY_ALIAS }}
          storeFile=upload-keystore.jks
          EOF
      - name: Write config
        run: |
          mkdir -p config
          cat > config/prod.json <<EOF
          { "SUPABASE_URL": "${{ secrets.SUPABASE_URL }}",
            "SUPABASE_ANON_KEY": "${{ secrets.SUPABASE_ANON_KEY }}",
            "APP_ENV": "prod" }
          EOF
      - run: flutter build apk --release --dart-define-from-file=config/prod.json
      - uses: softprops/action-gh-release@v2
        with: { files: build/app/outputs/flutter-apk/app-release.apk }
```

**Required GitHub secrets:** `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`.

> iOS is **not** built in CI. Free-account signing requires the Mac and a connected device; it cannot be automated on a hosted runner.

### 14.3 Versioning
`pubspec.yaml` → `version: 1.0.0+1`. The `+N` build number **must increase on every distributed build** — this is what the in-app update check compares (§11.14) and what Android uses to allow an over-the-top install. Tag releases `v1.0.0`.

---

## 15. Security & Privacy

1. **RLS is the only authorisation boundary that matters.** Client-side hiding of admin controls is UX, not security. Section 7.1 must be verified before any real data is entered.
2. **Never ship the `service_role` key.** If it ever appears in the repo or an APK, rotate it immediately in the Supabase dashboard.
3. **Sign-ups disabled** in Supabase Auth (§5.5 step 5) — this is what stops a stranger with the anon key from creating an account and reading the family's data. **This setting is as important as RLS.**
4. **Receipts** are in a private bucket, served only via short-lived signed URLs.
5. **Local database** is unencrypted SQLite. Acceptable given each phone has a device lock; if that changes, swap `sqlite3_flutter_libs` for SQLCipher. Sign-out wipes it.
6. **Logs** must never contain amounts, notes, emails, or tokens. Log IDs and counts only.
7. **Backups:** Supabase free tier does not guarantee point-in-time recovery. The admin runs the full JSON backup export (§11.11) monthly and stores it in Google Drive. This is a documented manual duty, not an automated feature.
8. **Password policy:** minimum 8 characters, enforced by Supabase settings.

---

## 16. Build & Distribution

### 16.1 Android — one-time keystore setup

```bash
keytool -genkey -v -keystore ~/kharcha-upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias kharcha
```
Answer the prompts; **remember the passwords** and back the `.jks` file up somewhere safe (Google Drive, password manager). **If you lose this keystore, family members must uninstall and reinstall the app to take an update** — the local cache is lost (cloud data is not).

`android/key.properties` (gitignored):
```properties
storePassword=<...>
keyPassword=<...>
keyAlias=kharcha
storeFile=/Users/<you>/kharcha-upload-keystore.jks
```

`android/app/build.gradle.kts` — load the properties and wire the release signing config; set `minSdk = 26`, `targetSdk` to the current Flutter default, and enable `isMinifyEnabled = true` with `isShrinkResources = true` for release.

### 16.2 Android — build and install

```bash
fvm flutter build apk --release --dart-define-from-file=config/prod.json
# Output: build/app/outputs/flutter-apk/app-release.apk  (~25–40 MB)
```

Split by ABI to halve the size (optional):
```bash
fvm flutter build apk --release --split-per-abi --dart-define-from-file=config/prod.json
# Give family members the arm64-v8a APK (correct for essentially every phone since 2017)
```

**Install methods**
- **By cable:** `adb install -r build/app/outputs/flutter-apk/app-release.apk` (requires USB debugging on; MacBook Air M2 needs a USB-C-to-USB-C or USB-C-to-USB-A-adapter cable).
- **By file (preferred, works remotely):** upload the APK to Google Drive → share the link → the recipient downloads it → taps it → Android prompts "Allow this source to install apps" → allow → Install.
- The **first** install of a new keystore requires uninstalling any previous differently-signed build.

**Android device checklist:** allow install from unknown sources for the browser/Drive app; allow notifications; disable battery optimisation for Kharcha (Settings → Apps → Kharcha → Battery → Unrestricted) so scheduled reminders fire.

### 16.3 iOS — free Apple ID sideload (D3)

> **Read this whole subsection before starting. This is the most fragile part of the project.**

#### 16.3.1 Cable
The MacBook Air M2 has USB-C ports only.
- iPhone 15 / 16 / newer → **USB-C to USB-C** cable.
- iPhone 14 or older → **USB-C to Lightning** cable (Apple's own, or any MFi one). A charge-only cable will not work — it must carry data.
- After the first successful wired pairing you can enable **wireless debugging**: Xcode → Window → Devices and Simulators → select the device → tick **"Connect via network"**. Subsequent re-signings can then be done over Wi-Fi, which matters a lot for the 7-day renewal cycle.

#### 16.3.2 One-time Xcode configuration
1. `open ios/Runner.xcworkspace` (the workspace, not the project).
2. Select the **Runner** target → **Signing & Capabilities**.
3. Tick **Automatically manage signing**.
4. **Team** → your Personal Team (`<Your Name> (Personal Team)`).
5. **Bundle Identifier** → `com.panicker.kharcha`. If Xcode says the identifier is unavailable, append something unique (e.g. `com.panicker.kharcha.vp`) and use that everywhere thereafter.
6. Set **Minimum Deployments → iOS 15.0**.
7. Do **not** add any capability that a free account cannot provision — no Push Notifications, no App Groups, no iCloud, no Associated Domains. (This is why D6 exists.)
8. In `ios/Podfile`, set `platform :ios, '15.0'`, then:
   ```bash
   cd ios && pod install --repo-update && cd ..
   ```

#### 16.3.3 Info.plist permission strings (required or the app is rejected at launch)
```xml
<key>NSCameraUsageDescription</key>
<string>Kharcha uses the camera to capture receipt photos for your expenses.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Kharcha lets you attach receipt photos from your photo library.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Kharcha can save exported reports to your photo library.</string>
```

#### 16.3.4 Installing on a family iPhone
1. Connect the iPhone by cable. Unlock it and tap **Trust This Computer**.
2. The iPhone must be added to your free team's device list — Xcode does this automatically the first time you build to it.
3. From the project root:
   ```bash
   fvm flutter devices          # find the device id
   fvm flutter run --release --device-id=<id> --dart-define-from-file=config/prod.json
   ```
   (Release mode is required; a debug build stops working the moment the cable is unplugged.)
4. On the iPhone: **Settings → General → VPN & Device Management → Developer App → <your Apple ID> → Trust**.
5. Launch the app.

#### 16.3.5 The 7-day renewal ritual (unavoidable with a free account)
A free-team provisioning profile expires after **7 days**. On expiry the app refuses to launch with "unable to verify app".

**Renewal procedure** (takes ~3 minutes per phone):
1. Bring the iPhone within Wi-Fi range of the Mac (or connect the cable).
2. `fvm flutter run --release --device-id=<id> --dart-define-from-file=config/prod.json`
3. The app is re-signed and reinstalled over the top. **App data and the local cache normally survive**; even if they do not, everything re-downloads from Supabase — which is precisely why the app is cloud-backed rather than local-only.

**Practical mitigations**
- Set a recurring calendar reminder every 6 days.
- Keep both iPhones paired for wireless debugging so no cable hunting is needed.
- Free accounts allow only **3** sideloaded apps and **10 new App IDs per 7 days** — don't burn App IDs by changing the bundle identifier casually.

#### 16.3.6 Escape hatch
If the 7-day cycle becomes intolerable, buy the **Apple Developer Program (₹8,900/yr approx.)**. This gives:
- Ad-hoc provisioning valid **1 year** (install once, forget for a year), or
- **TestFlight** — wireless installs, 90-day builds, updates pushed without touching the phone, and
- The Push Notifications entitlement, which unlocks the FCM upgrade in §18.4.

This is the single highest-leverage ₹9k in the project. The spec is written so that switching is a configuration change, not a rewrite: change the Team in Xcode, add the capability, and (optionally) implement §18.4.

### 16.4 Rollout order (recommended)
1. Build and install on **your own** Android phone. Use it alone for 3–5 days with real expenses.
2. Fix whatever annoys you. Bump the version.
3. Install on your own iPhone (if you have one) to validate the iOS path before involving family.
4. Roll out to one family member. Watch what confuses them.
5. Roll out to the rest.

---

## 17. Task Backlog — Executable Build Plan

> **Format:** `T-<phase>.<n>`. Build in order. Do not start a phase until the previous phase's gate passes.

### Phase 0 — Environment & scaffold

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-0.1 | Install Xcode, CLT, Homebrew, CocoaPods, Android Studio, JDK 17 per §4.1–4.4 | `flutter doctor -v` shows no red X for Flutter, Android, Xcode |
| T-0.2 | Install FVM, pin Flutter stable, record the version in `docs/DECISIONS.md` | `fvm flutter --version` matches the recorded version |
| T-0.3 | Create the Flutter project per §4.6 with org `com.panicker`, name `kharcha` | `fvm flutter run` launches the counter app on an Android emulator |
| T-0.4 | Apply the `.gitignore` from §4.7; create `docs/SPEC.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md` | `git status` shows no secrets tracked |
| T-0.5 | Add every package from §9.3 via `flutter pub add`; commit `pubspec.lock` | `fvm flutter pub get` succeeds; `fvm flutter analyze` clean |
| T-0.6 | Configure lints: `flutter_lints` + `riverpod_lint` + `custom_lint` in `analysis_options.yaml` | `fvm flutter analyze --fatal-infos` passes |
| T-0.7 | Set Android `minSdk = 26`, JDK 17, and iOS deployment target 15.0 | Debug builds succeed on both platforms |
| **Gate 0** | | Empty app runs on an Android emulator **and** an iOS simulator |

### Phase 1 — Supabase backend

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-1.1 | Create the Supabase project in `ap-south-1`; store credentials safely | Project URL and anon key recorded in `config/dev.json` |
| T-1.2 | `supabase init`, `supabase link` | `supabase/` directory exists and is linked |
| T-1.3 | Write migrations `0001`–`0004` (§6.2–6.5) | `supabase db push` succeeds; tables visible in the dashboard |
| T-1.4 | Write `0005_functions_triggers.sql` (§6.6) | `select public.advance_due_date('2026-01-31','monthly',1,31,null)` returns `2026-02-28` |
| T-1.5 | Write `0006_rls.sql` (§7) | Every table shows "RLS enabled" in the dashboard |
| T-1.6 | Write `0007_views.sql` and `0010_app_releases.sql` | `select public.get_dashboard(current_date)` returns valid JSON |
| T-1.7 | Write `0008_storage.sql` and `0009_seed.sql`; create the household row and 5 auth users per §5.5; disable sign-ups | 5 rows in `profiles`, one `admin`; sign-up returns an error |
| T-1.8 | **Execute the full RLS verification checklist §7.1** and record results in `docs/DECISIONS.md` | All 8 checks behave as specified |
| **Gate 1** | | A member JWT can read all household expenses and cannot modify anyone else's |

### Phase 2 — Core scaffold & local database

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-2.1 | Implement `core/config/app_config.dart` with compile-time defines (§5.6) | App asserts loudly when defines are missing |
| T-2.2 | Implement `core/money/money.dart` (§9.4) | Unit tests for parse/format pass, incl. lakh/crore |
| T-2.3 | Implement `core/time/app_time.dart`: IST now, month start/end, `spentOn` conversion, month labels | Unit tests incl. the 23:55-on-the-30th case |
| T-2.4 | Implement `Result`, `Failure`, `ErrorMapper`, `AppLogger` (§9.7–9.8) | Unit tests for the mapper's classification |
| T-2.5 | Define all Drift tables mirroring §6 + `OutboxEntries` + `SyncMeta`; `schemaVersion = 1` | `dart run build_runner build` generates cleanly; the DB opens |
| T-2.6 | Write DAOs: expense, income, category, payment method, budget, recurring, attachment, outbox, sync meta | In-memory Drift tests for each DAO's CRUD |
| T-2.7 | Build the freezed domain models and their mappers to/from Drift rows and JSON | Round-trip tests: model → JSON → model is identical |
| T-2.8 | Set up Riverpod: `ProviderScope`, `riverpod_generator`, a `providers.dart` barrel | App boots with `ProviderScope` |
| T-2.9 | Set up `go_router` with the route map (§10.1) and placeholder screens | Every route navigates without error |
| **Gate 2** | | `fvm flutter test` green; app boots to a placeholder dashboard |

### Phase 3 — Authentication

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-3.1 | `supabase_flutter` initialisation in the splash bootstrap (§11.1) | Supabase client is available via a provider |
| T-3.2 | `AuthRepository`: sign in, sign out, reset password, current session, auth stream | Unit tests with a mocked client |
| T-3.3 | Login screen + controller, with inline validation and friendly errors | Wrong password shows the specified message |
| T-3.4 | Router auth redirect + splash routing logic | Signed-out user always lands on `/login` |
| T-3.5 | Profile bootstrap: fetch and cache the signed-in user's profile and `household_id` locally | `currentProfileProvider` resolves offline from cache |
| T-3.6 | Offline session tolerance (§11.1) and sign-out wipe | Aeroplane-mode relaunch stays signed in; sign-out empties the Drift DB |
| **Gate 3** | | Sign in, force-quit, relaunch offline → dashboard placeholder, still signed in |

### Phase 4 — Sync engine (the heart of the app)

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-4.1 | `ConnectivityService` with an online/offline stream | Toggling aeroplane mode updates the stream |
| T-4.2 | Remote data sources for every entity (select-since-cursor, upsert, soft delete) | Integration test against the real dev project |
| T-4.3 | `OutboxProcessor` with dependency ordering, backoff, and permanent/transient classification (§9.6) | Unit tests for ordering, backoff maths, and both failure classes |
| T-4.4 | `PullService` with paging, cursor overlap, tombstone handling | Unit tests incl. a 501-row paged pull |
| T-4.5 | `SyncEngine` orchestration + single-flight lock + all six trigger points | Rapid double-trigger runs the cycle once |
| T-4.6 | Conflict resolution per D12, with the losing version logged | Test 5 from §13 passes |
| T-4.7 | `SyncState` provider + offline/sync banner widget | Banner reflects offline, syncing, error, pending-count |
| T-4.8 | Realtime listener with 2 s debounce, behind a feature flag defaulting to on | Disabling the flag leaves the app fully correct |
| **Gate 4** | | Two devices (or two emulators) signed in as different members see each other's changes within 10 s online, and reconcile correctly after both edit offline |

### Phase 5 — Expenses, categories, payment methods

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-5.1 | `CategoryRepository` + `PaymentMethodRepository` (local-first read, admin-only write) | Members see no write controls; RLS rejects a forced write |
| T-5.2 | Category management screen (§11.5) with reorder, archive, icon/colour pickers | Reorder persists and syncs |
| T-5.3 | Payment method management screen | Same |
| T-5.4 | `ExpenseRepository`: create/update/soft-delete → Drift + outbox, streaming reads | Unit tests; a write while offline lands in the outbox |
| T-5.5 | Add/Edit Expense screen per §11.2, including the chip rows, defaults, and autocomplete | Save completes in < 100 ms perceived; works offline |
| T-5.6 | Duplicate guard and the Undo snackbar | Both behave per spec |
| T-5.7 | Expense list per §11.3: grouping, sticky headers, infinite scroll, swipe actions | Smooth scroll with 5,000 seeded rows |
| T-5.8 | Filter sheet + search + filtered-total header | Filters combine correctly; total matches the filtered set |
| T-5.9 | Expense detail screen with edit/delete permissions | A member cannot see edit controls on someone else's expense |
| **Gate 5** | | Full expense CRUD works online and offline, on both platforms |

### Phase 6 — Dashboard

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-6.1 | `ReportRepository` with local Drift aggregate queries: household total, per-member, per-category, per-payment-method, month-over-month | DAO tests with seeded data; totals match a hand-computed fixture |
| T-6.2 | Month selector with bounds and persistence across tabs | Cannot select a future month |
| T-6.3 | Dashboard cards 1, 3, 4, 5 (§11.4) | Numbers match the Expense List's filtered totals exactly |
| T-6.4 | Pull-to-refresh wired to `SyncEngine.sync()` | Spinner reflects real sync state |
| T-6.5 | Empty states for a household with no data | No crashes, no `NaN`, no `₹0.00` division errors |
| **Gate 6** | | Dashboard totals are provably equal to the sum of listed expenses for the same month |

### Phase 7 — Income

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-7.1 | `IncomeRepository` mirroring the expense repository | Tests |
| T-7.2 | Add/Edit Income screen and income list | Works offline |
| T-7.3 | Dashboard income + net-saved figures (card 1) | `net = income − expense` for the selected month |
| **Gate 7** | | Income never contaminates any expense total |

### Phase 8 — Budgets & alerts

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-8.1 | `BudgetRepository` + scope validation matching the DB constraint | Invalid scope shapes are rejected client-side too |
| T-8.2 | Budget list and editor screens (§11.7), incl. "copy to next 12 months" | Creates exactly 12 rows |
| T-8.3 | Local budget status computation incl. rollover | Unit tests for ok / warning / exceeded and rollover maths |
| T-8.4 | Dashboard budget card (card 2) | Shows spent, remaining, days left, daily allowance |
| T-8.5 | Budget alert evaluation + deduplicated local notifications | Crossing 80% notifies once; crossing again in the same month does not |
| **Gate 8** | | A budget alert fires exactly once per status transition per month |

### Phase 9 — Recurring

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-9.1 | Dart `advanceDueDate` mirroring the SQL function, with month-end clamping | Unit tests incl. 31 Jan → 28 Feb and leap years |
| T-9.2 | `RecurringRepository` + rule editor with the 3-occurrence preview | Preview matches the engine's output |
| T-9.3 | Posting engine inside `sync()` (§11.8), with the 24-occurrence catch-up cap | A rule dormant for 2 years posts at most 24 and then stops cleanly |
| T-9.4 | Duplicate-post protection: catch the unique-index violation and treat it as success | Two emulators posting simultaneously create exactly one expense |
| T-9.5 | Pending confirmations card on the Dashboard with Post / Skip | Skip advances `next_due_date` without creating a transaction |
| **Gate 9** | | Test 4 from §13 passes on two devices |

### Phase 10 — Receipts

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-10.1 | Camera/gallery capture + compression pipeline (§11.9) | A 4 MB photo becomes < 400 KB |
| T-10.2 | Local receipt cache directory + `AttachmentRepository` | Offline capture stores locally and queues an upload |
| T-10.3 | Storage upload in the outbox processor; `has_receipt` maintained on the expense | Upload resumes after reconnecting |
| T-10.4 | Thumbnail on the expense detail; full-screen viewer with pinch-zoom and share | Signed URL fetched and cached, not re-downloaded |
| T-10.5 | Deletion cascade for attachments and storage objects | No orphan rows; orphan objects listed in Diagnostics |
| **Gate 10** | | Capture offline → reconnect → the image is visible on a second device |

### Phase 11 — Analytics

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-11.1 | Aggregate queries for all 7 charts in §11.10 | DAO tests against a fixture |
| T-11.2 | Monthly trend, category donut, member comparison charts | Render correctly in light and dark |
| T-11.3 | Payment-method split, day-of-week, top merchants, MoM table | Same |
| T-11.4 | Empty and single-data-point states for every chart | No exceptions, no infinite axes |
| **Gate 11** | | Every chart's totals reconcile with the Dashboard for the same period |

### Phase 12 — Export

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-12.1 | CSV builder with the exact header from §11.11 and a UTF-8 BOM | Opens correctly in Excel and Google Sheets with ₹ intact |
| T-12.2 | PDF report builder | Renders the summary and both tables; < 500 KB |
| T-12.3 | Export screen with range/member/category selection + `share_plus` | Shares to WhatsApp and Gmail successfully |
| T-12.4 | Admin-only full JSON backup | Re-importable by hand into Supabase; contains every table |
| **Gate 12** | | A month's CSV total equals the Dashboard total for that month |

### Phase 13 — Notifications

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-13.1 | `flutter_local_notifications` + `timezone` init; Android 13 and iOS permission requests | Permission prompt appears once on first launch |
| T-13.2 | Notification scheduler service; re-schedule everything on every app start | Reminders survive a device reboot (re-armed on next launch) |
| T-13.3 | All six notification types in §11.12 with per-type settings toggles | Each can be turned off and stops firing |
| T-13.4 | Deep-linking from a notification tap into the right screen | Tapping a budget alert opens that budget |
| **Gate 13** | | Daily reminder fires on a physical Android device and is correctly skipped when an expense was already logged |

### Phase 14 — Settings, admin, diagnostics

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-14.1 | Settings screen structure (§11.13) | All sections navigate |
| T-14.2 | Profile editing, change password, sign out | Password change works against Supabase |
| T-14.3 | Members list; admin sees roles and can toggle `is_active` | RLS blocks a member attempting the same |
| T-14.4 | "Sync now" and "Clear local cache and re-download" | Cache clear rebuilds the full local DB from Supabase |
| T-14.5 | Diagnostics: outbox contents, failed items with retry/discard, in-memory log viewer, share logs | A deliberately failed item is visible and retryable |
| T-14.6 | In-app update check (§11.14), incl. the blocking `min_supported` path | Bumping `app_releases` shows the banner within 24 h |
| **Gate 14** | | You can diagnose a sync failure on a family member's phone using only the Diagnostics screen |

### Phase 15 — Test hardening & CI

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-15.1 | Fill in every unit test listed in §13 | `fvm flutter test` green |
| T-15.2 | Money and date/timezone edge-case tests | Cases 1–3 from §13 pass |
| T-15.3 | Sync engine branch tests | Case 5 passes; 100% branch coverage in `sync/` |
| T-15.4 | Widget tests for the key screens | Green |
| T-15.5 | Golden-path integration test (§13) | Passes on a real Android device |
| T-15.6 | `ci.yml` and `release.yml` (§14) with all secrets configured | A push runs CI green; a tag produces a downloadable APK |
| **Gate 15** | | CI green on `main`; `flutter analyze --fatal-infos` clean; formatter clean |

### Phase 16 — Build, sign, distribute

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-16.1 | Generate the Android keystore, wire `key.properties` and the release signing config (§16.1) | `flutter build apk --release` produces a signed APK |
| T-16.2 | App icon and launcher name (generic — no design work; `flutter_launcher_icons` with a simple ₹ glyph) | Icon appears on both platforms |
| T-16.3 | Add the iOS `Info.plist` usage strings (§16.3.3) | The app does not crash when opening the camera |
| T-16.4 | Configure Xcode signing with the Personal Team (§16.3.2) | `flutter run --release` installs on a physical iPhone |
| T-16.5 | Install on all 5 devices; complete the per-device checklists (§16.2, §16.3.4) | Each member can sign in and add an expense |
| T-16.6 | Write `README.md`: build commands, install steps, the 7-day iOS ritual, backup duty, troubleshooting | A person who has never seen the project can rebuild and reinstall it from the README alone |
| T-16.7 | Publish the first `app_releases` row for both platforms | The in-app update check finds it |
| **Gate 16** | | All 5 devices are running the app against the production Supabase project |

### Phase 17 — Hardening & handover

| ID | Task | Acceptance / Verify |
|---|---|---|
| T-17.1 | Run the full RLS checklist again against production data | All 8 checks pass |
| T-17.2 | Seed 3 months of real historical expenses (manual entry or a CSV import script) | Dashboard shows meaningful trends |
| T-17.3 | Take the first full JSON backup; document the restore procedure in the README | The restore is proven on a scratch Supabase project |
| T-17.4 | Set a 6-day recurring calendar reminder for iOS re-signing | Reminder exists |
| T-17.5 | Two-week soak: log real expenses daily; record every bug in `docs/ISSUES.md` | No data loss, no unresolved sync failures |
| **Gate 17** | | The family has used the app for two weeks without you having to touch a database |

---

## 18. Deliberately Deferred (Phase 2 ideas)

These are **not** to be built in v1. They are recorded so scope stays honest.

| ID | Idea | Why deferred |
|---|---|---|
| 18.1 | Split & settle-up between members | Explicitly deselected; adds a whole debt-ledger domain |
| 18.2 | SMS / bank transaction auto-import | Android-only, fragile parsing, heavy permissions, Play Store policy landmine |
| 18.3 | Multi-currency | No current need (D7) |
| 18.4 | **Firebase Cloud Messaging push** | Requires a paid Apple Developer account. Upgrade path: buy the account → add the Push capability → add `firebase_messaging` → create a Supabase Edge Function that sends via FCM on budget-exceeded and daily-summary events → store device tokens in a `device_tokens` table with RLS |
| 18.5 | Home-screen widget / quick-add shortcut | Platform-specific native work |
| 18.6 | Voice entry ("add 500 rupees groceries") | Nice, but needs speech APIs and heavy parsing |
| 18.7 | Attachments on income; multi-page receipts | Low value for effort |
| 18.8 | Encrypted local DB (SQLCipher) | Only if a family phone stops using a screen lock |
| 18.9 | Scheduled server-side recurring posting (Supabase `pg_cron`) | Client-side posting is sufficient for 5 daily-active devices |
| 18.10 | Web dashboard for the admin | Flutter web build is cheap to add later if wanted |

---

## 19. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | iOS 7-day expiry causes family members to abandon the app | High | High | Calendar reminder; wireless debugging; §16.3.6 escape hatch clearly costed |
| R2 | RLS misconfiguration exposes data via the shipped anon key | Medium | Critical | §7.1 checklist is a hard gate (T-1.8, re-run at T-17.1); sign-ups disabled |
| R3 | Sync conflict silently loses an edit | Medium | High | LWW documented (D12); losing version logged; Diagnostics screen; soft deletes make recovery possible |
| R4 | Supabase free-tier project paused for inactivity | Medium | Medium | Free projects pause after ~1 week of no requests — daily family use prevents this; the admin should also keep the dashboard bookmarked |
| R5 | Lost Android keystore | Low | Medium | Back it up to Drive and a password manager at T-16.1 |
| R6 | Family members find the app too fiddly and stop logging | Medium | High | G1's 10-second target is a real requirement, not a nicety; F-02 optimisations exist for this reason |
| R7 | Local DB corruption on one device | Low | Low | "Clear local cache and re-download" (T-14.4) resolves it entirely |
| R8 | Timezone bugs put expenses in the wrong month | Medium | Medium | `spent_on` is derived server-side in IST by a BEFORE trigger; the Dart mirror of that logic is unit-tested (T-15.2) |
| R9 | The 5 MB storage limit or 1 GB bucket fills up | Low | Low | Compression to <400 KB → ~2,500 receipts fit in the free tier |
| R10 | AI-generated code drifts from this spec over a long build | High | Medium | Phase gates, `docs/PROGRESS.md`, one commit per task, CI on every push |

---

## 20. Appendices

### 20.1 Command cheat-sheet

```bash
# Run
fvm flutter run --dart-define-from-file=config/dev.json

# Codegen (after any model/Drift/Riverpod change)
fvm dart run build_runner build --delete-conflicting-outputs
fvm dart run build_runner watch  --delete-conflicting-outputs   # during development

# Quality
fvm flutter analyze --fatal-infos
fvm dart format .
fvm flutter test

# Database
supabase db push                       # apply migrations
supabase db diff -f <name>             # generate a migration from dashboard changes
supabase gen types dart --linked       # optional: generated types

# Release
fvm flutter build apk --release --dart-define-from-file=config/prod.json
fvm flutter run --release --device-id=<iphone> --dart-define-from-file=config/prod.json

# Devices
fvm flutter devices
adb devices
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### 20.2 `docs/PROGRESS.md` format

```
| Task   | Status | Date       | Notes                                   |
|--------|--------|------------|-----------------------------------------|
| T-0.1  | done   | 2026-09-04 | flutter doctor clean except Chrome      |
| T-0.2  | done   | 2026-09-04 | Pinned Flutter 3.35.2                   |
```

### 20.3 Glossary

| Term | Meaning |
|---|---|
| Household | The single family tenant; all data is scoped to one `household_id` |
| Member | A `profiles` row linked to an `auth.users` row |
| Paise | 1/100 of a rupee; the integer unit all money is stored in |
| Outbox | Local queue of mutations waiting to be pushed to Supabase |
| Tombstone | A row with `deleted_at` set, used to propagate deletions |
| LWW | Last-write-wins conflict resolution based on `updated_at` |
| Occurrence | One posted instance of a recurring rule, keyed by `occurrence_date` |
| Sideload | Installing an app without an app store |

### 20.4 Open questions to revisit after two weeks of real use
1. Is the 10-second add-expense target actually being met in practice, or does the category chip row need reordering by personal frequency rather than household frequency?
2. Do members want to see each other's individual line items, or would category-level visibility have been enough? (Changing this later is a one-line RLS edit plus a UI change.)
3. Is the 7-day iOS ritual sustainable, or should the ₹8,900 be spent in month one?
4. Are budgets being used at all, or only the dashboard totals?
5. Should income be per-member or a single household figure the admin maintains?

---

**End of specification. Build in phase order. Verify every gate. Record every decision.**
