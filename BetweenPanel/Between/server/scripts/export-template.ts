/**
 * Export a builtin blueprint as a drop-in template file (YAML by default,
 * JSON with --json) for the data/templates directory — the generic-instance
 * template format documented in docs/TEMPLATES.md.
 *
 * Usage:
 *   npx tsx scripts/export-template.ts <blueprintId> [--id <newId>] [--name <newName>] [--json] [-o <outFile>]
 *
 * Without -o the template is printed to stdout. `@asset:` references in
 * writeFile steps are inlined so the resulting file is fully self-contained.
 */
import fs from 'node:fs'
import path from 'node:path'
import { BlueprintRegistry } from '../src/blueprints/registry.ts'
import { stringifyYamlDoc } from '../src/lib/yamldoc.ts'
import { validateBlueprint } from '../src/blueprints/schema.ts'
import type { Blueprint, InstallStep } from '../src/types.ts'

function fail(msg: string): never {
  console.error(msg)
  process.exit(1)
}

const args = process.argv.slice(2)
const id = args.find((a) => !a.startsWith('-'))
if (!id) fail('usage: export-template.ts <blueprintId> [--id <newId>] [--name <newName>] [--json] [-o <outFile>]')
const flag = (name: string): string | undefined => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}

const registry = new BlueprintRegistry()
const source = registry.get(id)
if (!source) fail(`blueprint "${id}" not found (builtins: ${registry.all().length})`)

const bp: Blueprint = JSON.parse(JSON.stringify(source))
delete bp.custom
delete bp.templateFile
if (flag('--id')) bp.id = flag('--id')!
if (flag('--name')) bp.name = flag('--name')!

// Inline @asset: references — template files must be self-contained.
for (const step of bp.install as InstallStep[]) {
  if (step.type === 'writeFile' && step.content.startsWith('@asset:')) {
    step.content = registry.resolveAsset(step.content.slice('@asset:'.length))
  }
}

const problems = validateBlueprint(bp)
if (problems.length > 0) fail(`exported template would be invalid:\n  ${problems.join('\n  ')}`)

const out = args.includes('--json') ? JSON.stringify(bp, null, 2) + '\n' : stringifyYamlDoc(bp)
const outFile = flag('-o')
if (outFile) {
  fs.mkdirSync(path.dirname(path.resolve(outFile)), { recursive: true })
  fs.writeFileSync(outFile, out)
  console.log(`wrote ${outFile} (${out.length} bytes, id=${bp.id})`)
} else {
  process.stdout.write(out)
}
