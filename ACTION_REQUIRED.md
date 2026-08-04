# Your checklist — what only you can do, and what is waiting on your eyes

**Written 4 August 2026.** Everything in the repo that could be done without you
is done. This file is the remainder, split into what *blocks a submission*, what
*needs a decision*, and what is *built but unverified*.

The queue this comes from is [SHIP_PLAN_ANDROID_IOS.md](SHIP_PLAN_ANDROID_IOS.md).
Short status of the code: **Android is ready to submit.** All three signed
bundles build, from a clean clone, with R8 on. Nothing in the code blocks Play.

---

## 1. Do this first — it is the only irreversible item on the page

- [x] **G9 — Back up the three keystores and their passwords, off this laptop.**
      ✅ **Done 4 Aug**, before the first upload, which is the only moment it
      could still have been done. The table below is now a record of what was
      backed up rather than an instruction.

  | App | Keystore | Password |
  |---|---|---|
  | customer | `apps/customer/android/app/zopiqnow-release.jks` | in `apps/customer/android/key.properties` |
  | vendor | `apps/vendor/android/app/zopiqvendor-release.jks` | in `apps/vendor/android/key.properties` |
  | rider | `apps/rider/android/app/zopiqrider-release.jks` | in `apps/rider/android/key.properties` |

  All six files are gitignored and exist on exactly one machine. **A lost upload
  key is a new app listing** — Google cannot recover it, and neither can anyone
  else. Everything else on this page can be redone; this cannot.

  Copy both the `.jks` files *and* the passwords. A password without its keystore
  is useless, and so is the reverse.

---

## 2. Blocking a submission — accounts, queues and dashboards

Ordered by lead time. The first has a queue and gates the entire iOS half.

- [ ] **G1 — Apple Developer Program enrolment.** $99/yr, 24–48 h approval.
      **Every iOS item is downstream of the certificate it issues** — nothing in
      Phase 3 can start without it. Individual is faster; organisation needs a
      D-U-N-S number and only matters if the listing must read "Zopiq" rather
      than your own name.
- [ ] **G3 — Razorpay merchant KYC.** No live keys means no real money. It gates
      the payment gate (S5), and S5 ends with **one real ₹1 payment on a real
      device per platform** — the signature path has never run against Razorpay,
      only against a known-good vector.
- [x] **G4 — Host the legal documents at a public URL.** ✅ **Closed 4 Aug and
      verified live**: all four pages answer **HTTP 200** over HTTPS, and the
      byte counts match the repository's files exactly — so it is serving the
      real documents rather than a prettier 404. `legal/` is now **`docs/`**,
      because GitHub Pages can only be served from a repository's root or from
      `/docs`, and `/docs` publishes those four files rather than the whole
      monorepo. Nothing in the app moved: the in-app documents are Dart, in
      `legal_documents.dart`, and never read this HTML.

      Served from *Settings → Pages →* branch `main`, folder `/docs`. **These are
      the URLs both stores need** — paste them, do not retype them:

      | | |
      |---|---|
      | Privacy policy | `https://nayansuthar-1.github.io/zopiqnow/privacy.html` |
      | Terms | `https://nayansuthar-1.github.io/zopiqnow/terms.html` |
      | Account deletion | `https://nayansuthar-1.github.io/zopiqnow/delete-account.html` |

      Play's deletion requirement is satisfied by that third URL: it is a static
      page and works **without installing the app**, which is the part reviewers
      actually check.

      > A `.nojekyll` file sits in `docs/`. Without it Pages runs the content
      > through Jekyll, which silently drops files beginning with an underscore
      > and can fail a build on a tree it was not expecting.
