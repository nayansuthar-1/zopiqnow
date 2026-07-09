# Third-party assets

Everything zopiqnow ships that it did not create. Keep this file current — two of
these licenses require attribution in the distributed app.

---

## Figtree (brand typeface)

- **Where:** `packages/zopiq_ui/assets/fonts/Figtree-Variable.ttf`
- **Author:** Erik Kennedy
- **License:** SIL Open Font License 1.1 — `packages/zopiq_ui/assets/fonts/OFL.txt`
- **Source:** https://github.com/google/fonts/tree/main/ofl/figtree

The OFL permits embedding in a commercial app. It does **not** require attribution
in the app UI. The font may not be sold on its own.

Figtree stands in for **Proxima Nova**, the face Swiggy actually uses. Proxima Nova
is a commercial font (Mark Simonson Studio) and needs a paid mobile-app license.
If one is bought, drop the file in and change `ZopiqTypography.fontFamily` — the
only place a font name appears.

---

## OpenMoji (dish-category artwork)

- **Where:** `apps/customer/assets/categories/*.png`
- **Author:** OpenMoji — the open-source emoji and icon project
- **License:** Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0) —
  `apps/customer/assets/OPENMOJI-LICENSE.txt`
- **Source:** https://github.com/hfg-gmuend/openmoji

**Two obligations this places on us:**

1. **Attribution is required in the shipped app**, not just this file. A credits or
   licenses screen must name OpenMoji and the CC BY-SA 4.0 license. That screen does
   not exist yet — it is a release blocker, tracked in `DEVELOPMENT_PLAN.md`.
2. **ShareAlike:** if we *modify* an OpenMoji graphic, the modified graphic must be
   released under CC BY-SA 4.0 too. Using the files as-is, as we do, carries no such
   obligation on our own code — the license is not viral across the application.

If either obligation becomes inconvenient, the escape is to commission original
illustrations. `FoodCategory.imageAsset` is the single swap point; no layout,
sizing, or motion changes.

**These are not Swiggy's icons.** Swiggy's category illustrations are copyrighted
artwork on their CDN, and copying them into a competing delivery app would be
infringement.
