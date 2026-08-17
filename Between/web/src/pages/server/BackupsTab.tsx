import { useCallback, useEffect, useState } from 'react'
import { Archive, Download, Lock, LockOpen, Plus, RotateCcw, Trash2 } from 'lucide-react'
import { api, ApiError } from '../../api/client.ts'
import type { BackupInfo } from '../../api/types.ts'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Badge, Button, Card, Checkbox, EmptyState, Field, IconButton, Input, Spinner } from '../../components/ui.tsx'
import { Modal, ConfirmModal } from '../../components/Modal.tsx'
import { formatBytes, formatDateTime } from '../../lib/format.ts'

export function BackupsTab() {
  const { server } = useServer()
  const t = useT()
  const toast = useToast()
  // Lock/download are gateway-blocked for remote servers this round —
  // hidden rather than left to 400. Create/restore/delete work transparently.
  const remote = server.nodeId != null
  const [backups, setBackups] = useState<BackupInfo[] | null>(null)
  const [retention, setRetention] = useState(0)
  const [createOpen, setCreateOpen] = useState(false)
  const [note, setNote] = useState('')
  const [creating, setCreating] = useState(false)
  const [restoreTarget, setRestoreTarget] = useState<BackupInfo | null>(null)
  const [wipe, setWipe] = useState(false)
  const [safety, setSafety] = useState(true)
  const [restoring, setRestoring] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<BackupInfo | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ backups: BackupInfo[]; retention?: number }>(`/api/servers/${server.id}/backups`)
      setBackups(res.backups)
      setRetention(res.retention ?? 0)
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }, [server.id, toast])

  useEffect(() => {
    void load()
  }, [load])

  const create = async () => {
    setCreating(true)
    try {
      await api.post(`/api/servers/${server.id}/backups`, { note })
      setCreateOpen(false)
      setNote('')
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setCreating(false)
    }
  }

  const restore = async () => {
    if (!restoreTarget) return
    setRestoring(true)
    try {
      await api.post(`/api/servers/${server.id}/backups/${restoreTarget.id}/restore`, { wipe, safetyBackup: safety })
      toast('success', t('common.saved'))
      setRestoreTarget(null)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setRestoring(false)
    }
  }

  const toggleLock = async (backup: BackupInfo) => {
    setBusy(true)
    try {
      await api.post(`/api/servers/${server.id}/backups/${backup.id}/lock`, { locked: !backup.locked })
      await load()
    } catch (err) {
      toast('error', (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    if (!deleteTarget) return
    setBusy(true)
    try {
      await api.del(`/api/servers/${server.id}/backups/${deleteTarget.id}`)
      setDeleteTarget(null)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-end gap-3">
        {/* Effective retention (per-server override or panel default); 0 = unlimited. */}
        {retention > 0 && <p className="mr-auto text-xs text-muted">{t('backups.retentionActive', { n: retention })}</p>}
        <Button variant="primary" onClick={() => setCreateOpen(true)}>
          <Plus size={14} />
          {t('backups.create')}
        </Button>
      </div>

      <Card className="overflow-hidden">
        {!backups && <Spinner />}
        {backups && backups.length === 0 && <EmptyState icon={<Archive size={36} />} title={t('backups.empty')} />}
        {backups && backups.length > 0 && (
          <div className="divide-y divide-line/50">
            {backups.map((backup) => (
              <div key={backup.id} className="flex flex-wrap items-center gap-3 px-4 py-3 transition-colors hover:bg-elevated/40">
                <Archive size={17} className="shrink-0 text-accent/80" />
                <div className="min-w-0 flex-1 basis-52">
                  {/* The human note is the title; without one, a humanized
                      date stands in. The raw filename is demoted to meta. */}
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="truncate font-semibold">
                      {backup.note || t('backups.fromDate', { date: formatDateTime(backup.createdAt) })}
                    </span>
                    {backup.locked && <Badge className="border-warn/30 bg-warn/10 text-warn"><Lock size={10} className="mr-1" />{t('backups.locked')}</Badge>}
                    {backup.auto && <Badge>{t('backups.auto')}</Badge>}
                  </div>
                  <div className="tabular mt-0.5 text-xs text-muted">
                    {backup.note ? `${formatDateTime(backup.createdAt)} · ${formatBytes(backup.sizeBytes)} · ` : `${formatBytes(backup.sizeBytes)} · `}
                    <span className="font-mono">{backup.fileName}</span>
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <Button size="sm" variant="secondary" onClick={() => setRestoreTarget(backup)}>
                    <RotateCcw size={12} />
                    {t('backups.restore')}
                  </Button>
                  {!remote && (
                    <IconButton size="sm" disabled={busy} onClick={() => void toggleLock(backup)} label={backup.locked ? t('backups.unlock') : t('backups.lock')}>
                      {backup.locked ? <LockOpen size={13} /> : <Lock size={13} />}
                    </IconButton>
                  )}
                  {!remote && (
                    <a href={`/api/servers/${server.id}/backups/${backup.id}/download`} download>
                      <IconButton size="sm" label={t('common.download')}>
                        <Download size={13} />
                      </IconButton>
                    </a>
                  )}
                  {/* Hairline sets the destructive action apart from the cluster. */}
                  <span aria-hidden className="mx-1 h-4 w-px shrink-0 bg-line/70" />
                  <IconButton size="sm" disabled={backup.locked} onClick={() => setDeleteTarget(backup)} label={t('common.delete')} className="hover:bg-danger/15 hover:text-danger">
                    <Trash2 size={13} className="text-danger/80" />
                  </IconButton>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Modal
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        title={t('backups.create')}
        footer={
          <Button variant="primary" onClick={() => void create()} loading={creating}>
            {t('common.create')}
          </Button>
        }
      >
        <Field label={t('backups.note')} hint={creating ? t('backups.busy') : undefined}>
          <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder={t('backups.notePh')} autoFocus maxLength={120} />
        </Field>
      </Modal>

      <Modal
        open={restoreTarget !== null}
        onClose={() => setRestoreTarget(null)}
        title={`${t('backups.restore')}: ${restoreTarget?.fileName ?? ''}`}
        footer={
          <>
            <Button variant="ghost" onClick={() => setRestoreTarget(null)}>
              {t('common.cancel')}
            </Button>
            <Button variant="danger" onClick={() => void restore()} loading={restoring}>
              {t('backups.restore')}
            </Button>
          </>
        }
      >
        <p className="mb-4 text-sm leading-relaxed text-text/90">{t('backups.restoreConfirm')}</p>
        <div className="space-y-3">
          <Checkbox checked={safety} onChange={(e) => setSafety(e.target.checked)} label={t('backups.safety')} />
          <Checkbox checked={wipe} onChange={(e) => setWipe(e.target.checked)} label={t('backups.wipe')} />
        </div>
      </Modal>

      <ConfirmModal
        open={deleteTarget !== null}
        onClose={() => setDeleteTarget(null)}
        onConfirm={() => void remove()}
        message={t('backups.deleteConfirm')}
        danger
        loading={busy}
        confirmLabel={t('common.delete')}
      />
    </div>
  )
}
