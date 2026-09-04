/// Renders the extracted glyphs to a PNG so a person can look at them.
///
/// The generator reads a binary format by hand. A bug in it does not throw — it
/// draws the wrong picture, quietly, and the console ships twenty icons nobody
/// ever looked at. So this rasterises the committed path data to a contact
/// sheet, which is the only check that actually catches a mangled contour.
///
///   node tool/phosphor-preview.mjs [out.png]
import fs from 'node:fs'
import zlib from 'node:zlib'

const src = fs.readFileSync('apps/admin-web/src/ui/icons.ts', 'utf8')
const viewBox = /ICON_VIEWBOX = '([^']+)'/.exec(src)[1].split(' ').map(Number)
const glyphs = [...src.matchAll(/^ {2}(\w+): '([^']+)',$/gm)].map((m) => [m[1], m[2]])
if (glyphs.length === 0) throw new Error('no glyphs found in icons.ts')

const CELL = 64
const PAD = 6
const COLS = 5
const rows = Math.ceil(glyphs.length / COLS)
const W = COLS * CELL
const H = rows * CELL

/// Path string → polygons, with the quadratics flattened. 12 segments a curve
/// is far more than a 64px cell can show and keeps this loop trivial.
function flatten(d, sx, sy, ox, oy) {
  const polys = []
  let cur = []
  let x = 0
  let y = 0
  const P = (px, py) => [ox + (px - viewBox[0]) * sx, oy + (py - viewBox[1]) * sy]
  for (const m of d.matchAll(/([MLQZ])([-\d. ]*)/g)) {
    const n = m[2].trim().split(/[ ]+/).filter(Boolean).map(Number)
    if (m[1] === 'M') {
      if (cur.length) polys.push(cur)
      cur = [P(n[0], n[1])]
      x = n[0]; y = n[1]
    } else if (m[1] === 'L') {
      cur.push(P(n[0], n[1]))
      x = n[0]; y = n[1]
    } else if (m[1] === 'Q') {
      for (let t = 1; t <= 12; t++) {
        const u = t / 12
        const k = 1 - u
        cur.push(P(k * k * x + 2 * k * u * n[0] + u * u * n[2], k * k * y + 2 * k * u * n[1] + u * u * n[3]))
      }
      x = n[2]; y = n[3]
    } else if (m[1] === 'Z' && cur.length) {
      polys.push(cur)
      cur = []
    }
  }
  if (cur.length) polys.push(cur)
  return polys
}

// Greyscale canvas, white ground.
const px = new Uint8Array(W * H).fill(255)

/// Nonzero winding, sampled 3x3 per pixel — TrueType fills nonzero, and an
/// even-odd rasteriser would punch holes in every solid icon that happens to
/// have two contours wound the same way.
function fill(polys, x0, y0, size) {
  const S = 3
  for (let py = y0; py < y0 + size; py++) {
    for (let pxi = x0; pxi < x0 + size; pxi++) {
      let hits = 0
      for (let sy = 0; sy < S; sy++) {
        const yy = py + (sy + 0.5) / S
        for (let sx = 0; sx < S; sx++) {
          const xx = pxi + (sx + 0.5) / S
          let wind = 0
          for (const poly of polys) {
            for (let i = 0; i < poly.length; i++) {
              const a = poly[i]
              const b = poly[(i + 1) % poly.length]
              if (a[1] <= yy) {
                if (b[1] > yy && (b[0] - a[0]) * (yy - a[1]) - (xx - a[0]) * (b[1] - a[1]) > 0) wind++
              } else if (b[1] <= yy) {
                if ((b[0] - a[0]) * (yy - a[1]) - (xx - a[0]) * (b[1] - a[1]) < 0) wind--
              }
            }
          }
          if (wind !== 0) hits++
        }
      }
      if (hits) px[py * W + pxi] = Math.round(255 - (255 * hits) / (S * S))
    }
  }
}

glyphs.forEach(([, d], i) => {
  const cx = (i % COLS) * CELL
  const cy = Math.floor(i / COLS) * CELL
  const size = CELL - PAD * 2
  const s = size / viewBox[2]
  fill(flatten(d, s, s, cx + PAD, cy + PAD), cx, cy, CELL)
})

// ── PNG, 8-bit greyscale ───────────────────────────────────────────────────
const raw = Buffer.alloc((W + 1) * H)
for (let y = 0; y < H; y++) {
  raw[y * (W + 1)] = 0 // filter: none
  Buffer.from(px.subarray(y * W, y * W + W)).copy(raw, y * (W + 1) + 1)
}
const chunk = (type, data) => {
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length)
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(zlib.crc32(body) >>> 0)
  return Buffer.concat([len, body, crc])
}
const ihdr = Buffer.alloc(13)
ihdr.writeUInt32BE(W, 0)
ihdr.writeUInt32BE(H, 4)
ihdr[8] = 8 // bit depth
ihdr[9] = 0 // greyscale
const out = process.argv[2] ?? 'tool/.phosphor-preview.png'
fs.writeFileSync(
  out,
  Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]),
)
console.log(`${glyphs.length} glyphs → ${out} (${W}x${H})`)
console.log(glyphs.map(([n]) => n).join(', '))
