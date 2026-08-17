/**
 * Pterodactyl egg → Between blueprint conversion. Pure module (no I/O):
 * accepts both PTDL_v1 and PTDL_v2 egg exports and reports every lossy or
 * skipped mapping as a human-readable warning. The result always passes
 * validateBlueprint() — anything that cannot be represented is dropped with
 * a warning instead of producing an invalid blueprint.
 */
import type { Blueprint, BlueprintVariable, ConfigFileSpec, InstallStep, StopStrategy } from '../types.ts'
import { slugify } from './util.ts'
import { isValidImageRef } from './docker.ts'

/** Between built-ins that are always available in templates. */
const BUILTIN_VARS = new Set(['SERVER_DIR', 'SERVER_NAME', 'SERVER_ID', 'STEAMCMD_DIR', 'PLATFORM'])
const FALLBACK_INSTALL_IMAGE = 'debian:bookworm-slim'
const TEMPLATE_RE = /\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

/** Egg exports usually double-encode config sub-objects as JSON strings. */
function parseEmbedded(value: unknown, what: string, warnings: string[]): Record<string, unknown> | null {
  if (value === undefined || value === null || value === '') return null
  let parsed: unknown = value
  if (typeof value === 'string') {
    try {
      parsed = JSON.parse(value)
    } catch {
      warnings.push(`${what} is not valid JSON — skipped`)
      return null
    }
  }
  return isRecord(parsed) ? parsed : null
}

/** Uppercase, replace invalid chars, ensure a leading letter — VAR_KEY_RE safe. */
function sanitizeVarKey(raw: string): string {
  let key = raw.trim().toUpperCase().replace(/[^A-Z0-9_]/g, '_')
  if (!/^[A-Z]/.test(key)) key = `V_${key}`
  return key.slice(0, 64)
}

function uniqueKey(base: string, used: Set<string>): string {
  if (!used.has(base)) return base
  for (let n = 2; ; n++) {
    const suffix = `_${n}`
    const candidate = base.slice(0, 64 - suffix.length) + suffix
    if (!used.has(candidate)) return candidate
  }
}

/** Laravel-style rules: "required|numeric|between:1024,65535" or an array. */
function parseRules(raw: unknown): string[] {
  if (Array.isArray(raw)) return raw.map((r) => String(r).trim()).filter((r) => r.length > 0)
  if (typeof raw === 'string')
    return raw
      .split('|')
      .map((r) => r.trim())
      .filter((r) => r.length > 0)
  return []
}

function parseBooleanish(v: unknown): boolean {
  return v === true || v === 1 || v === '1' || v === 'true'
}

/** Replace {{name}} references (optional inner whitespace) with {{key}}. */
function renameRefs(text: string, from: string, to: string): string {
  return text.replace(new RegExp(`\\{\\{\\s*${escapeRegex(from)}\\s*\\}\\}`, 'g'), `{{${to}}}`)
}

interface ConversionState {
  variables: BlueprintVariable[]
  keys: Set<string>
  /** Original egg env name → sanitized Between key (only when they differ). */
  renames: Map<string, string>
  warnings: string[]
}

