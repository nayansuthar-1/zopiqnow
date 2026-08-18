// Turns the Word originals in `legal/source/` into Dart data files.
//
//   node tool/import_legal.mjs
//
// The .docx files are the source of truth — they are what the lawyers touch and
// what gets signed off. Everything else is generated: the Dart in
// `packages/zopiq_legal/`, which all three apps render, and the HTML in
// `legal/`, which Play links to. Two hand-kept copies of a legal document is
// two documents that disagree within a year, and the one that disagrees is
// always the one somebody is reading.
//
// **Do not edit the generated Dart.** Edit the .docx, run this, commit both.
//
// Zero dependencies, like every other script in `tool/` — there is no
// package.json in this repo and adding one to read a zip file would be a poor
// trade. A .docx is a zip of deflated XML, and `zlib.inflateRawSync` is in the
// standard library.

import { readFileSync, writeFileSync, readdirSync, mkdirSync } from 'node:fs';
import { inflateRawSync } from 'node:zlib';
import { join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const sourceDir = join(repo, 'legal', 'source');
const outDir = join(repo, 'packages', 'zopiq_legal', 'lib', 'src', 'documents');

// The date every document's `[To be inserted on launch]` placeholder becomes.
// One constant because it appears in 21 documents, and 21 dates is 21 chances
// for one of them to be wrong.
const EFFECTIVE_DATE = '18 August 2026';

// ---------------------------------------------------------------------------
// A zip reader, in as few lines as correctness allows
// ---------------------------------------------------------------------------

/// Pulls one entry out of a zip by name. Walks the central directory rather
/// than scanning for local headers: a local header may declare sizes of zero
/// and defer them to a trailing data descriptor, and the central directory
/// always carries the real ones.
function readZipEntry(buf, wanted) {
  // End of central directory: fixed 22 bytes, unless there is a comment, so
  // scan back from the end for its signature.
  let eocd = -1;
  for (let i = buf.length - 22; i >= 0 && i > buf.length - 22 - 0xffff; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error('not a zip file: no end-of-central-directory');

  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);

  for (let i = 0; i < count; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) {
      throw new Error('corrupt central directory');
    }
    const method = buf.readUInt16LE(p + 10);
    const compressedSize = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const localOffset = buf.readUInt32LE(p + 42);
    const name = buf.toString('utf8', p + 46, p + 46 + nameLen);

    if (name === wanted) {
      // The local header's own name/extra lengths are what the data sits
      // behind — the central directory's extra field is a different length.
      const lNameLen = buf.readUInt16LE(localOffset + 26);
      const lExtraLen = buf.readUInt16LE(localOffset + 28);
      const start = localOffset + 30 + lNameLen + lExtraLen;
      const data = buf.subarray(start, start + compressedSize);
      return method === 0 ? data : inflateRawSync(data);
    }

    p += 46 + nameLen + extraLen + commentLen;
  }
  throw new Error(`no entry ${wanted} in archive`);
}

// ---------------------------------------------------------------------------
// WordprocessingML → blocks
// ---------------------------------------------------------------------------

function decodeEntities(s) {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&amp;/g, '&');
}

/// The text of one `<w:p>` or `<w:tc>`: every `<w:t>` in it, joined, with tabs
/// and explicit breaks preserved as spaces. Word splits a sentence across runs
/// whenever formatting changes mid-line, so this has to concatenate rather than
/// take the first.
function textOf(xml) {
  let out = '';
  const re = /<w:t(?:\s[^>]*)?>([\s\S]*?)<\/w:t>|<w:tab\b[^>]*\/>|<w:br\b[^>]*\/>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    out += m[1] !== undefined ? decodeEntities(m[1]) : ' ';
  }
  // Word's smart punctuation, normalised to what a Dart string literal and a
  // terminal both survive. The curly apostrophe in particular appears in
  // "Zopiq's" hundreds of times.
  return out
    .replace(/ /g, ' ')
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/\s+/g, ' ')
    .trim();
}

/// Splits the body into top-level `<w:p>` and `<w:tbl>` elements, in order.
/// A regex, because the only nesting that matters here is a paragraph inside a
/// table cell — and taking whole `<w:tbl>` blocks first means those paragraphs
/// are consumed with their table rather than seen twice.
function splitBody(xml) {
  const body = /<w:body>([\s\S]*)<\/w:body>/.exec(xml);
  const inner = body ? body[1] : xml;
  const out = [];
  const re = /<w:tbl>[\s\S]*?<\/w:tbl>|<w:p\b[^>]*\/>|<w:p\b[^>]*>[\s\S]*?<\/w:p>/g;
  let m;
  while ((m = re.exec(inner)) !== null) {
    out.push({ kind: m[0].startsWith('<w:tbl') ? 'tbl' : 'p', xml: m[0] });
  }
  return out;
}

