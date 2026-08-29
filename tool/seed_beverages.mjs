// The eight bottled drinks every kitchen sells, and the artwork that stands in
// for them until real packshots arrive.
//
// **Why we draw these rather than download them.** A menu card wants a clean
// product shot on a plain ground, eight of them consistent with each other.
// Wikimedia Commons has no such set — its Mirinda is a hand holding a bottle in
// a garden, its Limca a dusty shop shelf, its Sprite 250px wide — and the
// bottlers' own photography is theirs, not ours to take. So each drink gets a
// drawn bottle in its own colours: no logo, no wordmark, nothing borrowed. The
// dish name under the card is what says "Coca Cola"; the picture only has to say
// "a cold bottle of something dark red-capped".
//
// **They are meant to be replaced.** Every upload is signed with a deterministic
// `public_id` (`zopiqnow/beverages/<slug>`) and `overwrite=true`, so dropping in
// a real photograph later is this same script pointed at a file — same URL, no
// database change, no migration. That is the whole reason not to use the
// unsigned preset here, which mints a random id per upload and would leave the
// old art orphaned and the new art unreferenced.
//
// Usage:
//   node tool/seed_beverages.mjs            # draw and upload all eight
//   node tool/seed_beverages.mjs --dry-run  # write the SVGs locally, upload nothing
//   node tool/seed_beverages.mjs --sql      # print the image_url map as SQL

import { createHash } from 'node:crypto'
import { writeFile, mkdir } from 'node:fs/promises'
import path from 'node:path'

import { loadEnv } from './env.mjs'

// ---------------------------------------------------------------------------
// The drinks.
// ---------------------------------------------------------------------------
// `liquid` is what is in the bottle, `label` the band around its middle, `cap`
// the closure. Sprite and 7 Up are both clear-and-green and Fanta and Mirinda
// both orange, so each pair is pulled apart deliberately — Sprite's darker
// green against 7 Up's brighter one, Fanta's red-orange against Mirinda's
// yellow-orange — rather than rendering two identical cards.
const DRINKS = [
  { slug: 'coca-cola', name: 'Coca Cola', liquid: '#3B1A10', label: '#E4002B', cap: '#E4002B' },
  { slug: 'thums-up', name: 'Thums Up', liquid: '#3B1A10', label: '#C8102E', cap: '#003876' },
  { slug: 'sprite', name: 'Sprite', liquid: '#E4F3E7', label: '#006F44', cap: '#006F44' },
  { slug: 'limca', name: 'Limca', liquid: '#EAF4E4', label: '#0E7A3C', cap: '#E4002B' },
  { slug: 'fanta', name: 'Fanta', liquid: '#F26522', label: '#F26522', cap: '#F26522' },
  { slug: 'mirinda', name: 'Mirinda', liquid: '#FFA400', label: '#FF8200', cap: '#F57C00' },
  { slug: '7up', name: '7Up', liquid: '#E8F5E9', label: '#00A94F', cap: '#00A94F' },
  { slug: 'maaza', name: 'Maaza', liquid: '#F2A32C', label: '#F08C1A', cap: '#14532D' },
]

// ---------------------------------------------------------------------------
// The drawing.
// ---------------------------------------------------------------------------
// A PET bottle as one closed path — neck, shouldered flare, body, radiused base
// — with the liquid clipped inside it and a label band clipped to the same
// shape so it wraps rather than sticking out at the sides. No text anywhere:
// Cloudinary's rasteriser has no fonts of ours to render with, and a wordmark is
// the one part of a drink that is not ours to draw.
const BOTTLE = [
  'M 364 152',
  'L 436 152',
  'L 436 212',
  'C 436 252, 500 262, 500 322',
  'L 500 662',
  'Q 500 702, 460 702',
  'L 340 702',
  'Q 300 702, 300 662',
  'L 300 322',
  'C 300 262, 364 252, 364 212',
  'Z',
].join(' ')

