import { useCallback, useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { TriangleAlert, X } from 'lucide-react'
import { Button, cx } from './ui.tsx'
import { useT } from '../i18n/index.tsx'

/** Tabbable elements for the focus trap (panel itself is tabindex=-1 → excluded). */
const FOCUSABLE = 'a[href], button:not([disabled]), textarea, input, select, [tabindex]:not([tabindex="-1"])'

export function Modal({
  open,
  onClose,
  title,
  children,
  footer,
  wide,
  dirty,
  tone,
}: {
  open: boolean
  onClose: () => void
  title: ReactNode
  children: ReactNode
  footer?: ReactNode
  wide?: boolean
  /** When true, backdrop/Escape/X ask for confirmation instead of discarding edits silently. */
  dirty?: boolean
  /** Optional header treatment; `danger` tints the header for destructive dialogs. */
  tone?: 'default' | 'danger'
}) {
  const t = useT()
  const [confirmDiscard, setConfirmDiscard] = useState(false)
  const titleId = useId()
  const panelRef = useRef<HTMLDivElement | null>(null)
  const discardRef = useRef<HTMLDivElement | null>(null)

  // Focus-restore target, captured at RENDER time on the closed→open
  // transition: React fires child `autoFocus` during commit (before any
  // effect runs), so an effect would already see focus inside the dialog
  // and lose the opener. Idempotent read + write, safe under StrictMode.
  const restoreFocusRef = useRef<HTMLElement | null>(null)
  const prevOpenRef = useRef(false)
  if (open && !prevOpenRef.current) {
    restoreFocusRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
  }
  prevOpenRef.current = open

  const attemptClose = useCallback(() => {
    if (dirty) setConfirmDiscard(true)
    else onClose()
  }, [dirty, onClose])

  useEffect(() => {
    if (!open) setConfirmDiscard(false)
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') attemptClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, attemptClose])

  // Initial focus on open (child autoFocus wins), restore to opener on close.
  useEffect(() => {
    if (!open) return
    const panel = panelRef.current
    if (panel && !panel.contains(document.activeElement)) {
      const first = panel.querySelector<HTMLElement>(FOCUSABLE)
      ;(first ?? panel).focus()
    }
    return () => {
      // StrictMode re-invokes mount effects with the dialog still in the DOM;
      // only restore focus when the panel really unmounted (close).
      if (panel && panel.isConnected) return
      const prev = restoreFocusRef.current
      if (prev && prev.isConnected) prev.focus()
    }
  }, [open])

  // Trap Tab/Shift+Tab inside the panel — or inside the dirty-discard
  // prompt while it is up (it overlays the panel, so it must be the only
  // reachable scope until dismissed).
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return
      const scope = discardRef.current ?? panelRef.current
      if (!scope) return
      const items = Array.from(scope.querySelectorAll<HTMLElement>(FOCUSABLE))
      if (items.length === 0) {
        e.preventDefault()
        panelRef.current?.focus()
        return
      }
      const first = items[0]
      const last = items[items.length - 1]
      const active = document.activeElement
      const inside = active instanceof HTMLElement && scope.contains(active)
      if (e.shiftKey) {
        if (!inside || active === first) {
          e.preventDefault()
          last.focus()
        }
      } else if (!inside || active === last) {
        e.preventDefault()
        first.focus()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  // Dirty-discard prompt: focus its first control (the non-destructive
  // "keep editing" button); hand focus back into the panel when dismissed.
  useEffect(() => {
    if (!confirmDiscard) return
    const before = document.activeElement instanceof HTMLElement ? document.activeElement : null
    discardRef.current?.querySelector<HTMLElement>(FOCUSABLE)?.focus()
    return () => {
      if (before && before.isConnected) before.focus()
    }
  }, [confirmDiscard])

  if (!open) return null
  // Portal to <body>: escapes transformed/filtered ancestors that would
  // otherwise become the containing block for this fixed overlay.
  return createPortal(
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-4">
      <div className="fade-in absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={attemptClose} />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className={cx(
          // Mobile (<sm): Apple-style bottom sheet pinned to the bottom edge.
          // Desktop (≥sm): centered glass dialog with a springy scale-in.
          'glass-strong relative flex max-h-[92dvh] w-full flex-col overflow-hidden outline-none',
          'safe-bottom rounded-t-2xl border-x-0 border-b-0 sm:max-h-[88dvh] sm:rounded-2xl sm:border-x sm:border-b sm:pb-0',
          'slide-up-sheet sm:scale-in',
          wide ? 'sm:max-w-3xl' : 'sm:max-w-lg',
        )}
      >
        {/* Decorative grab handle (bottom-sheet mode only). The wrapper carries
            the danger tint (padding, not child margin, so the tint covers the
            whole strip) — the sheet top must read as one surface with the
            tinted header below. */}
        <div aria-hidden className={cx('shrink-0 pt-2 sm:hidden', tone === 'danger' && 'bg-danger/10')}>
          <div className="mx-auto h-[5px] w-9 rounded-full bg-text/20" />
        </div>
        <div
          className={cx(
            'flex shrink-0 items-center justify-between gap-3 border-b px-4 py-3',
            tone === 'danger' ? 'border-danger/20 bg-danger/10' : 'border-line/60',
          )}
        >
          <h3 id={titleId} className="flex min-w-0 items-center gap-2.5 font-display text-[0.9375rem] font-semibold tracking-tight">
            {tone === 'danger' && (
              <span className="inline-flex shrink-0 items-center justify-center rounded-lg bg-danger/15 p-1.5 text-danger">
                <TriangleAlert size={15} />
              </span>
            )}
            <span className="min-w-0">{title}</span>
          </h3>
          <button
            onClick={attemptClose}
            aria-label={t('common.close')}
            title={t('common.close')}
            className="pressable shrink-0 rounded-lg p-1.5 text-muted hover:bg-elevated/70 hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
          >
            <X size={16} />
          </button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">{children}</div>
        {footer && <div className="flex shrink-0 justify-end gap-2 border-t border-line/60 px-4 py-3">{footer}</div>}
        {confirmDiscard && (
          <div ref={discardRef} className="fade-in absolute inset-0 z-10 flex items-center justify-center bg-black/55 p-6">
            <div className="glass-strong scale-in w-full max-w-sm rounded-2xl p-4">
              <h4 className="font-display text-[0.875rem] font-semibold tracking-tight">{t('common.discardTitle')}</h4>
              <p className="mt-1.5 text-[0.8125rem] leading-relaxed text-muted">{t('common.discardBody')}</p>
              <div className="mt-4 flex justify-end gap-2">
                <Button variant="ghost" size="sm" onClick={() => setConfirmDiscard(false)}>
                  {t('common.keepEditing')}
                </Button>
                <Button
                  variant="danger"
                  size="sm"
                  onClick={() => {
                    setConfirmDiscard(false)
                    onClose()
                  }}
                >
                  {t('common.discard')}
                </Button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>,
    document.body,
  )
}

export function ConfirmModal({
  open,
  onClose,
  onConfirm,
  title,
  message,
  danger,
  confirmLabel,
  children,
  loading,
}: {
  open: boolean
  onClose: () => void
  onConfirm: () => void
  title?: ReactNode
  message: ReactNode
  danger?: boolean
  confirmLabel?: string
  children?: ReactNode
  loading?: boolean
}) {
  const t = useT()
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title ?? t('confirm.title')}
      tone={danger ? 'danger' : undefined}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            {t('common.cancel')}
          </Button>
          <Button variant={danger ? 'danger' : 'primary'} onClick={onConfirm} loading={loading}>
            {confirmLabel ?? t('common.confirm')}
          </Button>
        </>
      }
    >
      <p className="text-sm leading-relaxed text-text/90">{message}</p>
      {children}
    </Modal>
  )
}
