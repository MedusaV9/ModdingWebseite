import { useId } from 'react'

/** Tiny dependency-free SVG area sparkline with an accent gradient stroke. */
export function Sparkline({
  values,
  max,
  width = 120,
  height = 34,
  className,
  strokeWidth = 1.5,
}: {
  values: number[]
  max?: number
  width?: number
  height?: number
  className?: string
  strokeWidth?: number
}) {
  const uid = useId()
  if (values.length < 2) {
    return <svg width={width} height={height} className={className} />
  }
  const hi = Math.max(...values)
  const lo = Math.min(...values)
  const flat = hi === lo
  // Normalization: an explicit `max` wins; otherwise 1.25× headroom keeps the
  // line off the top edge (peak = max would pin every local maximum to y≈4).
  // A constant series has no shape of its own — with no reference max it maps
  // to a level midline (flat-zero: the baseline) instead of the top edge.
  const peak = max ?? (flat ? (hi === 0 ? 1 : hi * 2) : hi * 1.25)
  const step = width / (values.length - 1)
  const points = values.map((v, i) => {
    const x = i * step
    const y = height - 2 - Math.min(1, v / peak) * (height - 6)
    return [x, y] as const
  })
  const line = points.map(([x, y], i) => `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`).join(' ')
  const area = `${line} L${width},${height} L0,${height} Z`
  const lineId = `spark-line-${uid}`
  const fillId = `spark-fill-${uid}`
  return (
    <svg width={width} height={height} className={className} viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
      <defs>
        {/* Theme vars don't work as SVG presentation attributes — set via style.
            userSpaceOnUse (not the objectBoundingBox default): a level line has
            a zero-height bbox, and bbox-relative gradients on degenerate boxes
            legally render as paint:none — the flat midline would vanish. */}
        <linearGradient id={lineId} gradientUnits="userSpaceOnUse" x1="0" y1="0" x2={width} y2="0">
          <stop offset="0" style={{ stopColor: 'var(--t-accent)' }} />
          <stop offset="1" style={{ stopColor: 'var(--t-accent2)' }} />
        </linearGradient>
        <linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" style={{ stopColor: 'var(--t-accent)', stopOpacity: 0.18 }} />
          <stop offset="1" style={{ stopColor: 'var(--t-accent)', stopOpacity: 0 }} />
        </linearGradient>
      </defs>
      {/* A flat series never gets the area fill — a uniform slab under a level
          line reads as "smeared glass", not a chart. Flat-zero stays subtle. */}
      {!flat && <path d={area} fill={`url(#${fillId})`} />}
      <path
        d={line}
        fill="none"
        stroke={`url(#${lineId})`}
        strokeOpacity={flat && hi === 0 ? 0.45 : undefined}
        strokeWidth={strokeWidth}
        strokeLinejoin="round"
        strokeLinecap="round"
      />
    </svg>
  )
}

export function ProgressBar({ pct, className, colorClass }: { pct: number; className?: string; colorClass?: string }) {
  const clamped = Math.max(0, Math.min(100, pct))
  const color =
    colorClass ?? (clamped > 90 ? 'bg-danger' : clamped > 70 ? 'bg-warn' : 'bg-[linear-gradient(100deg,var(--t-accent),var(--t-accent2))]')
  return (
    <div className={`glass-subtle h-2 w-full overflow-hidden rounded-full ${className ?? ''}`}>
      <div className={`h-full rounded-full transition-all duration-500 ${color}`} style={{ width: `${clamped}%` }} />
    </div>
  )
}
