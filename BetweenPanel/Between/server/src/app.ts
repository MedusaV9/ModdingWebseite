import express from 'express'
import http from 'node:http'
import path from 'node:path'
import fs from 'node:fs'
import { Store } from './lib/jsonstore.ts'
import { loadConfig, NODE_TOKEN_MIN_LENGTH, PANEL_VERSION, type PanelConfig } from './config.ts'
import { AuthService, makeAuthMiddleware, requireAuth } from './auth/service.ts'
import { AuditService } from './services/audit.ts'
import { BlueprintRegistry } from './blueprints/registry.ts'
import { SteamCmdManager } from './steam/steamcmd.ts'
import { SteamLoginService } from './steam/login.ts'
import { DockerService } from './services/docker.ts'
import { FileAccessService } from './services/fileaccess.ts'
import { ServerManager } from './servers/manager.ts'
import { BackupService } from './services/backups.ts'
import { ScheduleService } from './services/schedules.ts'
import { MetricsService } from './services/metrics.ts'
import { Notifier } from './services/notify.ts'
import { WsHub } from './ws/hub.ts'
import { ShellHub, SHELL_PATH_RE } from './ws/shell.ts'
import type { AppContext } from './context.ts'
import { currentSettings } from './context.ts'
import type { Blueprint, PanelSettings } from './types.ts'
import { authRouter } from './api/auth.ts'
import { usersRouter } from './api/users.ts'
import { serversRouter, serializeServer } from './api/servers.ts'
import { filesRouter } from './api/files.ts'
import { backupsRouter } from './api/backups.ts'
import { schedulesRouter } from './api/schedules.ts'
import { modsRouter } from './api/mods.ts'
import { miscRouter } from './api/misc.ts'
import { nodesRouter } from './api/nodes.ts'
import { errorMiddleware } from './api/helpers.ts'
import { NodeService } from './nodes/service.ts'
import { ServerGateway } from './nodes/gateway.ts'
import { NodeStreamBridge } from './nodes/bridge.ts'
import { makeNodeAuthMiddleware } from './nodes/token.ts'

export interface BetweenApp {
  ctx: AppContext
  server: http.Server
  start: () => Promise<{ port: number }>
  stop: () => Promise<void>
}