function parseTable(xml) {
  const rows = [];
  const rowRe = /<w:tr\b[^>]*>[\s\S]*?<\/w:tr>/g;
  let r;
  while ((r = rowRe.exec(xml)) !== null) {
    const cells = [];
    const cellRe = /<w:tc\b[^>]*>[\s\S]*?<\/w:tc>/g;
    let c;
    while ((c = cellRe.exec(r[0])) !== null) cells.push(textOf(c[0]));
    if (cells.some((x) => x !== '')) rows.push(cells);
  }
  if (rows.length === 0) return null;
  return { type: 'table', headers: rows[0], rows: rows.slice(1) };
}

/// Word writes a heading as a paragraph carrying `<w:pStyle w:val="Heading2"/>`
/// and a bullet as one carrying `<w:numPr>`. Both are reliable in these files —
/// they were generated, not hand-formatted — so the structure survives the trip
/// instead of arriving as one undifferentiated wall of text.
function paragraphKind(xml) {
  const style = /<w:pStyle w:val="([^"]+)"/.exec(xml);
  const name = style ? style[1] : '';
  const heading = /^Heading(\d)$/.exec(name);
  if (heading) return { kind: 'heading', level: Number(heading[1]) };
  if (/<w:numPr>/.test(xml)) return { kind: 'bullet' };
  return { kind: 'paragraph' };
}

// ---------------------------------------------------------------------------
// Cover page and metadata
// ---------------------------------------------------------------------------

/// Every document opens with the same generated cover block: the brand, the
/// title, a document number, a version, a status, an effective date and the
/// LLP's registered address. It is metadata that Word had nowhere to put, so it
/// was typed onto page one — rendering it as body text would put "Status:
/// Publication-Ready" in front of a customer. This lifts it out.
function takeCover(blocks) {
  const meta = {};
  const labels = {
    'Document': 'docId',
    'Version': 'version',
    'Status': 'status',
    'Effective Date': 'effectiveDate',
    'Last Updated': 'lastUpdated',
    'Owner': 'owner',
  };

  // The cover ends at the first real heading. Anything before that is either a
  // label, the brand line, the title, the subtitle, or the address block.
  let end = blocks.findIndex((b) => b.type === 'heading');
  if (end < 0) end = 0;

  const lead = [];
  for (const b of blocks.slice(0, end)) {
    const text = b.type === 'paragraph' || b.type === 'bullet' ? b.text : '';
    if (!text) continue;
    const labelled = /^([A-Za-z ]+):\s*(.+)$/.exec(text);
    if (labelled && labels[labelled[1].trim()]) {
      meta[labels[labelled[1].trim()]] = labelled[2].trim();
      continue;
    }
    lead.push(text);
  }

  // What is left, in order: "ZOPIQ", "Legal & Operational Documentation", the
  // TITLE in caps, then the subtitle. The two main documents (Terms, Privacy)
  // have no subtitle and put their version on the cover instead.
  const titleIndex = lead.findIndex(
    (t) => t === t.toUpperCase() && /[A-Z]{4}/.test(t) && t !== 'ZOPIQ',
  );
  if (titleIndex >= 0) {
    meta.coverTitle = titleCase(lead[titleIndex]);
    const next = lead[titleIndex + 1];
    // A subtitle is the descriptive line the numbered documents carry
    // ("Customer Orders, Cancellations, and Refunds"). The two main documents
    // have none and put their version number there instead, which is metadata
    // already captured above and would read as a subtitle if left alone.
    if (
      next &&
      next !== next.toUpperCase() &&
      !/^Hybrid Monks/.test(next) &&
      !/^Version\b/i.test(next)
    ) {
      meta.subtitle = next;
    }
  }

  return { meta, body: blocks.slice(end) };
}

