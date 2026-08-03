-- 0093 - a vouch is a privileged act
--
-- Ship-plan S9, 3 August 2026. The audit itself found the gate sound; this file
-- is the two things it found wrong on the way. What was verified is in the ship
-- plan.
--
-- The gate needed no change. `rider_work_block` is called by `set_rider_online`,
-- `available_deliveries`, `claim_delivery` and `accept_offer`, and
-- `rider_is_verified` by `offer_delivery` - all five confirmed in the *live*
-- function bodies, not in the migration that wrote them. Ten document states were
-- exercised against all five paths and every one behaved: an expired licence
-- blocks exactly as a missing one does, and says which document and on what date.
--
-- --------------------------------------------------------------------------
-- 1. An override is the most powerful switch in the product, and nothing
--    recorded it.
-- --------------------------------------------------------------------------
--
-- `rider_override_active` returns true when `override_reason` is set and
-- `override_until` is either in the future **or null**. A null is a permanent
-- bypass, and it defeats every other condition at once: a rider whose documents
-- were *rejected*, whose licence expired four hundred days ago and whose
-- insurance lapsed with it still passes all five gates. Proven, not inferred -
-- that exact row was constructed and every path answered `ALLOWED`.
--
-- That is a legitimate power. A partner whose papers are genuinely with the RTO
-- should not lose a week's earnings to a queue, and 0083 built it deliberately.
-- But it is the one action in this system that puts an unverified stranger at a
-- customer's door, and until now the only trace of it was the row itself - which
-- the next override overwrites.
--
-- So `rider_legal` joins 0092's trail. **Every** insert and update, not a
-- filtered subset: this table holds one row per rider and every write to it is a
-- KYC decision, a vouch, or a document being renewed. There is no noise to
-- exclude, and `detail` keeps the before and after, so an override that is
-- granted and then quietly widened is two rows rather than one silent edit.
--
-- Note what this does *not* change: the null `override_until` still means
-- permanent. Making it expire by force is a product decision about people's
-- livelihoods, not a migration, and it is written up in the ship plan for you to
-- settle rather than decided here.

create trigger rider_legal_audit_insert after insert on public.rider_legal
  for each row execute function public.record_admin_action('partner_email');

create trigger rider_legal_audit_update after update on public.rider_legal
  for each row execute function public.record_admin_action('partner_email');

-- --------------------------------------------------------------------------
-- 2. The refusal a rejected rider reads is missing a full stop.
-- --------------------------------------------------------------------------
--
-- `rider_work_block` builds the rejected message by concatenating the admin's
-- reason with a fixed sentence:
--
--     coalesce(nullif(trim(rejected_reason), ''), 'Your documents were not
--       accepted.') || ' Call Zopiqnow support to sort it out.'
--
-- The fallback ends in a full stop and reads correctly. A reason typed by a human
-- into the console does not, and the rider is shown:
--
--     The licence photo was unreadable Call Zopiqnow support to sort it out.
--
-- Two sentences run together. This is the message a partner reads when they have
-- been stopped from earning, so it is worth the four characters. `rtrim(…, ' .')`
-- means a reason typed *with* a full stop does not end up with two.
--
-- Everything else in this function is unchanged from the live definition.

create or replace function public.rider_work_block(p_email text)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_vehicle text;
  v_legal   public.rider_legal%rowtype;
begin
  select vehicle into v_vehicle
    from public.delivery_partners where email = p_email;

  if not found then
    return 'You are not a Zopiqnow delivery partner.';
  end if;

  if public.rider_override_active(p_email) then
    return null;
  end if;

  select * into v_legal
    from public.rider_legal where partner_email = p_email;

  if not found or v_legal.status = 'pending' then
    return 'Your documents are still being checked. You can start taking deliveries as soon as they are verified.';
  end if;

  if v_legal.status = 'rejected' then
    -- The reason is typed by a person and rarely ends in a full stop; the
    -- sentence after it always begins one. Trimming any trailing stop and then
    -- adding exactly one is what stops "…unreadable Call Zopiqnow support".
    return rtrim(
             coalesce(
               nullif(trim(v_legal.rejected_reason), ''),
               'Your documents were not accepted'
             ),
             ' .'
           ) || '. Call Zopiqnow support to sort it out.';
  end if;

  if v_vehicle <> 'bicycle' then
    if v_legal.licence_expiry < current_date then
      return 'Your driving licence expired on '
             || to_char(v_legal.licence_expiry, 'DD Mon YYYY')
             || '. Send us the renewed one to start taking deliveries again.';
    end if;
    if v_legal.insurance_expiry < current_date then
      return 'Your insurance expired on '
             || to_char(v_legal.insurance_expiry, 'DD Mon YYYY')
             || '. Send us the renewed policy to start taking deliveries again.';
    end if;
  end if;

  return null;
end;
$function$;

revoke execute on function public.rider_work_block(text) from public, anon;
grant execute on function public.rider_work_block(text) to authenticated;
