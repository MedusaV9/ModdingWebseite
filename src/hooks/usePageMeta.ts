import { useEffect } from 'react'

const SITE_TITLE = 'BAPBAP Modding — Community Mods & Launcher for BAPBAP'

function setMeta(selector: string, content: string) {
  document.querySelector(selector)?.setAttribute('content', content)
}

/**
 * Per-route document metadata: sets `document.title` plus the description /
 * Open Graph tags that ship in index.html. Pass an empty title for the full
 * site title (used on Home).
 */
export default function usePageMeta(title: string, description: string) {
  useEffect(() => {
    const fullTitle = title ? `${title} — BAPBAP Modding` : SITE_TITLE
    document.title = fullTitle
    setMeta('meta[name="description"]', description)
    setMeta('meta[property="og:title"]', fullTitle)
    setMeta('meta[property="og:description"]', description)
  }, [title, description])
}
