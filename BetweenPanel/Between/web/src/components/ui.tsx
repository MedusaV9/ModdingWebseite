import { cloneElement, isValidElement, useId, type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactElement, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes } from 'react'
import { Check, Loader2 } from 'lucide-react'

export function cx(...parts: (string | false | null | undefined)[]): string {
  return parts.filter(Boolean).join(' ')
}

// Shared focus treatment — the app-wide focus-visible standard (see DESIGN.md).
const FOCUS_RING = 'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40'

// ---------------------------------------------------------------------------
type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'success'

const BTN_BASE = cx(
  'ui-control inline-flex items-center justify-center gap-1.5 rounded-xl font-medium pressable select-none whitespace-nowrap',
  'disabled:opacity-40 disabled:saturate-50 disabled:cursor-not-allowed',
  FOCUS_RING,
)
const BTN_STYLES: Record<ButtonVariant, string> = {
  // Disabled primary is styled by `.btn-gradient:disabled` in index.css (flat
  // elevated chip, no gradient/glow) — utilities can't beat the unlayered
  // .btn-gradient background, so the treatment lives next to it.
  primary: 'btn-gradient glow-accent',
  secondary: 'glass-subtle text-text hover:bg-elevated/70 hover:border-accent/40',
  ghost: 'text-muted hover:text-text hover:bg-elevated/70',
  danger: 'bg-danger/15 text-danger border border-danger/30 hover:bg-danger/25',
  success: 'bg-success/15 text-success border border-success/30 hover:bg-success/25',
}

export function Button({
  variant = 'secondary',
  size = 'md',
  loading,
  className,
  children,
  disabled,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant; size?: 'sm' | 'md' | 'lg'; loading?: boolean }) {
  const sizeCls =
    size === 'sm' ? 'h-7 rounded-lg px-2.5 text-xs' : size === 'lg' ? 'h-11 px-5 text-sm' : 'h-9 px-3.5 text-[0.8125rem]'
  return (
    // While a mutation is in flight the button must not be clickable again —
    // double-clicking "Create" / "Restore" would fire duplicate requests.
    <button className={cx(BTN_BASE, BTN_STYLES[variant], sizeCls, className)} disabled={loading || disabled} {...rest}>
      {loading && <Loader2 size={14} className="animate-spin" />}
      {children}
    </button>
  )
}

// ---------------------------------------------------------------------------
const FIELD_BASE =
  'ui-control rounded-xl border border-line/70 bg-surface/60 text-[0.8125rem] text-text placeholder:text-muted/60 transition duration-150'
const FIELD_FOCUS = 'focus:border-accent/60 focus:bg-surface/80 focus:outline-none focus:ring-2 focus:ring-accent/30'

export function Input({ className, ...rest }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cx('h-9 w-full px-3', FIELD_BASE, FIELD_FOCUS, className)} {...rest} />
}

export function TextArea({ className, ...rest }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea className={cx('w-full px-3 py-2', FIELD_BASE, FIELD_FOCUS, className)} {...rest} />
}

export function Select({ className, children, ...rest }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select className={cx('h-9 w-full px-2.5', FIELD_BASE, FIELD_FOCUS, className)} {...rest}>
      {children}
    </select>
  )
}

export function Toggle({
  checked,
  onChange,
  label,
  disabled,
  'aria-label': ariaLabel,
  'aria-labelledby': ariaLabelledby,
}: {
  checked: boolean
  onChange: (v: boolean) => void
  label?: ReactNode
  disabled?: boolean
  /** Accessible name for the switch when no visible `label` is rendered. */
  'aria-label'?: string
  'aria-labelledby'?: string
}) {
  return (
    <label className={cx('flex cursor-pointer items-center gap-2.5 select-none', disabled && 'opacity-50 pointer-events-none')}>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={ariaLabel}
        aria-labelledby={ariaLabelledby}
        onClick={() => onChange(!checked)}
        className={cx('pressable relative h-7 w-12 shrink-0 rounded-full', FOCUS_RING, checked ? 'btn-gradient' : 'bg-line')}
      >
        <span
          className={cx(
            'absolute left-0.5 top-0.5 h-6 w-6 rounded-full bg-white shadow-md transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)]',
            checked ? 'translate-x-5' : 'translate-x-0',
          )}
        />
      </button>
      {label && <span className="text-[0.8125rem]">{label}</span>}
    </label>
  )
}

