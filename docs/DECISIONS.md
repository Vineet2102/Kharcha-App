# Decisions Log

Running log of implementation decisions made while building Kharcha, per
`docs/SPEC.md` §0 rule 4: ambiguities are resolved with the simplest option
that satisfies the acceptance criteria, and recorded here with a rationale.

---

## 2026-09-03 — Phase 0

### Pinned Flutter version
- **Flutter 3.47.2**, channel `stable`, Dart 3.13.2, installed via FVM.
- Pinned for this project with `fvm use stable` → `.fvm/fvm_config.json`.

### Project location
- Spec §4.6 suggests `~/Developer/kharcha`. The project already lives at
  `~/Desktop/KHARCHA` (where `KHARCHA_SPEC.md` was placed), so the Flutter
  project was scaffolded in place with `flutter create ... .` instead of a
  new directory under `~/Developer`. No functional difference; keeps
  everything in one place.

### `flutter create` flags
- Spec §4.6 lists a `--org-name` flag. This flag does not exist in current
  Flutter (`flutter create -h` confirms only `--org`, `--project-name`,
  `--platforms`, etc.). `--org com.panicker` alone sets the organization
  used for the Java package name and iOS bundle identifier prefix, which is
  the effect the spec wanted. Ran without `--org-name`.

### JDK 17 installation
- `brew install --cask temurin@17` requires `sudo` with an interactive
  terminal to enter a password; not available in this automated session,
  and the failure reproduced even via the `!`-prefixed direct-terminal
  path. Worked around by downloading the Temurin 17 macOS aarch64 **tar.gz**
  archive directly from Adoptium (no installer, no sudo) and extracting it
  to `~/Library/Java/JavaVirtualMachines/jdk-17.0.20.1+1/`. Verified with
  `java -version`. `JAVA_HOME` exported in `~/.zshrc` pointing at this path.
- In practice `flutter doctor` auto-detects and uses the JDK bundled with
  Android Studio (JetBrains Runtime, JDK 25) at
  `/Applications/Android Studio.app/Contents/jbr/Contents/Home` instead,
  since Flutter checks the Android Studio JBR before `JAVA_HOME`. Both JDKs
  are present on the machine; Android Studio's JBR is what Gradle actually
  uses for builds unless overridden with `flutter config --jdk-dir`.

### Android SDK command-line tools / licenses
- The Android SDK cmdline-tools shipped by the current Android Studio
  installation includes a new `android` CLI binary that **replaces**
  `sdkmanager` (which is now deprecated). The new tool shows and accepts
  the Android SDK Terms of Service once, automatically, on first invocation
  (when it downloads itself), and does not expose a `--licenses` flag —
  running `sdkmanager --licenses` or `flutter doctor --android-licenses`
  both print "Warning: The --licenses option is no longer needed." and
  make no further changes.