/// "REFUND & CANCELLATION POLICY" reads as shouting in a list of 21 rows.
/// Small words stay lowercase, except first.
const SMALL = new Set(['and', 'or', 'of', 'the', 'for', 'to', 'in', 'a', 'an', 'on']);
function titleCase(s) {
  return s
    .toLowerCase()
    .split(' ')
    .map((w, i) => {
      if (i > 0 && SMALL.has(w)) return w;
      // Keep acronyms the source shouted for a reason.
      if (['ai', 'sla', 'cod', 'gst', 'faq'].includes(w)) return w.toUpperCase();
      return w.charAt(0).toUpperCase() + w.slice(1);
    })
    .join(' ');
}

// ---------------------------------------------------------------------------
// Who each document is for
// ---------------------------------------------------------------------------

// Hand-assigned, not inferred. Which audience a policy belongs to is an
// editorial decision — the Merchant SLA mentions customers on every page and is
// still not a customer document — and guessing it from the text would put the
// Delivery Partner Verification Policy in front of somebody ordering a dosa.
const AUDIENCES = {
  Zopiq_Terms_and_Conditions: ['customer', 'restaurant', 'rider'],
  Zopiq_Privacy_Policy: ['customer', 'restaurant', 'rider'],
  Zopiq_Account_Deletion_Data_Retention_Policy: ['customer', 'restaurant', 'rider'],
  '01_Refund_and_Cancellation_Policy': ['customer', 'restaurant'],
  '02_Community_Guidelines': ['customer', 'restaurant', 'rider'],
  '03_Cookie_Policy': ['customer'],
  '04_App_Permissions_Policy': ['customer', 'restaurant', 'rider'],
  '05_Restaurant_Partner_Handbook': ['restaurant'],
  '06_Delivery_Partner_Handbook': ['rider'],
  '07_Merchant_SLA': ['restaurant'],
  '08_Grievance_Redressal_Policy': ['customer', 'restaurant', 'rider'],
  '09_Intellectual_Property_Policy': ['customer', 'restaurant', 'rider'],
  '10_Fraud_Prevention_Policy': ['customer', 'restaurant', 'rider'],
  '11_Platform_Safety_Policy': ['customer', 'restaurant', 'rider'],
  '12_Payment_and_Settlement_Policy': ['restaurant', 'rider'],
  '13_Restaurant_Verification_Policy': ['restaurant'],
  '14_Delivery_Partner_Verification_Policy': ['rider'],
  '15_Website_Terms_of_Use': ['customer'],
  '16_Data_Breach_Response_Policy': ['customer', 'restaurant', 'rider'],
  '17_Accessibility_Statement': ['customer', 'restaurant', 'rider'],
  '18_AI_Usage_and_Automated_Decision_Policy': ['customer', 'restaurant', 'rider'],
};

// The two documents a user must accept to sign in. Everything else is reference
// material they can read, and gating sign-in on 21 documents nobody reads is
// not consent — it is a dark pattern with extra steps.
const CONSENT = new Set(['Zopiq_Terms_and_Conditions', 'Zopiq_Privacy_Policy']);

// Order in the index, and the group each falls under.
const GROUPS = {
  Zopiq_Terms_and_Conditions: 'core',
  Zopiq_Privacy_Policy: 'core',
  Zopiq_Account_Deletion_Data_Retention_Policy: 'core',
  '01_Refund_and_Cancellation_Policy': 'orders',
  '12_Payment_and_Settlement_Policy': 'orders',
  '02_Community_Guidelines': 'conduct',
  '11_Platform_Safety_Policy': 'conduct',
  '10_Fraud_Prevention_Policy': 'conduct',
  '09_Intellectual_Property_Policy': 'conduct',
  '03_Cookie_Policy': 'data',
  '04_App_Permissions_Policy': 'data',
  '16_Data_Breach_Response_Policy': 'data',
  '18_AI_Usage_and_Automated_Decision_Policy': 'data',
  '08_Grievance_Redressal_Policy': 'support',
  '17_Accessibility_Statement': 'support',
  '15_Website_Terms_of_Use': 'support',
  '05_Restaurant_Partner_Handbook': 'partner',
  '07_Merchant_SLA': 'partner',
  '13_Restaurant_Verification_Policy': 'partner',
  '06_Delivery_Partner_Handbook': 'partner',
  '14_Delivery_Partner_Verification_Policy': 'partner',
};

/// `01_Refund_and_Cancellation_Policy` → `refund-and-cancellation-policy`.
/// The number is a filing order, not part of the name, and it would date the
/// URL the moment a document is inserted between two others.
function slugOf(name) {
  return name
    .replace(/^\d+_/, '')
    .replace(/^Zopiq_/, '')
    .replace(/_/g, '-')
    .toLowerCase();
}

