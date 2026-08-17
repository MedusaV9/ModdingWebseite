import type { Doc } from './lib/jsonstore.ts'

// ---------------------------------------------------------------------------
// Users / auth
// ---------------------------------------------------------------------------
export type GlobalRole = 'admin' | 'user'

export interface User extends Doc {
  username: string
  passwordHash: string
  role: GlobalRole
  createdAt: string
  totpSecret?: string | null
  totpEnabled?: boolean
  /** sha256 hashes of unused one-time recovery codes. */
  recoveryCodes?: string[]
  /** UI preferences persisted per user. */
  prefs?: { theme?: string; language?: string; accent?: string }
  suspended?: boolean
}

export interface Session extends Doc {
  token: string
  userId: string
  createdAt: string
  expiresAt: string
  ip?: string
  userAgent?: string
}

export interface ApiKey extends Doc {
  userId: string
  name: string
  /** sha256 of the actual key; the key itself is shown only once. */
  keyHash: string
  prefix: string
  scopes: string[]
  createdAt: string
  lastUsedAt?: string | null
}

export interface AuditEntry extends Doc {
  ts: string
  userId: string | null
  username: string
  ip?: string
  action: string
  target?: string
  serverId?: string | null
  meta?: Record<string, unknown>
}

// ---------------------------------------------------------------------------
// Blueprints (game templates)
// ---------------------------------------------------------------------------
export type Platform = 'linux' | 'win32' | 'darwin'

export type InstallStep =
  | {
      type: 'steamcmd'
      appId: number | string
      betaBranch?: string
      validate?: boolean
      platformOverride?: 'windows' | 'linux'
      /** This app cannot be downloaded anonymously — install with the panel Steam account. */
      requiresLogin?: boolean
    }
  | { type: 'download'; url: string; target: string; extract?: boolean; sha256?: string }
  | { type: 'paper'; project?: 'paper' | 'velocity' | 'waterfall' | 'folia'; versionVar?: string; target?: string }
  | { type: 'vanilla-minecraft'; versionVar?: string; target?: string }
  | { type: 'fabric'; versionVar?: string; target?: string }
  | { type: 'writeFile'; path: string; content: string }
  | { type: 'command'; command: string }
  | { type: 'mkdir'; path: string }
  | { type: 'docker-script'; image: string; script: string; entrypoint?: string }

export type VariableType = 'string' | 'number' | 'boolean' | 'enum' | 'password'

export interface BlueprintVariable {
  key: string
  label: string
  description?: string
  type: VariableType
  default: string | number | boolean
  options?: { value: string; label: string }[]
  min?: number
  max?: number
  required?: boolean
  /** Regex the value must match (strings only). */
  pattern?: string
  /** If true this variable is a port and participates in conflict checks. */
  isPort?: boolean
  /** Show in the "advanced" section of the UI. */
  advanced?: boolean
}

export type StopStrategy =
  | { type: 'command'; command: string; timeoutS?: number }
  | { type: 'signal'; signal: 'SIGINT' | 'SIGTERM'; timeoutS?: number }
  | { type: 'rcon'; command: string; timeoutS?: number }

export interface ConfigFileSpec {
  path: string
  format: 'properties' | 'ini' | 'json' | 'keyvalue' | 'yaml' | 'toml' | 'raw'
  /** Map of blueprint variable key -> config key path (dot notation for json). */
  mappings?: Record<string, string>
  /** Render the whole file from this template on every variable save. */
  template?: string
}

/** Docker runtime hints shipped with a blueprint. */
export interface BlueprintDocker {
  /** Default image when a server picks the docker runtime. */
  image: string
  /** Alternative images the UI offers (e.g. different Java versions). */
  images?: { label: string; image: string }[]
}

