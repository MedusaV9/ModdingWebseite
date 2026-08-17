import { Router } from 'express'
import os from 'node:os'
import type { AppContext } from '../context.ts'
import { currentSettings } from '../context.ts'
import { PANEL_VERSION } from '../config.ts'
import { requireAuth, requireAdmin, type AuthedRequest } from '../auth/service.ts'
import { asyncHandler, HttpError, intQuery } from './helpers.ts'
import { validateBlueprint } from '../blueprints/schema.ts'
import { convertEgg } from '../lib/eggs.ts'
import { fetchPublicJson } from '../lib/nettrust.ts'
import { validateWebhookUrl } from '../services/notify.ts'
import { catalogBlueprintId, catalogEntries, getCatalogEntry } from '../catalog/catalog.ts'
import type { Blueprint } from '../types.ts'

/** Eggs are tiny JSON files — cap fetches well below anything suspicious. */
const EGG_FETCH_TIMEOUT_MS = 10_000
const EGG_FETCH_MAX_BYTES = 2 * 1024 * 1024

/** Fetch an egg export from a public URL (SSRF-checked) — HttpError 400 on any failure. */
async function fetchEggFromUrl(url: unknown): Promise<unknown> {
  if (typeof url !== 'string' || url.trim().length === 0) throw new HttpError(400, 'url must be a non-empty string')
  try {
    return await fetchPublicJson(url.trim(), { timeoutMs: EGG_FETCH_TIMEOUT_MS, maxBytes: EGG_FETCH_MAX_BYTES })
  } catch (err) {
    throw new HttpError(400, `could not fetch egg from URL: ${(err as Error).message}`)
  }
}

