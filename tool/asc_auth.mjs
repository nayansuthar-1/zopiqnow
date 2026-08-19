// A signed token for the App Store Connect API.
//
// **No dependencies, deliberately** — the same reasoning as `play_auth.mjs`.
// fastlane is Ruby (this Mac has 2.6.10, too old for it, and upgrading the
// system Ruby is its own afternoon), and the API wants nothing more than a
// self-signed ES256 JWT that Node produces out of `node:crypto`.
//
// The one trap worth naming: ECDSA signatures come in two encodings. OpenSSL's
// default is DER, and Apple rejects it without saying why — a 401 that reads
// exactly like a wrong key. JWS wants the fixed 64-byte r||s form, which is what
// `dsaEncoding: 'ieee-p1363'` selects. Everything else here is bookkeeping.
//
// Unlike Google's flow there is no exchange step: the JWT *is* the credential,
// so nothing leaves this machine until an actual API call is made.

import { createSign, createPrivateKey } from 'node:crypto'
import { readFile } from 'node:fs/promises'

const base64url = (input) => Buffer.from(input).toString('base64url')

/// Apple caps token lifetime at 20 minutes and rejects anything longer outright.
/// Fifteen leaves room for a slow upload to finish inside one token without
/// courting the edge.
const LIFETIME_SECONDS = 15 * 60

/// Reads the three values the API needs, and says which one is missing rather
/// than failing later inside a 401.
///
/// The `.p8` path is deliberately a path and not the key itself: **this
/// repository is public**, and a `.p8` is upload access to the store listing.
export async function credential(env = process.env) {
  const keyId = env.ASC_KEY_ID
  const issuerId = env.ASC_ISSUER_ID
  const keyPath = env.ASC_KEY_PATH?.replace(/^~/, env.HOME ?? '~')

  const missing = [
    ['ASC_KEY_ID', keyId],
    ['ASC_ISSUER_ID', issuerId],
    ['ASC_KEY_PATH', keyPath],
  ].filter(([, v]) => !v).map(([n]) => n)
  if (missing.length) {
    throw new Error(`${missing.join(', ')} not set in .env — see RELEASING_IOS.md`)
  }

  const pem = await readFile(keyPath, 'utf8').catch(() => null)
  if (pem === null) throw new Error(`nothing readable at ${keyPath}`)

  let privateKey
  try {
    privateKey = createPrivateKey(pem)
  } catch {
    throw new Error(`${keyPath} is not a readable private key`)
  }
  if (privateKey.asymmetricKeyType !== 'ec') {
    // A Play service-account key or an APNs auth key in this slot is a plausible
    // mix-up, and both fail later as an unexplained 401.
    throw new Error(`${keyPath} is a ${privateKey.asymmetricKeyType} key, not the EC key App Store Connect issues`)
  }
  return { keyId, issuerId, privateKey, keyPath }
}

export function token({ keyId, issuerId, privateKey }) {
  const now = Math.floor(Date.now() / 1000)
  const unsigned =
    `${base64url(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }))}.` +
    `${base64url(JSON.stringify({
      iss: issuerId,
      iat: now,
      exp: now + LIFETIME_SECONDS,
      aud: 'appstoreconnect-v1',
    }))}`
  const signature = createSign('SHA256')
    .update(unsigned)
    .sign({ key: privateKey, dsaEncoding: 'ieee-p1363' })
    .toString('base64url')
  return `${unsigned}.${signature}`
}

/// One GET against the API, returning parsed JSON.
///
/// Apple's errors arrive as `{ errors: [{ title, detail }] }` and the detail is
/// the half worth reading: "The provided entity includes an attribute with a
/// value that has already been used" is a duplicate build number, and the title
/// alone ("Entity Error") tells you nothing.
export async function api(path, cred) {
  const res = await fetch(`https://api.appstoreconnect.apple.com/${path}`, {
    headers: { Authorization: `Bearer ${token(cred)}` },
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    const first = body.errors?.[0]
    throw new Error(
      first ? `${first.title} — ${first.detail}` : `HTTP ${res.status}`,
    )
  }
  return body
}
