# zopiqnow

Premium food delivery & quick-commerce platform.

> Read [`ENGINEERING_RULES.md`](ENGINEERING_RULES.md) and
> [`DEVELOPMENT_SETUP.md`](DEVELOPMENT_SETUP.md) **before contributing.** They are
> binding. [`ZOPIQNOW_ARCHITECTURE.md`](ZOPIQNOW_ARCHITECTURE.md) is the full blueprint.

## Monorepo layout

This is a **Dart pub workspace** (single shared `pubspec.lock` at the root =
the frozen dependency set, Rule 3) with **Melos** for cross-package tasks.

```
zopiqnow/
├── apps/
│   └── customer/         # Flutter customer app (Riverpod + go_router)
├── packages/
│   └── zopiq_ui/         # Design system: Swiggy-grade tokens, theme, components (Rule 2)
├── pubspec.yaml          # workspace root (members + Melos)
├── melos.yaml            # task runner (analyze / format / test)
├── analysis_options.yaml # shared strict lint config (included by every member)
└── .fvmrc                # pinned Flutter 3.44.5 (Rule 3)
```

More apps (delivery-partner, restaurant) and packages (core, data) join under
`apps/` and `packages/` as they are built.

## Getting started

Toolchain versions are **locked** — install exactly what `DEVELOPMENT_SETUP.md`
lists (Flutter 3.44.5 via FVM, JDK 17, Android SDK 36/35/29).

```bash
# From the repo root — resolves the whole workspace into one lockfile.
flutter pub get

# Run the customer app.
cd apps/customer && flutter run

# Quality gates (from root, via Melos).
dart run melos analyze
dart run melos test
dart run melos format
```

## Android builds

| Purpose | Command | Notes |
|---|---|---|
| Debug (emulator, all ABIs incl. x86_64) | `flutter build apk --debug` | run from `apps/customer` |
| **Release for Play (canonical)** | `flutter build appbundle --release` | R8 + resource shrink; arm64-v8a + armeabi-v7a |

> Release signing still uses the **debug** keystore — swap in a real keystore
> before publishing (see `apps/customer/android/app/build.gradle.kts`).
>
> **ABI strategy (decided 2026-07-07):** ship the **AAB** — Play does per-device
> ABI splitting from it. We keep `ndk.abiFilters` (arm64-v8a + armeabi-v7a) and do
> **not** use `flutter build apk --split-per-abi` (AGP forbids it alongside
> `abiFilters`). Debug APKs still include x86_64 for emulator testing.

## Milestone status

**M1 — Foundation & design system: ✅**
Monorepo, pinned toolchain, `zopiq_ui` (tokens + light/dark theme + core
components), app shell (Riverpod + go_router), and a design showcase screen.
