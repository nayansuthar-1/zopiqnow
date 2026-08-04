// send-sms-otp — carries a sign-in code to a phone, and nothing else.
//
// Wired in as GoTrue's **Send SMS hook**. MSG91 is not one of Supabase's four
// built-in SMS providers (twilio, messagebird, vonage, textlocal), and the hook
// is the supported way to use one that is not on that list.
//
// **The split is the security model, so do not "simplify" it.** Supabase
// generates the code, stores it, expires it and verifies it. This function is a
// courier: it receives a code that already exists and hands it to MSG91. It
// cannot mint a session, it holds no service-role key, and the most a total
// compromise of it yields is the ability to read codes in flight — bad, but not
// the same as issuing them.
//
// The alternative — MSG91's own OTP product, which generates *and* verifies its
// own code — was rejected deliberately. It would mean this project trusting a
// third party's word that a number was verified, then minting a Supabase session
// on the strength of it with the service-role key. That is a much larger hole
// than the one it saves, and it puts the service-role key on an internet-facing
// path for the sake of a convenience.
//
// Secrets (set with `supabase secrets set …`):
//   * MSG91_AUTHKEY      — the account auth key
//   * MSG91_TEMPLATE_ID  — the DLT-approved flow template that contains the code
//   * SEND_SMS_HOOK_SECRET — the `v1,whsec_…` secret Supabase shows when you
//                          enable the hook. Required; see below.
//
// **India delivers nothing without DLT.** TRAI requires a registered entity, an
// approved header (sender id) and an approved content template before any
// transactional SMS is delivered. `MSG91_TEMPLATE_ID` is that template's id.
// Credit in the account is necessary and not sufficient: an unregistered send is
// accepted by the API and dropped by the operator.
//
// **Who may call this.** Deployed `--no-verify-jwt`, because GoTrue calls it with
// no user JWT — exactly like `send-notification`, and with the same consequence:
// the gateway is not a check, so this handler does its own. Supabase signs every
// hook delivery as a Standard Webhook, and an unsigned or wrongly-signed request
// is refused before the body is read as anything but bytes. Without that, the
// URL is an open endpoint that texts attacker-chosen digits to attacker-chosen
// numbers, on our credit.
//
//   supabase functions deploy send-sms-otp --no-verify-jwt

const encoder = new TextEncoder()

/// Constant-time compare. A naive `===` on a signature leaks its prefix to
/// anyone willing to time the answer, which is enough to forge one byte at a
/// time.
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}

/// Standard Webhooks, which is what Supabase signs auth hooks with.
///
/// The signed content is `id.timestamp.body` — the raw body, byte for byte, so
/// this must never be handed a re-serialised object. `webhook-signature` carries
/// a space-separated list because a secret can be rotated with both live for a
/// while; any one matching is a pass.
async function isSignatureValid(
  rawBody: string,
  headers: Headers,
  secret: string,
): Promise<boolean> {
  const id = headers.get('webhook-id')
  const timestamp = headers.get('webhook-timestamp')
  const signatures = headers.get('webhook-signature')
  if (!id || !timestamp || !signatures) return false

  // Replay window. A valid delivery captured off the wire is otherwise valid
  // forever, and a replayed one re-texts a code the customer never asked for.
  const age = Math.abs(Date.now() / 1000 - Number(timestamp))
  if (!Number.isFinite(age) || age > 300) return false

  // `v1,whsec_<base64>` is how Supabase presents it; the bytes after the prefix
  // are the key. A secret pasted without the prefix still works.
  const raw = secret.replace(/^v1,/, '').replace(/^whsec_/, '')
  const key = await crypto.subtle.importKey(
    'raw',
    Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const mac = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(`${id}.${timestamp}.${rawBody}`),
  )
  const expected = new Uint8Array(mac)

  for (const entry of signatures.split(' ')) {
    const value = entry.startsWith('v1,') ? entry.slice(3) : entry
    let given: Uint8Array
    try {
      given = Uint8Array.from(atob(value), (c) => c.charCodeAt(0))
    } catch {
      continue
    }
    if (timingSafeEqual(expected, given)) return true
  }
  return false
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })

  const hookSecret = Deno.env.get('SEND_SMS_HOOK_SECRET')
  const authkey = Deno.env.get('MSG91_AUTHKEY')
  const templateId = Deno.env.get('MSG91_TEMPLATE_ID')

  // Fails closed, and deliberately *before* anything is parsed. A missing secret
  // is a misconfiguration, and the safe reading of "I cannot verify callers" is
  // "I answer nobody" rather than "I answer everybody".
  if (!hookSecret) {
    console.error('SEND_SMS_HOOK_SECRET is not set; refusing every request.')
    return new Response('Not configured', { status: 503 })
  }

  const rawBody = await req.text()
  if (!(await isSignatureValid(rawBody, req.headers, hookSecret))) {
    return new Response('Forbidden', { status: 403 })
  }

  if (!authkey || !templateId) {
    console.error('MSG91_AUTHKEY or MSG91_TEMPLATE_ID is not set.')
    return new Response('Not configured', { status: 503 })
  }

  let phone: string | undefined
  let otp: string | undefined
  try {
    const payload = JSON.parse(rawBody)
    phone = payload?.user?.phone
    otp = payload?.sms?.otp
  } catch {
    return new Response('Bad request', { status: 400 })
  }
  if (!phone || !otp) return new Response('Bad request', { status: 400 })

  // MSG91 wants the number with its country code and without the `+`; GoTrue
  // stores E.164. Digits-only is the whole conversion.
  const mobile = phone.replace(/\D/g, '')

  const response = await fetch('https://control.msg91.com/api/v5/flow/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', authkey },
    body: JSON.stringify({
      template_id: templateId,
      // The variable name has to match the one in the DLT template. `otp` is
      // MSG91's own convention for their OTP templates; if the approved
      // template names it something else, this key changes and nothing else.
      recipients: [{ mobiles: mobile, otp }],
    }),
  })

  const text = await response.text()
  if (!response.ok) {
    // The number is logged, the code never is. A log line is readable by anyone
    // with dashboard access and a sign-in code in it is a sign-in.
    console.error(`MSG91 refused ${mobile}: ${response.status} ${text}`)
    return new Response('Upstream failure', { status: 502 })
  }

  // MSG91 answers 200 with `{"type":"error"}` for a rejected template or an
  // empty balance, so the status alone is not the answer. Left as a 200 to
  // GoTrue either way: retrying will not fix a bad template, and a 500 here
  // shows the customer "could not send code" for a code that may yet arrive.
  if (text.includes('"type":"error"')) {
    console.error(`MSG91 accepted then refused ${mobile}: ${text}`)
  }

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
