import 'package:flutter/widgets.dart';

/// The product's icon set: Phosphor, as a bundled font.
///
/// ## Why this is a file of constants and not a dependency
///
/// `phosphor_flutter` and `lucide_icons` were both tried and both fail to
/// compile against this Flutter SDK, identically:
///
/// ```
/// Error: The class 'IconData' can't be extended outside of its library
///        because it's a final class.
/// ```
///
/// Flutter has sealed `IconData`, and every icon-font package of that shape
/// subclasses it to carry its own font family and package. There is no Phosphor
/// release that avoids it, and the only other fix is moving the Flutter pin —
/// which the version freeze exists to prevent.
///
/// **But only *extending* `IconData` is sealed. Constructing one never was.**
/// So the font is bundled here and each glyph is a plain `const IconData`
/// naming the family and this package. That is what those packages were doing
/// underneath a subclass, minus the subclass.
///
/// ⚠️ **`flutter analyze` does not catch the failure those packages have** — it
/// does not analyse the pub cache, so both analysed clean and died at kernel
/// compile. Any future icon package has to be proven with a real build.
///
/// ## What this buys beyond compiling
///
/// - **No dependency**, so nothing here can move a pin or drift on a `pub get`.
/// - **Two weights**, so "selected" is a filled glyph rather than a colour
///   change alone — see [ZopiqIconsFill].
/// - **Only what is named here ships.** Flutter's icon tree-shaker subsets a
///   font to the `const IconData` codepoints it can prove are reachable, and
///   every constant below is `const`. Adding one is a line; it costs a glyph.
///
/// ## Licence
///
/// Phosphor Icons is MIT, and the licence is redistributed beside the font at
/// `lib/fonts/PHOSPHOR-LICENSE.txt`. That is a real answer to the question both
/// stores ask about the content an app ships — unlike the dish art, whose
/// provenance is still open.
///
/// ## Adding one
///
/// Find the codepoint in `phosphor_icons_regular.dart` (or `_fill`) in the pub
/// cache, or on phosphoricons.com, and add a constant. **The codepoint must
/// match the weight**: Regular and Fill do not share a table, and a Regular
/// codepoint rendered in the Fill family is a different picture or an empty box.
class ZopiqIcons {
  const ZopiqIcons._();

  // Every glyph below repeats `fontFamily` and `fontPackage` rather than going
  // through a helper. That is deliberate and not verbosity for its own sake: a
  // factory function cannot be `const`, and `const` is the whole reason the
  // tree-shaker can prove which glyphs are reachable and drop the rest.

  // ── Navigation ────────────────────────────────────────────────────────────
  static const IconData arrowLeft = IconData(
    0xe058,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData arrowRight = IconData(
    0xe06c,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData caretRight = IconData(
    0xe13a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData close = IconData(
    0xe4f6,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData house = IconData(
    0xe2c2,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );

  // ── Identity & inbox ──────────────────────────────────────────────────────
  static const IconData user = IconData(
    0xe4c2,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData bell = IconData(
    0xe0ce,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData bellRinging = IconData(
    0xe5e8,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData bellSlash = IconData(
    0xe0d4,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );

  // ── Ordering ──────────────────────────────────────────────────────────────
  static const IconData moped = IconData(
    0xe824,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData cookingPot = IconData(
    0xe764,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData forkKnife = IconData(
    0xe262,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData storefront = IconData(
    0xe470,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData cart = IconData(
    0xe420,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData receipt = IconData(
    0xe3ec,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData wallet = IconData(
    0xe68a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData tag = IconData(
    0xe478,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData gift = IconData(
    0xe276,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );

  // ── Controls ──────────────────────────────────────────────────────────────
  static const IconData plus = IconData(
    0xe3d4,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData minus = IconData(
    0xe32a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData heart = IconData(
    0xe2a8,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData star = IconData(
    0xe46a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData circle = IconData(
    0xe18a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData checkCircle = IconData(
    0xe184,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData checkSquare = IconData(
    0xe186,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData trash = IconData(
    0xe4a6,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData share = IconData(
    0xe408,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData copy = IconData(
    0xe1cc,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData whatsapp = IconData(
    0xe5d0,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData search = IconData(
    0xe30c,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData sliders = IconData(
    0xe434,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData funnel = IconData(
    0xe266,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData refresh = IconData(
    0xe036,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );

  // ── Sorting & status ──────────────────────────────────────────────────────
  static const IconData sparkle = IconData(
    0xe6a2,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData timer = IconData(
    0xe492,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData clock = IconData(
    0xe19a,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData trendDown = IconData(
    0xe4ac,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData trendUp = IconData(
    0xe4ae,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData mapPin = IconData(
    0xe316,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData chat = IconData(
    0xe168,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData cloudSlash = IconData(
    0xe1b6,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
  static const IconData warning = IconData(
    0xe4e2,
    fontFamily: 'PhosphorRegular',
    fontPackage: 'zopiq_ui',
  );
}

/// The filled twin of [ZopiqIcons], for selected and active states.
///
/// Only the glyphs that actually have a selected state are here. A filled
/// version of every icon would double the font's shipped weight for pictures
/// nothing ever draws.
class ZopiqIconsFill {
  const ZopiqIconsFill._();

  static const IconData bellRinging = IconData(
    0xe5e8,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData heart = IconData(
    0xe2a8,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData star = IconData(
    0xe46a,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData checkCircle = IconData(
    0xe184,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData moped = IconData(
    0xe824,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData cookingPot = IconData(
    0xe764,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData tag = IconData(
    0xe478,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData wallet = IconData(
    0xe68a,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData chat = IconData(
    0xe168,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData receipt = IconData(
    0xe3ec,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData gift = IconData(
    0xe276,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
  static const IconData cart = IconData(
    0xe420,
    fontFamily: 'PhosphorFill',
    fontPackage: 'zopiq_ui',
  );
}
