// Read-only check: which versionCode sits on each track, per app.
//
// Exists because of the trap in the release notes: Play serves a tester the
// highest-priority track their account is in, and `internal` outranks `alpha`.
// A phone opted into internal keeps getting a months-old build while every ship
// goes to alpha, and the app looks broken when the code is fine.
import { readFile } from 'node:fs/promises'
import { loadEnv } from './env.mjs'
import { accessToken } from './play_auth.mjs'

await loadEnv()
const key = JSON.parse(await readFile(process.env.PLAY_SERVICE_ACCOUNT_JSON, 'utf8'))
const token = await accessToken(key)

const APPS = {
  customer: 'com.siteonlab.zopiqnow',
  vendor: 'com.siteonlab.zopiq_vendor',
  rider: 'com.siteonlab.zopiq_rider',
}

for (const [name, pkg] of Object.entries(APPS)) {
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}`
  const mk = await fetch(`${base}/edits`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: '{}',
  })
  const edit = await mk.json()
  if (!edit.id) { console.log(`${name}: could not open an edit — ${JSON.stringify(edit).slice(0, 120)}`); continue }

  const res = await fetch(`${base}/edits/${edit.id}/tracks`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  const body = await res.json()
  const rows = (body.tracks ?? []).map((t) => {
    const codes = (t.releases ?? []).flatMap((r) => r.versionCodes ?? [])
    const status = (t.releases ?? []).map((r) => r.status).join('/')
    return `${t.track}=${codes.join(',') || '—'}${status ? ` (${status})` : ''}`
  })
  console.log(`${name.padEnd(9)} ${rows.join('  ')}`)

  // Abandon the edit; this script must never change anything.
  await fetch(`${base}/edits/${edit.id}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  })
}
