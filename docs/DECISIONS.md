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
