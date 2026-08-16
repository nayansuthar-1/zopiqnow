-- A kitchen can be rung, not just pinged.
--
-- The vendor app now draws its own new-order notification so it can ring like a
-- call until the order is accepted or rejected. To do that it needs FCM to send
-- **data only** — a message carrying a `notification` block is drawn by Android
-- itself, and Android will not add `FLAG_INSISTENT`, so the kitchen gets one
-- ping instead of a ring.
--
-- But a data-only message sent to a build that predates this change shows
-- **nothing at all** when the app is killed. That is a missed order, which on
-- this platform is money. So the device says whether it can ring, the sender
-- reads it, and old installs keep the notification block until the day they
-- update. The flag flips itself: every launch re-registers the token.
--
-- Nothing here is vendor-specific in the schema — the column is on
-- `device_tokens` generally — but only `send-order-push` reads it today.

alter table public.device_tokens
  add column if not exists rings_new_orders boolean not null default false;

comment on column public.device_tokens.rings_new_orders is
  'True when this install draws its own new-order notification and can therefore '
  'be sent a data-only FCM message. False (the default) means the sender must '
  'include a notification block or the device shows nothing while killed.';

-- The registration RPC gains a parameter.
--
-- ⚠️ Dropping the 3-arg signature is not optional: adding a 4th argument
-- *creates an overload* rather than replacing the function, and two overloads
-- reachable by the same call is how an app ends up bound to the wrong one. The
-- new parameter carries a default, so a 3-argument call — which is exactly what
-- every already-installed build sends — still resolves here and still works.
drop function if exists public.register_device_token(text, text);
drop function if exists public.register_device_token(text, text, text);

create function public.register_device_token(
  p_token    text,
  p_platform text default 'android',
  -- What the *app* says it is: 'customer', 'rider' or 'restaurant'. Null from
  -- an older build, which falls back to inference below.
  p_audience text default null,
  -- Whether this install can be sent a data-only new-order message. Defaults
  -- to false so an older build, which does not send it at all, is treated as
  -- what it is: a device that still needs Android to draw the notification.
  p_rings_new_orders boolean default false
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
  v_rings      boolean := coalesce(p_rings_new_orders, false);
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
    insert into public.device_tokens
      (token, audience, restaurant_id, platform, rings_new_orders, updated_at)
    values
      (p_token, 'restaurant', v_restaurant, coalesce(p_platform, 'android'),
       v_rings, now())
    on conflict (token) do update
      set audience = 'restaurant', restaurant_id = excluded.restaurant_id,
          user_id = null, partner_email = null,
          platform = excluded.platform,
          rings_new_orders = excluded.rings_new_orders,
          updated_at = now();

  elsif v_audience = 'rider' then
    if v_rider is null then
      raise exception 'You are not a Zopiqnow delivery partner.'
        using errcode = 'P0001';
    end if;
    insert into public.device_tokens
      (token, audience, partner_email, platform, rings_new_orders, updated_at)
    values
      (p_token, 'rider', v_rider, coalesce(p_platform, 'android'), v_rings, now())
    on conflict (token) do update
      set audience = 'rider', partner_email = excluded.partner_email,
          restaurant_id = null, user_id = null,
          platform = excluded.platform,
          rings_new_orders = excluded.rings_new_orders,
          updated_at = now();

  elsif v_audience = 'customer' then
    if v_user is null then
      raise exception 'Please sign in before registering for notifications.'
        using errcode = 'P0001';
    end if;
    insert into public.device_tokens
      (token, audience, user_id, platform, rings_new_orders, updated_at)
    values
      (p_token, 'customer', v_user, coalesce(p_platform, 'android'), v_rings, now())
    on conflict (token) do update
      set audience = 'customer', user_id = excluded.user_id,
          restaurant_id = null, partner_email = null,
          platform = excluded.platform,
          rings_new_orders = excluded.rings_new_orders,
          updated_at = now();

  else
    raise exception 'Unknown notification audience: %', v_audience
      using errcode = 'P0001';
  end if;
end;
$$;

-- Born PUBLIC-executable and granted to `authenticated` by default; both routes
-- have to be closed before the one deliberate grant is made.
revoke all on function
  public.register_device_token(text, text, text, boolean) from public;
revoke all on function
  public.register_device_token(text, text, text, boolean) from anon;
revoke all on function
  public.register_device_token(text, text, text, boolean) from authenticated;

grant execute on function
  public.register_device_token(text, text, text, boolean) to authenticated;
