// Put a bundle Play already has onto another track.
//
//   node tool/play_promote.mjs <customer|vendor|rider> <track> <versionCode>
//
// The companion to play_tracks.mjs, and it exists for the trap that script
// reports: Play serves a tester the highest-priority track their account is in,
// and `internal` outranks `alpha`. Ship to alpha with a stale internal track and
// every internal tester keeps the old build — twice now that has cost a round of
// debugging a feature whose code was fine, because the phone did not have it.
//
// A promotion is not a release: no rebuild, no new versionCode, nothing built at
// all. The same .aab is assigned to a second track, which is why this is safe to
// run straight after a ship and why it takes the versionCode rather than
// working one out.
import { readFile } from 'node:fs/promises'
import { loadEnv } from './env.mjs'
import { accessToken } from './play_auth.mjs'

const APPS = {
  customer: 'com.siteonlab.zopiqnow',
  vendor: 'com.siteonlab.zopiq_vendor',
  rider: 'com.siteonlab.zopiq_rider',
}
const TRACKS = ['internal', 'alpha', 'beta', 'production']

const [app, track, code] = process.argv.slice(2)
if (!APPS[app] || !TRACKS.includes(track) || !/^\d+$/.test(code ?? '')) {
  console.error('usage: node tool/play_promote.mjs <customer|vendor|rider> <internal|alpha|beta|production> <versionCode>')
  process.exit(1)
}

// Deliberately not offered as a shortcut: production is asked for every time and
// is not something a promotion should make one keystroke away.
if (track === 'production') {
  console.error('Refusing to promote to production from here. That release is made deliberately, not as a follow-up.')
  process.exit(1)
}

await loadEnv()
const key = JSON.parse(await readFile(process.env.PLAY_SERVICE_ACCOUNT_JSON, 'utf8'))
const token = await accessToken(key)

const pkg = APPS[app]
const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}`
const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }

const edit = await (
  await fetch(`${base}/edits`, { method: 'POST', headers: auth, body: '{}' })
).json()
if (!edit.id) throw new Error(`could not open an edit: ${JSON.stringify(edit).slice(0, 200)}`)
console.log(`${app} → ${track} (${pkg})\n  edit ${edit.id}`)

const put = await fetch(`${base}/edits/${edit.id}/tracks/${track}`, {
  method: 'PUT',
  headers: auth,
  body: JSON.stringify({
    track,
    releases: [{ versionCodes: [String(code)], status: 'completed' }],
  }),
})
if (!put.ok) {
  // Abandon rather than leave a half-made edit lying against the app.
  await fetch(`${base}/edits/${edit.id}`, { method: 'DELETE', headers: auth })
  throw new Error(`assign failed: ${JSON.stringify(await put.json()).slice(0, 300)}`)
}
console.log(`  assigned versionCode ${code}`)

const done = await fetch(`${base}/edits/${edit.id}:commit`, { method: 'POST', headers: auth })
if (!done.ok) throw new Error(`commit failed: ${JSON.stringify(await done.json()).slice(0, 300)}`)
console.log(`  committed — version ${code} is now in review for ${track}`)
