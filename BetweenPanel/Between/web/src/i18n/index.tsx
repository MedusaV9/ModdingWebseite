import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { en, type I18nKey } from './en.ts'
import { de } from './de.ts'
import { setDateLocale } from '../lib/format.ts'

export type Language = 'en' | 'de'
const DICTS: Record<Language, Record<I18nKey, string>> = { en, de }

interface I18nContextValue {
  lang: Language
  setLang: (lang: Language) => void
  t: (key: I18nKey, params?: Record<string, string | number>) => string
}

const I18nContext = createContext<I18nContextValue>({
  lang: 'en',
  setLang: () => undefined,
  t: (key) => en[key] ?? key,
})

export function I18nProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Language>(() => {
    const saved = localStorage.getItem('between.lang')
    if (saved === 'de' || saved === 'en') return saved
    return navigator.language.toLowerCase().startsWith('de') ? 'de' : 'en'
  })

  const setLang = useCallback((next: Language) => {
    localStorage.setItem('between.lang', next)
    setLangState(next)
  }, [])

  // Synchronously during render (not an effect): the provider renders before
  // its consumers, so formatDateTime calls in the SAME pass already use the
  // new language. Idempotent module-level write — safe under StrictMode.
  setDateLocale(lang)

  const t = useCallback(
    (key: I18nKey, params?: Record<string, string | number>) => {
      let str: string = DICTS[lang][key] ?? en[key] ?? key
      if (params) {
        for (const [name, value] of Object.entries(params)) {
          str = str.replaceAll(`{${name}}`, String(value))
        }
      }
      return str
    },
    [lang],
  )

  const value = useMemo(() => ({ lang, setLang, t }), [lang, setLang, t])
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export function useI18n() {
  return useContext(I18nContext)
}

export function useT() {
  return useContext(I18nContext).t
}
