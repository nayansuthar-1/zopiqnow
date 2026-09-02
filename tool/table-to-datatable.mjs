// One-shot codemod for ADMIN_CONSOLE_UI_RENOVATION Phase 3: move the console's
// hand-rolled tables onto DataTable / Th / Td.
//
// Not kept — this is deleted in the same commit that finishes the conversion.
// It exists because nine tables is enough repetition to get wrong by hand, and
// the transformation is mechanical: the primitive owns the padding, the row
// divider, the alignment and the tabular figures, so every class the cells
// carried for those comes off and anything else stays.
import fs from 'fs'

const OWNED_BY_TD = ['px-5', 'py-3', 'py-4', 'align-top']
const OWNED_BY_TH = [
  'px-5',
  'py-3',
  'py-4',
  'font-medium',
  'font-semibold',
  'text-left',
  'uppercase',
  'tracking-wide',
  'text-xs',
  'text-ink-muted',
]

function splitAttrs(raw) {
  const m = raw.match(/className="([^"]*)"/)
  return { cls: m ? m[1] : '', rest: raw.replace(/className="[^"]*"/, '').trim() }
}

function render(tag, cls, rest, owned, extra = '') {
  let classes = cls.split(/\s+/).filter(Boolean)
  const right = classes.includes('text-right')
  classes = classes.filter((c) => c !== 'text-right' && !owned.includes(c))
  // Td adds tabular figures to every right-aligned column itself — that is the
  // whole reason the column is right-aligned — so the cell must not repeat it.
  if (right) classes = classes.filter((c) => c !== 'tabular-nums')
  const props = [
    right ? 'align="right"' : '',
    extra,
    classes.length ? `className="${classes.join(' ')}"` : '',
    rest,
  ].filter(Boolean)
  return `<${tag}${props.length ? ' ' + props.join(' ') : ''}>`
}

export function convert(src) {
  let s = src

  // Headings. A self-closing <th /> is the actions column: it still needs a
  // name for a screen reader, it just must not print one.
  s = s.replace(/<th\b([^>]*?)\/>/gs, (_, raw) => {
    const { cls, rest } = splitAttrs(raw)
    return render('Th', cls, rest, OWNED_BY_TH, 'hideLabel') + 'Actions</Th>'
  })
  s = s.replace(/<th\b([^>]*?)>/gs, (_, raw) => {
    const { cls, rest } = splitAttrs(raw)
    return render('Th', cls, rest, OWNED_BY_TH)
  })
  s = s.replace(/<\/th>/g, '</Th>')

  // Cells.
  s = s.replace(/<td\b([^>]*?)>/gs, (_, raw) => {
    const { cls, rest } = splitAttrs(raw)
    return render('Td', cls, rest, OWNED_BY_TD)
  })
  s = s.replace(/<\/td>/g, '</Td>')

  // The dividers and the row borders now belong to DataTable.
  s = s.replace(/<tbody className="divide-y divide-line">/g, '<tbody>')
  s = s.replace(/<thead className="[^"]*">/g, '<thead>')
  s = s.replace(
    /<tr className="border-b border-line(?: last:border-b-0| last:border-0)?">/g,
    '<tr>',
  )
  s = s.replace(
    /<tr\s+key=\{([^}]*)\}\s+className="border-b border-line(?: last:border-b-0| last:border-0)?"\s*>/gs,
    '<tr key={$1}>',
  )
  // The header row carried the whole heading style on the <tr> in two files.
  s = s.replace(
    /<tr className="border-b border-line text-left text-xs font-medium tracking-wide text-ink-muted uppercase">/g,
    '<tr>',
  )

  return s
}

if (process.argv[1] && process.argv[1].endsWith("table-to-datatable.mjs")) {
const [, , file, label, minWidth] = process.argv
let s = fs.readFileSync(file, 'utf8')
s = convert(s)

// The shell. Two of the twelve had no scroll wrapper at all, which is why the
// two forms are handled separately rather than by one pattern.
const min = minWidth ? ` minWidth={${minWidth}}` : ''
const MARK = '__DT__DT__DT__'
s = s.replace(
  /<div className="overflow-x-auto rounded-card border border-line bg-white">\s*<table className="w-full(?: min-w-\[\d+px\])?(?: text-left)? text-sm">/,
  `${MARK}<DataTable label="${label}"${min}>`,
)
s = s.replace(
  /<div className="overflow-x-auto">\s*<table className="w-full(?: min-w-\[\d+px\])?(?: text-left)? text-sm">/,
  `${MARK}<DataTable label="${label}"${min}>`,
)
s = s.replace(/<\/table>\s*<\/div>/, '</DataTable>')

// Dropping the wrapper <div> left every line of the table indented for a
// nesting level that no longer exists. Pull the block back by two spaces —
// there is no formatter in this project to do it afterwards.
// Located by the marker rather than by searching for `<DataTable`, because one
// page (Cash) has two tables and the second run must not re-dedent the first.
{
  const open = s.indexOf(MARK)
  s = s.replace(MARK, '')
  const close = s.indexOf('</DataTable>', open)
  if (open !== -1 && close !== -1) {
    const lineStart = s.lastIndexOf('\n', open) + 1
    const body = s.slice(lineStart, close)
    const dedented = body
      .split('\n')
      .map((l, i) => (i === 0 ? l : l.replace(/^ {2}/, '')))
      .join('\n')
    // the closing tag sits on its own over-indented line too
    const closeEnd = s.indexOf('\n', close)
    const closeLine = s.slice(close, closeEnd === -1 ? undefined : closeEnd)
    s =
      s.slice(0, lineStart) +
      dedented +
      closeLine +
      s.slice(closeEnd === -1 ? s.length : closeEnd)
  }
}

fs.writeFileSync(file, s)
console.log(
  `${file}: ${(s.match(/<Td/g) || []).length} cells, ${(s.match(/<Th/g) || []).length} headings, DataTable=${s.includes('<DataTable')}`,
)
}
