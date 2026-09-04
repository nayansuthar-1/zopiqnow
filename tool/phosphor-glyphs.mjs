/// Pulls a named set of Phosphor glyphs out of the bundled TTF as SVG paths.
///
/// The admin console needs icons and has two ways to get them, both of which
/// the renovation doc recorded as blocked: shipping the whole font costs
/// 376 kB gzipped for twenty pictures, and hand-writing Phosphor's path data
/// means drawing from memory and calling the result Phosphor. This is the third
/// way — read the outlines out of the file the three Flutter apps already
/// bundle, so the console's icons are the same drawings by construction rather
/// than by resemblance.
///
/// No dependency: a TrueType `glyf` table is a documented binary format and the
/// part of it these glyphs use is small. Run it when the icon list changes; the
/// output is committed.
///
///   node tool/phosphor-glyphs.mjs
import fs from 'node:fs'

const TTF = 'packages/zopiq_ui/lib/fonts/Phosphor-Regular.ttf'
const OUT = 'apps/admin-web/src/ui/icons.ts'

/// The console's icons, as {name in the generated file: codepoint}. Every
/// codepoint here is copied from
/// packages/zopiq_ui/lib/src/tokens/zopiq_icons.dart, which is the product's
/// icon table — a name that is not in that file is a picture the apps do not
/// use, and the two sets are not allowed to drift.
/// Exactly the twenty the sidebar draws, and nothing held in reserve — an
/// unused glyph is bytes in the bundle and a picture nobody has checked.
const WANTED = {
  cookingPot: 0xe764,
  receipt: 0xe3ec,
  chat: 0xe168,
  warning: 0xe4e2,
  gift: 0xe276,
  trendUp: 0xe4ae,
  storefront: 0xe470,
  plus: 0xe3d4,
  moped: 0xe824,
  user: 0xe4c2,
  sparkle: 0xe6a2,
  star: 0xe46a,
  mapPin: 0xe316,
  tag: 0xe478,
  bellRinging: 0xe5e8,
  refresh: 0xe036,
  forkKnife: 0xe262,
  wallet: 0xe68a,
  checkCircle: 0xe184,
  sliders: 0xe434,
}

const buf = fs.readFileSync(TTF)
const u8 = (o) => buf.readUInt8(o)
const u16 = (o) => buf.readUInt16BE(o)
const i16 = (o) => buf.readInt16BE(o)
const u32 = (o) => buf.readUInt32BE(o)

// ── Table directory ────────────────────────────────────────────────────────
const tables = {}
const numTables = u16(4)
for (let i = 0; i < numTables; i++) {
  const p = 12 + i * 16
  tables[buf.toString('ascii', p, p + 4)] = { off: u32(p + 8), len: u32(p + 12) }
}
for (const t of ['head', 'maxp', 'loca', 'glyf', 'cmap']) {
  if (!tables[t]) throw new Error(`${TTF} has no ${t} table`)
}

const unitsPerEm = u16(tables.head.off + 18)
const yMax = i16(tables.head.off + 42)
const indexToLocFormat = i16(tables.head.off + 50)
const numGlyphs = u16(tables.maxp.off + 4)

// ── cmap: codepoint → glyph id ─────────────────────────────────────────────
/// Format 4 only. Phosphor's codepoints live in the private use area below
/// 0xFFFF, so the BMP subtable is the whole story; a format 12 font would need
/// more code and this one is not that.
function cmapLookup() {
  const base = tables.cmap.off
  let sub = null
  for (let i = 0; i < u16(base + 2); i++) {
    const rec = base + 4 + i * 8
    const platform = u16(rec)
    const encoding = u16(rec + 2)
    if ((platform === 3 && (encoding === 1 || encoding === 0)) || platform === 0) {
      const off = base + u32(rec + 4)
      if (u16(off) === 4) {
        sub = off
        break
      }
    }
  }
  if (sub === null) throw new Error('no format 4 cmap subtable')

  const segX2 = u16(sub + 6)
  const ends = sub + 14
  const starts = ends + segX2 + 2
  const deltas = starts + segX2
  const ranges = deltas + segX2

  return (cp) => {
    for (let s = 0; s < segX2; s += 2) {
      if (u16(ends + s) < cp) continue
      if (u16(starts + s) > cp) return 0
      const ro = u16(ranges + s)
      if (ro === 0) return (cp + i16(deltas + s)) & 0xffff
      const gi = u16(ranges + s + ro + (cp - u16(starts + s)) * 2)
      return gi === 0 ? 0 : (gi + i16(deltas + s)) & 0xffff
    }
    return 0
  }
}

