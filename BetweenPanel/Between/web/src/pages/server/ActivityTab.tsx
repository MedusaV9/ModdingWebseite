import { useCallback, useEffect, useState } from 'react'
import { Activity } from 'lucide-react'
import { api } from '../../api/client.ts'
import type { AuditEntry } from '../../api/types.ts'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { Badge, Button, Card, EmptyState, Spinner } from '../../components/ui.tsx'
import { auditActionLabel, auditActionTint } from '../../lib/audit.ts'
import { formatDateTime } from '../../lib/format.ts'

const PAGE = 30

export function ActivityTab() {
  const { server } = useServer()
  const t = useT()
  const [entries, setEntries] = useState<AuditEntry[] | null>(null)
  const [total, setTotal] = useState(0)
  const [loadingMore, setLoadingMore] = useState(false)

  const load = useCallback(
    async (offset = 0) => {
      const res = await api
        .get<{ entries: AuditEntry[]; total: number }>(`/api/servers/${server.id}/activity?limit=${PAGE}&offset=${offset}`)
        .catch(() => null)
      if (!res) return
      setTotal(res.total)
      setEntries((prev) => (offset === 0 ? res.entries : [...(prev ?? []), ...res.entries]))
    },
    [server.id],
  )

  useEffect(() => {
    void load()
  }, [load])

  return (
    <Card className="overflow-hidden">
      {!entries && <Spinner />}
      {entries && entries.length === 0 && <EmptyState icon={<Activity size={36} />} title={t('activity.empty')} />}
      {entries && entries.length > 0 && (
        <>
          <div className="divide-y divide-line/50">
            {entries.map((entry) => (
              <div key={entry.id} className="flex flex-wrap items-center gap-3 px-4 py-2.5 transition-colors hover:bg-elevated/40">
                <Activity size={14} className="shrink-0 text-accent/70" />
                <span className="text-[0.8125rem] font-semibold">{entry.username}</span>
                <Badge title={entry.action} className={`font-mono ${auditActionTint(entry.action)}`}>
                  {auditActionLabel(entry.action, t)}
                </Badge>
                {entry.target && <span className="min-w-0 truncate text-[0.8125rem] text-muted">{entry.target}</span>}
                <span className="tabular ml-auto font-mono text-[11px] text-muted/70">{formatDateTime(entry.ts)}</span>
              </div>
            ))}
          </div>
          {entries.length < total && (
            <div className="border-t border-line/60 p-3 text-center">
              <Button
                variant="secondary"
                size="sm"
                loading={loadingMore}
                onClick={async () => {
                  setLoadingMore(true)
                  await load(entries.length)
                  setLoadingMore(false)
                }}
              >
                {t('common.loadMore')} ({entries.length}/{total})
              </Button>
            </div>
          )}
        </>
      )}
    </Card>
  )
}
