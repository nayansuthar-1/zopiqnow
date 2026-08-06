// A service-account access token for the Play Developer API.
//
// **No dependencies, deliberately.** The obvious ways to do this are fastlane
// (Ruby, not installed here) or googleapis (a large tree for four HTTP calls).
// What the API actually wants is a self-signed JWT exchanged for a token, and
// Node signs RS256 out of `node:crypto` — so this is the whole client, and there
// is nothing to keep current or to audit.
//
// Shared by the uploader and by `ship.mjs --check`, so that "the credential
// works" means the same thing in both: not that the file parses, but that Google
// accepted it.

import { createSign } from 'node:crypto'

const base64url = (input) => Buffer.from(input).toString('base64url')

export async function accessToken(key) {
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
  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    // Google's own words. "Invalid grant: account not found" (the service
    // account was deleted) and "unauthorized_client" (it exists but was never
    // granted access in the Play Console) are different problems with different
    // fixes, and the generic sentence distinguishes neither.
    throw new Error(body.error_description ?? body.error ?? `HTTP ${res.status}`)
  }
  return body.access_token
}