/**
 * Glass checkbox — a real controlled `<input type="checkbox">` (native
 * semantics, form participation, screen-reader state) under a crafted skin:
 * glass-subtle square when idle, accent gradient + check when checked.
 * `label` renders an inline text label; pass `aria-label` when omitting it.
 * `className` extends the outer <label> wrapper. Native `checked`/`onChange`
 * (ChangeEvent) contract — read `e.target.checked`.
 */
export function Checkbox({
  label,
  className,
  disabled,
  ...rest
}: Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> & { label?: string }) {
  return (
    <label
      className={cx(
        'inline-flex cursor-pointer select-none items-center gap-2',
        disabled && 'cursor-not-allowed opacity-50',
        className,
      )}
    >
      {/* The input can't contain children, so the check icon overlays it from
          a relative wrapper; peer-checked drives its visibility. */}
      <span className="relative inline-flex shrink-0">
        <input
          type="checkbox"
          disabled={disabled}
          className={cx(
            'peer glass-subtle pressable h-4.5 w-4.5 appearance-none rounded-lg',
            'checked:border-transparent checked:[background:linear-gradient(100deg,var(--t-accent),var(--t-accent2))]',
            'disabled:cursor-not-allowed',
            FOCUS_RING,
          )}
          {...rest}
        />
        <Check
          size={12}
          strokeWidth={3.5}
          aria-hidden
          className={cx(
            'pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 text-onaccent',
            'scale-50 opacity-0 transition duration-150 peer-checked:scale-100 peer-checked:opacity-100',
          )}
        />
      </span>
      {label && <span className="text-[0.8125rem]">{label}</span>}
    </label>
  )
}

export function Field({ label, hint, children, error }: { label: ReactNode; hint?: ReactNode; children: ReactNode; error?: string | null }) {
  const autoId = useId()
  // Single-element children (the common case: exactly one Input/Select/
  // TextArea) get wired up automatically — label→htmlFor and hint/error→
  // aria-describedby. Multi-element children stay untouched; explicit
  // id/aria-describedby on the child always win.
  const single = isValidElement(children) ? (children as ReactElement<{ id?: string; 'aria-describedby'?: string }>) : null
  const controlId = single ? (single.props.id ?? autoId) : undefined
  const describedBy = error ? `${autoId}-error` : hint ? `${autoId}-hint` : undefined
  const control = single
    ? cloneElement(single, { id: controlId, 'aria-describedby': single.props['aria-describedby'] ?? describedBy })
    : children
  return (
    <div className="space-y-1.5">
      {/* .microlabel = THE content micro-label spec (see DESIGN.md). */}
      <label htmlFor={controlId} className="microlabel block">{label}</label>
      {control}
      {hint && !error && <p id={`${autoId}-hint`} className="text-xs leading-snug text-muted/80">{hint}</p>}
      {error && <p id={`${autoId}-error`} className="text-xs text-danger">{error}</p>}
    </div>
  )
}

