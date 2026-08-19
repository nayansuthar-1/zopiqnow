// Ship an app to TestFlight: bump, build, upload, wait for Apple to finish.
//
//   node tool/ship_ios.mjs --check                what is set up, what is missing
//   node tool/ship_ios.mjs customer               the whole thing
//   node tool/ship_ios.mjs customer "QA"          …and hand it to a TestFlight group
//   node tool/ship_ios.mjs customer --no-upload   build only
//
// The Android counterpart is `ship.mjs`, and this deliberately reads like it:
// same order, same rollback, same rule that the version bump is committed only
// after Apple has the binary. What differs is forced by the platform.
//
// **The upload itself is `altool`, not an HTTP call.** The App Store Connect API
// does everything around a build — TestFlight groups, versions, submission — but
// it has no endpoint that accepts an `.ipa`. Apple's uploader owns that step, so
// this drives it and then switches to the API the moment the bytes have landed.
//
// **Submitting for review is not here, on purpose.** This gets a build to
// TestFlight, which is reversible. Putting a version in front of App Review is
// not, and it should be a thing somebody decides rather than a thing a script
// does at the end of a successful build.

import { spawn } from 'node:child_process'
import { readFile, writeFile, readdir, stat } from 'node:fs/promises'
import path from 'node:path'

import { loadEnv } from './env.mjs'
import { credential, api, token } from './asc_auth.mjs'

const APPS = ['customer', 'rider', 'vendor']
const root = path.resolve(import.meta.dirname, '..')

const args = process.argv.slice(2)
const check = args.includes('--check')
const noUpload = args.includes('--no-upload')
const [app, group] = args.filter((a) => !a.startsWith('--'))

await loadEnv()

function run(command, cmdArgs, cwd) {
  return new Promise((resolve) => {
    spawn(command, cmdArgs, { cwd, stdio: 'inherit', shell: false }).on('close', resolve)
  })
}

const bundleIdOf = async (a) =>
  (await readFile(path.join(root, 'apps', a, 'ios/Runner.xcodeproj/project.pbxproj'), 'utf8')
    .catch(() => ''))
    .match(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/)?.[1]?.trim()

const versionOf = async (a) =>
  (await readFile(path.join(root, 'apps', a, 'pubspec.yaml'), 'utf8').catch(() => ''))
    .match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m)

/// The app's record id, or null when Apple has never heard of this bundle id.
///
/// Worth distinguishing from an error: **the API cannot create app records.**
/// That is one of the few things which is still the web UI's alone, so "no
/// record" is a job for a human and not something a retry will fix.
async function appRecord(bundleId, cred) {
  const d = await api(`v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}`, cred)
  return d.data[0] ?? null
}

/// The highest build number Apple already holds for an app, across every version.
///
/// This exists because the pubspec is not the authority here and pretending it is
/// costs a full rebuild. Apple rejects a build number it has seen before, and it
/// rejects it *at the end of the upload* — so a pubspec that has drifted below
/// what is already on the store turns a fifteen-minute build into a fifteen-minute
/// build plus an error. Reading the real ceiling first makes that unrepresentable.
async function highestBuild(appId, cred) {
  const d = await api(`v1/builds?filter[app]=${appId}&limit=200`, cred)
  return d.data.reduce((max, b) => Math.max(max, Number(b.attributes.version) || 0), 0)
}

/// Finds one TestFlight group by name or by id.
///
/// **Names are not unique**, and this app is already proof: "Zopiq team" is both
/// an internal group and an external one with a public link. Those are different
/// audiences with different consequences — an external group means Beta App
/// Review and everybody holding the link — so a name matching two groups is
/// refused rather than resolved by picking the first. Pass the id to be explicit.
async function resolveGroup(appId, wanted, cred) {
  const groups = (await api(`v1/apps/${appId}/betaGroups?limit=50`, cred)).data
  const byId = groups.find((g) => g.id === wanted)
  if (byId) return byId

  const named = groups.filter((g) => g.attributes.name === wanted)
  if (named.length === 1) return named[0]
  if (named.length === 0) {
    throw new Error(
      `no TestFlight group "${wanted}". This app has: ` +
        groups.map((g) => `${g.attributes.name} (${kindOf(g)})`).join(', '),
    )
  }
  throw new Error(
    `"${wanted}" matches ${named.length} groups — pass the id instead:\n` +
      named.map((g) => `    ${g.id}  ${kindOf(g)}`).join('\n'),
  )
}

const kindOf = (g) =>
  g.attributes.isInternalGroup
    ? 'internal'
    : g.attributes.publicLinkEnabled ? 'external, public link' : 'external'

