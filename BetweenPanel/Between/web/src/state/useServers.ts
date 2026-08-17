import { useCallback, useEffect, useState } from 'react'
import { api } from '../api/client.ts'
import { wsClient } from '../api/ws.ts'
import type { QueryResult, ResourceSnapshot, ServerStatus, ServerSummary } from '../api/types.ts'

/** Live server list: initial fetch + WS deltas (status/stats/query), resync on reconnect. */
export function useServerList() {
  const [servers, setServers] = useState<ServerSummary[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ servers: ServerSummary[] }>('/api/servers')
      setServers(res.servers)
      setError(null)
    } catch (err) {
      setError((err as Error).message)
    }
  }, [])

  useEffect(() => {
    void load()
    return wsClient.onMessage((msg) => {
      if (msg.t === '_open') {
        void load()
        return
      }
      if (!msg.serverId) return
      if (msg.t === 'deleted') {
        setServers((prev) => prev?.filter((s) => s.id !== msg.serverId) ?? prev)
      } else if (msg.t === 'status') {
        const status = msg.status as ServerStatus
        setServers((prev) =>
          prev?.map((s) =>
            s.id === msg.serverId
              ? { ...s, status, installed: status !== 'installing' && status !== 'install_failed' ? true : s.installed }
              : s,
          ) ?? prev,
        )
        // creation changes list membership — refetch lazily
        if (status === 'installing') void load()
      } else if (msg.t === 'stats') {
        const snap = msg.snap as ResourceSnapshot
        setServers((prev) => prev?.map((s) => (s.id === msg.serverId ? { ...s, resources: snap, uptimeS: snap.uptimeS } : s)) ?? prev)
      } else if (msg.t === 'query') {
        const query = msg.query as QueryResult
        setServers((prev) => prev?.map((s) => (s.id === msg.serverId ? { ...s, query } : s)) ?? prev)
      }
    })
  }, [load])

  return { servers, error, reload: load }
}
