// send-notification — turns an inbox row into a push.
//
// Invoked by the database webhook on `notifications` INSERT (migration 0047).
// Every important event already writes a `notifications` row (a trigger does it,
// per 0047); this function is the other half — it takes that row, finds the
// devices belonging to whoever it is addressed to, and rings them through the
// FCM HTTP v1 API. One path for all three audiences: customer, rider, vendor.
//
// This supersedes `send-order-push` (which rang only the kitchen, only on a new
// order, straight off the `orders` table). Deploy THIS one and point the webhook
// at `notifications`; do not run both, or a new order would push twice.
//
// Secrets. At least one service-account JSON must be set as a function secret:
//   * FCM_SERVICE_ACCOUNT            — used for every audience, if the three apps
//                                      live in ONE Firebase project (recommended);
//   * FCM_SERVICE_ACCOUNT_CUSTOMER   — optional per-audience overrides, for the
//   * FCM_SERVICE_ACCOUNT_RIDER        case where an app has its own Firebase
//   * FCM_SERVICE_ACCOUNT_RESTAURANT   project. **None does.** All three live in
//                                      `zopiq-de276`, so these three are unused and
//                                      the APNs .p8 is one upload, not three.
// An audience with no service account (neither its own nor the default) is
// skipped, not an error — push for it is simply not configured yet.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
//
// **Who may call this (SEC-001).** The function is deployed `--no-verify-jwt`,
// because a database webhook carries no user JWT to verify. That is not a licence
// to trust the caller: without a check of its own the URL — which is derived from
// the project ref, and the project ref ships inside every APK — was an open
// endpoint that would push any title and body to any recipient named in the
// request. Two things close it, and the second matters more than the first:
//
//   1. `NOTIFY_WEBHOOK_SECRET`, a function secret, must arrive as the
//      `x-notify-secret` header. Set it with
//      `supabase secrets set NOTIFY_WEBHOOK_SECRET=…` and add the same header to
//      the notifications-INSERT webhook. Compared in constant time, because a
//      naive `!==` leaks the secret's prefix to anyone willing to time it.
//   2. **Only the row id is taken from the body.** The record is re-read from the
//      database with the service key, so the payload cannot describe a
//      notification that was never written. A leaked secret then buys an attacker
//      the ability to *re-send* a real notification, not to compose one — which is
//      the difference between a nuisance and a phishing channel.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Audience = "customer" | "rider" | "restaurant";

interface NotificationRecord {
  id: number;
  audience: Audience;
  restaurant_id: string | null;
  user_id: string | null;
  partner_email: string | null;
  kind: string;
  title: string;
  body: string | null;
  order_id: string | null;
  // The live card's numbers (migration 0052). Null on every other kind.
  data: Record<string, unknown> | null;
}

// The silent kind. An `order_live` row is not correspondence — it is a tick that
// moves a progress bar on a notification the device is already drawing, so it
// goes out as a *data-only* message: no `notification` block, which is what
// stops Android from posting a tray entry of its own beside the card. The app's
// background handler receives it and redraws. Everything else keeps the
// alerting shape 0047 shipped.
const SILENT_KINDS = new Set(["order_live"]);

// What the webhook posts. Supabase sends the whole row, but the type says `id`
// and nothing else on purpose: the rest is re-read from the table, and a field
// that is never read should not be nameable here. See SEC-001 in the header.
interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: { id: number } | null;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri: string;
  project_id: string;
}

// The Android channel a push lands on, per audience. The device-side app creates
// these channels; if one is missing, Android falls back to the default channel,
// so a mismatch is cosmetic, never a dropped push.
const CHANNEL: Record<Audience, string> = {
  restaurant: "new_orders",
  customer: "order_updates",
  rider: "jobs",
};

// --- Google access token, minted from the service account (JWT bearer grant) ---

