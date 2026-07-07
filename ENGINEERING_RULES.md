# ZOPIQNOW — Engineering Rules (Binding)
**Status:** MUST-FOLLOW for all contributors and for Claude/AI assistance.
**These rules override convenience. When in doubt, follow the rule, do not improvise.**

---

## RULE 1 — Android Compatibility (runs smoothly on new AND older devices)
The app **must install and run smoothly from Android 7.0 up to the latest Android**, with **Android 10 (API 29) treated as a first-class, explicitly-tested target**.

| Setting | Value | Reason |
|---|---|---|
| `minSdkVersion` | **24** (Android 7.0) | Covers ~99% of active devices; still lets us use modern APIs |
| `targetSdkVersion` | **35** (Android 15) | Required by Google Play in 2026 |
| `compileSdkVersion` | **35** | Compile against latest |
| NDK / arch | arm64-v8a + armeabi-v7a | Old + new hardware |

**Compatibility guardrails (do not violate):**
1. **No API used without a version guard.** Any API added above `minSdk` must be gated (`Build.VERSION.SDK_INT` on native side; capability checks on Dart side) with a graceful fallback.
2. **Use AndroidX + Jetpack compat** libraries only — never legacy support libs.
3. **Test matrix is mandatory** before every release: emulator + real device on **Android 10**, plus one older (Android 8/9) and one latest. A build is not "done" until it runs on Android 10.
4. **Keep the app lightweight for old hardware:** APK/AAB kept lean (split ABIs, `--split-per-abi`), avoid heavy startup work, lazy-init, cap animations to 60fps, no jank on mid-range 3GB-RAM devices.
5. **Enable code shrinking + resource shrinking (R8)** for release, with a tested, checked-in `proguard-rules.pro` (keep rules for reflection-based libs). Verify obfuscated release build on Android 10 before shipping.
6. **Graceful degradation:** features requiring newer OS/hardware (e.g., certain notification, biometrics, or exact-alarm behaviors) must degrade, never crash.
7. **Handle runtime permissions correctly across versions** (scoped storage, notification permission on 13+, background location rules) — behavior branch per OS version, tested.
8. **Minimum device profile target:** 3GB RAM, mid-tier CPU, slow 3G/4G. Design and test to this floor.

---

## RULE 2 — Design: Premium, Swiggy-grade, Swiggy Palette
The UI must feel **premium and polished like Swiggy** — generous spacing, crisp typography, smooth micro-interactions, consistent components.

**Primary brand palette (Swiggy-aligned) — single source of truth in `zopiq_ui` design tokens:**

| Token | Hex | Usage |
|---|---|---|
| `primary` (Swiggy Orange) | **#FC8019** | Primary brand, buttons, highlights, active states |
| `primaryDeep` (CTA Orange) | **#FF5200** | Strong CTAs, "ADD"/checkout emphasis, badges |
| `textDark` | **#282C3F** | Primary text / headings |
| `textMuted` | **#7E808C** | Secondary text, captions |
| `veg` | **#3D9B6D / #60B246** | Veg indicator, success |
| `nonVeg` | **#E43B4F** | Non-veg indicator, error |
| `surface` | **#FFFFFF** | Cards / sheets (light) |
| `background` | **#F4F4F5** | App background (light) |
| `divider` | **#E9E9EB** | Separators |
| `rating` | **#48C479** | Rating pill green |

**Design rules:**
1. **All colors/spacing/typography come from design tokens** in `zopiq_ui`. **No hardcoded hex or magic numbers** in feature code.
2. Material 3 base, but restyled to the Swiggy-premium look (custom buttons, cards, bottom sheets, shimmer skeletons) — not stock Material.
3. **Dark theme** is a full, designed variant using the same token system — not an afterthought.
4. Consistent 8pt spacing grid; consistent corner radii; consistent elevation/shadow scale.
5. Every list has shimmer/skeleton loaders, empty states, and error states — no blank screens.
6. Smooth transitions (hero, shared-axis), optimistic UI on cart, haptics on key actions.
7. Icons from one consistent set; images optimized (WebP/AVIF via CDN).
8. **Design is signed off in Figma before a screen is built.** Build to the design token, not to a screenshot.

> Note: Swiggy's exact brand assets/logo are proprietary. We match the **look, feel, and color language**, but zopiqnow uses its **own logo, name, and original iconography** — no copying of Swiggy's trademarked assets.

---

## RULE 3 — Version Freezing (do NOT change versions or tooling)
**Once a version is locked at project kickoff, it does not change without an explicit, approved change request.**

1. **Never bump, upgrade, or downgrade** any dependency, SDK, or tool version unless the task explicitly says "upgrade X to Y." This includes Flutter, Dart, Gradle, AGP, Kotlin, Java/JDK, Node, and every package in `pubspec.yaml` / `package.json`.
2. **Pin exact versions everywhere.**
   - Flutter/Dart: pinned via **FVM** (`.fvmrc` / `fvm_config.json` committed).
   - Dart packages: **exact versions** in `pubspec.yaml` (`1.2.3`, not `^1.2.3`), `pubspec.lock` committed.
   - Node: `.nvmrc` committed, `package-lock.json` / `pnpm-lock.yaml` committed, use `npm ci` (never `npm install` in CI).
   - Android: Gradle wrapper version, AGP, Kotlin pinned in Gradle files.
   - Docker base images pinned by **digest**, not `latest`.
3. **Lockfiles are committed and authoritative.** Never delete or regenerate a lockfile to "fix" something without approval.
4. **No `flutter pub upgrade`, no `npm update`, no auto-bump bots merging** without human review tied to an approved upgrade task.
5. **Dependency upgrades are a deliberate, separate, reviewed activity** — never a side effect of a feature branch. Upgrade in isolation, run the full test + Android-10 device matrix, then merge.
6. **AI/Claude rule:** Do not suggest or apply version changes as part of unrelated work. If a version issue is genuinely blocking, **stop and flag it** for human decision — do not silently change it.
7. One canonical version list lives in `DEVELOPMENT_SETUP.md`; that file is the only place versions are decided.

---

## RULE 4 — General Engineering Discipline
1. **Contracts-first:** freeze the OpenAPI/proto contract before implementing an endpoint or its client.
2. **No secrets in code or git.** Use env + secret manager. `.env` never committed.
3. **Feature flags default-off** for unfinished work; nothing half-built reaches users.
4. **Tests required** for domain logic and payment/order paths before merge (see SAD Section 23 gates).
5. **Every money movement is idempotent + ledger-backed** (SAD Section 17).
6. **Match surrounding code style**; run linters/formatters in CI; PRs blocked on lint/test failure.
7. **No breaking DB migrations** — expand/contract, reversible.
8. **Accessibility + localization from day one** — no hardcoded user-facing strings.

---
*Any deviation from Rules 1–3 requires written CTO approval recorded in the PR.*