function convertVariables(egg: Record<string, unknown>, state: ConversionState): void {
  const raw = Array.isArray(egg.variables) ? egg.variables : []
  raw.forEach((entry, i) => {
    if (!isRecord(entry) || typeof entry.env_variable !== 'string' || entry.env_variable.trim().length === 0) {
      state.warnings.push(`variables[${i}]: missing env_variable — skipped`)
      return
    }
    const envName = entry.env_variable.trim()
    let key = sanitizeVarKey(envName)
    key = uniqueKey(key, state.keys)
    if (key !== envName) {
      state.renames.set(envName, key)
      state.warnings.push(`variable "${envName}" renamed to ${key} (Between variable key format)`)
    }
    state.keys.add(key)

    const rules = parseRules(entry.rules)
    const label = typeof entry.name === 'string' && entry.name.trim().length > 0 ? entry.name.trim() : key
    const description = typeof entry.description === 'string' && entry.description.trim().length > 0 ? entry.description.trim() : undefined
    const required = rules.includes('required')
    const advanced = entry.user_editable === false
    const inRule = rules.find((r) => r.startsWith('in:'))

    const variable: BlueprintVariable = { key, label, type: 'string', default: '' }
    if (description) variable.description = description
    if (required) variable.required = true
    if (advanced) variable.advanced = true

    if (rules.includes('numeric') || rules.includes('integer')) {
      variable.type = 'number'
      const n = Number(entry.default_value)
      if (entry.default_value === undefined || entry.default_value === null || entry.default_value === '') {
        variable.default = 0
      } else if (Number.isFinite(n)) {
        variable.default = n
      } else {
        variable.default = 0
        state.warnings.push(`variable ${key}: default ${JSON.stringify(entry.default_value)} is not a number — using 0`)
      }
      const between = rules.find((r) => r.startsWith('between:'))
      if (between) {
        const [min, max] = between.slice('between:'.length).split(',').map(Number)
        if (Number.isFinite(min)) variable.min = min
        if (Number.isFinite(max)) variable.max = max
      }
      const min = rules.find((r) => r.startsWith('min:'))
      const max = rules.find((r) => r.startsWith('max:'))
      if (min && Number.isFinite(Number(min.slice(4)))) variable.min = Number(min.slice(4))
      if (max && Number.isFinite(Number(max.slice(4)))) variable.max = Number(max.slice(4))
    } else if (rules.includes('boolean') || rules.includes('bool')) {
      variable.type = 'boolean'
      variable.default = parseBooleanish(entry.default_value)
    } else if (inRule) {
      variable.type = 'enum'
      const values = [...new Set(inRule.slice('in:'.length).split(',').map((v) => v.trim()).filter((v) => v.length > 0))]
      const options = values.map((value) => ({ value, label: value }))
      const fallback = typeof entry.default_value === 'string' || typeof entry.default_value === 'number' ? String(entry.default_value) : ''
      if (!values.includes(fallback)) {
        options.push({ value: fallback, label: fallback })
        state.warnings.push(`variable ${key}: default ${JSON.stringify(fallback)} was not in its allowed values — added as an option`)
      }
      variable.options = options
      variable.default = fallback
    } else {
      variable.default = entry.default_value === undefined || entry.default_value === null ? '' : String(entry.default_value)
    }

    state.variables.push(variable)
  })

  // An egg-declared SERVER_PORT is a real port — let it drive port publishing.
  const serverPort = state.variables.find((v) => v.key === 'SERVER_PORT')
  if (serverPort && serverPort.type === 'number') serverPort.isPort = true
}

/** Add a variable the egg did not declare but references (Ptero built-ins etc.). */
function autoAddVariable(state: ConversionState, variable: BlueprintVariable): void {
  state.variables.push(variable)
  state.keys.add(variable.key)
}

function ensureServerMemory(state: ConversionState): string {
  if (!state.keys.has('SERVER_MEMORY'))
    autoAddVariable(state, { key: 'SERVER_MEMORY', label: 'Memory (MiB)', type: 'number', default: 2048, min: 128 })
  return 'SERVER_MEMORY'
}

/** Translate a Ptero config `find` placeholder into a Between variable key. */
function translateConfigPlaceholder(inner: string, state: ConversionState): string | null {
  if (inner === 'server.build.default.port') {
    const portVar = state.variables.find((v) => v.isPort)
    return portVar ? portVar.key : null
  }
  if (inner === 'server.build.memory' || inner === 'server.build.memory_limit') return ensureServerMemory(state)
  const envMatch = inner.match(/^(?:env|server\.env|server\.build\.env)\.(.+)$/)
  if (envMatch) {
    const key = state.renames.get(envMatch[1]) ?? sanitizeVarKey(envMatch[1])
    return state.keys.has(key) ? key : null
  }
  return null
}

function convertConfigFiles(filesRaw: unknown, state: ConversionState): ConfigFileSpec[] {
  const parsed = parseEmbedded(filesRaw, 'config.files', state.warnings)
  if (!parsed) return []
  const specs: ConfigFileSpec[] = []
  const formats: Record<string, ConfigFileSpec['format']> = { properties: 'properties', ini: 'ini', json: 'json' }
  for (const [filePath, spec] of Object.entries(parsed)) {
    if (!isRecord(spec)) {
      state.warnings.push(`config file ${filePath}: not an object — skipped`)
      continue
    }
    const parser = String(spec.parser ?? '')
    const format = formats[parser]
    if (!format) {
      state.warnings.push(`config file ${filePath}: parser "${parser}" is not supported — skipped`)
      continue
    }
    const find = isRecord(spec.find) ? spec.find : {}
    // Between mappings are inverse (variable key → config key), so only find
    // entries whose value is exactly one translatable placeholder survive.
    const mappings: Record<string, string> = {}
    for (const [configKey, value] of Object.entries(find)) {
      if (typeof value !== 'string') {
        state.warnings.push(`config file ${filePath}: "${configKey}" has a non-string replacement — skipped`)
        continue
      }
      const single = value.trim().match(/^\{\{\s*([^{}]+?)\s*\}\}$/)
      if (!single) {
        state.warnings.push(`config file ${filePath}: "${configKey}" is not a single variable placeholder — skipped`)
        continue
      }
      const varKey = translateConfigPlaceholder(single[1], state)
      if (!varKey) {
        state.warnings.push(`config file ${filePath}: cannot translate {{${single[1]}}} for "${configKey}" — skipped`)
        continue
      }
      if (mappings[varKey] !== undefined) {
        state.warnings.push(`config file ${filePath}: ${varKey} already maps to "${mappings[varKey]}" — "${configKey}" skipped`)
        continue
      }
      mappings[varKey] = configKey
    }
    if (Object.keys(mappings).length > 0) specs.push({ path: filePath, format, mappings })
  }
  return specs
}

