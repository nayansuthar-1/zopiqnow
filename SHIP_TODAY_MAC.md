# Ship day — iOS to the same place Android already is

**Written 2026-08-20 on the Windows box, for the Claude session on the Mac.**

Scope decided by the owner today, and it is narrower than
`IOS_RELEASE_RUNBOOK.md` §6 assumes: **the customer app, to chosen testers only,
on TestFlight.** Not a public App Store release. The target is *parity with the
Android closed track*, nothing more.

`IOS_RELEASE_RUNBOOK.md` is still the reference for how each piece works. This
file is today's order of work. Where the two disagree about status, the Mac wins.

---

## 0. What this scope deletes, and what it leaves

**Deleted, because they are App Review problems and there is no App Review:**

| Not needed today | Why |
|---|---|
| Razorpay live keys | The mock gateway's "Test gateway. No money moves" sheet is *correct* in a beta. It would have been a Guideline 2.1 rejection in a public submission; in TestFlight it is an honest beta. |
| App Store screenshots | TestFlight shows none. |
| The listing copy in `IOS_APP_STORE_LISTING.md` §3 | Nothing reads it until you submit publicly. |
| The App Privacy questionnaire | See the caveat in A3 — App Store Connect *may* insist before external testing. It is 15 minutes and §5 of the listing file is the answer key. |
| Live Activity, App Store submission | Already cut from v1. |

**What is left is smaller and one item of it is real work:**

1. A build of current `main` on TestFlight, handed to a group. *(One command.)*
2. **Push notifications, which have never worked on iOS.** Android has them live
   end-to-end; a TestFlight tester on an iPhone gets silence until the APNs key
   is uploaded and `send-notification` is redeployed. **This is the parity gap.**
3. Test Information and Beta App Review, if the testers are external.

---

## 1. Internal or external — pick before you start

Android's closed track has 12 invited testers. TestFlight has two shapes and they
are not equally convenient. This app already has one group of each, both
confusingly named **Zopiq team** — `--check` prints their ids.

| | Internal | External |
|---|---|---|
| Who | up to 100 **App Store Connect users** — each tester needs an Apple ID *added to your team* with a role | up to 10,000, invited by email or by public link |
| Review | **none** — the build is testable minutes after processing | **Beta App Review** on the first build, typically hours |
| Test Information needed | no | yes, including demo sign-in |
| Feels like | your own team | Android closed testing |

**Recommendation: do both, in this order.** Assign the build to the *internal*
group first — it is live immediately and proves the whole pipeline against real
phones with zero waiting. Then submit the same build to the external group for
Beta App Review, which is what actually matches the Android closed track for
testers you do not want inside App Store Connect.

⚠️ An internal tester is a user on your App Store Connect account. Use the
**Customer Support** role if you add anyone who should not see the rest of it.

---

## 2. Lane A — the owner (GUI and portals)

### A1. The APNs key — the parity item, ~15 minutes

This is the one that makes iOS equal to Android. Without it push is dead on every
iPhone, and it looks like a server bug rather than a missing key.

1. Apple Developer portal → **Certificates, Identifiers & Profiles → Keys → +**
2. Name it, tick **Apple Push Notifications service (APNs)**, continue, register.
3. **Download the `.p8`. You get exactly one download, ever.** Note the **Key ID**
   from the same page, and your **Team ID** — `759C76D23N`.
4. Store it beside the App Store Connect key, outside the repo:
   `~/.appstoreconnect/private_keys/` is already the habit. **Never in the repo —
   it is public.**
5. Firebase console → project **`zopiq-de276`** → Project Settings → **Cloud
   Messaging** → iOS app configuration → upload the `.p8`, Key ID, Team ID.

⚠️ **One upload, not three.** All three apps live in `zopiq-de276`. Older text in
`IOS_HANDOVER.md` §4 claiming the vendor app has its own project is wrong.

Hand the Mac session nothing here — it needs no copy of the key. Just tell it
when the upload is done, so it can run B3.

### A2. TestFlight testers

**Internal:** App Store Connect → **Users and Access** → invite each tester's
Apple ID → then TestFlight → the internal *Zopiq team* group → add them.

**External:** TestFlight → the external *Zopiq team* group → either paste tester
emails or enable/share the **public link**. The link is the closest thing to the
Android closed-testing opt-in URL, and the same people can hold both.

### A3. Test Information — external only, ~20 minutes

TestFlight tab → **Test Information**. Required before Beta App Review:

