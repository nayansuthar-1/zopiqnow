// razorpay-verify — the signature check that makes a payment real.
//
// This is the whole answer to audit PAY-001. Until now `place_order` accepted
// any non-empty string as `p_payment_id`, so "I paid, here is the reference" was
// a claim nobody checked. Razorpay's own design has the answer built in: when a
// payment succeeds against a server-created order, the checkout hands the device
//
//     razorpay_order_id, razorpay_payment_id, razorpay_signature
//
// where the signature is `HMAC_SHA256(order_id + "|" + payment_id, key_secret)`.
// Only Razorpay and this project's server know the secret, so a signature that
// verifies could not have been invented on a phone. That is the proof.
//
// On a good signature the intent (0085) moves `created` -> `verified` and
// remembers the payment id. `place_order`'s trigger then requires exactly such a
// row before an order may exist, and marks it `consumed` so one payment cannot
// buy two dinners.
//
// **The comparison is constant-time**, for the same reason `send-notification`'s
// is: a naive `!==` returns faster the earlier it finds a mismatched byte, which
// hands an attacker a way to discover the right signature one character at a
// time. It is a cheap defence against an expensive mistake.
//
// **The intent is matched on order id *and* the caller.** Without the second
// half, a signature that is genuinely valid — say, one belonging to somebody
// else's real payment — would verify an intent that is not theirs. The signature
// proves a payment happened; it does not by itself prove whose.
//
// **It also records what actually paid** (0139). Checkout no longer filters
// Razorpay's methods — the account offers what it has enabled, and ours has UPI
// off until KYC — so a payment may arrive by card, UPI, netbanking or a wallet.
// The checkout callback does not say which, so this reads the payment back from
// Razorpay after the signature has already checked out. It is a courtesy for
// whoever later answers "the customer says they paid by card", and it is
// wrapped accordingly: a failed lookup leaves `instrument` null and changes
// nothing else. Verification has already succeeded by then, and no lookup is
// worth costing a customer their order.
//
// Secrets: RAZORPAY_KEY_SECRET, and RAZORPAY_KEY_ID for the instrument lookup
// (absent, the lookup is skipped and verification is unaffected). SUPABASE_URL
// and SUPABASE_SERVICE_ROLE_KEY are injected. Deployed **with** JWT
// verification.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!keySecret) {
    // Nothing signed can be checked without the secret. Say so plainly rather
    // than reporting a verification that never happened.
    console.error("RAZORPAY_KEY_SECRET is not set — refusing to verify.");
    return json({ verified: false, error: "Payments are not configured" }, 503);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: {
    razorpayOrderId?: unknown;
    razorpayPaymentId?: unknown;
    signature?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Bad request" }, 400);
  }

  const orderId = asShortString(body.razorpayOrderId);
  const paymentId = asShortString(body.razorpayPaymentId);
  const signature = asShortString(body.signature);
  if (!orderId || !paymentId || !signature) {
    return json({ error: "Bad request" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const token = authHeader.replace(/^Bearer\s+/i, "");
  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData.user) {
    return json({ error: "Unauthorized" }, 401);
  }
  const userId = userData.user.id;

  const expected = await hmacSha256Hex(keySecret, `${orderId}|${paymentId}`);
  if (!constantTimeEquals(expected, signature.toLowerCase())) {
    console.warn(`Signature mismatch for order ${orderId}`);
    return json({ verified: false }, 400);
  }

  // `status = 'created'` in the filter is the replay guard: verifying the same
  // payment twice updates nothing the second time, and an intent already
  // consumed by an order can never be reopened.
  const { data: updated, error: updateError } = await supabase
    .from("payment_intents")
    .update({
      status: "verified",
      razorpay_payment_id: paymentId,
      verified_at: new Date().toISOString(),
    })
    .eq("razorpay_order_id", orderId)
    .eq("user_id", userId)
    .eq("status", "created")
    .select("id");

  if (updateError) {
    console.error("payment_intents update failed:", updateError.message);
    return json({ verified: false, error: "Could not record the payment" }, 500);
  }

  if (!updated || updated.length === 0) {
    // A valid signature for an order this customer never opened, or one already
    // verified. Neither should happen in a working app.
    console.warn(`No open intent for order ${orderId} and user ${userId}`);
    return json({ verified: false }, 409);
  }

  // Everything below is bookkeeping. The payment is verified and the customer is
  // waiting on the answer, so nothing here may throw and nothing here may be
  // awaited for longer than it deserves — see the header.
  await recordInstrument(supabase, updated[0].id, paymentId);

  return json({ verified: true });
});

/// Reads back what Razorpay says actually paid — `card`, `upi`, `netbanking`,
/// a wallet — and files it against the intent (0139). Never throws.
async function recordInstrument(
  supabase: ReturnType<typeof createClient>,
  intentId: number,
  paymentId: string,
): Promise<void> {
  try {
    const keyId = Deno.env.get("RAZORPAY_KEY_ID");
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!keyId || !keySecret) return;

    const response = await fetch(
      `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`,
      { headers: { "Authorization": `Basic ${btoa(`${keyId}:${keySecret}`)}` } },
    );
    if (!response.ok) {
      console.warn(`Instrument lookup for ${paymentId}: HTTP ${response.status}`);
      return;
    }

    const payment = await response.json() as { method?: unknown };
    if (typeof payment.method !== "string" || payment.method.length === 0) return;

    await supabase
      .from("payment_intents")
      .update({ instrument: payment.method.slice(0, 40) })
      .eq("id", intentId);
  } catch (error) {
    // A courtesy that failed. The payment is still verified and the order still
    // goes through; `instrument` stays null, which 0139 treats as an answer.
    console.warn("Instrument lookup failed:", String(error));
  }
}

function asShortString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 200) return null;
  return trimmed;
}

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(signed))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEquals(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