export interface Blueprint {
  id: string
  name: string
  category: string
  description: string
  icon?: string
  color?: string
  platforms: Platform[]
  install: InstallStep[]
  startCommand: string
  stop: StopStrategy
  variables: BlueprintVariable[]
  /** Optional docker runtime defaults; any blueprint can still run in docker with a custom image. */
  docker?: BlueprintDocker
  /** Named ports; values are variable keys holding the port number. */
  ports?: { name: string; variable: string; protocol: 'tcp' | 'udp' | 'both' }[]
  query?: { type: 'minecraft' | 'source' | 'none'; portVariable?: string }
  /** Source RCON endpoint; commands/stops can be sent via RCON for games that ignore stdin. */
  rcon?: { portVariable: string; passwordVariable: string }
  /** Mod/plugin support: where addons install to and which Modrinth loader applies. */
  mods?: { platform: 'modrinth'; loader: 'paper' | 'fabric' | 'velocity'; dir: string; versionVariable?: string }
  /** Per-player console actions; {{PLAYER}} is replaced with the player name. */
  playerActions?: { key: string; label: string; command: string; confirm?: boolean }[]
  configFiles?: ConfigFileSpec[]
  /** Console line regex that marks the server as fully online. */
  readyRegex?: string
  /** Additional patterns excluded from backups by default. */
  backupExcludes?: string[]
  notes?: string
  /** Custom (user-created) blueprints are stored in the DB, builtin ones ship with the panel. */
  custom?: boolean
  /**
   * Set on blueprints loaded from a template file in data/templates (the
   * AMP-Generic-style drop-in directory); value is the source filename.
   * File templates are read-only in the API — edit the file and rescan.
   */
  templateFile?: string
  version?: string
}

// ---------------------------------------------------------------------------
// Game servers
// ---------------------------------------------------------------------------
export type ServerStatus =
  | 'offline'
  | 'installing'
  | 'install_failed'
  | 'starting'
  | 'running'
  | 'stopping'
  | 'crashed'
  | 'updating'
  /**
   * Panel-side only: a server mirrored from a remote node whose node is
   * currently unreachable. Never produced by a local ServerInstance. The web
   * StatusPill tolerates unknown statuses (falls back to offline styling), so
   * this is safe to expose before the frontend learns the new label.
   */
  | 'node-offline'

export interface RestartPolicy {
  enabled: boolean
  maxRetries: number
  backoffS: number
}

export type ServerRuntime = 'process' | 'docker'

/** Per-server docker settings (only meaningful when runtime === 'docker'). */
export interface ServerDockerSettings {
  /** Image override; falls back to the blueprint default image. */
  image?: string | null
  /** Hard container memory limit in MiB (null = unlimited). */
  memoryMb?: number | null
  /** CPU limit in cores, e.g. 1.5 (null = unlimited). */
  cpus?: number | null
  /** bridge (published ports, default) or host networking. */
  networkMode?: 'bridge' | 'host'
}

export interface GameServer extends Doc {
  name: string
  blueprintId: string
  ownerId: string
  createdAt: string
  /** Directory name below data/servers (not the absolute path). */
  dirName: string
  variables: Record<string, string | number | boolean>
  tags: string[]
  notes?: string
  autoStart: boolean
  restartPolicy: RestartPolicy
  /** Optional override of the blueprint start command. */
  startCommandOverride?: string | null
  /** Run the SteamCMD app update before every start. */
  steamAutoUpdate?: boolean
  /**
   * Install/update via `+login <panel Steam account>` even when the blueprint
   * does not require it (for games that need ownership only for some content).
   */
  useSteamLogin?: boolean
  /** How the server runs: host process (default) or docker container. */
  runtime?: ServerRuntime
  docker?: ServerDockerSettings
  installed: boolean
  installedAt?: string | null
  /** Soft memory display limit (MiB), used for gauges. */
  memoryLimitMb?: number | null
  /** Keep only the last N *unlocked* backups (0 = unlimited, null/absent = panel default). */
  backupRetention?: number | null
  suspended?: boolean
  /**
   * Remote node this server lives on. null/absent = local (exactly today's
   * behavior). On the panel, records with a nodeId are lightweight mirrors in
   * the `remote_servers` collection — the AGENT owns the authoritative record
   * and the files; the mirror only carries what panel-side permission checks
   * and offline listings need.
   */
  nodeId?: string | null
}

// ---------------------------------------------------------------------------
// Remote nodes (panel side)
// ---------------------------------------------------------------------------
/**
 * A registered remote node (a Between instance running with
 * BETWEEN_MODE=node). The token is a shared secret: it is stored server-side
 * only and MUST never be serialized into API responses (see api/nodes.ts).
 */