- **Beta App Description** — what the app is and what you want tested.
- **Feedback Email** — `zopiqnow@gmail.com`.
- **Privacy Policy URL** — `https://nayansuthar-1.github.io/zopiqnow/privacy.html`
- **Sign-in required: Yes**, with a working account. The app is email-OTP only, so
  a reviewer cannot receive a code. Use the **fixed-OTP demo account** from
  `IOS_APP_STORE_LISTING.md` §4: Supabase Dashboard → Authentication → Sign In /
  Providers → Email → **Test OTPs**, mapping a throwaway address to a fixed
  six-digit code that is **not** `123456`. Save a **delivery address in Falna**
  on that account, or the reviewer sees an empty feed.
- **What to Test** — per build, and worth writing honestly: *"Payment is a test
  gateway in this build; no money moves."* A beta reviewer who is told that will
  not treat it as a bug.

> **The App Privacy caveat.** App Store Connect has been known to block external
> testing until App Privacy is answered. If it does, `IOS_APP_STORE_LISTING.md`
> §5 is a complete answer key — three overview answers, fifteen data types, and
> an explicit do-not-declare list. Do not improvise it; a wrong answer is a
> post-release enforcement problem rather than a review one.

Then **Submit for Beta App Review**. Internal testers do not wait for this.

---

## 3. Lane B — Claude on the Mac

### B1. Pull and confirm the tree is clean

```bash
cd /path/to/zopiqnow
git pull
git status --short          # must be clean before anything is built
flutter --version           # expect 3.44.8 — do NOT change it
flutter pub get             # NOT upgrade
node tool/ship_ios.mjs --check
```

`--check` prints the credential state, the app record, the highest build Apple
already holds, and **the TestFlight group ids** — both groups share the name
*Zopiq team*, so the script refuses the name and wants an id. Read the ids off
this output.

The pubspec reads `1.0.0+17`, committed today; it had been left dirty on the
Windows box after build 17 was hand-uploaded.

### B2. Build and hand it to a group — one command, ~45 minutes mostly waiting

```bash
node tool/ship_ios.mjs customer <internal-group-id>
```

That bumps the build number to `max(pubspec, Apple) + 1`, builds the `.ipa`,
uploads via `altool`, waits for Apple's processing verdict, **assigns the build
to the group**, and commits the bump only after Apple has the binary. It does not
submit for review — that is A3 and it is deliberate.

**Apple already holds builds 16 and 17 as `VALID`**, so an alternative exists:
assign build 17 to the group by hand in App Store Connect and skip the build
entirely. **Do not** — 17 predates `35eeecd` and `dd860d3`, the two home-feed
fixes Android testers already have, and shipping iOS testers an older app is the
opposite of parity. Build fresh.

Watch for the assignment line at the end. `Could NOT assign … HTTP 4xx` means the
build is on Apple and in nobody's TestFlight, which looks identical to success
from the terminal.

### B3. Make push actually arrive — needs A1 done first

```bash
supabase login                                   # interactive — the human
supabase link --project-ref ofjjuzrxnksbyglzwaah
supabase functions deploy send-notification
```

⚠️ **The redeploy is the step most easily forgotten and it invalidates everything
downstream.** Until it runs, the `apns` block in the function has no effect and
iOS push cannot arrive no matter how correct the key or the signing is.

Then walk the chain in order, stopping at the first link that fails
(`IOS_RELEASE_RUNBOOK.md` §B3):

1. APNs token — the device registers with Apple.
2. FCM token — Firebase exchanges it.
3. A `device_tokens` row with **`platform='ios'`**. A token hardcoded as
   `'android'` was one of the five Android-only bugs found during the port; the
   fix is in, but confirm the row says `ios`.
4. The DB webhook fired.
5. `send-notification` logs — invoked, and what it returned.

Test **foregrounded, backgrounded, and killed**. The killed case is the one that
finds real bugs — it is what forced the Android live card into a plugin package.

⚠️ **A simulator cannot prove this.** Push, real GPS and signing all need the
phone. Run what you can, and say plainly in B4 which links were observed and
which were reasoned about.

### B4. Write back

Update `IOS_HANDOVER.md` §0 and the status table in `IOS_RELEASE_RUNBOOK.md` §1
with what actually happened — real command output, not "it worked". Three rows
in that table are still `Not started` and two of them should change today. Note
anything in *this* file that turned out to be wrong.

---

## 4. Where this leaves the two platforms

| | Android | iOS after today |
|---|---|---|
| Distribution | closed testing, 12 testers | TestFlight, internal + external group |
| Review passed | Play policy review | Beta App Review (external only) |
| Push | live end-to-end since 2026-07-25 | live, if A1 + B3 land |
| Payments | mock behind checkout | mock behind checkout — **identical** |
| Production | applying for access (day 14 of the tester clock) | not attempted, by choice |

**Payments are the same on both, and that is the honest state of the product:**
no Razorpay keys means no real money anywhere, and a public release on either
store means free food. That is a launch blocker for both platforms on the day it
matters — it is simply not a blocker for *testers*, which is why it is out of
scope today.
