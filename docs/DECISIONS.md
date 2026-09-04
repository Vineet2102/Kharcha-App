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

## 2026-09-04 — Phase 5 (Expenses, categories, payment methods)

### Bug found & fixed — mapper `toDomain()` never applied the Phase 4 `.toUtc()` fix
- Phase 4's DECISIONS.md entry ("Drift `DateTime` columns decode as local-flagged, not UTC") fixed the read side in `pull_service.dart` but the fix was never applied to the 9 `data/local/mappers/*.dart` files' `toDomain()` extensions — because until Phase 5, nothing ever read a Drift row, edited it, and serialised it back out. `CategoryRepository.update()`/`ExpenseRepository.update()` are the first code paths to do exactly that (fetch via `findById()` → `toDomain()`, `copyWith(...)`, then `jsonEncode(model.toJson())` for the outbox payload).
- Caught by `expense_repository_test.dart`'s first assertion, which compared `row.spentOn` (raw Drift row) against a `DateTime.utc(...)` literal and failed by exactly 5:30 — the IST offset. Root cause confirmed identical to the Phase 4 bug: the stored instant is correct, but Drift decodes it with `isUtc: false`.
- Fixed by adding `.toUtc()` (or `?.toUtc()` for nullable columns) to every DateTime field in all 9 mappers' `toDomain()`, so any domain model built from a local row is UTC-correct at the source — every downstream `.toIso8601String()`/equality check is then safe without each call site having to remember to normalise. Left uncorrected, editing an existing category/expense/etc. would have silently pushed its timestamps to Supabase 5:30 off on every device physically in IST (i.e. every Kharcha user, by design).

### `ExpenseFilter` and the Expense List's "infinite scroll" grow a `limit`, not an offset (T-5.7)
- Spec §11.3 says "Infinite scroll, page size 50, driven by a Drift `Stream` with `limit/offset`." Implemented instead as one live stream per filter state whose `limit` grows by 50 as the user nears the bottom (`ExpenseDao.watchFiltered(..., limit: n)`, offset always 0).
- True offset paging (`limit: 50, offset: 50*page`, one stream per page, stitched together) breaks in a way that matters here: if a row is inserted at the top of the sort order (e.g. a new expense synced from another device) while page 2 is already loaded, every already-loaded page's offset silently shifts by one, and the stitched list gets a duplicate or a gap. A single growing-limit stream re-runs the whole query and always reflects the live, correctly-ordered top-N — the "N" is the only paging state, so there's nothing to desync. Cost: each page-load re-scans up to `limit` rows instead of just the new 50, which is irrelevant at the row counts a single household will ever have (§13's 5,000-row smoke test is well within SQLite's comfort zone for an indexed `ORDER BY ... LIMIT`).

### Plain in-flow date headers, not true pinned/sticky headers (T-5.7)
- Spec §11.3 calls for "a sticky date header." No sticky-header package is in `pubspec.yaml`, and adding one is a dependency-surface decision left for the user rather than made unilaterally mid-task. Implemented as a normal (non-pinned) section header row per date group instead — same grouping and per-day subtotal, just not pinned to the top of the viewport while its group scrolls past. Revisit if the user wants a true pinned header (e.g. `flutter_sticky_header` or a `CustomScrollView` of `SliverPersistentHeader`s).

### `Expense.isDirty` added to the domain model, excluded from JSON both ways
- The list row's "cloud-off badge if `is_dirty`" (spec §11.3) needs the sync-bookkeeping flag that lives on the Drift row (`Expenses.isDirty`) but was never on the domain model (domain models mirror server columns only). Added `isDirty` to `domain.Expense` with `@JsonKey(includeToJson: false, includeFromJson: false)` so it's populated from the Drift row on read but silently dropped from both the outbox push payload and any pull-side `fromJson` — `is_dirty` isn't a Postgres column, and sending it in an `upsert()` payload would fail with "column not found." The same pattern (an extra local-only field on a domain model, JSON-excluded) can be reused if a later phase needs an equivalent per-row local flag on another entity.

