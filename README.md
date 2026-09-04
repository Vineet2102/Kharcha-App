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
