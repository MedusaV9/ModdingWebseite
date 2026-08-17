import { useCallback, useEffect, useState } from 'react'
import { Download, ScrollText, Search } from 'lucide-react'
import { api } from '../api/client.ts'
import type { AuditEntry } from '../api/types.ts'
import { useT } from '../i18n/index.tsx'
import { Badge, Button, Card, EmptyState, Input, PageHeader, Spinner } from '../components/ui.tsx'
import { auditActionLabel, auditActionTint } from '../lib/audit.ts'
import { formatDateTime } from '../lib/format.ts'

const PAGE = 50

/** RFC 4180 field escaping: quote when the value contains a comma, quote, newline or tab. */
function escapeCsv(value: string): string {
  return /[",\n\r\t]/.test(value) ? '"' + value.replaceAll('"', '""') + '"' : value
}

/**
 * Spreadsheet formula-injection guard: Excel/LibreOffice execute cells that
 * start with = + - @ (or tab/CR) as formulas — and actor/target strings can
 * be influenced by subusers (server names, file names, backup notes). The
 * standard defense is a leading apostrophe, which spreadsheets treat as
 * "literal text" and plain-text tools show as-is.
 */
function neutralizeFormula(value: string): string {
  return /^[=+\-@\t\r]/.test(value) ? `'${value}` : value
}

function buildAuditCsv(entries: AuditEntry[], actionLabel: (action: string) => string): string {
  const header = ['timestamp', 'actor', 'action', 'action_label', 'target', 'ip', 'meta']
  const rows = entries.map((e) => [
    new Date(e.ts).toISOString(),
    e.username,
    e.action,
    actionLabel(e.action),
    e.target ?? '',
    e.ip ?? '',
    e.meta ? JSON.stringify(e.meta) : '',
  ])
  // BOM so Excel detects UTF-8 (umlauts in usernames/targets).
  return '\uFEFF' + [header.map(escapeCsv).join(','), ...rows.map((row) => row.map((cell) => escapeCsv(neutralizeFormula(cell))).join(','))].join('\r\n') + '\r\n'
}

function pad2(n: number): string {
  return String(n).padStart(2, '0')
}

export function AuditLog() {
  const t = useT()
  const [entries, setEntries] = useState<AuditEntry[] | null>(null)
  const [total, setTotal] = useState(0)
  const [filter, setFilter] = useState('')
  const [loadingMore, setLoadingMore] = useState(false)

  const load = useCallback(
    async (offset = 0, action = filter) => {
      const params = new URLSearchParams({ limit: String(PAGE), offset: String(offset) })
      if (action.trim()) params.set('action', action.trim())
      const res = await api.get<{ entries: AuditEntry[]; total: number }>(`/api/audit?${params}`).catch(() => null)
      if (!res) return
      setTotal(res.total)
      setEntries((prev) => (offset === 0 ? res.entries : [...(prev ?? []), ...res.entries]))
    },
    [filter],
  )

  useEffect(() => {
    const handle = setTimeout(() => void load(0), 250)
    return () => clearTimeout(handle)
  }, [load])

  // Exports exactly what the table shows: the currently loaded pages of the
  // currently active server-side action filter (not the full history).
  const exportCsv = () => {
    if (!entries || entries.length === 0) return
    const blob = new Blob([buildAuditCsv(entries, (action) => auditActionLabel(action, t))], { type: 'text/csv;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    const d = new Date()
    a.href = url
    a.download = `between-audit-${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}-${pad2(d.getHours())}${pad2(d.getMinutes())}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="fade-in-up">
      <PageHeader
        title={t('audit.title')}
        subtitle={t('audit.subtitle')}
        actions={
          <Button
            variant="secondary"
            onClick={exportCsv}
            disabled={!entries || entries.length === 0}
            title={entries && entries.length > 0 ? t('audit.exportCsvHint', { n: entries.length }) : undefined}
          >
            <Download size={15} />
            {t('audit.exportCsv')}
          </Button>
        }
      />

      <div className="relative mb-4 max-w-xs">
        <Search size={14} className="pointer-events-none absolute left-3.5 top-1/2 z-10 -translate-y-1/2 text-muted/60" />
        <Input
          value={filter}
          onChange={(e) => { setEntries(null); setFilter(e.target.value) }}
          placeholder={t('audit.filterAction')}
          className="rounded-full pl-9"
        />
      </div>

      <Card className="overflow-hidden">
        {!entries && <Spinner />}
        {entries && entries.length === 0 && <EmptyState icon={<ScrollText size={36} />} title={t('audit.empty')} />}
        {entries && entries.length > 0 && (
          <>
            <div className="table-scroll">
              <table className="w-full min-w-[40rem] text-[0.8125rem]">
                <thead>
                  <tr className="microlabel border-b border-line/70 text-left">
                    <th className="w-40 px-4 py-3 font-semibold">{t('audit.time')}</th>
                    <th className="w-32 px-3 py-3 font-semibold">{t('audit.user')}</th>
                    <th className="w-52 px-3 py-3 font-semibold">{t('audit.action')}</th>
                    <th className="px-3 py-3 font-semibold">{t('audit.target')}</th>
                  </tr>
                </thead>
                <tbody>
                  {entries.map((entry) => (
                    <tr key={entry.id} className="border-b border-line/40 transition-colors last:border-0 hover:bg-accent/5">
                      <td className="whitespace-nowrap px-4 py-2 font-mono text-xs text-muted tabular">{formatDateTime(entry.ts)}</td>
                      <td className="px-3 py-2 font-semibold">{entry.username}</td>
                      <td className="px-3 py-2">
                        {/* Humanized label; the raw key lives in `title` — the
                            filter above matches raw keys server-side. */}
                        <Badge title={entry.action} className={`font-mono ${auditActionTint(entry.action)}`}>
                          {auditActionLabel(entry.action, t)}
                        </Badge>
                      </td>
                      <td className="max-w-0 truncate px-3 py-2 text-muted">
                        {entry.target ?? '—'}
                        {entry.ip && <span className="ml-2 font-mono text-[0.6875rem] text-muted/60 tabular">{entry.ip}</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {entries.length < total && (
              <div className="border-t border-line/60 p-3 text-center">
                <Button
                  variant="secondary"
                  size="sm"
                  className="tabular"
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
    </div>
  )
}
