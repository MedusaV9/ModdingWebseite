import { useState } from 'react'
import { Check } from 'lucide-react'
import { api } from '../api/client.ts'
import { ACCENTS, THEMES, applyTheme } from '../themes.ts'
import { useAuth } from '../state/AuthContext.tsx'
import { useT } from '../i18n/index.tsx'
import { useToast } from '../state/ToastContext.tsx'
import { Button, Card, CardHeader, PageHeader, cx } from '../components/ui.tsx'
import { StatusPill } from '../components/StatusPill.tsx'
import { Sparkline } from '../components/Sparkline.tsx'

export function Appearance() {
  const t = useT()
  const toast = useToast()
  const { user, setUser } = useAuth()
  const [themeId, setThemeId] = useState(user?.prefs.theme ?? 'between-dark')
  // Prefs store "no custom accent" as '' — normalize to null so the
  // "Theme default" state actually renders as selected on load.
  const [accentId, setAccentId] = useState<string | null>(user?.prefs.accent || null)

  const apply = async (nextTheme: string, nextAccent: string | null) => {
    setThemeId(nextTheme)
    setAccentId(nextAccent)
    applyTheme(nextTheme, nextAccent)
    try {
      await api.patch('/api/auth/prefs', { theme: nextTheme, accent: nextAccent ?? '' })
      if (user) setUser({ ...user, prefs: { ...user.prefs, theme: nextTheme, accent: nextAccent ?? undefined } })
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }

  return (
    <div className="fade-in-up">
      <PageHeader title={t('appearance.title')} subtitle={t('appearance.subtitle')} />

      <div className="space-y-4">
        <Card>
          <CardHeader title={t('appearance.theme')} />
          <div className="stagger grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-3">
            {THEMES.map((theme) => (
              <button
                key={theme.id}
                onClick={() => void apply(theme.id, accentId)}
                aria-pressed={themeId === theme.id}
                className={cx(
                  'fade-in-up glass-subtle pressable overflow-hidden rounded-xl text-left',
                  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                  themeId === theme.id ? 'border-accent ring-2 ring-accent/40' : 'hover:border-accent/40',
                )}
              >
                {/* Mini live preview built from the theme's own tokens */}
                <div className="flex h-24 flex-col justify-between p-3" style={{ background: theme.vars['--t-bg'] }}>
                  <div className="flex items-center gap-1.5">
                    <span className="h-2.5 w-2.5 rounded-full" style={{ background: theme.vars['--t-accent'] }} />
                    <span className="h-2.5 w-2.5 rounded-full" style={{ background: theme.vars['--t-accent2'] }} />
                    <span className="h-2.5 w-2.5 rounded-full" style={{ background: theme.vars['--t-elevated'] }} />
                  </div>
                  <div className="rounded-lg border p-2" style={{ background: theme.vars['--t-surface'], borderColor: theme.vars['--t-line'] }}>
                    <div className="flex items-center justify-between gap-2">
                      <div className="min-w-0 space-y-1.5">
                        <div className="h-1.5 w-16 rounded-full" style={{ background: theme.vars['--t-text'], opacity: 0.75 }} />
                        <div className="h-1.5 w-10 rounded-full" style={{ background: theme.vars['--t-muted'], opacity: 0.5 }} />
                      </div>
                      <span
                        className="h-4 w-9 shrink-0 rounded-full"
                        style={{ background: `linear-gradient(120deg, ${theme.vars['--t-accent']}, ${theme.vars['--t-accent2']})` }}
                      />
                    </div>
                  </div>
                </div>
                <div className="flex items-center justify-between border-t border-line/60 px-3 py-2">
                  <span className="text-[0.8125rem] font-semibold">{theme.name}</span>
                  {themeId === theme.id && (
                    <span className="scale-in inline-flex h-4.5 w-4.5 items-center justify-center rounded-full btn-gradient">
                      <Check size={11} strokeWidth={3} />
                    </span>
                  )}
                </div>
              </button>
            ))}
          </div>
        </Card>

        <Card>
          <CardHeader title={t('appearance.accent')} />
          <div className="flex flex-wrap items-center gap-3 p-4">
            {/* "Theme default" leads the row at swatch height; selection uses
                the same check-badge language as the theme cards above. */}
            <button
              onClick={() => void apply(themeId, null)}
              aria-pressed={accentId === null}
              className={cx(
                'ui-control pressable flex h-11 items-center gap-2 rounded-full px-4 text-xs font-medium',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                accentId === null ? 'border border-accent bg-accent/15 text-accent' : 'glass-subtle text-muted hover:text-text',
              )}
            >
              {accentId === null && (
                <span className="scale-in inline-flex h-4.5 w-4.5 shrink-0 items-center justify-center rounded-full btn-gradient">
                  <Check size={11} strokeWidth={3} />
                </span>
              )}
              {t('appearance.accentDefault')}
            </button>
            {ACCENTS.map((accent) => (
              <button
                key={accent.id}
                onClick={() => void apply(themeId, accent.id)}
                title={accent.id}
                aria-label={accent.id}
                aria-pressed={accentId === accent.id}
                className={cx(
                  'sheen pressable relative h-11 w-11 rounded-full hover:scale-105',
                  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                  accentId === accent.id && 'ring-2 ring-accent ring-offset-2 ring-offset-bg',
                )}
                style={{ background: `linear-gradient(120deg, ${accent.accent}, ${accent.accent2})` }}
              >
                {/* White badge (like Toggle's knob) so the check-badge stays
                    visible on the swatch's own gradient. */}
                {accentId === accent.id && (
                  <span className="scale-in absolute left-1/2 top-1/2 inline-flex h-4.5 w-4.5 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-white shadow-md">
                    <Check size={11} strokeWidth={3} style={{ color: accent.accent }} />
                  </span>
                )}
              </button>
            ))}
          </div>
        </Card>

        <Card>
          <CardHeader title={t('appearance.preview')} />
          <div className="p-4">
            <div className="glass-subtle flex flex-wrap items-center gap-4 rounded-xl p-4">
              <Button variant="primary">{t('common.save')}</Button>
              <Button variant="secondary">{t('common.cancel')}</Button>
              <Button variant="danger">{t('common.delete')}</Button>
              <StatusPill status="running" />
              <StatusPill status="crashed" />
              <Sparkline values={[3, 5, 2, 8, 6, 9, 4, 7, 10, 6]} className="text-accent" />
              <span className="text-gradient font-display text-lg font-bold">Between</span>
            </div>
          </div>
        </Card>
      </div>
    </div>
  )
}
