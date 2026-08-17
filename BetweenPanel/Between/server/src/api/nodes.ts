/**
 * Admin API for remote node management. The node token is a shared secret:
 * it is accepted on create, stored server-side and NEVER serialized back out
 * (no GET returns it) — mirroring how API keys only surface their hash.
 */
import { Router } from 'express'
import type { AppContext } from '../context.ts'
import { requireAdmin, type AuthedRequest } from '../auth/service.ts'
import { asyncHandler, HttpError } from './helpers.ts'
import type { PanelNode } from '../types.ts'

export function nodesRouter(ctx: AppContext): Router {
  const router = Router()
  // Scoped to /nodes — an unscoped use() would gate every later /api route
  // behind admin because sibling routers share the /api mount point.
  router.use('/nodes', requireAdmin)

  const serializeNode = (node: PanelNode) => ({
    id: node.id,
    name: node.name,
    baseUrl: node.baseUrl,
    createdAt: node.createdAt,
    health: ctx.nodes.healthOf(node.id),
    serverCount: ctx.nodes.mirrors.filter((m) => m.nodeId === node.id).length,
  })

  router.get('/nodes', (_req, res) => {
    res.json({ nodes: ctx.nodes.nodes.all().map(serializeNode) })
  })

  router.post('/nodes', (req: AuthedRequest, res) => {
    const { node, problems } = ctx.nodes.addNode(req.body ?? {})
    if (!node) throw new HttpError(400, problems.join('; '))
    ctx.audit.log(req, 'node.created', { target: node.name, meta: { baseUrl: node.baseUrl } })
    res.status(201).json({ node: serializeNode(node) })
  })

  router.delete('/nodes/:id', (req: AuthedRequest, res) => {
    const node = ctx.nodes.get(req.params.id)
    if (!node) throw new HttpError(404, 'node not found')
    ctx.nodes.removeNode(node.id)
    ctx.audit.log(req, 'node.deleted', { target: node.name, meta: { baseUrl: node.baseUrl } })
    res.json({ ok: true })
  })

  router.post(
    '/nodes/:id/test',
    asyncHandler(async (req: AuthedRequest, res) => {
      const node = ctx.nodes.get(req.params.id)
      if (!node) throw new HttpError(404, 'node not found')
      const result = await ctx.nodes.testNode(node)
      // A reachable panel with an unreachable node is a 200 with ok:false —
      // the admin UI treats this as a diagnostic result, not a failure.
      res.json(result)
    }),
  )

  return router
}