function collectDockerImages(egg: Record<string, unknown>, warnings: string[]): { label: string; image: string }[] {
  const out: { label: string; image: string }[] = []
  const push = (labelRaw: string, imageRaw: unknown) => {
    const image = typeof imageRaw === 'string' ? imageRaw.trim() : ''
    if (!image || !isValidImageRef(image)) {
      warnings.push(`docker image ${JSON.stringify(imageRaw)} is not a valid image reference — skipped`)
      return
    }
    const label = (labelRaw.trim() || image.split('/').pop() || image).slice(0, 40)
    out.push({ label, image })
  }
  if (isRecord(egg.docker_images)) {
    // PTDL_v2: map of label → image
    for (const [label, image] of Object.entries(egg.docker_images)) push(label, image)
  } else if (Array.isArray(egg.images)) {
    // Late PTDL_v1: plain list of images
    for (const image of egg.images) push('', image)
  } else if (typeof egg.image === 'string' && egg.image.trim().length > 0) {
    // Early PTDL_v1: single image
    push('', egg.image)
  }
  return out
}

function convertInstallScript(egg: Record<string, unknown>, warnings: string[]): InstallStep[] {
  const scripts = isRecord(egg.scripts) ? egg.scripts : {}
  const installation = isRecord(scripts.installation) ? scripts.installation : {}
  // Normalize CRLF — exported scripts often carry \r\n, which breaks shells.
  const script = typeof installation.script === 'string' ? installation.script.replace(/\r\n/g, '\n') : ''
  if (script.trim().length === 0) return []
  let image = typeof installation.container === 'string' ? installation.container.trim() : ''
  if (!image) {
    warnings.push(`egg does not name an install container image — using ${FALLBACK_INSTALL_IMAGE}`)
    image = FALLBACK_INSTALL_IMAGE
  } else if (!isValidImageRef(image)) {
    warnings.push(`install container image ${JSON.stringify(image)} is invalid — using ${FALLBACK_INSTALL_IMAGE}`)
    image = FALLBACK_INSTALL_IMAGE
  }
  const entrypoint = typeof installation.entrypoint === 'string' && installation.entrypoint.trim().length > 0
    ? installation.entrypoint.trim()
    : 'bash'
  return [{ type: 'docker-script', image, script, entrypoint }]
}

/**
 * Convert a Pterodactyl egg export (parsed JSON) into a Between blueprint.
 * Throws for input that is not an egg; returns warnings for lossy mappings.
 */
