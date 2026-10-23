-- ---------------------------------------------------------------------------
-- 0169 — a delisted kitchen stays delisted, even for a customer who ate there.
-- ---------------------------------------------------------------------------
-- Eleven of the twelve restaurants on this platform are delisted. The feed
-- shows three: Sadri Test Restaurant, which is the active one, and 9Tiz Cafe
-- and Shiv Fast Food, which are not. Tapping either opens an empty menu —
-- `menu_items`' policy (0032, 0068) asks `r.is_active` and gets the right
-- answer, so the card is there and the food behind it is not.
--
-- The cause is 0100's second policy. It restored the restaurants a customer has
-- ordered from, because 43 of the 51 orders in this database were placed with
-- kitchens that 0100's *new* service-area clause was about to hide, and a
-- boundary drawn afterwards must not blank out somebody's own history. That was
-- right, and the file said plainly what it was not:
--
--     Closing a restaurant is `is_active`, and this is not that.
--
-- Except that it is. The policy was written standalone —
--
--     using (exists (select 1 from orders o where o.restaurant_id = …))
--
-- — with no `is_active` clause of its own, and permissive policies are OR'd. So
-- it did not merely re-admit out-of-area kitchens; it re-admitted *delisted*
-- ones, to every customer who had ordered from them, in every surface that
-- leans on the policy to mean "the catalogue". Which is all of them: the feed
-- and search filter on `service_area_id` and nothing else, by design, and
-- favourites says so in a comment that has quietly been false since 0100 —
--
--     A favourited restaurant that has since been delisted embeds as null:
--     the catalog policy is `using (is_active)`.
--
-- One clause restores all of it. The union becomes
--
--     is_active and (serviceable_point(…) or you ordered from it)
--
-- which is what 0100 meant: `is_active` is ops' switch and stands in front of
-- both doors, and the order-history exception reaches only past the service
-- area, which is the boundary it was written for.
--
-- ## What this costs the order list, and why it is already handled
--
-- A customer's own history joins `restaurants` for two things, and that join
-- now embeds null for a delisted kitchen. The order datasource has expected
-- exactly that since it was written:
--
--     The catalog join is for the photo and the kitchen's phone number — the
--     name is on the order, so a delisted restaurant costs us an image and a
--     number, not an identity.
--
-- `restaurant_name` is frozen on the order row, `_orderFrom` reads the embed as
-- nullable, and the invoice is `order_invoice` (0063), a definer function that
-- never consulted a policy. So a past order keeps its name, its lines, its
-- totals and its receipt, and loses the logo of a restaurant that is no longer
-- on the platform. Nothing in the app needs a release for this.
--
-- ## Not fixed in the client, on purpose
--
-- The feed could have grown `.eq('is_active', true)`, and search, and the
-- favourites embed. Three filters, three files, one of them needing `!inner` to
-- reach an embedded resource — and the next surface that queries the catalogue
-- would be the fourth place to forget. 0100 chose a policy over three call
-- sites for that reason and the reason holds; it is the policy that was wrong,
-- not the choice to have one.
-- ---------------------------------------------------------------------------

drop policy if exists "a restaurant you ordered from stays readable" on public.restaurants;
create policy "a restaurant you ordered from stays readable"
  on public.restaurants for select
  using (
    -- The new clause. Ops' delisting is not reachable past order history.
    is_active
    and exists (
      select 1 from public.orders o
       where o.restaurant_id = restaurants.id
         -- `orders.user_id` is `text`, not `uuid` — the cast is on the uuid so
         -- the comparison stays sargable against the column's own index.
         and o.user_id = auth.uid()::text
    )
  );

-- The staff policy (0009, `id = staff_restaurant_id()`) is untouched and still
-- carries no `is_active`: a delisted restaurant must keep its own vendor app,
-- which is the moment it most needs one. It is scoped to one row and to a
-- member of that one kitchen's staff, so it cannot widen a catalogue.
