// One-shot, deleted at the end of Phase 3. The mechanical half of the page
// conversions: the two pagers still written out by hand, the money that nine
// screens printed ungrouped, and the page wrappers.
import fs from 'fs'
import path from 'path'

const root = 'apps/admin-web/src'

function walk(d, out = []) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = path.join(d, e.name)
    if (e.isDirectory()) walk(f, out)
    else if (f.endsWith('.tsx')) out.push(f)
  }
  return out
}

const tally = {}
const bump = (k, n = 1) => {
  if (n) tally[k] = (tally[k] || 0) + n
}

for (const f of walk(root)) {
  if (f.endsWith('primitives.tsx')) continue
  let s = fs.readFileSync(f, 'utf8')
  const before = s

  // --- the two remaining hand-written pagers -------------------------------
  const pager =
    /\{pages > 1 && \(\r?\n\s*<div className="mt-4 flex items-center justify-between(?: px-5 pb-5)?">[\s\S]*?Page \{page \+ 1\} of \{pages\}[\s\S]*?<\/div>\r?\n\s*\)\}/
  if (pager.test(s)) {
    s = s.replace(pager, '<Pager page={page} pages={pages} onChange={setPage} />')
    bump('Pager')
  }

  // --- money, printed ungrouped on nine screens ----------------------------
  // Only the plain `₹{expr}` form. Anything inside a template literal or a
  // sentence is left for the eye: those are prose, and prose that says
  // "they are holding ₹420" does not want a component in the middle of it.
  const money = /₹\{([a-zA-Z_$][\w.$]*(?:\.[\w$]+)*)\}/g
  const hits = s.match(money)
  if (hits) {
    s = s.replace(money, '{inr($1)}')
    bump('inr', hits.length)
  }

  if (s !== before) fs.writeFileSync(f, s)
}

console.log(tally)
