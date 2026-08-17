import { Router } from 'express'
import fs from 'node:fs'
import type { AppContext } from '../context.ts'
import { requireAuth, type AuthedRequest } from '../auth/service.ts'
import { asyncHandler, HttpError, intQuery, makeServerAccess, type ServerRequest } from './helpers.ts'
import type { Blueprint, GameServer } from '../types.ts'
import { SERVER_PERMISSIONS } from '../types.ts'
import { dirSize } from '../services/files.ts'
import { applyConfigUpdates, getConfigValue, isStructuredFormat } from '../lib/configfiles.ts'
import { safeJoin } from '../lib/paths.ts'
import { substituteVars } from '../lib/util.ts'
import type { RemoteServerMirror } from '../nodes/service.ts'

export function serializeServer(ctx: AppContext, server: GameServer, detail = false) {
  const inst = ctx.manager.instances.get(server.id)
  const blueprint = ctx.registry.get(server.blueprintId)
  const latest = inst?.resources.last ?? null
  const base = {
    id: server.id,
    name: server.name,
    blueprintId: server.blueprintId,
    blueprintName: blueprint?.name ?? '(missing blueprint)',
    icon: blueprint?.icon ?? 'server',
    color: blueprint?.color ?? '#6366f1',
    ownerId: server.ownerId,
    createdAt: server.createdAt,
    tags: server.tags,
    autoStart: server.autoStart,
    installed: server.installed,
    suspended: Boolean(server.suspended),
    status: inst?.status ?? 'offline',
    uptimeS: inst?.uptimeS ?? 0,
    ports: inst?.ports ?? [],
    resources: latest,
    query: inst?.lastQuery ?? null,
    // A hard container limit doubles as the display limit for gauges.
    memoryLimitMb: (server.runtime === 'docker' ? server.docker?.memoryMb : null) ?? server.memoryLimitMb ?? null,
    installError: inst?.installError ?? null,
    runtime: server.runtime === 'docker' ? 'docker' : 'process',
    // Local servers carry the same node fields as mirrored remote ones so
    // list consumers see a uniform shape (null = this panel host).
    nodeId: null,
    nodeName: null,
    nodeOnline: true,
  }
  if (!detail) return base
  return {
    ...base,
    notes: server.notes ?? '',
    variables: server.variables,
    restartPolicy: server.restartPolicy,
    startCommandOverride: server.startCommandOverride ?? null,
    backupRetention: server.backupRetention ?? null,
    steamAutoUpdate: Boolean(server.steamAutoUpdate),
    useSteamLogin: Boolean(server.useSteamLogin),
    commandTransport: inst?.commandTransport ?? 'stdin',
    docker: server.docker ?? null,
    dockerImageEffective: inst?.dockerImage ?? null,
    blueprint: blueprint
      ? {
          id: blueprint.id,
          name: blueprint.name,
          category: blueprint.category,
          description: blueprint.description,
          // Needed by the Settings runtime card (docker requires Linux support).
          platforms: blueprint.platforms,
          variables: blueprint.variables,
          ports: blueprint.ports ?? [],
          startCommand: blueprint.startCommand,
          stop: blueprint.stop,
          query: blueprint.query ?? { type: 'none' },
          playerActions: blueprint.playerActions ?? [],
          configFiles: blueprint.configFiles ?? [],
          notes: blueprint.notes ?? '',
          hasSteamcmd: blueprint.install.some((s) => s.type === 'steamcmd'),
          requiresSteamLogin: blueprint.install.some((s) => s.type === 'steamcmd' && s.requiresLogin === true),
          docker: blueprint.docker ?? null,
        }
      : null,
  }
}