export function convertEgg(egg: unknown): { blueprint: Blueprint; warnings: string[] } {
  if (!isRecord(egg)) throw new Error('not a Pterodactyl egg export (expected a JSON object)')
  if (typeof egg.name !== 'string' || egg.name.trim().length === 0)
    throw new Error('not a Pterodactyl egg export (missing "name")')
  if (typeof egg.startup !== 'string' || egg.startup.trim().length === 0)
    throw new Error('not a Pterodactyl egg export (missing "startup" command)')

  const warnings: string[] = []
  const meta = isRecord(egg.meta) ? egg.meta : {}
  const metaVersion = typeof meta.version === 'string' ? meta.version : ''
  if (metaVersion && metaVersion !== 'PTDL_v1' && metaVersion !== 'PTDL_v2')
    warnings.push(`unknown egg export version ${metaVersion} — importing anyway`)

  const state: ConversionState = { variables: [], keys: new Set(), renames: new Map(), warnings }
  convertVariables(egg, state)

  // --- Startup command -------------------------------------------------------
  let startup = egg.startup.trim()
  startup = startup.replace(/\{\{\s*P_SERVER_UUID\s*\}\}/g, '{{SERVER_ID}}')
  if (/\{\{\s*P_SERVER_LOCATION\s*\}\}/.test(startup)) {
    startup = startup.replace(/\{\{\s*P_SERVER_LOCATION\s*\}\}/g, '')
    warnings.push('{{P_SERVER_LOCATION}} has no Between equivalent — replaced with an empty string')
  }
  for (const [from, to] of state.renames) startup = renameRefs(startup, from, to)

  // --- Stop strategy -----------------------------------------------------------
  const config = parseEmbedded(egg.config, 'config', warnings) ?? {}
  const stopRaw = typeof config.stop === 'string' ? config.stop.trim() : ''
  let stop: StopStrategy
  if (stopRaw === '^C' || stopRaw === '^^C') {
    stop = { type: 'signal', signal: 'SIGINT' }
  } else if (stopRaw.length > 0) {
    let command = stopRaw
    for (const [from, to] of state.renames) command = renameRefs(command, from, to)
    stop = { type: 'command', command }
  } else {
    stop = { type: 'signal', signal: 'SIGTERM' }
    warnings.push('egg defines no stop command — defaulting to SIGTERM')
  }

  // --- Ptero built-in placeholders + undeclared startup variables ---------------
  const referenced = new Set<string>()
  const scanned = stop.type === 'command' ? `${startup}\n${stop.command}` : startup
  for (const match of scanned.matchAll(TEMPLATE_RE)) referenced.add(match[1])

  if (referenced.has('SERVER_MEMORY')) ensureServerMemory(state)
  if (referenced.has('SERVER_PORT') && !state.keys.has('SERVER_PORT'))
    autoAddVariable(state, { key: 'SERVER_PORT', label: 'Server port', type: 'number', default: 25565, min: 1024, max: 65535, isPort: true })
  if (referenced.has('SERVER_IP') && !state.keys.has('SERVER_IP'))
    autoAddVariable(state, { key: 'SERVER_IP', label: 'Bind address', type: 'string', default: '0.0.0.0', advanced: true })
  if (referenced.has('TZ') && !state.keys.has('TZ'))
    autoAddVariable(state, { key: 'TZ', label: 'Timezone', type: 'string', default: 'UTC', advanced: true })
  for (const name of referenced) {
    if (state.keys.has(name) || BUILTIN_VARS.has(name)) continue
    let key = sanitizeVarKey(name)
    key = uniqueKey(key, state.keys)
    if (key !== name) {
      startup = renameRefs(startup, name, key)
      if (stop.type === 'command') stop.command = renameRefs(stop.command, name, key)
    }
    autoAddVariable(state, { key, label: name, type: 'string', default: '' })
    warnings.push(`startup references undeclared variable {{${name}}} — added as a string variable with an empty default`)
  }

  // --- Ready marker(s) → readyRegex ----------------------------------------------
  // The regex is matched against every console line — keep it bounded so a
  // hostile egg cannot generate a megabyte-sized pattern.
  let readyRegex: string | undefined
  const startupCfg = parseEmbedded(config.startup, 'config.startup', warnings)
  const done = startupCfg?.done
  const allMarkers = (typeof done === 'string' ? [done] : Array.isArray(done) ? done : [])
    .filter((m): m is string => typeof m === 'string' && m.length > 0)
  const markers = allMarkers.filter((m) => m.length <= 200).slice(0, 8)
  if (markers.length < allMarkers.length)
    warnings.push('some ready markers were dropped (longer than 200 chars or more than 8) — ready detection uses the rest')
  if (markers.length > 0) readyRegex = markers.map(escapeRegex).join('|')

  // --- Assemble --------------------------------------------------------------------
  const configFiles = convertConfigFiles(config.files, state)
  const images = collectDockerImages(egg, warnings)
  const install = convertInstallScript(egg, warnings)
  const portVar = state.variables.find((v) => v.isPort)
  const author = typeof egg.author === 'string' && egg.author.trim().length > 0 ? egg.author.trim() : ''

  const blueprint: Blueprint = {
    id: `${slugify(egg.name)}-egg-${crypto.randomUUID().slice(0, 4)}`,
    name: egg.name.trim(),
    category: 'custom',
    description: typeof egg.description === 'string' ? egg.description.trim() : '',
    platforms: ['linux'],
    install,
    startCommand: startup,
    stop,
    variables: state.variables,
    notes: `Imported from a Pterodactyl egg${author ? ` by ${author}` : ''}.`,
  }
  if (portVar) blueprint.ports = [{ name: 'game', variable: portVar.key, protocol: 'both' }]
  if (images.length > 0) blueprint.docker = { image: images[0].image, ...(images.length > 1 ? { images } : {}) }
  if (configFiles.length > 0) blueprint.configFiles = configFiles
  if (readyRegex) blueprint.readyRegex = readyRegex

  return { blueprint, warnings }
}