- [x] **G5 — Rotate the leaked Resend API key** (audit SEC-007). ✅ **Closed
      4 Aug as an accepted risk, not as a fix** — the owning account is
      unreachable, so the key stays live. Reasoning and the one standing
      condition are at the end of this item; read them before touching Resend.
      **Raised to
      urgent 4 Aug: this repository is public** — `"visibility": "public"` from
      GitHub's own API — so the key is not merely "in git history", it is
      readable by anyone who clones or browses `936f07c` right now.

      Verified rather than assumed, and the news is better than it could have
      been: **`RESEND_API` is the only variable that was ever committed.** The
      other thirteen — `SUPABASE_DB_PASSWORD`, `SUPABASE_ACCESS_TOKEN`,
      `SMTP_PASS`, `CLOUDINARY_API_SECRET`, both Ola secrets,
      `GOOGLE_WEB_CLIENT_SECRET`, `NOTIFY_WEBHOOK_SECRET` and the rest — have
      never been in a commit. The blast radius is one key.

      **Code cannot un-leak a secret**, and neither can deleting the file, which
      was already done and changes nothing: the object is still in history and
      still served by GitHub. Only rotation closes this.

      > **Proven live, 4 Aug.** `GET https://api.resend.com/domains` with the
      > committed key answers **HTTP 200**. It is not a stale credential, it is a
      > working one that a stranger can read today, and it has more than send
      > scope — it enumerates the account.
      >
      > **What limits the damage, and the condition on it:** that account has
      > **no verified domains** (`"data": []`), and Resend will not send to
      > arbitrary recipients without one. So the key currently buys an attacker
      > very little. **Verifying a domain on that account would turn a contained
      > leak into an open relay under your own brand** — do not do it, on that
      > account, ever.
      >
      > **A new Resend account does not close this**, and one was created on
      > 4 Aug. The leaked key lives in the *original* account and only the
      > original account can revoke it.
      >
      > **Decision, 4 Aug: the risk is accepted and this item is closed as
      > "will not fix".** The original account is no longer reachable, so the key
      > cannot be revoked by us. Note for anyone reading this later: the account
      > is *not* deleted — a deleted account's key would answer 401 and this one
      > answers 200 — it is abandoned, which is a different thing.
      >
      > **Why accepting it is reasonable:** with no verified domain the key
      > cannot send to arbitrary recipients, so the realistic worst case is a
      > stranger burning free-tier quota on an account nobody uses. It grants no
      > access to Zopiqnow, to Supabase, or to any customer data. Nothing in the
      > app or the edge functions has ever called Resend — mail goes through
      > Brevo SMTP.
      >
      > **The one condition, and it is permanent:** **never verify a domain on
      > that account.** That single act converts a contained leak into mail sent
      > as your brand by whoever holds the key. When `zopiqnow.com` exists,
      > verify it on the **new** account.
- [ ] **G6 — Enable PITR** in the Supabase dashboard (audit SEC-008). Launch week
      without point-in-time recovery is the one bad day that cannot be undone.
- [ ] **G13 — Set `rate_limit_verify` to 200.** Still 30, and **it caps
      successful sign-ins at 30/hour across all three apps.** The other two
      limits are already at 200. Dashboard → Authentication → Rate Limits.
      Raising it is safe: a 6-digit code is 1,000,000 possibilities against a
      300-second expiry, so 200/hour buys an attacker 16.7 tries inside one
      code's life — a 0.0017% chance.
- [ ] **G11 — Restrict the Google Maps Android key** in the Cloud Console to
      these three pairs. The key ships in every APK by design and **key
      restriction is the only control that exists for it.** These are the real
      fingerprints from the release keystores:

      com.siteonlab.zopiqnow        A9:09:B9:1D:C9:0A:26:D6:C7:67:D7:A8:5A:85:20:A9:51:2D:DC:46
      com.siteonlab.zopiq_vendor    05:F4:0D:21:D1:4E:6C:99:6C:CD:AC:F4:AD:84:47:26:B8:B4:A6:F9
      com.siteonlab.zopiq_rider     E9:F8:91:57:A7:0A:77:4D:0A:39:C3:06:96:C4:33:FF:13:10:2A:33

      Also restrict the key to the **Maps SDK for Android** alone.

      > **Play App Signing means the three SHA-1s above are not enough.** Google
      > re-signs with its own key, so the *installed* app presents a different
      > certificate and a key restricted to the list above goes blank in
      > production while working perfectly in your own builds. **For the customer
      > app that certificate is known** — G14 established it:
      >
      >     com.siteonlab.zopiqnow    0B:2E:C5:54:E9:08:66:02:1F:6E:36:A7:B6:B2:23:D6:46:65:93:94
      >
      > So the customer app needs **both** of its fingerprints in the
      > restriction. Vendor and rider will each acquire their own the day they
      > are uploaded; read them with the `adb pull` method in G14 rather than
      > from the console's copy-buttons.
