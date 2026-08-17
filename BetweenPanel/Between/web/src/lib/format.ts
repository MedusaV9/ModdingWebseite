export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B'
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  let v = bytes
  let i = 0
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  return `${v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)} ${units[i]}`
}

export function formatUptime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return '—'
  const d = Math.floor(seconds / 86400)
  const h = Math.floor((seconds % 86400) / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = Math.floor(seconds % 60)
  if (d > 0) return `${d}d ${h}h ${m}m`
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m ${s}s`
  return `${s}s`
}

/** Compact play-time duration in hours/minutes, e.g. "3h 12m", "45m", "<1m". */
export function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return ''
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m`
  return '<1m'
}

import type { I18nKey } from '../i18n/en.ts'

type TranslateFn = (key: I18nKey, params?: Record<string, string | number>) => string

// Absolute dates follow the app language, not the browser locale (a German UI
// must not show "08/15/26, 09:46:47 PM"). The i18n provider keeps this in
// sync via setDateLocale() so the many call sites stay parameterless.
const DATE_LOCALES: Record<string, string> = { en: 'en-US', de: 'de-DE' }
let dateLocale: string | undefined

export function setDateLocale(lang: string): void {
  dateLocale = DATE_LOCALES[lang]
}

export function timeAgo(iso: string | number, t?: TranslateFn): string {
  const then = typeof iso === 'number' ? iso : new Date(iso).getTime()
  const diff = Math.max(0, Date.now() - then)
  const min = Math.floor(diff / 60000)
  if (min < 1) return t ? t('time.justNow') : 'just now'
  if (min < 60) return t ? t('time.minutesAgo', { n: min }) : `${min}m ago`
  const hours = Math.floor(min / 60)
  if (hours < 24) return t ? t('time.hoursAgo', { n: hours }) : `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 30) return t ? t('time.daysAgo', { n: days }) : `${days}d ago`
  return new Date(then).toLocaleDateString(dateLocale)
}

export function formatDateTime(iso: string | number): string {
  const d = typeof iso === 'number' ? new Date(iso) : new Date(iso)
  return d.toLocaleString(dateLocale, {
    year: '2-digit',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}
