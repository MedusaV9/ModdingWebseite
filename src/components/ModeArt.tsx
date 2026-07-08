import { useId } from 'react'

export type ModeArtId = 'boss-rush' | 'battle-royale' | 'time-machine'

type ModeArtProps = {
  mode: ModeArtId
  className?: string
}

/**
 * Shared decorative SVG banner art for the three game-mode cards, used by
 * both the Home "Game modes" teaser and /modes. Always aria-hidden.
 */
export default function ModeArt({ mode, className = '' }: ModeArtProps) {
  const uid = useId()

  const svgProps = {
    viewBox: '0 0 400 96',
    preserveAspectRatio: 'xMidYMid slice',
    className: `block w-full ${className}`,
    'aria-hidden': true,
  } as const

  if (mode === 'boss-rush') {
    const chevronsId = `${uid}-chevrons`
    return (
      <svg {...svgProps}>
        <defs>
          <pattern
            id={chevronsId}
            width="48"
            height="96"
            patternUnits="userSpaceOnUse"
          >
            <rect width="48" height="96" fill="#eb204f" />
            <polygon fill="#ff2a6d" points="0,0 24,0 48,48 24,96 0,96 24,48" />
          </pattern>
        </defs>
        <rect width="400" height="96" fill={`url(#${chevronsId})`} />
        {/* Angular skull: cranium with square eyes + zigzag jaw */}
        <g transform="translate(306 22)">
          <polygon
            fill="#ffffff"
            points="0,0 60,0 60,34 54,46 48,34 42,46 36,34 30,46 24,34 18,46 12,34 6,46 0,34"
          />
          <rect x="10" y="10" width="12" height="12" fill="#0b0508" />
          <rect x="38" y="10" width="12" height="12" fill="#0b0508" />
        </g>
      </svg>
    )
  }

  if (mode === 'battle-royale') {
    const amberId = `${uid}-amber`
    return (
      <svg {...svgProps}>
        <defs>
          <linearGradient id={amberId} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#f89d37" />
            <stop offset="1" stopColor="#f0aa59" />
          </linearGradient>
        </defs>
        <rect width="400" height="96" fill={`url(#${amberId})`} />
        {/* Shrinking storm zone: concentric square outlines */}
        <g fill="none" stroke="#220f19">
          <rect x="190" y="-22" width="140" height="140" strokeWidth="2" opacity="0.35" />
          <rect x="210" y="-2" width="100" height="100" strokeWidth="2" opacity="0.55" />
          <rect x="228" y="16" width="64" height="64" strokeWidth="3" opacity="0.75" />
          <rect x="242" y="30" width="36" height="36" strokeWidth="3" />
        </g>
        {/* Tiny crosshair on the final zone */}
        <g fill="none" stroke="#ffffff" strokeWidth="2" strokeLinecap="square">
          <circle cx="260" cy="48" r="6" />
          <path d="M260 38v4" />
          <path d="M260 54v4" />
          <path d="M250 48h4" />
          <path d="M266 48h4" />
        </g>
      </svg>
    )
  }

  // time-machine
  const scanlinesId = `${uid}-scanlines`
  return (
    <svg {...svgProps}>
      <defs>
        <pattern
          id={scanlinesId}
          width="8"
          height="7"
          patternUnits="userSpaceOnUse"
        >
          <rect width="8" height="1" fill="rgba(255,42,109,0.3)" />
        </pattern>
      </defs>
      <rect width="400" height="96" fill="#220f19" />
      <rect width="400" height="96" fill={`url(#${scanlinesId})`} />
      {/* Echo: reversed second copy, offset behind the main clock */}
      <g
        fill="none"
        stroke="#ff2a6d"
        strokeWidth="4"
        strokeLinecap="square"
        opacity="0.45"
        transform="translate(226 48) scale(-1 1)"
      >
        <circle r="26" />
        <path d="M0 0v-16" />
        <path d="M0 0h12" />
      </g>
      <g
        fill="none"
        stroke="#ffffff"
        strokeWidth="4"
        strokeLinecap="square"
        transform="translate(206 48)"
      >
        <circle r="26" />
        <path d="M0 0v-16" />
        <path d="M0 0h12" />
      </g>
    </svg>
  )
}