// ── loca: glyph id → offset into glyf ──────────────────────────────────────
const locaAt = (i) =>
  indexToLocFormat === 0
    ? u16(tables.loca.off + i * 2) * 2
    : u32(tables.loca.off + i * 4)

/// The contours of one glyph, in font units, as arrays of {x, y, on}.
///
/// Composite glyphs are resolved by pulling in their components. Phosphor's
/// icons are simple ones, but the two component forms this does not handle
/// throw rather than draw something subtly wrong.
function contoursOf(gid, depth = 0) {
  if (depth > 5) throw new Error('composite glyph nested too deep')
  const start = locaAt(gid)
  if (locaAt(gid + 1) === start) return [] // empty glyph, e.g. space
  const g = tables.glyf.off + start
  const n = i16(g)

  if (n < 0) {
    const out = []
    let p = g + 10
    for (;;) {
      const flags = u16(p)
      const glyphIndex = u16(p + 2)
      p += 4
      let dx, dy
      if (flags & 1) {
        dx = i16(p)
        dy = i16(p + 2)
        p += 4
      } else {
        dx = buf.readInt8(p)
        dy = buf.readInt8(p + 1)
        p += 2
      }
      if (!(flags & 2)) throw new Error(`glyph ${gid}: point-matched component`)
      if (flags & (8 | 0x40 | 0x80)) throw new Error(`glyph ${gid}: scaled component`)
      for (const c of contoursOf(glyphIndex, depth + 1)) {
        out.push(c.map((pt) => ({ ...pt, x: pt.x + dx, y: pt.y + dy })))
      }
      if (!(flags & 0x20)) break
    }
    return out
  }

  const endPts = []
  for (let i = 0; i < n; i++) endPts.push(u16(g + 10 + i * 2))
  const numPts = n === 0 ? 0 : endPts[n - 1] + 1
  let p = g + 10 + n * 2
  p += 2 + u16(p) // skip the hinting instructions

  const flags = []
  while (flags.length < numPts) {
    const f = u8(p++)
    flags.push(f)
    if (f & 8) {
      let r = u8(p++)
      while (r-- > 0) flags.push(f)
    }
  }

  // x and y are delta-encoded, and each axis has a "short" bit and a bit that
  // means either "positive" (when short) or "same as the last one" (when not).
  const read = (shortBit, sameBit) => {
    const vals = []
    let v = 0
    for (const f of flags) {
      if (f & shortBit) {
        const d = u8(p++)
        v += f & sameBit ? d : -d
      } else if (!(f & sameBit)) {
        v += i16(p)
        p += 2
      }
      vals.push(v)
    }
    return vals
  }
  const xs = read(2, 16)
  const ys = read(4, 32)

  const out = []
  let from = 0
  for (const end of endPts) {
    const c = []
    for (let i = from; i <= end; i++) {
      c.push({ x: xs[i], y: ys[i], on: !!(flags[i] & 1) })
    }
    out.push(c)
    from = end + 1
  }
  return out
}

