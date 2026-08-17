import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from 'react'
import { ChevronRight, RotateCw, SquareTerminal } from 'lucide-react'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { Button, Card, EmptyState, Input, cx } from '../../components/ui.tsx'

const MAX_SCROLLBACK_CHARS = 200_000

type ShellStatus = 'connecting' | 'connected' | 'closed'

// The exec runs with a TTY, so output carries terminal control sequences.
// This tab renders plain text (not a full terminal emulator) — strip ANSI
// OSC/CSI sequences and carriage returns so the scrollback stays readable.
// Matching the ESC/BEL control characters is the whole point here:
// eslint-disable-next-line no-control-regex
const OSC_RE = /\u001b\][^\u0007\u001b]*(\u0007|\u001b\\)/g
// eslint-disable-next-line no-control-regex
const CSI_RE = /\u001b\[[0-9;?]*[ -/]*[@-~]/g

function cleanChunk(text: string): string {
  return text.replace(OSC_RE, '').replace(CSI_RE, '').replace(/\r/g, '')
}

const PILL_STYLE: Record<ShellStatus, string> = {
  connecting: 'border-warn/30 bg-warn/10 text-warn',
  connected: 'border-success/30 bg-success/10 text-success',
  closed: 'text-muted',
}

export function ShellTab() {
  const { server } = useServer()
  const t = useT()
  const [status, setStatus] = useState<ShellStatus>('connecting')
  const [scrollback, setScrollback] = useState('')
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [command, setCommand] = useState('')
  // Bumped by the Reconnect button — re-runs the socket effect.
  const [attempt, setAttempt] = useState(0)
  const wsRef = useRef<WebSocket | null>(null)
  const scrollRef = useRef<HTMLDivElement>(null)
  const [autoScroll, setAutoScroll] = useState(true)
  const history = useRef<string[]>([])
  const historyIdx = useRef(-1)

  const isDocker = server.runtime === 'docker'

  useEffect(() => {
    if (!isDocker) return
    setStatus('connecting')
    setErrorMsg(null)
    setScrollback('')
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(`${proto}://${location.host}/api/servers/${server.id}/shell`)
    wsRef.current = ws
    ws.onmessage = (ev) => {
      const text = String(ev.data)
      // Control frames are JSON ({t:'ready'|'error'}); everything else is
      // raw shell output.
      if (text.startsWith('{')) {
        try {
          const msg = JSON.parse(text) as { t?: string; message?: string }
          if (msg.t === 'ready') {
            setStatus('connected')
            ws.send(JSON.stringify({ op: 'resize', cols: 120, rows: 30 }))
            return
          }
          if (msg.t === 'error') {
            setErrorMsg(msg.message ?? 'error')
            return
          }
        } catch {
          /* not a control frame — plain output */
        }
      }
      setScrollback((prev) => (prev + cleanChunk(text)).slice(-MAX_SCROLLBACK_CHARS))
    }
    ws.onclose = () => {
      if (wsRef.current === ws) setStatus('closed')
    }
    return () => {
      wsRef.current = null
      ws.close()
    }
  }, [server.id, isDocker, attempt])

  useEffect(() => {
    if (autoScroll && scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight
  }, [scrollback, autoScroll])

  const onScroll = () => {
    const el = scrollRef.current
    if (!el) return
    setAutoScroll(el.scrollHeight - el.scrollTop - el.clientHeight < 40)
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    const ws = wsRef.current
    if (!ws || ws.readyState !== WebSocket.OPEN) return
    const cmd = command
    if (cmd.trim()) history.current = [cmd, ...history.current.slice(0, 49)]
    historyIdx.current = -1
    setCommand('')
    // The TTY echoes the command back, so no local echo is needed.
    ws.send(JSON.stringify({ op: 'stdin', data: cmd + '\n' }))
  }

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'ArrowUp') {
      e.preventDefault()
      const next = Math.min(historyIdx.current + 1, history.current.length - 1)
      if (history.current[next] !== undefined) {
        historyIdx.current = next
        setCommand(history.current[next])
      }
    } else if (e.key === 'ArrowDown') {
      e.preventDefault()
      const next = historyIdx.current - 1
      historyIdx.current = Math.max(next, -1)
      setCommand(next < 0 ? '' : history.current[next])
    }
  }

  if (!isDocker) {
    return <EmptyState icon={<SquareTerminal size={20} />} title={t('shell.notDocker')} />
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <SquareTerminal size={15} className="text-accent" />
        <span className="font-display text-sm font-semibold tracking-tight">{t('shell.title')}</span>
        <span className={cx('glass-subtle inline-flex items-center rounded-full px-2 py-0.5 text-[0.625rem] font-bold uppercase tracking-wide', PILL_STYLE[status])}>
          {status === 'connecting' ? t('shell.statusConnecting') : status === 'connected' ? t('shell.statusConnected') : t('shell.statusClosed')}
        </span>
        {status === 'closed' && (
          <Button size="sm" onClick={() => setAttempt((n) => n + 1)}>
            <RotateCw size={13} />
            {t('shell.reconnect')}
          </Button>
        )}
        <span className="basis-full text-xs text-muted">{t('shell.hint')}</span>
      </div>

      {errorMsg && (
        <div className="glass-subtle rounded-xl border-danger/30 bg-danger/10 px-3.5 py-2.5 text-[0.8125rem] text-danger">
          {t('shell.errorPrefix')} {errorMsg}
        </div>
      )}

      <Card className="overflow-hidden">
        <div className="relative">
          <div
            ref={scrollRef}
            onScroll={onScroll}
            className="console-scroll h-[40dvh] min-h-64 overflow-y-auto bg-(--console-bg) px-3 py-2 font-mono text-[12px] leading-[1.45] sm:h-[46vh]"
          >
            <pre className="whitespace-pre-wrap break-all font-mono text-text/90">{scrollback}</pre>
          </div>
          {!autoScroll && (
            <button
              onClick={() => {
                setAutoScroll(true)
                if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight
              }}
              className="glass-subtle pressable absolute bottom-3 right-4 rounded-full px-3 py-1 text-[0.6875rem] text-muted shadow-lg hover:text-text"
            >
              ↓ {t('console.autoscroll')}
            </button>
          )}
        </div>
        <form onSubmit={submit} className="flex items-center gap-2 border-t border-line/60 bg-elevated/40 px-3 py-2">
          <ChevronRight size={15} className="shrink-0 text-accent" />
          <Input
            value={command}
            onChange={(e) => setCommand(e.target.value)}
            onKeyDown={onKeyDown}
            placeholder={t('shell.inputPh')}
            disabled={status !== 'connected'}
            className="h-11 border-0 bg-transparent font-mono text-[13px] focus:bg-transparent focus:ring-0"
          />
        </form>
      </Card>
    </div>
  )
}
