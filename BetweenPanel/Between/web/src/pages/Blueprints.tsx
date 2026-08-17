import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { Braces, Check, Download, Egg, FileCode2, Link2, Package, Plus, RefreshCw, Search, Trash2, Upload } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import type { Blueprint } from '../api/types.ts'
import { downloadBlob } from '../lib/download.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { useToast } from '../state/ToastContext.tsx'
import { Badge, Button, Chip, EmptyState, Field, IconButton, Input, PageHeader, Spinner, TextArea, cx } from '../components/ui.tsx'
import { Modal, ConfirmModal } from '../components/Modal.tsx'
import { GameIcon } from '../components/GameIcon.tsx'

const TEMPLATE = {
  id: 'my-game',
  name: 'My Game Server',
  category: 'custom',
  description: 'Describe what this blueprint installs and runs.',
  icon: 'gamepad-2',
  color: '#6366f1',
  platforms: ['linux', 'win32'],
  install: [{ type: 'download', url: 'https://example.com/server.jar', dest: 'server.jar' }],
  startCommand: 'java -Xmx{{MEMORY_MB}}M -jar server.jar --port {{SERVER_PORT}}',
  stop: { type: 'command', command: 'stop', timeoutS: 30 },
  variables: [
    { key: 'SERVER_PORT', label: 'Server port', type: 'number', default: 25565, min: 1024, max: 65535, isPort: true },
    { key: 'MEMORY_MB', label: 'Memory (MB)', type: 'number', default: 2048, min: 512, max: 32768 },
  ],
  ports: [{ name: 'game', variable: 'SERVER_PORT', protocol: 'tcp' }],
  query: { type: 'none' },
}

