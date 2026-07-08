import { useEffect, useRef, useState } from 'react'
import type { CSSProperties, RefObject } from 'react'

type RevealOptions = {
  /** When true, the result also includes childStyle(index) for staggered child delays. */
  stagger?: boolean
}

type RevealResult<T extends HTMLElement> = {
  ref: RefObject<T | null>
  className: string
}

type StaggerRevealResult<T extends HTMLElement> = RevealResult<T> & {
  /** Per-child transitionDelay (80ms steps, capped at index 5; 0 with reduced motion). */
  childStyle: (index: number) => CSSProperties
}

/**
 * Scroll-reveal hook: returns a ref plus transition classes that fade/slide
 * the element in once it enters the viewport. Respects prefers-reduced-motion
 * by showing content immediately without animating.
 */
export default function useReveal<
  T extends HTMLElement = HTMLDivElement,
>(): RevealResult<T>
export default function useReveal<T extends HTMLElement = HTMLDivElement>(
  options: RevealOptions & { stagger: true },
): StaggerRevealResult<T>
export default function useReveal<T extends HTMLElement = HTMLDivElement>(
  options?: RevealOptions,
): RevealResult<T> | StaggerRevealResult<T> {
  const stagger = options?.stagger ?? false
  const ref = useRef<T>(null)
  const [visible, setVisible] = useState(false)
  const [reducedMotion, setReducedMotion] = useState(false)

  useEffect(() => {
    const node = ref.current
    if (!node) return

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setReducedMotion(true)
      setVisible(true)
      return
    }

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          setVisible(true)
          observer.disconnect()
        }
      },
      { threshold: 0.1 },
    )
    observer.observe(node)
    return () => observer.disconnect()
  }, [])

  const className = `transition-[opacity,translate] duration-700 ease-out motion-reduce:transition-none ${
    visible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'
  }`

  if (!stagger) return { ref, className }

  const childStyle = (index: number): CSSProperties => ({
    transitionDelay: reducedMotion ? '0ms' : `${Math.min(index, 5) * 80}ms`,
  })

  return { ref, className, childStyle }
}
