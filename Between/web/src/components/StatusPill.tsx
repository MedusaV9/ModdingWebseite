import type { ServerStatus } from '../api/types.ts'
import { useT } from '../i18n/index.tsx'
import { cx } from './ui.tsx'

const STYLES: Record<ServerStatus, { dot: string; text: string; pulse?: boolean }> = {
  offline: { dot: 'bg-muted/60', text: 'text-muted' },
  installing: { dot: 'bg-accent', text: 'text-accent', pulse: true },
  install_failed: { dot: 'bg-danger', text: 'text-danger' },
  starting: { dot: 'bg-warn', text: 'text-warn', pulse: true },
  running: { dot: 'bg-success glow-success', text: 'text-success' },
  stopping: { dot: 'bg-warn', text: 'text-warn', pulse: true },
  crashed: { dot: 'bg-danger', text: 'text-danger' },
  updating: { dot: 'bg-accent', text: 'text-accent', pulse: true },
  // The MACHINE is unreachable, not the game: muted-danger, no pulse — the
  // game may well still be running on the node; the panel just can't see it.
  'node-offline': { dot: 'bg-danger/60', text: 'text-danger/80' },
}

export function StatusPill({ status, size = 'md' }: { status: ServerStatus; size?: 'sm' | 'md' }) {
  const t = useT()
  const style = STYLES[status] ?? STYLES.offline
  return (
    <span
      className={cx(
        'glass-subtle inline-flex items-center gap-1.5 whitespace-nowrap rounded-full font-medium',
        size === 'sm' ? 'px-2.5 py-1 text-[0.6875rem]' : 'px-3 py-1.5 text-xs',
        style.text,
      )}
    >
      <span className={cx('h-1.5 w-1.5 rounded-full', style.dot, style.pulse && 'pulse-dot')} />
      {t(`status.${status}` as 'status.offline')}
    </span>
  )
}
