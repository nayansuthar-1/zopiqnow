// whatsapp-webhook — the ear for everything Meta says after a message leaves.
//
// 0132 posts an order confirmation to the Cloud API and learns only that Meta
// accepted it. Delivery, failure, and the reason for a failure all arrive
// later, over this webhook, and until now nothing was listening. Verdicts on
// template review arrive here too, which is how `zopiq_order_confirmed` going
// APPROVED becomes something we are *told* rather than something we poll for.
//
// Everything it receives goes into `public.whatsapp_events` (migration 0133).
//
// Secrets (set with `supabase secrets set …`):
//   * WHATSAPP_VERIFY_TOKEN — a string we invent, echoed back to us during the
//                             one-time handshake so Meta can prove it reached
//                             the endpoint we claimed. Paste the same value in
//                             the console's "Verify token" field.
//   * WHATSAPP_APP_SECRET   — the Meta app's App Secret (App Dashboard →
//                             Settings → Basic). Every delivery is signed with
//                             it; without it this endpoint cannot tell Meta
//                             from anyone else who found the URL.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
//
// **Who may call this.** Deployed `--no-verify-jwt`, because Meta sends no user
// JWT — the same shape as `send-whatsapp-otp`, and the same consequence: the
// gateway is not a check, so this handler does its own. The shipped anon key is
// publishable and the gateway waves it through, so `verify_jwt` would prove
// nothing about the caller even if it were on.
//
//   supabase functions deploy whatsapp-webhook --no-verify-jwt
//
// **Why it answers 200 to almost everything.** Meta retries a delivery that
// does not get a 2xx, with backoff, and disables the subscription outright
// after enough failures. A row we could not parse is our problem, not Meta's,
// and taking the whole webhook down over it would lose the events that *do*
// parse. So: signature invalid → 403 and nothing else; signature valid →
// always 200, and any trouble past that point is logged, not returned.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const encoder = new TextEncoder();

/// Constant-time compare, for the same reason `send-whatsapp-otp` has one: a
/// naive `===` on a signature leaks its prefix to anyone willing to time the
/// answer, which is enough to forge one byte at a time.
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/// Meta signs each delivery as `X-Hub-Signature-256: sha256=<hex>` — an HMAC of
/// the **raw** body with the app secret. It must never be handed a
/// re-serialised object: `JSON.parse` then `JSON.stringify` changes key order
/// and whitespace, and the signature is over bytes.
async function isSignatureValid(
  rawBody: string,
  header: string | null,
  appSecret: string,
): Promise<boolean> {
  if (!header || !header.startsWith("sha256=")) return false;
  const hex = header.slice("sha256=".length);
  if (hex.length !== 64 || !/^[0-9a-f]+$/i.test(hex)) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(appSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
  const expected = new Uint8Array(mac);

  const given = new Uint8Array(32);
  for (let i = 0; i < 32; i++) given[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);

  return timingSafeEqual(expected, given);
}

interface EventRow {
  kind: string;
  subject: string | null;
  recipient: string | null;
  status: string | null;
  detail: string | null;
  payload: unknown;
}

/// Flattens Meta's envelope into the rows 0133 stores.
///
/// The shape is `entry[].changes[]`, and one delivery can carry several
/// changes, each carrying several statuses — a batch of confirmations all
/// delivered at once arrives as one request. Anything whose field we do not
/// recognise is kept whole under its own name rather than dropped.
function rowsFrom(payload: Record<string, unknown>): EventRow[] {
  const rows: EventRow[] = [];
  const entries = Array.isArray(payload.entry) ? payload.entry : [];

  for (const entry of entries) {
    const changes = Array.isArray(entry?.changes) ? entry.changes : [];
    for (const change of changes) {
      const field = change?.field;
      const value = change?.value ?? {};

      if (field === "messages" && Array.isArray(value.statuses)) {
        for (const s of value.statuses) {
          // `errors` is present only on a failure, and its `title` is the
          // human-readable half — "Message undeliverable", "Re-engagement
          // message", and so on.
          const error = Array.isArray(s?.errors) ? s.errors[0] : null;
          rows.push({
            kind: "message_status",
            subject: s?.id ?? null,
            recipient: s?.recipient_id ?? null,
            status: s?.status ?? null,
            detail: error
              ? `${error.code ?? ""} ${error.title ?? ""}`.trim()
              : null,
            payload: s,
          });
        }
        continue;
      }

      if (field === "message_template_status_update") {
        rows.push({
          kind: "template_status",
          subject: value?.message_template_name ?? null,
          recipient: null,
          // `event` is the verdict: APPROVED, REJECTED, PAUSED, …
          status: value?.event ?? null,
          detail: value?.reason && value.reason !== "NONE" ? value.reason : null,
          payload: value,
        });
        continue;
      }

      // Inbound messages, account updates, quality signals — kept whole. What
      // matters later is not knowable now, and the raw payload costs nothing.
      rows.push({
        kind: typeof field === "string" ? field : "unknown",
        subject: null,
        recipient: null,
        status: null,
        detail: null,
        payload: value,
      });
    }
  }

  return rows;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const url = new URL(req.url);

  // -------------------------------------------------------------------------
  // The handshake, which happens once, when "Verify and save" is clicked.
  // -------------------------------------------------------------------------
  // Meta GETs the URL with a challenge and the token we configured; echoing the
  // challenge back *as plain text* is what proves we own the endpoint. Any
  // other content type, or a JSON-quoted body, and the console reports failure.
  if (req.method === "GET") {
    const verifyToken = Deno.env.get("WHATSAPP_VERIFY_TOKEN");
    if (!verifyToken) {
      console.error("WHATSAPP_VERIFY_TOKEN is not set; cannot complete the handshake.");
      return new Response("Not configured", { status: 503 });
    }
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");
    if (mode === "subscribe" && token === verifyToken && challenge) {
      return new Response(challenge, {
        status: 200,
        headers: { "Content-Type": "text/plain" },
      });
    }
    return new Response("Forbidden", { status: 403 });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // -------------------------------------------------------------------------
  // A delivery.
  // -------------------------------------------------------------------------
  const appSecret = Deno.env.get("WHATSAPP_APP_SECRET");

  // Fails closed, and before the body is read as anything but bytes. A missing
  // secret is a misconfiguration, and the safe reading of "I cannot verify
  // callers" is "I answer nobody" rather than "I answer everybody".
  if (!appSecret) {
    console.error("WHATSAPP_APP_SECRET is not set; refusing every delivery.");
    return new Response("Not configured", { status: 503 });
  }

  const rawBody = await req.text();
  if (!(await isSignatureValid(rawBody, req.headers.get("x-hub-signature-256"), appSecret))) {
    return new Response("Forbidden", { status: 403 });
  }

  // Past this line the caller is Meta, and the answer is 200 whatever happens —
  // see the note at the top about retries and disabled subscriptions.
  try {
    const payload = JSON.parse(rawBody);
    const rows = rowsFrom(payload);
    if (rows.length > 0) {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );
      const { error } = await supabase.from("whatsapp_events").insert(rows);
      if (error) console.error(`Could not store ${rows.length} event(s): ${error.message}`);
    }
  } catch (e) {
    // The body is logged, not the headers: the signature is in the headers and
    // a log line is readable by anyone with dashboard access.
    console.error(`Unparseable delivery: ${e}\n${rawBody.slice(0, 2000)}`);
  }

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
