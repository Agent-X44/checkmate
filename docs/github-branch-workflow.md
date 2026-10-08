# GitHub branches and Android releases

Production and developer editions share one codebase. A branch tracks code readiness; an Android flavor determines which tools an APK includes.

| Branch | Purpose |
| --- | --- |
| `stable` | Default branch and baseline for versioned releases. |
| `dev` | Ongoing work for both APK editions. |
| `feature/<change-name>` | Optional short-lived branches for individual changes. |
| `Android-dev`, `IOS-dev` | Existing platform branches retained for reference and ongoing platform work. |

The initial stable and development branches point to the same tested shared snapshot, including offline developer tools, Android flavors and the existing application fixes. Production remains authenticated and excludes developer tools. The developer edition supports local template work without signing in; its real LMS mode still uses normal authentication and access controls.

## Making a change

Start from `dev`. Small changes can be committed there; larger changes can use a `feature/<change-name>` branch and a pull request targeting `dev`. Shared fixes belong in this common source so both editions receive them.

When a version is ready, review a pull request from `dev` into `stable`. Run relevant tests and build both Android flavors before merging. Camera, OMR alignment and printing changes also need an Android device check.

## Publishing a version

Build both APKs from the same commit on `stable`, using the same version name and build number:

```powershell
./scripts/build-android-editions.ps1 -Flutter C:/flutter/bin/flutter.bat -BuildName 1.0.2 -BuildNumber 2
```

The version values above are examples; choose the actual next version before publishing. Configure a stable release signing key using `android/key.properties.example`. The resulting `CheckMate-Production.apk`, `CheckMate-Developer.apk` and `SHA256SUMS.txt` are in `build/releases`.

Create one GitHub release whose tag targets that exact stable commit, then attach both APKs and the checksum file. Git branches contain source code; generated APKs stay in release assets. Branch updates do not publish a release automatically.

See [Android edition details](android-editions-and-dev-tools.md) for offline tools, package IDs, signing and optional developer Firebase setup.
