import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { Blueprint } from '../types.ts'
import type { Collection } from '../lib/jsonstore.ts'
import { validateBlueprint } from './schema.ts'
import { parseYamlDoc, YamlDocError } from '../lib/yamldoc.ts'
import { nowIso } from '../lib/util.ts'

const here = path.dirname(fileURLToPath(import.meta.url))

/** Template files above this are certainly not blueprints (biggest builtin is ~8 KiB). */
const MAX_TEMPLATE_FILE_BYTES = 1024 * 1024

export interface TemplateScan {
  dir: string
  scannedAt: string
  loaded: { id: string; name: string; file: string }[]
  errors: { file: string; problems: string[] }[]
}

export class BlueprintRegistry {
  private builtin = new Map<string, Blueprint>()
  /** Blueprints loaded from drop-in template files (data/templates). */
  private fileTemplates = new Map<string, Blueprint>()
  lastTemplateScan: TemplateScan | null = null
  readonly assetsDir = path.join(here, 'assets')
  readonly builtinDir = path.join(here, 'builtin')

  constructor(
    private custom?: Collection<Blueprint & { id: string }>,
    /** Drop-in template directory (usually <dataDir>/templates); null = feature off. */
    readonly templatesDir: string | null = null,
  ) {
    this.loadBuiltins()
    if (templatesDir) this.loadFileTemplates()
  }

  /**
   * (Re)scan the drop-in template directory: every *.json / *.yaml / *.yml
   * file that validates as a blueprint becomes available like a builtin.
   * Invalid files never abort the scan — they are reported per file so one
   * broken template cannot take down the rest (or the panel boot).
   */
  loadFileTemplates(): TemplateScan {
    const dir = this.templatesDir
    const scan: TemplateScan = { dir: dir ?? '', scannedAt: nowIso(), loaded: [], errors: [] }
    this.fileTemplates.clear()
    if (!dir) {
      this.lastTemplateScan = scan
      return scan
    }
    try {
      fs.mkdirSync(dir, { recursive: true })
      for (const file of fs.readdirSync(dir).sort()) {
        if (!/\.(json|ya?ml)$/i.test(file)) continue
        try {
          const stat = fs.statSync(path.join(dir, file))
          if (!stat.isFile()) continue
          if (stat.size > MAX_TEMPLATE_FILE_BYTES) {
            scan.errors.push({ file, problems: [`file too large (max ${MAX_TEMPLATE_FILE_BYTES / 1024} KiB)`] })
            continue
          }
          const text = fs.readFileSync(path.join(dir, file), 'utf8')
          const doc = /\.json$/i.test(file) ? JSON.parse(text) : parseYamlDoc(text)
          const problems = validateBlueprint(doc)
          const bp = doc as Blueprint
          if (problems.length === 0) {
            if (this.builtin.has(bp.id)) problems.push(`id ${bp.id} collides with a builtin blueprint`)
            else if (this.custom?.get(bp.id)) problems.push(`id ${bp.id} collides with a custom blueprint`)
            else if (this.fileTemplates.has(bp.id)) problems.push(`id ${bp.id} already loaded from ${this.fileTemplates.get(bp.id)!.templateFile}`)
          }
          if (problems.length > 0) {
            scan.errors.push({ file, problems })
            continue
          }
          bp.custom = false
          bp.templateFile = file
          this.fileTemplates.set(bp.id, bp)
          scan.loaded.push({ id: bp.id, name: bp.name, file })
        } catch (err) {
          const msg = err instanceof YamlDocError ? err.message : (err as Error).message
          scan.errors.push({ file, problems: [msg] })
        }
      }
    } catch (err) {
      scan.errors.push({ file: '.', problems: [`cannot read template directory: ${(err as Error).message}`] })
    }
    if (scan.errors.length > 0)
      console.error('[templates] problems while loading template files:\n  ' + scan.errors.map((e) => `${e.file}: ${e.problems.join('; ')}`).join('\n  '))
    this.lastTemplateScan = scan
    return scan
  }