function base64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const der = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) der[i] = raw.charCodeAt(i);
  return der.buffer;
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  }));
  const signingInput = `${header}.${claim}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${base64url(signature)}`;

  const res = await fetch(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`Token exchange failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  return json.access_token as string;
}

// The service account to use for an audience: its own override, else the shared
// default. Null means push is not configured for that audience.
function serviceAccountFor(audience: Audience): ServiceAccount | null {
  const perAudience = Deno.env.get(`FCM_SERVICE_ACCOUNT_${audience.toUpperCase()}`);
  const shared = Deno.env.get("FCM_SERVICE_ACCOUNT");
  const raw = perAudience ?? shared;
  return raw ? JSON.parse(raw) as ServiceAccount : null;
}

// Constant-time string comparison. `a !== b` returns on the first differing
// byte, so the time it takes says how much of the secret was right — enough, over
// enough requests, to recover it a character at a time. This one always walks the
// whole string.
function secretMatches(given: string | null, expected: string): boolean {
  if (given === null) return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  // Length is not itself secret — the XOR below cannot compare unequal lengths,
  // and padding to hide it would leak the same fact through the allocation.
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// --- The function ---

Deno.serve(async (req) => {
  // The gate, before anything else is read or parsed. A caller who cannot prove
  // it is the webhook gets one word and no information about why.
  const expectedSecret = Deno.env.get("NOTIFY_WEBHOOK_SECRET");
  if (!expectedSecret) {
    // Fail closed. An unset secret is a misconfiguration, and the safe reading of
    // a misconfiguration on an endpoint like this one is "send nothing".
    console.error("NOTIFY_WEBHOOK_SECRET is not set — refusing every request.");
    return new Response("Forbidden", { status: 403 });
  }
  if (!secretMatches(req.headers.get("x-notify-secret"), expectedSecret)) {
    return new Response("Forbidden", { status: 403 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  const claimed = payload.record;
  if (payload.type !== "INSERT" || payload.table !== "notifications" || !claimed) {
    return new Response("Ignored", { status: 200 });
  }

  // `id` is a bigserial. Anything that is not a whole number would reach
  // PostgREST as a malformed bigint and come back as a 500 that reads like an
  // outage; refusing it here keeps a bad request looking like a bad request.
  const id = Number(claimed.id);
  if (!Number.isSafeInteger(id) || id <= 0) {
    return new Response("Bad request", { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // The id is the only thing the body is believed about. Everything the push
  // actually says — the audience, the recipient, the title, the body — comes back
  // out of the table, so a request cannot invent a notification.
  const { data: row, error: rowError } = await supabase
    .from("notifications")
    .select(
      "id, audience, restaurant_id, user_id, partner_email, kind, title, body, order_id, data",
    )
    .eq("id", id)
    .maybeSingle();

  if (rowError) {
    console.error("Notification read failed:", rowError.message);
    return new Response("Notification read failed", { status: 500 });
  }
  if (!row) {
    // No such row. Either it was deleted between the insert and this call, or the
    // caller made the id up. Neither is worth a retry.
    return new Response("No such notification", { status: 200 });
  }

  const n = row as NotificationRecord;

  const sa = serviceAccountFor(n.audience);
  if (!sa) {
    // Push not configured for this audience yet. The in-app inbox row still
    // exists — this is a missing channel, not a failure.
    return new Response(`Push not configured for ${n.audience}`, { status: 200 });
  }

  // Find the devices this row is addressed to, by the recipient column its
  // audience uses.
  const column = n.audience === "restaurant"
    ? "restaurant_id"
    : n.audience === "customer"
    ? "user_id"
    : "partner_email";
  const value = n.audience === "restaurant"
    ? n.restaurant_id
    : n.audience === "customer"
    ? n.user_id
    : n.partner_email;

  if (!value) {
    return new Response("Row has no recipient", { status: 200 });
  }

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("audience", n.audience)
    .eq(column, value);
  if (error) {
    console.error("Token read failed:", error.message);
    return new Response("Token read failed", { status: 500 });
  }
  if (!tokens || tokens.length === 0) {
    return new Response("No devices", { status: 200 });
  }

  const accessToken = await getAccessToken(sa);
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  // The data payload the app reads on tap. Only order_id when there is one.
  // FCM data values must be strings, so the row's jsonb is flattened one level —
  // numbers become their decimal text and the device parses them back.
  const data: Record<string, string> = { kind: n.kind };
  if (n.order_id) data.order_id = n.order_id;
  if (n.data) {
    for (const [key, value] of Object.entries(n.data)) {
      if (value !== null && value !== undefined) data[key] = String(value);
    }
  }

  const silent = SILENT_KINDS.has(n.kind);

  // A data-only message is delivered to a sleeping app only at high priority,
  // and even then Android may hold it if the app is dozing. That is the honest
  // ceiling of the live card below Android 16 and it is the same for every
  // sender — nothing here can raise it.
  // The APNs half, and it is not decoration: iOS drops a data-only message that
  // does not carry `content-available`, so before this block existed the live
  // card could not have worked on an iPhone at all — the app was never woken to
  // draw it. Android needs no such declaration, which is why the omission was
  // invisible for as long as Android was the only platform.
  //
  //   * `apns-push-type` is mandatory from iOS 13 and the send is rejected
  //     outright without it.
  //   * priority 5 for a silent push because Apple *requires* 5 for
  //     `background`; sending 10 gets the message throttled or dropped, not
  //     delivered faster.
  //   * `content-available: 1` is the wake itself.
  //
  // What this buys is a few seconds of runtime, not a guarantee. iOS budgets
  // background wakes and will delay or skip them on a low battery — the honest
  // ceiling of the live card on iOS, and the reason a push-to-start token is the
  // eventual upgrade (see IOS_HANDOVER.md). It is the same *kind* of ceiling
  // Android has with Doze, and neither is something this function can raise.
  const apns: Record<string, unknown> = silent
    ? {
      headers: { "apns-push-type": "background", "apns-priority": "5" },
      payload: { aps: { "content-available": 1 } },
    }
    : {
      headers: { "apns-push-type": "alert", "apns-priority": "10" },
      // `sound` here is the counterpart of the Android channel's importance:
      // iOS has no channels, so the alerting behaviour rides on each message.
      payload: { aps: { sound: "default" } },
    };

  const message: Record<string, unknown> = silent
    ? {
      android: { priority: "high" },
      apns,
      data,
    }
    : {
      notification: { title: n.title, body: n.body ?? "" },
      android: {
        priority: "high",
        notification: { channel_id: CHANNEL[n.audience] },
      },
      apns,
      data,
    };

  let sent = 0;
  for (const { token } of tokens) {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message: { token, ...message } }),
    });

    if (res.ok) {
      sent++;
    } else if (res.status === 404 || res.status === 400) {
      // UNREGISTERED / invalid — the device is gone. Prune it.
      await supabase.from("device_tokens").delete().eq("token", token);
    } else {
      console.error(`FCM send failed (${res.status}):`, await res.text());
    }
  }

  return new Response(JSON.stringify({ devices: tokens.length, sent }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
