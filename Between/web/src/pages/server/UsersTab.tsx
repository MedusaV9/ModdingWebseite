import { useCallback, useEffect, useState } from 'react'
import { Plus, Trash2, UsersRound } from 'lucide-react'
import { api, ApiError } from '../../api/client.ts'
import type { SubuserInfo } from '../../api/types.ts'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Button, Card, EmptyState, Field, IconButton, Input, Spinner, cx } from '../../components/ui.tsx'
import { Modal, ConfirmModal } from '../../components/Modal.tsx'

function PermissionPicker({
  available,
  value,
  onChange,
}: {
  available: string[]
  value: string[]
  onChange: (next: string[]) => void
}) {
  const toggle = (perm: string) => {
    onChange(value.includes(perm) ? value.filter((p) => p !== perm) : [...value, perm])
  }
  return (
    <div className="grid grid-cols-2 gap-1.5">
      {available.map((perm) => (
        <button
          key={perm}
          type="button"
          onClick={() => toggle(perm)}
          className={cx(
            'pressable rounded-lg border px-2.5 py-1.5 text-left font-mono text-[11px]',
            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
            value.includes(perm)
              ? 'sheen border-accent/50 bg-accent/15 text-accent'
              : 'border-line text-muted hover:border-accent/30 hover:text-text',
          )}
        >
          {perm}
        </button>
      ))}
    </div>
  )
}

export function UsersTab() {
  const { server } = useServer()
  const t = useT()
  const toast = useToast()
  const [subusers, setSubusers] = useState<SubuserInfo[] | null>(null)
  const [available, setAvailable] = useState<string[]>([])
  const [addOpen, setAddOpen] = useState(false)
  const [editing, setEditing] = useState<SubuserInfo | null>(null)
  const [username, setUsername] = useState('')
  const [perms, setPerms] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const [removeTarget, setRemoveTarget] = useState<SubuserInfo | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ subusers: SubuserInfo[]; availablePermissions: string[] }>(`/api/servers/${server.id}/subusers`)
      setSubusers(res.subusers)
      setAvailable(res.availablePermissions)
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }, [server.id, toast])

  useEffect(() => {
    void load()
  }, [load])

  const openAdd = () => {
    setEditing(null)
    setUsername('')
    setPerms(['server.view', 'server.console', 'server.command', 'server.power'])
    setAddOpen(true)
  }

  const openEdit = (sub: SubuserInfo) => {
    setEditing(sub)
    setUsername(sub.username)
    setPerms(sub.permissions)
    setAddOpen(true)
  }

  const save = async () => {
    setSaving(true)
    try {
      if (editing) await api.patch(`/api/servers/${server.id}/subusers/${editing.id}`, { permissions: perms })
      else await api.post(`/api/servers/${server.id}/subusers`, { username, permissions: perms })
      setAddOpen(false)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSaving(false)
    }
  }

  const remove = async () => {
    if (!removeTarget) return
    setBusy(true)
    try {
      await api.del(`/api/servers/${server.id}/subusers/${removeTarget.id}`)
      setRemoveTarget(null)
      await load()
    } catch (err) {
      toast('error', (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <Button variant="primary" onClick={openAdd}>
          <Plus size={14} />
          {t('subusers.add')}
        </Button>
      </div>

      <Card className="overflow-hidden">
        {!subusers && <Spinner />}
        {subusers && subusers.length === 0 && <EmptyState icon={<UsersRound size={36} />} title={t('subusers.empty')} />}
        {subusers && subusers.length > 0 && (
          <div className="divide-y divide-line/50">
            {subusers.map((sub) => (
              <div key={sub.id} className="flex flex-wrap items-center gap-3 px-4 py-3 transition-colors hover:bg-elevated/40">
                <span className="sheen inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent/15 font-display text-sm font-bold text-accent">
                  {sub.username.slice(0, 1).toUpperCase()}
                </span>
                <button
                  onClick={() => openEdit(sub)}
                  className="min-w-0 flex-1 basis-40 rounded-lg text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
                >
                  <div className="font-semibold">{sub.username}</div>
                  <div className="mt-0.5 truncate font-mono text-[11px] text-muted">
                    {sub.permissions.length} {t('subusers.permissions').toLowerCase()}: {sub.permissions.join(', ')}
                  </div>
                </button>
                <IconButton size="sm" onClick={() => setRemoveTarget(sub)} label={t('common.delete')} className="hover:bg-danger/15 hover:text-danger">
                  <Trash2 size={13} className="text-danger/80" />
                </IconButton>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Modal
        open={addOpen}
        onClose={() => setAddOpen(false)}
        title={editing ? `${t('common.edit')}: ${editing.username}` : t('subusers.add')}
        footer={
          <Button variant="primary" onClick={() => void save()} loading={saving} disabled={!editing && !username.trim()}>
            {t('common.save')}
          </Button>
        }
      >
        <div className="space-y-4">
          {!editing && (
            <Field label={t('subusers.username')}>
              <Input value={username} onChange={(e) => setUsername(e.target.value)} autoFocus />
            </Field>
          )}
          <Field label={t('subusers.permissions')}>
            <PermissionPicker available={available} value={perms} onChange={setPerms} />
          </Field>
        </div>
      </Modal>

      <ConfirmModal
        open={removeTarget !== null}
        onClose={() => setRemoveTarget(null)}
        onConfirm={() => void remove()}
        message={t('subusers.removeConfirm')}
        danger
        loading={busy}
        confirmLabel={t('common.delete')}
      />
    </div>
  )
}
