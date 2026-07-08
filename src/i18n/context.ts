import { createContext, useContext } from 'react'
import { en } from './en'

export type Locale = 'en' | 'de'

/** The dictionary shape — en.ts is the source of truth, de.ts must satisfy it. */
export type Dict = typeof en

export const STORAGE_KEY = 'bapbap-locale'

/**
 * Initial locale: stored preference first, then browser language, else 'en'.
 * localStorage access is wrapped in try/catch (privacy mode can throw) and
 * everything is guarded for SSR safety.
 */
export function detectLocale(): Locale {
  if (typeof window === 'undefined') return 'en'
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY)
    if (stored === 'en' || stored === 'de') return stored
  } catch {
    // Ignore storage errors and fall through to the browser language.
  }
  return navigator.language.toLowerCase().startsWith('de') ? 'de' : 'en'
}

export type I18nValue = {
  locale: Locale
  setLocale: (l: Locale) => void
  t: Dict
}

// Exported so LanguageProvider.tsx can render the provider; consume via useI18n.
export const I18nContext = createContext<I18nValue | null>(null)

export function useI18n(): I18nValue {
  const value = useContext(I18nContext)
  if (!value) {
    throw new Error(
      'useI18n must be used within <LanguageProvider> — wrap the app in src/i18n/LanguageProvider.tsx (see src/App.tsx).',
    )
  }
  return value
}
