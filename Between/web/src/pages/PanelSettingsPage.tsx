import { useCallback, useEffect, useState } from 'react'
import { Check, Container, Download, LogIn, LogOut, Save, Send } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import type { DockerStatus, PanelSettings, SteamLoginStatus, SteamStatus, SystemInfo } from '../api/types.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { useToast } from '../state/ToastContext.tsx'
import { Badge, Button, Card, CardHeader, Field, Input, PageHeader, Spinner, Toggle } from '../components/ui.tsx'

type SettingsCard = 'name' | 'backups' | 'discord' | 'webhook'

export function PanelSettingsPage() {
  const t = useT()
  const toast = useToast()
  const { refresh } = useAuth()
  const [settings, setSettings] = useState<PanelSettings | null>(null)
  const [system, setSystem] = useState<SystemInfo | null>(null)
  const [steam, setSteam] = useState<SteamStatus | null>(null)
  const [docker, setDocker] = useState<DockerStatus | null>(null)

  const [panelName, setPanelName] = useState('')
  const [retention, setRetention] = useState(10)
  const [webhookUrl, setWebhookUrl] = useState('')
  const [events, setEvents] = useState({ crash: true, power: false, backup: false })
  const [genericUrl, setGenericUrl] = useState('')
  const [genericEvents, setGenericEvents] = useState({ crash: true, power: false, backup: false })
  const [webhookTest, setWebhookTest] = useState<{ ok: boolean; status?: number; error?: string } | null>(null)
  const [testingWebhook, setTestingWebhook] = useState(false)
  const [savingCard, setSavingCard] = useState<SettingsCard | null>(null)
  const [steamInstalling, setSteamInstalling] = useState(false)
  const [loadFailed, setLoadFailed] = useState(false)

  // Steam account sign-in (panel-level; the password only lives in this form
  // state until the request is answered — it is never persisted anywhere).
  const [steamLogin, setSteamLogin] = useState<SteamLoginStatus | null>(null)
  const [steamUser, setSteamUser] = useState('')
  const [steamPass, setSteamPass] = useState('')
  const [steamGuard, setSteamGuard] = useState('')
  const [needsGuard, setNeedsGuard] = useState(false)
  const [steamSigningIn, setSteamSigningIn] = useState(false)
  const [steamSigningOut, setSteamSigningOut] = useState(false)
  const [steamLoginError, setSteamLoginError] = useState<string | null>(null)

  const load = useCallback(() => {
    setLoadFailed(false)
    // The core settings fetch decides whether the page can render; a failure
    // must surface an error + retry rather than an infinite spinner.
    void api
      .get<{ settings: PanelSettings }>('/api/settings')
      .then((res) => {
        setSettings(res.settings)
        setPanelName(res.settings.panelName)
        setRetention(res.settings.defaultBackupRetention)
        setWebhookUrl(res.settings.discordWebhookUrl ?? '')
        setEvents({
          crash: res.settings.discordEvents?.crash ?? true,
          power: res.settings.discordEvents?.power ?? false,
          backup: res.settings.discordEvents?.backup ?? false,
        })
        setGenericUrl(res.settings.webhookUrl ?? '')
        setGenericEvents({
          crash: res.settings.webhookEvents?.crash ?? true,
          power: res.settings.webhookEvents?.power ?? false,
          backup: res.settings.webhookEvents?.backup ?? false,
        })
      })
      .catch(() => setLoadFailed(true))
    void api.get<{ system: SystemInfo }>('/api/system').then((res) => setSystem(res.system)).catch(() => undefined)
    void api.get<SteamStatus>('/api/steam/status').then(setSteam).catch(() => undefined)
    void api
      .get<SteamLoginStatus>('/api/steam/login')
      .then((res) => {
        setSteamLogin(res)
        if (res.user) setSteamUser(res.user)
      })
      .catch(() => undefined)
    void api.get<DockerStatus>('/api/docker/status?refresh=true').then(setDocker).catch(() => undefined)
  }, [])

  useEffect(() => load(), [load])

  // Per-card save: each Save button commits exactly the fields of its own
  // card (the PATCH endpoint applies partial updates), so no button's scope
  // extends past the card it lives in.
  const saveCard = async (card: SettingsCard) => {
    setSavingCard(card)
    try {
      await api.patch(
        '/api/settings',
        card === 'name'
          ? { panelName }
          : card === 'backups'
            ? { defaultBackupRetention: retention }
            : card === 'webhook'
              ? { webhookUrl: genericUrl, webhookEvents: genericEvents }
              : { discordWebhookUrl: webhookUrl, discordEvents: events },
      )
      toast('success', t('toast.saved'))
      if (card === 'webhook') setWebhookTest(null) // stale result for the previous URL
      if (card === 'name') await refresh() // update panel name in sidebar
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSavingCard(null)
    }
  }

  // Tests the SAVED webhook URL (server-side config), not the unsaved input.
  const sendWebhookTest = async () => {
    setTestingWebhook(true)
    setWebhookTest(null)
    try {
      setWebhookTest(await api.post<{ ok: boolean; status?: number; error?: string }>('/api/settings/webhook-test'))
    } catch (err) {
      setWebhookTest({ ok: false, error: err instanceof ApiError ? err.message : String(err) })
    } finally {
      setTestingWebhook(false)
    }
  }

  const installSteam = async () => {
    setSteamInstalling(true)
    try {
      await api.post('/api/steam/install')
      const res = await api.get<SteamStatus>('/api/steam/status')
      setSteam(res)
      toast('success', t('settings.steamInstalled'))
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSteamInstalling(false)
    }
  }

  const steamSignIn = async () => {
    setSteamSigningIn(true)
    setSteamLoginError(null)
    try {
      const res = await api.post<{ ok: boolean; needsGuard?: boolean; error?: string }>('/api/steam/login', {
        username: steamUser.trim(),
        password: steamPass,
        ...(needsGuard && steamGuard.trim() ? { guardCode: steamGuard.trim() } : {}),
      })
      if (res.ok) {
        setSteamPass('')
        setSteamGuard('')
        setNeedsGuard(false)
        toast('success', t('steam.loginOk'))
        setSteamLogin(await api.get<SteamLoginStatus>('/api/steam/login'))
        setSteam(await api.get<SteamStatus>('/api/steam/status'))
      } else if (res.needsGuard) {
        // Two-step flow: the password was accepted but Steam Guard wants a
        // code. Keep the password in form state for the immediate retry
        // (steamcmd needs password + code in ONE session); it is cleared on
        // success or hard failure and never leaves the browser otherwise.
        setNeedsGuard(true)
      } else {
        setSteamPass('')
        setSteamGuard('')
        setSteamLoginError(res.error ?? '?')
      }
    } catch (err) {
      setSteamPass('')
      setSteamGuard('')
      setSteamLoginError(err instanceof ApiError ? err.message : String(err))
    } finally {
      setSteamSigningIn(false)
    }
  }

  const steamSignOut = async () => {
    setSteamSigningOut(true)
    try {
      await api.post('/api/steam/logout')
      toast('success', t('steam.loggedOut'))
      setSteamLogin({ user: null, loggedIn: false })
      setSteamUser('')
      setNeedsGuard(false)
      setSteamLoginError(null)
      setSteam(await api.get<SteamStatus>('/api/steam/status'))
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSteamSigningOut(false)
    }
  }

  if (!settings) {
    if (loadFailed) {
      return (
        <div className="flex flex-col items-center gap-3 py-16 text-center">
          <p className="text-sm text-muted">{t('settings.loadFailed')}</p>
          <Button variant="secondary" onClick={() => load()}>{t('common.refresh')}</Button>
        </div>
      )
    }
    return <Spinner label={t('common.loading')} />
  }

  return (
    <div className="fade-in-up">
      <PageHeader title={t('settings.title')} subtitle={t('settings.subtitle')} />

      <div className="max-w-3xl space-y-4">
        <Card>
          {/* Card title doubles as the input's label (aria-label below) —
              repeating it as a visible Field label 20px under is noise. */}
          <CardHeader title={t('settings.panelName')} actions={<SaveButton card="name" savingCard={savingCard} onSave={saveCard} label={t('common.save')} />} />
          <div className="grid gap-4 p-4 sm:grid-cols-2">
            <Input aria-label={t('settings.panelName')} value={panelName} onChange={(e) => setPanelName(e.target.value)} maxLength={40} />
          </div>
        </Card>

        <Card>
          <CardHeader title={t('settings.backups')} actions={<SaveButton card="backups" savingCard={savingCard} onSave={saveCard} label={t('common.save')} />} />
          <div className="grid gap-4 p-4 sm:grid-cols-2">
            <Field label={t('settings.retention')}>
              <Input type="number" min={1} max={100} value={String(retention)} onChange={(e) => setRetention(Number(e.target.value) || 10)} />
            </Field>
          </div>
        </Card>

        <Card>
          <CardHeader title={t('settings.discord')} actions={<SaveButton card="discord" savingCard={savingCard} onSave={saveCard} label={t('common.save')} />} />
          <div className="space-y-4 p-4">
            <Field label={t('settings.webhookUrl')} hint={t('settings.webhookHint')}>
              <Input
                value={webhookUrl}
                onChange={(e) => setWebhookUrl(e.target.value)}
                placeholder="https://discord.com/api/webhooks/…"
                className="font-mono text-xs"
              />
            </Field>
            <div className="space-y-3">
              <Toggle checked={events.crash} onChange={(v) => setEvents((prev) => ({ ...prev, crash: v }))} label={t('settings.notifyCrash')} />
              <Toggle checked={events.power} onChange={(v) => setEvents((prev) => ({ ...prev, power: v }))} label={t('settings.notifyPower')} />
              <Toggle checked={events.backup} onChange={(v) => setEvents((prev) => ({ ...prev, backup: v }))} label={t('settings.notifyBackup')} />
            </div>
          </div>
        </Card>

        <Card>
          <CardHeader title={t('settings.webhook')} actions={<SaveButton card="webhook" savingCard={savingCard} onSave={saveCard} label={t('common.save')} />} />
          <div className="space-y-4 p-4">
            <Field label={t('settings.webhookUrl')} hint={t('settings.webhookGenericHint')}>
              <Input
                value={genericUrl}
                onChange={(e) => setGenericUrl(e.target.value)}
                placeholder="http://192.168.1.10:5678/webhook/…"
                className="font-mono text-xs"
              />
            </Field>
            <div className="space-y-3">
              <Toggle checked={genericEvents.crash} onChange={(v) => setGenericEvents((prev) => ({ ...prev, crash: v }))} label={t('settings.notifyCrash')} />
              <Toggle checked={genericEvents.power} onChange={(v) => setGenericEvents((prev) => ({ ...prev, power: v }))} label={t('settings.notifyPower')} />
              <Toggle checked={genericEvents.backup} onChange={(v) => setGenericEvents((prev) => ({ ...prev, backup: v }))} label={t('settings.notifyBackup')} />
            </div>
            <div className="flex flex-wrap items-center gap-3">
              <Button variant="secondary" size="sm" onClick={() => void sendWebhookTest()} loading={testingWebhook}>
                <Send size={13} />
                {t('settings.webhookTest')}
              </Button>
              {webhookTest &&
                (webhookTest.ok ? (
                  <p className="flex items-center gap-1.5 text-sm font-medium text-success">
                    <Check size={14} />
                    {t('settings.webhookTestOk', { status: String(webhookTest.status ?? '?') })}
                  </p>
                ) : (
                  <p className="text-sm font-medium text-danger">
                    {t('settings.webhookTestFail', { error: webhookTest.error ?? `HTTP ${webhookTest.status ?? '?'}` })}
                  </p>
                ))}
            </div>
          </div>
        </Card>

        <Card>
          <CardHeader title={t('settings.steam')} />
          <div className="space-y-4 p-4">
            {steam?.installed ? (
              <p className="glass-subtle flex flex-wrap items-center gap-2 rounded-xl border-success/30 bg-success/10 px-3 py-2.5 text-sm font-medium text-success">
                <Check size={15} />
                {t('settings.steamInstalled')}
                <span className="min-w-0 truncate font-mono text-xs font-normal text-muted">{steam.dir}</span>
              </p>
            ) : (
              <div className="flex flex-wrap items-center gap-3">
                <p className="text-sm text-muted">{t('settings.steamMissing')}</p>
                <Button variant="secondary" onClick={() => void installSteam()} loading={steamInstalling}>
                  <Download size={14} />
                  {t('settings.steamInstall')}
                </Button>
              </div>
            )}

            {/* Panel Steam account: one interactive sign-in caches a SteamCMD
                session on this machine; installs then use +login <user>. */}
            <div className="space-y-4 border-t border-line/60 pt-4">
              <span className="microlabel block">{t('steam.account')}</span>
              {steamLogin?.loggedIn ? (
                <div className="flex flex-wrap items-center gap-3">
                  <p className="glass-subtle flex items-center gap-2 rounded-xl border-success/30 bg-success/10 px-3 py-2.5 text-sm font-medium text-success">
                    <Check size={15} />
                    {t('steam.loggedInAs', { user: steamLogin.user ?? '' })}
                  </p>
                  <Button variant="secondary" onClick={() => void steamSignOut()} loading={steamSigningOut}>
                    <LogOut size={14} />
                    {t('steam.signOut')}
                  </Button>
                </div>
              ) : (
                <form
                  className="space-y-4"
                  onSubmit={(e) => {
                    e.preventDefault()
                    void steamSignIn()
                  }}
                >
                  {steamLogin?.user && !needsGuard && (
                    <p className="text-sm font-medium text-warn">{t('steam.sessionExpired', { user: steamLogin.user })}</p>
                  )}
                  <div className="grid gap-4 sm:grid-cols-2">
                    <Field label={t('steam.username')}>
                      <Input value={steamUser} onChange={(e) => setSteamUser(e.target.value)} autoComplete="off" maxLength={64} />
                    </Field>
                    <Field label={t('steam.password')}>
                      <Input
                        type="password"
                        value={steamPass}
                        onChange={(e) => setSteamPass(e.target.value)}
                        autoComplete="off"
                        maxLength={256}
                      />
                    </Field>
                    {needsGuard && (
                      <div className="sm:col-span-2">
                        <Field label={t('steam.guardCode')} hint={t('steam.guardPrompt')}>
                          <Input
                            value={steamGuard}
                            onChange={(e) => setSteamGuard(e.target.value)}
                            autoComplete="off"
                            maxLength={10}
                            autoFocus
                            className="font-mono sm:max-w-xs"
                          />
                        </Field>
                      </div>
                    )}
                  </div>
                  {steamLoginError && (
                    <p className="text-sm font-medium text-danger">{t('steam.loginFailed', { error: steamLoginError })}</p>
                  )}
                  <Button
                    type="submit"
                    variant="secondary"
                    loading={steamSigningIn}
                    disabled={!steamUser.trim() || !steamPass || !steam?.installed}
                  >
                    <LogIn size={14} />
                    {t('steam.signIn')}
                  </Button>
                </form>
              )}
              <p className="text-xs leading-relaxed text-muted">{t('steam.hint')}</p>
            </div>
          </div>
        </Card>

        {/* Status-only cards below: muted titles + no header action mark them
            as read-only — the Save buttons' authority ends above this line. */}
        <Card>
          <CardHeader title={<span className="text-muted">{t('settings.docker')}</span>} />
          <div className="p-4">
            {docker?.available ? (
              <p className="glass-subtle flex flex-wrap items-center gap-2 rounded-xl border-success/30 bg-success/10 px-3 py-2.5 text-sm font-medium text-success">
                <Container size={15} />
                {t('settings.dockerAvailable', { version: docker.version ?? '?' })}
                <span className="min-w-0 truncate font-mono text-xs font-normal text-muted">{docker.socketPath}</span>
              </p>
            ) : (
              <div className="glass-subtle rounded-xl px-3 py-2.5">
                <p className="text-sm text-muted">{t('settings.dockerMissing')}</p>
                {docker?.error && <p className="mt-1 break-all font-mono text-xs text-muted/70">{docker.error}</p>}
              </div>
            )}
          </div>
        </Card>

        <Card>
          <CardHeader title={<span className="text-muted">{t('settings.system')}</span>} />
          <div className="grid gap-3 p-4 text-[0.8125rem] sm:grid-cols-2">
            <div className="glass-subtle flex items-center justify-between gap-3 rounded-xl px-3 py-2.5">
              <span className="shrink-0 text-muted">{t('settings.hostInfo')}</span>
              <span className="truncate font-mono text-xs">
                {system ? `${system.hostname} · ${system.platform}/${system.arch} · node ${system.nodeVersion}` : '—'}
              </span>
            </div>
            <div className="glass-subtle flex items-center justify-between gap-3 rounded-xl px-3 py-2.5">
              <span className="shrink-0 text-muted">{t('settings.dataDir')}</span>
              <span className="truncate font-mono text-xs">{system?.dataDir ?? '—'}</span>
            </div>
            <div className="glass-subtle flex items-center justify-between gap-3 rounded-xl px-3 py-2.5">
              <span className="shrink-0 text-muted">{t('settings.version')}</span>
              <Badge className="border-accent/30 bg-accent/10 text-accent tabular">v{system?.panelVersion ?? '—'}</Badge>
            </div>
            <div className="glass-subtle flex items-center justify-between gap-3 rounded-xl px-3 py-2.5">
              <span className="shrink-0 text-muted">CPU</span>
              <span className="truncate font-mono text-xs">{system ? `${system.cpus}× ${system.cpuModel}` : '—'}</span>
            </div>
          </div>
        </Card>
      </div>
    </div>
  )
}

/** Card-scoped Save action for the editable settings cards. */
function SaveButton({
  card,
  savingCard,
  onSave,
  label,
}: {
  card: SettingsCard
  savingCard: SettingsCard | null
  onSave: (card: SettingsCard) => Promise<void>
  label: string
}) {
  return (
    <Button variant="primary" size="sm" onClick={() => void onSave(card)} loading={savingCard === card} disabled={savingCard !== null && savingCard !== card}>
      <Save size={13} />
      {label}
    </Button>
  )
}
