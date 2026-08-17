import { useState, type FormEvent } from 'react'
import { AlertCircle, Boxes, Container, ShieldCheck } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { Button, Field, Input } from '../components/ui.tsx'
import type { SafeUser } from '../api/types.ts'

export function Login() {
  const t = useT()
  const { setUser, meta } = useAuth()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [totp, setTotp] = useState('')
  const [totpRequired, setTotpRequired] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      const res = await api.post<{ user: SafeUser }>(
        '/api/auth/login',
        { username, password, totp: totp || undefined },
        { emit401: false },
      )
      setUser(res.user)
    } catch (err) {
      if (err instanceof ApiError && err.data?.totpRequired) {
        setTotpRequired(true)
        setError(totp ? err.message : null)
      } else {
        setError(err instanceof ApiError ? err.message : String(err))
      }
    } finally {
      setBusy(false)
    }
  }

  const features: { icon: React.ReactNode; text: string }[] = [
    { icon: <Boxes size={16} />, text: t('login.feat1') },
    { icon: <Container size={16} />, text: t('login.feat2') },
    { icon: <ShieldCheck size={16} />, text: t('login.feat3') },
  ]

  return (
    // Centering via child `m-auto` (not items-center) so short viewports can
    // scroll to the top of the card instead of clipping it unreachably.
    <div className="app-bg safe-top safe-bottom flex h-full overflow-y-auto">
      <div className="m-auto w-full max-w-3xl px-4 py-6 sm:px-6">
        <div className="fade-in-up glass-strong grid w-full overflow-hidden rounded-2xl lg:grid-cols-[1.05fr_1fr]">
          {/* Brand panel */}
          <div className="relative hidden flex-col justify-between overflow-hidden border-r border-line/50 bg-linear-to-br from-accent/20 via-transparent to-accent2/15 p-8 lg:flex">
            {/* Soft accent orbs behind the glass (decorative, filter-blur — not backdrop) */}
            <div aria-hidden className="pointer-events-none absolute -right-16 -top-20 h-52 w-52 rounded-full bg-accent/20 blur-3xl" />
            <div aria-hidden className="pointer-events-none absolute -bottom-24 -left-14 h-56 w-56 rounded-full bg-accent2/15 blur-3xl" />
            <div className="relative">
              <div className="flex items-center gap-3">
                <span className="glow-accent inline-flex h-11 w-11 items-center justify-center rounded-2xl btn-gradient font-display text-lg font-bold">B</span>
                <div>
                  <div className="font-display text-xl font-bold tracking-tight">{meta?.panelName ?? 'Between'}</div>
                  <div className="text-xs text-muted">{t('login.tagline')}</div>
                </div>
              </div>
              <ul className="stagger mt-10 space-y-3">
                {features.map((f, i) => (
                  <li key={i} className="fade-in-up glass-subtle flex items-start gap-3 rounded-xl px-3 py-2.5 text-[0.8125rem] leading-relaxed text-text/85">
                    <span className="mt-0.5 inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-accent/12 text-accent">
                      {f.icon}
                    </span>
                    {f.text}
                  </li>
                ))}
              </ul>
            </div>
            <p className="relative text-[0.6875rem] text-muted/60">Between · {t('login.subtitle')}</p>
          </div>

          {/* Form panel */}
          <div className="p-6 sm:p-8">
            <div className="mb-6 lg:hidden">
              <span className="glow-accent mb-3 inline-flex h-11 w-11 items-center justify-center rounded-2xl btn-gradient font-display text-lg font-bold">B</span>
              <h1 className="font-display text-2xl font-bold tracking-tight">{meta?.panelName ?? 'Between'}</h1>
              <p className="mt-1 text-sm text-muted">{t('login.subtitle')}</p>
            </div>
            <h2 className="mb-5 hidden font-display text-xl font-bold tracking-tight lg:block">{t('login.title')}</h2>
            <form onSubmit={submit} className="space-y-4">
              <Field label={t('login.username')}>
                <Input className="h-11" value={username} onChange={(e) => setUsername(e.target.value)} autoFocus autoComplete="username" required />
              </Field>
              <Field label={t('login.password')}>
                <Input className="h-11" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
              </Field>
              {totpRequired && (
                <div className="fade-in-up">
                  <Field label={t('login.totp')} hint={t('login.totpHint')}>
                    <Input
                      value={totp}
                      // Accepts a 6-digit TOTP code or a recovery code (letters/digits/dashes)
                      onChange={(e) => setTotp(e.target.value.replace(/[^a-zA-Z0-9-]/g, '').slice(0, 14))}
                      autoFocus
                      placeholder="000000"
                      className="h-11 text-center font-mono tracking-[0.4em]"
                    />
                  </Field>
                </div>
              )}
              {error && (
                <div className="fade-in glass-subtle flex items-start gap-2 rounded-xl border-danger/40 bg-danger/10 px-3 py-2.5 text-[0.8125rem] leading-snug text-danger">
                  <AlertCircle size={15} className="mt-0.5 shrink-0" />
                  <span>{error}</span>
                </div>
              )}
              <Button type="submit" variant="primary" size="lg" className="w-full" loading={busy}>
                {t('login.submit')}
              </Button>
            </form>
          </div>
        </div>
      </div>
    </div>
  )
}
