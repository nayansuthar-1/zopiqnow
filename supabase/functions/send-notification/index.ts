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
//   * FCM_SERVICE_ACCOUNT_RESTAURANT   project (the vendor already does).
// An audience with no service account (neither its own nor the default) is
// skipped, not an error — push for it is simply not configured yet.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.

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
}

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: NotificationRecord | null;
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

// --- The function ---

Deno.serve(async (req) => {
  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  const n = payload.record;
  if (payload.type !== "INSERT" || payload.table !== "notifications" || !n) {
    return new Response("Ignored", { status: 200 });
  }

  const sa = serviceAccountFor(n.audience);
  if (!sa) {
    // Push not configured for this audience yet. The in-app inbox row still
    // exists — this is a missing channel, not a failure.
    return new Response(`Push not configured for ${n.audience}`, { status: 200 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

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
  const data: Record<string, string> = { kind: n.kind };
  if (n.order_id) data.order_id = n.order_id;

  let sent = 0;
  for (const { token } of tokens) {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: n.title, body: n.body ?? "" },
          android: {
            priority: "high",
            notification: { channel_id: CHANNEL[n.audience] },
          },
          data,
        },
      }),
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
