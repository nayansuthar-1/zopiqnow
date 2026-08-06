import { readFile } from 'node:fs/promises'
import path from 'node:path'

/// Loads the repo's `.env` into `process.env`, without overwriting anything
/// already set there.
///
/// Every tool that needs it loads it for itself. The alternative — one entry
/// point loading it for the others — works right up until somebody runs the
/// inner script directly, which is exactly what happens when a step of a
/// pipeline fails and you want to retry just that step.
///
/// Real values already in the environment win, so a one-off
/// `PLAY_SERVICE_ACCOUNT_JSON=... node tool/…` overrides the file rather than
/// being silently ignored.
export async function loadEnv() {
  const file = path.resolve(import.meta.dirname, '..', '.env')
  const text = await readFile(file, 'utf8').catch(() => '')
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/)
    if (m && !process.env[m[1]]) {
      process.env[m[1]] = m[2].trim().replace(/^"|"$/g, '')
    }
  }
}
