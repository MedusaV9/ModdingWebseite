import { useId } from 'react'

type EmblemProps = {
  className?: string
  /** Accessible name. When set the SVG is exposed as an image; otherwise it is decorative. */
  title?: string
}

/**
 * 12-point comic-burst starburst: 24 vertices alternating outer radius 46 /
 * inner radius 34, centered at 48,48 (viewBox 0 0 96 96).
 */
const BURST_POINTS =
  '48,2 56.8,15.16 71,8.16 72.04,23.96 87.84,25 80.84,39.2 94,48 80.84,56.8 87.84,71 72.04,72.04 71,87.84 56.8,80.84 48,94 39.2,80.84 25,87.84 23.96,72.04 8.16,71 15.16,56.8 2,48 15.16,39.2 8.16,25 23.96,23.96 25,8.16 39.2,15.16'

/**
 * The site's signature mark: a comic-burst starburst with an amber "misprint"
 * duplicate behind it, crossed by a white wrench (+45°) and lightning bolt
 * (−45°) glyph. Reads clearly down to 16px.
 */
export default function Emblem({ className = '', title }: EmblemProps) {
  const gradientId = useId()

  return (
    <svg
      viewBox="0 0 96 96"
      className={className}
      {...(title ? { role: 'img' } : { 'aria-hidden': true })}
    >
      {title ? <title>{title}</title> : null}
      <defs>
        {/* Matches the primary CSS gradient: linear-gradient(to left, #eb204f, #ff2a6d) */}
        <linearGradient id={gradientId} x1="1" y1="0" x2="0" y2="0">
          <stop offset="0" stopColor="#eb204f" />
          <stop offset="1" stopColor="#ff2a6d" />
        </linearGradient>
      </defs>
      <polygon points={BURST_POINTS} fill="#f89d37" transform="translate(4 4)" />
      <polygon points={BURST_POINTS} fill={`url(#${gradientId})`} />
      <g
        fill="none"
        stroke="#ffffff"
        strokeWidth={5}
        strokeLinecap="square"
        strokeLinejoin="miter"
      >
        {/* Wrench at +45°: open two-prong jaw + straight handle */}
        <g transform="rotate(45 48 48)">
          <path d="M40 26v8l8 8 8-8v-8" />
          <path d="M48 42v28" />
        </g>
        {/* Lightning bolt at −45° */}
        <path transform="rotate(-45 48 48)" d="M52 24 44 46h8L44 68" />
      </g>
    </svg>
  )
}
