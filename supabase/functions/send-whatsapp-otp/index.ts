// send-whatsapp-otp — carries a sign-in code over WhatsApp, and nothing else.
//
// The sibling of `send-sms-otp`, and deliberately a copy of its shape rather
// than a refactor of it. **The split is the security model, so do not
// "simplify" it.** Supabase generates the code, stores it, expires it and
// verifies it. This function is a courier: it receives a code that already
// exists and hands it to WhatsApp. It cannot mint a session, it holds no
// service-role key, and the most a total compromise of it yields is the ability
// to read codes in flight — bad, but not the same as issuing them.
//
// **Why WhatsApp at all.** India delivers no transactional SMS without DLT: a
// registered entity, an approved header and an approved content template.
// `send-sms-otp` is written and correct and delivers nothing until that
// clears. WhatsApp sits outside TRAI's SMS framework entirely, so it needs
// none of it. That is the whole reason this exists.
//
// **Only one function can be GoTrue's Send SMS hook.** Pointing the hook here
// takes it away from `send-sms-otp`. That file stays in the tree on purpose —
// it is the fallback for the day DLT is approved, and reinstating it is a
// dashboard change rather than a rewrite.
//
// Secrets (set with `supabase secrets set …`):
//   * WHATSAPP_TOKEN           — permanent system-user token, scopes
//                                whatsapp_business_messaging + _management
//   * WHATSAPP_PHONE_NUMBER_ID — the sender's id, *not* its phone number
//   * SEND_SMS_HOOK_SECRET     — the `v1,whsec_…` secret Supabase shows when
//                                you enable the hook. Required; see below.
//
// **Who may call this.** Deployed `--no-verify-jwt`, because GoTrue calls it
// with no user JWT — exactly like `send-sms-otp`, and with the same
// consequence: the gateway is not a check, so this handler does its own.
// Supabase signs every hook delivery as a Standard Webhook, and an unsigned or
// wrongly-signed request is refused before the body is read as anything but
// bytes. Without that, the URL is an open endpoint that WhatsApps
// attacker-chosen digits to attacker-chosen numbers, on our card.
//
//   supabase functions deploy send-whatsapp-otp --no-verify-jwt

// The approved authentication template. Meta fixes the wording of these — the
// body is always "{{1}} is your verification code." — so the only things we
// choose are the name, the language and the button, and all three must match
// the template as approved or the send fails with "template not found".
const TEMPLATE_NAME = 'zopiq_login_code'
const TEMPLATE_LANG = 'en_US'
const GRAPH_VERSION = 'v23.0'

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
  // forever, and a replayed one re-sends a code the customer never asked for.
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
  const token = Deno.env.get('WHATSAPP_TOKEN')
  const phoneNumberId = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID')

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

  if (!token || !phoneNumberId) {
    console.error('WHATSAPP_TOKEN or WHATSAPP_PHONE_NUMBER_ID is not set.')
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

  // WhatsApp wants the number with its country code and without the `+`;
  // GoTrue stores E.164. Digits-only is the whole conversion.
  const to = phone.replace(/\D/g, '')

  // An authentication template carries the code twice: once in the body, where
  // the customer reads it, and once in the button, which is what "Copy code"
  // actually copies. Sending only the body parameter is accepted by nothing —
  // Meta rejects the message for a missing button parameter.
  const response = await fetch(
    `https://graph.facebook.com/${GRAPH_VERSION}/${phoneNumberId}/messages`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to,
        type: 'template',
        template: {
          name: TEMPLATE_NAME,
          language: { code: TEMPLATE_LANG },
          components: [
            { type: 'body', parameters: [{ type: 'text', text: otp }] },
            {
              type: 'button',
              sub_type: 'url',
              index: '0',
              parameters: [{ type: 'text', text: otp }],
            },
          ],
        },
      }),
    },
  )

  if (!response.ok) {
    // The number is logged, the code never is. A log line is readable by anyone
    // with dashboard access and a sign-in code in it is a sign-in.
    const text = await response.text()
    console.error(`WhatsApp refused ${to}: ${response.status} ${text}`)
    // Unlike MSG91 there is no "accepted then refused" case to swallow: a
    // WhatsApp send that is going to fail fails here, so the customer is told
    // rather than left waiting for a message that is not coming. The commonest
    // cause in production is a number with no WhatsApp account at all.
    return new Response('Upstream failure', { status: 502 })
  }

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
