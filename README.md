# Kharcha — Family Expense Tracker

A private, cross-platform household expense tracker for a five-member family,
built with Flutter and a hosted Supabase backend (Postgres + Auth + Storage +
Realtime). Every member logs their own expenses offline-first; everything
syncs to one shared household database and rolls up into household- and
per-member dashboards, budgets, recurring bills, receipts, and exports.

Private sideload only — there is no Play Store or App Store listing.

## Docs

- [`docs/SPEC.md`](docs/SPEC.md) — the full technical specification and
  phased build plan this project is built against. Read this first for any
  question about *what* the app should do.
- [`docs/PROGRESS.md`](docs/PROGRESS.md) — task-by-task build log, one row
  per task/gate, in build order.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — rationale for every non-obvious
  implementation choice and every bug found along the way, in build order.
- [`INSTALL.md`](INSTALL.md) — sideload install instructions to hand a
  friend, in plain (non-technical) language.
- [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md) — a complete beginner's
  guide to using the app itself, from first sign-up to every feature.
  Hand this to friends alongside `INSTALL.md`.
- [`docs/ONBOARDING.md`](docs/ONBOARDING.md) — the message template for
  inviting a friend, plus the rollout-ring order (§16.4) and the three
  questions friends actually ask.
- [`docs/legal/PRIVACY.md`](docs/legal/PRIVACY.md) /
  [`docs/legal/TERMS.md`](docs/legal/TERMS.md) — source content for the
  published privacy policy and terms (the `gh-pages` branch has the live
  HTML versions of these).

## Getting started

Flutter version is pinned via [FVM](https://fvm.app/) — see
`.fvm/fvm_config.json`. Install dependencies and run:

```sh
fvm flutter pub get
fvm flutter pub run build_runner build   # generates .g.dart / .freezed.dart
```

The app needs Supabase credentials passed as dart-defines. Copy
`config/example.json` to `config/dev.json` (gitignored) and fill in your own
project's URL and publishable key, then:

```sh
fvm flutter run --dart-define-from-file=config/dev.json
```

Run the test suite and static analysis with:

```sh
fvm flutter test
fvm flutter analyze --fatal-infos
```

Supabase schema migrations live in `supabase/migrations/` — see
`docs/PROGRESS.md`'s Phase 1 entries for how they were applied.

## Owner maintenance (monthly, spec T-M3.8)

Once real users' data is in the database, do this once a month — none of
it is automated:

1. **Check Supabase DB size and storage usage** (dashboard → Project
   Settings → Usage). Free-tier limits are generous for a household app,
   but this is the only way you'd notice before hitting one.
2. **Read new `feedback` rows** (Table Editor → `feedback`, sorted by
   `created_at`). This is the only place feedback lands — there's no
   admin UI or notification for it.
3. **Scan `last_seen_at`/`last_active_at`** (Table Editor → `profiles` /
   `households`). A household that's gone quiet for a long stretch is
   worth a check-in; an account that's never signed in past onboarding is
   worth following up on directly.
4. **Take a full backup.** Supabase's free tier doesn't guarantee
   point-in-time recovery — from any account, Settings → Data → Export
   (full backup JSON), and stash it in Google Drive. Don't rely on anyone
   else remembering to do this.

## Importing historical expenses (spec T-17.2)

`scripts/import_historical_expenses.dart` bulk-imports real past expenses
from a CSV, for backfilling the app with history that predates it (spec
§17's "seed 3 months of real historical expenses"). It talks directly to
Supabase — no build step, no local DB involved.

```bash
fvm dart run scripts/import_historical_expenses.dart <csv-path> \
  [--config config/prod.json] [--yes] [--skip-invalid]
```

CSV columns (header row required), matching the app's own export format
(spec §11.11) minus the fields a new row can't have yet:

```
date,time,member,amount_inr,category,payment_method,merchant,note
2026-06-03,19:42,Vineet,450.00,Groceries,UPI,Reliance Fresh,weekly veg
```

- `date` (required, `yyyy-MM-dd`), `member` (required, must match an
  existing household member's display name), `amount_inr` (required,
  positive) are the only required columns.
- `time` defaults to `12:00`; `category`/`payment_method` may be left
  blank; both must match existing household names when given.
- Sign in as the household **admin** when prompted — RLS only lets a
  non-admin insert expenses under their own name, so a member sign-in can
  only import their own rows.

Every row is validated (dates, amounts, and that member/category/payment
method names actually exist in the household) before anything is written,
and you get a total + row count to confirm before it inserts anything.
Pass `--skip-invalid` to import the valid rows anyway when some don't
pass validation, instead of aborting the whole run.

## Disaster recovery: full backup + restore (spec T-17.3)

The full JSON backup (Settings → Data → Full backup, admin only) is the
escape hatch if the Supabase project is ever lost or corrupted. **Take one
periodically and store it in Google Drive** — Supabase's free tier has no
point-in-time recovery.

To restore one into a Supabase project:

```bash
# 1. Apply every migration to the target project first.
supabase db push --project-ref <target-ref> --password <target-db-password> --include-all

# 2. Turn the backup JSON into a restore SQL script.
fvm dart run scripts/restore_backup.dart kharcha_YYYY-MM-DD_backup.json > restore.sql

# 3. Link to the target and run it (db query --linked, not --project-ref —
#    an unlinked connection needs direct Postgres access on port 5432, which
#    isn't always reachable).
supabase link --project-ref <target-ref> --password <target-db-password>
supabase db query --linked -f restore.sql

# 4. Link back to whatever project you were actually working against.
supabase link --project-ref <your-real-ref>
```

`scripts/restore_backup.dart`'s own header comment documents the restore
order and two non-obvious gotchas it works around: `profiles.id`'s FK to
`auth.users` (needs minimal placeholder auth users first) and
`0009_seed.sql`'s default categories/payment methods colliding by name on
a freshly-migrated target (cleared automatically before restoring).

**Proven 2026-09-08** against a real, disposable scratch Supabase project:
restored the real production backup (1 household, 4 profiles, 21
categories, 6 payment methods, 3 recurring rules, 14 expenses, 1 income, 4
budgets, 3 attachments), verified every row count and foreign key matched
the source with zero orphans, and confirmed RLS still enforced correctly
against the restored data — then deleted the scratch project. Full
write-up in `docs/DECISIONS.md`. **Known limitation**: this restores
database rows only — receipt image bytes live in Storage, not the JSON
backup, so restored `attachments` rows point at storage paths with
nothing behind them until receipts are re-uploaded or restored separately
from a Storage-level backup.
