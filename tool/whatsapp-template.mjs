// whatsapp-template — submits the order-confirmation template to Meta, and
// reads back where its review got to.
//
//   node tool/whatsapp-template.mjs create
//   node tool/whatsapp-template.mjs status
//
// **Why a template at all.** WhatsApp lets a business open a conversation only
// with wording Meta has approved in advance. Free-form text is possible for 24
// hours after the *customer* writes first, which never happens here — nobody
// messages a delivery app to be told their order was accepted. So the message
// in migration 0132 is a template send, and it delivers nothing until the
// template below is APPROVED.
//
// **Why UTILITY.** Meta sorts templates into MARKETING, UTILITY and
// AUTHENTICATION, and the category is a permission as much as a label. This
// WABA cannot create AUTHENTICATION templates at all — see the long trail in
// the WhatsApp login work; UTILITY and MARKETING both create fine. An order
// confirmation is genuinely utility (a transaction the customer just made), so
// this is the honest category as well as the one that works. Do not push other
// message types through it: a miscategorised template risks UTILITY creation
// too, and that would take this feature down with it.
//
// **The variables are positional and their order is load-bearing.** {{1}} order
// id, {{2}} placed-at, {{3}} rupees — the same order the trigger in 0132 builds
// its parameter array in. Change one and you must change both, or customers get
// a date where the price goes.
//
// Deleting a template, should this one need replacing (a template's text cannot
// be edited once approved without a fresh review):
//
//   curl -X DELETE "https://graph.facebook.com/v23.0/$WHATSAPP_WABA_ID/message_templates?name=zopiq_order_confirmed" \
//        -H "Authorization: Bearer $WHATSAPP_TOKEN"
//
// Zero dependencies, like everything else in `tool/`.

import { loadEnv } from './env.mjs'

const GRAPH_VERSION = 'v23.0'

/// The template, in one place. `name` and `language` are repeated in migration
/// 0132 as literals — Postgres cannot read this file — so treat the pair as a
/// contract and grep for the name before renaming it.
const TEMPLATE = {
  name: 'zopiq_order_confirmed',
  language: 'en_US',
  category: 'UTILITY',
  components: [
    {
      type: 'BODY',
      text:
        'Your order is confirmed and the kitchen has started preparing it.\n' +
        '\n' +
        'Order ID: {{1}}\n' +
        'Placed on: {{2}}\n' +
        'Amount: ₹{{3}}\n' +
        '\n' +
        'You can follow it live in the Zopiq app.',
      // Meta reviews the wording against a filled-in example, and refuses a
      // body with variables that has none. These are never sent to anybody.
      example: {
        body_text: [['ZPQ-1042', '19 Aug 2026, 8:14 PM', '349']],
      },
    },
  ],
}

async function graph(path, init) {
  const res = await fetch(`https://graph.facebook.com/${GRAPH_VERSION}/${path}`, init)
  const text = await res.text()
  let json
  try {
    json = JSON.parse(text)
  } catch {
    json = null
  }
  if (!res.ok) {
    // Meta's errors carry the reason in `error.message` and the *actionable*
    // part in `error.error_user_msg`; print the lot rather than guess which.
    throw new Error(`${res.status} ${text}`)
  }
  return json
}

async function create(token, waba) {
  const created = await graph(`${waba}/message_templates`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(TEMPLATE),
  })
  console.log(`Submitted ${TEMPLATE.name} (${TEMPLATE.language}).`)
  console.log(`  id:       ${created.id}`)
  console.log(`  category: ${created.category ?? TEMPLATE.category}`)
  console.log(`  status:   ${created.status ?? 'PENDING'}`)
  console.log('')
  console.log('Meta reviews this in anything from minutes to 24 hours. Nothing')
  console.log('sends until it reads APPROVED — check with:')
  console.log('  node tool/whatsapp-template.mjs status')
}

async function status(token, waba) {
  const list = await graph(
    `${waba}/message_templates?fields=name,language,category,status,rejected_reason&limit=100`,
    { headers: { Authorization: `Bearer ${token}` } },
  )
  const rows = list.data ?? []
  if (rows.length === 0) {
    console.log('This WABA has no templates at all.')
    return
  }
  for (const t of rows) {
    const reason = t.rejected_reason && t.rejected_reason !== 'NONE'
      ? `  (${t.rejected_reason})`
      : ''
    console.log(
      `${t.status.padEnd(9)} ${t.category.padEnd(15)} ${t.name} [${t.language}]${reason}`,
    )
  }
}

const command = process.argv[2]
if (command !== 'create' && command !== 'status') {
  console.error('Usage: node tool/whatsapp-template.mjs create|status')
  process.exit(2)
}

await loadEnv()
const token = process.env.WHATSAPP_TOKEN
const waba = process.env.WHATSAPP_WABA_ID
if (!token || !waba) {
  console.error('WHATSAPP_TOKEN and WHATSAPP_WABA_ID must be set (see .env).')
  process.exit(2)
}

try {
  if (command === 'create') await create(token, waba)
  else await status(token, waba)
} catch (e) {
  console.error(String(e.message ?? e))
  process.exit(1)
}
