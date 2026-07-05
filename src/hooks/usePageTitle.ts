import { useEffect } from 'react'

/**
 * Sets `document.title` to "<title> — BAPBAP Modding".
 * Pass an empty string for the plain "BAPBAP Modding" title (used on Home).
 */
export default function usePageTitle(title: string) {
  useEffect(() => {
    document.title = title ? `${title} — BAPBAP Modding` : 'BAPBAP Modding'
  }, [title])
}
