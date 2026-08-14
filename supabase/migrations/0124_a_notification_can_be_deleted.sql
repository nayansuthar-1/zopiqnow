-- A notification can be deleted.
--
-- The inbox has been read-only since 0047: `mark_notification_read` and
-- `mark_all_notifications_read` are the only two writes a customer has, and
-- `notifications` carries RLS with no write policy and — since 0089 — no write
-- privilege either. So there was no route to a delete, by design rather than by
-- omission, and an inbox that only ever grows is one nobody opens twice.
--
-- An RPC rather than a DELETE policy, for the reason 0089 exists: a policy would
-- mean granting `authenticated` the DELETE privilege on the table and then
-- relying on the policy alone to scope it. That is the shape S4 found
-- twenty-eight tables in, and the lesson was that RLS should not be the only
-- guard. A definer function keeps the privilege off the role entirely.
--
-- Takes an array, because the screen deletes a selection. One round trip for
-- twenty rows rather than twenty, and — more to the point — one transaction, so
-- a selection cannot half-delete.

create or replace function public.delete_my_notifications(p_ids bigint[])
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id text := auth.uid()::text;
  v_deleted integer;
begin
  if v_user_id is null then
    raise exception 'You need to be signed in.';
  end if;

  if p_ids is null or cardinality(p_ids) = 0 then
    return 0;
  end if;

  -- A ceiling, in the S6 shape: this is cheap per row, but an unbounded array
  -- from a client is an unbounded statement, and the screen cannot select more
  -- than a page anyway.
  if cardinality(p_ids) > 200 then
    raise exception 'Too many at once. Select up to 200.';
  end if;

  -- **`user_id` is the whole guard.** The function is definer, so it is not
  -- subject to the caller's RLS — the `where` is what stops one customer
  -- deleting another's inbox by guessing ids. It is checked here rather than
  -- trusted from the array, and a row that is not theirs simply does not match
  -- rather than raising, so a stale id in a selection cannot fail the batch.
  delete from public.notifications
   where id = any(p_ids)
     and user_id = v_user_id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$;

-- 0087's standing rule: born executable by PUBLIC, and both roles inherit it.
revoke execute on function public.delete_my_notifications(bigint[])
  from public, anon, authenticated;
grant execute on function public.delete_my_notifications(bigint[])
  to authenticated;

comment on function public.delete_my_notifications(bigint[]) is
  'Deletes the caller''s own notifications by id. Returns how many were removed; '
  'ids belonging to anyone else are silently skipped rather than raising.';

-- ---------------------------------------------------------------- verification
-- Run the 0087 and 0089 footers verbatim; both returned zero rows after this.
-- And the guard itself, which is the claim worth proving:
--
--   select set_config('request.jwt.claims',
--            json_build_object('sub','<user-a>','role','authenticated')::text, true);
--   select public.delete_my_notifications(array[<an id belonging to user-b>]);
--   -- must return 0, and user-b's row must still be there.
