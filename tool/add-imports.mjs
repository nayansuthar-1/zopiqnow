// One-shot, deleted with the codemod beside it. Adds whatever primitives a file
// now uses and does not yet import, keeping the list alphabetical the way every
// import block in this app already is.
import fs from 'fs'

const CANDIDATES = [
  'Banner',
  'Button',
  'Card',
  'CardSkeleton',
  'ConfirmDialog',
  'DataTable',
  'EmptyState',
  'Field',
  'Modal',
  'PageBody',
  'Pager',
  'Pill',
  'SearchField',
  'SegmentedControl',
  'Select',
  'Skeleton',
  'StatTile',
  'TableSkeleton',
  'Td',
  'TextArea',
  'Th',
  'Toggle',
]

for (const file of process.argv.slice(2)) {
  let s = fs.readFileSync(file, 'utf8')
  // \r?\n throughout: a couple of these files came back from a `git checkout`
  // with CRLF, and an \n-only pattern silently matches nothing rather than
  // failing loudly.
  const m = s.match(
    /import \{\r?\n([\s\S]*?)\r?\n\} from '((?:\.\.\/)+ui\/primitives)'/,
  )
  if (!m) {
    console.log(`${file}: no multi-line primitives import — skipped`)
    continue
  }
  const have = m[1]
    .split(/\r?\n/)
    .map((l) => l.trim().replace(/,$/, ''))
    .filter(Boolean)

  const used = CANDIDATES.filter(
    (c) => new RegExp(`<${c}[\\s/>]`).test(s) && !have.includes(c),
  )
  if (used.length === 0) {
    console.log(`${file}: nothing to add`)
    continue
  }
  const next = [...have, ...used].sort((a, b) => a.localeCompare(b))
  const eol = m[0].includes('\r\n') ? '\r\n' : '\n'
  s = s.replace(
    m[0],
    `import {${eol}${next.map((n) => `  ${n},`).join(eol)}${eol}} from '${m[2]}'`,
  )
  fs.writeFileSync(file, s)
  console.log(`${file}: + ${used.join(', ')}`)
}
