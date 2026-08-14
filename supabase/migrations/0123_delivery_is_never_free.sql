-- Delivery is never free.
--
-- `v_delivery_fee := case when v_subtotal >= 500 then 0 else 40 end` — a ₹500
-- threshold, in two functions, since 0078's fee stack. It is withdrawn: every
-- order pays the flat ₹40, whatever the basket is worth.
--
-- **The rule lives in exactly two places and they must not drift.** `place_order`
-- charges it and `checkout_preflight` (0120) quotes it, and 0120 exists
-- precisely because a one-rupee disagreement between the quote and the charge is
-- itself a charge-then-refusal: the payment gate refuses an intent worth less
-- than the order. Changing one without the other reintroduces that bug at ₹40 a
-- time, on every basket over ₹500.
--
-- **So this migration edits the live definitions rather than restating them.**
-- Both functions are ~300 lines of money arithmetic. Pasting them into a
-- migration to change one expression means 600 lines of opportunity to
-- mistranscribe a tax line, and this repo has been bitten four times by the
-- file and the database disagreeing. Instead it reads `pg_get_functiondef`,
-- replaces the one expression, and executes the result — the same move 0091
-- made when it removed a header by reading the existing headers rather than
-- writing them out again. It **raises** if the expression is not found, so a
-- future rewrite of either function cannot let this silently no-op.
--
-- `create or replace` preserves the existing ACLs, so 0087's revokes survive.

do $$
declare
  f       record;
  v_def   text;
  v_new   text;
  v_old   constant text := 'case when v_subtotal >= 500 then 0 else 40 end';
  v_count integer := 0;
begin
  for f in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('place_order', 'checkout_preflight')
  loop
    v_def := pg_get_functiondef(f.oid);

    if position(v_old in v_def) = 0 then
      raise exception
        'The free-delivery expression is not in %. It was either already '
        'removed or the function was rewritten; read it before re-running this.',
        f.proname;
    end if;

    -- A bare 40, not a `case` that always yields 40: the next person to read
    -- this should see a flat fee, not a threshold whose branches happen to
    -- match.
    v_new := replace(v_def, v_old, '40');
    execute v_new;
    v_count := v_count + 1;
  end loop;

  if v_count <> 2 then
    raise exception 'Expected to rewrite 2 functions, rewrote %.', v_count;
  end if;
end $$;

-- ---------------------------------------------------------------- verification
-- Both must come back false, and the fee must be 40 on a basket either side of
-- the old threshold. Run the 0087 and 0089 footers as well, verbatim.
--
--   select p.proname,
--          pg_get_functiondef(p.oid) like '%v_subtotal >= 500%' as still_free
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('place_order', 'checkout_preflight');
