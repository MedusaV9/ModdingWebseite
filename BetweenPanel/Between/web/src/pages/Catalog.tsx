import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { LibraryBig, Plus, Search } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import type { Blueprint } from '../api/types.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { useToast } from '../state/ToastContext.tsx'
import { Badge, Button, Chip, EmptyState, Input, PageHeader, Spinner, cx } from '../components/ui.tsx'
import { Modal } from '../components/Modal.tsx'
import { GameIcon } from '../components/GameIcon.tsx'

interface CatalogEntry {
  id: string
  name: string
  category: string
  description: string
  icon?: string
  color?: string
  source: { type: 'builtin'; blueprintId: string } | { type: 'egg-url'; url: string }
  /** Resolved by the server: the blueprint id this entry maps to once added. */
  blueprintId: string
}

export function Catalog() {
  const t = useT()
  const toast = useToast()
  const navigate = useNavigate()
  const { user } = useAuth()
  const isAdmin = user?.role === 'admin'
  const [entries, setEntries] = useState<CatalogEntry[] | null>(null)
  const [installed, setInstalled] = useState<Set<string>>(new Set())
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState('all')
  const [addingId, setAddingId] = useState<string | null>(null)
  const [warningsModal, setWarningsModal] = useState<{ name: string; warnings: string[] } | null>(null)

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ entries: CatalogEntry[]; installedBlueprintIds: string[] }>('/api/catalog')
      setEntries(res.entries)
      setInstalled(new Set(res.installedBlueprintIds))
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }, [toast])

  useEffect(() => {
    void load()
  }, [load])

  const categories = useMemo(() => (entries ? ['all', ...new Set(entries.map((e) => e.category))] : []), [entries])

  const filtered = useMemo(() => {
    if (!entries) return []
    const q = search.trim().toLowerCase()
    return entries.filter((e) => {
      if (category !== 'all' && e.category !== category) return false
      if (!q) return true
      return e.name.toLowerCase().includes(q) || e.description.toLowerCase().includes(q) || e.id.includes(q)
    })
  }, [entries, search, category])

  // Fetches + converts the community egg server-side and saves the blueprint.
  const add = async (entry: CatalogEntry) => {
    if (addingId) return
    setAddingId(entry.id)
    try {
      const res = await api.post<{ blueprint: Blueprint; warnings: string[] }>(`/api/catalog/${entry.id}/add`)
      setInstalled((prev) => new Set(prev).add(res.blueprint.id))
      toast('success', t('catalog.addedToast', { name: entry.name }))
      if (res.warnings.length > 0) setWarningsModal({ name: entry.name, warnings: res.warnings })
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setAddingId(null)
    }
  }

  return (
    <div className="fade-in-up">
      <PageHeader title={t('catalog.title')} subtitle={t('catalog.subtitle')} />

      <div className="mb-6 space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative w-full max-w-xs">
            <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder={t('catalog.searchPh')}
              className={cx('rounded-full pl-8', entries && filtered.length < entries.length && 'pr-16')}
            />
            {/* Result counter only while a filter is narrowing the list — folded into the search field. */}
            {entries && filtered.length < entries.length && (
              <span className="tabular pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-xs text-muted">
                {filtered.length} / {entries.length}
              </span>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            {categories.map((cat) => (
              <Chip key={cat} active={category === cat} onClick={() => setCategory(cat)}>
                {cat === 'all' ? t('create.categories.all') : cat}
              </Chip>
            ))}
          </div>
        </div>
        <p className="text-xs text-muted">{t('catalog.communityHint')}</p>
      </div>

      {!entries && <Spinner />}
      {entries && filtered.length === 0 && <EmptyState icon={<LibraryBig size={36} />} title={t('catalog.empty')} />}

      <div className="stagger grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {filtered.map((entry) => {
          const isInstalled = installed.has(entry.blueprintId)
          const isBuiltin = entry.source.type === 'builtin'
          // Whole card mirrors its CTA (keyboard access lives on the inner
          // button/link); cards without an action get no pressable affordance.
          const cardAction = isInstalled
            ? () => navigate(`/servers/new?blueprint=${entry.blueprintId}`)
            : isAdmin
              ? () => void add(entry)
              : undefined
          return (
            <div
              key={entry.id}
              onClick={cardAction}
              // Dense grid (60 entries): blur-free glass tint — one backdrop-filter
              // per card would blow the perf budget.
              className={cx(
                'glass-subtle fade-in-up flex flex-col rounded-2xl p-4',
                cardAction && 'pressable cursor-pointer hover:border-accent/50 hover:bg-elevated/50',
              )}
            >
              <div className="flex items-center gap-3">
                <GameIcon icon={entry.icon} color={entry.color} boxed size={20} />
                <div className="min-w-0 flex-1">
                  <div className="truncate font-display text-[0.875rem] font-semibold tracking-tight">{entry.name}</div>
                  <div className="text-[0.6875rem] capitalize text-muted">{entry.category}</div>
                </div>
              </div>
              <p className="mt-2 line-clamp-2 flex-1 text-xs leading-relaxed text-muted">{entry.description}</p>
              <div className="mt-3 flex items-center gap-1.5">
                {/* Source badge only for the rarer kind — 60× "Built-in" says nothing. */}
                {!isBuiltin && <Badge className="text-accent2">{t('catalog.community')}</Badge>}
                {isInstalled && !isBuiltin && <Badge className="text-success">{t('catalog.added')}</Badge>}
                <span className="ml-auto" onClick={(e) => e.stopPropagation()}>
                  {isInstalled ? (
                    <Link to={`/servers/new?blueprint=${entry.blueprintId}`}>
                      <Button variant="secondary" size="sm">
                        <Plus size={13} />
                        {t('catalog.createServer')}
                      </Button>
                    </Link>
                  ) : isAdmin ? (
                    <Button variant="secondary" size="sm" onClick={() => void add(entry)} loading={addingId === entry.id}>
                      <LibraryBig size={13} />
                      {t('catalog.add')}
                    </Button>
                  ) : null}
                </span>
              </div>
            </div>
          )
        })}
      </div>

      {/* Conversion warnings after adding a community egg */}
      <Modal
        open={warningsModal !== null}
        onClose={() => setWarningsModal(null)}
        title={t('catalog.warningsTitle')}
        footer={
          <Button variant="primary" onClick={() => setWarningsModal(null)}>
            {t('common.close')}
          </Button>
        }
      >
        {warningsModal && (
          <div className="space-y-3 text-sm">
            <p className="text-xs text-muted">{t('catalog.warningsHint', { name: warningsModal.name })}</p>
            <ul className="max-h-64 space-y-1 overflow-y-auto text-xs text-warn">
              {warningsModal.warnings.map((w, i) => (
                <li key={i}>• {w}</li>
              ))}
            </ul>
          </div>
        )}
      </Modal>
    </div>
  )
}
