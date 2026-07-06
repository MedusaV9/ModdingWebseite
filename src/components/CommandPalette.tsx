import { useEffect, useMemo, useRef, useState } from 'react'
import type { KeyboardEvent as ReactKeyboardEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import useClipboard from '../hooks/useClipboard'
import { LINKS } from '../data/links'
import { MODS } from '../data/mods'
import { randomModId } from '../lib/randomMod'
import Icon from './brand/Icon'

type PaletteAction =
  | { kind: 'navigate'; to: string }
  | { kind: 'surprise' }
  | { kind: 'copy-discord' }
  | { kind: 'download' }

type PaletteItem = {
  id: string
  label: string
  sub?: string
  tags?: string[]
  action: PaletteAction
}

type PaletteGroup = { heading: string; items: PaletteItem[] }

const MOD_ITEMS: PaletteItem[] = MODS.map((mod) => ({
  id: `mod-${mod.id}`,
  label: mod.name,
  sub: mod.summary,
  tags: mod.tags,
  action: { kind: 'navigate', to: `/mods/${mod.id}` },
}))

const PAGE_ITEMS: PaletteItem[] = [
  { label: 'Home', to: '/' },
  { label: 'Mods', to: '/mods' },
  { label: 'Game Modes', to: '/modes' },
  { label: 'Launcher', to: '/launcher' },
  { label: 'Radio', to: '/radio' },
  { label: 'Guide', to: '/guide' },
  { label: 'For Modders', to: '/modders' },
  { label: 'Community', to: '/community' },
].map(({ label, to }) => ({
  id: `page-${to}`,
  label,
  sub: to,
  action: { kind: 'navigate', to },
}))

const ACTION_ITEMS: PaletteItem[] = [
  {
    id: 'action-surprise',
    label: 'Surprise me — random mod',
    sub: 'Open a random mod from the catalog',
    action: { kind: 'surprise' },
  },
  {
    id: 'action-copy-discord',
    label: 'Copy Discord invite',
    sub: LINKS.discord,
    action: { kind: 'copy-discord' },
  },
  {
    id: 'action-download',
    label: 'Download launcher',
    sub: 'BAPBAP Nexus for Windows',
    action: { kind: 'download' },
  },
]

/* Empty query shows PAGES + ACTIONS (11 items) — "~10" cap set to fit them. */
const MAX_RESULTS = 11

function matches(item: PaletteItem, query: string) {
  return [item.label, item.sub ?? '', ...(item.tags ?? [])]
    .join(' ')
    .toLowerCase()
    .includes(query)
}

const FOCUSABLE_SELECTOR =
  'a[href], button:not([disabled]), input, select, textarea, [tabindex]:not([tabindex="-1"])'

type CommandPaletteProps = {
  open: boolean
  onOpen: () => void
  onClose: () => void
}

export default function CommandPalette({
  open,
  onOpen,
  onClose,
}: CommandPaletteProps) {
  const navigate = useNavigate()
  const { copied, copy } = useClipboard()

  const [query, setQuery] = useState('')
  const [activeIndex, setActiveIndex] = useState(0)
  const [entered, setEntered] = useState(false)

  const inputRef = useRef<HTMLInputElement>(null)
  const panelRef = useRef<HTMLDivElement>(null)
  const previousFocusRef = useRef<HTMLElement | null>(null)
  const closeTimerRef = useRef<number | undefined>(undefined)

  // Global hotkeys: "/" or Ctrl/Cmd+K open — unless focus is in a form field.
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const target = event.target
      const inField =
        target instanceof HTMLElement &&
        target.closest('input, textarea, select, [contenteditable]') !== null
      const isSlash =
        event.key === '/' && !event.ctrlKey && !event.metaKey && !event.altKey
      const isCtrlK =
        (event.key === 'k' || event.key === 'K') &&
        (event.ctrlKey || event.metaKey)
      if ((isSlash || isCtrlK) && !inField) {
        event.preventDefault()
        onOpen()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [onOpen])

  // Open: remember trigger, lock body scroll, focus input; undo all on close.
  useEffect(() => {
    if (!open) return
    previousFocusRef.current =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null
    document.body.style.overflow = 'hidden'
    setQuery('')
    inputRef.current?.focus()
    const raf = requestAnimationFrame(() => setEntered(true))
    return () => {
      cancelAnimationFrame(raf)
      setEntered(false)
      document.body.style.overflow = ''
      window.clearTimeout(closeTimerRef.current)
      previousFocusRef.current?.focus()
    }
  }, [open])

  useEffect(() => () => window.clearTimeout(closeTimerRef.current), [])

  const trimmed = query.trim().toLowerCase()

  const groups = useMemo<PaletteGroup[]>(() => {
    const source: PaletteGroup[] = trimmed
      ? [
          { heading: 'MODS', items: MOD_ITEMS.filter((i) => matches(i, trimmed)) },
          { heading: 'PAGES', items: PAGE_ITEMS.filter((i) => matches(i, trimmed)) },
          { heading: 'ACTIONS', items: ACTION_ITEMS.filter((i) => matches(i, trimmed)) },
        ]
      : [
          { heading: 'PAGES', items: PAGE_ITEMS },
          { heading: 'ACTIONS', items: ACTION_ITEMS },
        ]
    const capped: PaletteGroup[] = []
    let count = 0
    for (const group of source) {
      if (count >= MAX_RESULTS) break
      const items = group.items.slice(0, MAX_RESULTS - count)
      if (items.length > 0) {
        capped.push({ heading: group.heading, items })
        count += items.length
      }
    }
    return capped
  }, [trimmed])

  const flat = useMemo(() => groups.flatMap((group) => group.items), [groups])

  useEffect(() => {
    setActiveIndex(0)
  }, [trimmed, open])

  const activeItem: PaletteItem | undefined = flat[activeIndex]
  const activeId = activeItem ? `palette-option-${activeItem.id}` : undefined

  useEffect(() => {
    if (!open || !activeId) return
    document.getElementById(activeId)?.scrollIntoView({ block: 'nearest' })
  }, [open, activeId])

  function activate(item: PaletteItem) {
    switch (item.action.kind) {
      case 'navigate':
        navigate(item.action.to)
        onClose()
        break
      case 'surprise':
        navigate(`/mods/${randomModId()}`)
        onClose()
        break
      case 'copy-discord':
        void copy(LINKS.discord).then((ok) => {
          if (!ok) {
            onClose()
            return
          }
          window.clearTimeout(closeTimerRef.current)
          closeTimerRef.current = window.setTimeout(onClose, 800)
        })
        break
      case 'download':
        window.open(LINKS.launcherDownload, '_blank', 'noopener')
        onClose()
        break
    }
  }

  function onPanelKeyDown(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (event.key === 'ArrowDown') {
      event.preventDefault()
      if (flat.length > 0) setActiveIndex((i) => (i + 1) % flat.length)
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      if (flat.length > 0) setActiveIndex((i) => (i - 1 + flat.length) % flat.length)
    } else if (event.key === 'Enter') {
      event.preventDefault()
      if (activeItem) activate(activeItem)
    } else if (event.key === 'Escape') {
      event.preventDefault()
      onClose()
    } else if (event.key === 'Tab') {
      // Trap focus inside the dialog.
      const focusables = panelRef.current?.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)
      if (!focusables || focusables.length === 0) {
        event.preventDefault()
        return
      }
      const first = focusables[0]
      const last = focusables[focusables.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
  }

  if (!open) return null

  return (
    <div
      className={`fixed inset-0 z-[60] flex items-start justify-center bg-bap-black/80 px-4 transition-opacity duration-150 ${
        entered ? 'opacity-100' : 'opacity-0'
      }`}
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label="Site search"
        onKeyDown={onPanelKeyDown}
        className="shadow-hard mt-[15vh] w-full max-w-xl border-2 border-bap-pink bg-bap-night"
      >
        <div className="flex items-center gap-3 border-b border-bap-line px-4">
          <Icon name="search" className="h-5 w-5 shrink-0 text-bap-pink" />
          <input
            ref={inputRef}
            role="combobox"
            aria-expanded={flat.length > 0}
            aria-controls="palette-list"
            aria-activedescendant={activeId}
            aria-autocomplete="list"
            autoComplete="off"
            spellCheck={false}
            type="text"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search mods, pages, actions…"
            className="w-full bg-transparent py-3.5 text-white placeholder-white/40 focus:outline-none"
          />
        </div>

        <div
          role="listbox"
          id="palette-list"
          aria-label="Search results"
          className="max-h-[min(50vh,26rem)] overflow-y-auto py-1"
        >
          {flat.length === 0 && (
            <p className="px-4 py-6 text-sm text-white/50">
              NO RESULTS — try different keywords.
            </p>
          )}
          {groups.map((group) => (
            <div
              key={group.heading}
              role="group"
              aria-labelledby={`palette-group-${group.heading}`}
            >
              <div
                id={`palette-group-${group.heading}`}
                role="presentation"
                className="px-4 pt-3 pb-1 font-teko uppercase text-bap-pink tracking-widest text-sm"
              >
                {group.heading}
              </div>
              {group.items.map((item) => {
                const flatIndex = flat.indexOf(item)
                const isActive = flatIndex === activeIndex
                const showCopied = item.action.kind === 'copy-discord' && copied
                return (
                  <div
                    key={item.id}
                    id={`palette-option-${item.id}`}
                    role="option"
                    aria-selected={isActive}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => activate(item)}
                    onMouseMove={() => setActiveIndex(flatIndex)}
                    className={`flex cursor-pointer flex-col gap-1 border-l-2 px-4 py-2.5 ${
                      isActive
                        ? 'border-bap-pink bg-bap-pink/15'
                        : 'border-transparent'
                    }`}
                  >
                    <span
                      className={`font-teko uppercase text-xl leading-none ${
                        showCopied ? 'text-bap-pink' : 'text-white'
                      }`}
                    >
                      {showCopied ? 'COPIED!' : item.label}
                    </span>
                    {item.sub && (
                      <span className="truncate text-xs text-white/50">
                        {item.sub}
                      </span>
                    )}
                  </div>
                )
              })}
            </div>
          ))}
        </div>

        <div className="border-t border-bap-line px-4 py-2.5 font-teko text-white/40 uppercase text-sm tracking-wide">
          ↑↓ NAVIGATE · ↵ OPEN · ESC CLOSE
        </div>
      </div>
    </div>
  )
}
