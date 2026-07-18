# send-order-push

Rings a restaurant's registered devices when a new order lands. Invoked by a
database webhook on `orders` INSERT; sends through the FCM HTTP v1 API.

This is the send side of Phase 7 push. The device side (token registration,
foreground display) ships in the app; tokens live in `device_tokens` (migration
0020). This function is the only thing that reads that table and sends.

## What it needs

| Name | What | Set by |
|---|---|---|
| `FCM_SERVICE_ACCOUNT` | The Firebase **Admin SDK** service-account JSON, as one string | You — a function secret. **Never commit it.** |
| `SUPABASE_URL` | Project URL | Injected by the platform |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role, to read tokens past RLS | Injected by the platform |

## Deploy (three steps, all yours — they touch secrets)

1. **Set the service-account secret** (the JSON you downloaded from Firebase →
   Project settings → Service accounts → Generate new private key):

   ```
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat ~/Downloads/zopiqnow-vendor-firebase-adminsdk-xxxx.json)"
   ```

   Or in the dashboard: Edge Functions → Manage secrets → add `FCM_SERVICE_ACCOUNT`,
   paste the whole JSON as the value.

2. **Deploy the function.** It is called by a webhook, not a signed-in user, so
   turn off JWT verification (the webhook authenticates with the service-role
   key on its own header):

   ```
   supabase functions deploy send-order-push --no-verify-jwt
   ```

3. **Create the database webhook** (Dashboard → Database → Webhooks → Create):
   - Table: `public.orders`
   - Events: **Insert** only
   - Type: **Supabase Edge Functions** → `send-order-push`
   - HTTP headers: add `Authorization: Bearer <SERVICE_ROLE_KEY>` (the dashboard
     offers to fill this) so only the webhook can invoke the function.

   The function itself ignores anything that isn't an INSERT of a `placed` order,
   so a stray call does nothing.

## Verify

Place a test order from the customer app (or insert a `placed` row) with a device
signed into that restaurant and the app backgrounded — the phone should buzz with
"New order · <restaurant> · ₹<total>". Function logs show `{ devices, sent }`.

A token FCM reports as dead (404/invalid) is deleted from `device_tokens` on the
spot, so the table stays clean without a cron.
