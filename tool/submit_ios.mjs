// Put a build Apple already holds in front of App Review, and let approval
// release it.
//
//   node tool/submit_ios.mjs <customer|rider|vendor>            what would happen
//   node tool/submit_ios.mjs <customer|rider|vendor> --submit    do it
//
// The App Store counterpart to `play_promote.mjs`, and the step `ship_ios.mjs`
// deliberately left out. That omission was right for as long as there was no
// reason to automate it; the reason now is that the Play side goes to production
// from one command and the iOS side did not, so the two platforms had different
// shapes for the same act.
//
// **Nothing here builds or uploads.** It attaches a build Apple already has to
// the version record and submits that version — so it is safe to run straight
// after `ship_ios.mjs`, and it takes no `.ipa`, no signing identity and no
// phone.
//
// **It still refuses by default.** `play_promote.mjs` will not promote to
// production at all, on the grounds that a release is decided rather than
// followed-up; the same instinct applies here and more sharply, because an App
// Store submission is answered by a human at Apple and a rejection is on the
// record. So the bare command only reports, and `--submit` is the whole of the
// difference.
//
// **What this does not check is metadata completeness**, and that is on purpose.
// Screenshots, description, review notes and the App Privacy answers are all
// required, and Apple validates them at the moment of submission far more
// accurately than a reimplementation of its rules ever would. A missing
// screenshot therefore surfaces as Apple's own sentence, which names the field.

import { loadEnv } from './env.mjs'
import { credential, api, send } from './asc_auth.mjs'

const APPS = {
  customer: 'com.siteonlab.zopiqnow',
  rider: 'com.siteonlab.zopiqRider',
  vendor: 'com.siteonlab.zopiqVendor',
}

const args = process.argv.slice(2)
const submit = args.includes('--submit')
const [app] = args.filter((a) => !a.startsWith('--'))

if (!APPS[app]) {
  console.error('usage: node tool/submit_ios.mjs <customer|rider|vendor> [--submit]')
  process.exit(1)
}

/// The states a version can be edited and submitted from.
///
/// The three rejection states are in here deliberately: a rejected version is
/// fixed and resubmitted in place, which is the same call as a first
/// submission. `WAITING_FOR_REVIEW` and `IN_REVIEW` are absent for the opposite
/// reason — Apple already has it, and submitting again is either a no-op or a
/// way to lose your place in the queue.
const SUBMITTABLE = new Set([
  'PREPARE_FOR_SUBMISSION',
  'DEVELOPER_REJECTED',
  'REJECTED',
  'METADATA_REJECTED',
])

await loadEnv()
const cred = await credential().catch((e) => {
  console.error(`App Store Connect credential: ${e.message}`)
  process.exit(1)
})

const bundleId = APPS[app]
const record = (await api(`v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}`, cred)).data[0]
if (!record) {
  console.error(`Apple has no record for ${bundleId}. Create it in the web UI first.`)
  process.exit(1)
}
console.log(`${app}  ${bundleId}\n  record ${record.id}`)

// The newest build Apple holds that is actually usable. `VALID` is the only
// processing state a version will accept, and an expired build is refused with
// an error that does not mention expiry.
const builds = (await api(`v1/builds?filter[app]=${record.id}&limit=200`, cred)).data
  .filter((b) => b.attributes.processingState === 'VALID' && !b.attributes.expired)
  .sort((a, b) => Number(b.attributes.version) - Number(a.attributes.version))
const build = builds[0]
if (!build) {
  console.error('  no VALID unexpired build on Apple — run ship_ios.mjs first')
  process.exit(1)
}
console.log(`  latest usable build ${build.attributes.version} (uploaded ${build.attributes.uploadedDate?.slice(0, 10)})`)

const versions = (await api(`v1/apps/${record.id}/appStoreVersions?limit=10`, cred)).data
const version = versions.find((v) => SUBMITTABLE.has(v.attributes.appStoreState))
if (!version) {
  const states = versions.map((v) => `${v.attributes.versionString} ${v.attributes.appStoreState}`)
  console.error(`  no version is in a submittable state — Apple has: ${states.join(', ') || 'none'}`)
  process.exit(1)
}
const state = version.attributes.appStoreState
console.log(`  version ${version.attributes.versionString} is ${state}`)

// Which build the version currently points at, if any. Worth printing rather
// than silently overwriting: a version already carrying the right build is the
// common case on a re-run, and one carrying a *different* build is a thing the
// operator should see before this changes it.
const attached = await api(`v1/appStoreVersions/${version.id}/build`, cred)
  .then((d) => d.data?.id ?? null)
  .catch(() => null)
const attachedVersion = attached
  ? builds.find((b) => b.id === attached)?.attributes.version ?? attached
  : 'none'
console.log(`  build attached to it: ${attachedVersion}`)

if (!submit) {
  console.log(
    `\nWould, with --submit:\n` +
      (attached === build.id ? '' : `  attach build ${build.attributes.version} to version ${version.attributes.versionString}\n`) +
      `  set release to automatic on approval\n` +
      `  submit version ${version.attributes.versionString} for App Review\n\n` +
      'Nothing was changed. Apple validates the metadata at submission, so a\n' +
      'missing screenshot or review note surfaces then, in its own words.\n',
  )
  process.exit(0)
}

if (attached !== build.id) {
  await send(`v1/appStoreVersions/${version.id}/relationships/build`, {
    method: 'PATCH',
    body: { data: { type: 'builds', id: build.id } },
  }, cred)
  console.log(`  attached build ${build.attributes.version}`)
}

// `AFTER_APPROVAL` is the whole of "automatically push to production": without
// it an approved version waits for somebody to press Release, which on the Play
// side nobody has to do.
await send(`v1/appStoreVersions/${version.id}`, {
  method: 'PATCH',
  body: {
    data: {
      type: 'appStoreVersions',
      id: version.id,
      attributes: { releaseType: 'AFTER_APPROVAL' },
    },
  },
}, cred)
console.log('  release type: automatic on approval')

// A submission is a container, and the app may already have an unsubmitted one
// — from a previous failed run, or from somebody in the web UI. Creating a
// second is refused by Apple, so the existing one is reused.
const open = (await api(`v1/apps/${record.id}/reviewSubmissions?filter[state]=READY_FOR_REVIEW&limit=1`, cred)).data[0]
const submission = open ?? (await send('v1/reviewSubmissions', {
  method: 'POST',
  body: {
    data: {
      type: 'reviewSubmissions',
      attributes: { platform: 'IOS' },
      relationships: { app: { data: { type: 'apps', id: record.id } } },
    },
  },
}, cred)).data
console.log(`  submission ${submission.id}${open ? ' (reused)' : ''}`)

// Adding the same version twice is an error rather than a no-op, so a reused
// submission is checked for it first.
const items = (await api(`v1/reviewSubmissions/${submission.id}/items?limit=50`, cred)).data
if (!items.some((i) => i.relationships?.appStoreVersion?.data?.id === version.id)) {
  await send('v1/reviewSubmissionItems', {
    method: 'POST',
    body: {
      data: {
        type: 'reviewSubmissionItems',
        relationships: {
          reviewSubmission: { data: { type: 'reviewSubmissions', id: submission.id } },
          appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } },
        },
      },
    },
  }, cred)
  console.log(`  added version ${version.attributes.versionString} to it`)
}

await send(`v1/reviewSubmissions/${submission.id}`, {
  method: 'PATCH',
  body: {
    data: { type: 'reviewSubmissions', id: submission.id, attributes: { submitted: true } },
  },
}, cred)
console.log(`\n  submitted — build ${build.attributes.version} is with App Review, and releases on approval\n`)
