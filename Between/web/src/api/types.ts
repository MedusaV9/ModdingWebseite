// Mirrors of the server-side API shapes used by the web UI.

export type ServerStatus =
  | 'offline'
  | 'installing'
  | 'install_failed'
  | 'starting'
  | 'running'
  | 'stopping'
  | 'crashed'
  | 'updating'
  /** Mirrored server on a remote node that is currently unreachable. */
  | 'node-offline'

export interface SafeUser {
  id: string
  username: string
  role: 'admin' | 'user'
  createdAt: string
  totpEnabled: boolean
  prefs: { theme?: string; language?: string; accent?: string }
  suspended: boolean
}

export interface PanelMeta {
  panelName: string
  version: string
  setupRequired: boolean
  defaultTheme: string
}

export interface BlueprintVariable {
  key: string
  label: string
  description?: string
  type: 'string' | 'number' | 'boolean' | 'enum' | 'password'
  default: string | number | boolean
  options?: { value: string; label: string }[]
  min?: number
  max?: number
  required?: boolean
  pattern?: string
  isPort?: boolean
  advanced?: boolean
}

export interface Blueprint {
  id: string
  name: string
  category: string
  description: string
  icon?: string
  color?: string
  platforms: string[]
  variables: BlueprintVariable[]
  ports?: { name: string; variable: string; protocol: string }[]
  startCommand: string
  stop: { type: string; command?: string; signal?: string; timeoutS?: number }
  query?: { type: string; portVariable?: string }
  /** Per-player console actions; {{PLAYER}} in command is replaced with the player name. */
  playerActions?: { key: string; label: string; command: string; confirm?: boolean }[]
  configFiles?: { path: string; format: string; mappings?: Record<string, string> }[]
  notes?: string
  custom?: boolean
  install?: unknown[]
  /** Detail responses only: whether the install pipeline contains a steamcmd step. */
  hasSteamcmd?: boolean
  /** Detail responses only: a steamcmd step demands the panel Steam account (no anonymous download). */
  requiresSteamLogin?: boolean
  /** Docker runtime defaults (default image + curated alternatives). */
  docker?: { image: string; images?: { label: string; image: string }[] } | null
}

export type ServerRuntime = 'process' | 'docker'

export interface ServerDockerSettings {
  image?: string | null
  memoryMb?: number | null
  cpus?: number | null
  networkMode?: 'bridge' | 'host'
}

export interface DockerStatus {
  available: boolean
  version: string | null
  apiVersion: string | null
  socketPath: string
  error: string | null
}

export interface ResourceSnapshot {
  ts: number
  cpuPct: number
  memBytes: number
  processes: number
  uptimeS: number
}

export interface QueryResult {
  online: boolean
  playersOnline?: number
  playersMax?: number
  /** Online player sample (may be partial — MC samples, A2S caps at the packet size). Absent = unknown. */
  players?: { name: string; score?: number; durationS?: number }[]
  version?: string
  motd?: string
  latencyMs?: number
  ts: number
}

export interface ServerSummary {
  id: string
  name: string
  blueprintId: string
  blueprintName: string
  icon: string
  color: string
  ownerId: string
  createdAt: string
  tags: string[]
  autoStart: boolean
  installed: boolean
  suspended: boolean
  status: ServerStatus
  uptimeS: number
  ports: { name: string; port: number; protocol: string }[]
  resources: ResourceSnapshot | null
  query: QueryResult | null
  memoryLimitMb: number | null
  installError: string | null
  runtime: ServerRuntime
  /** Remote node this server lives on; null = this panel machine. */
  nodeId: string | null
  nodeName: string | null
  /** false only for remote servers whose node is currently unreachable. */
  nodeOnline: boolean
}

export interface ServerDetail extends ServerSummary {
  notes: string
  variables: Record<string, string | number | boolean>
  restartPolicy: { enabled: boolean; maxRetries: number; backoffS: number }
  startCommandOverride: string | null
  /** Keep only the last N unlocked backups (0 = unlimited, null = panel default). */
  backupRetention: number | null
  /** Run the SteamCMD app update before every panel-initiated start. */
  steamAutoUpdate?: boolean
  /** Install/update via the panel Steam account instead of anonymous SteamCMD login. */
  useSteamLogin?: boolean
  /** How console commands reach the game: 'rcon' when the game ignores stdin. */
  commandTransport: 'rcon' | 'stdin'
  docker: ServerDockerSettings | null
  /** Image the next docker start would use (server override or blueprint default). */
  dockerImageEffective: string | null
  blueprint: Blueprint | null
}

export interface ConsoleLine {
  ts: number
  stream: 'stdout' | 'stderr' | 'system' | 'input' | 'install'
  line: string
  /** Monotonic per-instance id — stable React keys + reconnect dedupe. */
  seq?: number
}

