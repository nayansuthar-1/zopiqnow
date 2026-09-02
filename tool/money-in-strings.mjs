// One-shot, deleted at the end of Phase 3.
//
// The JSX form (`₹{o.total}`) was the easy half. This is the other half: money
// built inside template literals, which is where the console puts the figures
// that matter most — the subtitle saying what is still owed, and the title of
// the dialog that is about to send it.
import fs from 'fs'
import path from 'path'

function walk(d, out = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = path.join(d, e.name)
    if (e.isDirectory()) walk(f, out)
    else if (f.endsWith('.tsx')) out.push(f)
  }
  return out
}

const tally = {}
for (const f of walk('apps/admin-web/src')) {
  if (f.endsWith('primitives.tsx')) continue
  let s = fs.readFileSync(f, 'utf8')
  const before = s

  // The two screens that were already grouping digits did it inline. Unwrap
  // them first so inr() is the only thing doing it.
  s = s.replace(/₹\$\{([^{}]+?)\.toLocaleString\('en-IN'\)\}/g, '${inr($1)}')

  // Everything else: ₹${expr} inside a template literal.
  const n = (s.match(/₹\$\{[^{}]+\}/g) || []).length
  s = s.replace(/₹\$\{([^{}]+)\}/g, '${inr($1)}')
  if (n) tally[f] = n

  if (s !== before) fs.writeFileSync(f, s)
}
console.log(tally)