export function createApp(overrides: Partial<PanelConfig> = {}): BetweenApp {
  const config = { ...loadConfig(), ...overrides }
  const isNode = config.mode === 'node'
  if (isNode && (!config.nodeToken || config.nodeToken.length < NODE_TOKEN_MIN_LENGTH)) {
    throw new Error(`BETWEEN_MODE=node requires BETWEEN_NODE_TOKEN with at least ${NODE_TOKEN_MIN_LENGTH} characters`)
  }
  fs.mkdirSync(config.dataDir, { recursive: true })
  fs.mkdirSync(path.join(config.dataDir, 'tmp'), { recursive: true })

  const store = new Store(path.join(config.dataDir, 'db'))
  const settings = store.collection<PanelSettings>('settings')
  const auth = new AuthService(store, config.sessionTtlDays)
  const audit = new AuditService(store)
  const registry = new BlueprintRegistry(store.collection<Blueprint & { id: string }>('custom_blueprints'), path.join(config.dataDir, 'templates'))
  if (registry.lastTemplateScan && registry.lastTemplateScan.loaded.length > 0)
    console.log(`[boot] loaded ${registry.lastTemplateScan.loaded.length} template file(s) from ${registry.lastTemplateScan.dir}`)
  const steam = new SteamCmdManager(path.join(config.dataDir, 'steamcmd'), config.steamcmdBin)
  const steamLogin = new SteamLoginService(steam, settings)
  const docker = new DockerService()
  const notifier = new Notifier(settings)
  const fileAccess = new FileAccessService(settings)

  // Hub and schedule service are created after the manager; hooks close over these refs.
  let hub: WsHub
  let schedules: ScheduleService

  const manager = new ServerManager(store, registry, steam, config.dataDir, {
    onStatus: (server, status, prev) => {
      hub?.broadcast('servers', { t: 'status', serverId: server.id, status, prev }, server.id)
      // Event triggers (server.running/offline/crashed) — local servers only
      // by construction: remote mirrors never flow through the manager hooks.
      schedules?.handleStatusChange(server.id, status, prev)
      if (status === 'crashed') {
        audit.log(null, 'server.crashed', { target: server.name, serverId: server.id })
        notifier.notify('crash', 'Server crashed', `**${server.name}** crashed and may auto-restart.`, {
          server: { id: server.id, name: server.name, blueprintId: server.blueprintId },
        })
        hub?.broadcast('servers', { t: 'event', kind: 'crash', serverId: server.id, name: server.name, message: `${server.name} crashed` }, server.id)
      }
    },
    onConsole: (serverId, line) => {
      // Re-validate server.console per message so revoking console access drops
      // an already-subscribed socket instead of streaming until it reconnects.
      hub?.broadcast(`console:${serverId}`, { t: 'console', serverId, line }, serverId, 'server.console')
    },
    onResources: (serverId, snap) => {
      hub?.broadcast('servers', { t: 'stats', serverId, snap }, serverId)
    },
    onQuery: (serverId, result) => {
      hub?.broadcast('servers', { t: 'query', serverId, query: result }, serverId)
      // Player join/leave detection for event triggers (poll-diff based).
      schedules?.handleQueryResult(serverId, result)
    },
    onRemoved: (server) => {
      // Pass the full object: the server is already gone from the store, so an
      // id-based visibility lookup would drop the event for every client.
      hub?.broadcast('servers', { t: 'deleted', serverId: server.id }, server)
    },
  }, docker)
  // Login-required steamcmd installs resolve the panel Steam account through
  // this hook — a provider, so the manager never touches credentials.
  manager.steamAuth = () => steamLogin.installAuth()

  // Remote nodes: registry/poller + WS bridge (both inert in node-agent mode
  // — an agent never has downstream nodes of its own).
  const nodes = new NodeService(store, config.nodePollMs)
  let bridge: NodeStreamBridge
  hub = new WsHub(auth, manager, {
    nodeToken: isNode ? config.nodeToken : null,
    remoteLookup: isNode ? undefined : (id) => nodes.mirror(id),
    onSubscribe: isNode ? undefined : (channel) => bridge?.onPanelSubscribe(channel),
    onClientConnected: isNode ? undefined : () => bridge?.sync(),
  })
  bridge = new NodeStreamBridge(nodes, hub)
  nodes.onChanged = () => bridge.sync()
  const gateway = new ServerGateway(manager, nodes)

  const shell = new ShellHub(auth, manager, docker)
  audit.onEntry = (entry) => hub?.broadcast('audit', { t: 'audit', entry })

  const backups = new BackupService(store, manager, config.dataDir, settings, audit)
  schedules = new ScheduleService(store, manager, backups, notifier, isNode ? config.nodeName : null)
  const metrics = new MetricsService(config.dataDir)
  metrics.onSample((snap) => hub.broadcast('system', { t: 'metrics', snap }))

  const ctx: AppContext = { config, store, auth, manager, backups, schedules, metrics, audit, notifier, registry, steam, steamLogin, docker, fileAccess, hub, settings, nodes, gateway }
  currentSettings(ctx) // ensure defaults exist
  // Warm the docker availability cache (sync callers read lastInfo).
  void docker.info().then((info) => {
    if (info.available) console.log(`[boot] docker daemon detected (${info.version})`)
  })

  // Seed admin for automated environments (panel only — agents have no users)
  const seedUser = process.env.BETWEEN_SEED_ADMIN_USER
  const seedPass = process.env.BETWEEN_SEED_ADMIN_PASS
  if (!isNode && seedUser && seedPass && auth.setupRequired()) {
    const { user, problems } = auth.createUser(seedUser, seedPass, 'admin')
    if (user) console.log(`[boot] seeded admin user "${seedUser}"`)
    else console.error(`[boot] failed to seed admin: ${problems.join('; ')}`)
  }

  const app = express()
  app.disable('x-powered-by')
  // Default 'loopback': trust X-Forwarded-For only from a local reverse proxy so
  // a direct client can't spoof req.ip to defeat login rate limiting.
  app.set('trust proxy', config.trustProxy)
  app.use(express.json({ limit: '12mb' }))
  // Node-agent mode swaps cookie/session auth for the constant-time bearer
  // token check — same REST surface, admin-equivalent when the token matches.
  app.use(isNode ? makeNodeAuthMiddleware(config.nodeToken!) : makeAuthMiddleware(auth))

  if (isNode) {
    // Unauthenticated root identity so humans/load balancers can tell what
    // this is; everything real stays behind the token.
    app.get('/', (_req, res) => res.json({ between: 'node', name: config.nodeName, version: PANEL_VERSION }))
    app.get('/api/node/identity', requireAuth, (_req, res) => {
      res.json({ between: 'node', name: config.nodeName, version: PANEL_VERSION, platform: process.platform, arch: process.arch })
    })
  } else {
    // No users/sessions/setup wizard on agents — these routers only exist on the panel.
    app.use('/api', authRouter(ctx))
    app.use('/api', usersRouter(ctx))
    app.use('/api', nodesRouter(ctx))
  }
  app.use('/api', serversRouter(ctx))
  app.use('/api', filesRouter(ctx))
  app.use('/api', backupsRouter(ctx))
  app.use('/api', schedulesRouter(ctx))
  app.use('/api', modsRouter(ctx))
  app.use('/api', miscRouter(ctx))
  app.use('/api', (_req, res) => res.status(404).json({ error: 'unknown API route' }))
  app.use(errorMiddleware)

  // Production: serve the built web UI with SPA fallback (panel only — agents are headless)
  if (!isNode && fs.existsSync(config.webDistDir)) {
    app.use(express.static(config.webDistDir, { index: 'index.html', maxAge: '1h' }))
    app.get(/^\/(?!api\/).*/, (_req, res) => {
      res.sendFile(path.join(config.webDistDir, 'index.html'))
    })
  }

  const server = http.createServer(app)
  server.on('upgrade', (req, socket, head) => {
    // Unlike HTTP routes there is no Express error boundary here — any throw
    // would crash the whole process, so guard the upgrade path explicitly.
    try {
      if (SHELL_PATH_RE.test((req.url ?? '').split('?')[0])) shell.handleUpgrade(req, socket, head)
      else if (req.url?.startsWith('/api/ws')) hub.handleUpgrade(req, socket, head)
      else socket.destroy()
    } catch (err) {
      console.error('[ws] upgrade failed:', err)
      socket.destroy()
    }
  })

  let started = false
  return {
    ctx,
    server,
    start: () =>
      new Promise((resolve, reject) => {
        server.once('error', reject)
        server.listen(config.port, config.host, () => {
          started = true
          manager.boot()
          schedules.start()
          metrics.start()
          if (!isNode) {
            nodes.start()
            bridge.start()
          }
          const addr = server.address()
          resolve({ port: typeof addr === 'object' && addr ? addr.port : config.port })
        })
      }),
    stop: async () => {
      if (!started) return
      started = false
      const schedulesStopped = schedules.stop()
      const nodesStopped = nodes.stop()
      bridge.stop()
      metrics.stop()
      notifier.stop()
      await fileAccess.stop()
      hub.close()
      shell.close()
      await manager.shutdownAll()
      await schedulesStopped
      await nodesStopped
      store.flushAll()
      await new Promise<void>((resolve) => server.close(() => resolve()))
    },
  }
}

export { serializeServer }
