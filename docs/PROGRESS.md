| Task   | Status | Date       | Notes                                                              |
|--------|--------|------------|---------------------------------------------------------------------|
| T-0.1  | done   | 2026-09-03 | CLT/Homebrew/git pre-existing. CocoaPods, Android Studio via brew. JDK 17 via manual Temurin tar.gz (see DECISIONS.md). Xcode 26.6 installed from App Store, switched via xcode-select, license accepted, iOS 26.5 simulator runtime installed. |
| T-0.2  | done   | 2026-09-03 | FVM 4.3.0 installed. Flutter 3.47.2 (stable) installed and pinned via `fvm use stable`. Version recorded in DECISIONS.md. |
| T-0.3  | done   | 2026-09-03 | Flutter project created in place at repo root (not `~/Developer`, see DECISIONS.md) with org `com.panicker`, name `kharcha`, platforms android+ios. |
| T-0.4  | done   | 2026-09-03 | `.gitignore` extended per §4.7. `docs/SPEC.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md` created. |
| T-0.5  | done   | 2026-09-03 | All packages from §9.3 added except `custom_lint`/`riverpod_lint` (deferred, see DECISIONS.md). `integration_test` added as an SDK dependency. |
| T-0.6  | done   | 2026-09-03 | `flutter_lints` (from template) + default `analysis_options.yaml`. `flutter analyze --fatal-infos` passes with 0 issues. |
| T-0.7  | done   | 2026-09-03 | Android `minSdk = 26`, `compileSdk = 37` (bumped from default 36 for plugin requirements), core library desugaring enabled for `flutter_local_notifications`. iOS deployment target 15.0 (Flutter template default). |
| Gate 0 | partial | 2026-09-03 | **Android: PASSED** — empty app built, installed, and ran on emulator `kharcha_test` (Pixel 6, API 34), confirmed via live `flutter run` session. **iOS: BLOCKED**, not passed — see DECISIONS.md for the `com.apple.provenance`/codesign issue. Proceeding to Phase 1 on the Android path per user instruction; iOS to be revisited later. |
