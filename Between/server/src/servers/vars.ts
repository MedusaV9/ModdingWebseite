import path from 'node:path'
import type { Blueprint, GameServer } from '../types.ts'

export interface VarContext {
  serverDir: string
  steamcmdDir: string
}

/** Merge blueprint defaults, saved server variables and built-in variables. */
export function buildVars(
  server: Pick<GameServer, 'id' | 'name' | 'variables'>,
  blueprint: Blueprint,
  ctx: VarContext,
): Record<string, string | number | boolean> {
  const vars: Record<string, string | number | boolean> = {}
  for (const v of blueprint.variables) vars[v.key] = v.default
  for (const [key, value] of Object.entries(server.variables ?? {})) vars[key] = value
  vars.SERVER_DIR = path.resolve(ctx.serverDir)
  vars.SERVER_NAME = server.name
  vars.SERVER_ID = server.id
  vars.STEAMCMD_DIR = path.resolve(ctx.steamcmdDir)
  vars.PLATFORM = process.platform
  return vars
}

/** Validate + coerce user-provided variable values against the blueprint. */
export function coerceVariables(
  blueprint: Blueprint,
  input: Record<string, unknown>,
): { values: Record<string, string | number | boolean>; problems: string[] } {
  const problems: string[] = []
  const values: Record<string, string | number | boolean> = {}
  for (const v of blueprint.variables) {
    const raw = input[v.key]
    if (raw === undefined || raw === null || raw === '') {
      if (v.required && (v.default === '' || v.default === undefined)) {
        problems.push(`${v.label} (${v.key}) is required`)
      }
      values[v.key] = v.default
      continue
    }
    switch (v.type) {
      case 'number': {
        const n = typeof raw === 'number' ? raw : Number(raw)
        if (!Number.isFinite(n)) {
          problems.push(`${v.label} must be a number`)
          break
        }
        if (v.min !== undefined && n < v.min) problems.push(`${v.label} must be >= ${v.min}`)
        else if (v.max !== undefined && n > v.max) problems.push(`${v.label} must be <= ${v.max}`)
        else values[v.key] = n
        break
      }
      case 'boolean':
        values[v.key] = raw === true || raw === 'true' || raw === '1' || raw === 1
        break
      case 'enum': {
        const s = String(raw)
        if (!v.options?.some((o) => o.value === s)) problems.push(`${v.label}: invalid option ${s}`)
        else values[v.key] = s
        break
      }
      default: {
        const s = String(raw)
        if (s.length > 500) {
          problems.push(`${v.label} is too long`)
          break
        }
        if (v.pattern && s !== '' && !new RegExp(v.pattern).test(s)) {
          problems.push(`${v.label} does not match the required format`)
          break
        }
        values[v.key] = s
      }
    }
    if (!(v.key in values)) values[v.key] = v.default
  }
  return { values, problems }
}
