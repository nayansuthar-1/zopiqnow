// Uploads an .aab to Google Play and assigns it to a track.
//
// **No dependencies, deliberately.** The obvious way to do this is fastlane
// (Ruby, not installed here) or googleapis (a large npm tree for four HTTP
// calls). What the Play Developer API actually wants is a service-account JWT
// exchanged for an access token, and Node signs RS256 out of `node:crypto`
// without help — so the whole client is this file, and there is no dependency
// to keep current or to audit.
//
// The credential is a service-account JSON key, read from a path in .env. It is
// never in the repo, which is not a style preference: **this repository is
// public**, and a Play service-account key is upload access to the app.
//
// Usage:  node tool/play_upload.mjs <app> <track>
//   app    customer | vendor | rider
//   track  internal | alpha | beta | production
//
// The four calls, in order: open an edit, upload the bundle, point a track at
// its versionCode, commit the edit. Nothing is visible on Play until the commit
// — an edit that fails halfway leaves the listing exactly as it was.

import { createSign } from 'node:crypto'
import { readFile, stat } from 'node:fs/promises'
import path from 'node:path'

const APPS = ['customer', 'vendor', 'rider']
const TRACKS = ['internal', 'alpha', 'beta', 'production']

const [app, track] = process.argv.slice(2)
if (!APPS.includes(app) || !TRACKS.includes(track)) {
  console.error('usage: node tool/play_upload.mjs <customer|vendor|rider> <internal|alpha|beta|production>')
  process.exit(1)
}

const keyPath = process.env.PLAY_SERVICE_ACCOUNT_JSON
if (!keyPath) {
  console.error(
    'PLAY_SERVICE_ACCOUNT_JSON is not set. Put the path to the service-account\n' +
      'key in .env (the file itself must live outside the repo — this repo is public).',
  )
  process.exit(1)
}

const key = JSON.parse(await readFile(keyPath, 'utf8'))
const root = path.resolve(import.meta.dirname, '..')
const aab = path.join(root, 'apps', app, 'build/app/outputs/bundle/release/app-release.aab')

// A stale bundle is the one failure mode that looks like success: it uploads,
// Play accepts it, and the change you meant to ship is not in it. Ten minutes is
// long enough for a slow release build and short enough to catch yesterday's.
const built = await stat(aab).catch(() => null)
if (!built) {
  console.error(`No bundle at ${aab}\nRun: flutter build appbundle --release`)
  process.exit(1)
}
const ageMinutes = (Date.now() - built.mtimeMs) / 60000
if (ageMinutes > 10) {
  console.error(
    `That bundle is ${Math.round(ageMinutes)} minutes old — older than this run.\n` +
      'Rebuild it before uploading, or you will ship the previous build.',
  )
  process.exit(1)
}

// Read out of the Gradle file rather than kept in a table here. The package name
// is what Play identifies the app by, and a copy of it in this script is a copy
// free to go stale — uploading to the wrong listing, or to one that does not
// exist, on the day somebody renames a module.
const gradle = await readFile(
  path.join(root, 'apps', app, 'android/app/build.gradle.kts'),
  'utf8',
)
const applicationId = gradle.match(/applicationId\s*=\s*"([^"]+)"/)?.[1]
if (!applicationId) {
  console.error(`Could not read applicationId from ${app}'s build.gradle.kts`)
  process.exit(1)
}
const packageName = applicationId

// --- Auth: a self-signed JWT, exchanged for an access token -----------------
function base64url(input) {
  return Buffer.from(input).toString('base64url')
}

async function accessToken() {
  const now = Math.floor(Date.now() / 1000)
  const claims = {
    iss: key.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }
  const unsigned =
    `${base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.` +
    `${base64url(JSON.stringify(claims))}`
  const signature = createSign('RSA-SHA256')
    .update(unsigned)
    .sign(key.private_key)
    .toString('base64url')

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${signature}`,
    }),
  })
  const body = await res.json()
  if (!res.ok) throw new Error(`Token: ${body.error_description ?? res.status}`)
  return body.access_token
}

// --- The API ----------------------------------------------------------------
const token = await accessToken()
const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}`

async function api(url, { method = 'GET', body, headers = {} } = {}) {
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, ...headers },
    body,
  })
  const text = await res.text()
  const parsed = text ? JSON.parse(text) : {}
  if (!res.ok) {
    // Play's own sentence. "APK specifies a version code that has already been
    // used" is a one-line fix if you can read it and a mystery if you cannot.
    throw new Error(parsed.error?.message ?? `${res.status} ${text.slice(0, 300)}`)
  }
  return parsed
}

console.log(`${app} → ${track} (${packageName})`)

const edit = await api(`${base}/edits`, { method: 'POST' })
console.log(`  edit ${edit.id}`)

const bundle = await api(
  `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${packageName}/edits/${edit.id}/bundles?uploadType=media`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/octet-stream' },
    body: await readFile(aab),
  },
)
console.log(`  uploaded versionCode ${bundle.versionCode}`)

await api(`${base}/edits/${edit.id}/tracks/${track}`, {
  method: 'PUT',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    track,
    releases: [
      {
        versionCodes: [String(bundle.versionCode)],
        // `completed` = rolled out to everyone on this track. A staged rollout
        // is a deliberate act with a percentage on it, not something a script
        // should pick on your behalf.
        status: 'completed',
      },
    ],
  }),
})
console.log(`  assigned to ${track}`)

await api(`${base}/edits/${edit.id}:commit`, { method: 'POST' })
console.log(`  committed — version ${bundle.versionCode} is now in review for ${track}`)
