import { memo, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { ArrowDown } from 'lucide-react'
import type { ConsoleLine } from '../api/types.ts'
import { useT } from '../i18n/index.tsx'

/** Minimal ANSI SGR color parser → spans. Handles 30-37/90-97 fg + reset + bold. */
const ANSI_COLORS: Record<number, string> = {
  30: '#6b7280', 31: '#f87171', 32: '#4ade80', 33: '#facc15', 34: '#60a5fa', 35: '#c084fc', 36: '#22d3ee', 37: '#e5e7eb',
  90: '#9ca3af', 91: '#fca5a5', 92: '#86efac', 93: '#fde047', 94: '#93c5fd', 95: '#d8b4fe', 96: '#67e8f9', 97: '#f9fafb',
}

function renderAnsi(text: string): ReactNode {
  if (!text.includes('\u001b[')) return text
  const parts: ReactNode[] = []
  const re = /\u001b\[([0-9;]*)m/g
  let last = 0
  let color: string | null = null
  let bold = false
  let match: RegExpExecArray | null
  let key = 0
  while ((match = re.exec(text)) !== null) {
    if (match.index > last) {
      const chunk = text.slice(last, match.index)
      parts.push(
        color || bold ? (
          <span key={key++} style={{ color: color ?? undefined, fontWeight: bold ? 600 : undefined }}>
            {chunk}
          </span>
        ) : (
          chunk
        ),
      )
    }
    for (const code of match[1].split(';').map((c) => parseInt(c || '0', 10))) {
      if (code === 0) {
        color = null
        bold = false
      } else if (code === 1) bold = true
      else if (ANSI_COLORS[code]) color = ANSI_COLORS[code]
    }
    last = re.lastIndex
  }
  if (last < text.length) {
    const chunk = text.slice(last)
    parts.push(
      color || bold ? (
        <span key={key++} style={{ color: color ?? undefined, fontWeight: bold ? 600 : undefined }}>
          {chunk}
        </span>
      ) : (
        chunk
      ),
    )
  }
  return parts
}

// Pinned --console-text* tokens (index.css), NOT theme tokens: the console
// surface is theme-invariant dark, so its text must be too (theme text/accent
// colors are near-black on light themes — black-on-black otherwise).
const STREAM_STYLE: Record<ConsoleLine['stream'], string> = {
  stdout: 'text-(--console-text)',
  stderr: 'text-(--console-text-stderr)',
  system: 'text-(--console-text-system)',
  input: 'text-(--console-text-input)',
  install: 'text-(--console-text-install)',
}

const Line = memo(function Line({ line, showTime }: { line: ConsoleLine; showTime: boolean }) {
  return (
    <div className="flex gap-2 px-3 hover:bg-white/[0.03]">
      {/* Gutter hidden below sm: game logs carry their own [hh:mm:ss] and the
          double timestamp ate ~40% of a phone viewport. The user toggle
          (showTimestamps) removes it entirely on every breakpoint. */}
      {showTime && (
        <span className="shrink-0 select-none text-(--console-text-dim) max-sm:hidden">
          {new Date(line.ts).toLocaleTimeString(undefined, { hour12: false })}
        </span>
      )}
      <span className={`min-w-0 whitespace-pre-wrap break-words [overflow-wrap:anywhere] ${STREAM_STYLE[line.stream]}`}>
        {renderAnsi(line.line)}
      </span>
    </div>
  )
})

export function Terminal({
  lines,
  filter,
  className,
  showTimestamps = true,
}: {
  lines: ConsoleLine[]
  filter?: string
  className?: string
  showTimestamps?: boolean
}) {
  const t = useT()
  const ref = useRef<HTMLDivElement>(null)
  const [autoScroll, setAutoScroll] = useState(true)

  // Case-insensitive substring filter over the scrollback (display only —
  // the buffer itself is untouched). Empty query = the unfiltered fast path.
  const query = (filter ?? '').trim().toLowerCase()
  const visible = useMemo(() => {
    const base = query ? lines.filter((l) => l.line.toLowerCase().includes(query)) : lines
    return base.slice(-1500)
  }, [lines, query])

  useEffect(() => {
    if (autoScroll && ref.current) ref.current.scrollTop = ref.current.scrollHeight
  }, [visible, autoScroll])

  // A changed query invalidates the previous scroll position, so the filtered
  // view snaps back to the bottom (newest matches first in view). Runs only
  // when the query actually changes — the unfiltered path never re-triggers.
  useEffect(() => {
    setAutoScroll(true)
    if (ref.current) ref.current.scrollTop = ref.current.scrollHeight
  }, [query])

  const onScroll = () => {
    const el = ref.current
    if (!el) return
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40
    setAutoScroll(atBottom)
  }

  return (
    // Glass-adjacent frame: the console keeps its fixed dark surface for
    // readability, wrapped in a rounded hairline. className comes last so
    // embedding pages can override the frame (e.g. rounded-none border-0).
    <div className={`relative overflow-hidden rounded-xl border border-line/60 ${className ?? ''}`}>
      <div
        ref={ref}
        onScroll={onScroll}
        className="console-scroll h-full overflow-y-auto bg-(--console-bg) py-2 font-mono text-[12px] leading-[1.45]"
      >
        {visible.length === 0 ? (
          <div className="flex h-full items-center justify-center text-(--console-text-dim)">
            {query ? t('console.noMatches') : t('console.emptyBuffer')}
          </div>
        ) : (
          // seq gives a stable identity: with positional keys every append past
          // the render cap used to shift all keys and re-mount the whole list.
          // ts is included because seq restarts with every panel restart.
          visible.map((line, i) => (
            <Line key={line.seq !== undefined ? `${line.ts}#${line.seq}` : `${line.ts}-${i}`} line={line} showTime={showTimestamps} />
          ))
        )}
      </div>
      {/* Subtle inner shadow drawn above the content. Fixed low-alpha rgba is
          intentional here: it sits on the theme-invariant dark console bg. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 rounded-xl shadow-[inset_0_1px_0_rgba(255,255,255,0.04),inset_0_0_20px_rgba(0,0,0,0.28)]"
      />
      {!autoScroll && (
        <button
          onClick={() => {
            setAutoScroll(true)
            if (ref.current) ref.current.scrollTop = ref.current.scrollHeight
          }}
          aria-label={t('console.autoscroll')}
          title={t('console.autoscroll')}
          className="glass-subtle pressable ui-control icon-btn absolute bottom-3 right-4 inline-flex h-9 w-9 items-center justify-center rounded-full text-muted shadow-[inset_0_1px_0_var(--glass-highlight),var(--glass-shadow)] hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
        >
          <ArrowDown size={15} />
        </button>
      )}
    </div>
  )
}
