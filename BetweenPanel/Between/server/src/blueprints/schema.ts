/**
 * Hand-rolled blueprint validation (no external schema libs). Returns a list
 * of human-readable problems; empty list = valid.
 */
const ID_RE = /^[a-z0-9][a-z0-9-]{1,63}$/
const VAR_KEY_RE = /^[A-Z][A-Z0-9_]{0,63}$/
const ACTION_KEY_RE = /^[a-z0-9_-]{1,20}$/
const IMAGE_RE = /^[a-z0-9][a-z0-9._\-/:@]{0,254}$/i
const CATEGORIES = ['minecraft', 'steam', 'sandbox', 'survival', 'shooter', 'simulation', 'voice', 'custom', 'other']
const PLATFORMS = ['linux', 'win32', 'darwin']
const VAR_TYPES = ['string', 'number', 'boolean', 'enum', 'password']

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

function validateVariable(v: unknown, i: number, problems: string[]): void {
  if (!isRecord(v)) {
    problems.push(`variables[${i}]: not an object`)
    return
  }
  if (typeof v.key !== 'string' || !VAR_KEY_RE.test(v.key))
    problems.push(`variables[${i}]: key must match ${VAR_KEY_RE} (got ${JSON.stringify(v.key)})`)
  if (typeof v.label !== 'string' || v.label.length === 0) problems.push(`variables[${i}] (${v.key}): missing label`)
  if (!VAR_TYPES.includes(v.type as string)) problems.push(`variables[${i}] (${v.key}): invalid type ${JSON.stringify(v.type)}`)
  if (v.default === undefined) problems.push(`variables[${i}] (${v.key}): missing default`)
  if (v.type === 'enum') {
    if (!Array.isArray(v.options) || v.options.length === 0) {
      problems.push(`variables[${i}] (${v.key}): enum needs options`)
    } else if (!v.options.some((o) => isRecord(o) && o.value === v.default)) {
      problems.push(`variables[${i}] (${v.key}): default not in options`)
    }
  }
  if (v.type === 'number') {
    if (typeof v.default !== 'number') problems.push(`variables[${i}] (${v.key}): number default must be a number`)
    if (v.min !== undefined && typeof v.min !== 'number') problems.push(`variables[${i}] (${v.key}): min must be a number`)
    if (v.max !== undefined && typeof v.max !== 'number') problems.push(`variables[${i}] (${v.key}): max must be a number`)
  }
  if (v.type === 'boolean' && typeof v.default !== 'boolean')
    problems.push(`variables[${i}] (${v.key}): boolean default must be true/false`)
  if (v.isPort) {
    if (v.type !== 'number') problems.push(`variables[${i}] (${v.key}): isPort requires type number`)
  }
  if (v.pattern !== undefined) {
    try {
      new RegExp(v.pattern as string)
    } catch {
      problems.push(`variables[${i}] (${v.key}): invalid pattern regex`)
    }
  }
}

