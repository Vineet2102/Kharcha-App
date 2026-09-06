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

## 2026-09-05 — Phase 9 (Recurring)

### The SQL `advance_due_date()`'s dead `p_weekday` parameter isn't mirrored

Spec §6.6's SQL function accepts `p_weekday` alongside `p_dom`, but no
branch of the function — daily/weekly/monthly/yearly — actually reads it;
weekly recurrence just steps by whole weeks from the anchor date, which
already preserves the weekday on its own. `domain/models/recurring_schedule.dart`'s
`advanceDueDate` mirrors every branch's real behaviour but drops this
parameter rather than carrying a genuinely-dead one into Dart. Recorded here
in case a future spec revision gives `weekday` real meaning (e.g. "every
Tuesday" independent of the anchor date) — that would need a new branch in
both the SQL and this Dart mirror, not just wiring the existing parameter
through.

### Yearly recurrence deliberately left unclamped, same as the SQL

The monthly branch explicitly clamps the target day to the last valid day
of the target month (spec's own `least(...)` — the 31st → 28th/29th in
February). The yearly branch has no equivalent clamp in the SQL, and
`advanceDueDate` doesn't add one either: a rule anchored on 29 Feb of a leap
year rolls over to 1 Mar in a non-leap target year. Verified this is safe to
leave unclamped rather than a latent bug worth "fixing" beyond the spec:
Postgres's `date + interval 'N years'` and Dart's `DateTime.utc(y, m, d)`
both overflow a nonexistent Feb 29 into March 1 the same way (field-by-field
construction with day-overflow, not a lookup-and-clamp) — the two stay in
agreement without any extra code. Covered by a unit test
(`recurring_schedule_test.dart`) precisely so a future refactor that adds
"helpful" clamping here doesn't silently start disagreeing with the server.

### The posting engine splits into three tiers, not one loop (T-9.3/T-9.5)

Spec §11.8's pseudocode reads as a single loop ("advance next_due_date;
repeat until it is in the future") regardless of `auto_post`. Read
literally, a `false`-auto_post rule with several overdue occurrences would
auto-advance past all but the last one in the background — but T-9.5's own
acceptance criterion ("Skip advances next_due_date without creating a
transaction") only makes sense as a *user-driven*, one-occurrence-at-a-time
action. `RecurringPostingEngine` resolves this by treating the pseudocode's
loop as describing the *auto-post* path literally (batch-catches-up,
capped at 24 per run, entirely inside `sync()`), and treating the
non-auto-post path as: leave `next_due_date` frozen at the earliest
still-askable occurrence (so it keeps showing as "pending" via
`RecurringDao.dueOn`, unchanged run after run) until `postOneOccurrence`/
`skipOneOccurrence` — both single-step, called only from the Dashboard's
Post/Skip buttons (`RecurringRepository.postPending`/`skipPending`) —
advance it by exactly one. The "pending confirmations expire after 30
days" rule (spec §11.8's last bullet) is the one piece of automatic
behaviour that *does* apply to the manual path: occurrences older than 30
days are silently skipped (advanced past, no transaction, no dashboard
entry) inside the same sync-time pass, capped at the same 24-per-run to
bound a rule dormant for years.

### Local idempotency check is separate from the cross-device duplicate guard (T-9.4)

Two different races are handled two different ways. Within *this* device:
`RecurringPostingEngine._createOccurrence` checks
`ExpenseDao.findByOccurrence`/`IncomeDao.findByOccurrence` before creating a
row, guarding against the app being killed after creating an occurrence but
before persisting the rule's advanced `next_due_date` — on the next launch,
the same `next_due_date` would otherwise regenerate the occurrence with a
fresh random id. Across *devices*: two phones can each pass this local
check (neither has the other's row yet) and both enqueue a create; only one
insert can win the server's `expenses_recurrence_unique`/
`incomes_recurrence_unique` index. `OutboxProcessor._handleRecurrenceDuplicate`
catches the loser's `23505` on push (identified by the payload carrying a
non-null `recurring_rule_id`, not by parsing the constraint name out of the
error message — robust to the constraint being renamed) and discards the
local phantom row outright rather than retrying or parking it as
`'failed'`; the winner's row arrives normally on the next pull. Running the
posting engine right after the pull (not before) in `SyncEngine.sync()`
narrows this race further — an occurrence another device already posted is
usually already visible locally before this device decides whether to post
its own — but doesn't eliminate it, which is why the outbox-level guard
still exists as the actual correctness backstop.

### A posted occurrence's `merchant`/`source` carries the rule's title

`recurring_rules` has `title` but `expenses`/`incomes` have no equivalent
field — only `note`/`merchant` and `note`/`source` respectively. Posting an
occurrence with `note: rule.note, merchant: ''` would silently lose the
rule's identity whenever its own `note` was left blank (Expense List and
Recent Activity both fall back to the category name when `note` is empty,
never merchant) — a "Netflix" auto-post would just show as "Subscriptions".
Fixed by mapping `rule.title` onto the expense's `merchant`
(and the income's `source`), and falling back to it for `note` too when the
rule's own note is empty, so a posted occurrence is never a bare,
unlabelled amount.

### A monthly rule always stores an explicit `day_of_month`, never leaves it null

`advanceDueDate`'s monthly branch falls back to `from.day` when
`dayOfMonth` is `null` — but `from` is *the previous occurrence's own
(possibly already-clamped) date*, not the rule's original anchor day. A
rule created on the 31st with `dayOfMonth` left null would step 31 → 28
(clamped, Feb) → 28 (Mar, now reading `from.day = 28` instead of the
original 31) and stay stuck at the 28th forever, even in months that do
have a 31st. `RecurringDetailScreen._save` always resolves
`dayOfMonth ?? startDate.day` before calling `create`/`update`, so
`day_of_month` is only ever left unset by direct API/SQL access, never by
the app's own editor.

### Bug found & fixed — Auto-post switch's subtitle never reflected the toggle

`RecurringDetailScreen`'s `SwitchListTile` for `auto_post` was given a
`const Text(...)` subtitle hardcoded to the "Off" copy, so toggling it on
during live verification left the helper text reading "Off: each
occurrence waits on the Dashboard..." even with the switch itself visibly
on. Fixed by switching the subtitle to a non-const `Text` keyed off
`_autoPost`, mirroring the copy the Recurring List already computes
correctly per-rule from the persisted value.

### Live verification (Gate 9)

`fvm flutter analyze --fatal-infos` clean; `fvm flutter test` green at 176
tests (28 new: `recurring_schedule_test.dart`'s pure-function coverage of
`advanceDueDate`/`dueOccurrencesFor`/`previewOccurrences` incl. the 31
Jan → 28/29 Feb and 24-occurrence-cap cases from T-9.1/T-9.3;
`recurring_posting_engine_test.dart`'s in-memory-Drift coverage of
auto-post catch-up, the 30-day pending-expiry sweep, end-date
deactivation, and `postOneOccurrence`/`skipOneOccurrence`;
`recurring_repository_test.dart`; 3 new `outbox_processor_test.dart` cases
for T-9.4). Live-verified on the `kharcha_test` emulator against the real
Supabase project: created an auto-post "Netflix" ₹499/month rule (day 5,
today) — the Dashboard's next sync cycle posted it automatically with the
correct category/merchant, and the rule's `next_due_date` advanced from
5 Sep to 5 Oct. Created a second, manual "Rent" ₹15,000/month rule — the
Dashboard's "Pending confirmations" card (card 6) appeared with Skip/Post
buttons; tapping Post created the expense and advanced `next_due_date`,
and the card disappeared once nothing was left pending. Both rules and
their posted expenses were deleted afterward to restore the shared
household data to its pre-test state. Not independently re-verified on a
second physical/emulated device — T-9.4's cross-device race is instead
covered by the `outbox_processor_test.dart` cases that script "device A's
push succeeds, device B's conflicting push is discarded" against the same
local outbox, following the same precedent as Gate 4's two-device scenario.

## 2026-09-05 — Gate 4 two-device live re-verification

### Bug found, not yet fixed — reconciliation is last-device-to-push-wins, not newest-edit-wins

Gate 4's originally-deferred scenario — two real devices editing the same
expense offline, then reconciling online — was run live for the first
time (Phase 5+ now provides the real write UI it needed). Two emulators:
`kharcha_test` as Vineet (admin), a newly created `kharcha_test_2` as
Rupesh (member), both taken fully offline (`svc wifi disable` +
`svc data disable`, confirmed via `dumpsys connectivity`) and both editing
the same shared expense. Vineet edited first (T1); ~75s later, still
offline, Rupesh edited the same row again (T2, chronologically newer).
Rupesh's device was brought online first and pushed cleanly. Vineet's
device was brought online next and pushed *its* still-dirty, older T1
edit — which silently overwrote Rupesh's newer T2 edit on the server.
Rupesh's device then received Vineet's older edit back via its realtime
pull, replacing his own newer edit locally with no warning.

Both devices converged to an identical, non-corrupted state — no crash,
no duplicate rows, no permanent fork — so the specific concern Gate 4 had
flagged as unverified (does reconciliation actually converge?) is
resolved. But the resolution mechanism is **last-device-to-push-wins**,
not **newest-edit-wins**: `TableRemoteDataSource.upsert()`
(`table_remote_data_source.dart`) is an unconditional
`.upsert(payload, onConflict: 'id')` with no check against the row's
current server state, so whichever device happens to push second always
overwrites, regardless of which edit is actually newer. Confirmed via
`adb logcat` on both devices that `_logConflictLoss`
(`entity_sync_adapters.dart`) never fired — it only warns when the
*receiving* device's own local copy is still dirty at pull time, and
Rupesh's device was already clean (its own push had already succeeded)
when the older edit arrived, so the overwrite looked like an ordinary
sync, not a conflict.

This means spec §13 Test 5 ("resolves ... without data loss on the losing
side ... the losing version is logged") holds only for the narrower race
`entity_sync_adapters_test.dart`/T-4.6 already covers deterministically —
a device that is *still dirty* when it pulls a newer remote row — not for
this literal two-independent-device case, where the losing edit can
vanish silently with no log entry and no user-visible indication. **Not
yet fixed.** Closing the gap would need `pushUpsert` to carry an
optimistic-concurrency check (e.g., a conditional update keyed on the
row's current `updated_at`, or a Postgres trigger/RPC that rejects a push
older than the row it would overwrite) so a genuine cross-device conflict
is detected and logged regardless of push order, rather than only when
the receiving device happens to still be dirty.

Test data (the shared expense and both edits) was deleted afterward on
both devices and in Supabase; the household's real data was left
unchanged.

## 2026-09-05 — Gate 4 fix: compare-and-swap on push

Closed the gap above: `pushUpsert` no longer does a plain unconditional
`.upsert()`. Every push-capable table (`categories`, `payment_methods`,
`expenses`, `incomes`, `budgets`, `recurring_rules`, `attachments`) gained
a `base_updated_at` column (schema v2 → v3) — the row's `updated_at` as of
the last time *this device* confirmed it matched the server (a pull, or
this device's own successful push). It is deliberately a separate column
from `updated_at`/`local_updated_at`: once a local edit overwrites
`updated_at` with the new value, the pre-edit "confirmed" value would
otherwise be lost, and that's exactly the value a compare-and-swap needs
to check against.

`TableRemoteDataSource.upsertIfBaseMatches()` does the actual CAS: if
`base` is null (a locally-created row with no server counterpart yet) it's
a plain upsert; otherwise it's `.update(payload).eq('id', id).eq('updated_at',
base)` — a single atomic UPDATE that only touches the row if the server's
`updated_at` still equals what this device last confirmed. No Postgres
migration was needed — `updated_at` already exists server-side; this is
client-side filtering only.

On a CAS mismatch (someone else moved the row), `EntitySyncAdapter`'s new
`_pushUpsertWithCas()` helper (`entity_sync_adapters.dart`) fetches the
current server row and resolves it exactly like a pull-time D12 conflict —
by comparing timestamps, not by who pushed first:
- **the local edit is genuinely newer** (dirty and `local_updated_at` is
  after the server's `updated_at`) → `base_updated_at` is refreshed to the
  server's current value and a `SyncConflictRetryException` is thrown.
  `ErrorMapper` classifies this as transient (falls through to
  `UnknownFailure`), so `OutboxProcessor`'s existing exponential backoff
  retries it — by then the base is correct, so the retry's CAS succeeds
  against whatever is actually on the server;
- **otherwise the remote row wins** — applied locally by calling the
  adapter's own `pullApply()` (the exact same overwrite-and-log-the-loss
  path a routine pull uses), and the outbox entry is dropped: there is
  nothing left to push once the local edit has been discarded.

Concretely, replaying the Vineet/Rupesh scenario above with this fix:
Rupesh's push (base = T0) succeeds first, server moves to T2. Vineet's
push (base = T0, now stale) gets a CAS mismatch; the fetched server row
(T2, Rupesh's edit) is compared against Vineet's `local_updated_at` (T1) —
T2 is newer, so Vineet's device discards its own edit, logs the loss via
`AppLogger`, and adopts Rupesh's T2 edit. If the timing were reversed
(Vineet's T1 edit pushes second but is *not* actually newer than what's on
the server), the outcome is now determined by timestamp comparison either
way — never by which device happened to push last.

`pushUpsert`'s abstract signature gained an `AppDatabase db` parameter (it
now needs to read/write the local row during conflict resolution) and, for
the `upsert` op only, fully owns the local row's post-push state — success
stamps it via a new `markSyncedWithBase(id, base)` DAO method (like
`markSynced` but also updates `base_updated_at`); a conflict resolved in
the remote's favour goes through `pullApply` instead. `OutboxProcessor`
was restructured so only the `upsert` case skips the old blanket
`adapter.markLocalSynced()` call afterward — `delete`/`upload` still use
it unchanged.

**Schema migration (v2 → v3)**: existing devices already have a real local
database with no `base_updated_at` column. The migration adds it to all 7
tables and backfills `base_updated_at = updated_at` for every row that is
*not* currently dirty — a clean row's `updated_at` already equals the
server's by definition, so this is exact, not a guess. A row that happens
to be mid-edit (dirty) at the moment of the upgrade is left with
`base_updated_at = null`, which falls back to a plain unconditional
upsert for that one specific in-flight edit — the same behaviour as
before the fix, but only for that single edit; it self-heals the moment
that edit's push succeeds and stamps a real base. Verified against a
hand-built v2 sqlite file (not `AppDatabase.forTesting`, which always
starts fresh at the latest schema) in
`test/unit/db/migration_v2_to_v3_test.dart`.

**Not re-verified live this session** (no emulator available in this
environment) — Gate 4 stays at **partial** in PROGRESS.md until the exact
two-device scenario from 2026-09-05 is re-run live and confirmed to now
converge on Rupesh's (newer) edit with a logged conflict on Vineet's
device, rather than the reverse.

## 2026-09-05 — Phase 10 (Receipts)

### Receipt capture is edit-only, not offered on a brand-new unsaved expense

Spec §11.2's field table lists Receipt as a field of the Add/Edit Expense
form, which could be read as "attachable before the first Save." That
would require generating the expense's id client-side before it exists in
Drift, so an attachment (and its outbox `upload` job, referencing
`expense_id`) could be created first. The risk: if the user backs out of
the Add form after taking a photo but before hitting Save, the attachment
row and its already-enqueued outbox entry would reference an expense that
was never created, and would push straight into a Postgres FK violation
(`attachments.expense_id references expenses(id)`) — a permanently stuck
outbox entry with no clean recovery path.

Chose the simpler, safer option (spec item 4: simplest option satisfying
acceptance criteria): the Receipts section only renders when
`widget.id != null` (`ExpenseDetailScreen`, `expense_detail_screen.dart`) —
i.e. once the expense has actually been saved. Attaching a receipt to a
just-created expense means reopening it from the Expense List, one extra
tap. None of Phase 10's acceptance criteria (T-10.1–T-10.5, Gate 10)
require pre-save capture.

### Image compression is injected, not called directly

`AttachmentRepository` takes an `ImageCompressor` typedef (defaults to
`FlutterImageCompress.compressWithFile`) rather than calling the plugin
statically, purely so `attachment_repository_test.dart` can run under
plain `flutter_test` (no platform channel) with a pass-through fake. Same
reasoning as the existing `path_provider_platform_interface` fake used in
`migration_v2_to_v3_test.dart` — reused here for the same purpose (faking
`getApplicationDocumentsDirectory()`).

`minWidth`/`minHeight` are both set to 1600 to approximate spec §11.9's
"longest edge ≤ 1600px" — `flutter_image_compress`'s actual resize
algorithm scales to the given bounds while preserving aspect ratio; it
doesn't expose a literal "cap the longest edge" parameter. This is the
standard usage pattern for this plugin across the ecosystem. T-10.1's
"4 MB photo → <400 KB" acceptance is verified live on-device (Gate 10),
not by a unit test — there's no real multi-MB JPEG fixture in the repo,
and faking one wouldn't exercise the actual compressor anyway (the unit
tests substitute it out).

### `has_receipt` is maintained via `ExpenseRepository.setHasReceipt`, not owned by `AttachmentRepository`

`expenses.has_receipt` is a plain, non-generated column (§6.4) — nothing
server-side keeps it in sync with the `attachments` table, and the Expense
List's "only with receipts" filter (T-5.8) queries it directly rather than
joining attachments. `AttachmentRepository` doesn't touch the `expenses`
table itself; it calls `ExpenseRepository.setHasReceipt(expenseId, value)`,
which loads the current row and re-saves it through the existing
`update()` path (bumping `updated_at`, re-enqueuing the full row). This is
the same "reach into the DAO/repository you need directly" pattern
`CategoryRepository.delete()`'s usage guard already established, rather
than introducing a two-way dependency between the two repositories.

Consequence worth naming: attaching or removing a receipt bumps the
expense's `updated_at`, which is one more thing that can race a concurrent
edit under D12's last-write-wins. Accepted as no worse than any other
field edit in this app.

### Attachment deletion cascade lives in `ExpenseRepository`, not `AttachmentRepository`

T-10.5 requires deleting an expense to cascade-delete its attachments (no
orphan rows). `ExpenseRepository.delete()` reaches directly into
`_db.attachmentDao`/`_db.outboxDao` to soft-delete every active attachment
and enqueue its removal, rather than depending on `AttachmentRepository`
for this — same precedent as the `has_receipt` decision above and as
`CategoryRepository`'s existing usage-guard.

### Storage object deletion happens inside `OutboxProcessor`, is best-effort, and Diagnostics isn't built yet

Spec §11.9: "Deleting an expense soft-deletes its attachments and enqueues
storage deletions. Orphaned storage objects are cleaned by a manual admin
action in Settings → Diagnostics (v1 does not run a scheduled job)." Read
this as: the outbox `delete` op for an `attachment` entity should attempt
to remove the actual Storage object (not just tombstone the row), with the
Diagnostics sweep existing only as a backstop for whatever that attempt
fails to catch (offline at delete time and the retry chain still fails,
etc).

Implemented in `OutboxProcessor._processEntry`'s `delete` case: for
`entity == 'attachment'`, best-effort `client.storage.from('receipts')
.remove([storagePath])` before the row's `pushSoftDelete` — wrapped in its
own try/catch so a failed storage delete never blocks the row tombstone
from propagating (that's the actually load-bearing part; a lingering
Storage object is just wasted space until cleaned up). The "Diagnostics →
list orphaned objects" admin screen itself is genuinely Phase 14 work
(Settings, admin, diagnostics) and was **not** built now — out of phase
order, and Phase 10's own acceptance criteria don't require it.

Not unit-tested: mocking `SupabaseClient.storage.from(...).remove(...)`
with mocktail requires stubbing a getter chain through `StorageFileApi`,
which adds real fragility for a path that's already wrapped in a
swallow-and-log try/catch (i.e. it cannot break the outbox's actual
job — draining the queue — even if the storage call throws or is
unstubbed). Covered by Gate 10's live verification instead, same
precedent as the recurring-posting engine's notification checks in Gate 8.

### Signed URLs, not `StorageFileApi.download()`

§8's locked client rule is explicit: "Images are fetched with signed URLs
(`createSignedUrl`, 1 hour TTL), never public URLs." `supabase_flutter`
also exposes a `download()` method that fetches authenticated bytes
directly without a literal signed URL — simpler to call, but not what the
spec names. `AttachmentRepository.resolveLocalFile()` follows the spec
literally: `createSignedUrl` then a plain `dart:io HttpClient` GET
(`consolidateHttpClientResponseBytes` from `package:flutter/foundation.dart`
turns the response into bytes) — no new package dependency for something
`dart:io` already covers.

### No iOS Info.plist changes

The `ios/` platform directory was deliberately dropped earlier in the
build (Android-only for now — see the Phase 0/Gate 0 entries). Spec
§16.3's `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` strings
have nowhere to go until iOS work resumes; only `AndroidManifest.xml`
gained the `CAMERA` permission this phase.

### Attachment domain model grew an `isDirty` field

`Attachment` (unlike the other syncable domain models until now) had no
local-only dirty flag — nothing needed it before the expense detail
screen's "upload pending" badge (spec §11.9's last line: "the thumbnail
shows an 'upload pending' badge"). Added the same way `Expense.isDirty`
already works: `@JsonKey(includeToJson: false, includeFromJson: false)`,
populated by `AttachmentRowMapper.toDomain()` from the Drift row's
`is_dirty` column.

## 2026-09-05 — Gate 10 live two-device verification

Ran the actual Gate 10 acceptance test live: two real emulators
(`kharcha_test` = Vineet/admin, `kharcha_test_2` = Rupesh/member) against
the real Supabase project. Device 2 was taken fully offline (`svc wifi
disable` + `svc data disable`, same technique as Gate 3), a new expense was
created and a receipt photo attached entirely offline, then reconnected.
This surfaced three real bugs — two fixed now, one documented but
deliberately not fixed this session (see below) — before the core
acceptance ("capture offline → reconnect → the image is visible on a
second device") was confirmed working end-to-end.

### Bug found & fixed — a push's CAS base was stamped from the client's stale payload, not the server's actual stored value

**Symptom:** created an expense offline, then immediately attached a
receipt (a second, distinct edit to the same row — `AttachmentRepository`
calling `ExpenseRepository.setHasReceipt(true)`). After reconnecting, both
outbox entries for the expense drained without error, but `has_receipt`
came back `false` — the second edit was silently discarded with no
conflict logged anywhere.

**Root cause:** Postgres's `touch_updated_at()` trigger does
`updated_at := GREATEST(now(), incoming)`. After being offline for any
real stretch, the server's `now()` is later than the client's claimed
`updated_at`, so the trigger silently advances it. `_pushUpsertWithCas`
(the Gate 4 CAS mechanism) used to call
`markSynced(_updatedAtOf(payload))` on a successful push — i.e. it trusted
the *payload's own claimed* `updated_at`, not what the server actually
ended up storing. So after the first queued upsert pushed, the client's
recorded `base_updated_at` was already wrong. When the second queued
upsert (the `has_receipt` change) pushed next, its CAS
(`.eq('updated_at', wrongBase)`) mismatched against the real server value.
Because the first push's `markSynced` had already (wrongly) cleared
`is_dirty`, the conflict-resolution code read "not dirty" and concluded
there was nothing local to protect — so it silently adopted the remote
(stale, `has_receipt = false`) row instead of retrying.

**Fix:** `TableRemoteDataSource.upsertIfBaseMatches()` now returns
`Future<DateTime?>` — the row's actual resulting `updated_at` (via a
trailing `.select('updated_at')` on both the unconditional `upsert()` and
the conditional `update()`), or `null` for a genuine CAS mismatch — instead
of `Future<bool>`. `_pushUpsertWithCas` stamps `base_updated_at` from that
real value, never from the payload. `test/unit/sync/push_conflict_resolution_test.dart`
gained a dedicated regression test simulating exactly this: two sequential
`pushUpsert` calls for the same row, where the server-returned value
legitimately differs from what each payload claimed — both edits now
survive.

### Bug found & fixed — `local_updated_at` was never populated on an ordinary edit, silently defeating the Gate 4 conflict fix and crashing the sync loop

While investigating the bug above, found a second, more severe defect: **every** entity mapper's `toCompanion(dirty: true)`
(`expense_mapper.dart`, `income_mapper.dart`, `category_mapper.dart`,
`payment_method_mapper.dart`, `budget_mapper.dart`,
`recurring_rule_mapper.dart`, `attachment_mapper.dart`) left
`local_updated_at` absent from the companion. Since `upsert()` is a plain
`insertOnConflictUpdate`, an absent column is never written — so
`local_updated_at` stayed `null` forever on every entity, for every write,
except a soft-delete (`ExpenseDao.softDelete` etc. are the only call sites
that ever set it).

**Consequence #1 (silent, no crash):** the entire Gate 4 CAS-conflict
mechanism's `localIsNewer` check
(`meta.isDirty && meta.localUpdatedAt != null && meta.localUpdatedAt!.isAfter(remoteUpdatedAt)`)
can never be true if `localUpdatedAt` is always null — a genuinely newer
local edit that loses a CAS race could never be recognised as such, and
would always be silently overwritten by whatever's on the server. The
Gate 4 fix's core promise ("never silently overwritten by push order") was
dead code in production from the moment it shipped, only masked because
its own tests construct `_LocalSyncMeta`/local rows with `localUpdatedAt`
set explicitly by hand.

**Consequence #2 (crash, found live):** `_logConflictLoss` — called from
both `_pushUpsertWithCas` and every entity's `pullApply` — force-unwrapped
`meta!.localUpdatedAt!` / `local!.localUpdatedAt!` to build its log
message. Once a dirty row with a null `localUpdatedAt` actually hit a CAS
mismatch (exactly what consequence #1 permits), this threw a `TypeError`
("Null check operator used on a null value"), caught by
`OutboxProcessor`'s generic handler and misreported to the user as
"Something went wrong. Please try again." — and because the exception was
thrown *before* `applyRemote()` ran, the row never actually resolved: it
retried forever, identically, every cycle. Confirmed via a real
`ws://.../ws` VM-service connection (see below) reading the actual
exception and stack trace off the running app — `AppLogger`'s messages go
through `dart:developer`'s `log()`, which **does not appear in `adb
logcat`** for a plain installed APK; a small standalone `dart:io
WebSocket` script subscribing to the VM service's `Logging`/`Stdout`
streams was the only way to see the real exception instead of
`ErrorMapper`'s deliberately-generic user-facing message.

**Fix (two parts):**
1. Every affected mapper's `toCompanion()` now sets
   `localUpdatedAt: dirty ? Value(DateTime.now().toUtc()) : const Value.absent()`
   — mirroring what `softDelete()` already did. Covered by
   `test/unit/data/mapper_local_updated_at_test.dart` (one test per
   entity).
2. `_logConflictLoss`'s `localUpdatedAt` parameter is now `DateTime?`
   (formats as "unknown time" when absent) instead of force-unwrapping —
   defensive on top of fix #1, since a row dirtied by an already-installed
   build before this fix still has `localUpdatedAt = null` and must not
   crash the sync loop the first time it hits a conflict. Covered by a new
   test in `push_conflict_resolution_test.dart`.

With both fixes, a genuine local-newer-than-remote conflict now correctly
throws `SyncConflictRetryException` (the intended, benign retry path) and
converges on the next attempt — confirmed live via the same VM-service log
tail.

### Bug found & fixed — `base_updated_at`'s round-trip through Drift lost sub-second precision, so a CAS retry could loop forever

While confirming the two fixes above live, one specific expense's
`has_receipt` push kept retrying with `SyncConflictRetryException`
indefinitely — the *intended* retry path (not a crash), but it never
actually converged. Root cause: `base_updated_at` was a Drift
`DateTimeColumn`, stored as a plain integer **seconds**-since-epoch
(`sqlite3 ... "select base_updated_at, typeof(base_updated_at) from
expenses"` → `1788594865|integer`, i.e. whole seconds). Postgres's
`timestamptz` has microsecond precision, and `now()` essentially never
lands on an exact second boundary. So: fetch the server's row →
`DateTime.parse(...)` retains microseconds → store as `base_updated_at` →
**Drift truncated to whole seconds on write** → next CAS attempt sends
`.eq('updated_at', truncated.toIso8601String())` → server's actual stored
value still has its original microseconds → never matches → mismatch →
re-fetch → re-store (still truncated) → repeat forever. This wasn't
specific to receipts or to the other two fixes above — it was a latent
defect in the Gate 4 CAS design itself, and would have affected **any**
entity the moment it needed a second real conflict-resolution cycle (as
opposed to a first, unconditional `expectedBase == null` push, which never
compares anything).

**Fix — a raw string, never a `DateTime`, anywhere in the round trip.**
Rather than just widening the column's precision, the CAS base's type
changed everywhere it flows: `TableRemoteDataSource.upsertIfBaseMatches()`
now takes and returns `String?` — the server's `updated_at` exactly as
Postgres/PostgREST serialised it, read straight off the JSON response
(`list.first['updated_at'] as String`) and never parsed into a `DateTime`
or reformatted. `_LocalSyncMeta.baseUpdatedAt`, every DAO's
`markSyncedWithBase`/`updateBaseUpdatedAt`, and every `toCompanion()`'s
`baseUpdatedAt` parameter all became `String?` to match. Every table's
`baseUpdatedAt` column moved from `DateTimeColumn` to `TextColumn` (schema
v3 → v4). This is stronger than "store more decimal places" — it makes
the value a pure passthrough, so there is no longer any code path that
*could* reformat it and reintroduce drift. (`_updatedAtOf()`'s parsed
`DateTime`, used only for "is local newer than remote" ordering checks
in `_localWins`/`localIsNewer`, is unaffected and unchanged — ordering
comparisons don't need microsecond exactness, only exact-equality CAS
does.)

**Migration (v3 → v4):** SQLite can't change a column's type in place, so
`AppDatabase`'s `onUpgrade` drops and re-adds `base_updated_at` on all 7
syncable tables (`m.dropColumn`, requires sqlite 3.35+, guaranteed here by
bundling `sqlite3_flutter_libs` rather than relying on the OS's sqlite).
Every row's base resets to `null` across the upgrade — deliberately: the
old integer value could never CAS-match the server's full-precision
`updated_at` anyway, so migrating it across would just carry the bug
forward. A `null` base means that row's *next* push is unconditional
(identical to a brand-new row), then self-heals with a precise `TEXT`
base from that push onward. Covered by
`test/unit/db/migration_v3_to_v4_test.dart` (hand-built v3 sqlite file,
same technique as `migration_v2_to_v3_test.dart`), plus a new
sub-second-precision round-trip test and rewrite of the `String?`-typed
fake in `push_conflict_resolution_test.dart`.

**Live-verified the exact scenario that found this bug.** The one test
expense that got stuck (`Groceries`, ₹250, Rupesh) had been retrying
identically for hours across the earlier live-verification session.
Rebuilt the app with this fix, reinstalled over the *same* on-device
database (not a fresh install — the point was proving the migration runs
correctly against real stuck data), and relaunched: `base_updated_at`
confirmed `TEXT NULL` immediately after the v3→v4 migration ran, and after
one sync cycle the outbox drained to empty with the expense finally
landing `has_receipt=1, is_dirty=0, sync_status='synced'`,
`base_updated_at='2026-09-05T13:32:17.259813+00:00'` — a precise,
microsecond-bearing string, proving the whole mechanism end-to-end against
the real Supabase project. (This pass also hit an unrelated environment
issue — the long-suspended emulator's DNS resolution broke, "Failed host
lookup" on Supabase's hostname, confirmed via the same VM-service log
technique below; a bare ICMP ping to `8.8.8.8` still worked, ruling out
general connectivity — a cold restart of the emulator fixed it. Unrelated
to this fix; noted only so a future session recognises the symptom
quickly.)

### Bug found, unrelated, NOT fixed — Dashboard per-member row crashes on tap

Twice during this session, tapping a member's row in the Dashboard's "Per
member" card (spec §6.3's "tap filters the Expense List to that member")
crashed with `Tried to modify a provider while the widget tree was
building.` — a Riverpod state-mutation-during-build error, not a null
crash. This is unrelated to Phase 10/Receipts (nothing this phase touched
the Dashboard or that cross-tab filter handoff) — pre-existing since
Phase 6 (T-6.3). Not investigated further; noted here so it isn't
mistaken for a Gate 10 regression. Worth its own root-cause pass — likely
a `ref.read(...)`/provider write happening synchronously inside a tap
handler that fires during the same frame as a `StatefulShellRoute` branch
switch.

### Debugging technique worth keeping — reading `dart:developer` logs from an installed APK

`AppLogger` (and any `debugPrint`/`FlutterError` output that isn't a raw
crash) does not appear in `adb logcat` for an app launched via `adb install`
+ `am start` — `developer.log()` only reaches a **connected** Dart VM
service client (DevTools, or `flutter attach`), not the Android log
buffer. The APK's own logcat always prints a `Dart VM service is
listening on http://127.0.0.1:<port>/<token>/` line on startup; from
there: `adb forward tcp:<port> tcp:<port>`, then either `flutter attach
-d <device> --debug-uri http://127.0.0.1:<port>/<token>/` (re-mints a
fresh, forwardable URI in its own output), or connect a raw
`dart:io WebSocket` to the `.../ws` endpoint and send `{"method":
"streamListen", "params": {"streamId": "Logging"}}` (JSON-RPC 2.0) to get
every `AppLogger`/uncaught-exception record with its real stack trace,
independent of `ErrorMapper`'s deliberately-generic user-facing message.
This is how every exact root cause in this session's three bugs was
actually found — the sqlite `outbox_entries.last_error` column and the
in-app error banner only ever show the sanitised `Failure.message`.

### Live verification (Gate 10)

`fvm flutter analyze --fatal-infos` clean; `fvm flutter test` green at 198
tests (5 in `attachment_repository_test.dart`, 7 in the new
`mapper_local_updated_at_test.dart`, 1 new sub-second-precision round-trip
case plus the earlier double-push regression case in
`push_conflict_resolution_test.dart` — that whole file's fake rewritten for
the `String?` CAS-base signature — and 1 new
`migration_v3_to_v4_test.dart`). **Live-verified** on two real Android
emulators against the real Supabase project: Rupesh (member), fully
offline (`svc wifi/data disable`, confirmed 0 connected networks), created
a ₹250 "Groceries" expense and attached a photo from the gallery — both
the expense and the compressed receipt (712 KB source → 151 KB cached
file, well under the 400 KB target) saved locally with the correct
`is_dirty`/`pending` bookkeeping and the correct
`<household_id>/<expense_id>/<attachment_id>.jpg` storage path. Reconnected
— the attachment uploaded and synced cleanly. Vineet (admin), on a
completely separate emulator, opened the same expense from the Expense
List and saw the receipt thumbnail (downloaded via signed URL and cached),
opened the full-screen viewer, and saw the share button — confirming
T-10.4's resolution order and cross-device visibility end-to-end. Gate
10's literal acceptance text ("Capture offline → reconnect → the image is
visible on a second device") is satisfied.

The sub-second-precision fix was then also live-verified directly against
the real stuck row from this same session (see above) — the exact
`has_receipt` push that had been retrying for hours converged cleanly the
moment the fixed app opened its existing (unmodified) local database, with
no data loss and no manual intervention: `base_updated_at` confirmed
`TEXT NULL` right after the v3 → v4 migration, then a precise
microsecond-bearing string after the next successful push.

This is a genuine, real conflict-retry converging via the CAS mechanism
end-to-end for the first time this build has actually observed it
succeed — every earlier attempt this session hit one of the three bugs
above first. It is **not**, however, a re-run of Gate 4's own pending
acceptance scenario (two separate devices editing the *same* row while
both offline, reconnecting, and confirming the newer edit wins) — this
was a single device's own two sequential edits colliding with themselves.
**Gate 4 stays at partial**, now blocked only on that literal two-device
scenario re-run (no emulator pair was free for a second, parallel test
in this same session) — but with materially higher confidence than
before, since the CAS plumbing it depends on has now been shown to work
correctly against the real Supabase project rather than only in the
`push_conflict_resolution_test.dart` fakes.

## 2026-09-06 — Phase 11 (Analytics)

**Raw SQL for the multi-month aggregates, typed queries for everything
else.** `ReportDao`'s existing single-period queries (household/member/
category/payment-method totals) stayed as typed `selectOnly(...)` builders
— same pattern since Phase 6. But the three genuinely *multi-month* charts
(12-month trend, 6-month member comparison, 3-month category MoM table)
needed a single query grouped by calendar month, and Drift's typed builder
has no portable "group by month of a date column" expression. Rather than
issue one query per month (12–36 separate `Stream`s that would then need
error-prone client-side zipping to combine into one reactive chart), each
uses a single `customSelect` with SQLite's `strftime('%Y-%m', col,
'unixepoch')`. This only works because Drift's `DateTimeColumn` has stored
as unix-epoch-**seconds** INTEGER by default since Phase 2 (never
overridden via `DriftDatabaseOptions.storeDateTimeAsText`) — confirmed by
grep before writing a line of SQL, and confirmed correct by 9 new DAO
tests that actually exercise `strftime` against a real in-memory SQLite
database rather than mocking it. Day-of-week grouping (`strftime('%w',
...)`) has the same dependency. If a future migration ever turns on
text-based date storage, every one of these five queries needs rewriting.

**Weekday averaging is client-side, not SQL.** The day-of-week chart needs
"average spend on a Tuesday", i.e. total ÷ *how many Tuesdays occurred in
the period* — not ÷ the count of expense rows, which would just be "average
per transaction". Counting calendar-weekday occurrences from period bounds
is a 30-iteration loop in Dart (`AppTime`'s existing month-bounds helpers
already give `[start, end)`); doing it in SQL would mean a second, uglier
query solely to generate a weekday-occurrence calendar. `ReportDao` returns
the raw per-weekday *totals* only; `_DayOfWeekChart` in
`analytics_screen.dart` owns the averaging.

**Payment-method split and top-merchants use plain widgets, not
`fl_chart`.** Spec §11.10 calls the payment-method chart a "horizontal
bar", but `fl_chart` 1.2.0's `BarChart` renders vertically only — there is
no horizontal-orientation flag, only a whole-chart `rotationQuarterTurns`
which would also rotate the axis labels and touch handling. Rather than
fight the library (or add a second charting dependency for one chart),
both use the same proportional-bar-row / ranked-list widgets the Dashboard
already established for its per-member breakdown (Phase 6) — simpler, and
visually consistent with the rest of the app.

**Shared `MonthSelector`/`SectionCard` extraction.** Spec §11.10 says the
month/range selector is "shared with the Dashboard" — not just
conceptually similar, but literally the same picker so switching tabs
keeps the same selected month. Since `dashboard_screen.dart`'s private
`_MonthSelector`/`_MonthYearPickerDialog`/`_MonthCell` and
`_DashboardCard`/`_EmptyCardBody` were already an exact byte-for-byte match
for what Analytics needed, they were pulled out verbatim into
`features/dashboard/widgets/month_selector.dart` (`MonthSelector`) and
`section_card.dart` (`SectionCard`/`EmptySectionBody`) rather than
duplicated a second time — both screens now import the same widgets and
both watch the same `selectedMonthControllerProvider`.

**Bug found & fixed**: the monthly trend chart's x-axis thins its labels
to every other month once 12 months don't fit, but the naive `i.isOdd`
check could land on the *last* index (the current month — the most
relevant point on the whole chart) and hide it. Caught immediately on the
first live screenshot on the `kharcha_test` emulator: September's spike
had no "Sep" tick under it. Fixed by special-casing `isLast` so the final
label always renders regardless of parity.

### Live verification (Gate 11)

`fvm flutter analyze --fatal-infos` clean; `fvm flutter test` green at 206
tests (9 new in `report_dao_test.dart`). **Live-verified** on the
`kharcha_test` emulator against the real Supabase project and the real
household's live data (₹250 Groceries + ₹50 zomato expenses, ₹50,000
income, all logged in September 2026): every one of the 7 charts'
figures reconciled exactly against the Dashboard's own cards for the same
period (donut 83%/₹250 + 17%/₹50 matching the Dashboard's top-categories
card; payment-method split's Cash ₹250 + UPI ₹50 summing to the
Dashboard's ₹300 spent; the trend chart's September point matching the
Dashboard's income/expense figures exactly). Paged the shared month
selector back to August 2026 (a real month with zero household activity)
and confirmed all 7 cards render the "No data for this period" empty
state cleanly — no crashes, no `NaN`, no infinite axes. Re-verified in
dark mode too (`adb shell cmd uimode night yes` plus a full app restart,
since a live theme-only broadcast wasn't picked up without one): every
card's background, text, and every chart's line/bar/slice colours (all
sourced from `Theme.of(context).colorScheme`, never a hardcoded
light-only `Color`) stayed legible against the dark surface.

## 2026-09-06 — Phase 12 (Export)

### `pdf`'s base14 fonts have no ₹ glyph — Noto Sans bundled as an asset (T-12.2)
- First unit-test run of `buildReportPdf` printed, to the console, "Unable
  to find a font to draw '₹' (U+20b9)" against `pw.Font.helvetica()` —
  confirmed this is a real, load-bearing gap, not a test artifact: the
  `pdf` package's base14 fonts (Helvetica/Courier/Times, the PDF spec's
  built-in set) only cover WinAnsi/Latin-1, which doesn't include the
  Rupee sign. Left unfixed, every ₹ in the PDF export would either render
  as nothing or trip the same warning in production.
- Fixed by downloading and bundling **Noto Sans Regular + Bold**
  (OFL-licensed, `assets/fonts/`, ~390 KB each) rather than reaching for
  `printing`'s `PdfGoogleFonts` helper (which lazily fetches fonts from
  Google's CDN at runtime) — bundling keeps PDF generation fully offline,
  consistent with this app's offline-first design throughout, and avoids
  a first-use network dependency for something as basic as rendering a
  report. Glyph coverage (U+20B9 present in both weights) was verified
  with `fontTools` before committing the files, rather than assuming it.
  Registered under `flutter: assets:` in `pubspec.yaml`, **not** `fonts:` —
  they're loaded as raw bytes for `pw.Font.ttf(...)` (a `pdf`-package
  concept), never used as a Flutter `TextStyle` font family.
- `buildReportPdf` (`data/export/pdf_report_builder.dart`) takes the two
  `pw.Font`s as parameters rather than loading them itself via
  `rootBundle`, so the function stays plain-Dart-testable; only
  `ExportRepository._loadReportFonts()` (the real call site) touches
  `rootBundle`. Live-verified the real NotoSans pair renders ₹ correctly
  throughout the report (see Gate 12 in PROGRESS.md).

### CSV `amount_inr` is a plain decimal, never `Money.format()`'s Indian grouping (T-12.1)
- Spec §11.11's CSV header example shows `amount_inr` as `450.00` — a bare
  decimal. `Money.format()` (built for on-screen display, T-2.2) would
  instead render a four-figure amount as `1,23,456.00`, and a comma inside
  a numeric CSV cell forces the field to be quoted, which stops a
  spreadsheet from summing the column directly with `SUM()` — exactly the
  thing a CSV export exists to make easy. `csv_export_builder.dart` formats
  `amount_inr` with a private `_amountStr` (`(paise / 100).toStringAsFixed(2)`)
  instead, deliberately bypassing `Money` for this one column.

### `csv` package v8's API replaced `ListToCsvConverter` — and gained built-in BOM support
- The pinned `csv: ^8.0.0` (added back in Phase 0, unused until now) turned
  out to have a fully rewritten API from the `ListToCsvConverter`/
  `CsvToListConverter` shape most still-circulating examples (and the
  spec's own phrasing) assume — `flutter analyze` caught this immediately
  (`creation_with_non_type`). The new `CsvEncoder(addBom: true).convert(rows)`
  actually simplifies spec §11.11's "UTF-8 with a BOM" requirement: the BOM
  is the encoder's own option, not something to prepend by hand as 3 raw
  bytes after the fact.

### Income gets its own CSV header shape, not a column subset of the expense one
- Spec §11.11 only shows the expense header verbatim and says "a second CSV
  for income when income is included" without specifying its columns.
  `buildIncomeCsv`'s header (`date,member,amount_inr,category,source,note,id`)
  drops `time`/`payment_method`/`merchant`/`has_receipt` entirely rather
  than leaving them blank for every row — the `incomes` table has none of
  those columns (§11.6, same reasoning as `IncomeRepository`'s Phase 7
  decision to not carry over expense-only features), so an always-empty
  column would just be noise in the file.

### PDF category/member breakdown tables are always household-wide for the period, independent of the screen's member/category filter
- The Export screen's member/category `FilterChip`s scope the CSV rows and
  the PDF's optional transaction-list appendix, but **not** the PDF's
  "Spend by category"/"Spend by member" tables — those always summarise
  the full household for the selected date range, matching spec §11.11's
  literal description of the PDF as a report, not a filtered view. Simpler
  than teaching `ReportDao`'s grouped-total queries a second filter
  dimension for a case the spec doesn't ask for.

### Full JSON backup includes soft-deleted rows — the one deliberate exception to this app's "never show deleted data" rule
- Every other read in this app (every DAO's `watchAll`, every repository
  stream) filters `deleted_at IS NULL`. `ExportRepository.exportFullBackupJson()`
  is the one exception: it selects straight off each Drift table with no
  `where` clause at all, on the reasoning that a disaster-recovery
  snapshot ("the disaster-recovery escape hatch", spec §11.11) should
  capture full history, not the live view — a restore that silently
  dropped every prior edit/delete would be a worse backup, not a cleaner
  one.

### Live verification (Gate 12)
- See PROGRESS.md for the full live-verification trace (CSV BOM/header/
  totals reconciling with the Dashboard, PDF rendering with a real ₹
  glyph via `qlmanage`, full backup's row counts matching the real
  household). One process note: the Export screen's own button
  coordinates were computed correctly this time by remembering Gate 7's
  screenshot-scaling lesson (the tool's screenshots are returned
  downscaled — multiply by the ratio to the device's real resolution
  before issuing `adb shell input tap`) after one early tap silently
  missed the button for the same reason as that gate's first attempt.

## 2026-09-06 — Phase 13 (Notifications)

### Only the daily reminder is a true OS-scheduled alarm — everything else is evaluated live
- Spec §11.12's table nominally "schedules" all six notification types,
  but three of them (monthly summary, recurring due, sync stuck) need
  content that literally cannot exist at any earlier scheduling time —
  "August: family spent ₹84,320" needs August to have actually finished;
  "3 recurring items are waiting" needs live pending-count data; "outbox
  stuck" needs the outbox's current age. `flutter_local_notifications`'
  `zonedSchedule` bakes a notification's title/body into the OS alarm at
  *schedule* time and fires it later with **zero app code running** (that's
  precisely how it survives the app being fully closed) — there is no hook
  to compute fresh content at the moment it fires, and this app has no
  background isolate to provide one (§11.12: "the app cannot run in the
  background").
- Resolved by treating those three as event-driven, exactly like
  `BudgetAlertService` (Phase 8) already does: evaluated at every app
  start/resume, and shown immediately (`NotificationService.show`, not
  `scheduleAt`) if their condition is currently true, deduplicated in
  `shared_preferences` (`notif_monthly_summary_notified_<yyyyMM>`,
  `notif_recurring_due_notified_<yyyyMMdd>`,
  `notif_sync_stuck_last_notified_ms`) so a later resume the same day/month
  doesn't re-fire the same one. Only the **daily reminder** is a real
  `zonedSchedule` alarm, because it's the one type whose fire time is
  genuinely fixed in advance (a wall-clock time-of-day) — see the next
  entry for how its "skip if already logged" condition still works
  correctly despite the alarm's content being baked in ahead of time.

### Daily reminder: single-shot re-scheduling, not a repeating alarm with `matchDateTimeComponents`
- The obvious API for "fires daily at HH:mm" is `zonedSchedule` with
  `matchDateTimeComponents: DateTimeComponents.time` (true OS-level daily
  repeat). Not used here, because the "skip if the user already logged ≥ 1
  expense today" condition (spec §11.12) can only be evaluated once, at
  schedule time — a true repeating alarm can't re-evaluate anything each
  day, since (again) no app code runs when it fires.
- Instead, `NotificationScheduler._scheduleDailyReminder` cancels and
  re-arms a **single one-shot** alarm every time it runs (every app start/
  resume, per T-13.2's own requirement — "must be re-scheduled on every
  app start"): `nextDailyReminderFireIst` (pure, `core/notifications/
  daily_reminder_schedule.dart`) decides whether that next occurrence is
  today (nothing logged yet, time hasn't passed) or tomorrow (already
  logged, or today's time already passed). This is not just a best-effort
  approximation — logging an expense is only possible with the app in the
  foreground, and that foreground moment always re-triggers this same
  re-evaluation, so the redundant alarm for "today" is reliably cancelled
  the moment it becomes unnecessary, before it would have fired.

### `NotificationService.show()` now requires an explicit channel per call site
- Before Phase 13, `show()` had `'budget_alerts'` hardcoded as the only
  Android notification channel, since `BudgetAlertService` was its only
  caller. Phase 13 adds three more `show()` call sites (monthly summary,
  recurring due, sync stuck) that are not budget alerts — hardcoding them
  onto the same channel would mislabel them in the system notification
  settings and let disabling "Budget alerts" silently kill unrelated
  notification types. `show()`'s signature now requires `channelId`/
  `channelName`/`channelDescription` explicitly; `BudgetAlertService`'s one
  call site was updated to pass its own values rather than relying on a
  default.

### `rootNavigatorKey` pulled out of `app_router.dart` into its own file
- Deep-linking a notification tap (T-13.4) needs a `BuildContext` from
  outside the widget tree, which only the root `Navigator`'s `GlobalKey`
  can provide — but that key previously lived as a private top-level
  variable inside `app_router.dart`, which imports every feature screen in
  the app. `core/notifications/notification_service.dart` must not import
  routing/features (layering), so the key moved to its own leaf file,
  `routing/root_navigator_key.dart` (no screen imports), which both
  `app_router.dart` and `app.dart`'s deep-link handler import directly.
  `app.dart` (not `NotificationService`) owns the actual
  `GoRouter.of(context).push(...)` call, keeping `NotificationService`
  payload-agnostic — a payload is just an opaque route path string.

### Live verification (Gate 13)
- Confirmed via `adb shell dumpsys alarm` that changing the reminder time
  in the new Notifications screen re-registers a real `RTC_WAKEUP` alarm
  for `ScheduledNotificationReceiver` at exactly the computed instant every
  time, including rolling correctly to "tomorrow" once picked a time that
  had already passed that day — matching `nextDailyReminderFireIst`'s
  branch for that exact case, and confirmed via the alarm history that each
  earlier alarm is cleanly `alarm_cancelled` before the new one is set (no
  stacking). One accidental but useful data point: a stray tap during
  manual testing committed the reminder time to 10:00 AM while the device
  clock read 11:04 AM — the very next `runAll()` correctly computed
  "tomorrow at 10:00 AM" (today's window had already passed), which is
  exactly the "already logged/already passed" fallback branch, live and
  unprompted.
- Budget-alert deep-linking was verified fully end-to-end: created a real
  ₹55 household budget against the household's actual ₹300 month-to-date
  spend, triggered `BudgetAlertService.evaluate()` via a background/
  foreground resume cycle, confirmed the real notification in the shade
  ("Budget alert — Household budget exceeded by ₹245.00", exact spec
  copy), and tapping it opened that exact budget's edit screen — T-13.4's
  literal acceptance line. Test budget deleted afterward.
- The daily reminder's actual alarm *firing* could not be confirmed this
  session: `dumpsys alarm` showed it correctly pending at the right instant,
  then later gone from the pending list with no corresponding log line or
  posted notification, evaluated well past its `inexactAllowWhileIdle`
  window (`maxWhenElapsed`). This looks like the emulator's own alarm-
  dispatch/App-Standby-Bucket throttling (confirmed the app's own bucket
  was already `active`, the best case, and device idle state was
  `ACTIVE` too — ruling out the two most common causes — without finding
  the actual blocker) rather than an app-side defect, but wasn't fully
  root-caused. Gate 13 is held at **partial** on this basis — matching
  Gate 0/Gate 4's precedent of recording an honest, unresolved gap rather
  than a false pass — pending either a patient longer re-run or, per the
  spec's own acceptance line, an actual physical Android device, which was
  never available in this sandboxed session.
- Also worth recording: automated `adb shell input tap` intermittently
  stopped reaching this emulator mid-session (a system `TimePickerDialog`'s
  Cancel/OK buttons and its on-screen numeric keypad silently ate several
  taps in a row, while `adb shell input keyevent` commands kept working
  throughout) — the same category of flakiness Phase 3's DECISIONS.md
  entry already documented for this environment. Worked around by asking
  the user to tap the stuck control directly rather than continuing to
  fight it automatically.

### iOS platform restored — the `com.apple.provenance` blocker is fixed upstream

- Phase 0 recorded the iOS half of Gate 0 as **BLOCKED** on macOS tagging
  build output with a `com.apple.provenance` extended attribute that
  `codesign` unconditionally refuses to sign, worked around at the time by
  hand-patching `removeExtendedAttributes` in the FVM-managed SDK's
  `packages/flutter_tools/lib/src/ios/mac.dart` — a patch that entry
  explicitly noted "is NOT part of the Kharcha repo" and would be lost on
  the next SDK reinstall.
- That patch is now **unnecessary**: Flutter 3.47.2 ships the same fix
  upstream, removing `com.apple.provenance` by name alongside
  `com.apple.FinderInfo`. Verified it is genuinely upstream rather than a
  surviving local edit — this session installed the SDK into an empty
  `~/fvm/versions/` from scratch and `git status` in the SDK checkout is
  clean. `flutter run` on the simulator now completes with no codesign
  failure at any step.
- `ios/` was therefore re-created rather than repaired, using the same
  Flutter revision `.metadata` already pins (`d3b14c8769`), so the template
  is consistent with the Android side rather than a mix of two SDK versions.
  The first attempt used the machine's global Homebrew Flutter (3.44.2,
  Dart 3.12.2), which cannot resolve this project at all (`pubspec.yaml`
  needs SDK `^3.13.2`) — FVM, which the project has pinned since T-0.2, is
  not optional here.

### `flutter create` on an existing project rewrites more than the platform folder

Running `fvm flutter create --platforms=ios .` also modified three tracked
files that have nothing to do with iOS, all reverted before committing:

- `.gitignore` — re-introduced the template's blanket `.fvm/` ignore,
  undoing the Phase-0 decision above to keep `.fvm/fvm_config.json`
  tracked. Left as-is this would have quietly untracked the pinned
  Flutter version.
- `.metadata` — dropped the `android` platform block from the `migration`
  list while adding nothing new (the `ios` entry was already there from
  T-0.3, since the original project *was* created with both platforms).
- `pubspec.lock` — resolved 24 packages upward, `analyzer` 13.3.0 → 14.3.0
  among them, despite the lockfile being committed deliberately per T-0.5.
  Reverting the lock and re-running `fvm flutter pub get` reproduces the
  committed resolution exactly.

### iOS launch screen mirrors Android's, rather than the Flutter template's

Android's launch window (`drawable-v21/launch_background.xml` +
`values/`/`values-night/styles.xml`) is a plain `?android:colorBackground`
fill with no logo, so it follows the system light/dark setting. The Flutter
iOS template instead hardcodes white with a centred `LaunchImage`. Matched
Android by stripping the image view and filling the root view with
`systemBackgroundColor` — UIKit's dynamic white/black — so neither platform
flashes a light panel before the first Flutter frame on a device in dark
mode. The `LaunchImage` imageset is left in the asset catalog, unreferenced,
the same way Android keeps its `<bitmap>` block commented out for whenever
T-16.2's real icon work happens.

Nothing above the platform layer needed a change for the splash journey:
`main()`'s bootstrap, `SplashScreen`, and the router's auth `redirect` are
all pure Dart and behave identically on both platforms.

### Simulator smoke test ran against a placeholder Supabase config

`config/dev.json` is gitignored and holds the real project's credentials on
the build machine; this session created a placeholder one
(`https://placeholder.supabase.co`) purely so `AppConfig.assertValid()`
passes. That is sufficient for exactly the journey under test — splash →
`redirect` → `/login` never makes a network call, since it turns only on
`client.auth.currentSession` being null — and the run log confirms
`***** Supabase init completed *****` with a placeholder URL. Actually
signing in from iOS against the real project remains unverified.
