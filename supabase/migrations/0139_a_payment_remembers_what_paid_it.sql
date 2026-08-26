-- ---------------------------------------------------------------------------
-- 0139 — a payment remembers what paid it.
-- ---------------------------------------------------------------------------
-- Checkout stopped filtering Razorpay's payment methods. It used to send
-- `method: {upi: true, card: false, …}`, which was launch C1's UPI-only decision
-- expressed on the device — and which produced an empty sheet and Razorpay's
-- "No appropriate payment method found" the moment the merchant account turned
-- out to have UPI disabled pending KYC. The account exposes what it can take;
-- filtering that from the phone can only ever subtract.
--
-- So the sheet now shows whatever is enabled — card today, UPI the day
-- activation lands, netbanking and wallets if they are ever turned on — and it
-- does that with no release, for the same reason setting the keys needed none.
--
-- ## Why `orders.payment_method` is not what changes
--
-- The obvious move is a third value next to `cod` and `upi`. It is the wrong
-- one, because **nothing downstream distinguishes instruments** — every consumer
-- asks the binary question "is this cash?":
--
--     rider   job.dart          isCash: payment_method == 'cod'
--     vendor  vendor_order.dart value == 'upi' ? upi : cod
--     admin   LiveOrdersPage    payment_method === 'upi' ? 'prepaid' : 'cash…'
--     0085    payment gate      if new.payment_method <> 'upi' then return new
--     0003    prepaid_order_has_a_payment_id, and place_order's own check
--
-- A new `'card'` would read as **cash** in the first three, **skip the payment
-- gate** in the fourth, and be accepted **with no payment id** by the fifth.
-- Four silent misclassifications of money already taken, to record a difference
-- nobody asks about. `upi` in this schema has never meant UPI; it has meant
-- *prepaid*, as against `cod`, and it goes on meaning that.
--
-- ## What is worth recording, and where
--
-- The instrument still matters to exactly one audience: a person answering "the
-- customer says they paid by card." That belongs on `payment_intents`, which is
-- already the Razorpay-facing ledger and already the row both functions write —
-- not on `orders`, which no consumer would read it from.
--
-- `razorpay-verify` fills it in. The checkout callback does not carry the
-- method, so the function reads the payment back from Razorpay with the same
-- credentials it already holds. Null stays a perfectly good answer: an intent
-- that was never verified never had an instrument, and a lookup that fails must
-- not cost a customer their order.
--
-- No constraint on the values. Razorpay's vocabulary (`card`, `upi`,
-- `netbanking`, `wallet`, `emi`, `paylater`, …) is Razorpay's to extend, and a
-- `check (…in…)` restated here would be one more thing to drift — see the
-- constraint this project has already had to repair for exactly that reason.
-- ---------------------------------------------------------------------------

alter table public.payment_intents
  add column if not exists instrument text;

comment on column public.payment_intents.instrument is
  '0139: what Razorpay says actually paid — card, upi, netbanking, wallet… Null until verified, and null is not an error.';
