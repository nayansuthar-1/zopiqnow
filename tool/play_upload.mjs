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

import { createReadStream } from 'node:fs'
import { readFile, stat } from 'node:fs/promises'
import https from 'node:https'
import path from 'node:path'

import { accessToken } from './play_auth.mjs'
import { loadEnv } from './env.mjs'

await loadEnv()

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
//
// **Skipped when ship.mjs says it just built this**, and that is a correctness
// fix rather than a convenience. Gradle is incremental: if the inputs have not
// changed it leaves the existing .aab alone, mtime and all. So a build that
// legitimately succeeded seconds ago can leave a file an hour old, and this
// check would refuse the very bundle it was asked to ship. "The build I just
// ran succeeded against this exact pubspec" is a stronger guarantee than a
// timestamp anyway; the timestamp is only here for a human running this script
// on its own, where there is no such guarantee to be had.
const justBuilt = process.argv.includes('--just-built')
const ageMinutes = (Date.now() - built.mtimeMs) / 60000
if (!justBuilt && ageMinutes > 10) {
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

// --- The API ----------------------------------------------------------------
const token = await accessToken(key)
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
    throw new Error(explain(parsed.error?.message ?? `${res.status} ${text.slice(0, 300)}`))
  }
  return parsed
}

/// Play's sentence, plus what to do about it when the sentence does not say.
///
/// These three are the ones that arrive with no hint of a cause, and each has
/// exactly one fix. "This Edit has been deleted" in particular reads like data
/// loss and is nothing of the kind — it means somebody else committed an edit on
/// this app while ours was open, which is what happens the moment two people run
/// this script at once.
function explain(message) {
  if (/Edit has been deleted/i.test(message)) {
    return (
      `${message}\n\n` +
      'Play allows one open edit per app, so a second release running at the same\n' +
      'time deletes the first. Nothing was uploaded and nothing was broken — wait\n' +
      'for the other run to finish, then run this again.'
    )
  }
  if (/version code.*already been used|already exists/i.test(message)) {
    return (
      `${message}\n\n` +
      'That versionCode is already on Play. Run again — the bump takes the next one.'
    )
  }
  if (/not found/i.test(message)) {
    return (
      `${message}\n\n` +
      'The app has to exist in the Play Console before anything can be uploaded to\n' +
      'it. Create it there first; there is no API for that step.'
    )
  }
  return message
}

/// Streams the .aab up.
///
/// **Not `fetch`, and that is the whole reason this function exists.** Node's
/// fetch is undici, whose headers timeout starts when the request does — but
/// Google sends no headers until the last byte of a 69 MB body has arrived, so
/// on any ordinary upstream connection the timeout fires mid-upload and the
/// whole thing fails with `UND_ERR_HEADERS_TIMEOUT`. `node:https` has no such
/// clock, and streaming the file keeps 69 MB out of memory besides.
function uploadBundle(editId) {
  return new Promise((resolve, reject) => {
    const request = https.request(
      {
        hostname: 'androidpublisher.googleapis.com',
        path:
          `/upload/androidpublisher/v3/applications/${packageName}` +
          `/edits/${editId}/bundles?uploadType=media`,
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/octet-stream',
          'Content-Length': built.size,
        },
      },
      (res) => {
        let text = ''
        res.on('data', (chunk) => (text += chunk))
        res.on('end', () => {
          const parsed = text ? JSON.parse(text) : {}
          if (res.statusCode >= 300) {
            reject(new Error(explain(parsed.error?.message ?? `HTTP ${res.statusCode}`)))
          } else {
            resolve(parsed)
          }
        })
      },
    )
    request.on('error', reject)

    // Progress, because 69 MB on a domestic uplink is minutes of silence
    // otherwise, and silence is indistinguishable from a hang.
    let sent = 0
    let lastShown = 0
    const file = createReadStream(aab)
    file.on('data', (chunk) => {
      sent += chunk.length
      const percent = Math.floor((sent / built.size) * 100)
      if (percent >= lastShown + 10) {
        lastShown = percent
        console.log(`  ${percent}%`)
      }
    })
    file.on('error', reject)
    file.pipe(request)
  })
}

console.log(`${app} → ${track} (${packageName})`)

const edit = await api(`${base}/edits`, { method: 'POST' })
console.log(`  edit ${edit.id}`)

const bundle = await uploadBundle(edit.id)
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