export function Card({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={cx('glass rounded-2xl', className)}>{children}</div>
}

export function CardHeader({ title, subtitle, actions }: { title: ReactNode; subtitle?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-3 border-b border-line/60 px-4 py-3">
      <div>
        <h3 className="font-display text-[0.9375rem] font-semibold tracking-tight">{title}</h3>
        {subtitle && <p className="mt-0.5 text-xs text-muted">{subtitle}</p>}
      </div>
      {actions}
    </div>
  )
}

export function EmptyState({ icon, title, body, action }: { icon?: ReactNode; title: ReactNode; body?: ReactNode; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center gap-4 py-14 text-center">
      {icon && <div className="glass-subtle rounded-2xl p-4 text-muted/60">{icon}</div>}
      {/* With a `body`, the title steps up to a real heading; without one the
          original single muted line is preserved (all existing call sites). */}
      {body ? (
        <div>
          <p className="font-display text-[0.9375rem] font-semibold tracking-tight">{title}</p>
          <p className="mx-auto mt-1 max-w-sm text-sm leading-relaxed text-muted">{body}</p>
        </div>
      ) : (
        <p className="max-w-sm text-sm text-muted">{title}</p>
      )}
      {action}
    </div>
  )
}

export function PageHeader({ title, subtitle, actions }: { title: ReactNode; subtitle?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  )
}

export function Spinner({ label }: { label?: string }) {
  return (
    <div className="flex items-center justify-center gap-2 py-10 text-muted">
      <Loader2 size={18} className="animate-spin" />
      {label && <span className="text-sm">{label}</span>}
    </div>
  )
}

/**
 * Skeleton loading block — a glass-subtle placeholder with a shimmer sweep
 * (static under prefers-reduced-motion; see .skeleton in index.css). Shape it
 * with utilities: size (`h-4 w-40`) and, where needed, radius (base is
 * rounded-xl; use `rounded-full` for text lines/pills, `rounded-2xl` for
 * card-sized blocks). Compose content-shaped loaders that mirror the real
 * layout so the content swap doesn't jump. Decorative: always aria-hidden —
 * put aria-busy on the surface that is loading.
 */
export function Skeleton({ className }: { className?: string }) {
  return <div aria-hidden className={cx('skeleton', className)} />
}

export function Badge({ children, className, title }: { children: ReactNode; className?: string; title?: string }) {
  return (
    <span
      title={title}
      className={cx('glass-subtle inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[0.6875rem] font-medium text-muted', className)}
    >
      {children}
    </span>
  )
}

/** Filter/category pill: glass-subtle when idle, accent-tinted when active. */
export function Chip({
  active,
  className,
  children,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { active?: boolean }) {
  return (
    <button
      type="button"
      aria-pressed={active}
      className={cx(
        'ui-control pressable rounded-full px-3 py-1.5 text-xs font-medium capitalize',
        FOCUS_RING,
        active
          ? 'border border-accent/40 bg-accent/15 text-accent'
          : 'glass-subtle text-muted hover:bg-elevated/60 hover:text-text',
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  )
}

export function KeyboardHint({ children }: { children: ReactNode }) {
  return <kbd className="rounded-lg border border-line/70 bg-elevated/70 px-1.5 py-0.5 font-mono text-[0.625rem] text-muted">{children}</kbd>
}

// ---------------------------------------------------------------------------
export interface SegmentedOption<T extends string = string> {
  value: T
  label: ReactNode
  icon?: ReactNode
}

/**
 * iOS-style segmented tabs: a glass pill container with an animated thumb
 * behind the active segment. Equal-width segments (grid), no measurement.
 */
export function SegmentedControl<T extends string>({
  options,
  value,
  onChange,
  size = 'md',
  className,
  'aria-label': ariaLabel,
}: {
  options: SegmentedOption<T>[]
  value: T
  onChange: (value: T) => void
  size?: 'sm' | 'md'
  className?: string
  /** Accessible name for the radiogroup (what this control selects). */
  'aria-label'?: string
}) {
  const idx = options.findIndex((o) => o.value === value)
  const n = Math.max(options.length, 1)
  return (
    <div role="radiogroup" aria-label={ariaLabel} className={cx('glass-subtle relative isolate inline-grid auto-cols-fr grid-flow-col rounded-full p-1', className)}>
      {idx >= 0 && (
        <span
          aria-hidden
          className="sheen absolute -z-10 rounded-full bg-elevated/90 shadow-sm transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)]"
          style={{
            top: '0.25rem',
            bottom: '0.25rem',
            left: '0.25rem',
            width: `calc((100% - 0.5rem) / ${n})`,
            transform: `translateX(${idx * 100}%)`,
          }}
        />
      )}
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={o.value === value}
          onClick={() => onChange(o.value)}
          className={cx(
            'ui-control pressable inline-flex items-center justify-center gap-1.5 whitespace-nowrap rounded-full font-medium',
            FOCUS_RING,
            size === 'sm' ? 'h-6 px-2.5 text-xs' : 'h-8 px-3.5 text-[0.8125rem]',
            o.value === value ? 'text-text' : 'text-muted hover:text-text',
          )}
        >
          {o.icon}
          {o.label}
        </button>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
/** Square icon-only button for toolbars. `label` doubles as aria-label/title. */
export function IconButton({
  label,
  variant = 'ghost',
  size = 'md',
  loading,
  className,
  children,
  disabled,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { label: string; variant?: 'ghost' | 'glass'; size?: 'sm' | 'md'; loading?: boolean }) {
  return (
    <button
      aria-label={label}
      title={label}
      className={cx(
        'ui-control icon-btn pressable inline-flex shrink-0 items-center justify-center rounded-xl',
        'disabled:opacity-40 disabled:cursor-not-allowed',
        FOCUS_RING,
        size === 'sm' ? 'h-8 w-8' : 'h-9 w-9',
        variant === 'glass' ? 'glass-subtle text-text hover:bg-elevated/70' : 'text-muted hover:bg-elevated/70 hover:text-text',
        className,
      )}
      // Same rule as Button: an in-flight action must not be clickable again.
      disabled={loading || disabled}
      {...rest}
    >
      {loading ? <Loader2 size={size === 'sm' ? 13 : 15} className="animate-spin" /> : children}
    </button>
  )
}
