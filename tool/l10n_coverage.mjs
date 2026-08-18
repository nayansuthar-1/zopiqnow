// l10n_coverage — how much of the customer app actually speaks each language.
//
//   node tool/l10n_coverage.mjs
//
// `AppStrings` is deliberately concrete rather than abstract, so a translation
// that has not been written inherits English and the build stays green. That is
// the right trade for shipping incrementally, and it has one cost: a missing
// translation is completely silent. This makes it loud.
//
// It compares the member names declared in `strings.dart` against those
// overridden in each `strings_<code>.dart`, and lists what is missing. Names
// only — it cannot tell a good translation from a bad one, only a present one
// from an absent one.

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const L10N_DIR = 'apps/customer/lib/core/l10n';

/// Every getter and method on the class, by name.
///
/// Comments are stripped first. Without that, the `[AppStrings.categoryName]`
/// references inside the doc comments get counted as members and every file
/// reports keys it does not have.
function members(source) {
  const code = source
    .replace(/\/\/\/.*$/gm, '')
    .replace(/\/\/.*$/gm, '')
    .replace(/\/\*[\s\S]*?\*\//g, '');

  const found = new Set();
  for (const m of code.matchAll(/String\s+get\s+([A-Za-z0-9_]+)/g)) {
    found.add(m[1]);
  }
  // Methods that take an interpolated value — `categoryName(...)`.
  for (const m of code.matchAll(/String\s+([A-Za-z0-9_]+)\s*\(/g)) {
    found.add(m[1]);
  }
  return found;
}

const base = members(readFileSync(join(L10N_DIR, 'strings.dart'), 'utf8'));

const translations = readdirSync(L10N_DIR)
  .filter((f) => /^strings_[a-z]{2}\.dart$/.test(f))
  .sort();

let incomplete = false;

console.log(`base (English): ${base.size} strings\n`);

for (const file of translations) {
  const code = file.slice('strings_'.length, -'.dart'.length);
  const translated = members(readFileSync(join(L10N_DIR, file), 'utf8'));

  const missing = [...base].filter((key) => !translated.has(key)).sort();
  // A key here and not in the base is a rename that left an orphan behind: it
  // overrides nothing, so `@override` would not have caught it either.
  const orphaned = [...translated].filter((key) => !base.has(key)).sort();

  const done = base.size - missing.length;
  const pct = ((done / base.size) * 100).toFixed(1);
  console.log(`${code}: ${done}/${base.size} (${pct}%)`);

  if (missing.length > 0) {
    incomplete = true;
    console.log(`  missing (${missing.length}):`);
    for (const key of missing) console.log(`    ${key}`);
  }
  if (orphaned.length > 0) {
    incomplete = true;
    console.log(`  orphaned — not in the base class (${orphaned.length}):`);
    for (const key of orphaned) console.log(`    ${key}`);
  }
  console.log();
}

process.exit(incomplete ? 1 : 0);
