-- 0087 - a revoke that did nothing
--
-- Found by the ship-plan authorization sweep (S1), 3 August 2026.
--
-- Migration 0086 ends its definition of `order_receipt_by_key` with:
--
--     revoke all on function public.order_receipt_by_key(text, text)
--       from anon, authenticated;
--
-- That line has no effect, and the function it was meant to lock has been
-- callable by anyone holding the anon key since the day it shipped. Proven over
-- HTTP, not inferred: a POST to /rest/v1/rpc/order_receipt_by_key carrying only
-- the anon key - the key that ships in plaintext inside every APK and IPA -
-- returns 200.
--
-- The reason is that `anon` and `authenticated` were never the only grantees.
-- Every function created in this database is born with EXECUTE granted to
-- PUBLIC, and both roles are members of PUBLIC. Revoking a role's own grant
-- leaves the one it inherits. Checked rather than assumed:
--
--     create function public.zz_probe() returns int language sql as 'select 1';
--     -- acl: =X/postgres postgres=X/postgres authenticated=X/postgres ...
--     --      ^ that leading empty grantee is PUBLIC
--
-- `alter default privileges ... revoke execute on functions from public` does
-- not prevent it here. The stored default-ACL row for postgres in `public`
-- already carries no PUBLIC entry, the statement changes nothing, and new
-- functions still arrive with one. **So the only thing that closes this is an
-- explicit `revoke ... from public` per function, and every future migration
-- that creates a function owned by postgres has to carry one.**
--
-- Audit SEC-002 swept 51 functions clean on 30 July. Six had come back by 3
-- August - one per recent migration - which is what a point-in-time sweep of a
-- recurring default is worth.
--
-- The six, and what each one was actually exposing:
--
--   order_receipt_by_key   the real hole. SECURITY DEFINER, and it takes the
--                          user id as an *argument* rather than deriving it
--                          from auth.uid(), so the caller names whose receipt
--                          to read. An unauthenticated caller with a
--                          (user_id, idempotency_key) pair gets that order's
--                          delivery address, total and payment id. The key is
--                          128-bit random, so this was not brute-forceable -
--                          but "not brute-forceable" is not the standard.
--
--   place_order            reachable, not exploitable: its first act is
--                          `v_user_id := auth.uid()::text` and it raises when
--                          that is null. anon got a clean refusal. Revoked
--                          anyway - anon has no business reaching it.
--
--   orders_reject_new_cash, orders_require_verified_payment,
--   orders_refund_on_termination, refund_within_the_order
--                          trigger functions. Postgres refuses to call these
--                          directly, so the grant bought nobody anything. They
--                          are here so that "no function of ours is executable
--                          by PUBLIC" is a sentence with no exceptions in it.
--
-- Nothing here changes who is *supposed* to have access: `authenticated` keeps
-- its explicit grant on `place_order`, and `order_receipt_by_key` keeps working
-- for its only caller, which is `place_order` itself - a SECURITY DEFINER
-- function owned by postgres, so it executes as postgres regardless of PUBLIC.

revoke execute on function public.order_receipt_by_key(text, text) from public;

revoke execute on function public.place_order(
  text, text, jsonb, text, text, double precision, double precision,
  text, text, text, text
) from public;

revoke execute on function public.orders_reject_new_cash() from public;
revoke execute on function public.orders_require_verified_payment() from public;
revoke execute on function public.orders_refund_on_termination() from public;
revoke execute on function public.refund_within_the_order() from public;

-- The check that keeps this closed. Run it before every release; it must return
-- zero rows. When it does not, the named function was created by a migration
-- that forgot its `revoke ... from public`.
--
--   select p.proname
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and pg_get_userbyid(p.proowner) = 'postgres'
--      and exists (
--            select 1 from aclexplode(p.proacl) a where a.grantee = 0
--          );
