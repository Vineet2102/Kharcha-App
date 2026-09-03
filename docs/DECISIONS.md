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