export function miscRouter(ctx: AppContext): Router {
  const router = Router()

  // --- Blueprints -------------------------------------------------------------
  router.get(
    '/blueprints',
    requireAuth,
    asyncHandler(async (_req, res) => {
      const docker = await ctx.docker.info()
      res.json({
        blueprints: ctx.registry.all(),
        platform: process.platform,
        docker: { available: docker.available, version: docker.version ?? null },
      })
    }),
  )

  router.get('/blueprints/:id', requireAuth, (req, res) => {
    const bp = ctx.registry.get(req.params.id)
    if (!bp) throw new HttpError(404, 'blueprint not found')
    res.json({ blueprint: bp })
  })

  router.post('/blueprints', requireAdmin, (req: AuthedRequest, res) => {
    const bp = req.body?.blueprint as Blueprint
    const { ok, problems } = ctx.registry.addCustom(bp)
    if (!ok) throw new HttpError(400, problems.join('; '))
    ctx.audit.log(req, 'blueprint.created', { target: bp.id })
    res.status(201).json({ blueprint: ctx.registry.get(bp.id) })
  })

  router.post('/blueprints/validate', requireAdmin, (req, res) => {
    const problems = validateBlueprint(req.body?.blueprint)
    res.json({ valid: problems.length === 0, problems })
  })

  // Convert a Pterodactyl egg export into a blueprint preview. Accepts the
  // egg as an object, a raw JSON string, or a public URL to fetch it from.
  // Nothing is saved here — the client reviews the result and saves via
  // POST /blueprints (which is where validation and audit logging happen).
  router.post(
    '/blueprints/import-egg',
    requireAdmin,
    asyncHandler(async (req, res) => {
      let egg: unknown = req.body?.egg
      if (req.body?.url !== undefined) {
        egg = await fetchEggFromUrl(req.body.url)
      } else if (typeof egg === 'string') {
        try {
          egg = JSON.parse(egg)
        } catch {
          throw new HttpError(400, 'egg is not valid JSON')
        }
      }
      try {
        const { blueprint, warnings } = convertEgg(egg)
        res.json({ blueprint, warnings })
      } catch (err) {
        throw new HttpError(400, (err as Error).message)
      }
    }),
  )

  router.put('/blueprints/:id', requireAdmin, (req: AuthedRequest, res) => {
    const { ok, problems } = ctx.registry.updateCustom(req.params.id, req.body?.blueprint as Blueprint)
    if (!ok) throw new HttpError(400, problems.join('; '))
    ctx.manager.refreshBlueprint(req.params.id)
    ctx.audit.log(req, 'blueprint.updated', { target: req.params.id })
    res.json({ blueprint: ctx.registry.get(req.params.id) })
  })

  router.delete('/blueprints/:id', requireAdmin, (req: AuthedRequest, res) => {
    if (ctx.registry.isBuiltin(req.params.id)) throw new HttpError(400, 'builtin blueprints cannot be deleted')
    const inUse = ctx.manager.servers.filter((s) => s.blueprintId === req.params.id)
    if (inUse.length > 0) throw new HttpError(400, `blueprint is used by ${inUse.length} server(s)`)
    if (!ctx.registry.removeCustom(req.params.id)) throw new HttpError(404, 'custom blueprint not found')
    ctx.audit.log(req, 'blueprint.deleted', { target: req.params.id })
    res.json({ ok: true })
  })

  // --- Game Library catalog ----------------------------------------------------
  router.get('/catalog', requireAuth, (_req, res) => {
    const installedBlueprintIds = catalogEntries
      .map((entry) => catalogBlueprintId(entry))
      .filter((id) => ctx.registry.get(id) !== undefined)
    res.json({
      entries: catalogEntries.map((entry) => ({ ...entry, blueprintId: catalogBlueprintId(entry) })),
      installedBlueprintIds,
    })
  })

  router.post(
    '/catalog/:id/add',
    requireAdmin,
    asyncHandler(async (req: AuthedRequest, res) => {
      const entry = getCatalogEntry(req.params.id)
      if (!entry) throw new HttpError(404, 'catalog entry not found')

      // Builtin entries already ship as blueprints — nothing to save.
      if (entry.source.type === 'builtin') {
        const blueprint = ctx.registry.get(entry.source.blueprintId)
        if (!blueprint) throw new HttpError(500, `catalog entry references missing builtin blueprint ${entry.source.blueprintId}`)
        res.json({ blueprint, warnings: [] })
        return
      }

      const targetId = catalogBlueprintId(entry)
      if (ctx.registry.get(targetId)) throw new HttpError(400, `"${entry.name}" is already in your library`)

      const egg = await fetchEggFromUrl(entry.source.url)
      let converted: { blueprint: Blueprint; warnings: string[] }
      try {
        converted = convertEgg(egg)
      } catch (err) {
        throw new HttpError(400, `could not convert egg for "${entry.name}": ${(err as Error).message}`)
      }
      // Deterministic id + catalog cosmetics, so "already added" detection and
      // the create-server link work without extra bookkeeping.
      const blueprint = { ...converted.blueprint, id: targetId, name: entry.name, category: entry.category }
      if (entry.icon) blueprint.icon = entry.icon
      if (entry.color) blueprint.color = entry.color
      const { ok, problems } = ctx.registry.addCustom(blueprint)
      if (!ok) throw new HttpError(400, problems.join('; '))
      ctx.audit.log(req, 'catalog.added', { target: entry.id, meta: { blueprintId: targetId, url: entry.source.url } })
      res.status(201).json({ blueprint: ctx.registry.get(targetId), warnings: converted.warnings })
    }),
  )

  // --- API keys ---------------------------------------------------------------
  router.get('/apikeys', requireAuth, (req: AuthedRequest, res) => {
    const keys = ctx.auth.apiKeys
      .filter((k) => k.userId === req.user!.id)
      .map((k) => ({ id: k.id, name: k.name, prefix: k.prefix, scopes: k.scopes, createdAt: k.createdAt, lastUsedAt: k.lastUsedAt }))
    res.json({ apiKeys: keys })
  })

  router.post('/apikeys', requireAuth, (req: AuthedRequest, res) => {
    const { name, scopes } = req.body ?? {}
    const { apiKey, secret } = ctx.auth.createApiKey(req.user!.id, String(name ?? 'api key'), Array.isArray(scopes) ? scopes : [])
    ctx.audit.log(req, 'apikey.created', { target: apiKey.name })
    res.status(201).json({
      apiKey: { id: apiKey.id, name: apiKey.name, prefix: apiKey.prefix, scopes: apiKey.scopes, createdAt: apiKey.createdAt },
      secret,
    })
  })

  router.delete('/apikeys/:id', requireAuth, (req: AuthedRequest, res) => {
    const key = ctx.auth.apiKeys.get(req.params.id)
    if (!key || key.userId !== req.user!.id) throw new HttpError(404, 'api key not found')
    ctx.auth.apiKeys.remove(key.id)
    ctx.audit.log(req, 'apikey.deleted', { target: key.name })
    res.json({ ok: true })
  })

  // --- Audit (admin) -----------------------------------------------------------
  router.get('/audit', requireAdmin, (req, res) => {
    const { entries, total } = ctx.audit.list({
      serverId: req.query.serverId ? String(req.query.serverId) : undefined,
      userId: req.query.userId ? String(req.query.userId) : undefined,
      action: req.query.action ? String(req.query.action) : undefined,
      limit: intQuery(req.query.limit, 50, 1, 200),
      offset: intQuery(req.query.offset, 0, 0, Number.MAX_SAFE_INTEGER),
    })
    res.json({ entries, total })
  })

  // --- Settings (admin) ----------------------------------------------------------
  router.get('/settings', requireAdmin, (_req, res) => {
    res.json({ settings: currentSettings(ctx) })
  })

  router.patch('/settings', requireAdmin, (req: AuthedRequest, res) => {
    const settings = currentSettings(ctx)
    const { panelName, defaultBackupRetention, portRangeStart, portRangeEnd, discordWebhookUrl, discordEvents, webhookUrl, webhookEvents, defaultTheme } =
      req.body ?? {}
    const patch: Partial<typeof settings> = {}
    if (panelName !== undefined) {
      const name = String(panelName).trim()
      if (!name || name.length > 40) throw new HttpError(400, 'panel name must be 1-40 characters')
      patch.panelName = name
    }
    if (defaultBackupRetention !== undefined)
      patch.defaultBackupRetention = Math.max(1, Math.min(100, Number(defaultBackupRetention) || 10))
    if (portRangeStart !== undefined) patch.portRangeStart = Math.max(1024, Math.min(65535, Number(portRangeStart) || 25565))
    if (portRangeEnd !== undefined) patch.portRangeEnd = Math.max(1024, Math.min(65535, Number(portRangeEnd) || 29000))
    if (discordWebhookUrl !== undefined) {
      const url = String(discordWebhookUrl ?? '').trim()
      if (url && !/^https:\/\/(discord\.com|discordapp\.com)\/api\/webhooks\//.test(url))
        throw new HttpError(400, 'invalid Discord webhook URL')
      patch.discordWebhookUrl = url || null
    }
    if (discordEvents !== undefined) {
      patch.discordEvents = {
        crash: Boolean(discordEvents?.crash),
        power: Boolean(discordEvents?.power),
        backup: Boolean(discordEvents?.backup),
      }
    }
    if (webhookUrl !== undefined) {
      const url = String(webhookUrl ?? '').trim()
      // Shape-only validation on purpose: self-hosted panels post to private/
      // LAN receivers (n8n, custom scripts), so any host and port must be
      // accepted here — see validateWebhookUrl in services/notify.ts.
      if (url) {
        const problem = validateWebhookUrl(url)
        if (problem) throw new HttpError(400, problem)
      }
      patch.webhookUrl = url || null
    }
    if (webhookEvents !== undefined) {
      patch.webhookEvents = {
        crash: Boolean(webhookEvents?.crash),
        power: Boolean(webhookEvents?.power),
        backup: Boolean(webhookEvents?.backup),
      }
    }
    if (defaultTheme !== undefined) patch.defaultTheme = String(defaultTheme).slice(0, 40)
    ctx.settings.update(settings.id, patch)
    ctx.audit.log(req, 'settings.updated', { meta: { keys: Object.keys(patch) } })
    res.json({ settings: currentSettings(ctx) })
  })

  // Deliver a `test` payload to the configured generic webhook so admins can
  // verify their receiver without waiting for a real event.
  router.post(
    '/settings/webhook-test',
    requireAdmin,
    asyncHandler(async (_req, res) => {
      if (!currentSettings(ctx).webhookUrl) throw new HttpError(400, 'no webhook URL configured — save one first')
      const result = await ctx.notifier.sendTestWebhook()
      res.json(result)
    }),
  )

  // --- System ----------------------------------------------------------------------
  router.get('/system', requireAuth, (_req, res) => {
    const latest = ctx.metrics.latest()
    res.json({
      system: {
        platform: process.platform,
        release: os.release(),
        arch: os.arch(),
        hostname: os.hostname(),
        cpus: os.cpus().length,
        cpuModel: os.cpus()[0]?.model ?? 'unknown',
        nodeVersion: process.version,
        panelVersion: PANEL_VERSION,
        panelUptimeS: Math.floor(process.uptime()),
        dataDir: ctx.config.dataDir,
        serverCount: ctx.manager.servers.size(),
        runningCount: [...ctx.manager.instances.values()].filter((i) => i.status === 'running' || i.status === 'starting').length,
        metrics: latest,
      },
    })
  })

  router.get('/system/metrics', requireAuth, (req, res) => {
    // Full ring by default; ?limit=N trims the payload to the newest N samples
    // (the dashboard sparklines only chart a short recent window).
    const limit = intQuery(req.query.limit, ctx.metrics.history.cap, 1, ctx.metrics.history.cap)
    res.json({ history: ctx.metrics.history.toArray(limit) })
  })

  // --- Docker ------------------------------------------------------------------------
  router.get(
    '/docker/status',
    requireAuth,
    asyncHandler(async (req, res) => {
      const info = await ctx.docker.info(req.query.refresh === 'true')
      res.json({
        available: info.available,
        version: info.version ?? null,
        apiVersion: info.apiVersion ?? null,
        socketPath: info.socketPath,
        error: info.error ?? null,
      })
    }),
  )

  // --- SteamCMD -----------------------------------------------------------------------
  router.get('/steam/status', requireAuth, (_req, res) => {
    // `loginConfigured` (not the account name) is deliberately the only login
    // detail visible below admin — server owners need it to know whether the
    // per-server "use Steam login" toggle can work.
    res.json({
      installed: ctx.steam.isInstalled(),
      dir: ctx.steam.dir,
      platform: process.platform,
      loginConfigured: ctx.steamLogin.user !== null,
    })
  })

  router.post(
    '/steam/install',
    requireAdmin,
    asyncHandler(async (req: AuthedRequest, res) => {
      const log: string[] = []
      await ctx.steam.ensureInstalled((line) => log.push(line))
      ctx.audit.log(req, 'steam.installed')
      res.json({ ok: true, log })
    }),
  )

  // --- Steam account login (panel-level, admin) ---------------------------------------
  // The password travels request → steamcmd stdin and nowhere else: it is
  // never persisted, never echoed back and scrubbed from all captured output
  // (see steam/login.ts). Session state is per machine — remote nodes are
  // not covered by this login (v1 limitation, surfaced in the UI).
  router.get(
    '/steam/login',
    requireAdmin,
    asyncHandler(async (req, res) => {
      // Probe = one `+login <user> +quit` run against the cached session,
      // TTL-cached for 5 min; ?refresh=true forces a fresh probe.
      const status = await ctx.steamLogin.status(req.query.refresh === 'true')
      res.json(status)
    }),
  )

  router.post(
    '/steam/login',
    requireAdmin,
    asyncHandler(async (req: AuthedRequest, res) => {
      const { username, password, guardCode } = req.body ?? {}
      const result = await ctx.steamLogin.login(String(username ?? ''), String(password ?? ''), guardCode === undefined ? undefined : String(guardCode))
      // Audit carries the outcome and the account NAME only — never secrets.
      if (result.ok) ctx.audit.log(req, 'steam.login', { target: ctx.steamLogin.user ?? String(username ?? '') })
      else if (!result.needsGuard) ctx.audit.log(req, 'steam.login_failed', { target: String(username ?? ''), meta: { reason: result.error ?? 'unknown' } })
      res.json(result)
    }),
  )

  router.post(
    '/steam/logout',
    requireAdmin,
    asyncHandler(async (req: AuthedRequest, res) => {
      const user = ctx.steamLogin.user
      await ctx.steamLogin.logout()
      ctx.audit.log(req, 'steam.logout', { target: user ?? undefined })
      res.json({ ok: true })
    }),
  )

  return router
}
