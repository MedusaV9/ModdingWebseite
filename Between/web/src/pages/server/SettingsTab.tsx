import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { AlertTriangle, Boxes, Download, RefreshCcw, Save, Trash2 } from 'lucide-react'
import { api, ApiError } from '../../api/client.ts'
import type { DockerStatus, ServerDetail, ServerRuntime, SteamStatus } from '../../api/types.ts'
import { useServer } from './ServerDetail.tsx'
import { useAuth } from '../../state/AuthContext.tsx'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Button, Card, CardHeader, Checkbox, Field, Input, TextArea, Toggle } from '../../components/ui.tsx'
import { ConfirmModal, Modal } from '../../components/Modal.tsx'
import { DockerSettingsFields, RuntimePicker, dockerFormToPayload, emptyDockerForm, type DockerFormValues } from '../../components/RuntimePicker.tsx'

export function SettingsTab() {
  const { server, patchServer, can } = useServer()
  const { user } = useAuth()
  const t = useT()
  const toast = useToast()
  const navigate = useNavigate()

  const [name, setName] = useState(server.name)
  const [tags, setTags] = useState(server.tags.join(', '))
  const [notes, setNotes] = useState(server.notes)
  const [autoStart, setAutoStart] = useState(server.autoStart)
  const [steamAutoUpdate, setSteamAutoUpdate] = useState(Boolean(server.steamAutoUpdate))
  const [useSteamLogin, setUseSteamLogin] = useState(Boolean(server.useSteamLogin))
  const [steamLoginConfigured, setSteamLoginConfigured] = useState(false)
  const [restartEnabled, setRestartEnabled] = useState(server.restartPolicy.enabled)
  const [maxRetries, setMaxRetries] = useState(server.restartPolicy.maxRetries)
  const [backoffS, setBackoffS] = useState(server.restartPolicy.backoffS)
  const [backupRetention, setBackupRetention] = useState(server.backupRetention == null ? '' : String(server.backupRetention))
  const [suspended, setSuspended] = useState(server.suspended)
  const [saving, setSaving] = useState(false)

  const [runtime, setRuntime] = useState<ServerRuntime>(server.runtime)
  const [dockerForm, setDockerForm] = useState<DockerFormValues>(emptyDockerForm(server.docker))
  const [dockerStatus, setDockerStatus] = useState<DockerStatus | null>(null)
  const [runtimeSaving, setRuntimeSaving] = useState(false)
  const [pulling, setPulling] = useState(false)

  useEffect(() => {
    void api.get<DockerStatus>('/api/docker/status').then(setDockerStatus).catch(() => {})
    void api.get<SteamStatus>('/api/steam/status').then((res) => setSteamLoginConfigured(Boolean(res.loginConfigured))).catch(() => {})
  }, [])

  const [reinstallOpen, setReinstallOpen] = useState(false)
  const [steamBusy, setSteamBusy] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [deleteBackups, setDeleteBackups] = useState(false)
  const [deleting, setDeleting] = useState(false)

  const isAdmin = user?.role === 'admin'
  // Remote servers: settings PATCH / runtime / reinstall are gateway-blocked
  // in this round — the management cards give way to a quiet notice. Delete
  // DOES work through the gateway, so the danger zone stays.
  const remote = server.nodeId != null
  const usesSteam = Boolean(
    server.blueprint?.hasSteamcmd ?? server.blueprint?.install?.some((s) => (s as { type?: string }).type === 'steamcmd'),
  )

  const save = async () => {
    setSaving(true)
    try {
      const res = await api.patch<{ server: ServerDetail }>(`/api/servers/${server.id}`, {
        name,
        tags: tags.split(',').map((s) => s.trim()).filter(Boolean),
        notes,
        autoStart,
        steamAutoUpdate,
        useSteamLogin,
        suspended,
        restartPolicy: { enabled: restartEnabled, maxRetries, backoffS },
        backupRetention: backupRetention.trim() === '' ? null : Number(backupRetention),
      })
      patchServer(res.server)
      toast('success', t('toast.saved'))
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSaving(false)
    }
  }

  const reinstall = async () => {
    try {
      await api.post(`/api/servers/${server.id}/reinstall`)
      setReinstallOpen(false)
      navigate(`/servers/${server.id}`)
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    }
  }

  const steamUpdate = async () => {
    setSteamBusy(true)
    try {
      await api.post(`/api/servers/${server.id}/steam-update`)
      navigate(`/servers/${server.id}`)
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSteamBusy(false)
    }
  }

  const remove = async () => {
    setDeleting(true)
    try {
      await api.del(`/api/servers/${server.id}`, { deleteBackups })
      navigate('/servers')
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
      setDeleting(false)
    }
  }

  const serverStopped = ['offline', 'crashed', 'install_failed'].includes(server.status)

  const saveRuntime = async () => {
    setRuntimeSaving(true)
    try {
      const res = await api.patch<{ server: ServerDetail }>(`/api/servers/${server.id}`, {
        runtime,
        docker: dockerFormToPayload(dockerForm),
      })
      patchServer(res.server)
      setDockerForm(emptyDockerForm(res.server.docker))
      toast('success', t('toast.saved'))
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setRuntimeSaving(false)
    }
  }

  // Safe while running or stopped — progress streams into the Console tab.
  const pullImage = async () => {
    setPulling(true)
    try {
      await api.post(`/api/servers/${server.id}/docker/pull`)
      toast('success', t('runtime.pullStarted'))
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setPulling(false)
    }
  }

  if (remote) {
    return (
      <div className="space-y-4">
        <Card className="p-5">
          <div className="flex items-start gap-3">
            <span className="glass-subtle shrink-0 rounded-xl p-2.5 text-accent">
              <Boxes size={18} />
            </span>
            <div className="min-w-0">
              <h3 className="font-display text-[0.9375rem] font-semibold tracking-tight">
                {t('remote.managedOnNode', { name: server.nodeName ?? '' })}
              </h3>
              <p className="mt-1 text-sm leading-relaxed text-muted">{t('remote.settingsNotice')}</p>
            </div>
          </div>
        </Card>

        {can('owner') && (
          <Card className="border-danger/40 bg-danger/[0.07]">
            <CardHeader title={<span className="flex items-center gap-2 text-danger"><AlertTriangle size={15} />{t('sset.danger')}</span>} />
            <div className="p-4">
              <Button variant="danger" onClick={() => setDeleteOpen(true)}>
                <Trash2 size={14} />
                {t('sset.deleteServer')}
              </Button>
            </div>
          </Card>
        )}

        <Modal
          open={deleteOpen}
          onClose={() => setDeleteOpen(false)}
          title={t('confirm.title')}
          footer={
            <>
              <Button variant="ghost" onClick={() => setDeleteOpen(false)}>
                {t('common.cancel')}
              </Button>
              <Button variant="danger" onClick={() => void remove()} loading={deleting}>
                <Trash2 size={14} />
                {t('sset.deleteServer')}
              </Button>
            </>
          }
        >
          <p className="mb-4 text-sm leading-relaxed text-text/90">{t('sset.deleteConfirm', { name: server.name })}</p>
          <Checkbox checked={deleteBackups} onChange={(e) => setDeleteBackups(e.target.checked)} label={t('sset.deleteBackupsToo')} />
        </Modal>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader
          title={t('sset.general')}
          actions={
            // Header-embedded card actions are size="sm" everywhere (see DESIGN.md).
            <Button variant="primary" size="sm" onClick={() => void save()} loading={saving}>
              <Save size={13} />
              {t('common.save')}
            </Button>
          }
        />
        <div className="grid gap-4 p-4 sm:grid-cols-2">
          <Field label={t('sset.name')}>
            <Input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} />
          </Field>
          <Field label={t('sset.tags')}>
            <Input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="e.g. survival, modded" />
          </Field>
          <div className="sm:col-span-2">
            <Field label={t('sset.notes')}>
              <TextArea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} maxLength={2000} />
            </Field>
          </div>
          <div className="space-y-3 sm:col-span-2">
            <Toggle checked={autoStart} onChange={setAutoStart} label={t('sset.autostart')} />
            {usesSteam && (
              <div>
                <Toggle checked={steamAutoUpdate} onChange={setSteamAutoUpdate} label={t('sset.steamAutoUpdate')} />
                <p className="ml-[3.625rem] mt-1 text-xs leading-snug text-muted">{t('sset.steamAutoUpdateHint')}</p>
              </div>
            )}
            {/* Games that cannot be downloaded anonymously always use the
                panel account — a toggle would be a lie, so show a note. */}
            {usesSteam && server.blueprint?.requiresSteamLogin && (
              <p className="text-xs leading-snug text-muted">{t('sset.steamLoginRequired')}</p>
            )}
            {usesSteam && !server.blueprint?.requiresSteamLogin && (steamLoginConfigured || useSteamLogin) && (
              <div>
                <Toggle checked={useSteamLogin} onChange={setUseSteamLogin} label={t('sset.useSteamLogin')} />
                <p className="ml-[3.625rem] mt-1 text-xs leading-snug text-muted">{t('sset.useSteamLoginHint')}</p>
              </div>
            )}
            {isAdmin && <Toggle checked={suspended} onChange={setSuspended} label={t('sset.suspended')} />}
          </div>
          {/* Crash auto-restart lives INSIDE the General card: the header Save
              commits restartPolicy too, so a separate card would lie about the
              Save button's scope (one card, one Save). */}
          <div className="space-y-4 border-t border-line/60 pt-4 sm:col-span-2">
            <span className="microlabel block">{t('sset.restart')}</span>
            <Toggle checked={restartEnabled} onChange={setRestartEnabled} label={t('sset.restartEnabled')} />
            {restartEnabled && (
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label={t('sset.maxRetries')}>
                  <Input type="number" min={0} max={20} value={String(maxRetries)} onChange={(e) => setMaxRetries(Number(e.target.value) || 0)} />
                </Field>
                <Field label={t('sset.backoff')}>
                  <Input type="number" min={1} max={600} value={String(backoffS)} onChange={(e) => setBackoffS(Number(e.target.value) || 1)} />
                </Field>
              </div>
            )}
          </div>
          {/* Backup retention lives in the General card because its header Save
              is the request that actually persists it (one card, one Save). */}
          <div className="space-y-4 border-t border-line/60 pt-4 sm:col-span-2">
            <span className="microlabel block">{t('settings.backups')}</span>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label={t('sset.backupRetention')} hint={t('sset.backupRetentionHint')}>
                <Input type="number" min={0} max={50} value={backupRetention} onChange={(e) => setBackupRetention(e.target.value)} />
              </Field>
            </div>
          </div>
        </div>
      </Card>

      <Card>
        <CardHeader
          title={t('runtime.title')}
          subtitle={runtime === 'docker' ? (server.dockerImageEffective ?? undefined) : undefined}
          actions={
            <Button variant="primary" size="sm" onClick={() => void saveRuntime()} loading={runtimeSaving}>
              <Save size={13} />
              {t('common.save')}
            </Button>
          }
        />
        <div className="space-y-4 p-4">
          <RuntimePicker
            runtime={runtime}
            onRuntimeChange={setRuntime}
            dockerAvailable={Boolean(dockerStatus?.available) && Boolean(server.blueprint?.platforms?.includes('linux'))}
            dockerVersion={dockerStatus?.version}
            disabled={!serverStopped}
            disabledHint={!serverStopped ? t('runtime.switchHint') : undefined}
          />
          {runtime === 'docker' && (
            <DockerSettingsFields blueprint={server.blueprint} values={dockerForm} onChange={setDockerForm} />
          )}
          {runtime === 'docker' && Boolean(dockerStatus?.available) && (
            <div className="flex flex-wrap items-center gap-3 border-t border-line/60 pt-4">
              <Button variant="secondary" onClick={() => void pullImage()} loading={pulling}>
                <Download size={14} />
                {t('runtime.pullImage')}
              </Button>
              <p className="text-xs text-muted">{t('runtime.pullHint')}</p>
            </div>
          )}
        </div>
      </Card>

      <Card>
        <CardHeader title={t('sset.reinstall')} subtitle={t('sset.reinstallHint')} />
        <div className="flex flex-wrap gap-2 p-4">
          <Button variant="secondary" onClick={() => setReinstallOpen(true)} disabled={server.status !== 'offline' && server.status !== 'install_failed' && server.status !== 'crashed'}>
            <RefreshCcw size={14} />
            {t('sset.reinstall')}
          </Button>
          {usesSteam && (
            <Button variant="secondary" onClick={() => void steamUpdate()} loading={steamBusy} disabled={server.status !== 'offline' && server.status !== 'crashed'} title={t('sset.steamUpdateHint')}>
              <RefreshCcw size={14} />
              {t('sset.steamUpdate')}
            </Button>
          )}
        </div>
      </Card>

      {/* Deleting is restricted to the owner/admin on the API — hide it for subusers */}
      {can('owner') && (
        // Danger-tinted glass: overriding the background keeps the blur,
        // hairline and specular edge from .glass while adding the red wash.
        <Card className="border-danger/40 bg-danger/[0.07]">
          <CardHeader title={<span className="flex items-center gap-2 text-danger"><AlertTriangle size={15} />{t('sset.danger')}</span>} />
          <div className="p-4">
            <Button variant="danger" onClick={() => setDeleteOpen(true)}>
              <Trash2 size={14} />
              {t('sset.deleteServer')}
            </Button>
          </div>
        </Card>
      )}

      <ConfirmModal
        open={reinstallOpen}
        onClose={() => setReinstallOpen(false)}
        onConfirm={() => void reinstall()}
        message={t('sset.reinstallConfirm')}
        confirmLabel={t('sset.reinstall')}
      />

      <Modal
        open={deleteOpen}
        onClose={() => setDeleteOpen(false)}
        title={t('confirm.title')}
        footer={
          <>
            <Button variant="ghost" onClick={() => setDeleteOpen(false)}>
              {t('common.cancel')}
            </Button>
            <Button variant="danger" onClick={() => void remove()} loading={deleting}>
              <Trash2 size={14} />
              {t('sset.deleteServer')}
            </Button>
          </>
        }
      >
        <p className="mb-4 text-sm leading-relaxed text-text/90">{t('sset.deleteConfirm', { name: server.name })}</p>
        <Checkbox checked={deleteBackups} onChange={(e) => setDeleteBackups(e.target.checked)} label={t('sset.deleteBackupsToo')} />
      </Modal>
    </div>
  )
}