- `flutter doctor` still performs its own legacy check for known license
  hash files under `$ANDROID_HOME/licenses/` and reports
  "✗ Android license status unknown" because the new tool doesn't write
  the same hash files. This is treated as a **known cosmetic doctor
  warning** rather than a blocker: the SDK platform and build-tools are
  already installed and actual Gradle/Android builds are the real
  verification (per §0 rule 5, "do not skip verification" — but the
  verification used here is "the app builds and runs", not "doctor is
  100% green", since doctor's check is stale relative to newer tooling).
  Revisit if a real build ever fails with a license-related Gradle error.

### `.gitignore`
- Spec §4.7's FVM line (`.fvm/flutter_sdk`) was merged with `flutter
  create`'s own default `.gitignore`, which shipped with a blanket `.fvm/`
  ignore. Replaced the blanket ignore with the spec's more precise
  `.fvm/flutter_sdk` so that `.fvm/fvm_config.json` (the pinned version)
  is tracked in git, per §4.2: "Add `.fvm/` to `.gitignore` except
  `.fvm/fvm_config.json`."

### Packages: `custom_lint` / `riverpod_lint` deferred (§9.3, D13)
- `riverpod_generator` (needed for D13's code-generated Riverpod) currently
  requires `analyzer ^13.0.0`. No published version of `custom_lint` (the
  framework `riverpod_lint` plugs into) supports past `analyzer ^7.x`/`^8.x`
  yet — every combination of versions was tried and all fail to resolve.
  This is a genuine upstream ecosystem gap, not a local misconfiguration.
- Decision: ship without `custom_lint`/`riverpod_lint` for now. `flutter_lints`
  (standard, stable) still provides full `flutter analyze` coverage — it
  passes with 0 issues. Revisit by periodically retrying
  `flutter pub add --dev custom_lint riverpod_lint` once `custom_lint`
  publishes an analyzer-13-compatible release.

### Android `compileSdk` and core library desugaring (T-0.7, Gate 0)
- Flutter's default `compileSdk` (36) is below what two plugins require:
  `flutter_secure_storage` and `permission_handler_android` both need
  `compileSdk 37`. Set explicitly in `android/app/build.gradle.kts`.
- `flutter_local_notifications` requires Java 8+ core library desugoring.
  Enabled `isCoreLibraryDesugaringEnabled = true` and added
  `com.android.tools:desugar_jdk_libs:2.1.5` as a `coreLibraryDesugaring`
  dependency.
- With both fixes, `flutter run` on the Android emulator succeeds:
  APK builds, installs, and the app launches and renders (Impeller/OpenGLES
  backend). **Android confirms Gate 0.**

### iOS build blocked by macOS `com.apple.provenance` / codesign bug (Gate 0 — NOT PASSED)
- **Status: unresolved, deferred.** `fvm flutter run -d "iPhone 17"` fails
  every time at the `debug_unpack_ios` step with:
  `Failed to codesign .../Flutter.framework/Flutter with identity -.` /
  `resource fork, Finder information, or similar detritus not allowed`.
- Root cause: newer macOS (this machine: macOS 26.6.2 "Tahoe", Xcode 26.6)
  tags files with a `com.apple.provenance` extended attribute at
  copy-time. `codesign` unconditionally refuses to sign any file carrying
  it. This is a live, currently-unresolved upstream bug, not specific to
  this session — confirmed via web research to affect Flutter developers
  broadly on macOS Sequoia/Tahoe + Xcode 26. Tracked upstream at
  flutter/flutter#189734, #181103, #180351, #130639.
- The attribute is **OS-synthesized, not file-resident**: it survives even
  a byte-for-byte copy (`cat file > newfile`) and reappears on freshly
  copied build output regardless of which process does the copying —
  confirmed independently both from this session's tool calls (including
  with sandboxing disabled) and from the user's own, separate Terminal.app
  session.
- Plain `xattr -d com.apple.provenance <file>` silently no-ops (exits 0,
  attribute persists) in this session's process tree, but **`xattr -cr`
  (recursive clear-all) does work when run from the user's own Terminal.app**
  — it does not work when run from within this session's tool calls, even
  unsandboxed, suggesting the removal itself is also gated by process
  ancestry, not just the tagging.
- Applied a **local patch** to the FVM-managed Flutter SDK at
  `~/fvm/versions/stable/packages/flutter_tools/lib/src/ios/mac.dart`,
  function `removeExtendedAttributes`: added an `xattr -c -r <path>`
  fallback after the existing per-attribute `xattr -r -d` removal (which
  only works for `com.apple.FinderInfo`, not `com.apple.provenance`).
  Forced a rebuild of `flutter_tools.snapshot` by deleting
  `bin/cache/flutter_tools.{stamp,snapshot}` and running `flutter --version`.
  **This patch is NOT part of the Kharcha repo** — it lives in the global,
  machine-local FVM SDK cache and will be lost on `fvm` SDK reinstall/upgrade.
  If iOS work resumes, re-check whether this patch is still present, and
  whether it's still needed (an official Flutter fix may have landed).
- **Even with the patch, the build still failed** when run from the user's
  Terminal.app (same error). Not yet root-caused whether the patched
  `xattr -cr` call is failing on the *freshly copied* build artifact for a
  reason different from the source-file case (e.g. running as a
  subprocess of `flutter assemble`, which is itself a subprocess of
  `xcodebuild`, may have a different process-ancestry chain than a bare
  shell command), or whether some other factor is at play.
- **Decision (per user, 2026-09-03): proceed with Android-only for now.**
  iOS Gate 0 is explicitly NOT met — Section 17 says "do not skip the
  verification step" and "never mark a task done with a failing build," so
  this is recorded as a known, open blocker rather than a false pass.
  Revisit before Phase 16 (build/sign/distribute), which needs iOS working
  for 2 of 5 family devices. Options to try next time: (a) check if a
  newer Flutter/Xcode release has landed an official fix, (b) try building
  from a completely different, never-Claude-touched macOS user account or
  machine, (c) investigate whether Apple's a fix ships in a macOS point
  update.

## 2026-09-03 — Phase 1 (partial)

### Supabase CLI version
- Installed via `brew tap supabase/tap && brew install supabase/tap/supabase`.
- Version: **2.116.0**.

### Migrations written without a live project
- Wrote all ten migration files (`0001_extensions.sql` through
  `0010_app_releases.sql`) verbatim from spec §6–§8 into
  `supabase/migrations/`, and ran `supabase init` at the repo root
  (created `supabase/config.toml`, `supabase/.gitignore`).
- These have **not** been applied anywhere yet (`supabase db push` needs
  `supabase link`, which needs a project ref, which needs T-1.1). No
  Docker-based local stack (`supabase db start`) was attempted this
  session either, so the SQL is unexecuted and unverified beyond visual
  correctness against the spec.
- T-1.1 (create the actual Supabase project at supabase.com, in
  `ap-south-1`) and the rest of T-1.7 (creating the household row and the
  5 auth user accounts via the dashboard) require the admin's own
  Supabase account and were left for the user to do, or to hand
  credentials back for. `config/example.json` (placeholder, committed)
  was created; `config/dev.json` (real credentials, gitignored per
  existing `.gitignore` rule) was not, since no real credentials exist
  yet.
- T-1.8 (RLS verification checklist) is consequently also blocked on
  T-1.1.

## 2026-09-03 — Phase 1 (continued): live project created, schema pushed

### Supabase project created
- User created the Supabase account and project themselves (account
  creation and password entry are actions this agent does not perform).
  Org "Panicker Family" (free plan), project `kharcha`, region **South
  Asia (Mumbai) / `ap-south-1`** per spec §5.1. Project ref
  `jqorwgiowfxxgjvayznj`.
- This project was created under Supabase's newer API key system
  (publishable/secret keys, format `sb_publishable_...` /
  `sb_secret_...`) rather than the legacy JWT `anon`/`service_role` keys
  the spec's §5.2/§5.6 examples show. The publishable key is
  functionally the same thing the spec means by "anon key" — the
  dashboard itself labels it "safe to use in a browser if RLS is
  enabled" / "safe to share publicly" — so it was used as-is for
  `SUPABASE_ANON_KEY` in `config/dev.json`. `supabase_flutter ^2.17.2`
  (already pinned in `pubspec.yaml`) accepts this key format directly.

### `supabase login` doesn't work in an agent/non-TTY shell
- `supabase login` (no flags) fails with `LegacyLoginMissingTokenError:
  Cannot use automatic login flow inside non-TTY environments` when run
  from this session's Bash tool — there's no way to complete the
  browser-based OAuth device flow from a non-interactive shell.
- Worked around by having the user generate a personal access token
  from https://supabase.com/dashboard/account/tokens and run
  `export SUPABASE_ACCESS_TOKEN=...` themselves, in their own terminal,
  followed by `supabase link --project-ref jqorwgiowfxxgjvayznj` and
  later `supabase db push`. The token was deliberately never pasted into
  the chat/agent session — env vars set in the user's terminal don't
  carry over to this agent's separate Bash tool processes anyway, so
  each CLI command that needed the token had to be run by the user
  directly.

### Bug in spec §7 / §6.8: `app_releases` RLS enabled before the table exists
- `0006_rls.sql`, copied verbatim from spec §7, includes
  `alter table public.app_releases enable row level security;` and a
  `rel_select` policy on `app_releases`. But `app_releases` is only
  created in `0010_app_releases.sql` (spec §6.8) — migration files run
  in filename order, so `0006` runs before `0010` and `supabase db push`
  failed with `relation "public.app_releases" does not exist`
  (SQLSTATE 42P01) at that statement.
- Fix: moved the `app_releases` RLS-enable line and the `rel_select`
  policy out of `0006_rls.sql` and into `0010_app_releases.sql`,
  immediately after the `create table` statement. This is the simplest
  fix that preserves every other migration's content and ordering
  exactly as specified. After the fix, `supabase db push` completed
  successfully for all 10 migrations (migrations `0001`–`0005` had
  already been applied and were left untouched by the CLI; `0006`
  re-ran cleanly since the CLI rolls back a failed migration file as a
  single transaction).
- Verified live in the dashboard: all 10 tables + 4 reporting views
  present in Table Editor; the seed household row, 20 categories, and 6
  payment methods are present and linked to
  `11111111-1111-1111-1111-111111111111`.

## 2026-09-04 — Phase 2: core scaffold & local database

### Drift row class / domain model name collision (T-2.7)
- Drift's default data-class naming singularises the table class name
  (`Expenses` → `Expense`, `Categories` → `Category`, etc. — see
  `dataClassNameForClassName` in `drift_dev`). Every one of those generated
  names is identical to the corresponding freezed domain model name
  (`domain/models/expense.dart`'s `Expense`, etc.), since both were named
  after the same DB entity.
- This is only a problem where a single file needs both types at once —
  the mapper files (`data/local/mappers/*.dart`). Resolved by importing the
  domain model file with an `as domain` prefix in every mapper
  (`import '.../domain/models/expense.dart' as domain;`) and referencing
  the Drift-generated row type unprefixed. `SyncMeta` (the one table whose
  class name isn't a plural) needed no such handling — Drift's fallback
  naming appends `Data` for non-plural table names, so its row class is
  `SyncMetaData`, not `SyncMeta`.
- Elsewhere (routing, providers, screens) nothing yet imports both a Drift
  row type and a same-named domain model in one file, so this only matters
  going forward for repositories (Phase 5+) — apply the same `as domain`
  convention there.

### `AppTime` uses a fixed +5:30 offset, not the `timezone` package (T-2.3)
- India has no DST, so IST is always exactly UTC+5:30. `core/time/app_time.dart`
  hardcodes that offset rather than depending on `package:timezone`'s tz
  database, which spec §9.3 lists as a dependency for a different purpose
  (Phase 13's `flutter_local_notifications` scheduling, which genuinely
  needs `TZDateTime`). Keeps Phase 2's pure-Dart core free of any
  asset-loading/init step.
- `calendarDate()` mirrors the DB trigger `public.set_ist_date()` from
  `0005_functions_triggers.sql` exactly (convert to IST, take the date),
  so client-computed `spentOn`/`receivedOn` values will always agree with
  what the server trigger computes for the same instant.

### Placeholder screens share one `PlaceholderScreen` widget (T-2.9)
- Spec §9.2's folder structure implies one screen file per route (~19
  routes across `features/*/screens/`). Rather than duplicating a Scaffold
  body 19 times, every placeholder screen is a few-line wrapper around a
  single shared `features/shell/widgets/placeholder_screen.dart` widget.
  Each later phase replaces one wrapper's body with the real screen — the
  file locations already match §9.2, so nothing needs to move.
- The router boots straight to `/` (dashboard) instead of `/splash`, since
  splash's real job — deciding the auth redirect — is explicitly T-3.4
  (Phase 3). Gate 2 only requires booting to a placeholder dashboard;
  `/splash` and `/login` are wired and reachable but not yet the entry
  point.

### Riverpod 3.4 / freezed 4.0 / drift 2.34 API notes (pinned versions)
- Riverpod 3's codegen uses a single generic `Ref` type for every
  `@riverpod` function/class (imported from `riverpod_annotation`), not
  the old per-provider `FooRef` typedefs from Riverpod 2.
- Freezed 4.0 added a "primary constructor" style but the classic
  `factory Foo(...) = _Foo;` + `with _$Foo` style (used throughout
  `domain/models/`) still works unchanged and was kept for familiarity.
- `go_router` 18's `StatefulShellRoute.indexedStack` API (used for the
  4-tab bottom nav in `routing/app_router.dart`) is unchanged from the
  pattern in go_router's own examples.

### Gate 2 verification
- `fvm flutter analyze --fatal-infos`: clean.
- `fvm flutter test`: 44 tests green (money parsing/formatting incl. 1
  lakh/1 crore/rounding; the 23:55-on-the-30th IST boundary case;
  ErrorMapper classification; in-memory Drift DAO CRUD + soft-delete
  ordering; 9 domain-model JSON round-trips; the app-boots-to-dashboard
  widget test).
- Also run live on the `kharcha_test` Android emulator (API 34) via
  `fvm flutter run --dart-define-from-file=config/dev.json`: builds,
  installs, boots straight to the placeholder Dashboard with a working
  4-tab bottom nav and FAB, no crashes. First build was slow (~2 min)
  because `sqlite3_flutter_libs` native-compiles for 3 ABIs on a clean
  checkout — expected, not a regression.

## 2026-09-04 — T-1.7 / T-1.8: household users and RLS verification

### 4 auth users instead of the spec's 5
- Spec §5.5 assumes 5 family members. Per the user, only 4 accounts are
  needed right now: Rupesh, Tanish, Trupti (all `role='member'`) and
  Vineet (`role='admin'`). `handle_new_user` (0002_core_tables.sql)
  auto-created each `profiles` row on user creation, linked to the
  household via "pick the first (and only) household"; `display_name`
  and `role` were then set per-row via the SQL editor. A 5th member can
  be added later the same way — nothing in the schema assumes exactly 5.
- Sign-ups disabled (Authentication → Providers → Email → "Allow new
  users to sign up" off, saved successfully), locking the household to
  these 4 accounts per §5.5 step 5 / the R2 risk note in §17.

### T-1.8 — RLS verification checklist (§7.1), executed via SQL editor impersonation
- No UI/app exists yet to exercise RLS end-to-end (Phase 3+ auth/CRUD
  not built), so the checklist was run directly in the Supabase SQL
  editor using session-local JWT-claim impersonation rather than the
  dashboard's user-picker (simpler to script, same effect):
  ```sql
  begin;
  select set_config('request.jwt.claims', json_build_object('sub','<uid>','role','authenticated')::text, true);
  set local role authenticated;
  -- test query
  rollback;
  ```
  Every check ran inside `begin; ... rollback;` so no test — including
  the deliberately-attempted illegal writes — left any lasting change.
  Two throwaway expense rows (owned by Rupesh and Tanish) were inserted
  as the unrestricted `postgres` role beforehand to have real data to
  test against, and deleted again afterward once all 8 checks passed.
- **All 8 checks passed, no policy changes needed:**
  - RLS-1: Rupesh (member) selects all household expenses → saw both
    rows (his + Tanish's). Pass.
  - RLS-2: Rupesh updates Tanish's expense → 0 rows changed (verified by
    re-selecting the row's value inside the same transaction). Pass.
  - RLS-3: Rupesh deletes Tanish's expense → row still present. Pass.
  - RLS-4: Rupesh inserts an expense with `user_id` set to Tanish →
    `ERROR 42501: new row violates row-level security policy for table
    "expenses"`. Pass.
  - RLS-5: Rupesh inserts a category (admin-only per `cat_write`) →
    `ERROR 42501: ... "categories"`. Pass.
  - RLS-6: Vineet (admin) updates Rupesh's expense → succeeded. Pass.
  - RLS-7: anon role selects `expenses` → 0 rows (no policy grants `anon`
    access at all; only `to authenticated` policies exist). Pass.
  - RLS-8: Rupesh selects `expenses` filtered by a forged/other
    `household_id` → 0 rows (RLS's `household_id = current_household_id()`
    clause ignores what the query asks for). Pass.
- Conclusion: the `0006_rls.sql` policies as pushed match the spec's
  intent exactly — no further RLS work needed before Phase 3.

## 2026-09-04 — Phase 3 (Authentication)

### Login error copy corrected to match spec verbatim
- T-2.4's `ErrorMapper` mapped invalid-credentials `AuthException`s to
  "Incorrect email or password." — close to, but not, the string spec
  §11.1 actually specifies: "Email or password is incorrect." T-3.3's
  acceptance ("wrong password shows the specified message") makes this
  wording load-bearing for the first time, so it was corrected to match
  the spec exactly. The one existing test asserting the old string
  (`error_mapper_test.dart`) was updated alongside it.

### `supabase_flutter` key parameter renamed
- `Supabase.initialize(..., anonKey: ...)` is deprecated in
  `supabase_flutter` 2.17.2 in favour of `publishableKey:` (the project
  already uses Supabase's newer `sb_publishable_...` key format, per
  T-1.1). Switched to `publishableKey:` in `main()`; the `AppConfig`
  field and the `SUPABASE_ANON_KEY` dart-define name were left alone —
  purely a call-site rename, not a config format change.

### Bug found & fixed — sign-out wipe silently incomplete (auto-dispose race)
- First live pass of T-3.6 (Settings → Sign out) left the `profiles`
  table with 1 row after every other table was correctly emptied by
  `AppDatabase.wipeAll()`. Root cause, found via temporary debug logging
  plus reading `flutter run`'s console: `SignOutController` (and
  `LoginController`, same shape) were plain `@riverpod` — Riverpod
  **auto-dispose** providers. `AuthRepository.signOut()` flips the
  session to null as soon as it runs, which fires the T-3.4 router
  redirect immediately and unmounts the Settings screen the controller
  was read from. With no active `ref.watch` keeping it alive, Riverpod
  tore the provider down mid-flight, and the console showed: `Cannot use
  the Ref of signOutControllerProvider after it has been disposed.` This
  silently skipped (or ran a possibly-incomplete) `wipeAll()` — thrown
  into an unawaited zone, so nothing surfaced in the UI. Fixed by marking
  both `LoginController` and `SignOutController` `@Riverpod(keepAlive:
  true)`, matching every other cross-cutting provider in the app. Verified
  by re-running the full sign-in/sign-out cycle live and pulling
  `kharcha.sqlite` off the device (`adb exec-out run-as ... cat`) to
  confirm all 11 tables read 0 rows afterward.
- A second, narrower race was fixed defensively at the same time:
  `ProfileRepository.refresh()`'s background Supabase fetch (kicked off
  fire-and-forget by `currentProfileProvider`) can still be in flight at
  sign-out; without a guard, its response could land after `wipeAll()`
  and resurrect the profile row a second time. `refresh()` now re-checks
  `client.auth.currentSession` immediately before writing and aborts if
  the session has changed underneath it. This alone did not fix the bug
  above (the auto-dispose crash pre-empted it), but it closes a real
  independent window and was kept.
- Diagnostic method worth repeating: `adb exec-out run-as
  com.panicker.kharcha cat <path>` is the reliable way to pull a debug
  app's private SQLite file for direct inspection (`adb shell run-as ...
  cat > file` on the host side silently produces a 0-byte file — the
  shell redirection happens on the wrong side of the `adb shell`
  boundary; `exec-out` is required for binary-safe pulls). Also:
  automated `adb shell input tap`/`swipe` did not reach this emulator
  from this sandboxed environment at all (focus/window checks looked
  normal; taps simply had no effect, even on the notification shade) —
  manual taps from the user were used for every interactive step in this
  phase's live verification instead.

## 2026-09-04 — Phase 4 (Sync engine)

### Consolidated file layout vs. spec §9.2's literal per-entity file list
- Spec §9.2 names one remote-data-source file per entity
  (`expense_remote_ds.dart`, `income_remote_ds.dart`, ...). All 9 tables'
  remote reads/writes (select-since-cursor, upsert, soft-delete) are
  identical in shape, parameterised only by table name — so one shared
  `TableRemoteDataSource` (`data/remote/table_remote_data_source.dart`)
  implements the logic once, and the 9 named files (kept, for the DI/import
  ergonomics the spec's layout implies) are thin one-line subclasses.
- Similarly, the 9 `EntitySyncAdapter`s (the layer that bridges remote JSON
  to typed Drift rows — conflict resolution, tombstones, dispatch) live
  together in one file, `data/sync/entity_sync_adapters.dart`, rather than
  9 files — each adapter body is genuinely mechanical (delegates to the
  already-existing `domain.Model.fromJson()`/`.toCompanion()` mappers from
  Phase 2 plus the matching DAO), so nothing is gained by fragmenting them
  and side-by-side review is easier in one file. Per §0 rule 4 (simplest
  option that satisfies acceptance criteria, recorded here).

### `households` / `profiles` are pull-only, no-tombstone special cases
- Neither table has a `deleted_at` column server-side, and neither has any
  write UI planned before Phase 14 (Settings/admin) — so their adapters
  have `supportsPush = false` and throw `UnsupportedError` if the outbox
  ever somehow contains one (nothing currently enqueues either).
- `profiles` pulls **every** household member, not just the signed-in
  one — needed groundwork for Phase 6's per-member dashboard breakdown.
  The existing `ProfileRepository.refresh()` (T-3.5) is untouched; this
  pull is a superset and both paths upsert idempotently.
- `households` skips the since-cursor paging machinery entirely (a plain
  fetch-by-id) — there is exactly one row, ever, per §1.4.

### `OutboxEntries.status` column added — schema v1 → v2
- The outbox needed a way to distinguish "still eligible for auto-retry"
  from "permanently failed" (RLS denial, constraint violation — spec
  §9.6). Without it, `dueEntries()` would keep re-selecting a
  permanently-failed row forever (`next_attempt_at` stays null). Added
  `status` (`'pending' | 'failed'`, default `'pending'`), bumped
  `AppDatabase.schemaVersion` to 2 with an `addColumn` migration step.
  Safe — dev-only local DBs, no data loss.

### Failure classification reuses `ErrorMapper`, not a new HTTP-status table
- Spec §9.6 describes permanent-vs-transient by HTTP status (4xx vs
  network/5xx/429). `supabase-dart`'s `PostgrestException` doesn't reliably
  expose an HTTP status, but the existing `ErrorMapper` (T-2.4) already
  classifies the exact same distinction by Postgres error code
  (`PermissionFailure` for RLS denials, `ValidationFailure` for constraint
  violations) for the UI's error messages. `OutboxProcessor` reuses that
  mapping directly (`PermissionFailure`/`ValidationFailure` ⇒ permanent,
  everything else ⇒ transient with backoff) rather than inventing a second,
  parallel classification — one source of truth for "is this the user's
  fault or the network's fault."

### Bug found & fixed — Drift `DateTime` columns decode as local-flagged, not UTC
- Found while writing `pull_service_test.dart`: a `DateTime.utc(...)` value
  written to a Drift `dateTime()` column and read back compares **unequal**
  via `==` to the original — Drift's sqlite backend stores the correct
  absolute instant (confirmed: `read.toUtc() == original` always holds,
  and `.isAfter()`/`.isBefore()`/`.compareTo()` are unaffected since they
  compare the instant, not the flag) but decodes into a DateTime object
  flagged `isUtc: false`, and Dart's `DateTime.==` **is** sensitive to that
  flag even when the instant is identical.
- This was a real, not just a test, bug: `PullService._pullEntity()`
  derives its since-cursor from `SyncMeta.lastPulledAt` (read from Drift)
  and passes it to `.toIso8601String()` for the Postgrest query — a
  local-flagged DateTime serialises **without** a `Z`/offset suffix, which
  is ambiguous to interpret server-side. On a device actually running in
  IST (every Kharcha user, by design — §3), this would have silently
  shifted every pull's cursor by 5:30, at best re-fetching a wider window
  than necessary and at worst missing rows depending on how Postgrest
  resolves an unqualified timestamp string.
- Fixed by normalising with `.toUtc()` immediately after reading
  `lastPulledAt` from Drift, before using it (`pull_service.dart`). The
  D12 conflict check in `entity_sync_adapters.dart` needed no equivalent
  fix — it only ever uses `.isAfter()`, which is instant-correct regardless
  of the flag. Worth remembering for any future code that reads a Drift
  `DateTime` column and serialises it (rather than only comparing it).

### Bug found & fixed — single-flight lock set after an `await`
- Found via `sync_engine_test.dart`'s rapid-double-trigger test: the
  original `SyncEngine.sync()` checked `_syncing` synchronously but only
  *set* `_syncing = true` after `await connectivity.isOnline` — so two
  calls fired back-to-back both passed the guard before either reached the
  line that sets it, and both ran a full push/pull cycle. Fixed by moving
  `_syncing = true` to immediately after the synchronous guard checks, with
  the connectivity check moved inside the `try`/`finally`.

### Live verification (partial Gate 4 — see PROGRESS.md)
- Ran live on the `kharcha_test` emulator via
  `fvm flutter run --dart-define-from-file=config/dev.json`. User signed in
  with a real account. Pulled `kharcha.sqlite` off the device
  (`adb exec-out run-as ... cat`, same technique as Gate 3) and confirmed,
  against the live Supabase project: all 20 categories, all 6 payment
  methods, all 4 profiles, and the 1 household row present locally;
  `sync_meta` shows a populated `last_pulled_at`/`last_success_at` for
  every one of the 9 entities (including the empty ones — expense, income,
  budget, recurring_rule, attachment — proving `pullAll()` ran the full
  entity list, not just the ones with seed data); `outbox_entries` empty;
  no sync-related errors in the app process's logcat; sync banner rendered
  nothing (correct idle-and-clean state).