// ---------------------------------------------------------------------------
// Dart emission
// ---------------------------------------------------------------------------

function dartString(s) {
  return `'${s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;
}

/// Wraps a long string literal across lines so the generated file is readable
/// in a diff and does not trip an 80-column lint.
function dartWrapped(s, indent) {
  const escaped = s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$');
  const width = 78 - indent.length;
  if (escaped.length <= width) return `'${escaped}'`;

  const lines = [];
  let line = '';
  for (const word of escaped.split(' ')) {
    if (line && (line + ' ' + word).length > width) {
      lines.push(line);
      line = word;
    } else {
      line = line ? line + ' ' + word : word;
    }
  }
  if (line) lines.push(line);

  return lines
    .map((l, i) => `'${l}${i === lines.length - 1 ? '' : ' '}'`)
    .join(`\n${indent}    `);
}

function emitBlock(b, indent) {
  const i = indent;
  switch (b.type) {
    case 'heading':
      return `${i}LegalHeading(${b.level}, ${dartWrapped(b.text, i + '  ')}),`;
    case 'paragraph':
      return `${i}LegalParagraph(\n${i}  ${dartWrapped(b.text, i + '  ')},\n${i}),`;
    case 'bullets': {
      const items = b.items
        .map((x) => `${i}    ${dartWrapped(x, i + '    ')},`)
        .join('\n');
      return `${i}LegalBullets(<String>[\n${items}\n${i}]),`;
    }
    case 'table': {
      const head = b.headers.map((h) => dartString(h)).join(', ');
      const rows = b.rows
        .map((r) => `${i}    <String>[${r.map((c) => dartWrapped(c, i + '      ')).join(', ')}],`)
        .join('\n');
      return `${i}LegalTable(\n${i}  headers: <String>[${head}],\n${i}  rows: <List<String>>[\n${rows}\n${i}  ],\n${i}),`;
    }
    default:
      throw new Error(`unknown block ${b.type}`);
  }
}

function emitDocument(name, doc) {
  const varName = camel(slugOf(name));
  const audiences = AUDIENCES[name].map((a) => `LegalAudience.${a}`).join(', ');
  const blocks = doc.blocks.map((b) => emitBlock(b, '    ')).join('\n');

  return `// GENERATED BY tool/import_legal.mjs — DO NOT EDIT.
// Source: legal/source/${name}.docx
//
// Edit the Word document, run \`node tool/import_legal.mjs\`, commit both.
import 'package:zopiq_legal/src/legal_document.dart';

const LegalDocument ${varName} = LegalDocument(
  slug: ${dartString(doc.slug)},
  title: ${dartString(doc.title)},
  subtitle: ${doc.subtitle ? dartString(doc.subtitle) : 'null'},
  docId: ${doc.docId ? dartString(doc.docId) : 'null'},
  version: ${dartString(doc.version)},
  effectiveDate: ${dartString(doc.effectiveDate)},
  group: ${dartString(doc.group)},
  audiences: <LegalAudience>{${audiences}},
  requiresConsent: ${doc.requiresConsent},
  blocks: <LegalBlock>[
${blocks}
  ],
);
`;
}

function camel(slug) {
  const parts = slug.split('-');
  return parts[0] + parts.slice(1).map((p) => p.charAt(0).toUpperCase() + p.slice(1)).join('');
}

// ---------------------------------------------------------------------------

/// Replaces the `[To be inserted on launch]` placeholders with a real date,
/// wherever they appear — including inside the version-history tables, which is
/// where the first pass at this missed one.
function withDate(block) {
  const fix = (s) =>
    s.replace(/\[(?:To be inserted(?: on launch)?|Launch Date)\]/g, EFFECTIVE_DATE);

  if (block.type === 'table') {
    return {
      ...block,
      headers: block.headers.map(fix),
      rows: block.rows.map((r) => r.map(fix)),
    };
  }
  return block.text === undefined ? block : { ...block, text: fix(block.text) };
}

function parseDocument(file) {
  const name = basename(file, '.docx');
  const xml = readZipEntry(readFileSync(file), 'word/document.xml').toString('utf8');

  // Pass one: every paragraph and table, typed.
  const raw = [];
  for (const el of splitBody(xml)) {
    if (el.kind === 'tbl') {
      const table = parseTable(el.xml);
      if (table) raw.push(table);
      continue;
    }
    const text = textOf(el.xml);
    if (!text) continue;
    const k = paragraphKind(el.xml);
    if (k.kind === 'heading') raw.push({ type: 'heading', level: k.level, text });
    else if (k.kind === 'bullet') raw.push({ type: 'bullet', text });
    else raw.push({ type: 'paragraph', text });
  }

  const { meta, body } = takeCover(raw);

  // Pass two: drop Word's table of contents, collapse runs of bullets into one
  // list, and turn the date placeholders into a real date.
  const blocks = [];
  let skipping = false;
  for (const b of body) {
    // Word's TOC is a field: the page numbers are live and arrive here as
    // "4.2 After Restaurant Acceptance •" with nothing after the bullet. An app
    // has a scrollbar and a back arrow, so a contents list of dead page numbers
    // is thirty rows of noise before the document starts. It runs from its own
    // heading to the next top-level one.
    if (b.type === 'heading') {
      skipping = b.level === 1 && /^table of contents$/i.test(b.text.trim());
      if (skipping) continue;
    }
    if (skipping) continue;

    const fixed = withDate(b);

    if (fixed.type === 'bullet') {
      const last = blocks[blocks.length - 1];
      if (last && last.type === 'bullets') last.items.push(fixed.text);
      else blocks.push({ type: 'bullets', items: [fixed.text] });
    } else {
      blocks.push(fixed);
    }
  }

  return {
    name,
    slug: slugOf(name),
    title: meta.coverTitle ?? titleCase(name.replace(/^\d+_/, '').replace(/_/g, ' ')),
    subtitle: meta.subtitle ?? null,
    docId: meta.docId ?? null,
    version: meta.version ?? '1.0',
    effectiveDate: EFFECTIVE_DATE,
    group: GROUPS[name],
    requiresConsent: CONSENT.has(name),
    blocks,
  };
}

function main() {
  mkdirSync(outDir, { recursive: true });

  const files = readdirSync(sourceDir)
    .filter((f) => f.endsWith('.docx'))
    .sort();

  const docs = [];
  for (const f of files) {
    const doc = parseDocument(join(sourceDir, f));
    if (!AUDIENCES[doc.name]) {
      throw new Error(
        `${doc.name} has no audience. Add it to AUDIENCES and GROUPS in this ` +
          `script — a document nobody is assigned to is a document nobody sees.`,
      );
    }
    writeFileSync(join(outDir, `${doc.slug.replace(/-/g, '_')}.dart`), emitDocument(doc.name, doc));
    docs.push(doc);
    console.log(
      `  ${doc.slug.padEnd(42)} ${String(doc.blocks.length).padStart(4)} blocks  ` +
        `[${AUDIENCES[doc.name].join(', ')}]`,
    );
  }

  // The manifest: every document, in filing order, so the index page, the apps
  // and the HTML build all read from one list rather than four that drift.
  const imports = docs
    .map((d) => `import 'package:zopiq_legal/src/documents/${d.slug.replace(/-/g, '_')}.dart';`)
    .sort()
    .join('\n');
  const entries = docs.map((d) => `  ${camel(d.slug)},`).join('\n');

  // The version somebody's acceptance is recorded against. Generated rather
  // than typed, because a consent version that has to be remembered is a
  // consent version that will one day say 1.0 about a document that says 1.1 —
  // and then nobody is re-asked when the terms change.
  const consentVersions = [...new Set(docs.filter((d) => d.requiresConsent).map((d) => d.version))];
  const consentVersion =
    consentVersions.length === 1
      ? consentVersions[0]
      : docs
          .filter((d) => d.requiresConsent)
          .map((d) => `${d.slug}@${d.version}`)
          .join('+');

  writeFileSync(
    join(outDir, 'all.dart'),
    `// GENERATED BY tool/import_legal.mjs — DO NOT EDIT.
${imports}
import 'package:zopiq_legal/src/legal_document.dart';

/// Every legal document, in filing order.
const List<LegalDocument> allLegalDocuments = <LegalDocument>[
${entries}
];

/// The version string an acceptance is recorded against. Bumping a consent
/// document's version in Word changes this, and everybody is asked again.
const String legalConsentVersion = ${dartString(consentVersion)};
`,
  );

  console.log(`\n${docs.length} documents → ${outDir}`);
  console.log(`consent version: ${consentVersion}`);
}

main();
