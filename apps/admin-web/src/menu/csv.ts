/// A small CSV reader, because a 120-dish menu typed one dialog at a time is not
/// onboarding, it is data entry as punishment.
///
/// Deliberately not a library. What arrives here is a file we hand out the
/// template for, and the format that template uses is the one this parses: commas,
/// optional double quotes, doubled quotes to escape a quote inside a field. It
/// does not do semicolon delimiters, or the various things Excel does in other
/// locales. When one of those turns up, the preview shows the mess rather than
/// silently importing it — which is the actual requirement.

export const csvColumns = [
  'category',
  'name',
  'description',
  'price',
  'is_veg',
  'is_bestseller',
  'image_url',
] as const

export const csvTemplate = `category,name,description,price,is_veg,is_bestseller,image_url
Recommended,Paneer Tikka,"Char-grilled cottage cheese, mint chutney",280,yes,yes,
Recommended,Chicken Biryani,"Long-grain rice, slow-cooked",320,no,yes,
Breads,Butter Naan,,60,yes,no,
`

export type ParsedRow = {
  line: number
  values: Record<string, string>
  problem: string | null
}

function splitLine(line: string): string[] {
  const out: string[] = []
  let field = ''
  let quoted = false

  for (let i = 0; i < line.length; i++) {
    const c = line[i]
    if (quoted) {
      if (c === '"') {
        // A doubled quote inside a quoted field is one literal quote.
        if (line[i + 1] === '"') {
          field += '"'
          i++
        } else {
          quoted = false
        }
      } else {
        field += c
      }
    } else if (c === '"') {
      quoted = true
    } else if (c === ',') {
      out.push(field)
      field = ''
    } else {
      field += c
    }
  }
  out.push(field)
  return out.map((f) => f.trim())
}

/// `yes`, `y`, `true`, `1`, `veg` — whatever a person typing a spreadsheet by hand
/// would reasonably write. Anything else is false, including empty.
function truthy(value: string): boolean {
  return ['yes', 'y', 'true', '1', 'veg'].includes(value.trim().toLowerCase())
}

export function parseCsv(text: string): ParsedRow[] {
  const lines = text
    .replace(/^﻿/, '') // Excel's byte-order mark, invisible and load-bearing
    .split(/\r?\n/)
    .filter((l) => l.trim() !== '')

  if (lines.length === 0) return []

  const header = splitLine(lines[0]).map((h) => h.toLowerCase())
  const rows: ParsedRow[] = []

  for (let i = 1; i < lines.length; i++) {
    const cells = splitLine(lines[i])
    const values: Record<string, string> = {}
    header.forEach((h, index) => {
      values[h] = cells[index] ?? ''
    })

    let problem: string | null = null
    const price = Number(values.price)
    if (!values.name) problem = 'No dish name.'
    else if (!values.category) problem = 'No section.'
    else if (!values.price) problem = 'No price.'
    else if (!Number.isFinite(price) || !Number.isInteger(price)) {
      problem = `Price "${values.price}" is not a whole number.`
    } else if (price <= 0) problem = 'A dish has to cost more than zero.'

    rows.push({ line: i + 1, values, problem })
  }

  return rows
}

export function toMenuItem(row: ParsedRow): Record<string, unknown> {
  return {
    name: row.values.name,
    description: row.values.description ?? '',
    price: Number(row.values.price),
    category: row.values.category,
    is_veg: truthy(row.values.is_veg ?? ''),
    is_bestseller: truthy(row.values.is_bestseller ?? ''),
    image_url: row.values.image_url ?? '',
  }
}

export function missingColumns(text: string): string[] {
  const header = splitLine(text.split(/\r?\n/)[0] ?? '').map((h) => h.toLowerCase())
  return ['category', 'name', 'price'].filter((c) => !header.includes(c))
}