export interface PanelNode extends Doc {
  name: string
  baseUrl: string
  token: string
  createdAt: string
}

/** Cached health of a node, refreshed by the NodeService poll loop. */
export interface NodeHealth {
  online: boolean
  /** ISO timestamp of the last successful poll (null = never seen). */
  lastSeen: string | null
  latencyMs: number | null
  cpuPct: number | null
  memUsedBytes: number | null
  memTotalBytes: number | null
  diskUsedBytes: number | null
  diskTotalBytes: number | null
  version: string | null
  error: string | null
}

export interface Subuser extends Doc {
  serverId: string
  userId: string
  permissions: string[]
  createdAt: string
}

export interface Backup extends Doc {
  serverId: string
  fileName: string
  note: string
  sizeBytes: number
  createdAt: string
  locked: boolean
  auto: boolean
}

export type ScheduleTask =
  | { type: 'power'; action: 'start' | 'stop' | 'restart' | 'kill' }
  | { type: 'command'; command: string }
  | { type: 'backup'; note?: string }
  | { type: 'wait'; seconds: number }

/** Server-side events a schedule can react to (see ScheduleService for the detection sources). */
export type ScheduleEventName = 'server.running' | 'server.offline' | 'server.crashed' | 'player.joined' | 'player.left'

export type ScheduleTrigger = { type: 'cron'; expr: string } | { type: 'event'; event: ScheduleEventName }

export interface ScheduleRun {
  ts: string
  ok: boolean
  message: string
  /** What started this run: 'cron' | 'manual' | 'event:<name>'. Absent on pre-trigger records. */
  source?: string
}

export interface Schedule extends Doc {
  serverId: string
  name: string
  /** Legacy cron field (kept for stored documents and the plain-cron API payload); '' for event triggers. */
  cron: string
  /** Trigger union; documents created before event triggers existed lack it (= cron). */
  trigger?: ScheduleTrigger
  enabled: boolean
  onlyIfRunning: boolean
  tasks: ScheduleTask[]
  lastRuns: ScheduleRun[]
  createdAt: string
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------
export interface PanelSettings extends Doc {
  panelName: string
  defaultBackupRetention: number
  portRangeStart: number
  portRangeEnd: number
  discordWebhookUrl?: string | null
  discordEvents?: { crash: boolean; power: boolean; backup: boolean }
  /** Generic JSON webhook (n8n/Zapier/custom receivers) — see services/notify.ts. */
  webhookUrl?: string | null
  webhookEvents?: { crash: boolean; power: boolean; backup: boolean }
  defaultTheme?: string
  /**
   * Panel Steam account NAME for authenticated SteamCMD installs. Only the
   * name is stored — the password is never persisted (see steam/login.ts:
   * one interactive login, SteamCMD caches the session on disk afterwards).
   */
  steamUser?: string | null
}

// ---------------------------------------------------------------------------
// Runtime (non-persisted) views
// ---------------------------------------------------------------------------
export interface ConsoleLine {
  ts: number
  stream: 'stdout' | 'stderr' | 'system' | 'input' | 'install'
  line: string
  /** Monotonic per-instance id — stable React keys + reconnect dedupe. */
  seq?: number
}

export interface QueryResult {
  online: boolean
  playersOnline?: number
  playersMax?: number
  /** Online player sample (may be partial — MC samples, A2S caps at the packet size). */
  players?: { name: string; score?: number; durationS?: number }[]
  version?: string
  motd?: string
  latencyMs?: number
  ts: number
}

export interface ResourceSnapshot {
  ts: number
  cpuPct: number
  memBytes: number
  processes: number
  uptimeS: number
}

export const SERVER_PERMISSIONS = [
  'server.view',
  'server.console',
  'server.command',
  'server.power',
  'server.files.read',
  'server.files.write',
  'server.backups',
  'server.schedules',
  'server.config',
  'server.users',
  'server.activity',
] as const

export type ServerPermission = (typeof SERVER_PERMISSIONS)[number]