/// One contour as SVG path commands.
///
/// TrueType is quadratic and lets two control points sit next to each other
/// with the on-curve point between them left out, so a run of off-curve points
/// implies a midpoint between each pair. Rotating the contour to start on an
/// on-curve point means the loop never has to special-case where it began.
function toPath(contour) {
  if (contour.length === 0) return ''
  let pts = contour
  const startIdx = pts.findIndex((p) => p.on)
  if (startIdx === -1) {
    // Every point is off-curve. The real start is then the midpoint of the last
    // and the first — a shape TrueType allows, and Phosphor's circles use it.
    const last = pts[pts.length - 1]
    pts = [{ x: (pts[0].x + last.x) / 2, y: (pts[0].y + last.y) / 2, on: true }, ...pts]
  } else {
    pts = pts.slice(startIdx).concat(pts.slice(0, startIdx))
  }

  // Rounded to whole font units. The em is 1024 wide and these are drawn at
  // 16-20 px, so one unit is a fiftieth of a pixel — keeping two decimals would
  // buy nothing visible and cost a third of the file.
  const r = (n) => Math.round(n)
  const out = [`M${r(pts[0].x)} ${r(pts[0].y)}`]
  let i = 1
  while (i <= pts.length) {
    const cur = pts[i % pts.length]
    if (cur.on) {
      out.push(`L${r(cur.x)} ${r(cur.y)}`)
      i++
      continue
    }
    const next = pts[(i + 1) % pts.length]
    const end = next.on ? next : { x: (cur.x + next.x) / 2, y: (cur.y + next.y) / 2 }
    out.push(`Q${r(cur.x)} ${r(cur.y)} ${r(end.x)} ${r(end.y)}`)
    i += next.on ? 2 : 1
  }
  out.push('Z')
  return out.join('')
}

const lookup = cmapLookup()
const entries = []
for (const [name, cp] of Object.entries(WANTED)) {
  const gid = lookup(cp)
  if (!gid || gid >= numGlyphs) {
    throw new Error(`${name} (0x${cp.toString(16)}) is not in the font`)
  }
  const contours = contoursOf(gid)
  if (contours.length === 0) {
    throw new Error(`${name} (0x${cp.toString(16)}) is an empty glyph`)
  }
  // y is negated here, not at render time: SVG counts down and a font counts
  // up, and doing it once in the data means the component is a plain <svg>
  // with no transform on it.
  const d = contours
    .map((c) => toPath(c.map((p) => ({ ...p, y: -p.y }))))
    .join('')
  entries.push([name, d])
}

// One viewBox for all of them, off the font's own metrics rather than each
// glyph's bounding box — per-glyph boxes would scale every icon to fill its
// square, so a full-height house would come out the same size as a short dash.
const viewBox = `0 ${-yMax} ${unitsPerEm} ${unitsPerEm}`

const header = `/// Phosphor glyphs, as path data.
///
/// **Generated. Do not hand-edit — run \`node tool/phosphor-glyphs.mjs\`.**
///
/// C1 in the renovation doc called the console's total absence of icons its
/// biggest missing piece and recorded the two obvious routes as blocked:
/// \`@font-face\` on Phosphor-Regular.ttf costs 376 kB gzipped to draw twenty
/// pictures, and writing the paths by hand means drawing from memory and
/// labelling the result Phosphor. This is neither. The generator reads the
/// outlines straight out of the TTF the three Flutter apps bundle, so these are
/// the same drawings the apps use — by construction, not by resemblance.
///
/// Phosphor Icons is MIT; the licence travels with the font at
/// packages/zopiq_ui/lib/fonts/PHOSPHOR-LICENSE.txt.
///
/// The codepoints live in packages/zopiq_ui/lib/src/tokens/zopiq_icons.dart,
/// which is the product's icon table. Adding an icon here means adding it to
/// WANTED in the generator, and only from a name that table already has.

export const ICON_VIEWBOX = '${viewBox}'

export const icons = {
`
const body = entries.map(([n, d]) => `  ${n}: '${d}',`).join('\n')
const footer = `
} as const

export type IconName = keyof typeof icons
`
fs.writeFileSync(OUT, (header + body + footer).replace(/\n/g, '\r\n'))

const bytes = entries.reduce((n, [, d]) => n + d.length, 0)
console.log(`unitsPerEm=${unitsPerEm} yMax=${yMax} viewBox="${viewBox}"`)
console.log(`${entries.length} glyphs, ${bytes} bytes of path data → ${OUT}`)
