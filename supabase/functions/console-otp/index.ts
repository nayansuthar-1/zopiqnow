// console-otp — the admin console's second door, and the only one that opens
// without a password.
//
// The console signs in with email and password against `auth.users` (0153).
// This adds a way in for an admin who does not have the password to hand: a
// six-digit code, mailed by GoTrue, verified in the browser. What it very
// deliberately does **not** add is a way in for anybody else.
//
// **Why this is a function and not two lines in the browser.** The rule is
// "only an address already in `platform_admins`", and that table is closed —
// RLS on, no policies, so `anon` and `authenticated` read nothing from it no
// matter what the grants say (0026). A gate the browser could evaluate would
// need the roster readable, or an RPC answering "is this address an admin?" to
// anyone who asks. That second one is an *oracle*: it hands a stranger the
// exact list of addresses worth attacking, which is the thing 0026 closed the
// table to prevent. So the check happens here, with the service-role key, and
// the answer never leaves.
//
// **Both outcomes return the same body.** An address on the roster gets a code
// and `{ ok: true }`. An address not on it gets `{ ok: true }` and nothing
// else — no mail, no error, no difference the caller can see. The console's
// copy matches: "if that address can open this console, a code is on its way".
// A 404 for strangers would be the oracle again, wearing a different hat.
//
// **`shouldCreateUser: false` is load-bearing.** The console's *first* door was
// an OTP one, and it called `signInWithOtp` with `shouldCreateUser: true` — so
// typing any address into the sign-in screen minted an `auth.users` row for it.
// That was survivable, because authority is the `platform_admins` row and not
// the account, but it meant the front door of an ops console created users as a
// side effect of being looked at. This one creates nothing, ever: an address
// with no account gets no code, and no account.
//
// **What this does not, and cannot, do.** It does not stop a customer or a
// rider from getting a Supabase session — the anon key is public, GoTrue's
// `/otp` endpoint is reachable directly, and the customer app is *built* on
// asking it for codes. It never could. What keeps a non-admin out of the
// console is `is_admin()` on every screen and every RPC behind it, and that has
// not changed. What this function guarantees is narrower and still worth
// having: **the console never mails a sign-in code to somebody who is not an
// admin, and never creates an account for anybody at all.**
//
// Two honest limits, written down rather than papered over:
//
//   * **Timing.** A roster hit does a GoTrue round trip and a miss does not, so
//     the two answers do not take equally long. That is a far weaker signal
//     than a 404 and it is not worth a fake delay pretending otherwise.
//   * **Mail to a known admin.** Anyone who already knows an admin's address can
//     make this send them a code. They cannot read it, and GoTrue's own
//     per-address cooldown and the project's hourly cap are what stop it being
//     a way to fill an inbox. There is no separate throttle here, on purpose:
//     one that ran *before* the roster check would answer differently for
//     admins and strangers, and one that ran after would be the oracle again.
//
// No secrets to set. `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
// `SUPABASE_SERVICE_ROLE_KEY` are injected into every function.
//
// **Who may call this.** Nobody is signed in yet — that is the entire point —
// so there is no JWT to verify and the gateway's check would be theatre anyway
// (a publishable key is not a JWT, and the gateway waves it through):
//
//   supabase functions deploy console-otp --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Called from a browser, unlike every other function here, so the preflight has
// to be answered. `*` is deliberate: this endpoint returns one fixed body to
// everybody, so there is nothing an origin could be trusted with that another
// could not.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// The one answer. Named, so that adding a second one is a decision somebody has
// to make on purpose rather than a line they slip in while debugging.
const SAME_ANSWER = { ok: true };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: { email?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Bad request" }, 400);
  }

  const email = String(body.email ?? "").trim().toLowerCase();

  // The one thing answered differently, and it is safe to: a malformed address
  // is not on the roster and could not be, so saying so reveals nothing about
  // who is. Silently accepting it would leave an admin staring at an inbox over
  // a typo they cannot see.
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return json({ error: "That doesn't look like an email address." }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // `service_role` bypasses RLS, which is the only way anything reads this
  // table. Stored lowercase and checked lowercase — `platform_admins` carries a
  // constraint saying so (0026), so this needs no `ilike` and gets to use the
  // primary key.
  const { data: roster, error: lookupError } = await admin
    .from("platform_admins")
    .select("email")
    .eq("email", email)
    .maybeSingle();

  if (lookupError) {
    // A failure to *check* is not a refusal, and must not be dressed as one.
    console.error("console-otp: roster lookup failed", lookupError.message);
    return json({ error: "Could not check that address. Try again." }, 500);
  }

  if (!roster) {
    console.log("console-otp: not on the roster, nothing sent");
    return json(SAME_ANSWER);
  }

  // The anon key, not the service-role one: this is an ordinary sign-in
  // request, and it should be rate-limited, templated and logged exactly like
  // one. The service-role client above answers a question; it does not open
  // doors.
  const gotrue = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { auth: { persistSession: false } },
  );

  const { error: sendError } = await gotrue.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false },
  });

  if (sendError) {
    // Logged, never returned. This is where the cooldown lands ("you can only
    // request this after N seconds"), and where an admin whose `auth.users` row
    // is missing would land too — both are real, and both would answer
    // differently for an admin than for a stranger if they were reported.
    console.error("console-otp: send failed", sendError.message);
  }

  return json(SAME_ANSWER);
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