function validateInstallStep(s: unknown, i: number, problems: string[]): void {
  if (!isRecord(s)) {
    problems.push(`install[${i}]: not an object`)
    return
  }
  switch (s.type) {
    case 'steamcmd':
      if (!(typeof s.appId === 'number' || (typeof s.appId === 'string' && s.appId.length > 0)))
        problems.push(`install[${i}]: steamcmd needs appId`)
      if (s.requiresLogin !== undefined && typeof s.requiresLogin !== 'boolean')
        problems.push(`install[${i}]: steamcmd requiresLogin must be a boolean`)
      break
    case 'download':
      if (typeof s.url !== 'string' || !/^(https?:\/\/|\{\{)/.test(s.url as string))
        problems.push(`install[${i}]: download needs an http(s) url (template vars allowed)`)
      if (typeof s.target !== 'string' || (s.target as string).length === 0)
        problems.push(`install[${i}]: download needs target`)
      break
    case 'paper':
    case 'vanilla-minecraft':
    case 'fabric':
      break
    case 'writeFile':
      if (typeof s.path !== 'string' || (s.path as string).length === 0) problems.push(`install[${i}]: writeFile needs path`)
      if (typeof s.content !== 'string') problems.push(`install[${i}]: writeFile needs content`)
      break
    case 'command':
      if (typeof s.command !== 'string' || (s.command as string).length === 0)
        problems.push(`install[${i}]: command step needs command`)
      break
    case 'mkdir':
      if (typeof s.path !== 'string' || (s.path as string).length === 0) problems.push(`install[${i}]: mkdir needs path`)
      break
    case 'docker-script':
      if (typeof s.image !== 'string' || !IMAGE_RE.test(s.image))
        problems.push(`install[${i}]: docker-script needs a valid image reference`)
      if (typeof s.script !== 'string' || s.script.length === 0 || s.script.length > 64 * 1024)
        problems.push(`install[${i}]: docker-script needs a non-empty script (max 64 KiB)`)
      if (s.entrypoint !== undefined && (typeof s.entrypoint !== 'string' || s.entrypoint.length === 0 || s.entrypoint.length > 100))
        problems.push(`install[${i}]: docker-script entrypoint must be 1-100 characters`)
      break
    default:
      problems.push(`install[${i}]: unknown step type ${JSON.stringify(s.type)}`)
  }
}

export function validateBlueprint(bp: unknown): string[] {
  const problems: string[] = []
  if (!isRecord(bp)) return ['blueprint is not an object']

  if (typeof bp.id !== 'string' || !ID_RE.test(bp.id)) problems.push(`id must match ${ID_RE} (got ${JSON.stringify(bp.id)})`)
  if (typeof bp.name !== 'string' || bp.name.length === 0) problems.push('missing name')
  if (typeof bp.description !== 'string') problems.push('missing description')
  if (typeof bp.category !== 'string' || !CATEGORIES.includes(bp.category))
    problems.push(`category must be one of ${CATEGORIES.join(', ')}`)
  if (!Array.isArray(bp.platforms) || bp.platforms.length === 0 || !bp.platforms.every((p) => PLATFORMS.includes(p as string)))
    problems.push('platforms must be a non-empty array of linux|win32|darwin')
  if (typeof bp.startCommand !== 'string' || bp.startCommand.length === 0) problems.push('missing startCommand')

  if (!isRecord(bp.stop)) problems.push('missing stop strategy')
  else if (bp.stop.type === 'command') {
    if (typeof bp.stop.command !== 'string' || bp.stop.command.length === 0) problems.push('stop.command missing')
  } else if (bp.stop.type === 'signal') {
    if (bp.stop.signal !== 'SIGINT' && bp.stop.signal !== 'SIGTERM') problems.push('stop.signal must be SIGINT or SIGTERM')
  } else if (bp.stop.type === 'rcon') {
    if (typeof bp.stop.command !== 'string' || bp.stop.command.length === 0) problems.push('stop.command missing')
  } else {
    problems.push('stop.type must be command, signal or rcon')
  }

  if (!Array.isArray(bp.install)) problems.push('install must be an array')
  else bp.install.forEach((s, i) => validateInstallStep(s, i, problems))

  const varKeys = new Set<string>()
  if (!Array.isArray(bp.variables)) problems.push('variables must be an array')
  else {
    bp.variables.forEach((v, i) => validateVariable(v, i, problems))
    for (const v of bp.variables) {
      if (isRecord(v) && typeof v.key === 'string') {
        if (varKeys.has(v.key)) problems.push(`duplicate variable key ${v.key}`)
        varKeys.add(v.key)
      }
    }
  }

  if (bp.ports !== undefined) {
    if (!Array.isArray(bp.ports)) problems.push('ports must be an array')
    else {
      bp.ports.forEach((p, i) => {
        if (!isRecord(p) || typeof p.name !== 'string' || typeof p.variable !== 'string')
          problems.push(`ports[${i}]: needs name and variable`)
        else if (!varKeys.has(p.variable)) problems.push(`ports[${i}]: variable ${p.variable} not declared`)
        else if (!['tcp', 'udp', 'both'].includes(p.protocol as string)) problems.push(`ports[${i}]: bad protocol`)
      })
    }
  }

  if (bp.query !== undefined) {
    if (!isRecord(bp.query) || !['minecraft', 'source', 'none'].includes(bp.query.type as string))
      problems.push('query.type must be minecraft|source|none')
    else if (bp.query.type !== 'none') {
      if (typeof bp.query.portVariable !== 'string' || !varKeys.has(bp.query.portVariable))
        problems.push('query.portVariable must reference a declared variable')
    }
  }

  if (bp.rcon !== undefined) {
    if (!isRecord(bp.rcon)) problems.push('rcon must be an object')
    else {
      if (typeof bp.rcon.portVariable !== 'string' || !varKeys.has(bp.rcon.portVariable))
        problems.push('rcon.portVariable must reference a declared variable')
      if (typeof bp.rcon.passwordVariable !== 'string' || !varKeys.has(bp.rcon.passwordVariable))
        problems.push('rcon.passwordVariable must reference a declared variable')
    }
  }

  if (bp.mods !== undefined) {
    if (!isRecord(bp.mods)) problems.push('mods must be an object')
    else {
      if (bp.mods.platform !== 'modrinth') problems.push('mods.platform must be modrinth')
      if (!['paper', 'fabric', 'velocity'].includes(bp.mods.loader as string))
        problems.push('mods.loader must be paper, fabric or velocity')
      if (typeof bp.mods.dir !== 'string' || bp.mods.dir.length === 0) problems.push('mods.dir must be a non-empty path')
      else if (bp.mods.dir.startsWith('/') || bp.mods.dir.split(/[\\/]/).includes('..'))
        problems.push('mods.dir must be a relative path without ..')
      if (bp.mods.versionVariable !== undefined) {
        if (typeof bp.mods.versionVariable !== 'string' || !varKeys.has(bp.mods.versionVariable))
          problems.push('mods.versionVariable must reference a declared variable')
      }
    }
  }

  if (bp.playerActions !== undefined) {
    if (!Array.isArray(bp.playerActions)) problems.push('playerActions must be an array')
    else {
      if (bp.playerActions.length > 6) problems.push('playerActions: at most 6 actions allowed')
      bp.playerActions.forEach((a, i) => {
        if (!isRecord(a)) {
          problems.push(`playerActions[${i}]: not an object`)
          return
        }
        if (typeof a.key !== 'string' || !ACTION_KEY_RE.test(a.key))
          problems.push(`playerActions[${i}]: key must match ${ACTION_KEY_RE} (got ${JSON.stringify(a.key)})`)
        if (typeof a.label !== 'string' || a.label.length === 0 || a.label.length > 30)
          problems.push(`playerActions[${i}] (${a.key}): label must be 1-30 characters`)
        if (typeof a.command !== 'string' || a.command.length === 0 || a.command.length > 200)
          problems.push(`playerActions[${i}] (${a.key}): command must be 1-200 characters`)
        else if (!a.command.includes('{{PLAYER}}'))
          problems.push(`playerActions[${i}] (${a.key}): command must contain {{PLAYER}}`)
        if (a.confirm !== undefined && typeof a.confirm !== 'boolean')
          problems.push(`playerActions[${i}] (${a.key}): confirm must be a boolean`)
      })
    }
  }

  if (bp.configFiles !== undefined) {
    if (!Array.isArray(bp.configFiles)) problems.push('configFiles must be an array')
    else {
      bp.configFiles.forEach((cf, i) => {
        if (!isRecord(cf) || typeof cf.path !== 'string') problems.push(`configFiles[${i}]: needs path`)
        else if (!['properties', 'ini', 'json', 'keyvalue', 'yaml', 'toml', 'raw'].includes(cf.format as string))
          problems.push(`configFiles[${i}]: bad format`)
        if (isRecord(cf) && cf.mappings !== undefined && !isRecord(cf.mappings))
          problems.push(`configFiles[${i}]: mappings must be an object`)
      })
    }
  }

  if (bp.docker !== undefined) {
    if (!isRecord(bp.docker)) problems.push('docker must be an object')
    else {
      if (typeof bp.docker.image !== 'string' || !IMAGE_RE.test(bp.docker.image))
        problems.push('docker.image must be a valid image reference')
      if (bp.docker.images !== undefined) {
        if (!Array.isArray(bp.docker.images)) problems.push('docker.images must be an array')
        else {
          bp.docker.images.forEach((entry, i) => {
            if (!isRecord(entry) || typeof entry.label !== 'string' || entry.label.length === 0 || entry.label.length > 40)
              problems.push(`docker.images[${i}]: needs a label (1-40 chars)`)
            if (!isRecord(entry) || typeof entry.image !== 'string' || !IMAGE_RE.test(entry.image as string))
              problems.push(`docker.images[${i}]: invalid image reference`)
          })
        }
      }
    }
  }

  if (bp.readyRegex !== undefined) {
    try {
      new RegExp(bp.readyRegex as string)
    } catch {
      problems.push('readyRegex is not a valid regex')
    }
  }

  // Referenced template variables must exist (built-in vars are always available)
  const builtin = new Set(['SERVER_DIR', 'SERVER_NAME', 'SERVER_ID', 'STEAMCMD_DIR', 'PLATFORM'])
  const collectTemplates: string[] = typeof bp.startCommand === 'string' ? [bp.startCommand] : []
  if (Array.isArray(bp.install)) {
    for (const s of bp.install) {
      if (!isRecord(s)) continue
      // 'script' (docker-script) is deliberately not scanned: install scripts
      // are plain shell and must not be treated as blueprint templates.
      for (const field of ['url', 'target', 'path', 'content', 'command']) {
        if (typeof s[field] === 'string') collectTemplates.push(s[field] as string)
      }
    }
  }
  if (isRecord(bp.stop) && typeof bp.stop.command === 'string') collectTemplates.push(bp.stop.command)
  for (const template of collectTemplates) {
    for (const m of template.matchAll(/\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g)) {
      const key = m[1]
      if (!varKeys.has(key) && !builtin.has(key)) problems.push(`template references undeclared variable {{${key}}}`)
    }
  }

  return problems
}
