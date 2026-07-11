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

## Microsoft Fluent Emoji (dish-category 3D artwork)

- **Where:** `apps/customer/assets/categories/*.png`
- **Author:** Microsoft — the Fluent Emoji project (3D style)
- **License:** MIT — `apps/customer/assets/FLUENT-EMOJI-LICENSE.txt`
- **Source:** https://github.com/microsoft/fluentui-emoji

MIT is permissive: it requires only that the copyright and permission notice ship
with the app (the `FLUENT-EMOJI-LICENSE.txt` above, surfaced in the in-app licenses
screen). No ShareAlike, no viral obligation on our own code, and modifying a render
carries no extra duty. Each category maps to its nearest food emoji (e.g. Biryani →
Curry rice, Momos → Dumpling); `FoodCategory.imageAsset` is the single swap point
for commissioned renders — no layout, sizing, or motion changes.

**These are not Swiggy's icons.** Swiggy's category illustrations are copyrighted
artwork on their CDN, and copying them into a competing delivery app would be
infringement.