export function Blueprints() {
  const t = useT()
  const toast = useToast()
  const { user } = useAuth()
  const isAdmin = user?.role === 'admin'
  const [blueprints, setBlueprints] = useState<Blueprint[] | null>(null)
  const [platform, setPlatform] = useState('')
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState('all')
  const [detail, setDetail] = useState<Blueprint | null>(null)
  const [showJson, setShowJson] = useState(false)

  // Custom editor state
  const [editorOpen, setEditorOpen] = useState(false)
  const [editorJson, setEditorJson] = useState('')
  const [editorOriginal, setEditorOriginal] = useState('')
  const [editingId, setEditingId] = useState<string | null>(null)
  const [problems, setProblems] = useState<string[] | null>(null)
  const [validOk, setValidOk] = useState(false)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<Blueprint | null>(null)
  const [busy, setBusy] = useState(false)
  const [rescanning, setRescanning] = useState(false)
  const importInput = useRef<HTMLInputElement>(null)

  // Pterodactyl egg import state
  const [eggOpen, setEggOpen] = useState(false)
  const [eggJson, setEggJson] = useState('')
  const [eggUrl, setEggUrl] = useState('')
  const [eggPreview, setEggPreview] = useState<{ blueprint: Blueprint; warnings: string[] } | null>(null)
  const [eggError, setEggError] = useState<string | null>(null)
  const [eggBusy, setEggBusy] = useState(false)
  const eggInput = useRef<HTMLInputElement>(null)

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ blueprints: Blueprint[]; platform: string }>('/api/blueprints')
      setBlueprints(res.blueprints)
      setPlatform(res.platform)
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }, [toast])

  useEffect(() => {
    void load()
  }, [load])

  const categories = useMemo(() => (blueprints ? ['all', ...new Set(blueprints.map((b) => b.category))] : []), [blueprints])

  const filtered = useMemo(() => {
    if (!blueprints) return []
    const q = search.trim().toLowerCase()
    return blueprints.filter((b) => {
      if (category !== 'all' && b.category !== category) return false
      if (!q) return true
      return b.name.toLowerCase().includes(q) || b.description.toLowerCase().includes(q) || b.id.includes(q)
    })
  }, [blueprints, search, category])

  const openCreate = () => {
    setEditingId(null)
    const json = JSON.stringify(TEMPLATE, null, 2)
    setEditorJson(json)
    setEditorOriginal(json)
    setProblems(null)
    setValidOk(false)
    setEditorOpen(true)
  }

  const openEditCustom = (bp: Blueprint) => {
    setEditingId(bp.id)
    const { custom: _custom, ...rest } = bp
    const json = JSON.stringify(rest, null, 2)
    setEditorJson(json)
    setEditorOriginal(json)
    setProblems(null)
    setValidOk(false)
    setEditorOpen(true)
    setDetail(null)
  }

  const exportBlueprint = (bp: Blueprint) => {
    // Same shape the editor works with — the runtime-only `custom` flag stays out.
    const { custom: _custom, ...rest } = bp
    downloadBlob(`${bp.id}.blueprint.json`, JSON.stringify(rest, null, 2))
  }

  // Imported JSON is never saved directly: it lands in the editor modal so the
  // admin reviews it, and the usual validate/save flow applies.
  const importBlueprintFile = async (file: File) => {
    try {
      const parsed = JSON.parse(await file.text()) as unknown
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) throw new Error('not an object')
      setEditingId(null)
      const json = JSON.stringify(parsed, null, 2)
      setEditorJson(json)
      setEditorOriginal(json)
      setProblems(null)
      setValidOk(false)
      setEditorOpen(true)
    } catch {
      toast('error', t('bp.importInvalid'))
    }
  }

  const parseEditor = (): unknown | null => {
    try {
      return JSON.parse(editorJson)
    } catch (err) {
      setProblems([`JSON: ${(err as Error).message}`])
      setValidOk(false)
      return null
    }
  }

  const validate = async () => {
    const bp = parseEditor()
    if (bp === null) return
    try {
      const res = await api.post<{ valid: boolean; problems: string[] }>('/api/blueprints/validate', { blueprint: bp })
      setProblems(res.valid ? [] : res.problems)
      setValidOk(res.valid)
    } catch (err) {
      setProblems([(err as Error).message])
      setValidOk(false)
    }
  }

  const save = async () => {
    const bp = parseEditor()
    if (bp === null) return
    setSaving(true)
    try {
      if (editingId) await api.put(`/api/blueprints/${editingId}`, { blueprint: bp })
      else await api.post('/api/blueprints', { blueprint: bp })
      toast('success', t('toast.saved'))
      setEditorOpen(false)
      await load()
    } catch (err) {
      setProblems([err instanceof ApiError ? err.message : String(err)])
      setValidOk(false)
    } finally {
      setSaving(false)
    }
  }

  const remove = async () => {
    if (!deleteTarget) return
    setBusy(true)
    try {
      await api.del(`/api/blueprints/${deleteTarget.id}`)
      setDeleteTarget(null)
      setDetail(null)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  // Re-read the data/templates drop-in directory (docs/TEMPLATES.md) so new
  // or edited template files show up without a panel restart.
  const rescanTemplates = async () => {
    setRescanning(true)
    try {
      const res = await api.post<{ scan: { loaded: unknown[]; errors: { file: string; problems: string[] }[] } }>('/api/templates/rescan')
      const { loaded, errors } = res.scan
      toast(errors.length > 0 ? 'error' : 'success', t('bp.rescanDone', { loaded: loaded.length, errors: errors.length }))
      for (const e of errors) toast('error', `${e.file}: ${e.problems.join('; ')}`)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setRescanning(false)
    }
  }

  // --- Pterodactyl egg import ------------------------------------------------
  const openEggImport = () => {
    setEggJson('')
    setEggUrl('')
    setEggPreview(null)
    setEggError(null)
    setEggOpen(true)
  }

  const eggFilePicked = async (file: File) => {
    try {
      setEggJson(await file.text())
      setEggPreview(null)
      setEggError(null)
    } catch {
      toast('error', t('eggs.invalidFile'))
    }
  }

  // Server-side conversion returns a preview + warnings; nothing is saved yet.
  // A URL takes precedence over pasted JSON — the server fetches + converts it.
  const previewEgg = async () => {
    const url = eggUrl.trim()
    if (!url && !eggJson.trim()) {
      setEggError(t('eggs.empty'))
      return
    }
    setEggBusy(true)
    setEggError(null)
    try {
      const res = await api.post<{ blueprint: Blueprint; warnings: string[] }>(
        '/api/blueprints/import-egg',
        url ? { url } : { egg: eggJson },
      )
      setEggPreview(res)
    } catch (err) {
      setEggError(err instanceof ApiError ? err.message : String(err))
    } finally {
      setEggBusy(false)
    }
  }

  const saveEgg = async () => {
    if (!eggPreview) return
    setEggBusy(true)
    setEggError(null)
    try {
      await api.post('/api/blueprints', { blueprint: eggPreview.blueprint })
      toast('success', t('eggs.saved'))
      setEggOpen(false)
      await load()
    } catch (err) {
      setEggError(err instanceof ApiError ? err.message : String(err))
    } finally {
      setEggBusy(false)
    }
  }

  const eggHasInstallScript = Boolean(
    eggPreview?.blueprint.install?.some((s) => (s as { type?: string }).type === 'docker-script'),
  )

  return (
    <div className="fade-in-up">
      <PageHeader
        title={t('bp.title')}
        subtitle={t('bp.subtitle')}
        actions={
          isAdmin ? (
            // PageHeader's actions container wraps by itself — no own wrapper.
            <>
              <input
                ref={importInput}
                type="file"
                accept=".json,application/json"
                className="hidden"
                onChange={(e) => {
                  const file = e.target.files?.[0]
                  e.target.value = ''
                  if (file) void importBlueprintFile(file)
                }}
              />
              <Button variant="secondary" onClick={() => importInput.current?.click()}>
                <Upload size={15} />
                {t('bp.import')}
              </Button>
              <Button variant="secondary" onClick={() => void rescanTemplates()} loading={rescanning}>
                <RefreshCw size={15} />
                {t('bp.rescanTemplates')}
              </Button>
              <Button variant="secondary" onClick={openEggImport}>
                <Egg size={15} />
                {t('eggs.import')}
              </Button>
              <Button variant="primary" onClick={openCreate}>
                <Plus size={15} />
                {t('bp.newCustom')}
              </Button>
            </>
          ) : undefined
        }
      />

      <div className="mb-6 flex flex-wrap items-center gap-2">
        <div className="relative w-full max-w-xs">
          <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t('bp.searchPh')}
            className={cx('rounded-full pl-8', blueprints && filtered.length < blueprints.length && 'pr-16')}
          />
          {/* Result counter only while a filter is narrowing the list — folded into the search field. */}
          {blueprints && filtered.length < blueprints.length && (
            <span className="tabular pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-xs text-muted">
              {filtered.length} / {blueprints.length}
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

      {!blueprints && <Spinner />}
      {blueprints && filtered.length === 0 && <EmptyState icon={<Package size={36} />} title={t('servers.noneMatching')} />}

      <div className="stagger grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {filtered.map((bp) => {
          const onHost = bp.platforms.includes(platform)
          return (
            <button
              key={bp.id}
              onClick={() => setDetail(bp)}
              // Dense grid (70+ cards): blur-free glass tint — one backdrop-filter
              // per card would blow the perf budget.
              className="glass-subtle fade-in-up pressable rounded-2xl p-4 text-left hover:border-accent/50 hover:bg-elevated/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            >
              <div className="flex items-center gap-3">
                <GameIcon icon={bp.icon} color={bp.color} boxed size={20} />
                <div className="min-w-0 flex-1">
                  <div className="truncate font-display text-[0.875rem] font-semibold tracking-tight">{bp.name}</div>
                  <div className="text-[0.6875rem] capitalize text-muted">{bp.category}</div>
                </div>
                {bp.custom && <Badge className="text-accent2">{t('bp.custom')}</Badge>}
                {bp.templateFile && <Badge className="text-accent">{t('bp.templateBadge')}</Badge>}
                {/* Compatibility is the default — only the exception (not runnable here) gets a badge. */}
                {!onHost && <Badge className="shrink-0 text-warn">{t('bp.notOnHost')}</Badge>}
              </div>
              <p className="mt-2 line-clamp-2 text-xs leading-relaxed text-muted">{bp.description}</p>
            </button>
          )
        })}
      </div>

      {/* Detail modal */}
      <Modal
        open={detail !== null}
        onClose={() => { setDetail(null); setShowJson(false) }}
        title={
          detail && (
            <span className="flex items-center gap-2.5">
              <GameIcon icon={detail.icon} color={detail.color} size={18} />
              {detail.name}
            </span>
          )
        }
        wide
        footer={
          detail && (
            <div className="flex flex-1 flex-wrap items-center justify-end gap-2">
              {isAdmin && detail.custom && (
                <>
                  <IconButton label={t('common.delete')} onClick={() => setDeleteTarget(detail)} className="text-danger/80 hover:text-danger">
                    <Trash2 size={15} />
                  </IconButton>
                  <Button variant="secondary" onClick={() => openEditCustom(detail)}>
                    {t('common.edit')}
                  </Button>
                </>
              )}
              {(detail.custom || detail.templateFile) && (
                <IconButton label={t('bp.export')} onClick={() => exportBlueprint(detail)}>
                  <Download size={15} />
                </IconButton>
              )}
              <IconButton label={t('bp.viewJson')} variant={showJson ? 'glass' : 'ghost'} onClick={() => setShowJson((s) => !s)}>
                <Braces size={15} />
              </IconButton>
              {detail.platforms.includes(platform) ? (
                <Link to={`/servers/new?blueprint=${detail.id}`}>
                  <Button variant="primary">{t('bp.useBlueprint')}</Button>
                </Link>
              ) : (
                <Badge className="text-warn">{t('bp.notOnHost')}</Badge>
              )}
            </div>
          )
        }
      >
        {detail && !showJson && (
          <div className="space-y-4 text-sm">
            <p className="leading-relaxed text-text/90">{detail.description}</p>
            {detail.templateFile && (
              <p className="glass-subtle flex items-start gap-2 rounded-xl px-3 py-2 text-xs leading-relaxed text-muted">
                <FileCode2 size={14} className="mt-0.5 shrink-0 text-accent" />
                {t('bp.templateFileInfo', { file: detail.templateFile })}
              </p>
            )}
            {detail.notes && <p className="glass-subtle rounded-xl px-3 py-2 text-xs leading-relaxed text-muted">{detail.notes}</p>}
            <div className="grid gap-4 sm:grid-cols-3">
              <div>
                <h4 className="microlabel mb-1.5">{t('bp.platforms')}</h4>
                <div className="flex flex-wrap gap-1">
                  {detail.platforms.map((p) => (
                    <Badge key={p} className={p === platform ? 'text-success' : undefined}>{p}</Badge>
                  ))}
                </div>
              </div>
              <div>
                <h4 className="microlabel mb-1.5">{t('bp.ports')}</h4>
                <div className="flex flex-wrap gap-1">
                  {(detail.ports ?? []).map((p) => (
                    <Badge key={p.name} className="font-mono">{p.name}/{p.protocol}</Badge>
                  ))}
                  {(detail.ports ?? []).length === 0 && <span className="text-xs text-muted">{t('common.none')}</span>}
                </div>
              </div>
              <div>
                <h4 className="microlabel mb-1.5">{t('bp.variables')}</h4>
                <span className="text-xs text-muted">{detail.variables.length}</span>
              </div>
            </div>
            <div>
              <h4 className="microlabel mb-1.5">{t('config.startCmd')}</h4>
              <div className="glass-subtle overflow-x-auto rounded-xl px-3 py-2 font-mono text-xs whitespace-nowrap">{detail.startCommand}</div>
            </div>
            {detail.variables.length > 0 && (
              <div>
                <h4 className="microlabel mb-1.5">{t('bp.variables')}</h4>
                <div className="max-h-52 space-y-1 overflow-y-auto">
                  {detail.variables.map((v) => (
                    <div key={v.key} className="glass-subtle flex items-center gap-2 rounded-lg px-3 py-1.5 text-xs">
                      <span className="font-mono font-semibold">{v.key}</span>
                      <Badge>{v.type}</Badge>
                      {v.isPort && <Badge className="text-accent">port</Badge>}
                      <span className="ml-auto truncate text-muted">{v.label}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
        {detail && showJson && (
          <pre className="glass-subtle max-h-[55vh] overflow-auto rounded-xl p-3 font-mono text-[11px] leading-relaxed">
            {JSON.stringify(detail, null, 2)}
          </pre>
        )}
      </Modal>

      {/* Custom blueprint editor */}
      <Modal
        open={editorOpen}
        onClose={() => setEditorOpen(false)}
        title={editingId ? `${t('bp.editor')}: ${editingId}` : t('bp.editor')}
        wide
        dirty={editorJson !== editorOriginal}
        footer={
          <>
            <Button variant="secondary" onClick={() => void validate()}>
              <Check size={14} />
              {t('bp.validate')}
            </Button>
            <Button variant="primary" onClick={() => void save()} loading={saving}>
              {t('common.save')}
            </Button>
          </>
        }
      >
        <p className="mb-3 text-xs text-muted">{t('bp.editorHint')}</p>
        <TextArea
          value={editorJson}
          onChange={(e) => { setEditorJson(e.target.value); setProblems(null); setValidOk(false) }}
          spellCheck={false}
          className="min-h-[45vh] font-mono text-xs leading-relaxed"
        />
        {validOk && problems?.length === 0 && (
          <p className="mt-2 flex items-center gap-1.5 text-sm text-success">
            <Check size={14} />
            {t('bp.valid')}
          </p>
        )}
        {problems && problems.length > 0 && (
          <ul className="mt-2 space-y-1 text-xs text-danger">
            {problems.map((p, i) => (
              <li key={i}>• {p}</li>
            ))}
          </ul>
        )}
      </Modal>

      {/* Pterodactyl egg import */}
      <Modal
        open={eggOpen}
        onClose={() => setEggOpen(false)}
        title={t('eggs.title')}
        wide
        dirty={eggJson.trim().length > 0 || eggUrl.trim().length > 0}
        footer={
          eggPreview ? (
            <>
              <Button variant="ghost" onClick={() => { setEggPreview(null); setEggError(null) }}>
                {t('common.back')}
              </Button>
              <Button variant="primary" onClick={() => void saveEgg()} loading={eggBusy}>
                {t('eggs.save')}
              </Button>
            </>
          ) : (
            <Button variant="primary" onClick={() => void previewEgg()} loading={eggBusy}>
              {t('eggs.preview')}
            </Button>
          )
        }
      >
        {!eggPreview && (
          <div className="space-y-3">
            <p className="text-xs text-muted">{t('eggs.hint')}</p>
            <Field label={t('eggs.url')} hint={t('eggs.urlHint')}>
              <div className="flex gap-2">
                <Input
                  value={eggUrl}
                  onChange={(e) => { setEggUrl(e.target.value); setEggError(null) }}
                  placeholder={t('eggs.urlPh')}
                  spellCheck={false}
                />
                <Button variant="secondary" onClick={() => void previewEgg()} loading={eggBusy} disabled={!eggUrl.trim()}>
                  <Link2 size={15} />
                  {t('eggs.fetchUrl')}
                </Button>
              </div>
            </Field>
            <input
              ref={eggInput}
              type="file"
              accept="application/json,.json"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0]
                e.target.value = ''
                if (file) void eggFilePicked(file)
              }}
            />
            <Button variant="secondary" onClick={() => eggInput.current?.click()}>
              <Upload size={15} />
              {t('eggs.chooseFile')}
            </Button>
            <Field label={t('eggs.paste')}>
              <TextArea
                value={eggJson}
                onChange={(e) => { setEggJson(e.target.value); setEggError(null) }}
                placeholder={t('eggs.pastePh')}
                spellCheck={false}
                className="min-h-[30vh] font-mono text-xs leading-relaxed"
              />
            </Field>
          </div>
        )}
        {eggPreview && (
          <div className="space-y-4 text-sm">
            <p className="text-xs text-muted">{t('eggs.previewHint')}</p>
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <h4 className="microlabel mb-1.5">{t('common.name')}</h4>
                <div>{eggPreview.blueprint.name}</div>
              </div>
              <div>
                <h4 className="microlabel mb-1.5">{t('eggs.blueprintId')}</h4>
                <div className="font-mono text-xs">{eggPreview.blueprint.id}</div>
              </div>
              <div>
                <h4 className="microlabel mb-1.5">{t('eggs.dockerImage')}</h4>
                <div className="font-mono text-xs">{eggPreview.blueprint.docker?.image ?? '—'}</div>
              </div>
              <div>
                <h4 className="microlabel mb-1.5">{t('bp.variables')}</h4>
                <div>{eggPreview.blueprint.variables.length}</div>
              </div>
              <div>
                <h4 className="microlabel mb-1.5">{t('eggs.installScript')}</h4>
                <div>{eggHasInstallScript ? t('eggs.installScriptYes') : t('eggs.installScriptNone')}</div>
              </div>
            </div>
            <div>
              <h4 className="microlabel mb-1.5">{t('eggs.warnings')}</h4>
              {eggPreview.warnings.length === 0 ? (
                <p className="flex items-center gap-1.5 text-xs text-success">
                  <Check size={14} />
                  {t('eggs.noWarnings')}
                </p>
              ) : (
                <ul className="max-h-52 space-y-1 overflow-y-auto text-xs text-warn">
                  {eggPreview.warnings.map((w, i) => (
                    <li key={i}>• {w}</li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        )}
        {eggError && <p className="mt-3 text-xs text-danger">{eggError}</p>}
      </Modal>

      <ConfirmModal
        open={deleteTarget !== null}
        onClose={() => setDeleteTarget(null)}
        onConfirm={() => void remove()}
        message={t('bp.deleteConfirm')}
        danger
        loading={busy}
        confirmLabel={t('common.delete')}
      />
    </div>
  )
}
