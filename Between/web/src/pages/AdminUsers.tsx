import { useCallback, useEffect, useState } from 'react'
import { KeyRound, Plus, ShieldCheck, Trash2, UserX } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import type { SafeUser } from '../api/types.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { useToast } from '../state/ToastContext.tsx'
import { Badge, Button, Card, Field, IconButton, Input, PageHeader, Select, Spinner } from '../components/ui.tsx'
import { Modal, ConfirmModal } from '../components/Modal.tsx'
import { formatDateTime } from '../lib/format.ts'

export function AdminUsers() {
  const t = useT()
  const toast = useToast()
  const { user: me } = useAuth()
  const [users, setUsers] = useState<SafeUser[] | null>(null)

  const [createOpen, setCreateOpen] = useState(false)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [role, setRole] = useState<'user' | 'admin'>('user')
  const [saving, setSaving] = useState(false)

  const [resetTarget, setResetTarget] = useState<SafeUser | null>(null)
  const [newPassword, setNewPassword] = useState('')
  const [deleteTarget, setDeleteTarget] = useState<SafeUser | null>(null)
  const [roleChange, setRoleChange] = useState<{ target: SafeUser; role: 'user' | 'admin' } | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ users: SafeUser[] }>('/api/users')
      setUsers(res.users)
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }, [toast])

  useEffect(() => {
    void load()
  }, [load])

  const create = async () => {
    setSaving(true)
    try {
      await api.post('/api/users', { username, password, role })
      setCreateOpen(false)
      setUsername('')
      setPassword('')
      setRole('user')
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSaving(false)
    }
  }

  const update = async (target: SafeUser, patch: Record<string, unknown>) => {
    try {
      await api.patch(`/api/users/${target.id}`, patch)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    }
  }

  const resetPassword = async () => {
    if (!resetTarget) return
    setBusy(true)
    try {
      await api.patch(`/api/users/${resetTarget.id}`, { password: newPassword })
      toast('success', t('common.saved'))
      setResetTarget(null)
      setNewPassword('')
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    if (!deleteTarget) return
    setBusy(true)
    try {
      await api.del(`/api/users/${deleteTarget.id}`)
      setDeleteTarget(null)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="fade-in-up">
      <PageHeader
        title={t('users.title')}
        subtitle={t('users.subtitle')}
        actions={
          <Button variant="primary" onClick={() => setCreateOpen(true)}>
            <Plus size={15} />
            {t('users.create')}
          </Button>
        }
      />

      <Card className="overflow-hidden">
        {!users && <Spinner />}
        {users && (
          <div className="table-scroll">
            <table className="w-full text-[0.8125rem]">
              <thead>
                <tr className="microlabel border-b border-line/70 text-left">
                  <th className="px-4 py-3 font-semibold">{t('users.username')}</th>
                  <th className="px-3 py-3 font-semibold">{t('users.role')}</th>
                  <th className="hidden px-3 py-3 font-semibold sm:table-cell">{t('users.2fa')}</th>
                  <th className="hidden px-3 py-3 font-semibold md:table-cell">{t('users.created')}</th>
                  <th className="px-3 py-3" />
                </tr>
              </thead>
              <tbody>
                {users.map((user) => (
                  <tr key={user.id} className="border-b border-line/40 transition-colors last:border-0 hover:bg-accent/5">
                    <td className="px-4 py-2.5">
                      <div className="flex items-center gap-2.5">
                        <span className="sheen inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full btn-gradient font-display text-xs font-bold">
                          {user.username.slice(0, 1).toUpperCase()}
                        </span>
                        <span className="font-semibold">{user.username}</span>
                        {user.id === me?.id && <Badge className="border-accent/30 bg-accent/10 text-accent">{t('common.you')}</Badge>}
                        {user.suspended && <Badge className="border-danger/30 bg-danger/10 text-danger">{t('users.suspended')}</Badge>}
                      </div>
                    </td>
                    <td className="px-3 py-2.5">
                      {/* Width via wrapper: Select's base w-full vs a w-* on its
                          className resolve by stylesheet order (see DESIGN.md). */}
                      <div className="w-32">
                        <Select
                          value={user.role}
                          onChange={(e) => setRoleChange({ target: user, role: e.target.value as 'user' | 'admin' })}
                          disabled={user.id === me?.id}
                          className="h-8 rounded-full px-3 text-xs"
                        >
                          <option value="admin">{t('users.role.admin')}</option>
                          <option value="user">{t('users.role.user')}</option>
                        </Select>
                      </div>
                    </td>
                    <td className="hidden px-3 py-2.5 sm:table-cell">
                      {user.totpEnabled ? (
                        <Badge className="border-success/30 bg-success/10 text-success">
                          <ShieldCheck size={11} />
                          {t('common.enabled')}
                        </Badge>
                      ) : (
                        <span className="text-xs text-muted">{t('common.disabled')}</span>
                      )}
                    </td>
                    <td className="hidden whitespace-nowrap px-3 py-2.5 font-mono text-xs text-muted tabular md:table-cell">
                      {formatDateTime(user.createdAt)}
                    </td>
                    <td className="px-3 py-2.5">
                      <div className="flex items-center justify-end gap-1">
                        <IconButton size="sm" label={t('users.resetPassword')} onClick={() => { setResetTarget(user); setNewPassword('') }}>
                          <KeyRound size={14} />
                        </IconButton>
                        <IconButton
                          size="sm"
                          label={t('users.suspended')}
                          disabled={user.id === me?.id}
                          onClick={() => void update(user, { suspended: !user.suspended })}
                        >
                          <UserX size={14} className={user.suspended ? 'text-danger' : undefined} />
                        </IconButton>
                        <IconButton
                          size="sm"
                          label={t('common.delete')}
                          disabled={user.id === me?.id}
                          className="text-danger/80 hover:bg-danger/15 hover:text-danger"
                          onClick={() => setDeleteTarget(user)}
                        >
                          <Trash2 size={14} />
                        </IconButton>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {/* Create user */}
      <Modal
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        title={t('users.create')}
        footer={
          <Button variant="primary" onClick={() => void create()} loading={saving} disabled={!username.trim() || password.length < 8}>
            {t('common.create')}
          </Button>
        }
      >
        <div className="space-y-4">
          <Field label={t('users.username')}>
            <Input value={username} onChange={(e) => setUsername(e.target.value)} autoFocus />
          </Field>
          <Field label={t('users.password')}>
            <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" minLength={8} />
          </Field>
          <Field label={t('users.role')}>
            <Select value={role} onChange={(e) => setRole(e.target.value as 'user')}>
              <option value="user">{t('users.role.user')}</option>
              <option value="admin">{t('users.role.admin')}</option>
            </Select>
          </Field>
        </div>
      </Modal>

      {/* Reset password */}
      <Modal
        open={resetTarget !== null}
        onClose={() => setResetTarget(null)}
        title={`${t('users.resetPassword')}: ${resetTarget?.username ?? ''}`}
        footer={
          <Button variant="primary" onClick={() => void resetPassword()} loading={busy} disabled={newPassword.length < 8}>
            {t('common.save')}
          </Button>
        }
      >
        <Field label={t('account.newPw')}>
          <Input type="password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} autoFocus autoComplete="new-password" minLength={8} />
        </Field>
      </Modal>

      <ConfirmModal
        open={deleteTarget !== null}
        onClose={() => setDeleteTarget(null)}
        onConfirm={() => void remove()}
        message={t('users.deleteConfirm', { name: deleteTarget?.username ?? '' })}
        danger
        loading={busy}
        confirmLabel={t('common.delete')}
      />

      {/* Role changes (especially promotions to admin) need explicit confirmation */}
      <ConfirmModal
        open={roleChange !== null}
        onClose={() => setRoleChange(null)}
        onConfirm={async () => {
          if (!roleChange) return
          await update(roleChange.target, { role: roleChange.role })
          setRoleChange(null)
        }}
        message={t('users.roleConfirm', {
          name: roleChange?.target.username ?? '',
          role: roleChange ? t(roleChange.role === 'admin' ? 'users.role.admin' : 'users.role.user') : '',
        })}
        danger={roleChange?.role === 'admin'}
        confirmLabel={t('common.confirm')}
      />
    </div>
  )
}
