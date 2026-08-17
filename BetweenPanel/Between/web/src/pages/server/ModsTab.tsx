import { useCallback, useEffect, useState } from 'react'
import { Download, Package, Puzzle, Search, Trash2 } from 'lucide-react'
import { api, ApiError } from '../../api/client.ts'
import type { ModSearchHit, ModSearchResult, ModsOverview } from '../../api/types.ts'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Badge, Button, Card, CardHeader, EmptyState, IconButton, Input, Spinner } from '../../components/ui.tsx'
import { ConfirmModal } from '../../components/Modal.tsx'
import { formatBytes, formatDateTime } from '../../lib/format.ts'

/** Compact download counter, e.g. 9200000 → "9.2M" (locale-aware). */
function formatCompact(n: number): string {
  return new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 }).format(n)
}

function ModIcon({ url, alt }: { url: string | null; alt: string }) {
  const [failed, setFailed] = useState(false)
  if (!url || failed) {
    return (
      <div className="glass-subtle flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-muted/60">
        <Package size={18} />
      </div>
    )
  }
  return (
    <img
      src={url}
      alt={alt}
      loading="lazy"
      className="sheen h-10 w-10 shrink-0 rounded-lg border border-line/70 bg-elevated object-cover"
      onError={() => setFailed(true)}
    />
  )
}

export function ModsTab() {
  const { server, can } = useServer()
  const t = useT()
  const toast = useToast()
  const mayWrite = can('server.files.write')

  const [overview, setOverview] = useState<ModsOverview | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null)
  const [deleting, setDeleting] = useState(false)
  const [query, setQuery] = useState('')
  const [hits, setHits] = useState<ModSearchHit[] | null>(null)
  const [searching, setSearching] = useState(false)
  const [installingId, setInstallingId] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const res = await api.get<ModsOverview>(`/api/servers/${server.id}/mods`)
      setOverview(res)
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }, [server.id, toast])

  useEffect(() => {
    void load()
  }, [load])

  // Debounced Modrinth search; responses from stale queries are dropped.
  useEffect(() => {
    const q = query.trim()
    if (q.length < 2) {
      setHits(null)
      setSearching(false)
      return
    }
    setSearching(true)
    let cancelled = false
    const timer = setTimeout(() => {
      void (async () => {
        try {
          const res = await api.get<ModSearchResult>(`/api/servers/${server.id}/mods/search?q=${encodeURIComponent(q)}&limit=20`)
          if (!cancelled) setHits(res.hits)
        } catch (err) {
          if (!cancelled) {
            setHits(null)
            toast('error', err instanceof ApiError ? err.message : String(err))
          }
        } finally {
          if (!cancelled) setSearching(false)
        }
      })()
    }, 400)
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [query, server.id, toast])

  const install = async (hit: ModSearchHit) => {
    setInstallingId(hit.projectId)
    try {
      // No versionId → the backend picks the newest compatible version.
      await api.post(`/api/servers/${server.id}/mods/install`, { projectId: hit.projectId })
      toast('success', t('mods.installed', { name: hit.title }))
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setInstallingId(null)
    }
  }

  const remove = async () => {
    if (!deleteTarget) return
    setDeleting(true)
    try {
      await api.del(`/api/servers/${server.id}/mods/${encodeURIComponent(deleteTarget)}`)
      setDeleteTarget(null)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setDeleting(false)
    }
  }

  if (!overview) return <Spinner label={t('common.loading')} />
  if (!overview.supported) {
    return (
      <Card>
        <EmptyState icon={<Puzzle size={36} />} title={t('mods.unsupported')} />
      </Card>
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Puzzle size={17} className="text-accent/80" />
        <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight">{t('tab.mods')}</h2>
        <span className="text-xs text-muted">{t('mods.subtitle', { loader: overview.loader ?? '', dir: overview.dir ?? '' })}</span>
        {overview.mcVersion && <Badge>{t('mods.mcVersion', { v: overview.mcVersion })}</Badge>}
      </div>

      <Card className="overflow-hidden">
        <CardHeader title={t('mods.installedTitle')} />
        {overview.installed.length === 0 && <p className="px-4 py-6 text-center text-sm text-muted">{t('mods.noneInstalled')}</p>}
        {overview.installed.length > 0 && (
          <div className="divide-y divide-line/50">
            {overview.installed.map((mod) => (
              <div key={mod.fileName} className="flex flex-wrap items-center gap-3 px-4 py-2.5 transition-colors hover:bg-elevated/40">
                <Package size={16} className="shrink-0 text-accent/80" />
                <div className="min-w-0 flex-1 basis-40">
                  <div className="truncate font-mono text-[0.8125rem] font-medium">{mod.fileName}</div>
                  <div className="tabular mt-0.5 text-xs text-muted">
                    {formatBytes(mod.sizeBytes)} · {formatDateTime(mod.modifiedAt)}
                  </div>
                </div>
                {mayWrite && (
                  <IconButton size="sm" onClick={() => setDeleteTarget(mod.fileName)} label={t('common.delete')} className="hover:bg-danger/15 hover:text-danger">
                    <Trash2 size={13} className="text-danger/80" />
                  </IconButton>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card className="overflow-hidden">
        <CardHeader title={t('mods.searchTitle')} subtitle={overview.dir ? t('mods.target', { dir: overview.dir }) : undefined} />
        <div className="border-b border-line/60 px-4 py-3">
          <div className="relative">
            <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={t('mods.searchPlaceholder')}
              className="pl-8"
              maxLength={100}
            />
          </div>
        </div>
        {searching && <Spinner />}
        {!searching && hits && hits.length === 0 && (
          <p className="px-4 py-6 text-center text-sm text-muted">{t('mods.noResults', { q: query.trim() })}</p>
        )}
        {!searching && hits && hits.length > 0 && (
          <div className="divide-y divide-line/50">
            {hits.map((hit) => (
              <div key={hit.projectId} className="flex flex-wrap items-center gap-3 px-4 py-3 transition-colors hover:bg-elevated/40">
                <ModIcon url={hit.iconUrl} alt={hit.title} />
                <div className="min-w-0 flex-1 basis-40">
                  <div className="flex items-center gap-2">
                    <span className="truncate text-[0.8125rem] font-medium">{hit.title}</span>
                    <span className="tabular shrink-0 text-[0.6875rem] text-muted">{t('mods.downloads', { n: formatCompact(hit.downloads) })}</span>
                  </div>
                  <p className="mt-0.5 line-clamp-2 text-xs leading-snug text-muted">{hit.description}</p>
                </div>
                {mayWrite && (
                  <Button
                    size="sm"
                    variant="secondary"
                    loading={installingId === hit.projectId}
                    disabled={installingId !== null}
                    onClick={() => void install(hit)}
                  >
                    <Download size={12} />
                    {t('mods.install')}
                  </Button>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>

      <ConfirmModal
        open={deleteTarget !== null}
        onClose={() => setDeleteTarget(null)}
        onConfirm={() => void remove()}
        message={t('mods.deleteConfirm', { name: deleteTarget ?? '' })}
        danger
        loading={deleting}
        confirmLabel={t('common.delete')}
      />
    </div>
  )
}
