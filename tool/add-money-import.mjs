// One-shot, deleted at the end of Phase 3.
import fs from 'fs'
import path from 'path'

for (const file of process.argv.slice(2)) {
  let s = fs.readFileSync(file, 'utf8')
  if (/from '(\.\.\/)+lib\/money'/.test(s)) continue
  if (!/\binr\(/.test(s)) continue

  // depth from src/, so the relative path is right in both src/x/ and
  // src/x/y/ (the wizard steps live one level deeper)
  const rel = path
    .relative(path.dirname(file), 'apps/admin-web/src/lib/money')
    .replace(/\\/g, '/')
  const spec = rel.startsWith('.') ? rel : './' + rel

  // Sits after the primitives import, which is the last of the local imports
  // in every one of these files.
  const m = s.match(/^import \{[\s\S]*?\} from '(?:\.\.\/)+ui\/primitives'$/m)
  if (!m) {
    console.log(`${file}: no anchor — add by hand`)
    continue
  }
  const eol = s.includes('\r\n') ? '\r\n' : '\n'
  s = s.replace(m[0], `${m[0]}${eol}import { inr } from '${spec}'`)
  fs.writeFileSync(file, s)
  console.log(`${file}: + inr from '${spec}'`)
}
