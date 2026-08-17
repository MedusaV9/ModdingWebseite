import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { CheckCircle2, AlertTriangle, XCircle, Info, X } from 'lucide-react'
import { useT } from '../i18n/index.tsx'

export type ToastKind = 'success' | 'error' | 'warn' | 'info'
interface Toast {
  id: number
  kind: ToastKind
  message: string
}

const ToastContext = createContext<{ toast: (kind: ToastKind, message: string) => void }>({
  toast: () => undefined,
})

const ICONS = {
  success: <CheckCircle2 size={16} className="text-success shrink-0" />,
  error: <XCircle size={16} className="text-danger shrink-0" />,
  warn: <AlertTriangle size={16} className="text-warn shrink-0" />,
  info: <Info size={16} className="text-accent shrink-0" />,
}

/** Status-tinted hairline per kind (overrides the .glass-strong border color). */
const BORDERS: Record<ToastKind, string> = {
  success: 'border-success/30',
  error: 'border-danger/30',
  warn: 'border-warn/30',
  info: 'border-accent/30',
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const t = useT()
  const [toasts, setToasts] = useState<Toast[]>([])
  const counter = useRef(0)
  const timers = useRef(new Map<number, ReturnType<typeof setTimeout>>())

  const dismiss = useCallback((id: number) => {
    const timer = timers.current.get(id)
    if (timer) clearTimeout(timer)
    timers.current.delete(id)
    setToasts((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const toast = useCallback(
    (kind: ToastKind, message: string) => {
      const id = ++counter.current
      setToasts((prev) => {
        for (const dropped of prev.slice(0, Math.max(0, prev.length - 4))) {
          const timer = timers.current.get(dropped.id)
          if (timer) clearTimeout(timer)
          timers.current.delete(dropped.id)
        }
        return [...prev.slice(-4), { id, kind, message }]
      })
      const timer = setTimeout(() => dismiss(id), kind === 'error' ? 8000 : 4500)
      timers.current.set(id, timer)
    },
    [dismiss],
  )

  const value = useMemo(() => ({ toast }), [toast])

  useEffect(
    () => () => {
      for (const timer of timers.current.values()) clearTimeout(timer)
      timers.current.clear()
    },
    [],
  )

  return (
    <ToastContext.Provider value={value}>
      {children}
      {/* Phones (<md): full-width cards floating above the bottom dock
          (dock ≈ 4.5rem tall incl. its inset; 5.5rem clears it). Tablets
          (md..lg): right-aligned cards, still above the dock — a full-width
          strip reads phone-ish at 768+. Desktop (≥lg, dock gone): classic
          bottom-right stack. */}
      <div className="pointer-events-none fixed inset-x-4 bottom-[calc(5.5rem+env(safe-area-inset-bottom,0px))] z-[100] flex flex-col gap-2 md:inset-x-auto md:right-4 md:w-80 lg:bottom-4">
        {toasts.map((item) => (
          <div
            key={item.id}
            className={`glass-strong fade-in-up pointer-events-auto flex items-start gap-2.5 rounded-xl px-3.5 py-3 ${BORDERS[item.kind]}`}
          >
            {ICONS[item.kind]}
            <div className="min-w-0 flex-1 text-[0.8125rem] leading-snug break-words">{item.message}</div>
            <button
              onClick={() => dismiss(item.id)}
              aria-label={t('common.close')}
              className="pressable -m-1 rounded-lg p-1 text-muted hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            >
              <X size={14} />
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  )
}

export function useToast() {
  return useContext(ToastContext).toast
}
