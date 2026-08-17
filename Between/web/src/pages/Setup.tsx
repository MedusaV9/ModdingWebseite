import { useState, type FormEvent } from 'react'
import { AlertCircle } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { Button, Field, Input } from '../components/ui.tsx'
import type { SafeUser } from '../api/types.ts'

export function Setup() {
  const t = useT()
  const { setUser, refresh } = useAuth()
  const [panelName, setPanelName] = useState('Between')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [password2, setPassword2] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    if (password !== password2) {
      setError(t('setup.mismatch'))
      return
    }
    setBusy(true)
    setError(null)
    try {
      const res = await api.post<{ user: SafeUser }>('/api/auth/setup', { username, password, panelName })
      setUser(res.user)
      await refresh()
    } catch (err) {
      setError(err instanceof ApiError ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    // Centering via child `m-auto` (not items-center) so short viewports can
    // scroll to the top of the card instead of clipping it unreachably.
    <div className="app-bg safe-top safe-bottom flex h-full overflow-y-auto">
      <div className="m-auto w-full max-w-md px-4 py-6">
        <div className="fade-in-up">
          <div className="mb-6 text-center">
            <span className="glow-accent scale-in mx-auto mb-4 inline-flex h-12 w-12 items-center justify-center rounded-2xl btn-gradient font-display text-xl font-bold">B</span>
            <h1 className="font-display text-2xl font-bold tracking-tight">
              <span className="text-gradient">{t('setup.title')}</span>
            </h1>
            <p className="mx-auto mt-1.5 max-w-sm text-sm leading-relaxed text-muted">{t('setup.subtitle')}</p>
          </div>
          <form onSubmit={submit} className="glass-strong space-y-4 rounded-2xl p-6">
            <Field label={t('setup.panelName')}>
              <Input className="h-11" value={panelName} onChange={(e) => setPanelName(e.target.value)} maxLength={40} />
            </Field>
            <Field label={t('setup.username')}>
              <Input className="h-11" value={username} onChange={(e) => setUsername(e.target.value)} autoFocus autoComplete="username" required />
            </Field>
            <Field label={t('setup.password')}>
              <Input className="h-11" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" required minLength={8} />
            </Field>
            <Field label={t('setup.password2')}>
              <Input className="h-11" type="password" value={password2} onChange={(e) => setPassword2(e.target.value)} autoComplete="new-password" required />
            </Field>
            {error && (
              <div className="fade-in glass-subtle flex items-start gap-2 rounded-xl border-danger/40 bg-danger/10 px-3 py-2.5 text-[0.8125rem] leading-snug text-danger">
                <AlertCircle size={15} className="mt-0.5 shrink-0" />
                <span>{error}</span>
              </div>
            )}
            <Button type="submit" variant="primary" size="lg" className="w-full" loading={busy}>
              {t('setup.submit')}
            </Button>
          </form>
        </div>
      </div>
    </div>
  )
}
