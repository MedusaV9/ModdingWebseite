type StickerProps = {
  className?: string
}

/** Angular ghost: rectangle body with a zigzag 3-tooth bottom edge and two square eyes. */
export function GhostSticker({ className = '' }: StickerProps) {
  return (
    <svg viewBox="0 0 48 48" className={className} aria-hidden="true">
      <polygon
        fill="#ff2a6d"
        points="8,6 40,6 40,36 34.7,42 29.3,36 24,42 18.7,36 13.3,42 8,36"
      />
      <rect x="15" y="16" width="5" height="5" fill="#ffffff" />
      <rect x="27" y="16" width="5" height="5" fill="#ffffff" />
    </svg>
  )
}

/** 4-point star polygon. */
export function SparkSticker({ className = '' }: StickerProps) {
  return (
    <svg viewBox="0 0 48 48" className={className} aria-hidden="true">
      <polygon
        fill="#f89d37"
        points="24,2 30,18 46,24 30,30 24,46 18,30 2,24 18,18"
      />
    </svg>
  )
}

/** Circle with 4 tick lines. */
export function CrosshairSticker({ className = '' }: StickerProps) {
  return (
    <svg viewBox="0 0 48 48" className={className} aria-hidden="true">
      <g
        fill="none"
        stroke="#ff2a6d"
        strokeWidth={3}
        strokeLinecap="square"
      >
        <circle cx="24" cy="24" r="14" />
        <path d="M24 2v8" />
        <path d="M24 38v8" />
        <path d="M2 24h8" />
        <path d="M38 24h8" />
      </g>
    </svg>
  )
}

/** An "!" (tall rectangle + square dot) in white inside a small burst on #eb204f. */
export function BangSticker({ className = '' }: StickerProps) {
  return (
    <svg viewBox="0 0 48 48" className={className} aria-hidden="true">
      <polygon
        fill="#eb204f"
        points="24,2 29.7,10.1 39.6,8.4 37.9,18.3 46,24 37.9,29.7 39.6,39.6 29.7,37.9 24,46 18.3,37.9 8.4,39.6 10.1,29.7 2,24 10.1,18.3 8.4,8.4 18.3,10.1"
      />
      <rect x="21" y="12" width="6" height="14" fill="#ffffff" />
      <rect x="21" y="30" width="6" height="6" fill="#ffffff" />
    </svg>
  )
}
