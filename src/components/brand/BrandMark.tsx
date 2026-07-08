import Emblem from './Emblem'

type BrandMarkProps = {
  className?: string
}

/** Horizontal brand lockup: Emblem + "BAPBAP·MODS" wordmark. */
export default function BrandMark({ className = '' }: BrandMarkProps) {
  return (
    <span className={`inline-flex items-center gap-2 ${className}`}>
      <Emblem className="h-7 w-7" />
      <span className="font-display text-lg uppercase leading-none">
        <span className="text-white">BAPBAP</span>
        <span className="text-bap-pink">·MODS</span>
      </span>
    </span>
  )
}
