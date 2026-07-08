import { useI18n } from '../i18n/context'
import type { Locale } from '../i18n/context'

const LOCALES: { code: Locale; label: string }[] = [
  { code: 'en', label: 'EN' },
  { code: 'de', label: 'DE' },
]

/** Segmented [EN][DE] control, styled to match the navbar search button. */
export default function LanguageSwitcher({
  className = '',
}: {
  className?: string
}) {
  const { locale, setLocale, t } = useI18n()

  return (
    <div
      role="group"
      aria-label={t.nav.languageLabel}
      className={`flex h-10 border border-bap-line ${className}`}
    >
      {LOCALES.map(({ code, label }) => (
        <button
          key={code}
          type="button"
          aria-pressed={locale === code}
          onClick={() => setLocale(code)}
          className={`flex h-full items-center px-2.5 pt-[3px] font-teko uppercase text-lg leading-none transition-colors cursor-pointer ${
            locale === code
              ? 'bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] text-white'
              : 'text-white/60 hover:text-bap-pink'
          }`}
        >
          {label}
        </button>
      ))}
    </div>
  )
}
