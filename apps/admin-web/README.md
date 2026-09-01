# Zopiqnow admin console

The web console restaurants, riders and orders are administered from. React + Vite +
Tailwind, deployed on Vercel, talking to Supabase through named `security definer` RPCs —
never to a table directly.

```bash
npm install
cp .env.example .env.local   # fill from the repo-root .env
npm run dev                  # vite, on :5173
npm run build                # tsc -b && vite build
npm run lint                 # oxlint — this should print nothing at all
```

Only the anon key reaches the browser. Authority is the signed-in admin's own JWT: every
RPC re-asks `is_admin()` server-side, where the answer cannot be edited in a devtools
console. `VITE_GOOGLE_MAPS_BROWSER_KEY` is optional — without it the address step falls
back to two typed coordinate fields and says so.

## Getting in

Email and password, against `auth.users`. There is no sign-up and **no password reset
link**, and both are deliberate: either would be a way into an ops console that does not
begin with an existing admin. An admin exists because another admin made them one, from
Settings, which creates the account and sets the first password
(`0153_an_admin_is_made_with_a_password_not_a_promise.sql`).

The cost of that decision is the runbook below. A forgotten password is not recoverable
from inside the console by anybody, including the person who forgot it.

## Locked out: resetting a console password

Needs the database password — so whoever holds that, and nobody else. Everything here is
one address at a time and none of it is reversible, so read the row before writing it.

Connect with the pooler (`psql` from the repo root; the ref and password are
`SUPABASE_PROJECT_REF` and `SUPABASE_DB_PASSWORD` in the repo-root `.env`, and do **not**
try to `source` that file in bash — it eats the Windows backslashes):

```
postgresql://postgres.<project-ref>:<db-password>@aws-1-ap-northeast-2.pooler.supabase.com:6543/postgres
```

**1. Confirm they are actually an admin.** If this returns nothing, a password is not
their problem — they were never granted the console.

```sql
select email, name from public.platform_admins where email = lower('them@example.com');
```

**2. Confirm the account exists, and is the one you think.**

```sql
select id, email, email_confirmed_at, deleted_at, last_sign_in_at
  from auth.users
 where lower(email) = lower('them@example.com');
```

A `deleted_at` that is not null is a soft-deleted row: it still holds the address, and it
cannot be signed in with. That is a different repair from this one.

**3. Set the new password.** Hand it over in person, the way Settings does — it is not
mailed, and there is nothing to show it again.

```sql
update auth.users
   set encrypted_password = extensions.crypt('<the new password>', extensions.gen_salt('bf', 10)),
       updated_at = now()
 where lower(email) = lower('them@example.com')
   and deleted_at is null;
```

`extensions.` is not decoration — pgcrypto lives in the `extensions` schema and
`search_path` is pinned to `public`. Cost 10 is what GoTrue itself writes; a different cost
still verifies, but stop matching it and you have two conventions in one table.

**4. End the sessions the old password opened.** Not strictly required to get them back in,
but a reset that leaves an old session alive has not actually taken anything away.

```sql
delete from auth.sessions
 where user_id = (select id from auth.users where lower(email) = lower('them@example.com'));
```

**5. If sign-in answers HTTP 500 with a body of `{}`**, the row was written by hand and is
missing things GoTrue reads into Go `string`s, which cannot hold NULL. It names no column
and there is nothing to search for — check for nulls and fill them with `''`:

```sql
select confirmation_token, recovery_token, email_change, email_change_token_new,
       email_change_token_current, phone_change, phone_change_token, reauthentication_token
  from auth.users where lower(email) = lower('them@example.com');
```

```sql
update auth.users
   set confirmation_token         = coalesce(confirmation_token, ''),
       recovery_token             = coalesce(recovery_token, ''),
       email_change               = coalesce(email_change, ''),
       email_change_token_new     = coalesce(email_change_token_new, ''),
       email_change_token_current = coalesce(email_change_token_current, ''),
       phone_change               = coalesce(phone_change, ''),
       phone_change_token         = coalesce(phone_change_token, ''),
       reauthentication_token     = coalesce(reauthentication_token, '')
 where lower(email) = lower('them@example.com');
```

The unique indexes on those columns are partial (`WHERE token !~ '^[0-9 ]*$'`), and `''`
matches that pattern, so every account can carry `''` without colliding.

**6. If sign-in is refused as though the address does not exist**, the account has no
`auth.identities` row for the `email` provider, and GoTrue cannot resolve the sign-in at
all:

```sql
select provider, provider_id from auth.identities
 where user_id = (select id from auth.users where lower(email) = lower('them@example.com'));
```

`auth.identities.email` is a **generated** column reading `identity_data->>'email'`.
Naming it in an insert is an error, not a redundancy — set the address in the JSON:

```sql
insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
select u.id::text, u.id,
       jsonb_build_object('sub', u.id::text, 'email', lower(u.email),
                          'email_verified', true, 'phone_verified', false),
       'email', now(), now()
  from auth.users u
 where lower(u.email) = lower('them@example.com');
```

**Then check it from outside**, rather than assuming: sign in at the console. A row that
looks right in `psql` and a row GoTrue accepts are two different claims, and only the
second one matters.

## Removing an admin

From Settings, not from `psql` — `admin_remove_admin` (`0038_admin_roster.sql:78`) refuses
to remove you from your own session and refuses to remove the last admin on the roster,
and neither of those guards is in a `delete` typed at three in the morning.

It takes the `platform_admins` row and nothing else, which is right: the person keeps
whatever Zopiqnow access they had as a customer, a rider or a restaurant's owner. Deleting
their `auth.users` row instead would take that with it.
