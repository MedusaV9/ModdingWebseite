import { useCallback, useEffect, useRef, useState } from 'react'

/**
 * Copy-to-clipboard with a self-resetting "copied" flag.
 *
 * `copy(text)` resolves to `false` when the Clipboard API is unavailable
 * (permissions / insecure context) so callers can run their own fallback,
 * e.g. selecting the text for manual copying.
 */
export default function useClipboard(resetMs = 2000) {
  const [copied, setCopied] = useState(false)
  const timeoutRef = useRef<number | undefined>(undefined)

  useEffect(() => () => window.clearTimeout(timeoutRef.current), [])

  const copy = useCallback(
    async (text: string): Promise<boolean> => {
      try {
        await navigator.clipboard.writeText(text)
        setCopied(true)
        window.clearTimeout(timeoutRef.current)
        timeoutRef.current = window.setTimeout(() => setCopied(false), resetMs)
        return true
      } catch {
        return false
      }
    },
    [resetMs],
  )

  return { copied, copy }
}
