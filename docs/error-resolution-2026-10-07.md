# Crucial-error resolution — 7 October 2026

## Fixed

- Android builds failed before compilation with Java NIO's `Unable to establish loopback connection` / `Invalid argument: connect`. Using a project-local temporary directory worked for the Gradle client and daemon. The Windows wrapper now scopes TEMP and TMP to `android/.gradle/java-tmp` for itself and its children. No global Java or Windows settings were changed. The wrapper is no longer ignored by Git so the fix can be retained in the repository.
- Flutter analysis now explicitly excludes the separate .kilo checkout, artifacts, the Python virtual environment, and generated Flutter ephemeral directories. Owned source and tests remain analyzed.
- Local IDE configuration had Python site-packages marked as source and module-relative paths pointing beneath .idea. Corrected the root to the project directory, restored lib/test source roots, and excluded generated directories, the virtual environment, artifacts, and the duplicate checkout. These IDE files are intentionally local and ignored by Git.
- Removed the obsolete local ndk.dir setting; Android already selects NDK 28.2.13676358 in app/build.gradle.kts. Flutter regenerates SDK path entries in local.properties, so its path-escape inspection messages may reappear without indicating build failure.

## Validation

- `dart analyze lib test test.dart`: no issues.
- `flutter analyze --no-pub`, after the scope correction: no issues (11.5 seconds).
- Backend test suite: 107 passed, one PyPDF2 deprecation warning.
- Initial Android native/debug build with a temporary Java socket-directory override: successful.
- Normal `flutter build apk --debug --no-pub`, using the saved wrapper fix and no temporary environment override: successful (57.3 seconds).
- APK: build/app/outputs/flutter-apk/app-debug.apk.
- Git diff whitespace check: passed.

## Remaining limitations

Flutter tests fail during native asset setup before test execution. The installed dartcv4 hook cannot find a suitable system CMake, and Flutter doctor reports no Visual Studio C++ toolchain. Selecting tests that do not directly call OpenCV does not avoid package-level native asset building. Neither disabling test assets nor a process-scoped native-feature override resolves this. No platform feature was globally disabled and no dependency implementation was modified. Install/configure the Windows native toolchain before running the full Flutter tests, including sheet alignment.

No device was connected; camera, QR scanning, on-device OMR, notifications, and live Supabase RLS were not exercised. Android build success confirms native compilation, not those runtime behaviors.

Remaining Kotlin/plugin migration, SDK tooling, and deprecation warnings did not block the verified debug build. No dependency upgrade was made solely to remove warnings. No business-rule behavior was changed.

## Usage ledger

The five-hour allowance started at 0% used. At the final checkpoint it was 10% used, below the requested 30-percentage-point daily ceiling. These readings are account-wide, approximate, and cannot isolate concurrent usage. Resume with a fresh usage reading and account for today's completed work.
