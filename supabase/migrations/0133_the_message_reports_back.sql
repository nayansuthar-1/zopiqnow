-- ---------------------------------------------------------------------------
-- 0133 — the message reports back.
-- ---------------------------------------------------------------------------
-- 0132 sends an order confirmation over WhatsApp and then goes deaf. The only
-- trace of what happened is `net._http_response`, and all that records is that
-- Meta *accepted* the request — a 200 there means "queued", not "delivered".
-- A customer whose number has no WhatsApp account, a message blocked, a
-- template paused: every one of those is a 200 at send time and silence after.
--
-- Meta reports the rest over a webhook, which nothing was listening for. This
-- is the table it lands in; `supabase/functions/whatsapp-webhook` is the ear.
--
-- **Two event kinds are worth keeping and the rest is noise.**
--
--   * `message_status` — sent → delivered → read, or failed with a reason. This
--     is the answer to "did the confirmation actually arrive", which we have
--     never been able to answer.
--   * `template_status` — Meta's review verdict on a template, which today
--     means finding out `zopiq_order_confirmed` went APPROVED without anybody
--     polling for it.
--
-- Anything else Meta sends (inbound messages, account updates) is stored under
-- its own field name with the raw payload and nothing extracted. Storing it
-- costs nothing and guessing wrong about what matters later costs a migration.
--
-- **This is a log, not state.** Nothing in the app reads it and nothing should
-- start: it is for answering questions with `select`, and for a future job that
-- wants to know which numbers are not reachable on WhatsApp. It is not the
-- source of truth for anything.

create table if not exists public.whatsapp_events (
  id         bigserial primary key,

  -- 'message_status', 'template_status', or Meta's raw field name for anything
  -- else. Not a check constraint: this mirrors a vocabulary Meta owns and
  -- extends without telling us, and a webhook that raises on an unknown field
  -- is a webhook Meta disables after enough non-200s.
  kind       text not null,

  -- The WhatsApp message id for a status, the template name for a verdict.
  -- Null for anything we did not recognise.
  subject    text,

  -- The customer's number, digits only, as Meta reports it. Only meaningful on
  -- a message status.
  recipient  text,

  -- 'sent' | 'delivered' | 'read' | 'failed' for a message;
  -- 'APPROVED' | 'REJECTED' | 'PAUSED' | … for a template.
  status     text,

  -- The error title, or the rejection reason. The *why*, when there is one.
  detail     text,

  -- Everything, verbatim. The extracted columns above are a convenience and
  -- this is the record.
  payload    jsonb not null,

  created_at timestamptz not null default now()
);

create index if not exists whatsapp_events_recent_idx
  on public.whatsapp_events (created_at desc);

-- Failed sends are the reason this table exists; make finding them cheap.
create index if not exists whatsapp_events_failures_idx
  on public.whatsapp_events (recipient)
  where status = 'failed';

-- RLS on with no policies at all, which is a closed door rather than an open
-- one — and the grants revoked besides, because a new table arrives writable by
-- `anon` (RLS hides that, and RLS does not cover TRUNCATE). Only the service
-- role, which is what the Edge Function holds, gets in.
alter table public.whatsapp_events enable row level security;
revoke all on public.whatsapp_events from anon, authenticated;
revoke all on sequence public.whatsapp_events_id_seq from anon, authenticated;