export function serversRouter(ctx: AppContext): Router {
  const router = Router()
  const access = makeServerAccess(ctx.auth, ctx.manager, (id) => ctx.nodes.mirror(id))
  router.use(requireAuth)

  router.get('/servers', (req: AuthedRequest, res) => {
    // Local servers + mirrored remote ones, both filtered by the same
    // panel-side visibility rules. Remote entries come from the poll cache —
    // the list stays fast even when a node is slow or down.
    const visible = ctx.auth.visibleServers(req.user!, ctx.manager.servers.all())
    const remoteVisible = ctx.auth.visibleServers(req.user!, ctx.nodes.mirrors.all()) as RemoteServerMirror[]
    res.json({
      servers: [...visible.map((s) => serializeServer(ctx, s)), ...remoteVisible.map((m) => ctx.nodes.serializeRemote(m))],
    })
  })

  router.post(
    '/servers',
    asyncHandler(async (req: AuthedRequest, res) => {
      const { name, blueprintId, variables, autoStart, startAfterInstall, tags, runtime, docker, nodeId } = req.body ?? {}

      // Node-agent mode: the panel may EMBED the full blueprint JSON so its
      // custom blueprints work here without any catalog sync. Only honored in
      // node mode — on the panel, blueprint creation stays an admin-gated
      // separate endpoint (a blueprint defines arbitrary commands).
      if (ctx.config.mode === 'node' && req.body?.blueprint && typeof req.body.blueprint === 'object') {
        const embedded = req.body.blueprint as Blueprint
        if (embedded.id !== String(blueprintId ?? '')) throw new HttpError(400, 'embedded blueprint id does not match blueprintId')
        const { ok, problems } = ctx.registry.putReplica(embedded)
        if (!ok) throw new HttpError(400, `embedded blueprint rejected: ${problems.join('; ')}`)
      }

      // Panel: optional nodeId routes the create to a remote node. The agent
      // owns the record + files; the panel keeps a mirror owned by req.user.
      if (ctx.config.mode !== 'node' && typeof nodeId === 'string' && nodeId) {
        const node = ctx.nodes.get(nodeId)
        if (!node) throw new HttpError(400, 'unknown node — register it under Nodes first')
        if (!ctx.nodes.healthOf(node.id).online)
          throw new HttpError(502, `node "${node.name}" is currently unreachable — try again once it is back online`)
        const blueprint = ctx.registry.get(String(blueprintId ?? ''))
        if (!blueprint) throw new HttpError(400, `blueprint ${String(blueprintId ?? '')} not found`)
        const out = await ctx.gateway.callNode(node, ctx.nodes.clientFor(node), (client) =>
          client.createServer({
            name: String(name ?? ''),
            blueprintId: blueprint.id,
            variables: variables ?? {},
            autoStart: Boolean(autoStart),
            startAfterInstall: Boolean(startAfterInstall),
            tags: Array.isArray(tags) ? tags : [],
            runtime: typeof runtime === 'string' ? runtime : undefined,
            docker,
            blueprint,
          }),
        )
        ctx.nodes.adoptCreated(node.id, out.server, req.user!.id)
        ctx.audit.log(req, 'server.created', {
          target: out.server.name,
          serverId: out.server.id,
          meta: { blueprintId, runtime: out.server.runtime ?? 'process', nodeId: node.id },
        })
        res.status(201).json({ server: { ...out.server, ownerId: req.user!.id, nodeId: node.id, nodeName: node.name, nodeOnline: true } })
        return
      }

      const { server, problems } = await ctx.manager.create({
        name: String(name ?? ''),
        blueprintId: String(blueprintId ?? ''),
        ownerId: req.user!.id,
        variables: variables ?? {},
        autoStart: Boolean(autoStart),
        startAfterInstall: Boolean(startAfterInstall),
        tags: Array.isArray(tags) ? tags : [],
        runtime: typeof runtime === 'string' ? runtime : undefined,
        docker,
      })
      if (!server) throw new HttpError(400, problems.join('; '))
      ctx.audit.log(req, 'server.created', {
        target: server.name,
        serverId: server.id,
        meta: { blueprintId, runtime: server.runtime ?? 'process' },
      })
      res.status(201).json({ server: serializeServer(ctx, server, true) })
    }),
  )

  router.get(
    '/servers/:id',
    access('server.view'),
    asyncHandler(async (req: ServerRequest, res) => {
      const server = req.gameServer!
      if (ctx.gateway.isRemote(server)) {
        const mirror = server as RemoteServerMirror
        const node = ctx.nodes.get(mirror.nodeId)
        const myPermissions = ctx.auth.effectivePermissions(req.user!, server)
        if (node && ctx.nodes.healthOf(node.id).online) {
          const out = await ctx.gateway.proxy(server, (client) => client.getDetail(server.id))
          res.json({
            server: { ...out.server, ownerId: mirror.ownerId, nodeId: node.id, nodeName: node.name, nodeOnline: true },
            myPermissions,
          })
        } else {
          // Node down: serve the degraded mirror so the page still renders.
          res.json({ server: ctx.nodes.serializeRemote(mirror), myPermissions })
        }
        return
      }
      res.json({
        server: serializeServer(ctx, server, true),
        myPermissions: ctx.auth.effectivePermissions(req.user!, server),
      })
    }),
  )

  router.patch(
    '/servers/:id',
    access('server.config'),
    asyncHandler(async (req: ServerRequest, res) => {
      ctx.gateway.assertLocal(req.gameServer!, 'editing settings')
      // Switching to docker validates against the cached probe — refresh it
      // first so a freshly started daemon is picked up immediately.
      if (req.body?.runtime === 'docker' && ctx.manager.docker) await ctx.manager.docker.info()
      const updated = ctx.manager.updateServer(req.gameServer!.id, req.body ?? {})
      ctx.audit.log(req, 'server.updated', { target: updated.name, serverId: updated.id, meta: { keys: Object.keys(req.body ?? {}) } })
      res.json({ server: serializeServer(ctx, updated, true) })
    }),
  )

  router.delete(
    '/servers/:id',
    access('server.view'),
    asyncHandler(async (req: ServerRequest, res) => {
      const server = req.gameServer!
      if (req.user!.role !== 'admin' && server.ownerId !== req.user!.id)
        throw new HttpError(403, 'only the owner or an admin can delete a server')
      const keepFiles = Boolean(req.query.keepFiles === 'true' || req.body?.keepFiles)
      const deleteBackups = Boolean(req.body?.deleteBackups)
      if (ctx.gateway.isRemote(server)) {
        // The agent removes the record + files; the panel then drops its
        // mirror and panel-side attachments (subusers). A dead node → 502;
        // deregistering the node is the escape hatch for permanent losses.
        await ctx.gateway.proxy(server, (client) => client.deleteServer(server.id, { keepFiles, deleteBackups }))
        ctx.nodes.forgetServer(server.id)
        ctx.auth.subusers.removeWhere((s) => s.serverId === server.id)
        ctx.audit.log(req, 'server.deleted', { target: server.name, serverId: server.id, meta: { nodeId: server.nodeId } })
        ctx.hub.broadcast('servers', { t: 'deleted', serverId: server.id }, server)
        res.json({ ok: true })
        return
      }
      await ctx.manager.remove(server.id, keepFiles)
      ctx.schedules.removeAllForServer(server.id)
      ctx.auth.subusers.removeWhere((s) => s.serverId === server.id)
      if (deleteBackups) ctx.backups.removeAllForServer(server.id)
      ctx.audit.log(req, 'server.deleted', { target: server.name, serverId: server.id })
      res.json({ ok: true })
    }),
  )

  // --- Clone -----------------------------------------------------------------
  router.post(
    '/servers/:id/clone',
    access('server.view'),
    asyncHandler(async (req: ServerRequest, res) => {
      const source = req.gameServer!
      ctx.gateway.assertLocal(source, 'cloning')
      if (req.user!.role !== 'admin' && source.ownerId !== req.user!.id)
        throw new HttpError(403, 'only the owner or an admin can clone a server')
      const { name, copyFiles, variables } = req.body ?? {}
      const { server, problems } = ctx.manager.clone(source.id, String(name ?? ''), {
        copyFiles: copyFiles === undefined ? true : Boolean(copyFiles),
        variables: variables && typeof variables === 'object' ? (variables as Record<string, unknown>) : undefined,
      })
      if (!server) throw new HttpError(400, problems.join('; '))
      ctx.audit.log(req, 'server.cloned', { target: server.name, serverId: source.id, meta: { newServerId: server.id } })
      res.status(201).json({ server: serializeServer(ctx, server, true) })
    }),
  )

  // --- Power / console -----------------------------------------------------
  router.post(
    '/servers/:id/power',
    access('server.power'),
    asyncHandler(async (req: ServerRequest, res) => {
      const action = String(req.body?.action ?? '')
      if (!['start', 'stop', 'restart', 'kill'].includes(action)) throw new HttpError(400, 'invalid power action')
      const server = req.gameServer!
      let status: string
      if (ctx.gateway.isRemote(server)) {
        status = (await ctx.gateway.proxy(server, (client) => client.power(server.id, action))).status
      } else {
        await ctx.manager.power(server.id, action as 'start')
        status = ctx.manager.instance(server.id).status
      }
      ctx.audit.log(req, `server.power.${action}`, { target: server.name, serverId: server.id })
      ctx.notifier.notify('power', `Power: ${action}`, `**${server.name}** — ${action} by ${req.user!.username}`, {
        server: { id: server.id, name: server.name, blueprintId: server.blueprintId },
        data: { action, by: req.user!.username },
      })
      res.json({ ok: true, status })
    }),
  )

  router.post(
    '/servers/:id/command',
    access('server.command'),
    asyncHandler(async (req: ServerRequest, res) => {
      const command = String(req.body?.command ?? '').trim()
      if (!command) throw new HttpError(400, 'command required')
      if (command.length > 1000) throw new HttpError(400, 'command too long')
      const server = req.gameServer!
      if (ctx.gateway.isRemote(server)) {
        await ctx.gateway.proxy(server, (client) => client.sendCommand(server.id, command))
      } else {
        ctx.manager.sendCommand(server.id, command)
      }
      res.json({ ok: true })
    }),
  )

  router.get(
    '/servers/:id/console',
    access('server.console'),
    asyncHandler(async (req: ServerRequest, res) => {
      const server = req.gameServer!
      const limit = intQuery(req.query.limit, 500, 1, 2000)
      if (ctx.gateway.isRemote(server)) {
        res.json(await ctx.gateway.proxy(server, (client) => client.consoleLog(server.id, limit)))
        return
      }
      const inst = ctx.manager.instance(server.id)
      res.json({ lines: inst.consoleBuffer.slice(-limit), status: inst.status })
    }),
  )

  router.get(
    '/servers/:id/resources',
    access('server.view'),
    asyncHandler(async (req: ServerRequest, res) => {
      const server = req.gameServer!
      if (ctx.gateway.isRemote(server)) {
        // Forward ?limit as-is; the agent applies the same clamping locally.
        const rawLimit = Number(req.query.limit)
        res.json(
          await ctx.gateway.proxy(server, (client) =>
            client.resources(server.id, Number.isFinite(rawLimit) ? Math.trunc(rawLimit) : undefined),
          ),
        )
        return
      }
      const inst = ctx.manager.instance(server.id)
      // Full ring by default; ?limit=N trims the payload to the newest N samples
      // (the console sparklines only chart a short recent window).
      const limit = intQuery(req.query.limit, inst.resources.cap, 1, inst.resources.cap)
      res.json({ resources: inst.resources.last ?? null, history: inst.resources.toArray(limit), status: inst.status, uptimeS: inst.uptimeS })
    }),
  )

  router.get(
    '/servers/:id/size',
    access('server.view'),
    asyncHandler(async (req: ServerRequest, res) => {
      const server = req.gameServer!
      if (ctx.gateway.isRemote(server)) {
        res.json(await ctx.gateway.proxy(server, (client) => client.size(server.id)))
        return
      }
      const inst = ctx.manager.instance(server.id)
      res.json({ sizeBytes: dirSize(inst.serverDir) })
    }),
  )

  // --- Variables / install ----------------------------------------------------
  router.put('/servers/:id/variables', access('server.config'), (req: ServerRequest, res) => {
    ctx.gateway.assertLocal(req.gameServer!, 'editing variables')
    const { problems } = ctx.manager.setVariables(req.gameServer!.id, req.body?.values ?? {})
    if (problems.length > 0) throw new HttpError(400, problems.join('; '))
    ctx.audit.log(req, 'server.variables_updated', { target: req.gameServer!.name, serverId: req.gameServer!.id })
    res.json({ server: serializeServer(ctx, ctx.manager.servers.get(req.gameServer!.id)!, true) })
  })

  // --- Config files (managed keys) -------------------------------------------
  // Structured config editing beyond the file manager: list the blueprint's
  // declared config files with the current on-disk value of every mapped key,
  // and PUT targeted key updates through the format engines.
  const CONFIG_FILE_MAX = 2 * 1024 * 1024 // 2 MiB — configs are small; anything bigger is not one

  router.get('/servers/:id/configfiles', access('server.files.read'), (req: ServerRequest, res) => {
    ctx.gateway.assertLocal(req.gameServer!, 'the config editor')
    const inst = ctx.manager.instance(req.gameServer!.id)
    const vars = inst.vars
    const files = (inst.blueprint.configFiles ?? []).map((spec) => {
      const rel = substituteVars(spec.path, vars)
      const info: Record<string, unknown> = {
        path: rel,
        format: spec.format,
        exists: false,
        template: Boolean(spec.template),
        managed: [],
      }
      try {
        const file = safeJoin(inst.serverDir, rel)
        if (!fs.existsSync(file)) return info
        const stat = fs.statSync(file)
        if (!stat.isFile()) return info
        info.exists = true
        if (stat.size > CONFIG_FILE_MAX) {
          info.tooLarge = true
          return info
        }
        // Raw/template bodies belong to the file manager — only mapped keys here
        if (!isStructuredFormat(spec.format) || !spec.mappings) return info
        const text = fs.readFileSync(file, 'utf8')
        info.managed = Object.entries(spec.mappings).map(([varKey, configKey]) => ({
          varKey,
          configKey,
          value: getConfigValue(spec.format as Exclude<typeof spec.format, 'raw'>, text, configKey) ?? null,
          varValue: varKey in vars ? String(vars[varKey]) : null,
        }))
      } catch (err) {
        // one unreadable file must not take the whole listing down
        info.error = (err as Error).message
      }
      return info
    })
    res.json({ files })
  })

  router.put('/servers/:id/configfiles', access('server.config'), (req: ServerRequest, res) => {
    ctx.gateway.assertLocal(req.gameServer!, 'the config editor')
    const inst = ctx.manager.instance(req.gameServer!.id)
    const rel = String(req.body?.path ?? '')
    if (!rel) throw new HttpError(400, 'path required')
    const rawValues = req.body?.values
    if (typeof rawValues !== 'object' || rawValues === null || Array.isArray(rawValues))
      throw new HttpError(400, 'values must be an object of configKey → value')
    const entries = Object.entries(rawValues as Record<string, unknown>)
    if (entries.length === 0) throw new HttpError(400, 'values must not be empty')
    if (entries.length > 100) throw new HttpError(400, 'too many values (max 100)')
    const updates: Record<string, string> = {}
    for (const [key, value] of entries) {
      if (!key.trim() || key.length > 200) throw new HttpError(400, 'invalid config key')
      if (value !== null && typeof value === 'object') throw new HttpError(400, `value for ${key} must be a scalar`)
      const s = String(value ?? '')
      if (s.length > 4000) throw new HttpError(400, `value for ${key} is too long`)
      updates[key] = s
    }
    let requested: string
    try {
      requested = safeJoin(inst.serverDir, rel)
    } catch {
      throw new HttpError(400, 'invalid path')
    }
    // Only paths the blueprint declares are editable through this endpoint
    const vars = inst.vars
    const spec = (inst.blueprint.configFiles ?? []).find((cf) => {
      try {
        return safeJoin(inst.serverDir, substituteVars(cf.path, vars)) === requested
      } catch {
        return false
      }
    })
    if (!spec) throw new HttpError(400, 'path is not a declared config file of this server')
    if (!isStructuredFormat(spec.format)) throw new HttpError(400, 'raw config files are edited via the file manager instead')
    if (!fs.existsSync(requested)) throw new HttpError(400, 'config file does not exist on disk yet — install the server first')
    const stat = fs.statSync(requested)
    if (!stat.isFile()) throw new HttpError(400, 'config path is not a file')
    if (stat.size > CONFIG_FILE_MAX) throw new HttpError(400, 'config file too large to edit (max 2 MiB)')
    const text = fs.readFileSync(requested, 'utf8')
    fs.writeFileSync(requested, applyConfigUpdates(spec.format, text, updates))
    ctx.audit.log(req, 'server.configfile_updated', {
      target: rel,
      serverId: req.gameServer!.id,
      meta: { keys: Object.keys(updates) },
    })
    res.json({ ok: true })
  })

  router.post(
    '/servers/:id/reinstall',
    access('server.config'),
    asyncHandler(async (req: ServerRequest, res) => {
      ctx.gateway.assertLocal(req.gameServer!, 'reinstalling')
      ctx.audit.log(req, 'server.reinstall', { target: req.gameServer!.name, serverId: req.gameServer!.id })
      void ctx.manager.reinstall(req.gameServer!.id).catch(() => undefined)
      res.json({ ok: true })
    }),
  )

  router.post(
    '/servers/:id/steam-update',
    access('server.config'),
    asyncHandler(async (req: ServerRequest, res) => {
      ctx.gateway.assertLocal(req.gameServer!, 'the game update')
      ctx.audit.log(req, 'server.steam_update', { target: req.gameServer!.name, serverId: req.gameServer!.id })
      void ctx.manager.steamUpdate(req.gameServer!.id).catch(() => undefined)
      res.json({ ok: true })
    }),
  )

  router.post(
    '/servers/:id/docker/pull',
    access('server.config'),
    asyncHandler(async (req: ServerRequest, res) => {
      ctx.gateway.assertLocal(req.gameServer!, 'the docker image pull')
      // The pull runs in the background and only reports through the console,
      // so precondition failures must surface as a real 4xx before the 200.
      const inst = ctx.manager.instance(req.gameServer!.id)
      if (inst.runtime !== 'docker') throw new HttpError(400, 'this server does not use the docker runtime')
      if (!inst.dockerImage) throw new HttpError(400, 'no docker image configured — set one in Settings → Runtime')
      if (inst.installController) throw new HttpError(409, 'an install or update is already running for this server')
      try {
        await ctx.manager.assertDockerUsable()
      } catch (err) {
        throw new HttpError(400, (err as Error).message)
      }
      ctx.audit.log(req, 'server.docker_pull', {
        target: req.gameServer!.name,
        serverId: req.gameServer!.id,
        meta: { image: inst.dockerImage },
      })
      void ctx.manager.pullDockerImage(req.gameServer!.id).catch(() => undefined)
      res.json({ ok: true })
    }),
  )

  // --- Subusers -----------------------------------------------------------------
  router.get('/servers/:id/subusers', access('server.users'), (req: ServerRequest, res) => {
    const subusers = ctx.auth.subusers
      .filter((s) => s.serverId === req.gameServer!.id)
      .map((s) => ({
        id: s.id,
        userId: s.userId,
        username: ctx.auth.users.get(s.userId)?.username ?? '(deleted)',
        permissions: s.permissions,
        createdAt: s.createdAt,
      }))
    res.json({ subusers, availablePermissions: SERVER_PERMISSIONS })
  })

  // A subuser managing other subusers must never grant a permission they don't
  // themselves hold, otherwise `server.users` becomes a self-escalation to full
  // control (incl. `server.config` → arbitrary start command). Admins/owners
  // hold every permission via effectivePermissions, so they are unrestricted.
  const clampToGranter = (req: ServerRequest, requested: unknown): string[] => {
    const allowed = new Set(ctx.auth.effectivePermissions(req.user!, req.gameServer!))
    return (Array.isArray(requested) ? requested : [])
      .filter((p): p is string => typeof p === 'string')
      .filter((p) => (SERVER_PERMISSIONS as readonly string[]).includes(p) && allowed.has(p))
  }

  router.post('/servers/:id/subusers', access('server.users'), (req: ServerRequest, res) => {
    const { username, permissions } = req.body ?? {}
    const user = ctx.auth.users.find((u) => u.username.toLowerCase() === String(username ?? '').toLowerCase())
    if (!user) throw new HttpError(404, 'user not found')
    if (user.id === req.gameServer!.ownerId) throw new HttpError(400, 'owner already has full access')
    if (ctx.auth.subusers.find((s) => s.serverId === req.gameServer!.id && s.userId === user.id))
      throw new HttpError(400, 'user is already a subuser')
    const perms = clampToGranter(req, permissions)
    const sub = ctx.auth.subusers.insert({
      serverId: req.gameServer!.id,
      userId: user.id,
      permissions: perms,
      createdAt: new Date().toISOString(),
    })
    ctx.audit.log(req, 'server.subuser_added', { target: user.username, serverId: req.gameServer!.id })
    res.status(201).json({ subuser: { id: sub.id, userId: user.id, username: user.username, permissions: sub.permissions } })
  })

  router.patch('/servers/:id/subusers/:subId', access('server.users'), (req: ServerRequest, res) => {
    const sub = ctx.auth.subusers.get(req.params.subId)
    if (!sub || sub.serverId !== req.gameServer!.id) throw new HttpError(404, 'subuser not found')
    // Editing your own subuser row would let a `server.users` holder rewrite
    // their own permission set — block it outright (owners/admins have no such row).
    if (sub.userId === req.user!.id) throw new HttpError(403, 'cannot edit your own permissions')
    const perms = clampToGranter(req, req.body?.permissions)
    ctx.auth.subusers.update(sub.id, { permissions: perms })
    ctx.audit.log(req, 'server.subuser_updated', { serverId: req.gameServer!.id })
    res.json({ ok: true })
  })

  router.delete('/servers/:id/subusers/:subId', access('server.users'), (req: ServerRequest, res) => {
    const sub = ctx.auth.subusers.get(req.params.subId)
    if (!sub || sub.serverId !== req.gameServer!.id) throw new HttpError(404, 'subuser not found')
    ctx.auth.subusers.remove(sub.id)
    ctx.audit.log(req, 'server.subuser_removed', { serverId: req.gameServer!.id })
    res.json({ ok: true })
  })

  // --- Per-server activity --------------------------------------------------------
  router.get('/servers/:id/activity', access('server.activity'), (req: ServerRequest, res) => {
    const { entries, total } = ctx.audit.list({
      serverId: req.gameServer!.id,
      limit: intQuery(req.query.limit, 50, 1, 200),
      offset: intQuery(req.query.offset, 0, 0, Number.MAX_SAFE_INTEGER),
    })
    res.json({ entries, total })
  })

  return router
}