- [x] **G14 — Register Play's app-signing certificate with the Google OAuth
      client.** ✅ **Closed 4 Aug, verified on a device: Google sign-in works from
      the internal-testing build.** *(Added the same day as a prediction,
      confirmed as a failure within the hour, fixed the hour after that.)*

      **Play's app signing certificate for `com.siteonlab.zopiqnow`:**

      0B:2E:C5:54:E9:08:66:02:1F:6E:36:A7:B6:B2:23:D6:46:65:93:94

      That value is now registered to a second Android OAuth client in project
      `789936942272`, alongside the upload key's. **G11 needs it too** — see
      below.

      > **How it was found, because the console could not be trusted to say.**
      > Two attempts failed on fingerprints copied from *App integrity*, whose
      > values are copy-buttons with no visible text — there is no reading back
      > what you took, and the page offers four of them. The certificate was read
      > instead **off the binary the phone was actually running**:
      >
      >     adb shell pm path com.siteonlab.zopiqnow
      >     adb pull <base.apk> && apksigner verify --print-certs base.apk
      >
      > which answers `CN=Android, OU=Android, O=Google Inc.` — Google's key, not
      > `CN=Zopiqnow` — and the SHA-1 above. **That is ground truth**: it is the
      > certificate the device presents, rather than the one a console claims it
      > should. Use it for the vendor and rider apps rather than repeating the
      > guesswork.

      **It was never avoidable.** Play App Signing has been mandatory for every
      new app since August 2021, so the binary a tester downloads is *always*
      signed by Google rather than by the upload key — there is no setting that
      would have kept our certificate on the installed app.

      Google sign-in is authorised by the pair (package name, signing
      certificate), and the only pair registered today is
      `com.siteonlab.zopiqnow` + **our** upload certificate
      `A9:09:B9:1D:C9:0A:26:D6:C7:67:D7:A8:5A:85:20:A9:51:2D:DC:46`. Play App
      Signing means the binary a tester downloads is signed by **Google's** key,
      not that one — so sign-in works perfectly in every build you make by hand
      and fails for everybody who installs from Play. The symptom is the account
      sheet opening, an account being picked, and a refusal; the log says
      `Invalid key value: <sha1>:com.siteonlab.zopiqnow`.

      **Do this:** Play Console → *Setup → App integrity* → copy the **app
      signing key** SHA-1 (not the upload key). Cloud project **789936942272** →
      Credentials → **create a second Android OAuth client** for the same package
      name with that fingerprint. Two clients for one package is the supported
      shape — the global uniqueness rule is per *(package, certificate)* pair,
      and a different certificate is a different pair, so this does not collide
      with the existing one and does not need it changed.

      > **The trap on that page, walked into first time (4 Aug).** App integrity
      > shows **two** certificates — *app signing key* and *upload key* — and the
      > upload key is `A9:09:B9:1D:…`, our own keystore. Copying that one and
      > creating an OAuth client with it fails with **"the Android package name
      > and fingerprint are already in use"**, which reads like the July disaster
      > and is nothing of the kind: the pair is in use *by our own existing
      > client*, and the error is Google refusing to register the same thing
      > twice. **The one you want is the fingerprint that is not
      > `A9:09:B9:1D:…`.** Nothing is damaged by the failed attempt.
      >
      > **And there are four fingerprints on that page, not two.** The *App
      > signing key · In use* block offers SHA-1 and SHA-256 under a **Classical
      > key** heading and both again under **Post-quantum cryptography key**
      > (beta). An Android OAuth client takes the **Classical key → SHA-1**, and
      > nothing else. The values are copy-buttons with no visible text, so there
      > is no reading them back afterwards — check what landed in the paste
      > field, not what you think you clicked.
      >
      > If the *app signing* block shows `A9:09:B9:1D:…` as well, then Play
      > adopted our key rather than generating one, the pair is already correctly
      > registered, and the sign-in failure is something else — read the reason
      > out of Crashlytics rather than guessing at fingerprints.

      **Keep the existing Android client.** It is what makes the release builds
      you make by hand work, and it is a different certificate, so the two do not
      compete. Deleting it would break your own testing to fix Play's.

      Nothing in `env.dart` changes: only the **web** client id is ever named in
      code, and it stays. The Android client exists solely to make Google vouch
      for the certificate. **No rebuild, no new bundle, no version code bump** —
      this is a registration on Google's side, and the build already on the track
      starts working once it lands.

      > **The Maps key is the same fingerprint problem and is *not* broken yet,
      > for the wrong reason.** G11 has not been done, so the key is still
      > unrestricted and therefore works everywhere, Play-signed builds included.
      > The day G11 *is* done, Play's app-signing SHA-1 must go in alongside the
      > three upload SHA-1s — otherwise restricting the key is what takes the
      > maps out, and it will look like G11 broke them rather than completed
      > them.