### Duplicate-guard / Undo semantics clarified (T-5.6)
- Spec §11.2's "Save is instant and local... Undo (5s window; undo performs a local soft delete and removes the outbox entry if it hasn't been pushed)" is about undoing a **create** (the just-saved expense), not undoing a delete — there's no separate "undo delete" feature in scope. `ExpenseRepository.undoCreate(id)`: if the create's outbox `upsert` entry is still pending (`OutboxDao.removePendingUpsert` returns true), it's removed outright — the server never received the expense, so no delete needs to reach it either. If it's already been pushed (removal returns false), the row is soft-deleted and a real outbox `delete` entry is enqueued so the undo still propagates on the next sync. This is stricter than the spec's literal text (which only mentions the outbox-not-yet-pushed case) but closes the obvious race without adding real complexity.

### Bug found & fixed — the Undo snackbar never auto-dismissed (live verification)
- Found live: after saving an expense, the "Saved ✓ / Undo" snackbar stayed on screen indefinitely instead of dismissing after its 5s `duration`.
- Root cause: Flutter's `SnackBar` silently ignores `duration` whenever the device has accessible navigation on (e.g. TalkBack) — it waits for a manual dismiss instead, by design, so a screen-reader user isn't rushed. The `kharcha_test` emulator has this on.
- Fixed in `expense_detail_screen.dart`'s `_showSavedSnackbar` by capturing the `ScaffoldFeatureController` returned from `showSnackBar()` and force-closing it with an explicit `Future.delayed(Duration(seconds: 5), controller.close)`, rather than relying on `SnackBar.duration` alone — guarantees the same 5s window on every device regardless of accessibility settings. Worth remembering for any other timed snackbar/action this app adds later (e.g. a future delete-undo).

### Household id: `AppConstants.seedHouseholdId`, not a per-repository lookup
- Every Phase 5 repository/provider that needs a household id uses the same constant `sync_engine.dart` already uses (T-4.5), rather than resolving it from `currentProfileProvider` per call site — consistent with the single-tenant design (spec §1.4) and avoids a redundant provider dependency in every list/detail screen.

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

## 2026-09-04 — Phase 6 (Dashboard)

### Month-over-month is the same total query, called twice
- T-6.1 lists "month-over-month" as its own aggregate alongside household/
  per-member/per-category/per-payment-method totals. Rather than a
  dedicated comparison query, `ReportRepository.watchExpenseTotal()` just
  takes an arbitrary `monthStart`; the household summary card calls it once
  for the selected month and again for `AppTime.monthAfter(monthStart, -1)`
  and computes the % change client-side. One query, reused, instead of a
  second near-duplicate DAO method.

### Tapping a member on the Dashboard filters the Expense List via a keepAlive controller, not route `extra`
- Every other cross-screen data handoff in this app so far (duplicate-expense,
  expense id) passes through `GoRouterState.extra` on a `context.push()` into
  a modal route with its own navigator. The Expense List tab is different:
  it's a `StatefulShellBranch` leaf inside the bottom-nav `IndexedStack`, so
  reaching it from the Dashboard tab means switching branches, not pushing a
  new route — and go_router's shell branches don't thread `extra` the same
  way a plain `GoRoute` push does.
- Solved with `ExpenseListPresetFilterController` (`features/expenses/
  controllers/`, Riverpod `Notifier`, `keepAlive`): the Dashboard's member-bar
  `onTap` sets it to an `ExpenseFilter` (current month + that member) and
  calls `context.go(AppRoutes.expenses)`; `ExpenseListScreen.initState` reads
  it once, applies it as the screen's starting filter, and immediately clears
  it — so it never re-applies on a later, unrelated visit to the Expenses tab.
  `keepAlive` matters here specifically because the value is set from outside
  the Expense List's own widget subtree and must still be there once that
  screen mounts a moment later.

### Cards 2 (budget progress) and 6 (pending recurring) intentionally not stubbed
- T-6.3 explicitly scopes Phase 6 to "Dashboard cards 1, 3, 4, 5" — budget
  progress needs Phase 8's `BudgetRepository` and pending-recurring needs
  Phase 9's recurring-rule posting logic, neither of which exist yet. Rather
  than add empty/placeholder card widgets for them now, they're simply
  absent from `DashboardScreen` until their own phase lands with real data
  to show — an empty card that can never have content in the meantime would
  just be dead UI to delete later.

