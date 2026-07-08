type MarqueeProps = {
  text: string
  className?: string
  /** Animation duration in seconds (lower = faster). */
  speed?: number
  direction?: 'left' | 'right'
  /** 'outline' = pink text stroke (default), 'solid' = filled pink text. */
  variant?: 'outline' | 'solid'
}

const REPEAT_COUNT = 12

export default function Marquee({
  text,
  className = '',
  speed = 30,
  direction = 'left',
  variant = 'outline',
}: MarqueeProps) {
  const items = Array.from({ length: REPEAT_COUNT })

  const track = (ariaHidden: boolean) => (
    <div
      aria-hidden={ariaHidden}
      className="flex shrink-0 items-center whitespace-nowrap"
    >
      {items.map((_, i) => (
        <span
          key={i}
          className="flex items-center font-display uppercase text-2xl md:text-3xl"
        >
          <span
            className={variant === 'solid' ? 'text-bap-pink' : 'text-transparent'}
            style={
              variant === 'solid'
                ? undefined
                : { WebkitTextStroke: '1px #ff2a6d' }
            }
          >
            {text}
          </span>
          <span className="mx-6 text-bap-pink">✕</span>
        </span>
      ))}
    </div>
  )

  return (
    <div
      className={`w-full overflow-hidden border-y border-bap-line bg-bap-black py-3 ${className}`}
    >
      <div
        className="flex w-max"
        style={{
          animation: `${
            direction === 'right' ? 'marquee-reverse' : 'marquee'
          } ${speed}s linear infinite`,
        }}
      >
        {track(false)}
        {track(true)}
      </div>
    </div>
  )
}