- [ ] **G16 — SMS sign-in: DLT registration, then four values.** *(Parked by you
      on 5 Aug. The app code is done and pushed (`ac5fe18`); nothing below is
      code.)*

      **⚠️ The sign-in screen now leads with a mobile field that cannot work
      yet.** Phone is the primary path with the focus and the orange button;
      email has moved down to a secondary. Until this item is closed, a customer
      who does the obvious thing gets an error and has to notice the smaller
      button underneath. **Do not put an AAB built from `main` in front of the
      twelve testers without either closing this or gating the field** — the gate
      is one boolean and is offered below.

      **Step 1, the long pole: DLT registration.** India delivers no
      transactional SMS without a registered entity, an approved header (sender
      id) and an approved content template. Credit in MSG91 is necessary and not
      sufficient — an unregistered send is *accepted by the API and dropped by
      the operator*, which reads exactly like a bug in our code. MSG91 will walk
      you through it; it is days, not minutes.

      **Step 2, what I need from you when it clears:**

      | | |
      |---|---|
      | `MSG91_AUTHKEY` | the account auth key |
      | `MSG91_TEMPLATE_ID` | the **DLT-approved** flow template id |
      | The template's variable name | `send-sms-otp` sends the code as `otp`; if the approved template calls it something else, one key in the function changes |
      | Confirmation the function is deployed | `supabase functions deploy send-sms-otp --no-verify-jwt` |

      **Step 3, mine once those exist:** enable the Phone provider, enable the
      Send SMS hook against that function, store its `v1,whsec_…` as
      `SEND_SMS_HOOK_SECRET`, and raise `sms_otp_exp` from **60 seconds** — which
      is shorter than an SMS often takes to arrive — to 300, matching email.
      `rate_limit_sms_sent` is 30/hour and has G13's problem.

      > **A consequence that is permanent and is not a bug.** Supabase keys a
      > user on phone *or* email, so a customer who signed up with an address and
      > later signs in with their number arrives as **a different user id**, with
      > none of their orders, addresses or saved restaurants. Cheap at 13 users,
      > expensive later. Linking them is separate work and is worth doing before
      > real customers arrive.

- [ ] **G15 — Publish the OAuth consent screen before the closed test starts.**
      *(Added 4 Aug, alongside G14 and for the same reason: it fails in a way
      that is indistinguishable from a certificate problem.)*

      Cloud project **789936942272** → APIs & Services → OAuth consent screen →
      *Publishing status*. **While it reads "Testing", only accounts on the
      test-user list can sign in at all** — 100 maximum, each added by hand. Your
      own account works because it is on that list or owns the project, which is
      exactly why this stays invisible until somebody else tries.

      **Twelve testers who cannot sign in burn days of the 14-day clock that
      cannot be got back**, and the symptom — sheet opens, account picked,
      nothing happens — is the same sentence as G14's. Diagnosing it as a
      fingerprint problem a second time is the trap.

      **Publish it** rather than listing twelve accounts. Google's verification
      review applies to *sensitive* and *restricted* scopes; this app asks for
      `openid`, `email` and `profile`, which are neither, so publishing is
      immediate and needs no review.

- [ ] **G12 — Cap the Cloudinary unsigned preset** (audit SEC-004): allowed
      formats, max file size, folder. The preset ships inside every binary by
      design — it carries no secret, but it lets a stranger upload to your
      account. Signed uploads through an edge function are the real fix and are
      post-launch.