### Bug found & fixed — `widget_test.dart`'s "signed-in boots to dashboard" test started hanging
- Found once `DashboardScreen` stopped being a `PlaceholderScreen` and began
  issuing live Drift stream queries (`ReportRepository`, `categoriesProvider`,
  `householdProfilesProvider`) as soon as it mounts. The existing test never
  overrode `appDatabaseProvider`, so it exercised the real, path-provider-
  backed `AppDatabase()` — whose `NativeDatabase.createInBackground()` spins
  up a background isolate — inside a `flutter_test` widget test, which runs
  test bodies under `fake_async`. Two separate failures resulted:
  1. **"A Timer is still pending even after the widget tree was disposed"**:
     when the `ProviderScope`/widget tree is torn down at test end, disposing
     each active `StreamProvider` cancels its underlying Drift stream, which
     schedules a zero-duration debounce `Timer`
     (`StreamQueryStore.markAsClosed`) to actually close it. `pumpAndSettle()`
     flushes animation frames and microtasks, not a bare `Timer`, so the
     framework's end-of-test invariant check tripped on it.
  2. With the real isolate-backed database also in play, the same test then
     hung for the full 10-minute `flutter test` timeout rather than failing
     fast — the background isolate's own keepalive outlived `fake_async`'s
     clock entirely.
- Fixed two ways in `test/widget_test.dart`: (1) both tests now override
  `appDatabaseProvider` with `AppDatabase.forTesting(NativeDatabase.memory())`
  — no path-provider, no background isolate; (2) a shared `_disposeAndFlush`
  helper (`pumpWidget(const SizedBox())` to force the tree to unmount, then
  one more `pump(Duration(milliseconds: 1))`) runs at the end of each test to
  let drift's pending debounce timer actually fire before the framework's
  invariant check runs. Worth remembering for any future widget test that
  pumps `KharchaApp`/`ProviderScope` while a screen holds live Drift streams.

### Live verification (Gate 6)
- Ran live on the `kharcha_test` emulator via
  `fvm flutter run --dart-define-from-file=config/dev.json`, screenshot
  captured with `adb exec-out screencap`. Against the real household's
  existing seed data (one ₹50.00 expense, category "zomato", logged by
  Vineet, no income rows), the Dashboard rendered: "This month" card —
  Spent ₹50.00 / Income ₹0.00 / Net saved -₹50.00 (red, no month-over-month
  row since there's no prior-month data to compare against — the T-6.5
  guard, not a bug); "Per member" — Vineet, ₹50.00, 100%, full-width bar;
  "Top categories" — zomato, 100%, ₹50.00, with its category icon/colour;
  "Recent activity" — the single expense with the payer's name and amount.
  All four figures reconcile with what the Expense List shows for the same
  month, satisfying Gate 6's literal acceptance bar even at this small a
  dataset, and no `NaN`/`Infinity`/divide-by-zero artifacts appeared
  anywhere on screen.

## 2026-09-04 — Phase 7 (Income)

### `IncomeRepository` deliberately drops three ExpenseRepository features
- Spec §11.6 says income is "same shape as expenses" for its *fields*
  (amount, category, date, source, note, member), not for every behaviour
  `ExpenseRepository` has. Three things were intentionally not carried over,
  each because nothing in the spec calls for it on income and adding it
  would be unrequested scope (§0 rule 4):
  - **No duplicate guard.** §11.2's 2-minute same-amount/category check is
    an expense-specific UX affordance; §11.6 doesn't mention one for income.
  - **No Undo snackbar / `undoCreate()`.** Same reasoning — §11.2's 5s Undo
    window is never mentioned for income.
  - **No payment method.** The `incomes` table has no `payment_method_id`
    column (§6.3) — there's nothing to pick.
