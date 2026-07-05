import { useEffect, useRef, useState } from 'react'

/**
 * Scroll-reveal hook: returns a ref plus transition classes that fade/slide
 * the element in once it enters the viewport. Respects prefers-reduced-motion
 * by showing content immediately without animating.
 */
export default function useReveal<T extends HTMLElement = HTMLDivElement>() {
  const ref = useRef<T>(null)
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    const node = ref.current
    if (!node) return

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
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

  return { ref, className }
}
