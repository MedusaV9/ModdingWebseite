import { useCallback, useEffect, useState } from 'react'
import { Copy, KeyRound, Monitor, Plus, RefreshCw, ShieldCheck, ShieldOff, Smartphone, Trash2 } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import type { ApiKeyInfo, SessionInfo } from '../api/types.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useI18n, useT, type Language } from '../i18n/index.tsx'
import { useToast } from '../state/ToastContext.tsx'
import { Badge, Button, Card, CardHeader, Checkbox, Field, IconButton, Input, PageHeader, Select } from '../components/ui.tsx'
import { ConfirmModal, Modal } from '../components/Modal.tsx'
import { formatDateTime, timeAgo } from '../lib/format.ts'

// Tiny presentational UA sniff for the sessions list — browser + OS family
// only ("Chrome 148 · Linux"), never used for logic. Order matters: Edge and
// Opera UAs also contain "Chrome/", Chrome UAs contain "Safari/".
const UA_BROWSERS: [RegExp, string][] = [
  [/Edg[A-Za-z]*\/(\d+)/, 'Edge'],
  [/OPR\/(\d+)/, 'Opera'],
  [/(?:Firefox|FxiOS)\/(\d+)/, 'Firefox'],
  [/(?:Chrome|CriOS)\/(\d+)/, 'Chrome'],
  [/Version\/(\d+).*Safari/, 'Safari'],
]

function describeUserAgent(ua: string | undefined): string | null {
  if (!ua) return null
  const os = /iphone|ipad|ipod/i.test(ua)
    ? 'iOS'
    : /android/i.test(ua)
      ? 'Android'
      : /windows/i.test(ua)
        ? 'Windows'
        : /mac os x|macintosh/i.test(ua)
          ? 'macOS'
          : /linux|x11/i.test(ua)
            ? 'Linux'
            : null
  let browser: string | null = null
  for (const [re, name] of UA_BROWSERS) {
    const m = ua.match(re)
    if (m) {
      browser = `${name} ${m[1]}`
      break
    }
  }
  if (browser && os) return `${browser} · ${os}`
  return browser ?? os
}

