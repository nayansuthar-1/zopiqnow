-- ---------------------------------------------------------------------------
-- 0060 — a token belongs to an app, not to a person's job.
-- ---------------------------------------------------------------------------
-- 0047 worked out what kind of device it was being handed by looking at *who
-- was signed in*: staff of a restaurant meant a restaurant device, a delivery
-- partner meant a rider device, anyone else meant a customer. That reads
-- sensibly and is wrong, because it answers a question nobody asked. The token
-- does not belong to a person's role. It belongs to an **installed app**, and
-- the only party that knows which app is calling is the app.
--
-- One person holding two roles is all it takes. `nayansuthar969@gmail.com` is
-- staff at `r1` and also an ordinary customer with an order in flight. Signing
-- into the *customer* app filed that phone's customer token as
-- `audience = 'restaurant'`, and two things followed:
--
--   * customer pushes are addressed to `audience = 'customer'`, so the phone
--     was simply not in the list and nothing ever arrived — the reported bug;
--   * the customer app was subscribed to `r1`'s **restaurant** notifications,
--     which is somebody else's order traffic on a customer's phone. That is the
--     more serious half, and it was silent.
--
-- This is not a rare configuration. It is every vendor who also orders dinner,
-- and it is every single person who tests this platform.
--
-- **The fix is to stop guessing.** The app states what it is, and the database
-- checks whether it is entitled to say so. Stating is not trusting: a claim of
-- `restaurant` still has to survive `staff_restaurant_id()`, and a claim of
-- `rider` still has to survive `delivery_partner_email()`. A customer app that
-- lied about being a restaurant would be refused by the same predicate 0047
-- used — the difference is that the answer is now *verified* rather than
-- *assumed*.
--
-- **`p_audience` is nullable, and that is deliberate.** There are APKs in the
-- field that call this with two arguments and cannot be updated from here. Null
-- means "no claim", and falls back to 0047's inference — no worse for them than
-- today, and correct for everyone whose roles do not overlap. New builds pass
-- theirs explicitly and are right regardless.
--
-- **Dropped and recreated rather than replaced.** A new argument makes a new
-- signature, and `create or replace` would leave 0047's two-argument version
-- beside it as an overload — with PostgREST free to bind a two-argument call to
-- either. That trap cost us 0045 and this migration is not walking into it
-- again.

drop function if exists public.register_device_token(text, text);
drop function if exists public.register_device_token(text, text, text);

create function public.register_device_token(
  p_token    text,
  p_platform text default 'android',
  -- What the *app* says it is: 'customer', 'rider' or 'restaurant'. Null from
  -- an older build, which falls back to inference below.
  p_audience text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_rider      text;
  v_user       text;
  v_audience   text;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return;
  end if;

  v_restaurant := public.staff_restaurant_id();
  v_rider      := public.delivery_partner_email();
  v_user       := auth.uid()::text;

  -- No claim: 0047's inference, kept only for builds already installed.
  v_audience := coalesce(
    nullif(trim(lower(p_audience)), ''),
    case
      when v_restaurant is not null then 'restaurant'
      when v_rider      is not null then 'rider'
      when v_user       is not null then 'customer'
    end
  );

  if v_audience is null then
    raise exception 'Please sign in before registering for notifications.'
      using errcode = 'P0001';
  end if;

  -- The claim is checked, never taken on faith. Each branch demands the same
  -- predicate 0047 would have used to infer that audience in the first place,
  -- so no app can register itself into an audience it does not belong to.
  if v_audience = 'restaurant' then
    if v_restaurant is null then
      raise exception 'You are not staff of any restaurant.'
        using errcode = 'P0001';
    end if;
    insert into public.device_tokens (token, audience, restaurant_id, platform, updated_at)
    values (p_token, 'restaurant', v_restaurant, coalesce(p_platform, 'android'), now())
    on conflict (token) do update
      set audience = 'restaurant', restaurant_id = excluded.restaurant_id,
          user_id = null, partner_email = null,
          platform = excluded.platform, updated_at = now();

  elsif v_audience = 'rider' then
    if v_rider is null then
      raise exception 'You are not a Zopiqnow delivery partner.'
        using errcode = 'P0001';
    end if;
    insert into public.device_tokens (token, audience, partner_email, platform, updated_at)
    values (p_token, 'rider', v_rider, coalesce(p_platform, 'android'), now())
    on conflict (token) do update
      set audience = 'rider', partner_email = excluded.partner_email,
          restaurant_id = null, user_id = null,
          platform = excluded.platform, updated_at = now();

  elsif v_audience = 'customer' then
    if v_user is null then
      raise exception 'Please sign in before registering for notifications.'
        using errcode = 'P0001';
    end if;
    insert into public.device_tokens (token, audience, user_id, platform, updated_at)
    values (p_token, 'customer', v_user, coalesce(p_platform, 'android'), now())
    on conflict (token) do update
      set audience = 'customer', user_id = excluded.user_id,
          restaurant_id = null, partner_email = null,
          platform = excluded.platform, updated_at = now();

  else
    raise exception 'Unknown notification audience: %', v_audience
      using errcode = 'P0001';
  end if;
end;
$$;

grant execute on function public.register_device_token(text, text, text)
  to authenticated;