- [ ] **G8 — Confirm `support@zopiqnow.com` is a real inbox somebody reads.** It
      is written into both legal documents, the deletion page and the in-app
      support tile. Both stores email it.
- [x] **G2 — Confirm the Play Console account type.** ✅ **Answered 4 Aug: it is
      an individual account, identity-verified.** So the closed-test requirement
      applies in full — **12 testers opted in for 14 continuous days** before the
      account can even *apply* for production access, and the application is
      reviewed after that.

      **The 14 days are the schedule, not a step in it.** The clock starts when a
      closed track is live with testers actually opted in — not when the account
      was created, and not when the build was uploaded — and it runs in parallel
      with every other item on this page. So the correct order is: get a build
      onto a closed track and the twelfth tester opted in **first**, then write
      the listing during the wait. Two weeks of screenshots costs nothing; two
      weeks of not having started costs two weeks.

      **Run it with the customer app only.** Production access is granted to the
      *account*, so vendor and rider do not each need their own fourteen days —
      confirm that in the console before assuming it, but do not run three tests
      in parallel on the strength of a guess either way.

---

## 3. Decisions only you can make

- [ ] **Where did the dish art come from?** *(blocks D3 and D4)* The code claimed
      Microsoft Fluent Emoji under MIT and pointed at an `ATTRIBUTIONS.md` that
      **does not exist in this repo**. The files themselves carry C2PA generation
      metadata, which says AI-generated rather than Fluent Emoji. Both stores make
      you affirm you have the rights to what you ship. **If you generated them,
      that is a perfectly good answer** — it just needs to be written down, and it
      decides whether `FLUENT-EMOJI-LICENSE.txt` stays, changes, or is joined by a
      real attributions file.
- [ ] **Keystore passwords: keep mine, or set your own?** I generated 32-character
      random ones. Nothing is uploaded to Play yet, so regenerating is free
      **today** and impossible after the first upload. Say the word and I redo
      both before anything ships.
- [ ] **Should a rider override with `override_until = null` keep meaning
      *permanent*?** It is the most powerful switch in the product: it lets a
      rider whose documents were *rejected*, whose licence expired 400 days ago
      and whose insurance lapsed pass all five KYC gates. Forcing every vouch to
      expire (30 days, say) means no rider is ever indefinitely unverified — and
      also means somebody must remember to renew it or a working partner stops
      earning. That is a judgement about livelihoods, not a schema change. It is
      now at least *recorded* in the audit trail, which it was not before.
- [ ] **Where should the store icons live in the repo?** A1 produced
      `<app>-play-512.png` and `<app>-appstore-1024.png` for all three, opaque
      and correct, currently in a scratchpad. Name a home and they move in.

---

## 4. Built, but never seen working — pending your review

Each of these is code that is finished and verified as far as it can be verified
without a device or a browser. **None has been exercised by a human.**

- [ ] **Block a real person, end to end.** The admin console's People page has
      **never been clicked through in a browser.** The worth-doing-first check:
      block a test account, confirm it is signed out and cannot order, then
      unblock it. Every rail was exercised in rolled-back SQL, but a screen is
      not SQL.
- [ ] **The rider's location disclosure sheet has never been rendered.** Built
      in ship A7. Trigger it by installing a fresh build on a phone that has not
      granted location, then opening a job map or starting a delivery. It should
      appear *once*, before the system dialog, and never again after a decision.
- [x] **R8 reflection paths — it happened.** ✅ **Found and fixed 5 Aug.** This
      item said it was the single highest-risk untested thing in the Android
      build. It was, and it had already shipped to the internal track.

      **Firebase was silently dead in every release build.** `logcat` off the
      device running the Play bundle:

          ComponentDiscovery: Could not instantiate ...FirebaseMessagingKtxRegistrar
          Caused by: java.lang.NoSuchMethodException: ...KtxRegistrar.<init> []

      …and the same for `FirebaseInstallationsKtxRegistrar` and
      `CrashlyticsRegistrar`. `FirebaseInitProvider` reads registrar class names
      out of AAR manifest metadata — **strings**, so R8 sees classes nobody
      constructs and deletes their no-argument constructors. The app then logs
      *"FirebaseApp initialization successful"* and runs on with **no messaging,
      no installations and no crash reporting**.

      **It explains two separate mysteries at once**, which is how it was
      confirmed rather than guessed: the customer app had never written a
      `device_tokens` row, so *Send a notification → Customer* counted **0
      recipients**; and Crashlytics was empty the whole time we were reading it
      for answers about Google sign-in. One cause, both symptoms.

      Fixed with the keep rule now in **all three** `proguard-rules.pro` —
      `-keep class * implements com.google.firebase.components.ComponentRegistrar
      { <init>(); }`. Verified in the rebuilt R8 mapping: the registrars survive
      un-renamed and `void <init>()` is still on them.

      > **The vendor and rider bundles built on 4 Aug carry this bug too.** All
      > three apps were minified with no Firebase rules, so their release builds
      > have no push and no crash reporting either. Rebuild both before they go
      > anywhere near a track.
