type MarqueeProps = {
  text: string
  className?: string
}

const REPEAT_COUNT = 12

export default function Marquee({ text, className = '' }: MarqueeProps) {
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
            className="text-transparent"
            style={{ WebkitTextStroke: '1px #ff2a6d' }}
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
      <div className="flex w-max [animation:marquee_30s_linear_infinite]">
        {track(false)}
        {track(true)}
      </div>
    </div>
  )
}
