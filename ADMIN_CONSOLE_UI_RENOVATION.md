# Admin console — UI renovation

A survey of how `apps/admin-web/` **looks and behaves on screen**, on 2026-09-02, against
`main` at `0f22390`. The successor to `ADMIN_CONSOLE_FIX_QUEUE.md`, which is closed —
all twenty-four of its findings landed on 2026-09-01, and every one of them was about
what the console *did*. Nothing below is about what it does. This is about what it is:
typography, colour, rhythm, density, and the twelve tables that were each written from
scratch.

**State of the build, at this survey.** `tsc -b` clean. `vite build` clean in 370 ms.
`oxlint` exits 0 with no output at all. There is no lint or type debt to work around —
every change proposed here starts from green and has to end there.

**What this is not.** Not a redesign. The console's visual language is already decided
and is right: a flat white surface on a grey canvas, one accent colour, no glow, no
gimmicks — the same restraint the three Flutter apps are held to. The problem is not the
language. The problem is that twenty-one screens speak it with twenty-one accents, and
that a handful of things in it are measurably wrong rather than merely inconsistent.

---

## Part 1 — The analysis

### How the console is built today

| | |
|---|---|
| Screens | 21 routes, one shell, one wizard of 8 steps |
| Source | ~13,600 lines of TSX across 53 files (`src/lib/api.ts` is another 1,634) |
| Design system | `src/ui/primitives.tsx` — 704 lines, 15 exported components |
| Tokens | `src/index.css` — 13 colours, 2 radii, mirrored by hand from `packages/zopiq_ui/lib/src/tokens/` |
| Tables | 12, all hand-rolled |
| Icons | none — *20 Phosphor glyphs since C1* |
| Shadows | one, on the modal |
| Bundle | a single 712 kB chunk (191 kB gzipped), no code splitting — *split in Phase 6* |

The primitives are genuinely good. `Modal` traps focus, restores it, and refuses to close
mid-request. `Button` defaults to `type="button"` for a reason that is written down.
`Banner` puts `role="alert"` on the error tone and `role="status"` on the rest, and says
why. `SegmentedControl` is a real radio group. This is a component library somebody
thought about.

**The gap is between the primitives and the pages.** Fifteen components exist; the pages
reach past them for a hand-written `<div className="rounded-[12px] border border-line
bg-white p-5">` twenty-seven times. That is the shape of every finding below.

---

### A. Things that are measurably wrong

These are not taste. Each one is a number that fails a published threshold.

#### A1 — The primary button's label fails contrast at 2.55:1
- [x] **Done** — `src/index.css`, `src/ui/primitives.tsx`, `src/ui/AppShell.tsx` and 25 page
      files (`a66a546`, `7bf1d8e`)

**Decided: keep `#fc8019`, darken the *label*.** Ink on the unchanged brand orange measures
**5.41:1** — the option this section did not measure when it was written, and the better one.
The resting orange stays identical to the three apps, where the recommendation below would
have changed it on every primary button in the console. Both cost exactly one new token.

