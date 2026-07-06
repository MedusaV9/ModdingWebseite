import type { ReactNode } from 'react'

export type IconName =
  | 'download'
  | 'wrench'
  | 'radio'
  | 'clock'
  | 'shield'
  | 'gamepad'
  | 'bolt'
  | 'arrow-right'
  | 'search'
  | 'shuffle'
  | 'copy'
  | 'check'
  | 'external'
  | 'play'
  | 'pause'
  | 'skip-prev'
  | 'skip-next'
  | 'x'

/** Hand-drawn angular 24×24 stroke paths — no icon library. */
const PATHS: Record<IconName, ReactNode> = {
  download: (
    <>
      <path d="M12 3v11" />
      <path d="M7 10l5 5 5-5" />
      <path d="M4 20h16" />
    </>
  ),
  wrench: (
    <>
      <path d="M8 3v5l4 4 4-4V3" />
      <path d="M12 12v9" />
    </>
  ),
  radio: (
    <>
      <path d="M3 9h18v11H3z" />
      <path d="M7 9l10-6" />
      <path d="M7 13h4v4H7z" />
      <path d="M15 13h3" />
      <path d="M15 17h3" />
    </>
  ),
  clock: (
    <>
      <path d="M15.4 3.7H8.6L3.7 8.6v6.8l4.9 4.9h6.8l4.9-4.9V8.6z" />
      <path d="M12 7v5h4" />
    </>
  ),
  shield: (
    <>
      <path d="M12 3l8 3v6l-8 9-8-9V6z" />
      <path d="M9 11l2 2 4-4" />
    </>
  ),
  gamepad: (
    <>
      <path d="M4 7h16v10H4z" />
      <path d="M8 10v4" />
      <path d="M6 12h4" />
      <path d="M15 11h2" />
      <path d="M17 14h2" />
    </>
  ),
  bolt: (
    <>
      <path d="M13 3L8 13h7l-4 8" />
    </>
  ),
  'arrow-right': (
    <>
      <path d="M4 12h15" />
      <path d="M13 6l6 6-6 6" />
    </>
  ),
  search: (
    <>
      <path d="M4 4h11v11H4z" />
      <path d="M15 15l6 6" />
    </>
  ),
  shuffle: (
    <>
      <path d="M3 6h4l10 12h4" />
      <path d="M3 18h4l10-12h4" />
      <path d="M18 3l3 3-3 3" />
      <path d="M18 15l3 3-3 3" />
    </>
  ),
  copy: (
    <>
      <path d="M8 8h12v12H8z" />
      <path d="M4 16V4h12" />
    </>
  ),
  check: (
    <>
      <path d="M4 12l6 6L20 6" />
    </>
  ),
  external: (
    <>
      <path d="M19 13v7H4V5h7" />
      <path d="M14 4h6v6" />
      <path d="M20 4l-9 9" />
    </>
  ),
  play: (
    <>
      <path d="M7 4l14 8-14 8z" />
    </>
  ),
  pause: (
    <>
      <path d="M8 5v14" />
      <path d="M16 5v14" />
    </>
  ),
  'skip-prev': (
    <>
      <path d="M6 5v14" />
      <path d="M20 5l-10 7 10 7z" />
    </>
  ),
  'skip-next': (
    <>
      <path d="M18 5v14" />
      <path d="M4 5l10 7-10 7z" />
    </>
  ),
  x: (
    <>
      <path d="M5 5l14 14" />
      <path d="M19 5L5 19" />
    </>
  ),
}

type IconProps = {
  name: IconName
  className?: string
}

export default function Icon({ name, className = '' }: IconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="square"
      strokeLinejoin="miter"
      aria-hidden="true"
    >
      {PATHS[name]}
    </svg>
  )
}