- [ ] **The S4 pricing check over HTTP, with a real signed-in session.** Place one
      order and compare `orders.total` against the cart's own figure. The pricing
      was attacked and held, but in `psql` as role `authenticated` rather than
      through a real user token — the one claim not proven the way the plan's own
      standard demands. One real order settles it.
- [ ] **iOS privacy manifests are written but NOT wired in.** I created
      `PrivacyInfo.xcprivacy` for all three apps (valid XML, verified) at
      `apps/<app>/ios/Runner/`. **They do nothing until each is added to its
      Runner target's *Copy Bundle Resources* build phase** — a two-minute Xcode
      GUI step I deliberately did not fake by hand-editing `project.pbxproj`.
      Until then, ITMS-91053 still applies.

---

## 5. Needs hardware I do not have

- [ ] **A5 — Install the three AABs on a real Android 10 device and a current
      one, and smoke them** before anything is uploaded. Bundles are built and
      signed; the device half is yours.

      > **Rebuild the customer bundle before you smoke it, or checkout is dead
      > in your hand.** The bundles were built with a plain
      > `flutter build appbundle --release`, and in a release build with no
      > `ALLOW_MOCK_PAYMENTS` the payment gateway is `LockedPaymentGateway` —
      > every attempt to pay answers *"Payments aren't available in this build
      > yet."* and no order can be placed. That is correct for a production
      > bundle and wrong for a test one. For anything you install to try the
      > product on, build it as:
      >
      > ```
      > flutter build appbundle --release --dart-define=ALLOW_MOCK_PAYMENTS=true
      > ```
      >
      > This is safe to keep using until Razorpay is live and needs no undoing
      > afterwards: the flag only decides what happens when `razorpay-order`
      > answers `configured: false`. The day the keys are set as function
      > secrets it answers `configured: true`, and the same bundle starts taking
      > real payments without a rebuild. **Do not ship the flagged bundle to
      > production** — that is the one thing it must not be used for.
      >
      > A debug build (`flutter run`) already gets the mock and needs no flag.
- [ ] **Phase 5 — the full regression list**, on release builds, both platforms.
      It is in the ship plan and it is 19 lines long.
- [ ] **All of Phase 3 (iOS)** — signing, APNs key, device run, dSYM phase,
      archive, TestFlight. Needs a Mac with Xcode *and* G1.

---

## 6. Done — no action needed

For confidence rather than action. Closed and pushed on 3–4 August:

- **Phase 1 security, S1–S9** (migrations 0087, 0089–0093) — the authorization
  sweep, the write-grant sweep, rate limits, the audit trail, the service-role
  key removed from the notifications webhook, the rider KYC gate verified.
- **A1** icons · **A2** keystores · **A3** R8 on all three · **A4** permission
  register · **A6** customer location disclosure · **A7** rider location
  disclosure.
- **The 225 MB problem** — the customer APK was 225.7 MB and 198 MB of it was
  category artwork rendered into 58 dp circles. Now 68.9 MB.
- **G7** — two dead edge functions deleted. One of them, `send-order-push`, was a
  **live unauthenticated push endpoint** that would ring every device registered
  to an attacker-chosen restaurant. It is 404 now.
- **The two standing release checks** (0087 and 0089 footers) — both returned
  **zero rows** against the live database on 4 August. Run them again before each
  release.

---

**The honest date.** Android can be submitted as soon as section 2 is done —
none of it is code. iOS cannot start until G1 clears, and then needs a Mac.