What shipped: `--color-brand-hover` (#f06e00) for the button's hover, because
`--color-brand-deep` measured 4.24:1 with ink and failed; `--color-brand-ink` (#b85400) for
brand as text or a line; `--color-non-veg-ink` (#c62336) for error copy, leaving
`--color-non-veg` alone where it means *food*; `--color-warn` darkened in place to #a05f18,
no sibling needed because nothing in the console fills with it; and `--color-field` (#8e8e99)
for the boundary of a control. **All 21 measured pairs now pass**, re-checked against the hex
values as they sit in `index.css` rather than against these notes.


White text on `--color-brand` (`#fc8019`) measures **2.55:1**. WCAG AA needs 4.5:1 for
14 px semibold text and 3:1 even for large text. It fails both. The hover state
(`--color-brand-deep`, `#ff5200`) measures **3.25:1** and still fails.

This is every `<Button>` with no `variant` in the console — the save on all eight wizard
steps, "Add rider", "Add restaurant", the confirm on every non-destructive dialog.

Measured across the palette:

| Pair | Ratio | AA (4.5) |
|---|---|---|
| Body — ink on white | 13.80 | pass |
| Muted — ink-muted on white | 5.93 | pass |
| Muted on canvas | 5.49 | pass |
| Pill `neutral` — ink-muted on canvas | 5.49 | pass |
| Pill `live` / Banner success — veg on veg-soft | 5.14 | pass |
| Danger button — non-veg on white | 4.17 | **fail** |
| Field error text — non-veg on white | 4.17 | **fail** |
| Pill `warn` — warn on warn-soft | 3.83 | **fail** |
| Pill `danger` / Banner error — non-veg on non-veg-soft | 3.60 | **fail** |
| Pill `brand` / active nav — brand-deep on brand-soft | 3.00 | **fail** |
| **Primary button — white on brand** | **2.55** | **fail (and fails 3:1)** |
| **Focus ring — brand on white** | **2.55** | **fail (needs 3:1, WCAG 1.4.11)** |
| Input border — line on white | 1.21 | **fail (needs 3:1 for a control's only boundary)** |

**This is a decision, not a fix, and it is the user's.** `#FC8019` is not the console's
to change: it is `ZopiqPalette.primary` in `packages/zopiq_ui/lib/src/tokens/zopiq_palette.dart:13`,
the source of truth for all four surfaces, and the Swiggy-aligned palette is a deliberate
product choice recorded in that file's own header. Three ways out, in the order I'd
recommend them:

1. **Add a token, change no existing one.** `--color-brand-ink` — a darkened orange used
   *only* where brand carries text or draws a control boundary (the primary button's
   fill, the focus ring, the active-nav text). Orange stays orange everywhere it is a
   fill behind nothing. `#C25000` reaches 4.6:1 with white. The palette file has done
   exactly this once before: `textMuted` was darkened from Swiggy's `#7E808C` for the
   same reason, and says so in a comment.
2. **Keep the orange, darken the label's weight and size** — does not work; 2.55:1 fails
   the large-text threshold too. Noted only so it is not proposed later.
3. **Accept it and record the exception.** Defensible for a ten-person internal console
   in a way it would not be for the customer app. But the console is where somebody
   cancels a stranger's dinner, and the button they press to do it should be readable.

Whichever is chosen, the **focus ring at 2.55:1** and the **input border at 1.21:1**
should be fixed regardless — those are not brand expression, they are the only thing
telling a keyboard user where they are and telling anyone where a text field is.

#### A2 — Every `<select>` in the console has no focus indicator

Ten native selects, in five files. All ten carry `outline-none focus:border-brand` — which
removes the browser's own focus ring and replaces it with a 1 px border colour change
that itself measures 2.55:1 against white. `RidersPage.tsx:1277` has no focus style at
all.

- `src/gifts/GiftItemDialog.tsx:156,184`
- `src/menu/ItemDialog.tsx:147,250`
- `src/orders/AllOrdersPage.tsx:302`
- `src/restaurants/steps/TeamStep.tsx:65,109`
- `src/riders/RidersPage.tsx:143,797,1277`

The `RING` constant that exists for exactly this (`primitives.tsx:22`) reaches none of
them, because there is no `Select` primitive to put it in.

#### A3 — No table in the console has a hover state, and none has a sticky header

Zero of the twelve tables highlight the row under the cursor. Zero keep their header
visible while the body scrolls.

`SettlementsPage` is nine columns wide (`min-w-[980px]`) and the ninth is **Payable**,
with a "Mark paid" button beside it. Tracking a restaurant's name from column one to a
money button in column nine, on a row that looks identical to the fourteen around it,
with the header scrolled off the top — that is the console's highest-consequence
interaction and it has the least support. `CashPage`, `RefundsPage`, `PayoutsPage`,
`AllOrdersPage` and `UsersPage` are all the same shape at 900 px.

#### A4 — No `<th>` in the console has `scope="col"`

Twelve tables, none of them. A screen reader in table-navigation mode cannot associate a
cell with its column heading. Cheap to fix, and it is the one accessibility gap the
primitives never addressed because the tables were never primitives.

#### A5 — Money is formatted two different ways, in the same console, on the same kind of screen

`SettlementsPage` and `AnalyticsPage` group digits: `₹${n.toLocaleString('en-IN')}` →
`₹1,25,000`. `AllOrdersPage`, `CashPage`, `PayoutsPage`, `RefundsPage`, `SupportPage`,
`GiftOrdersPage`, `UsersPage`, `CouponsPage` and `MenuStep` interpolate raw: `₹{o.total}`
→ `₹125000`.

And `tabular-nums` — which `index.css` goes out of its way to explain, "a settlement table
where the rupee figures are proportionally spaced is one nobody can scan down" — is
missing from the money columns in `UsersPage.tsx:531` (which also drops the
`font-semibold` every other money cell has), `SupportPage.tsx:251` and
`GiftOrdersPage.tsx:240`.

Three dates in `AlertsPage.tsx:202,221,276` call `toLocaleString()` with no locale, so
they render in the browser's, while every other date in the console is pinned to `en-IN`.

#### A6 — The browser tab shows a purple logo that is not this product's

`apps/admin-web/public/favicon.svg` is a 48×46 mark filled `#863bff`. Zopiqnow's mark is
the orange pin in `apps/customer/android/app/src/main/res/mipmap-*/ic_launcher.png`, and
`#863bff` appears nowhere else in the repository. It is a leftover.

`apps/admin-web/public/icons.svg` is likewise dead — a sprite sheet of social icons
(Bluesky, among others), referenced by nothing in `src/` or `index.html`. *Mentioned, not
deleted* — it is not this survey's to remove.

#### A7 — The toggle's two states are both below the non-text threshold

*Found while fixing A1; not in the original survey.* `Toggle` (`primitives.tsx:216`) shows
"on" as a white thumb on `--color-brand` (**2.55:1**) and "off" as a white thumb on
`--color-line` (**1.21:1**). A switch's state is conveyed by nothing but those two, so
WCAG 1.4.11 asks both for 3:1.

Deliberately **not** taken with A1: the answer is either a darker track — which makes the
control a different colour from the brand it is meant to echo — or a shape change, and
neither is a token swap. It belongs with the primitives work in Phase 2.

---

### B. Things that are inconsistent

Twenty-one screens, one design system, and no two screens applying it the same way.

#### B1 — Twelve tables, four header styles, three divider styles, two row heights

| File | Header | Dividers | Cell padding | Width floor |
|---|---|---|---|---|
| `AnalyticsPage:160` | sentence case, `font-medium` | `divide-y` | `py-3` | 560 |
| `CouponsPage:476` | sentence case, `font-medium` | `divide-y` | `py-3` | 820 |
| `PayoutsPage:123` | sentence case, `font-medium` | `divide-y` | `py-3` | 760 |
| `RefundsPage:193` | sentence case, `font-medium` | `divide-y` | `py-3` | 900 |
| `CashPage:164` | sentence case, `font-medium` | `divide-y` | `py-3` | 900 |
| `SettlementsPage:199` | sentence case, `font-medium` | `divide-y` | `py-3` | 980 |
| `RestaurantsPage:174` | UPPERCASE, `font-semibold` | `border-b last:border-0` | `py-3` | 820 |
| `GiftOrdersPage:196` | UPPERCASE, no weight | `divide-y` | `py-4` | none |
| `SupportPage:200` | UPPERCASE, no weight | `divide-y` | `py-4` | none |
| `AllOrdersPage:346` | UPPERCASE, `font-medium` | `border-b last:border-b-0` | `py-4` | 900 |
| `UsersPage:496` | UPPERCASE, `font-medium` | `border-b last:border-b-0` | `py-4` | 900 |
| `ImportDialog:113` | — | `border-b last:border-0` | — | 560 |

Two of them (`SupportPage`, `GiftOrdersPage`) have no `min-w` at all, so their columns
crush instead of scrolling — the opposite behaviour from the other ten, on the two screens
that sit side by side in the same nav group.

None of the twelve gives the horizontal scroll any affordance: `overflow-x-auto` on a bare
`<div>`, no edge fade, no shadow. On a laptop there is nothing on screen to say the table
continues to the right.

#### B2 — Twenty-seven hand-rolled cards against seventeen uses of `<Card>`

`Card` exists (`primitives.tsx:690`) and is `p-6`. The string
`rounded-[12px] border border-line bg-white` appears **27 more times** outside it, at
three different paddings — `p-4` (`BroadcastPage:234`, `OrderAdsPage:130`), `p-5`
(`AnalyticsPage:86,215,253`, `LiveOrdersPage:342`), `p-6` (everywhere else). `Card` is
used on 6 screens; the other 15 write it out.

#### B3 — Sixteen hand-copied field styles

`h-11 w-full rounded-[8px] border border-line bg-white px-3 text-sm` appears 16 times
across 10 files, outside the `Field` primitive that owns it. Every one of them is a
`Field` with something `Field` cannot express: a `<select>` (A2), a search box that needs
`flex-1`, a number input beside a `+₹` prefix.

The two search boxes (`LiveOrdersPage:196`, `AllOrdersPage:271`) are character-identical
and neither is a component.

#### B4 — Seven hand-rolled pills beside the `Pill` primitive, in two sizes

`Pill` is `px-2.5 py-1 text-xs font-semibold`. Hand-rolled ones are `px-2 py-0.5 text-xs
font-medium` — smaller, lighter, on a different vertical rhythm:

- `RidersPage.tsx:299,304` — *on the same line as a real `<Pill>`.* A rider row can show
  "inactive" (hand-rolled), "carrying ZPQ-1044" (hand-rolled) and "verified" (`Pill`)
  side by side, in two different pill shapes.
- `MenuStep.tsx:224`, `HoursStep.tsx:127`, `GalleryField.tsx:103`, `OrderAdsPage.tsx:146`
- `HeroSlidesPage.tsx:76` re-implements `Pill` outright, with its own `stateStyles` map
  and the exact same class string.

#### B5 — Three copy-pasted pagers, and nine tables with no pagination at all

`AllOrdersPage:444`, `SupportPage:273` and `GiftOrdersPage:262` carry the same
Previous / "Page n of m" / Next block, verbatim, three times.

The other nine tables load everything. At twelve kitchens and one town that is invisible;
at fifty it is a settlements page that renders every week ever closed. This is a UI
question as much as a data one — the answer is one `Pager` primitive and a decision about
which lists get it.

#### B6 — "Loading…" as bare text in eight places, in a console whose own primitives file explains why that is wrong

`primitives.tsx:581` reads: *"A skeleton rather than the word 'Loading…', because the
console's tables are the width of the window: the text version collapses the page to one
line and then throws it back to full height, and the button somebody was reaching for has
moved by the time they get there."*

Bare `Loading…` remains in `App.tsx:33`, `AlertsPage:214`, `HeroSlidesPage:716`,
`OrderAdsPage:95`, `GiftOrdersPage:355`, `AllOrdersPage:485`, `ReviewStep:115`,
`WizardPage:82`, `RidersPage:236`.

Four more screens hand-compose skeletons instead of using `TableSkeleton`/`CardSkeleton`:
`AnalyticsPage:87`, `RidersPage:685,1079,1267`, `SettingsPage:86,255`, `CashPage:423`.

And three screens never reach `EmptyState`: `RidersPage:285` uses a bare `<p>`,
`CashPage` and `AnalyticsPage` render nothing.

#### B7 — Two stat-tile treatments

`AnalyticsPage`'s `Tile` (`:205`) is `text-2xl font-bold tabular-nums`, label
`font-medium uppercase`, `mt-1.5` / `mt-0.5`. `UsersPage:175` is `text-2xl font-semibold`,
no `tabular-nums`, label with no weight, `mt-2` / `mt-1`. Neither is a primitive; both are
the same idea.

#### B8 — Page bodies on three paddings and seven content widths

Eighteen pages are `p-6`. `AlertsPage:153` is `px-6 py-6` (identical, written
differently). `GiftCataloguePage:206` is `px-6 py-5` — off the grid.

Content width is where it shows most. `RidersPage` caps at `max-w-3xl` and `SettingsPage`
at `max-w-2xl`, while `UsersPage` — the same kind of roster screen — runs full-bleed to
whatever the monitor is. `HeroSlidesPage` is `max-w-5xl`. The wizard switches between
`max-w-2xl` and `max-w-4xl` on `step === 6`, a magic number. There is no rule, so there is
no way for a new screen to be right.

Banners inherit the confusion: `LiveOrdersPage` puts an error banner at `max-w-2xl` and,
four lines later, a success banner at `max-w-3xl`.

Only **6 `lg:` breakpoints exist in the entire console.** On a 27-inch monitor almost
nothing uses the width; the tables stretch their columns to 2000 px and the forms sit in
a 672 px ribbon against an ocean of grey.

---

### C. Things that are missing

#### C1 — There are no icons
- [x] **Done** — `tool/phosphor-glyphs.mjs`, `src/ui/icons.ts`, `src/ui/primitives.tsx`,
  `src/ui/nav.ts`, `src/ui/AppShell.tsx`

**Both routes below were tried and both were dead ends, so there is a third.** The font
costs **376 kB gzipped** to draw twenty pictures. Phosphor's SVG set is not in this
repository, and writing the paths from memory would be inventing drawings and labelling
them Phosphor.

So `tool/phosphor-glyphs.mjs` reads the outlines out of `Phosphor-Regular.ttf` — the file
the three Flutter apps already bundle — and emits them as path data. No dependency: a
TrueType `glyf` table is a documented format and the part these glyphs use is small. The
result is the apps' own drawings **by construction rather than by resemblance**, which is
the whole point, and it costs **10 kB gzipped** instead of 376.

**Twenty glyphs, one per sidebar link, none held in reserve** — an unused glyph is bytes in
the bundle and a picture nobody has looked at. The codepoints are copied from
`packages/zopiq_ui/lib/src/tokens/zopiq_icons.dart` and the generator refuses a codepoint
that is not in the font, so the console's set cannot drift from the apps'. The font's
`post` table is version 3.0 and carries no glyph names, so that Dart file is the only
name-to-codepoint map there is — which is why the generator is pinned to it.

**The check that matters is `tool/phosphor-preview.mjs`.** A hand-written binary parser
does not fail loudly when it is wrong; it draws a subtly mangled contour, silently, and
twenty icons nobody ever looked at ship. So the second tool rasterises the committed path
data to a contact sheet — nonzero winding, 3×3 supersampled, PNG written with `zlib` and
no dependency — and all twenty were checked by eye before this landed. Re-run it after any
change to the generator.

`Icon` is always `aria-hidden`: every icon here sits beside its own label, and announcing
it would read the name twice. It fills with `currentColor`, so the active nav item's glyph
turns `brand-ink` along with its label rather than needing a second rule to keep in step.

*The original survey follows.*

Two `<svg>` elements exist in 13,600 lines: the `Spinner`, and the sparkline in
`AnalyticsPage`. The sidebar is twenty text links. Every button is a word. Every status is
a word in a coloured lozenge. Nothing on any screen is scannable at a glance, and an ops
console is a tool people scan.

**The set already exists and is already licensed.** `packages/zopiq_ui/lib/fonts/`
carries `Phosphor-Regular.ttf` and `Phosphor-Fill.ttf` under MIT, with 54 glyphs named in
`zopiq_icons.dart` and the whole rationale written down (Flutter sealed `IconData`, so the
font is bundled rather than depended on). The web console can use the same two files and
be iconographically identical to the three apps for the cost of an `@font-face` — or take
Phosphor's own SVG set, which is the same drawing. Either way, the answer is "the icons
the product already uses", not a new dependency.

#### C2 — There is no brand typeface
- [x] **Done** — `src/index.css`, `src/fonts/` (`8300746`)


`index.css` sets `system-ui, 'Segoe UI', Roboto, sans-serif`. The apps set **Figtree**, a
variable face bundled at `packages/zopiq_ui/assets/fonts/Figtree-Variable.ttf` (62 kB,
SIL OFL), chosen as the closest freely-licensable relative of Swiggy's Proxima Nova, with
a comment saying nothing else in the codebase references a font name.

The console is the one surface that looks like a different company's product.

#### C3 — There is no type scale
- [x] **Done** — `src/index.css` (`8300746`). Mirrored onto the six size names the console
      already writes, so 308 uses of `text-sm` inherited the scale without a page changing.


The token package defines thirteen steps with line-heights and letter-spacing
(`zopiq_typography.dart:44-57`). The console has four sizes and no scale: **308**
`text-sm`, **93** `text-xs`, 20 `text-base`, 3 `text-xl`, 2 `text-2xl`, **1** `text-lg` —
and that one is the page `<h1>` (`AppShell.tsx:178`). A page title is 18 px; body is
14 px; there is one step between the largest and smallest thing on most screens. No
line-height or letter-spacing is set anywhere. That flatness is most of why the console
reads as utilitarian rather than professional.

#### C4 — There is no elevation, and the sticky header proves it
- [~] **Half done** — the scale is mirrored and the modal’s inline shadow is named
      (`8300746`). The sticky headers that need one are Phase 4.


One shadow exists, on the modal (`primitives.tsx:448`). `ZopiqElevation` defines three
tiers and calls them "soft, premium … rather than harsh Material drop shadows".

`PageHeader` is `sticky top-0` with a 1 px bottom border and nothing else, so on every
scrolling screen the table slides *under* it with no separation. The wizard's step bar
sticks the same way and has the same problem.

#### C5 — There is no toast, so half the confirmations are invisible

Fifty `<Banner>`s, all inline at the top of the page body. Act on row 40 of a settlements
table and the banner saying it worked renders 1,800 px above the viewport. The user sees
a button stop spinning and nothing else.

This is the one finding here that is closest to a functional bug, and it is the reason to
put a toast layer in: an ops console's feedback has to arrive where the eye already is.

#### C6 — There is no spacing grid
- [x] **Written down** — `src/index.css` (`8300746`). Stating the grid is the whole of this
      item; the off-grid `p-5` and `py-2.5` sites are corrected per screen in Phase 3.


`ZopiqSpacing` is an 8-pt grid — 2, 4, 8, 12, 16, 24, 32, 48 — and says "no magic
numbers". The console uses `p-5` (20), `py-0.5` (2), `mt-1.5` (6), `gap-3` (12),
`py-2.5` (10), `mt-0.5` (2) freely. Most of the visual noise between two adjacent cards
is this.

#### C7 — Five corner radii where the tokens declare two
- [x] **Done** — `src/index.css` and 37 files (`8300746`). 119 literals became `rounded-card`,
      `rounded-field` and `rounded-xs`; `rounded-lg` was Tailwind’s 8px, the field radius named
      by accident. **Four literals stay on purpose** — three `rounded-[6px]` and the
      `rounded-[2px]` veg indicator, none of which is a value ZopiqRadii declares.


`index.css` declares `--radius-card: 12px` and `--radius-field: 8px`. In use:
`rounded-[8px]` ×81, `rounded-[12px]` ×34, `rounded-full` ×17, `rounded-[4px]` ×4,
`rounded-lg` ×4 (`AllOrdersPage:598,602`, `SupportPage:410,414` — Tailwind's 8 px, so
correct by accident, wrong by name), `rounded-[6px]` ×3, `rounded-[2px]` ×1
(`MenuStep:300`).

Neither declared token is ever used as a token. Every one of those 115 radii is a literal.

#### C8 — There is no dark mode

The token package has a full dark palette. The console has zero `dark:` classes. **This is
probably correct and should stay a decision, not a task** — a console read under office
light all day does not need one, and it would double the surface of every other change
here. Recorded so it is not rediscovered.

---

### D. Screen-by-screen notes

Things that belong to one screen rather than to the system.

- **Sign-in** (`SignInPage.tsx:118`) — the first thing anyone sees is an unbranded white
  card: no mark, no wordmark beyond the `<h1>`. And its error is a bare
  `<p className="text-sm text-non-veg">` (`:159`, and again at `:184` and `:221`), not a `Banner` — no `role="alert"`,
  so a screen reader is told nothing when a password is refused.
- **Sidebar** (`AppShell.tsx:14`) — twenty links in five groups. On desktop, good. Below
  `md` the whole thing becomes one horizontal scroller with the group headings hidden, so
  a phone user scrolls a twenty-item strip with no landmarks. The comment still says
  "eleven links"; it has been twenty for a while.
- **Riders** (`RidersPage.tsx:225`) — the only roster screen that is not a table. It is a
  `max-w-3xl` card wrapping a nested `divide-y` list, so the same job (find a person, act
  on them) has a different shape here than on People, Restaurants or Gift catalogue. At
  1,305 lines it is also the largest file in the app.
- **Wizard** (`WizardPage.tsx:107`) — the eight-step bar shows a number and an underline
  and nothing else. There is no completed state, so on step 6 there is no way to see which
  of the first five actually saved. Unreachable steps render at `text-ink-muted/40`, far
  below 3:1.
- **StepFrame** (`StepFrame.tsx:41`) — hand-rolls an error banner rather than using
  `Banner`: no `role="alert"`, no dismiss, and it sits at the *bottom* of the form, so an
  error about the first field appears below the last one.
- **Analytics** (`AnalyticsPage.tsx:228`) — the one chart in the console is a hand-drawn
  800×180 SVG polyline with no axes, no labels, no hover and no accessible text.
- **Bundle** — 712 kB in one chunk. Every admin downloads all 21 screens, the wizard, the
  image adjuster and the map picker to look at the live board. Not a visual defect; it is
  the first thing anybody feels.

---

## Part 2 — The renovation

Six phases, in dependency order. Each one is small enough to review in a sitting and ends
green. Nothing here invents a new visual language — every phase either finishes something
the primitives started or deletes a copy of it.

**The rules this work is held to.** Rule 2 of `ENGINEERING_RULES.md` — no raw hex in
feature code, tokens only. Rule 3 of `CLAUDE.md` — touch only what the phase names.
`packages/zopiq_ui/lib/src/tokens/` stays the source of truth; `index.css` mirrors it and
never leads it.

**One thing blocks Phase 1 and is not mine to decide:** A1, the brand contrast. Everything
else can proceed without an answer.

---

### Phase 1 — The token floor

**Done** (`a66a546`, `7bf1d8e`, `8300746`). All six items landed; item 5’s elevation half
carries over to Phase 4, which is where the shadow gets a consumer.

*Goal: the console's colour, type, spacing and radius all come from a token, and the ones
that fail a contrast threshold stop failing.*

1. **Resolve A1.** Add `--color-brand-ink` (recommended), or record the exception. Applies
   to the primary button fill, the focus ring, active nav text, and the `warn` / `danger` /
   `brand` pill foregrounds.
2. **Fix the focus ring and the input border regardless** — 2.55:1 and 1.21:1 are the two
   that are not about brand expression.
3. **Bundle Figtree** (C2) from `packages/zopiq_ui/assets/fonts/Figtree-Variable.ttf`, as
   a self-hosted `@font-face` with the current stack as fallback. Self-hosted, not Google
   Fonts — the file is already in the repo and the console should not reach the network
   for a typeface.
4. **Mirror the type scale** (C3) into `@theme` as named steps with their line-heights and
   letter-spacing, from `zopiq_typography.dart`.
5. **Mirror the radius and elevation scales** (C4, C7) and make `--radius-card` /
   `--radius-field` real, so `rounded-card` replaces `rounded-[12px]`.
6. **State the spacing grid** (C6) in a comment in `index.css` — Tailwind's default scale
   is already 4-pt, so this is a rule to follow, not a token to add.

**Verify:** every pair in the A1 table at 4.5:1 or better (or listed as an accepted
exception with a reason); `grep -c 'text-sm'` unchanged (Phase 1 changes no page);
`tsc -b`, `vite build`, `oxlint` all clean; the console renders in Figtree.

---

### Phase 2 — The missing primitives

**Done** (`e459c7d`), with one deferral. Seven of the eight landed and three pages moved
onto them — All orders, Platform and Settlements — for 174 insertions against 224 deletions.

**`Icon` did not ship, and the reason is a number.** Phosphor as a web font is 488 kB +
449 kB raw, **376 kB gzipped for 54 glyphs** — twice the console's entire JS bundle. The
Flutter apps get away with bundling it because Flutter's tree-shaker subsets the font to
the codepoints it can prove are reachable; the web has no equivalent. The route that works
is extracting the 54 glyph outlines from the TTF into SVG paths at authoring time, which
is its own piece of work rather than a line in a commit. C1 stays open.

**Two things the build taught, worth keeping:** a sticky `<thead>` cannot live inside
`overflow-x: auto` — CSS computes the other axis to `auto` as well, so the header sticks
to a box that never scrolls vertically and never moves. And `border-collapse` loses a
sticky cell's border, because a collapsed border belongs to the table rather than the cell.
`DataTable` is its own scroller, capped against a `--page-header-h` that `PageHeader`
publishes through a `ResizeObserver` — its height is not a constant, being 87px with a
subtitle and 64px without.


*Goal: nothing in `src/` outside `primitives.tsx` writes a card, a select, a pill, a table
or a pager by hand.*

New, all in `src/ui/`:

| Primitive | Replaces | Fixes |
|---|---|---|
| `DataTable` (+ `Th`, `Td`) | 12 hand-rolled tables | A3, A4, B1 |
| `Select` | 10 raw `<select>` | A2, B3 |
| `SearchField` | 2 copy-pasted search boxes | B3 |
| `Pager` | 3 copy-pasted pagers | B5 |
| `StatTile` | `Tile` + `UsersPage:175` | B7 |
| `Money` | ~30 raw `₹{n}` | A5 |
| `Icon` | nothing — new | C1 |
| `PageBody` | 21 page wrappers | B8 |

`DataTable` carries the row hover, the sticky header, `scope="col"`, the scroll affordance
and one set of paddings. It is the single highest-value component in this document.

`Money` is not decoration: one place that decides `toLocaleString('en-IN')` and
`tabular-nums`, so A5 cannot come back.

`Icon` renders from the Phosphor set already in `packages/zopiq_ui/lib/fonts/` — same
glyphs as the apps, MIT, no dependency.

**Verify:** each primitive lands with at least one page converted to it, and that page's
diff is a deletion. `tsc -b` / `vite build` / `oxlint` clean at every step.

---

### Phase 3 — Convert the pages

**Mostly done** (`bc38bc1`, `6b95e38`). Every page-level table, every page wrapper, every
hand-rolled card and every hand-rolled pill is on a primitive. What is left is listed under
**Still open** below.

**Two tables stay hand-rolled on purpose:** the cash ledger inside a card and the CSV
preview inside the import dialog. Both are sub-tables at their own density (`py-2 pr-4`,
`px-3 py-2`); wrapping either in `DataTable` would give it a border, a radius and a
viewport-height cap it has no business having. Both got `scope="col"`, which was the part
of A4 that actually applied to them.

**One thing the conversion found that the survey missed:** Gift orders and Support each
drew a bordered card *around* a `TableSkeleton`, an `EmptyState` and a table — all three of
which draw their own border. That was a double border before this work and would have been
a triple after it. Both wrappers are gone.

**Closed** (`40673af`). All ten selects are on `Select`; every `<th>` in the console has
`scope`; there are no hand-rolled pills left.

**Five of the ten `Loading…` strings stay, on purpose.** `App.tsx` boots before the shell
exists, so there is no layout to hold open and a skeleton of a screen nobody has chosen yet
is a lie. Hero slides, Map ads and Riders put the word in a `PageHeader` *subtitle*, which
is a sentence about the page rather than a stand-in for its content. The other five — the
two that held a whole page open, and three inside a panel or dialog — are skeletons now.

**`StepFrame` moved its error above the fields**, as well as making it a `Banner`. It had
been a bare `<p>` below the last field and over the save button, so a refusal about the
*first* field announced itself six hundred pixels below it, and — being a `<p>` — announced
itself to a screen reader not at all.


*Goal: the 27 hand-rolled cards, 16 field copies, 7 pills and 12 tables are gone.*

Screen by screen, in this order — busiest first, so the value lands early and the risky
conversions happen after the pattern is proven:

1. Live orders, All orders, Support, Alerts *(the Today group — what gets opened daily)*
2. Settlements, Refunds, Payouts, Cash *(the money group — where A3's hover matters most)*
3. Restaurants, People, Riders, Gift catalogue, Gift orders
4. Coupons, Broadcast, Home hero, Map ads, Platform
5. The wizard and its eight steps, Settings

Per screen: table → `DataTable`; card → `Card`; select → `Select`; pill → `Pill`; money →
`Money`; `Loading…` → skeleton; missing empty state → `EmptyState`; page wrapper →
`PageBody`; add the icons that earn their place (nav, row actions, status).

**Riders** (D) is the one screen that changes shape rather than just parts: it becomes a
`DataTable` like the other rosters. That is a bigger change than the rest of Phase 3 and
should be its own commit.

**Verify:** after each screen, `grep -c 'rounded-\[12px\] border border-line bg-white'`
falls and never rises; the four hand-copied class strings reach zero by the end; build and
lint clean per screen.

---

### Phase 4 — Layout and rhythm

**Done bar one item** (`e638afa`). The content-width rule shipped early, as `PageBody`'s
`width` prop in Phase 3.

**Toasts:** nine screens kept a `note` in state and rendered it as a success banner at the
top of the page body. A success clears itself after six seconds; **a failure never does**,
because a failure nobody read is indistinguishable from a success. The host sits outside
`AppShell`, so a confirmation survives the screen that raised it unmounting — the usual
shape here is act, then navigate away.

**Error banners stay inline, deliberately.** They already carry `role="alert"`, and an
error usually belongs beside the form that produced it rather than in a corner. So do the
banners that *are* content — Riders' two KYC warnings and Cash's limit note describe a
state rather than report an event, which is why they never had an `onDismiss`.

**Still open: the tick on saved wizard steps.** The unreachable-step contrast is fixed
(1.80:1 → 3.08:1), but the tick is not, and the reason is worth keeping. A truthful one has
to come from `checksFor` in `ReviewStep`, which needs the menu the wizard does not load;
inventing a second completeness rule in the step bar is exactly the divergence that file's
own header warns about — *"if the two ever disagree the database wins"*. It needs the
checklist lifted somewhere both can read it, not a guess in the tab strip.


*Goal: two screens of the same kind look the same, at any window width.*

1. **One content-width rule** (B8). Proposal: list and table screens run full-bleed with a
   `max-w-[1600px]` ceiling so a 27-inch monitor does not stretch a nine-column table to
   2000 px; form and detail screens cap at `max-w-2xl`; the wizard's Menu step and Home
   hero cap at `max-w-4xl`. Written into `PageBody` as a `width` prop, so the rule is a
   type rather than a habit, and the `step === 6` magic number goes.
2. **Elevation on the sticky headers** (C4) — a shadow that appears on scroll, on
   `PageHeader` and the wizard's step bar.
3. **Toast layer** (C5). A `ToastProvider` at the app root; success and short errors move
   to it; the banners that *are* the page's content (`RidersPage`'s two KYC warnings,
   `CashPage`'s limit note) stay where they are. The nine `warn`/`success` banners left
   without `onDismiss` in the last audit were left there for exactly that reason — this
   phase is where that distinction gets made properly rather than by omission.
4. **Mobile nav** (D) — below `md`, the twenty-link scroller becomes a disclosure with the
   group headings intact.
5. **Wizard step states** (D) — a tick on saved steps; unreachable steps to a legible
   disabled colour.

**Verify:** every screen at 1280, 1440 and 2560 px, and at 768 px; no horizontal body
scrollbar anywhere; every table's own scroll shows its affordance.

---

### Phase 5 — Identity and the small things

**Done bar the sidebar icons**, which are C1 and still blocked. Everything else landed.

**The favicon is the shipped raster, not a redrawing.** The mark is
`apps/customer/android/app/src/main/res/mipmap-*/ic_launcher.png` — a `#F74E03` square
with a white pin, a Z, a fork and three speed lines in it. Nothing in the repository is
that drawing as vector art, and tracing it here would have given the console its own
slightly-different version of the company mark, which is exactly what the purple `#863bff`
leftover was. So the two files are copies: `favicon-48.png` from `mipmap-mdpi` and
`favicon-192.png` from `mipmap-xxxhdpi`. **Two sizes, because a tab draws the icon at 16
or 32 px** — a 192 px source scaled that far turns the pin's strokes to grey mush and a
48 px source does not. The day somebody draws the mark as an SVG, this is one `<link>` to
change.

**The sign-in mark is the same file the tab loads,** at 56 px above the card, and it is on
`NotAdminPage` too — signing in and being turned away are the same doorway. `alt=""`,
because the heading directly under it already reads "Zopiqnow Console", and announcing the
name twice is worse than skipping a decoration. The three copies of
`<p className="text-sm text-non-veg-ink">{error}</p>` are one `Banner tone="error"`.

**Eight dates were unpinned, not three.** The survey named the three `toLocaleString()`
calls in `AlertsPage`; two `toLocaleTimeString()` calls sit in the same block of the same
component, and `RidersPage`'s KYC dialog has three `toLocaleDateString()` calls with the
same defect — the one place an admin reads back the end date of a KYC override. All eight
go through a local formatter now, which is the shape every other screen already uses. The
verify line below is stricter than the survey's: no bare `toLocale*` call anywhere in
`src/`.

**The count comment landed here; the sidebar icons landed later, under C1.** Three
comments said "eleven links". There are twenty, and have been for some time. The icons were
blocked at the time this phase ran — the font route costs 376 kB gzipped and Phosphor's SVG
set is not in this repository — and were unblocked afterwards by extracting the outlines
from the bundled TTF. See C1.

*Goal: the console looks like Zopiqnow made it.*

1. **Favicon** (A6) — the real mark, from the launcher icon.
2. **Delete `public/icons.svg`** — dead, and by then it is this work's own mess to clean.
3. **Sign-in** (D) — the mark above the card; the error becomes a `Banner`.
4. **Alerts' three dates** (A5) pinned to `en-IN`.
5. **Sidebar** — icons per link, and the stale "eleven links" comment corrected.

**Verify:** the tab icon is orange; `grep -rn "toLocale[A-Za-z]*()" src/` returns nothing.

---

### Phase 6 — Weight

**Done** — the initial download is **139 kB gzipped**, from 192 kB. The doc asked for under
250 kB, so this clears it with room; the twenty screens that are not the live board come
down as their own chunks, the largest being the wizard at 15.7 kB gzipped.

**The live board is not a chunk.** It is the landing route, and lazy-loading the screen
somebody always lands on buys nothing and costs a round trip. The shell, the primitives,
`api.ts` and the board are the first download; everything else is fetched on the click.

**Nineteen `lazy()` calls written out rather than folded into a helper.** A generic
`named(name, load)` has to type the module as components-only, which stops being true the
moment a screen also exports a constant — and `import()` has to be statically visible in
the source for the bundler to cut a chunk from it at all. Verbose beats clever here.

**The fallback is the console's own frame with the real screen name already in it.** The
nav knows where you clicked, so `currentLink(pathname)` fills the header while the chunk is
in the air; the screen then draws its own skeleton while it queries, so a navigation reads
as one continuous load instead of a blank flash followed by a header dropping in. That
needed `groups` and `currentLink` out of `AppShell.tsx` and into `src/ui/nav.ts` — two
files want them now, and oxlint's `react(only-export-components)` is right that a file
exporting both components and plain functions breaks fast refresh.

**Splitting bought one new way to fail, so it comes with its cure.** A single bundle either
loaded or did not; twenty chunks can each 404 on their own, most often because the console
was redeployed while an admin had the tab open and the hashed filename it is asking for is
last week's. React's answer to a rejected `lazy` import is to unmount the tree — a white
page mid-shift. `src/ui/RouteBoundary.tsx` catches it and offers a reload, which for a
stale chunk is genuinely the fix. It clears itself on navigation via `getDerivedStateFromProps`
rather than by being keyed from outside, so a working screen is not remounted on every
click just to reset an error it never had. It is the console's only error boundary; there
was none before, because before there was nothing for one to catch.

**What was verified and what was not.** `tsc -b`, `vite build` and `oxlint` are green;
`dist/index.html` preloads only the entry and the CSS, so a hard reload on `/` provably
does not fetch the wizard; `vite preview` serves `/`, `/orders`, `/restaurants/new`,
`/settings` and `/gifts` at 200 and every chunk is fetchable. **Clicking all twenty-one
routes in a browser is still a manual step** — there is no headless browser in this
toolchain and adding one is a dependency change.

*Goal: the console opens fast enough that nobody notices it opening.*

Route-level `React.lazy` on the twenty-one screens. The live board, the shell and the
primitives are the initial chunk; the wizard, the image adjuster and the map picker load
when somebody onboards a restaurant.

**Verify:** initial chunk under 250 kB gzipped *(139 kB)*; every route still reachable; a
hard reload on `/` does not fetch the wizard *(`dist/index.html` references neither)*.

---

## What this does not touch

- **Dark mode** (C8) — a decision, and the decision is no.
- **`packages/zopiq_ui/`** — read from, never written to, except the one token addition
  Phase 1 may need, which is a decision above the console.
- **Anything below the UI.** No RPC, no migration, no query. If a phase seems to need one,
  it has left its lane.
- **Pagination for the nine unpaginated tables** (B5) — the `Pager` primitive is built in
  Phase 2 and applied to the three screens that already have one. Which other lists need
  it is a product question at a scale we are not at yet.

---

## Ledger

Tick as they land.

**Part 1 — measurably wrong**
- [x] A1 — brand contrast *(decided: keep the orange, darken the label — 21/21 pairs pass)*
- [x] A2 — `<select>` focus *(all 10 call sites)*
- [x] A3 — table hover + sticky header *(all 10 page-level tables)*
- [x] A4 — `scope="col"` *(every `<th>` in the console has it)*
- [x] A5 — money *(49 sites through `inr`/`inrSigned`)* and all 8 unpinned dates
- [x] A6 — favicon *(the real mark, at 48 and 192 px)*; the dead sprite deleted
- [x] A7 — the toggle's two states *(2.55 → 4.88 on, 1.21 → 3.24 off)*

**Part 2 — inconsistent**
- [x] B1 — twelve tables → one *(10 converted, 2 sub-tables deliberately not)*
- [x] B2 — 27 hand-rolled cards *(12 more on `Card`; 4 changed padding to p-6)*
- [x] B3 — 16 field copies
- [x] B4 — seven hand-rolled pills
- [x] B5 — three pagers → one
- [x] B6 — `Loading…`, skeletons, empty states *(5 of 10 kept, with reasons)*
- [x] B7 — two stat tiles → one
- [x] B8 — page padding and content width *(`PageBody` on 16 pages)*

**Part 3 — missing**
- [x] C1 — icons *(20 Phosphor glyphs extracted from the bundled TTF, 10 kB gzipped
      against the font's 376; one per sidebar link, each one checked by eye)*
- [x] C2 — Figtree
- [x] C3 — type scale
- [x] C4 — elevation *(scale mirrored; `PageHeader` lifts on scroll)*
- [x] C5 — toasts *(9 screens; errors stay inline on purpose)*
- [x] C6 — spacing grid *(stated; per-screen corrections in Phase 3)*
- [x] C7 — radii
- [x] C8 — dark mode *(decided: no)*

**Part 4 — per screen**
- [~] D — sidebar (mobile disclosure, link count, icons per link), step frame, the
      wizard’s step contrast, sign-in and the bundle done; the Riders table shape and the
      chart still open
