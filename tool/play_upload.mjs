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

/// Opens a resumable upload session and returns the URI to send bytes to.
///
/// **Resumable and not `uploadType=media`, because a 69 MB body does not
/// reliably survive a domestic uplink.** `media` is one unbroken stream: a
/// connection reset at 40% throws the 40% away and the next attempt starts at
/// zero, which is how three consecutive attempts can fail without ever getting
/// further. A resumable session lets the next attempt ask Google how much it
/// already has and carry on from there, so progress accumulates across resets
/// instead of being discarded.
function startSession(editId) {
  return new Promise((resolve, reject) => {
    const request = https.request(
      {
        hostname: 'androidpublisher.googleapis.com',
        path:
          `/upload/androidpublisher/v3/applications/${packageName}` +
          `/edits/${editId}/bundles?uploadType=resumable`,
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Length': 0,
          'X-Upload-Content-Type': 'application/octet-stream',
          'X-Upload-Content-Length': built.size,
        },
      },
      (res) => {
        let text = ''
        res.on('data', (chunk) => (text += chunk))
        res.on('end', () => {
          if (res.statusCode >= 300) {
            const parsed = text ? JSON.parse(text) : {}
            reject(new Error(explain(parsed.error?.message ?? `HTTP ${res.statusCode}`)))
          } else if (!res.headers.location) {
            reject(new Error('Play opened no resumable session (no Location header).'))
          } else {
            resolve(res.headers.location)
          }
        })
      },
    )
    request.on('error', reject)
    request.end()
  })
}

/// Where the session actually got to.
///
/// Returns `{ done: true, bundle }` when Play already has every byte — a reset
/// can kill the response *after* the last byte landed, so "finished" is a real
/// answer to this question and the Bundle resource comes back with it rather
/// than being thrown away and re-uploaded.
///
/// Otherwise `{ done: false, offset }`. The `Range` header reads `bytes=0-N` and
/// is *inclusive*, so the next byte to send is N+1. A 308 carrying no `Range` at
/// all means Play holds nothing yet, which is a legitimate answer and not an
/// error.
function sessionStatus(sessionUri) {
  return new Promise((resolve, reject) => {
    const request = https.request(
      sessionUri,
      {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Length': 0,
          'Content-Range': `bytes */${built.size}`,
        },
      },
      (res) => {
        let text = ''
        res.on('data', (chunk) => (text += chunk))
        res.on('end', () => {
          if (res.statusCode === 200 || res.statusCode === 201) {
            return resolve({ done: true, bundle: text ? JSON.parse(text) : {} })
          }
          if (res.statusCode !== 308) {
            return reject(new Error(`Upload session is gone (HTTP ${res.statusCode}).`))
          }
          const range = res.headers.range
          resolve({ done: false, offset: range ? Number(range.split('-')[1]) + 1 : 0 })
        })
      },
    )
    request.on('error', reject)
    request.end()
  })
}

/// Sends the bytes from [offset] on.
///
/// Resolves the parsed Bundle resource when Play accepts the last byte, and
/// `null` when the session is merely incomplete (308) — the caller loops.
///
/// **Not `fetch`, and that part is unchanged.** Node's fetch is undici, whose
/// headers timeout starts when the request does — but Google sends no headers
/// until the last byte has arrived, so on any ordinary upstream connection the
/// timeout fires mid-upload and the whole thing dies with
/// `UND_ERR_HEADERS_TIMEOUT`. `node:https` has no such clock, and streaming from
/// disk keeps 69 MB out of memory besides.
function sendFrom(sessionUri, offset) {
  return new Promise((resolve, reject) => {
    const remaining = built.size - offset
    const request = https.request(
      sessionUri,
      {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Length': remaining,
          'Content-Range': `bytes ${offset}-${built.size - 1}/${built.size}`,
        },
      },
      (res) => {
        let text = ''
        res.on('data', (chunk) => (text += chunk))
        res.on('end', () => {
          if (res.statusCode === 308) return resolve(null)
          const parsed = text ? JSON.parse(text) : {}
          if (res.statusCode >= 300) {
            return reject(new Error(explain(parsed.error?.message ?? `HTTP ${res.statusCode}`)))
          }
          resolve(parsed)
        })
      },
    )
    request.on('error', reject)

    // Progress, because 69 MB on a domestic uplink is minutes of silence
    // otherwise, and silence is indistinguishable from a hang. Counted from
    // [offset] so a resumed attempt picks up the percentage rather than
    // restarting it.
    let sent = offset
    let lastShown = Math.floor((offset / built.size) * 100)
    const file = createReadStream(aab, { start: offset })
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

/// One session, retried until the bytes are all there.
///
/// The session URI outlives a reset, so each attempt resumes rather than
/// restarts. Bounded, because a link that has dropped eight times is not going
/// to be talked round by a ninth, and an unbounded loop on a broken uplink is a
/// hang rather than an upload.
async function uploadBundle(editId) {
  const sessionUri = await startSession(editId)
  let offset = 0

  for (let attempt = 1; attempt <= 8; attempt++) {
    try {
      const bundle = await sendFrom(sessionUri, offset)
      if (bundle) return bundle
    } catch (error) {
      if (attempt === 8) throw error
      console.log(`  ${error.code ?? error.message} — resuming (attempt ${attempt + 1}/8)`)
      await new Promise((r) => setTimeout(r, 2000 * attempt))
    }

    // Always ask where we got to rather than trusting the local count: a reset
    // can drop bytes that were written to the socket but never committed, so
    // ours is optimistic and Play's is the truth. This also catches the case
    // where every byte landed and only the response was lost.
    const status = await sessionStatus(sessionUri)
    if (status.done) return status.bundle
    offset = status.offset
  }
  throw new Error('Upload did not complete after 8 attempts.')
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
