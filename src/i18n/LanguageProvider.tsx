import { useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { I18nContext, STORAGE_KEY, detectLocale } from './context'
import type { I18nValue, Locale } from './context'
import { de } from './de'
import { en } from './en'

export default function LanguageProvider({
  children,
}: {
  children: ReactNode
}) {
  const [locale, setLocale] = useState<Locale>(detectLocale)

  useEffect(() => {
    document.documentElement.lang = locale
    try {
      localStorage.setItem(STORAGE_KEY, locale)
    } catch {
      // Persisting the choice is best-effort (private mode etc.).
    }
  }, [locale])

  const value = useMemo<I18nValue>(
    () => ({ locale, setLocale, t: locale === 'de' ? de : en }),
    [locale],
  )

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}
