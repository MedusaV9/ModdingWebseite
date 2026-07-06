import { useEffect, useRef, useState } from 'react'

type CountUpOptions = {
  durationMs?: number
}

/**
 * Animates an integer from 0 to `target` (easeOutCubic, requestAnimationFrame)
 * once the returned ref's element enters the viewport (observed once,
 * threshold 0.5). With prefers-reduced-motion the final value is set
 * immediately. rAF and observer are cleaned up on unmount.
 */
export default function useCountUp<T extends HTMLElement = HTMLElement>(
  target: number,
  { durationMs = 900 }: CountUpOptions = {},
) {
  const ref = useRef<T>(null)
  const [value, setValue] = useState(0)
  const rafRef = useRef<number | undefined>(undefined)

  useEffect(() => {
    const node = ref.current
    if (!node) return

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setValue(target)
      return
    }

    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries[0].isIntersecting) return
        observer.disconnect()

        const start = performance.now()
        const tick = (now: number) => {
          const progress = Math.min((now - start) / durationMs, 1)
          const eased = 1 - Math.pow(1 - progress, 3)
          setValue(Math.round(eased * target))
          if (progress < 1) {
            rafRef.current = requestAnimationFrame(tick)
          }
        }
        rafRef.current = requestAnimationFrame(tick)
      },
      { threshold: 0.5 },
    )
    observer.observe(node)

    return () => {
      observer.disconnect()
      if (rafRef.current !== undefined) cancelAnimationFrame(rafRef.current)
    }
  }, [target, durationMs])

  return { ref, value }
}