  loadBuiltins(): { loaded: number; errors: string[] } {
    this.builtin.clear()
    const errors: string[] = []
    if (!fs.existsSync(this.builtinDir)) return { loaded: 0, errors: ['builtin dir missing'] }
    for (const file of fs.readdirSync(this.builtinDir).sort()) {
      if (!file.endsWith('.json')) continue
      try {
        const bp = JSON.parse(fs.readFileSync(path.join(this.builtinDir, file), 'utf8')) as Blueprint
        const problems = validateBlueprint(bp)
        if (problems.length > 0) {
          errors.push(`${file}: ${problems.join('; ')}`)
          continue
        }
        if (this.builtin.has(bp.id)) {
          errors.push(`${file}: duplicate blueprint id ${bp.id}`)
          continue
        }
        bp.custom = false
        this.builtin.set(bp.id, bp)
      } catch (err) {
        errors.push(`${file}: ${(err as Error).message}`)
      }
    }
    if (errors.length > 0) console.error('[blueprints] problems while loading builtins:\n  ' + errors.join('\n  '))
    return { loaded: this.builtin.size, errors }
  }

  all(): Blueprint[] {
    const customs = (this.custom?.all() ?? []).map((bp) => ({ ...bp, custom: true }))
    return [...this.builtin.values(), ...this.fileTemplates.values(), ...customs]
  }

  get(id: string): Blueprint | undefined {
    const customBp = this.custom?.get(id)
    if (customBp) return { ...customBp, custom: true }
    return this.builtin.get(id) ?? this.fileTemplates.get(id)
  }

  isBuiltin(id: string): boolean {
    return this.builtin.has(id)
  }

  /** File templates are read-only via the API: edit the file, then rescan. */
  isFileTemplate(id: string): boolean {
    return this.fileTemplates.has(id)
  }

  addCustom(bp: Blueprint): { ok: boolean; problems: string[] } {
    const problems = validateBlueprint(bp)
    if (this.builtin.has(bp.id)) problems.push(`id ${bp.id} collides with a builtin blueprint`)
    if (this.fileTemplates.has(bp.id)) problems.push(`id ${bp.id} collides with a template file blueprint`)
    if (this.custom?.get(bp.id)) problems.push(`custom blueprint ${bp.id} already exists`)
    if (problems.length > 0) return { ok: false, problems }
    this.custom?.insert({ ...bp, custom: true })
    return { ok: true, problems: [] }
  }

  updateCustom(id: string, bp: Blueprint): { ok: boolean; problems: string[] } {
    if (!this.custom?.get(id)) return { ok: false, problems: [`custom blueprint ${id} not found`] }
    const problems = validateBlueprint(bp)
    if (bp.id !== id) problems.push('blueprint id cannot be changed')
    if (problems.length > 0) return { ok: false, problems }
    this.custom.update(id, () => undefined) // touch
    this.custom.update(id, bp as Partial<Blueprint & { id: string }>)
    return { ok: true, problems: [] }
  }

  removeCustom(id: string): boolean {
    return this.custom?.remove(id) ?? false
  }

  /**
   * Node-agent path: persist a panel-supplied blueprint copy embedded in a
   * remote create request, so custom panel blueprints work on nodes and
   * survive agent restarts. Unlike addCustom this may shadow a builtin id —
   * get() prefers the custom collection, so the panel's copy always wins.
   * Replace (not merge) so removed fields don't linger across updates.
   */
  putReplica(bp: Blueprint): { ok: boolean; problems: string[] } {
    const problems = validateBlueprint(bp)
    if (problems.length > 0) return { ok: false, problems }
    if (!this.custom) return { ok: false, problems: ['no custom blueprint store configured'] }
    this.custom.remove(bp.id)
    this.custom.insert({ ...bp, custom: true })
    return { ok: true, problems: [] }
  }

  /** Resolve "@asset:<name>" file references used by writeFile install steps. */
  resolveAsset(name: string): string {
    const file = path.join(this.assetsDir, path.basename(name))
    return fs.readFileSync(file, 'utf8')
  }
}
