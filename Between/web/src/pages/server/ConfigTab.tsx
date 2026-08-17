import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { FileCog, Lock, RotateCw, Save } from 'lucide-react'
import { api, ApiError } from '../../api/client.ts'
import type { ServerDetail } from '../../api/types.ts'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Badge, Button, Card, CardHeader, Field, Input, Spinner, Toggle } from '../../components/ui.tsx'
import { VariablesForm, type VarValues } from '../../components/VariablesForm.tsx'

// Shapes of GET/PUT /api/servers/:id/configfiles — see server/src/api/servers.ts
interface ManagedKey {
  varKey: string
  configKey: string
  /** Current on-disk value of the config key (null when unreadable/absent). */
  value: string | null
  /** Current blueprint-variable value mapped to this key. */
  varValue: string | number | boolean | null
}

interface ConfigFileInfo {
  path: string
  format: string
  exists: boolean
  template: boolean
  tooLarge?: boolean
  error?: string
  managed: ManagedKey[]
}

/** What the input shows before any edit: on-disk value, else the mapped variable. */
const baseValue = (m: ManagedKey): string => m.value ?? (m.varValue == null ? '' : String(m.varValue))

export function ConfigTab() {
  const { server, patchServer, can } = useServer()
  const t = useT()
  const toast = useToast()
  const [values, setValues] = useState<VarValues>({ ...server.variables })
  const [override, setOverride] = useState(server.startCommandOverride ?? '')
  const [saving, setSaving] = useState(false)

  const canRead = can('server.files.read')
  const canWrite = can('server.config')
  const [files, setFiles] = useState<ConfigFileInfo[] | null>(null)
  const [filesError, setFilesError] = useState<string | null>(null)
  // Unsaved input per file path → configKey → value, overlaid on fetched values.
  const [edits, setEdits] = useState<Record<string, Record<string, string>>>({})
  const [savingPath, setSavingPath] = useState<string | null>(null)

  const loadFiles = useCallback(async () => {
    setFilesError(null)
    try {
      const res = await api.get<{ files: ConfigFileInfo[] }>(`/api/servers/${server.id}/configfiles`)
      setFiles(res.files)
    } catch (err) {
      const msg = err instanceof ApiError ? err.message : String(err)
      setFilesError(msg)
      toast('error', msg)
    }
  }, [server.id, toast])

  useEffect(() => {
    if (canRead) void loadFiles()
  }, [canRead, loadFiles])

  const save = async () => {
    setSaving(true)
    try {
      const res = await api.put<{ server: ServerDetail }>(`/api/servers/${server.id}/variables`, { values })
      const trimmed = override.trim()
      if ((trimmed || null) !== (server.startCommandOverride ?? null)) {
        await api.patch(`/api/servers/${server.id}`, { startCommandOverride: trimmed || null })
      }
      patchServer({ ...res.server, startCommandOverride: trimmed || null })
      toast('success', t('toast.saved'))
      // A variable save re-syncs mapped keys on disk — refresh the live editor.
      if (canRead) void loadFiles()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSaving(false)
    }
  }

  /** Only keys whose edited value differs from what the file currently holds. */
  const changedFor = (file: ConfigFileInfo): Record<string, string> => {
    const fileEdits = edits[file.path]
    if (!fileEdits) return {}
    const out: Record<string, string> = {}
    for (const m of file.managed) {
      const edited = fileEdits[m.configKey]
      if (edited !== undefined && edited !== baseValue(m)) out[m.configKey] = edited
    }
    return out
  }

  const saveFile = async (file: ConfigFileInfo) => {
    const changed = changedFor(file)
    if (Object.keys(changed).length === 0) return
    setSavingPath(file.path)
    try {
      await api.put(`/api/servers/${server.id}/configfiles`, { path: file.path, values: changed })
      setEdits((prev) => {
        const next = { ...prev }
        delete next[file.path]
        return next
      })
      toast('success', t('toast.saved'))
      await loadFiles()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSavingPath(null)
    }
  }

  const setKeyValue = (path: string, configKey: string, value: string) =>
    setEdits((prev) => ({ ...prev, [path]: { ...prev[path], [configKey]: value } }))

  const renderKey = (file: ConfigFileInfo, m: ManagedKey) => {
    const base = baseValue(m)
    const current = edits[file.path]?.[m.configKey] ?? base
    const looksBoolean = base === 'true' || base === 'false'
    return (
      <Field
        key={m.configKey}
        label={
          <span className="normal-case tracking-normal">
            <span className="font-mono">{m.configKey}</span>
            <span className="ml-1.5 text-[0.625rem] font-normal text-muted/70" title={t('config.mappedTo')}>
              {m.varKey}
            </span>
          </span>
        }
      >
        {looksBoolean ? (
          <Toggle
            checked={current === 'true'}
            onChange={(v) => setKeyValue(file.path, m.configKey, v ? 'true' : 'false')}
            label={current}
            disabled={!canWrite}
          />
        ) : (
          <Input
            value={current}
            onChange={(e) => setKeyValue(file.path, m.configKey, e.target.value)}
            className="font-mono text-xs"
            readOnly={!canWrite}
          />
        )}
      </Field>
    )
  }

  const renderFile = (file: ConfigFileInfo) => {
    const editable = file.exists && !file.tooLarge && !file.error && file.managed.length > 0
    const dirtyCount = Object.keys(changedFor(file)).length
    return (
      <div key={file.path} className="space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-3">
          <FileCog size={15} className="shrink-0 text-accent" />
          <span className="font-mono text-[0.8125rem] font-medium">{file.path}</span>
          <Badge>{file.format}</Badge>
          {canWrite && editable && (
            <Button
              size="sm"
              variant="primary"
              className="ml-auto"
              disabled={dirtyCount === 0}
              loading={savingPath === file.path}
              onClick={() => void saveFile(file)}
            >
              <Save size={12} />
              {t('config.saveFile')}
            </Button>
          )}
        </div>
        {!file.exists ? (
          <p className="text-xs text-muted">{t('config.notCreated')}</p>
        ) : file.tooLarge ? (
          <p className="text-xs text-muted">{t('config.tooLarge')}</p>
        ) : file.error ? (
          <p className="text-xs text-danger">{file.error}</p>
        ) : file.format === 'raw' ? (
          <p className="text-xs text-muted">
            {t('config.rawInFiles')}{' '}
            <Link to={`/servers/${server.id}/files`} className="text-accent hover:underline">
              {t('config.openFiles')}
            </Link>
          </p>
        ) : file.managed.length === 0 ? (
          <p className="text-xs text-muted">{t('config.noManagedKeys')}</p>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">{file.managed.map((m) => renderKey(file, m))}</div>
        )}
      </div>
    )
  }

  if (!server.blueprint) return null
  const bp = server.blueprint

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title={t('config.title')}
          subtitle={t('config.subtitle')}
          actions={
            // Header-embedded card actions are size="sm" everywhere (see DESIGN.md).
            <Button variant="primary" size="sm" onClick={() => void save()} loading={saving}>
              <Save size={13} />
              {t('config.saveVars')}
            </Button>
          }
        />
        <div className="p-4">
          <VariablesForm blueprint={bp} values={values} onChange={setValues} />
        </div>
      </Card>

      <Card>
        <CardHeader title={t('config.startCmd')} />
        <div className="space-y-4 p-4">
          {/* Read-only effective command: labeled + deliberately NOT styled
              like an input (flat elevated tint, no border, lock glyph) so it
              can't be confused with the editable override below. */}
          <div>
            <span className="microlabel mb-1.5 block">{t('config.blueprintCmd')}</span>
            <div className="flex items-start gap-2.5 rounded-xl bg-elevated/40 px-3.5 py-2.5 font-mono text-xs text-muted">
              <span className="min-w-0 flex-1 break-all">{bp.startCommand}</span>
              <Lock size={12} aria-hidden className="mt-0.5 shrink-0 text-muted/60" />
            </div>
          </div>
          <Field label={t('config.startCmdOverride')} hint={t('config.overridePh')}>
            <Input
              value={override}
              onChange={(e) => setOverride(e.target.value)}
              placeholder={bp.startCommand}
              className="font-mono text-xs"
            />
          </Field>
        </div>
      </Card>

      {canRead && (
        <Card>
          <CardHeader title={t('config.filesLive')} subtitle={t('config.onDiskHint')} />
          {filesError !== null ? (
            <div className="flex flex-col items-start gap-3 p-4">
              <p className="text-sm text-danger">{t('config.loadFailed')}</p>
              <Button size="sm" variant="secondary" onClick={() => void loadFiles()}>
                <RotateCw size={12} />
                {t('config.reload')}
              </Button>
            </div>
          ) : !files ? (
            <Spinner label={t('common.loading')} />
          ) : files.length === 0 ? (
            <p className="p-4 text-xs text-muted">{t('config.noFiles')}</p>
          ) : (
            <div className="divide-y divide-line/60">{files.map(renderFile)}</div>
          )}
        </Card>
      )}
    </div>
  )
}