// --- Preflight --------------------------------------------------------------
// Every line is read from disk or from Apple. Nothing here is a reassurance.
async function doctor() {
  let cred = null
  let credOk = true
  const credLine = await credential()
    .then((c) => { cred = c; return c.keyPath })
    .catch((e) => { credOk = false; return `MISSING — ${e.message}` })

  let apiLine = 'not checked (no credential)'
  if (cred) {
    apiLine = await api('v1/apps?limit=1', cred)
      .then(() => 'token accepted')
      .catch((e) => { credOk = false; return `REJECTED — ${e.message}` })
  }

  // Readiness is per app, not global. Two of these three apps having no store
  // record says nothing about whether the third can ship today, and a single
  // pass/fail would hide that for as long as the other two are unfinished.
  const shippable = []
  console.log(`\nApp Store Connect credential\n  ${credLine}\n  ${apiLine}\n\nApps`)
  for (const a of APPS) {
    let ready = credOk
    const v = await versionOf(a)
    const bundleId = await bundleIdOf(a) ?? '??'
    console.log(`  ${a.padEnd(9)} ${bundleId}  v${v ? `${v[1]}+${v[2]}` : '??'}`)

    const exported = await stat(path.join(root, 'apps', a, 'ios/ExportOptions.plist'))
      .then(() => 'ExportOptions.plist present')
      .catch(() => 'NO ExportOptions.plist — cannot export a signed archive')
    if (exported.startsWith('NO')) ready = false
    console.log(`  ${' '.repeat(9)} ${exported}`)

    if (!cred) { continue }
    const record = await appRecord(bundleId, cred).catch((e) => e)
    if (record instanceof Error) {
      console.log(`  ${' '.repeat(9)} could not read app record — ${record.message}`)
      ready = false
    } else if (!record) {
      // Not a failure of this script, and not fixable from here.
      console.log(`  ${' '.repeat(9)} NO App Store Connect record — create it in the web UI first`)
      ready = false
    } else {
      const top = await highestBuild(record.id, cred).catch(() => null)
      console.log(`  ${' '.repeat(9)} record ${record.id}, highest build on Apple: ${top ?? '?'}`)
      const groups = await api(`v1/apps/${record.id}/betaGroups?limit=50`, cred)
        .then((d) => d.data).catch(() => null)
      if (!groups) {
        console.log(`  ${' '.repeat(9)} TestFlight groups: (could not read)`)
      } else if (!groups.length) {
        console.log(`  ${' '.repeat(9)} TestFlight groups: (none)`)
      } else {
        // Printed one per line with its kind, because two of these share a name
        // and the difference between them is who receives the build.
        console.log(`  ${' '.repeat(9)} TestFlight groups:`)
        for (const g of groups) {
          const ambiguous = groups.filter((o) => o.attributes.name === g.attributes.name).length > 1
          console.log(
            `  ${' '.repeat(11)} ${g.attributes.name} (${kindOf(g)})` +
              (ambiguous ? `  — name is ambiguous, use id ${g.id}` : ''),
          )
        }
      }
    }
    if (ready) shippable.push(a)
  }

  console.log(
    shippable.length
      ? `\nReady: ${shippable.join(', ')}. ` +
          `\`node tool/ship_ios.mjs ${shippable[0]}\` will build and upload.\n`
      : '\nNothing is ready to ship — see the MISSING/NO lines above.\n',
  )
  process.exit(shippable.length ? 0 : 1)
}

if (check) await doctor()

if (!APPS.includes(app)) {
  console.error(
    'usage:\n' +
      '  node tool/ship_ios.mjs --check\n' +
      '  node tool/ship_ios.mjs <customer|rider|vendor> [testflight-group] [--no-upload]',
  )
  process.exit(1)
}

const cred = await credential().catch((e) => {
  console.error(`App Store Connect credential: ${e.message}`)
  process.exit(1)
})
const bundleId = await bundleIdOf(app)
const record = await appRecord(bundleId, cred)
if (!record) {
  console.error(
    `No App Store Connect record for ${bundleId}.\n` +
      'The API cannot create one — add the app in App Store Connect first.',
  )
  process.exit(1)
}

// Resolved now rather than after the upload. A misspelled group is a typo, and
// finding it out at the end costs the whole build; worse, the build would by
// then already be on Apple with the bump uncommitted.
const target = group
  ? await resolveGroup(record.id, group, cred).catch((e) => {
      console.error(`TestFlight group: ${e.message}`)
      process.exit(1)
    })
  : null
if (target) {
  console.log(`Will hand the finished build to "${target.attributes.name}" (${kindOf(target)}).`)
}

