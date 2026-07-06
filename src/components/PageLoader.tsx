import Emblem from './brand/Emblem'

/** Suspense fallback shown inside <main> while a route chunk loads. */
export default function PageLoader() {
  return (
    <div
      role="status"
      aria-label="Loading page"
      className="flex min-h-[60vh] w-full flex-col items-center justify-center gap-4"
    >
      <Emblem className="h-16 w-16 animate-pulse" />
      <span className="font-teko uppercase text-2xl leading-none text-white/60">
        LOADING
      </span>
    </div>
  )
}
