/**
 * Keyboard-shortcuts help overlay, opened with "?" (Layout) or the sidebar
 * help button. Built on Modal — portal, focus trap, Escape and the mobile
 * bottom sheet come for free. Lists ONLY shortcuts that really exist in the
 * app; keep it in sync when adding new key handlers.
 */
import { Modal } from './Modal.tsx'
import { KeyboardHint } from './ui.tsx'
import { useT } from '../i18n/index.tsx'

// ⌘ on Apple platforms, Ctrl everywhere else — matches the sidebar's ⌘K hint.
const IS_APPLE = /mac|iphone|ipad|ipod/i.test(navigator.platform)

interface ShortcutRow {
  label: string
  keys: string[]
}

export function ShortcutsHelp({ open, onClose }: { open: boolean; onClose: () => void }) {
  const t = useT()

  const groups: { label: string; rows: ShortcutRow[] }[] = [
    {
      label: t('shortcuts.groupGlobal'),
      rows: [
        { label: t('shortcuts.openPalette'), keys: [IS_APPLE ? '⌘' : 'Ctrl', 'K'] },
        { label: t('shortcuts.openHelp'), keys: ['?'] },
        { label: t('shortcuts.closeOverlay'), keys: ['Esc'] },
      ],
    },
    {
      label: t('shortcuts.groupPalette'),
      rows: [
        { label: t('shortcuts.paletteNavigate'), keys: ['↑', '↓'] },
        { label: t('shortcuts.paletteOpen'), keys: ['↵'] },
      ],
    },
    {
      label: t('shortcuts.groupConsole'),
      rows: [
        { label: t('shortcuts.focusSearch'), keys: ['/'] },
        { label: t('shortcuts.historyNav'), keys: ['↑', '↓'] },
      ],
    },
  ]

  return (
    <Modal open={open} onClose={onClose} title={t('shortcuts.title')}>
      <div className="space-y-4">
        {groups.map((group) => (
          <section key={group.label}>
            <div className="microlabel mb-1.5">{group.label}</div>
            <div className="glass-subtle divide-y divide-line/40 rounded-xl px-3">
              {group.rows.map((row) => (
                <div key={row.label} className="flex min-h-9 items-center justify-between gap-3 py-2">
                  <span className="text-[0.8125rem] text-text/90">{row.label}</span>
                  <span className="flex shrink-0 items-center gap-1">
                    {row.keys.map((k) => (
                      <KeyboardHint key={k}>{k}</KeyboardHint>
                    ))}
                  </span>
                </div>
              ))}
            </div>
          </section>
        ))}
      </div>
    </Modal>
  )
}