// --- 1. Bump ----------------------------------------------------------------
// The new number has to beat both the pubspec and everything Apple already holds;
// those disagree whenever a build was uploaded by hand.
const pubspecPath = path.join(root, 'apps', app, 'pubspec.yaml')
const original = await readFile(pubspecPath, 'utf8')
const match = await versionOf(app)
if (!match) {
  console.error(`Could not read a 'version: x.y.z+n' line from ${pubspecPath}`)
  process.exit(1)
}
const [, name, oldCode] = match
const ceiling = Math.max(Number(oldCode), await highestBuild(record.id, cred))
const newCode = ceiling + 1
if (ceiling > Number(oldCode)) {
  console.log(`${app}: Apple already holds build ${ceiling}; pubspec said ${oldCode}.`)
}
console.log(`${app}: build ${oldCode} → ${newCode} (version ${name})`)
await writeFile(pubspecPath, original.replace(/^version:\s*\d+\.\d+\.\d+\+\d+\s*$/m, `version: ${name}+${newCode}`))

// --- 2. Build ---------------------------------------------------------------
const appDir = path.join(root, 'apps', app)
console.log('Building signed ipa…')
const built = await run(
  'flutter',
  ['build', 'ipa', '--release', '--export-options-plist=ios/ExportOptions.plist'],
  appDir,
)
if (built !== 0) {
  await writeFile(pubspecPath, original)
  console.error('Build failed. Build number restored.')
  process.exit(1)
}

const ipaDir = path.join(appDir, 'build/ios/ipa')
const ipa = (await readdir(ipaDir).catch(() => [])).find((f) => f.endsWith('.ipa'))
if (!ipa) {
  await writeFile(pubspecPath, original)
  console.error(`Build reported success but there is no .ipa in ${ipaDir}.`)
  process.exit(1)
}

if (noUpload) {
  await writeFile(pubspecPath, original)
  console.log(`Built ${path.join(ipaDir, ipa)}. Not uploaded (--no-upload); build number not committed.`)
  process.exit(0)
}

// --- 3. Upload --------------------------------------------------------------
// `altool` finds the .p8 by key id, searching a fixed set of directories. Rather
// than require the key to sit in one of them, point it at wherever .env says.
console.log(`Uploading ${ipa} …`)
const uploaded = await new Promise((resolve) => {
  spawn(
    'xcrun',
    ['altool', '--upload-app', '-f', path.join(ipaDir, ipa), '-t', 'ios',
     '--apiKey', cred.keyId, '--apiIssuer', cred.issuerId],
    {
      cwd: appDir,
      stdio: 'inherit',
      shell: false,
      env: { ...process.env, API_PRIVATE_KEYS_DIR: path.dirname(cred.keyPath) },
    },
  ).on('close', resolve)
})
if (uploaded !== 0) {
  await writeFile(pubspecPath, original)
  console.error('Upload failed. The build number is NOT committed.')
  process.exit(1)
}

// --- 4. Wait ----------------------------------------------------------------
// An accepted upload is not a usable build. Apple processes it afterwards, and
// that is where entitlement and missing-icon problems surface — minutes later,
// silently, unless something waits for the verdict.
console.log('Uploaded. Waiting for Apple to finish processing…')
let state = 'PROCESSING'
for (let i = 0; i < 40 && state === 'PROCESSING'; i++) {
  await new Promise((r) => setTimeout(r, 30_000))
  const found = await api(
    `v1/builds?filter[app]=${record.id}&filter[version]=${newCode}&limit=1`,
    cred,
  ).then((d) => d.data[0]).catch(() => null)
  state = found?.attributes.processingState ?? 'PROCESSING'
  process.stdout.write(`  ${new Date().toLocaleTimeString()}  ${state}\n`)
  if (state === 'VALID' && target) {
    const res = await fetch(
      `https://api.appstoreconnect.apple.com/v1/betaGroups/${target.id}/relationships/builds`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token(cred)}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ data: [{ type: 'builds', id: found.id }] }),
      },
    )
    // Said out loud either way: an unassigned build is on Apple but in nobody's
    // TestFlight, which looks identical to a successful run from the terminal.
    console.log(
      res.ok
        ? `Handed to "${target.attributes.name}".`
        : `Could NOT assign to "${target.attributes.name}" — HTTP ${res.status}. Build ${newCode} is uploaded but unassigned.`,
    )
  }
}
if (state !== 'VALID') {
  console.error(`Processing ended in state ${state}. The build number is NOT committed.`)
  await writeFile(pubspecPath, original)
  process.exit(1)
}

// --- 5. Record --------------------------------------------------------------
await run('git', ['add', `apps/${app}/pubspec.yaml`], root)
await run('git', ['commit', '-m', `chore(${app}): ios build ${name}+${newCode} to TestFlight`], root)

console.log(`\nDone. ${app} ${name}+${newCode} is on TestFlight.`)
