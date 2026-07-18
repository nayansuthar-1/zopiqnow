// send-order-push — rings a kitchen's devices when a new order lands.
//
// Invoked by the database webhook on `orders` INSERT (see migration 0021). It
// reads the FCM tokens registered for the order's restaurant (0020), mints a
// short-lived Google access token from the service account, and posts a
// notification to each device through the FCM HTTP v1 API. A token FCM reports
// as dead is pruned on the spot, so the table doesn't rot.
//
// The one secret this needs is FCM_SERVICE_ACCOUNT — the Admin SDK service
// account JSON, set as a function secret, never committed. SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are injected by the platform.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface OrderRecord {
  id: string;
  restaurant_id: string;
  restaurant_name: string | null;
  total: number | null;
  status: string;
}

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: OrderRecord | null;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri: string;
  project_id: string;
}

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

// --- The function ---

Deno.serve(async (req) => {
  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  const order = payload.record;
  // Only a brand-new order rings. Updates (status marching to delivered) don't.
  if (payload.type !== "INSERT" || payload.table !== "orders" || !order) {
    return new Response("Ignored", { status: 200 });
  }
  if (order.status !== "placed") {
    return new Response("Not a new order", { status: 200 });
  }

  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saRaw) {
    console.error("FCM_SERVICE_ACCOUNT is not set.");
    return new Response("Not configured", { status: 500 });
  }
  const sa: ServiceAccount = JSON.parse(saRaw);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("restaurant_id", order.restaurant_id);
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

  const rupees = order.total != null ? `₹${order.total}` : "";
  const title = "New order";
  const body = [order.restaurant_name, rupees].filter(Boolean).join(" · ") ||
    "You have a new order.";

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
          notification: { title, body },
          android: {
            priority: "high",
            notification: { channel_id: "new_orders" },
          },
          data: { order_id: order.id },
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