export interface FileEntry {
  name: string
  isDir: boolean
  size: number
  mtimeMs: number
  mode: string
}

export type ModLoader = 'paper' | 'fabric' | 'velocity'

export interface InstalledMod {
  fileName: string
  sizeBytes: number
  modifiedAt: string
}

/** GET /api/servers/:id/mods — loader/dir/mcVersion are absent when supported=false. */
export interface ModsOverview {
  supported: boolean
  loader?: ModLoader
  dir?: string
  mcVersion?: string
  installed: InstalledMod[]
}

export interface ModSearchHit {
  projectId: string
  slug: string
  title: string
  description: string
  downloads: number
  iconUrl: string | null
  projectType: string
}

/** GET /api/servers/:id/mods/search */
export interface ModSearchResult {
  loader: ModLoader
  mcVersion?: string
  hits: ModSearchHit[]
}

export interface ModVersionFile {
  url: string
  filename: string
  primary: boolean
  size: number
  sha512?: string
  sha1?: string
}

/** GET /api/servers/:id/mods/versions — newest compatible first. */
export interface ModVersion {
  id: string
  name: string
  versionNumber: string
  gameVersions: string[]
  loaders: string[]
  datePublished: string
  files: ModVersionFile[]
}

export interface BackupInfo {
  id: string
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

export type ScheduleEventName = 'server.running' | 'server.offline' | 'server.crashed' | 'player.joined' | 'player.left'

export type ScheduleTrigger = { type: 'cron'; expr: string } | { type: 'event'; event: ScheduleEventName }

export interface ScheduleInfo {
  id: string
  serverId: string
  name: string
  cron: string
  /** Absent on schedules created before event triggers existed (= cron). */
  trigger?: ScheduleTrigger
  enabled: boolean
  onlyIfRunning: boolean
  tasks: ScheduleTask[]
  lastRuns: { ts: string; ok: boolean; message: string; source?: string }[]
  createdAt: string
  nextRunAt: number | null
}

export interface SubuserInfo {
  id: string
  userId: string
  username: string
  permissions: string[]
  createdAt?: string
}

export interface AuditEntry {
  id: string
  ts: string
  userId: string | null
  username: string
  ip?: string
  action: string
  target?: string
  serverId?: string | null
  meta?: Record<string, unknown>
}

export interface HostSnapshot {
  ts: number
  cpuPct: number
  memUsedBytes: number
  memTotalBytes: number
  diskUsedBytes: number
  diskTotalBytes: number
  load1: number
  platform: string
}

export interface SystemInfo {
  platform: string
  release: string
  arch: string
  hostname: string
  cpus: number
  cpuModel: string
  nodeVersion: string
  panelVersion: string
  panelUptimeS: number
  dataDir: string
  serverCount: number
  runningCount: number
  metrics: HostSnapshot | null
}

export interface PanelSettings {
  id: string
  panelName: string
  defaultBackupRetention: number
  portRangeStart: number
  portRangeEnd: number
  discordWebhookUrl?: string | null
  discordEvents?: { crash: boolean; power: boolean; backup: boolean }
  webhookUrl?: string | null
  webhookEvents?: { crash: boolean; power: boolean; backup: boolean }
  defaultTheme?: string
  /** Panel Steam account NAME (the password is never stored server-side). */
  steamUser?: string | null
}

/** GET /api/steam/status — SteamCMD install state (all authenticated users). */
export interface SteamStatus {
  installed: boolean
  dir: string
  platform: string
  /** A panel Steam account is configured (name/session detail is admin-only). */
  loginConfigured: boolean
}

/** GET /api/steam/login (admin) — panel Steam account session state. */
export interface SteamLoginStatus {
  user: string | null
  loggedIn: boolean
}

export interface ApiKeyInfo {
  id: string
  name: string
  prefix: string
  scopes: string[]
  createdAt: string
  lastUsedAt?: string | null
}

export interface SessionInfo {
  id: string
  createdAt: string
  expiresAt: string
  ip?: string
  userAgent?: string
  current: boolean
}

// ---------------------------------------------------------------------------
// Remote nodes (multi-machine)
// ---------------------------------------------------------------------------
/** Cached health of a registered node, refreshed by the panel's poll loop. */
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

/** GET /api/nodes entry — the shared token is NEVER serialized back out. */
export interface NodeInfo {
  id: string
  name: string
  baseUrl: string
  createdAt: string
  serverCount: number
  health: NodeHealth
}

/** POST /api/nodes/:id/test — a reachable panel with a dead node is ok:false. */
export interface NodeTestResult {
  ok: boolean
  identity?: { name: string; version: string; platform: string; arch: string }
  latencyMs?: number
  error?: string
}
