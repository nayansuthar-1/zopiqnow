// razorpay-order — creates the Razorpay order a payment is made against.
//
// **Why the client cannot do this itself.** Razorpay's checkout can be opened
// with nothing but an amount, and millions of apps do exactly that. It is also
// how you get charged whatever the phone felt like charging: an amount that
// originates on the device is an amount an attacker chooses. The fix Razorpay
// intends is a server-created *order* — the amount is fixed here, the checkout
// is opened against the order id, and the signature that comes back is only
// valid for that order. This function is that server.
//
// It writes a `payment_intents` row (0085) at the same time, which is what the
// `orders_require_verified_payment` trigger later reads. The row is the memory
// of "we asked for ₹460 from this customer"; the signature check in
// `razorpay-verify` is the proof they paid it.
//
// **Amounts.** Rupees on the way in, because every price in this schema is in
// rupees. Paise on the way to Razorpay, because that is its only unit. The
// conversion happens once, here, and nowhere on the device.
//
// **The amount is still client-supplied, and that is not the hole it looks
// like.** `place_order` reprices the whole cart in Postgres and the trigger
// refuses any intent worth less than the order's own total, so understating it
// buys a refusal rather than cheap food. What it cannot catch is *over*payment,
// which is the customer's own money and a refund, not an exploit.
//
// Secrets: RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET. Absent — which is the state
// today — this answers `{configured:false}` rather than failing, and the app
// falls back to its mock. That is deliberate: it means the day the keys are set
// here, every already-installed build starts taking real payments with no new
// release. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected.
//
// Deployed **with** JWT verification (no `--no-verify-jwt`): only a signed-in
// customer may create an intent, and the intent is stamped with whoever they are.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RAZORPAY_ORDERS = "https://api.razorpay.com/v1/orders";

// A ceiling so a bug or a hostile caller cannot open a checkout for a lakh. The
// largest plausible food order is far below this; raise it when that stops
// being true.
const MAX_AMOUNT_RUPEES = 50_000;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

  // Not an error. See the header: this is how the app learns to keep using the
  // mock, and how it learns to stop.
  if (!keyId || !keySecret) {
    return json({ configured: false });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: { amount?: unknown; description?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Bad request" }, 400);
  }

  const amount = Number(body.amount);
  if (!Number.isSafeInteger(amount) || amount <= 0 || amount > MAX_AMOUNT_RUPEES) {
    return json({ error: "Bad request" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // The platform has already checked the JWT is well-formed and unexpired; this
  // is how we find out *whose* it is. Never trust a user id from the body.
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData.user) {
    return json({ error: "Unauthorized" }, 401);
  }
  const userId = userData.user.id;

  const receipt = `zpq_${Date.now()}_${userId.slice(0, 8)}`;

  const rzpResponse = await fetch(RAZORPAY_ORDERS, {
    method: "POST",
    headers: {
      "Authorization": `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount: amount * 100, // paise
      currency: "INR",
      receipt,
      notes: {
        // Enough to find the customer from Razorpay's dashboard during a
        // dispute, and nothing that is not already ours.
        user_id: userId,
        description: typeof body.description === "string"
          ? body.description.slice(0, 120)
          : "Zopiq order",
      },
    }),
  });

  if (!rzpResponse.ok) {
    // Razorpay's own message can name a misconfigured account or a disabled
    // method; it belongs in the log, not in front of a hungry customer.
    console.error(
      "Razorpay order creation failed:",
      rzpResponse.status,
      await rzpResponse.text(),
    );
    return json({ error: "Could not start the payment" }, 502);
  }

  const rzpOrder = await rzpResponse.json() as { id?: string };
  if (!rzpOrder.id) {
    console.error("Razorpay returned no order id:", JSON.stringify(rzpOrder));
    return json({ error: "Could not start the payment" }, 502);
  }

  const { error: insertError } = await supabase
    .from("payment_intents")
    .insert({
      user_id: userId,
      razorpay_order_id: rzpOrder.id,
      amount,
      status: "created",
    });

  if (insertError) {
    // The Razorpay order exists and we cannot remember it, so nothing will ever
    // be able to consume it. Refusing here costs the customer a retry; carrying
    // on would cost them a payment that can never become an order.
    console.error("payment_intents insert failed:", insertError.message);
    return json({ error: "Could not start the payment" }, 500);
  }

  return json({
    configured: true,
    keyId,
    orderId: rzpOrder.id,
    amount,
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
