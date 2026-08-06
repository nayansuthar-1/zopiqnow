// Ship an app to Play: bump, build, upload, record.
//
//   node tool/ship.mjs --check                  what is set up, what is missing
//   node tool/ship.mjs customer internal        the whole thing
//   node tool/ship.mjs customer internal --no-upload   build only
//
// **One entry point, in Node rather than PowerShell**, so the same command works
// from any shell on this box — including the one Claude runs. That is the whole
// reason this replaced `release.ps1`: a release nobody but a human at a
// PowerShell prompt could start was a release Claude could not do for you.
//
// Order matters and is not arbitrary: the versionCode is committed **after** Play
// accepts the upload. A failed build therefore never burns a number that no
// bundle on Play ever used, and the git history never claims a release that
// does not exist.

import { spawn } from 'node:child_process'
import { readFile, writeFile, stat } from 'node:fs/promises'
import path from 'node:path'

import { loadEnv } from './env.mjs'

const APPS = ['customer', 'vendor', 'rider']
/// The four Play creates for you. **Not a whitelist** — a closed test can be a
/// track you named yourself ("qa", "friends-and-family"), and the API takes that
/// name verbatim. `--check` lists what this app actually has, which is the only
/// answer that is true for *your* console rather than for Play in general.
///
/// The mapping is worth stating because the Console and the API use different
/// words for the same thing: Console "Closed testing" is `alpha` unless renamed,
/// and Console "Open testing" is `beta`.
const KNOWN_TRACKS = ['internal', 'alpha', 'beta', 'production']
const root = path.resolve(import.meta.dirname, '..')

const args = process.argv.slice(2)
const check = args.includes('--check')
const noUpload = args.includes('--no-upload')
const [app, track] = args.filter((a) => !a.startsWith('--'))

await loadEnv()

/// Runs a child process to completion, resolving with its exit code.
///
/// [shell] defaults on for Windows because `flutter` and `git` are `.bat`
/// wrappers there and cannot be executed directly. It must be **off** for
/// `process.execPath`, which is `C:\Program Files\nodejs\node.exe` — a shell
/// splits that on the space and tries to run `C:\Program`.
function run(command, cmdArgs, cwd, { shell = process.platform === 'win32' } = {}) {
  return new Promise((resolve) => {
    const child = spawn(command, cmdArgs, { cwd, stdio: 'inherit', shell })
    child.on('close', resolve)
  })
}

/// The track names Play holds for one app.
///
/// Listing tracks needs an edit to hang the read off, so one is opened and then
/// abandoned. Abandoning is the point: an edit that is never committed changes
/// nothing on the listing, so this stays a read however often it is run.
async function tracksOf(appName, token) {
  const gradle = await readFile(
    path.join(root, 'apps', appName, 'android/app/build.gradle.kts'),
    'utf8',
  )
  const id = gradle.match(/applicationId\s*=\s*"([^"]+)"/)?.[1]
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${id}`
  const auth = { Authorization: `Bearer ${token}` }

  const editRes = await fetch(`${base}/edits`, { method: 'POST', headers: auth })
  const edit = await editRes.json().catch(() => ({}))
  if (!editRes.ok) throw new Error(edit.error?.message ?? `HTTP ${editRes.status}`)

  const res = await fetch(`${base}/edits/${edit.id}/tracks`, { headers: auth })
  const body = await res.json().catch(() => ({}))
  await fetch(`${base}/edits/${edit.id}`, { method: 'DELETE', headers: auth })
  if (!res.ok) throw new Error(body.error?.message ?? `HTTP ${res.status}`)

  return (body.tracks ?? []).map((t) => t.track)
}

// --- Preflight --------------------------------------------------------------
// Every answer here is a fact read off the disk, not a reassurance. The point of
// this mode is to find the missing piece *before* a fifteen-minute build, and
// to name it precisely enough to act on.
async function doctor() {
  const lines = []
  let ready = true

  for (const a of APPS) {
    const gradle = await readFile(
      path.join(root, 'apps', a, 'android/app/build.gradle.kts'),
      'utf8',
    ).catch(() => '')
    const id = gradle.match(/applicationId\s*=\s*"([^"]+)"/)?.[1] ?? '??'
    const target = gradle.match(/targetSdk\s*=\s*(\d+)/)?.[1] ?? '??'
    const pubspec = await readFile(
      path.join(root, 'apps', a, 'pubspec.yaml'),
      'utf8',
    ).catch(() => '')
    const version = pubspec.match(/^version:\s*(\S+)/m)?.[1] ?? '??'
    const signing = await stat(
      path.join(root, 'apps', a, 'android/key.properties'),
    ).then(() => 'signing key configured').catch(() => 'NO key.properties — release builds will not be signed')
    lines.push(`  ${a.padEnd(9)} ${id}  v${version}  targetSdk ${target}`)
    lines.push(`  ${' '.repeat(9)} ${signing}`)
    if (signing.startsWith('NO')) ready = false
  }

  const keyPath = process.env.PLAY_SERVICE_ACCOUNT_JSON
  let play
  if (!keyPath) {
    play = 'MISSING — PLAY_SERVICE_ACCOUNT_JSON is not set in .env'
    ready = false
  } else {
    const key = await readFile(keyPath, 'utf8').then(JSON.parse).catch(() => null)
    if (!key) {
      play = `MISSING — nothing readable at ${keyPath}`
      ready = false
    } else if (!key.client_email || !key.private_key) {
      play = `INVALID — ${keyPath} is not a service-account key (no client_email/private_key)`
      ready = false
    } else {
      play = `${key.client_email}`
      // Proves the key is not merely well-formed but actually accepted, and that
      // it has been granted access in the Play Console — two different failures
      // that look identical until something asks Google.
      const { accessToken } = await import('./play_auth.mjs')
      const token = await accessToken(key).catch((e) => e)
      if (token instanceof Error) {
        play += `\n  Play API      REJECTED — ${token.message}`
        ready = false
      } else {
        play += '\n  Play API      token granted'
        // What tracks this app really has, read from Play rather than assumed.
        // A closed test can be a track somebody named, and guessing `alpha` when
        // it is called something else uploads to a track nobody is testing on.
        for (const a of APPS) {
          const names = await tracksOf(a, token).catch((e) => e)
          play += names instanceof Error
            ? `\n  ${a.padEnd(13)} could not list tracks — ${names.message}`
            : `\n  ${a.padEnd(13)} tracks: ${names.join(', ') || '(none yet)'}`
        }
      }
    }
  }

  console.log('\nApps')
  console.log(lines.join('\n'))
  console.log(`\nPlay credential\n  ${play}\n`)
  console.log(
    ready
      ? 'Ready. `node tool/ship.mjs customer internal` will build and upload.'
      : 'Not ready — see the MISSING lines above. RELEASING.md has the setup.',
  )
  process.exit(ready ? 0 : 1)
}

if (check) await doctor()

if (!APPS.includes(app) || !track) {
  console.error(
    'usage:\n' +
      '  node tool/ship.mjs --check\n' +
      '  node tool/ship.mjs <customer|vendor|rider> <track> [--no-upload]\n' +
      `\n  track: ${KNOWN_TRACKS.join(' | ')}, or a custom one — run --check to list this app's.`,
  )
  process.exit(1)
}
if (!KNOWN_TRACKS.includes(track)) {
  // Not refused: a custom closed track is a legitimate name. Said out loud,
  // because a typo here uploads to a track that quietly springs into existence
  // with nobody testing on it.
  console.log(`Track "${track}" is not one of Play's standard four — assuming a custom track.`)
}