- Everything else mirrors `ExpenseRepository` exactly: local-first Drift
  read, every write → Drift + outbox (§9.1's iron rule), `receivedOn`
  derived from `receivedAt` via `AppTime.calendarDate` (same reasoning as
  `spentOn`, so the client and the server's `set_ist_date()` trigger never
  disagree).

### Same ownership rule as expenses for editing (T-7.2)
- `0006_rls.sql`'s `inc_update`/`inc_delete` policies are byte-for-byte the
  same shape as `exp_update`/`exp_delete` ("owner or admin") — confirmed by
  reading the migration before building the screen. `IncomeDetailScreen`
  therefore reuses T-5.9's pattern exactly: a non-owner, non-admin viewer
  gets `_ReadOnlyIncomeView` instead of the form, rather than relying on RLS
  alone to reject the write after the fact.

### Income List has no filter sheet, search, or infinite scroll
- The Expense List's filter sheet/free-text search/growing-limit pagination
  (T-5.7/T-5.8) exist because a household can accumulate thousands of
  expenses (§13's 5,000-row smoke test). Income entries are structurally
  far rarer — salary, interest, the occasional rent receipt — so a single
  unbounded `IncomeDao.watchAll` stream is simplest and sufficient. Spec
  §11.6 only asks for "a separate list at `/income`", not filtering.
  Revisit if a household's real usage proves this wrong.

### Bug found & fixed — category delete guard never checked income usage
- `CategoryRepository.delete()` (T-5.1) has always summed only
  `expenseDao.countByCategory(id)` before allowing a soft-delete. Categories
  can be `kind='income'` (5 are seeded — Salary, Business, etc.), but until
  this phase nothing ever created an income row, so the gap was
  unreachable. Phase 7 makes it reachable: deleting an in-use income
  category would have succeeded silently, leaving that income's
  `category_id` pointing at a soft-deleted category (not a hard constraint
  violation server-side, since `category_id` is `on delete set null` only
  for a *hard* delete — but the app never hard-deletes from this path, so
  the row would just permanently reference an archived-looking category
  with no "Archive instead" recovery offered).
- Fixed by adding `IncomeDao.countByCategory` (mirroring
  `ExpenseDao.countByCategory`) and summing both counts in
  `CategoryRepository.delete()`. Covered by a new test in
  `category_repository_test.dart` mirroring the existing expense-usage
  guard test.

### Dashboard's Income row navigation
- `_SummaryRow` gained an optional `onTap`, used only by the Income row
  (`context.push(AppRoutes.income)`) — satisfies spec §11.6's "reachable
  ... from the Dashboard's income figure" literally, without touching the
  Spent/Net saved rows which have no equivalent destination.

### `AppConstants.maxExpenseAmountPaise` renamed to `maxTransactionAmountPaise`
- The ₹10,00,00,000 sanity cap (spec §11.2) isn't expense-specific — it's a
  client-side sanity bound reused as-is for income amounts too (the DB only
  enforces `amount_paise > 0` server-side for both tables, per
  `0003_transactions.sql`). Renamed for accuracy rather than referencing an
  expense-named constant from the income form; the one call site in
  `expense_detail_screen.dart` was updated alongside it.

### Live verification (Gate 7)
- Ran live on the `kharcha_test` emulator via
  `fvm flutter run --dart-define-from-file=config/dev.json`. Automated
  `adb shell input tap` **did** reach this emulator this session (contrast
  with Phase 3's DECISIONS.md note that it didn't) — every tap in this
  pass's walkthrough (Dashboard → Income row → FAB → category chip →
  amount/source fields → Save → back to Dashboard) worked once coordinates
  were computed correctly from the screenshot's *original* pixel dimensions
  (1080×2400), not the tool's downscaled display dimensions (900×2000) —
  an early tap on the FAB at the wrong (unscaled) coordinates silently
  missed; `uiautomator dump`'s exact widget `bounds` was used to recover
  once relying on scaled screenshot coordinates got a Save-button tap
  wrong. Confirmed the on-device `kharcha.sqlite` lives at
  `app_flutter/kharcha.sqlite` under the app's data dir, not
  `databases/kharcha.sqlite` (unlike some other Flutter/Drift app layouts) —
  `adb exec-out run-as com.panicker.kharcha cat app_flutter/kharcha.sqlite`
  is the correct pull command for this app.

## 2026-09-05 — Phase 8 (Budgets & alerts)

### Notification init brought forward from Phase 13 (T-8.5)
- Spec §11.12 (notifications) is Phase 13's phase, but T-8.5 explicitly
  requires firing a real local notification on a budget threshold crossing.
  Rather than half-build notification support inside Phase 8 and redo it in
  Phase 13, `core/notifications/notification_service.dart` is the real,
  final `flutter_local_notifications` wrapper (`init()` + `show()`) that
  Phase 13 will reuse as-is, just adding scheduled notifications
  (`.zonedSchedule()`) on top. `NotificationService.instance.init()` is
  called once from `main()`'s bootstrap (`await`ed, before `runApp`), and
  `android/app/src/main/AndroidManifest.xml` gained the Android 13+
  `POST_NOTIFICATIONS` permission.
- `flutter_local_notifications` 22.3.0's `initialize()`/`show()` now take
  everything as named parameters (`settings:`, `notificationDetails:`) —
  the positional-args signature shown in most still-circulating tutorials
  is stale for this pinned version.

### Member-facing scope choices mirror `bud_write`'s RLS shape (T-8.1/T-8.2)
- `0006_rls.sql`'s `bud_write` policy: `is_admin() OR user_id = auth.uid()`.
  Since `scope = household` and `scope = category` always have `user_id
  IS NULL` (per the `budgets_scope_shape` constraint), a non-admin member
  can never legally write one — RLS would reject it every time. Rather than
  let a member fill out the whole form and then fail server-side,
  `BudgetDetailScreen._allowedScopes` only shows Household/Category as
  choices when `_isAdmin`; a member sees User/User+Category only, with
  `_userId` pre-forced to their own id and not editable. `create()`/
  `update()` still separately check `isValidBudgetScopeShape()` (T-8.1) —
  that guards the shape constraint, not the RLS ownership rule, which stays
  server-enforced only (consistent with every other repository in this app:
  "RLS is the real enforcement, screens just hide the controls").

### `copyToNext12Months` skips instead of erroring on an existing month
- Spec T-8.2 says "creates exactly 12 rows," which assumes a clean 12-month
  run. `BudgetRepository.copyToNext12Months()` looks up each target month
  via `findByScope` first and skips it if a budget with that exact scope
  shape already exists there, rather than letting the DB's
  `budgets_unique_scope` index reject it as a hard failure partway through
  the loop. Simplest option that can't leave the operation half-applied
  with a swallowed error.

### Budget status/rollover is nested `StreamBuilder`s, not a Riverpod combinator
- Computing a budget's live status needs to combine two things: a live
  scoped-spend stream (spec: "evaluated after every expense save") and the
  previous month's budget+spend (only for rollover). Rather than building a
  Riverpod provider that watches N other providers to fan this out,
  `BudgetRepository.watchStatus()` is a plain method returning
  `Stream<BudgetStatus>` (spend stream `.asyncMap`'d with a one-shot
  rollover lookup), consumed via a `StreamBuilder` per row — exactly the
  nested-`StreamBuilder` pattern `dashboard_screen.dart`'s cards already
  use (T-6.3's `_HouseholdSummaryCard`). Keeps this feature consistent with
  the rest of the app's Dashboard-adjacent code rather than introducing a
  second combining idiom.
- The Budget List screen's ok/warning/exceeded summary header needs the
  computed health of every row, but each row's `BudgetStatus` only exists
  inside that row's own `StreamBuilder`. Rather than a second live
  subscription per row just to feed a header count, each `_BudgetRow`
  reports its health up via a plain callback (`onHealth`), and the parent
  `State` aggregates it in a `Map<String, BudgetHealth>`, deferred one
  frame via `WidgetsBinding.instance.addPostFrameCallback` to avoid a
  `setState`-during-build error. **Bug found & fixed during live
  verification**: this map was never pruned when a budget left the current
  month's list (deleted, or the month changed), so a deleted budget's last
  health kept inflating the summary counts forever. Fixed by computing the
  displayed counts only over budgets still present in the current
  `budgets` list (`currentHealths` in `budget_list_screen.dart`), rather
  than over every id the map has ever seen.

### Bug found & fixed — `DateTime.parse` on a bare Postgres `date` column corrupts the instant by the device's UTC offset
- **This is the third occurrence of the IST-offset family of bugs first
  documented in Phase 4** ("Drift `DateTime` columns decode as
  local-flagged, not UTC") and Phase 5 ("mapper `toDomain()` never applied
  the Phase 4 `.toUtc()` fix") — same root cause category (a UTC/local
  timezone boundary silently applied where it shouldn't be), a different
  code path each time, and — like both predecessors — invisible to every
  previous gate's live verification until a query pattern came along that
  actually exposed it.
- **Symptom**: created a household budget for "September 2026" live on the
  `kharcha_test` emulator (physically running with IST as its timezone,
  per spec §3 — every real Kharcha device). `BudgetListScreen`'s exact
  `t.periodMonth.equals(periodMonth)` query against a freshly computed
  `AppTime.monthStart(DateTime.now().toUtc())` (verified correct via a
  temporary debug `print`: `2026-09-01T00:00:00.000Z`, `isUtc: true`)
  returned nothing — the just-created budget had vanished from the list
  entirely, in both September *and* August.
- **Root cause**: `period_month` (and `spent_on`, `received_on`,
  `start_date`, `end_date`, `next_due_date`, `last_posted_on` — every
  calendar-date-only column in the schema, §6.2–§6.5) is Postgres type
  `date`, not `timestamptz`. PostgREST serialises a `date` column as a bare
  `"2026-09-01"` — no time-of-day, no `Z`/offset suffix. Every affected
  domain model's `fromJson` (json_serializable's default codegen for a
  `DateTime` field) calls plain `DateTime.parse(value)` on that string.
  Dart's `DateTime.parse` on a string **with no offset returns a
  local-flagged DateTime** — on a device physically in IST, parsing
  `"2026-09-01"` yields the instant `2026-08-31T18:30:00Z` once
  `millisecondsSinceEpoch` is taken (as Drift does for storage), a full
  5:30 away from the intended `2026-09-01T00:00:00Z` UTC-midnight marker
  this app's every other calendar-date value uses by convention. The
  budget's `period_month`, having round-tripped through a pull from
  Supabase (remote-wins, since the row was clean/non-dirty), got corrupted
  this way; the fresh in-memory query value never round-trips through JSON
  so it stayed correct — hence the exact-equality mismatch.
- Confirmed via a temporary debug `print` at both the query site
  (`BudgetDao.watchForMonth`) and the write site (`BudgetRepository._save`)
  that both the query and a **freshly created** budget's `periodMonth` were
  byte-for-byte correct (`ms=1788220800000`) — the corruption only appears
  after a value has round-tripped through `fromJson` from a real pull.
  Raw `sqlite3` reads of the on-device file (`adb shell run-as
  com.panicker.kharcha sqlite3 app_flutter/kharcha.sqlite`) confirmed the
  stored integer, not just the decoded Dart flag, is what's wrong here —
  a stronger and different symptom than Phase 4's bug, where the decoded
  *instant* was always correct and only the `isUtc` flag was wrong.
- Also explains, in hindsight, why the pre-existing `spent_on` for an
  expense created in an earlier phase read back as `2026-09-03T18:30:00Z`
  instead of a clean UTC midnight when dumped raw off the device — the
  exact same corruption, silently present since Phase 4/5, just never
  caught because `spentOn`/`receivedOn` are only ever used in **range**
  filters (`>=`/`<`) for a whole month at a time; shifting every row's
  bound by the same 5:30 in the same direction rarely changes which side
  of a boundary a row falls on, unless the true date is the 1st of the
  month (untested by any prior gate's fixture data). Budgets' **exact
  month-equality** lookup has no such tolerance, which is what surfaced it.
- **Fix**: `AppTime.parseDateOnly(String)` / `parseDateOnlyOrNull(String?)`
  (`core/time/app_time.dart`) parse the string, then reconstruct
  `DateTime.utc(parsed.year, parsed.month, parsed.day)` — discarding
  whatever timezone `DateTime.parse` guessed, keeping only the calendar
  digits. Applied via `@JsonKey(fromJson: AppTime.parseDateOnly)` (or the
  nullable sibling) on: `Expense.spentOn`, `Income.receivedOn`,
  `Budget.periodMonth`, `RecurringRule.startDate`/`endDate`/`nextDueDate`/
  `lastPostedOn` — every `DateTime` field backed by a `date` column in the
  schema. `toJson` was left untouched: a `DateTime.utc(y,m,d)` value's
  default `.toIso8601String()` already round-trips correctly through
  Postgres's cast from a full timestamptz string to `date` (confirmed by
  the *absence* of any corruption on the write side throughout this
  investigation).
- Self-healed automatically for already-synced rows: the next pull
  re-applies `fromJson` with the fix and overwrites the locally-corrupted
  value (remote wins, since these rows were never `is_dirty`) — no manual
  data migration was needed once the parser was fixed; verified live by
  restarting the app and re-reading the previously-corrupted budget row's
  `period_month` off the device, now correct.
- `test/unit/domain/model_json_roundtrip_test.dart`'s existing Expense/
  Income/RecurringRule fixtures reused one `now` timestamp (with a
  non-midnight time-of-day) for *both* the real-instant fields
  (`spentAt`/`receivedAt`) and the date-only fields (`spentOn`/`receivedOn`/
  `startDate`/`nextDueDate`) — tolerated before only because the old naive
  `DateTime.parse` preserved whatever time-of-day it was given. Split into
  `now` (instants) and a separate `midnight` (date-only fields) so the
  fixtures reflect this app's actual convention instead of accidentally
  depending on the bug being fixed.
