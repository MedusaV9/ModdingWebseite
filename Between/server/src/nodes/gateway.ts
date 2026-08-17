/**
 * Thin dispatch facade between the API routes and the two places a server
 * can live: the local ServerManager or a remote node agent. Routes keep
 * their permission gates (permissions are PANEL-side; the node trusts the
 * panel token) and call the gateway to (a) resolve ids across both worlds,
 * (b) proxy an operation to the owning node with consistent error mapping,
 * or (c) reject operations v1 does not support remotely.
 */
import type { GameServer, PanelNode } from '../types.ts'
import type { ServerManager } from '../servers/manager.ts'
import { HttpError } from '../api/helpers.ts'
import { NodeRequestError, type RemoteNodeClient } from './client.ts'
import type { NodeService } from './service.ts'

export class ServerGateway {
  constructor(private manager: ServerManager, private nodes: NodeService) {}

  /** Resolve a server id: local record first, then the remote mirror. */
  lookup(id: string): GameServer | undefined {
    return this.manager.servers.get(id) ?? this.nodes.mirror(id)
  }

  isRemote(server: GameServer): boolean {
    return typeof server.nodeId === 'string' && server.nodeId.length > 0
  }

  /** Resolve the owning node of a remote server; 502 when it is gone or offline. */
  requireOnline(server: GameServer): { node: PanelNode; client: RemoteNodeClient } {
    const node = server.nodeId ? this.nodes.get(server.nodeId) : undefined
    if (!node) throw new HttpError(502, `the node hosting "${server.name}" is no longer registered`)
    if (!this.nodes.healthOf(node.id).online)
      throw new HttpError(502, `node "${node.name}" is currently unreachable — try again once it is back online`)
    return { node, client: this.nodes.clientFor(node) }
  }

  /**
   * Run one operation against the node owning this server. Unreachable node
   * → 502 with a clear message; agent-side validation errors relay their
   * original status and message so the UX matches local behavior.
   */
  async proxy<T>(server: GameServer, fn: (client: RemoteNodeClient) => Promise<T>): Promise<T> {
    const { node, client } = this.requireOnline(server)
    return this.callNode(node, client, fn)
  }

  /** Same error mapping for calls that have a node but no server yet (create). */
  async callNode<T>(node: PanelNode, client: RemoteNodeClient, fn: (client: RemoteNodeClient) => Promise<T>): Promise<T> {
    try {
      return await fn(client)
    } catch (err) {
      if (err instanceof NodeRequestError) {
        if (err.status === null) throw new HttpError(502, `node "${node.name}" unreachable: ${err.message}`)
        throw new HttpError(err.status, err.message)
      }
      throw err
    }
  }

  /** Guard for operations that v1 does not support on remote servers. */
  assertLocal(server: GameServer, what: string): void {
    if (this.isRemote(server)) throw new HttpError(400, `${what} is not yet supported for servers on remote nodes`)
  }
}
