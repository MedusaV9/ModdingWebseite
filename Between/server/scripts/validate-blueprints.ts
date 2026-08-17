/**
 * Validates all builtin blueprint JSON files. Exits non-zero on problems.
 * Usage: npm run validate  (inside Between/server)
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { validateBlueprint } from '../src/blueprints/schema.ts'

const here = path.dirname(fileURLToPath(import.meta.url))
const builtinDir = path.join(here, '..', 'src', 'blueprints', 'builtin')

let failed = 0
const ids = new Set<string>()
const files = fs.readdirSync(builtinDir).filter((f) => f.endsWith('.json')).sort()

for (const file of files) {
  try {
    const bp = JSON.parse(fs.readFileSync(path.join(builtinDir, file), 'utf8'))
    const problems = validateBlueprint(bp)
    if (bp.id && ids.has(bp.id)) problems.push(`duplicate blueprint id ${bp.id}`)
    ids.add(bp.id)
    if (problems.length > 0) {
      failed++
      console.error(`✗ ${file}`)
      for (const p of problems) console.error(`    - ${p}`)
    } else {
      console.log(`✓ ${file} (${bp.id})`)
    }
  } catch (err) {
    failed++
    console.error(`✗ ${file}: ${(err as Error).message}`)
  }
}

console.log(`\n${files.length - failed}/${files.length} blueprints valid`)
if (failed > 0) process.exit(1)
