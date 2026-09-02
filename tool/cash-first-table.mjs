// One-shot, deleted with the codemod beside it.
//
// Cash is the only page with two tables and only the first is page-level. The
// second is a ledger inside a card at its own density (py-2 pr-4); wrapping it
// in DataTable would give a sub-table a border, a radius and a viewport-height
// cap it has no business having. So only the first block converts, located by
// line and checked before anything is written.
import fs from 'fs'
import { convert } from './table-to-datatable.mjs'

const p = 'apps/admin-web/src/payouts/CashPage.tsx'
const lines = fs.readFileSync(p, 'utf8').split('\n')

const from = 162
const to = 262
if (!lines[from].includes('overflow-x-auto rounded-card')) {
  throw new Error('from line is not the wrapper: ' + lines[from])
}
if (lines[to].trim() !== '</div>') {
  throw new Error('to line is not the close: ' + lines[to])
}

let block = convert(lines.slice(from, to + 1).join('\n'))
block = block.replace(
  /<div className="overflow-x-auto rounded-card border border-line bg-white">\s*<table className="w-full min-w-\[900px\] text-sm">/,
  '<DataTable label="Rider cash" minWidth={900}>',
)
block = block.replace(/<\/table>\s*<\/div>\s*$/, '</DataTable>')
block = block
  .split('\n')
  .map((l, i) => (i === 0 ? l : l.replace(/^ {2}/, '')))
  .join('\n')

fs.writeFileSync(
  p,
  [...lines.slice(0, from), block, ...lines.slice(to + 1)].join('\n'),
)
console.log('cash table 1 converted, table 2 left alone')