function svgFor({ liquid, label, cap }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="800" viewBox="0 0 800 800">
  <defs>
    <linearGradient id="ground" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="100%" stop-color="#F1F2F4"/>
    </linearGradient>
    <radialGradient id="tint" cx="50%" cy="42%" r="52%">
      <stop offset="0%" stop-color="${label}" stop-opacity="0.10"/>
      <stop offset="100%" stop-color="${label}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="fill" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="${liquid}" stop-opacity="0.82"/>
      <stop offset="38%" stop-color="${liquid}"/>
      <stop offset="100%" stop-color="${liquid}" stop-opacity="0.88"/>
    </linearGradient>
    <linearGradient id="band" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="${label}" stop-opacity="0.88"/>
      <stop offset="40%" stop-color="${label}"/>
      <stop offset="100%" stop-color="${label}" stop-opacity="0.90"/>
    </linearGradient>
    <clipPath id="body"><path d="${BOTTLE}"/></clipPath>
  </defs>

  <rect width="800" height="800" fill="url(#ground)"/>
  <rect width="800" height="800" fill="url(#tint)"/>

  <!-- The bottle sits on something, or it floats. -->
  <ellipse cx="400" cy="716" rx="128" ry="17" fill="#0B0F19" opacity="0.10"/>

  <!-- Glass first, so a pale drink still reads as a bottle and not a smudge. -->
  <path d="${BOTTLE}" fill="#FFFFFF" opacity="0.96"/>

  <g clip-path="url(#body)">
    <!-- Filled to just under the shoulder: a full-to-the-cap bottle looks wrong. -->
    <rect x="290" y="238" width="220" height="474" fill="url(#fill)"/>
    <!-- The band is bracketed rather than laid straight on the liquid: on the
         orange drinks an orange label against orange juice vanishes, and a
         hairline of glass above and below is what a real wrapper leaves. -->
    <rect x="292" y="398" width="216" height="6" fill="#FFFFFF" opacity="0.75"/>
    <rect x="292" y="404" width="216" height="150" fill="url(#band)"/>
    <rect x="292" y="554" width="216" height="6" fill="#FFFFFF" opacity="0.75"/>
    <!-- One soft highlight down the left, which is what makes it look round. -->
    <rect x="330" y="250" width="26" height="440" rx="13" fill="#FFFFFF" opacity="0.30"/>
    <rect x="466" y="300" width="12" height="360" rx="6" fill="#FFFFFF" opacity="0.14"/>
  </g>

  <path d="${BOTTLE}" fill="none" stroke="#0B0F19" stroke-opacity="0.10" stroke-width="2"/>

  <!-- Neck ring and cap. -->
  <rect x="360" y="146" width="80" height="12" rx="6" fill="${cap}" opacity="0.55"/>
  <rect x="358" y="96" width="84" height="56" rx="8" fill="${cap}"/>
  <rect x="368" y="104" width="12" height="40" rx="6" fill="#FFFFFF" opacity="0.26"/>
</svg>`
}

// ---------------------------------------------------------------------------
// The upload.
// ---------------------------------------------------------------------------
// Signed, because the unsigned preset invents a `public_id` per call and a
// re-run would silently duplicate all eight assets rather than replacing them.
// The signature covers every parameter except `file`, `api_key` and
// `resource_type`, sorted by key.
function sign(params, secret) {
  const base = Object.keys(params)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('&')
  return createHash('sha1').update(base + secret).digest('hex')
}

async function upload(slug, svg, { cloud, key, secret }) {
  const params = {
    format: 'jpg', // rasterise on the way in — Image.network gets no say in SVG
    // Purge the CDN copy. Without this an overwrite is invisible for hours:
    // the first pass of these drawings was re-uploaded and the old art kept
    // being served, which is exactly what would happen the day real
    // photographs replace them.
    invalidate: 'true',
    overwrite: 'true',
    public_id: `zopiqnow/beverages/${slug}`,
    timestamp: String(Math.floor(Date.now() / 1000)),
  }
  const form = new FormData()
  form.set('file', `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`)
  form.set('api_key', key)
  form.set('signature', sign(params, secret))
  for (const [k, v] of Object.entries(params)) form.set(k, v)

  const res = await fetch(`https://api.cloudinary.com/v1_1/${cloud}/image/upload`, {
    method: 'POST',
    body: form,
  })
  const body = await res.json()
  if (!res.ok) {
    throw new Error(`${slug}: ${res.status} ${body?.error?.message ?? JSON.stringify(body)}`)
  }
  // Deliberately NOT `body.secure_url`, which carries a `/v<version>/` segment
  // that changes on every upload. `menu_items.image_url` should name the drink,
  // not this particular rendering of it — so replacing the artwork stays a
  // re-run of this script with no UPDATE to follow it. `invalidate` above is
  // what makes the un-versioned URL safe to cache.
  return `https://res.cloudinary.com/${cloud}/image/upload/zopiqnow/beverages/${slug}.jpg`
}

// ---------------------------------------------------------------------------
async function main() {
  await loadEnv()
  const dryRun = process.argv.includes('--dry-run')
  const asSql = process.argv.includes('--sql')

  const out = path.resolve(import.meta.dirname, '..', 'build', 'beverages')
  if (dryRun) await mkdir(out, { recursive: true })

  const creds = {
    cloud: process.env.CLOUDINARY_CLOUD_NAME,
    key: process.env.CLOUDINARY_API_KEY,
    secret: process.env.CLOUDINARY_API_SECRET,
  }
  if (!dryRun && (!creds.cloud || !creds.key || !creds.secret)) {
    throw new Error('CLOUDINARY_CLOUD_NAME / _API_KEY / _API_SECRET missing from .env')
  }

  const urls = {}
  for (const drink of DRINKS) {
    const svg = svgFor(drink)
    if (dryRun) {
      await writeFile(path.join(out, `${drink.slug}.svg`), svg, 'utf8')
      urls[drink.slug] = `(dry run) ${drink.slug}.svg`
    } else {
      // Cloudinary's `fetch` has thrown a bare "fetch failed" on a first call
      // before and succeeded on a retry, so one retry rather than a red run.
      let url
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          url = await upload(drink.slug, svg, creds)
          break
        } catch (err) {
          if (attempt === 3) throw err
          await new Promise((r) => setTimeout(r, 1500 * attempt))
        }
      }
      urls[drink.slug] = url
    }
    console.error(`${drink.name.padEnd(12)} ${urls[drink.slug]}`)
  }

  if (asSql) {
    console.log('-- image_url per drink, generated by tool/seed_beverages.mjs')
    for (const d of DRINKS) console.log(`--   ${d.name.padEnd(12)} ${urls[d.slug]}`)
  }
}

main().catch((err) => {
  console.error(err.message)
  process.exit(1)
})