export function Account() {
  const t = useT()
  const { lang, setLang } = useI18n()
  const toast = useToast()
  const { user, refresh } = useAuth()

  // Password change
  const [currentPw, setCurrentPw] = useState('')
  const [newPw, setNewPw] = useState('')
  const [pwBusy, setPwBusy] = useState(false)

  // 2FA
  const [totpSecret, setTotpSecret] = useState<{ secret: string; uri: string } | null>(null)
  const [totpCode, setTotpCode] = useState('')
  const [totpBusy, setTotpBusy] = useState(false)
  const [disableOpen, setDisableOpen] = useState(false)

  // Recovery codes (plaintext codes exist in state only right after enable/regenerate)
  const [recoveryCodes, setRecoveryCodes] = useState<string[] | null>(null)
  const [recoveryRemaining, setRecoveryRemaining] = useState<number | null>(null)
  const [regenOpen, setRegenOpen] = useState(false)
  const [regenCode, setRegenCode] = useState('')
  const [regenBusy, setRegenBusy] = useState(false)

  // Sessions + API keys
  const [sessions, setSessions] = useState<SessionInfo[]>([])
  const [apiKeys, setApiKeys] = useState<ApiKeyInfo[]>([])
  const [keyName, setKeyName] = useState('')
  const [keyReadOnly, setKeyReadOnly] = useState(false)
  const [keySecret, setKeySecret] = useState<string | null>(null)
  const [keyBusy, setKeyBusy] = useState(false)
  const [deleteKey, setDeleteKey] = useState<ApiKeyInfo | null>(null)
  const [deleteKeyBusy, setDeleteKeyBusy] = useState(false)

  const load = useCallback(async () => {
    void api.get<{ sessions: SessionInfo[] }>('/api/auth/sessions').then((res) => setSessions(res.sessions)).catch(() => undefined)
    void api.get<{ apiKeys: ApiKeyInfo[] }>('/api/apikeys').then((res) => setApiKeys(res.apiKeys)).catch(() => undefined)
    void api
      .get<{ recoveryCodesRemaining?: number }>('/api/auth/me')
      .then((res) => setRecoveryRemaining(res.recoveryCodesRemaining ?? null))
      .catch(() => undefined)
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const changePassword = async () => {
    setPwBusy(true)
    try {
      await api.post('/api/auth/password', { current: currentPw, next: newPw })
      toast('success', t('account.pwChanged'))
      setCurrentPw('')
      setNewPw('')
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setPwBusy(false)
    }
  }

  const startTotp = async () => {
    try {
      const res = await api.post<{ secret: string; uri: string }>('/api/auth/totp/start')
      setTotpSecret(res)
      setTotpCode('')
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }

  const enableTotp = async () => {
    setTotpBusy(true)
    try {
      const res = await api.post<{ recoveryCodes: string[] }>('/api/auth/totp/enable', { code: totpCode })
      toast('success', t('account.2faEnabled'))
      setTotpSecret(null)
      setTotpCode('')
      setRecoveryCodes(res.recoveryCodes)
      await refresh()
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setTotpBusy(false)
    }
  }

  const regenerateRecoveryCodes = async () => {
    setRegenBusy(true)
    try {
      const res = await api.post<{ recoveryCodes: string[] }>('/api/auth/totp/recovery-codes', { code: regenCode })
      setRegenOpen(false)
      setRegenCode('')
      setRecoveryCodes(res.recoveryCodes)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setRegenBusy(false)
    }
  }

  const disableTotp = async () => {
    setTotpBusy(true)
    try {
      await api.post('/api/auth/totp/disable', { code: totpCode })
      setDisableOpen(false)
      setTotpCode('')
      await refresh()
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setTotpBusy(false)
    }
  }

  const createKey = async () => {
    setKeyBusy(true)
    try {
      const res = await api.post<{ secret: string }>('/api/apikeys', {
        name: keyName || 'api key',
        scopes: keyReadOnly ? ['read'] : [],
      })
      setKeySecret(res.secret)
      setKeyName('')
      setKeyReadOnly(false)
      await load()
    } catch (err) {
      toast('error', (err as Error).message)
    } finally {
      setKeyBusy(false)
    }
  }

  const copy = async (text: string) => {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text)
      } else {
        // Self-hosted panels usually run over plain http:// (a non-secure
        // context), where navigator.clipboard is undefined — fall back to the
        // legacy execCommand so "Copy" still works (critical for recovery codes).
        const ta = document.createElement('textarea')
        ta.value = text
        ta.style.position = 'fixed'
        ta.style.opacity = '0'
        document.body.appendChild(ta)
        ta.focus()
        ta.select()
        const ok = document.execCommand('copy')
        document.body.removeChild(ta)
        if (!ok) throw new Error('copy failed')
      }
      toast('success', t('common.copied'))
    } catch {
      toast('error', t('common.copyFailed'))
    }
  }

  const changeLanguage = async (next: Language) => {
    setLang(next)
    try {
      await api.patch('/api/auth/prefs', { language: next })
    } catch {
      /* offline pref only */
    }
  }

  return (
    <div className="fade-in-up">
      <PageHeader title={t('account.title')} subtitle={t('account.subtitle')} />

      <div className="max-w-3xl space-y-4">
        {/* Language */}
        <Card>
          <CardHeader title={t('account.language')} />
          <div className="max-w-xs p-4">
            <Select value={lang} onChange={(e) => void changeLanguage(e.target.value as Language)}>
              <option value="en">English</option>
              <option value="de">Deutsch</option>
            </Select>
          </div>
        </Card>

        {/* Password */}
        <Card>
          <CardHeader title={t('account.password')} />
          <div className="grid gap-4 p-4 sm:grid-cols-2">
            <Field label={t('account.currentPw')}>
              <Input type="password" value={currentPw} onChange={(e) => setCurrentPw(e.target.value)} autoComplete="current-password" />
            </Field>
            <Field label={t('account.newPw')}>
              <Input type="password" value={newPw} onChange={(e) => setNewPw(e.target.value)} autoComplete="new-password" minLength={8} />
            </Field>
            <div>
              <Button variant="primary" onClick={() => void changePassword()} loading={pwBusy} disabled={!currentPw || newPw.length < 8}>
                {t('account.changePw')}
              </Button>
            </div>
          </div>
        </Card>

        {/* 2FA */}
        <Card>
          <CardHeader title={t('account.2fa')} />
          <div className="space-y-4 p-4">
            {user?.totpEnabled ? (
              <div className="space-y-3">
                <div className="glass-subtle flex flex-wrap items-center gap-3 rounded-xl border-success/30 bg-success/10 px-3 py-2.5">
                  <p className="flex items-center gap-2 text-sm font-medium text-success">
                    <ShieldCheck size={16} />
                    {t('account.2faEnabled')}
                  </p>
                  <Button variant="danger" size="sm" className="ml-auto" onClick={() => { setTotpCode(''); setDisableOpen(true) }}>
                    <ShieldOff size={13} />
                    {t('account.2faDisable')}
                  </Button>
                </div>
                <div className="flex flex-wrap items-center gap-3">
                  <p className="text-sm text-muted">{t('account.recovery.remaining', { n: recoveryRemaining ?? 0 })}</p>
                  <Button variant="secondary" size="sm" onClick={() => { setRegenCode(''); setRegenOpen(true) }}>
                    <RefreshCw size={13} />
                    {t('account.recovery.regenerate')}
                  </Button>
                </div>
              </div>
            ) : totpSecret ? (
              <div className="fade-in-up space-y-4">
                <div className="glass-subtle mx-auto flex w-full max-w-md flex-col items-center gap-3 rounded-xl p-4 text-center">
                  <p className="text-sm text-muted">{t('account.2faSecret')}</p>
                  <div className="flex max-w-full items-center gap-2">
                    <code className="sheen min-w-0 break-all rounded-lg border border-line/70 bg-elevated/70 px-3 py-2 font-mono text-sm tracking-wider">
                      {totpSecret.secret}
                    </code>
                    <IconButton label={t('common.copy')} variant="glass" size="sm" onClick={() => void copy(totpSecret.secret)}>
                      <Copy size={13} />
                    </IconButton>
                  </div>
                  <p className="break-all font-mono text-[0.6875rem] text-muted/70">{totpSecret.uri}</p>
                </div>
                <div className="mx-auto flex w-full max-w-md flex-col items-center gap-3 text-center">
                  <p className="text-sm text-muted">{t('account.2faConfirm')}</p>
                  <div className="flex items-center gap-2">
                    <Input
                      value={totpCode}
                      onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                      placeholder="000000"
                      inputMode="numeric"
                      className="h-11 w-36 text-center font-mono tracking-[0.3em]"
                    />
                    <Button variant="primary" onClick={() => void enableTotp()} loading={totpBusy} disabled={totpCode.length !== 6}>
                      {t('account.2faEnable')}
                    </Button>
                  </div>
                </div>
              </div>
            ) : (
              <div className="flex flex-wrap items-center gap-3">
                <p className="text-sm text-muted">{t('account.2faDisabled')}</p>
                <Button variant="secondary" onClick={() => void startTotp()}>
                  <ShieldCheck size={14} />
                  {t('account.2faStart')}
                </Button>
              </div>
            )}
          </div>
        </Card>

        {/* Sessions */}
        <Card>
          <CardHeader title={t('account.sessions')} />
          <div className="divide-y divide-line/60">
            {sessions.map((session) => (
              <div key={session.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <span className="glass-subtle inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-muted">
                  {/mobi|android|iphone|ipad/i.test(session.userAgent ?? '') ? <Smartphone size={15} /> : <Monitor size={15} />}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 text-[0.8125rem]">
                    <span className="font-mono tabular">{session.ip ?? '?'}</span>
                    {session.current && <Badge className="border-success/30 bg-success/10 text-success">{t('account.session.current')}</Badge>}
                  </div>
                  <div className="mt-0.5 line-clamp-1 text-[0.6875rem] text-muted" title={session.userAgent ?? undefined}>
                    {timeAgo(session.createdAt, t)} · {describeUserAgent(session.userAgent) ?? session.userAgent ?? '—'}
                  </div>
                </div>
                {!session.current && (
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={async () => {
                      await api.del(`/api/auth/sessions/${session.id}`).catch(() => undefined)
                      await load()
                    }}
                  >
                    {t('account.session.revoke')}
                  </Button>
                )}
              </div>
            ))}
          </div>
        </Card>

        {/* API keys */}
        <Card>
          <CardHeader title={t('account.apikeys')} subtitle={t('account.apikeys.hint')} />
          <div className="space-y-3 p-4">
            <div className="flex flex-wrap items-end gap-2">
              <div className="w-full max-w-xs">
                <Field label={t('account.apikeys.name')}>
                  <Input value={keyName} onChange={(e) => setKeyName(e.target.value)} placeholder="e.g. ci-deploy" maxLength={40} />
                </Field>
              </div>
              <Checkbox
                className="pb-2.5"
                checked={keyReadOnly}
                onChange={(e) => setKeyReadOnly(e.target.checked)}
                label={t('account.apikeys.readonly')}
              />
              <Button variant="primary" onClick={() => void createKey()} loading={keyBusy}>
                <Plus size={14} />
                {t('account.apikeys.create')}
              </Button>
            </div>

            {keySecret && (
              <div className="fade-in-up glass-subtle rounded-xl border-success/40 bg-success/10 p-3">
                <p className="mb-2 text-xs font-semibold text-success">{t('account.apikeys.secretOnce')}</p>
                <div className="flex items-center gap-2">
                  <code className="sheen min-w-0 flex-1 break-all rounded-lg border border-line/70 bg-surface/70 px-3 py-2 font-mono text-xs">{keySecret}</code>
                  <IconButton label={t('common.copy')} variant="glass" size="sm" onClick={() => void copy(keySecret)}>
                    <Copy size={13} />
                  </IconButton>
                </div>
              </div>
            )}

            {apiKeys.length === 0 && <p className="text-sm text-muted">{t('account.apikeys.empty')}</p>}
            <div className="divide-y divide-line/60">
              {apiKeys.map((key) => (
                <div key={key.id} className="flex flex-wrap items-center gap-3 py-3">
                  <span className="glass-subtle inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-accent/80">
                    <KeyRound size={15} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 text-[0.8125rem]">
                      <span className="font-semibold">{key.name}</span>
                      <Badge className="font-mono">{key.prefix}…</Badge>
                      {key.scopes?.includes('read') && !key.scopes?.includes('write') && (
                        <Badge>{t('account.apikeys.readonly')}</Badge>
                      )}
                    </div>
                    <div className="mt-0.5 text-[0.6875rem] text-muted tabular">
                      {formatDateTime(key.createdAt)} · {key.lastUsedAt ? timeAgo(key.lastUsedAt, t) : t('common.never')}
                    </div>
                  </div>
                  <IconButton
                    label={t('common.delete')}
                    size="sm"
                    className="text-danger/80 hover:bg-danger/15 hover:text-danger"
                    onClick={() => setDeleteKey(key)}
                  >
                    <Trash2 size={14} />
                  </IconButton>
                </div>
              ))}
            </div>
          </div>
        </Card>
      </div>

      {/* Disable 2FA modal */}
      <Modal
        open={disableOpen}
        onClose={() => setDisableOpen(false)}
        title={t('account.2faDisable')}
        footer={
          <>
            <Button variant="ghost" onClick={() => setDisableOpen(false)}>
              {t('common.cancel')}
            </Button>
            <Button variant="danger" onClick={() => void disableTotp()} loading={totpBusy} disabled={totpCode.length !== 6}>
              {t('account.2faDisable')}
            </Button>
          </>
        }
      >
        <Field label={t('account.2faCode')}>
          <Input
            value={totpCode}
            onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
            placeholder="000000"
            inputMode="numeric"
            autoFocus
            className="w-32 text-center font-mono tracking-[0.3em]"
          />
        </Field>
      </Modal>

      {/* Recovery codes — plaintext is shown exactly once */}
      <Modal
        open={recoveryCodes !== null}
        onClose={() => setRecoveryCodes(null)}
        title={t('account.recovery.title')}
        footer={
          <Button variant="primary" onClick={() => void copy((recoveryCodes ?? []).join('\n'))}>
            <Copy size={13} />
            {t('account.recovery.copy')}
          </Button>
        }
      >
        <div className="space-y-3">
          <p className="glass-subtle rounded-xl border-warn/40 bg-warn/10 px-3 py-2.5 text-sm leading-relaxed text-warn">
            {t('account.recovery.warning')}
          </p>
          <div className="grid grid-cols-2 gap-2">
            {(recoveryCodes ?? []).map((code) => (
              <code key={code} className="glass-subtle rounded-xl px-3 py-2.5 text-center font-mono text-sm tracking-wide tabular">
                {code}
              </code>
            ))}
          </div>
        </div>
      </Modal>

      {/* Regenerate recovery codes: confirm with current TOTP code */}
      <Modal
        open={regenOpen}
        onClose={() => setRegenOpen(false)}
        title={t('account.recovery.regenerate')}
        footer={
          <Button variant="primary" onClick={() => void regenerateRecoveryCodes()} loading={regenBusy} disabled={regenCode.length !== 6}>
            {t('account.recovery.regenerate')}
          </Button>
        }
      >
        <Field label={t('account.recovery.confirmCode')}>
          <Input
            value={regenCode}
            onChange={(e) => setRegenCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
            placeholder="000000"
            inputMode="numeric"
            autoFocus
            className="w-32 text-center font-mono tracking-[0.3em]"
          />
        </Field>
      </Modal>

      {/* Delete API key confirmation */}
      <ConfirmModal
        open={deleteKey !== null}
        onClose={() => setDeleteKey(null)}
        onConfirm={async () => {
          if (!deleteKey) return
          setDeleteKeyBusy(true)
          try {
            await api.del(`/api/apikeys/${deleteKey.id}`)
            setDeleteKey(null)
            await load()
          } catch (err) {
            toast('error', err instanceof ApiError ? err.message : String(err))
          } finally {
            setDeleteKeyBusy(false)
          }
        }}
        message={t('account.apikeys.deleteConfirm', { name: deleteKey?.name ?? '' })}
        danger
        confirmLabel={t('common.delete')}
        loading={deleteKeyBusy}
      />
    </div>
  )
}
