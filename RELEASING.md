# Releasing to Google Play

## The short version

```bash
node tool/ship.mjs --check                 # what is set up, what is missing
node tool/ship.mjs customer internal      # a test build, live in ~minutes
node tool/ship.mjs customer production    # the real thing, hours to days
```

One Node entry point rather than a PowerShell script, so it runs from any shell
on this machine — **including the one Claude runs**. Once the credential below is
in place, Claude can ship a build without you touching anything.

That bumps the versionCode, builds the bundle, uploads it, and commits the bump —
in that order, so a failed build never burns a version number.

---

## Do I have to redo internal / closed / open testing for every update?

**No.** Testing tracks are not a gate you pass through on each release. They are
places you can put a build. Once you are in production you push straight to
production.

There is one thing that *is* a one-time gate, and it is worth being precise
about, because it is the part people get caught by:

> **If your Play Console account is a personal (individual) developer account
> created after 13 November 2023**, Google requires a closed test with **at least
> 12 testers who stayed opted in for 14 continuous days** before you may apply for
> production access.

That requirement is **once per app, to unlock production** — not once per update.
After production access is granted, an update is: build → upload → review → live.
No 14-day wait, no minimum tester count, ever again.

If your account is an **organisation** account, this rule does not apply at all
and you can go to production immediately.

Check which you have: Play Console → Setup → *Advanced settings*, or the account
type shown on your developer profile. I could not verify this from here — it is
tied to your account, not to the code.

### What each track actually costs you

| Track | Review | Who sees it | Use it for |
|---|---|---|---|
| **Internal** | Usually minutes | Up to 100 emails you list | Every working build. This is the one to use while we iterate. |
| **Closed** | Hours | A tester list or Google Group | The 12-tester/14-day requirement, if it applies to you |
| **Open** | Hours–days | Anyone with the link | Public beta |
| **Production** | Hours–days (first one can be longer) | Everyone | Real releases |

**While we are building, use `internal`.** It is reviewed in minutes rather than
days, it takes unlimited uploads, and the testers are just email addresses you
add once. Nothing about using it slows down a later production release.

---

## "Immediately on the Play Store" — the honest bit

Nothing publishes immediately. Google reviews every release, and the review is
theirs, not something a script can skip:

- **internal** — typically a few minutes
- **production** — typically hours, occasionally days

What we *can* remove is everything on our side. One command now covers version
bumping, building, signing, uploading, track assignment, and the git commit. The
only remaining wait is Google's.

If you want the fastest possible loop while we work, it is:

1. You tell me what to change.
2. I make the change and commit it.
3. Claude runs `node tool/ship.mjs customer internal` — or you do; same command.
4. A few minutes later it is on your phone, from the Play internal-testing link.

Once the service account exists, **step 3 needs nobody's hands** — Claude can run
it. The signing key already lives on this machine, so the only thing that was
ever yours to do is creating the credential, once.

---

## First-time setup (once, ~10 minutes)

You need a service account so the script can upload without a browser.

1. **Play Console → Setup → API access → Create new service account.** That link
   sends you to Google Cloud.
2. In Google Cloud: **Create service account**, then **Keys → Add key → JSON**.
   Download it.
3. **Save the JSON outside this repository.** `D:\keys\zopiqnow-play.json` is
   fine. ⚠️ **This repo is public** — a Play service-account key is upload access
   to your app, and anything inside the repo is one `git push` from being
   readable by anyone.
4. Back in Play Console → **API access**, find the new account and **Grant
   access**. It needs *Release manager* on your apps (or at minimum: view app
   information, manage production/testing releases).
5. Add the path to `.env` (untracked):

   ```
   PLAY_SERVICE_ACCOUNT_JSON=D:\keys\zopiqnow-play.json
   ```

6. Confirm the upload signing key is where Gradle expects it — the release build
   already works, so this is done.

Test it end to end with a throwaway internal build:

```bash
node tool/ship.mjs --check      # should end in "Ready."
node tool/ship.mjs customer internal
```

---

## What the script will not do for you

- **It will not pick a staged rollout.** Releases go out at 100% of the chosen
  track. Rolling out to 20% of production is a deliberate decision with a number
  attached; if you want it, do that release from the Console.
- **It will not write release notes.** Play shows the previous notes until you
  change them. Edit them in the Console when a release is worth describing.
- **It will not upload a stale bundle.** If the `.aab` on disk is more than ten
  minutes old it refuses, because a stale bundle is the one failure that looks
  exactly like success: it uploads, Play accepts it, and your change is not in it.

---

## Track names: the Console and the API disagree

The Play Console and the API use different words for the same track. This catches
people out, because uploading to the wrong one succeeds silently:

| Play Console says | The API calls it |
|---|---|
| Internal testing | `internal` |
| Closed testing | `alpha` — **unless you named the track yourself** |
| Open testing | `beta` |
| Production | `production` |

A closed test can be a track you named ("qa", "friends-and-family"), and then that
name *is* the API name. Do not guess — `node tool/ship.mjs --check` lists the
tracks Play actually holds for each app, read from your console rather than
assumed.

---

## Target API level

Play requires the target API to be within one year of the latest Android release.
As of **31 Aug 2026** that means **API 36 (Android 16)**, which all three apps now
target. `minSdk` stays at 24 (Android 7), so this changed nothing about which
phones can install the app.

This will come round again roughly every August. When it does it is usually a
one-line change per app in `android/app/build.gradle.kts`, plus checking that
year's behaviour changes.

---

## Who presses the button

Once the service account is in place, Claude can run `ship.mjs` unattended. Two
standing rules, unless you say otherwise:

- **`internal` — Claude ships it freely.** Up to 100 testers you chose, reviewed
  in minutes, and every build replaces the last. Nothing about it is hard to undo.
- **`production` — Claude asks first, every time.** That is a release to everyone
  who has the app, it cannot be unpublished cleanly, and a bad one is a bad one in
  public. "Ship it" said once is not a standing order for every release after it.

If you want production to be hands-off too, say so explicitly and I will treat it
that way.
