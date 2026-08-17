import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { Blueprint } from '../types.ts'
import type { Collection } from '../lib/jsonstore.ts'
import { validateBlueprint } from './schema.ts'

const here = path.dirname(fileURLToPath(import.meta.url))

export class BlueprintRegistry {
  private builtin = new Map<string, Blueprint>()
  readonly assetsDir = path.join(here, 'assets')
  readonly builtinDir = path.join(here, 'builtin')

  constructor(private custom?: Collection<Blueprint & { id: string }>) {
    this.loadBuiltins()
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
    return [...this.builtin.values(), ...customs]
  }

  get(id: string): Blueprint | undefined {
    const customBp = this.custom?.get(id)
    if (customBp) return { ...customBp, custom: true }
    return this.builtin.get(id)
  }

  isBuiltin(id: string): boolean {
    return this.builtin.has(id)
  }

  addCustom(bp: Blueprint): { ok: boolean; problems: string[] } {
    const problems = validateBlueprint(bp)
    if (this.builtin.has(bp.id)) problems.push(`id ${bp.id} collides with a builtin blueprint`)
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