// --- 1. Bump ----------------------------------------------------------------
// `version: 1.0.0+7` — what follows the + is Play's versionCode and has to beat
// every code ever uploaded. The name before it is left alone: what a release is
// *called* is a decision, not an increment.
const pubspecPath = path.join(root, 'apps', app, 'pubspec.yaml')
const original = await readFile(pubspecPath, 'utf8')
const match = original.match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m)
if (!match) {
  console.error(`Could not read a 'version: x.y.z+n' line from ${pubspecPath}`)
  process.exit(1)
}
const [, name, oldCode] = match
const newCode = Number(oldCode) + 1

console.log(`${app}: versionCode ${oldCode} → ${newCode} (version ${name})`)
await writeFile(
  pubspecPath,
  original.replace(/^version:\s*\d+\.\d+\.\d+\+\d+\s*$/m, `version: ${name}+${newCode}`),
)

// --- 2. Build ---------------------------------------------------------------
console.log('Building release bundle…')
const built = await run('flutter', ['build', 'appbundle', '--release'], path.join(root, 'apps', app))
if (built !== 0) {
  // Put it back. A failed build has not used this code, and leaving it bumped
  // means the next attempt silently skips a number.
  await writeFile(pubspecPath, original)
  console.error('Build failed. versionCode restored.')
  process.exit(1)
}

if (noUpload) {
  console.log('Built. Not uploaded (--no-upload). The version bump is not committed.')
  await writeFile(pubspecPath, original)
  process.exit(0)
}

// --- 3. Upload --------------------------------------------------------------
const uploaded = await run(
  process.execPath,
  [path.join(root, 'tool/play_upload.mjs'), app, track, '--just-built'],
  root,
  { shell: false },
)
if (uploaded !== 0) {
  console.error('Upload failed. The version bump is NOT committed.')
  process.exit(1)
}

// --- 4. Record --------------------------------------------------------------
// `shell: false` for git, like the node call above: git.exe is a real
// executable, and a Windows shell concatenates arguments without quoting — so
// `-m "release 1.0.0+8 to internal"` arrives as five separate pathspecs and the
// commit fails after the upload has already happened.
const gitOpts = { shell: false }
await run('git', ['add', `apps/${app}/pubspec.yaml`], root, gitOpts)
await run('git', ['commit', '-m', `chore(${app}): release ${name}+${newCode} to ${track}`], root, gitOpts)
await run('git', ['push'], root, gitOpts)

console.log(`\nDone. ${app} ${name}+${newCode} is in review for ${track}.`)
