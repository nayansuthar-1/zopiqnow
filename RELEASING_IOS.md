# Releasing to the App Store

## The short version

```bash
node tool/ship_ios.mjs --check        # what is set up, what is missing
node tool/ship_ios.mjs customer       # bump, build, upload, wait for processing
node tool/ship_ios.mjs customer <group-id>   # …and hand it to a TestFlight group
```

The iOS counterpart to `tool/ship.mjs`, and deliberately the same shape: bump the
build number, build, upload, and commit the bump **only after Apple has the
binary** — so a failed build never burns a number.

Once the credential below is in place, **Claude can ship a TestFlight build
without you touching anything.** That is the whole point of the API key: it
replaces an Apple ID login, and with it the two-factor prompt that made every
previous step of this pipeline require a human at a keyboard.

---

## First-time setup (once, ~5 minutes)

1. App Store Connect → **Users and Access → Integrations → App Store Connect API**.
2. Generate a key with the **App Manager** role. Admin is more than this needs.
3. Download the `.p8`. **You get exactly one download**, ever.
4. Put it where Apple's uploader already looks, outside the repo:

   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
   chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
   ```

5. Put the three identifiers in `.env` (gitignored — **this repo is public**, and
   a `.p8` is upload access to the store listing):

   ```
   ASC_KEY_ID=XXXXXXXXXX
   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
   ```

   The Issuer ID is a UUID shown *above* the key table on that same page. It is
   not inside the `.p8` and cannot be derived from it.

6. `node tool/ship_ios.mjs --check` — it will say `token accepted` if Apple
   agrees, and name the missing piece if not.

---

## What the script will not do for you

**Create an App Store Connect app record.** The API has no endpoint for it; it is
one of the last things that is still the web UI's alone. `--check` will say
`NO App Store Connect record` for any app missing one, and no amount of retrying
changes that. New apps: App Store Connect → Apps → **+** → New App.

**Write `ExportOptions.plist`.** Each app needs one at `apps/<app>/ios/` naming
its provisioning profile. `customer` has one; it is the template.

**Submit for review.** On purpose. A TestFlight build is reversible and a review
submission is not, so that stays a decision rather than the last step of a
successful build.

---

## TestFlight groups: names are not unique

This app already has two groups both called **Zopiq team** — one internal, one
external with a public link enabled. They are different audiences:

| | who gets it | Beta App Review? |
|---|---|---|
| internal | up to 100 App Store Connect users on the team | no |
| external | anyone you invite, or anyone with the public link | **yes** |

So the script refuses an ambiguous name rather than guessing, and asks for the
group id. `--check` prints the ids next to any name that collides. Renaming one
of them in App Store Connect would also fix it, and is probably worth doing.

---

## Build numbers

Apple rejects a build number it has already seen, and it rejects it **at the end
of the upload** — after the build. So the script asks Apple for the highest build
it already holds and takes `max(pubspec, Apple) + 1`, rather than trusting the
pubspec. That matters here because builds have been uploaded by hand: the pubspec
said `+17` while Apple already held `17`.

---

## Who presses the button

Anyone who can run the command, which now includes Claude. The credential is a
file on this machine referenced by path from `.env`; nothing about the release
path requires a browser or a 2FA code any more.
