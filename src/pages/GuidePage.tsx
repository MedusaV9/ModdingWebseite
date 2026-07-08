import { Link } from 'react-router-dom'
import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { useI18n } from '../i18n/context'
import { LINKS } from '../data/links'

const linkClasses = 'text-bap-pink hover:underline'

// Step copy lives in the dict as plain {before, linkLabel, after} strings;
// only the link targets stay here (same order as t.guide.steps). 'version'
// renders the highlighted MelonLoader version span, null = no inline link.
const stepLinks: (
  | { kind: 'external'; href: string }
  | { kind: 'internal'; to: string }
  | { kind: 'version' }
  | null
)[] = [
  { kind: 'external', href: LINKS.steam },
  { kind: 'external', href: LINKS.launcherDownload },
  { kind: 'version' },
  { kind: 'internal', to: '/modes' },
  { kind: 'internal', to: '/mods' },
  null,
]

function StepLink({ index, label }: { index: number; label: string }) {
  const link = stepLinks[index]
  if (!link || !label) return null
  if (link.kind === 'external') {
    return (
      <a href={link.href} target="_blank" rel="noreferrer" className={linkClasses}>
        {label}
      </a>
    )
  }
  if (link.kind === 'internal') {
    return (
      <Link to={link.to} className={linkClasses}>
        {label}
      </Link>
    )
  }
  return <span className="text-white/80">{label}</span>
}

export default function GuidePage() {
  const { t } = useI18n()
  usePageMeta(t.meta.guide.title, t.meta.guide.description)

  const revealSteps = useReveal()
  const revealFaq = useReveal()
  const revealCta = useReveal()

  return (
    <>
      {/* Numbered steps */}
      <section
        aria-labelledby="guide-heading"
        className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28"
      >
        <div ref={revealSteps.ref} className={revealSteps.className}>
          <SectionHeading
            id="guide-heading"
            eyebrow={t.guide.eyebrow}
            title={t.guide.title}
            subtitle={t.guide.subtitle}
          />

          <ol className="mt-12 grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-3">
            {t.guide.steps.map((step, index) => (
              <li key={step.title} className="flex flex-col gap-3">
                <span
                  aria-hidden
                  className="font-display text-7xl leading-none text-transparent"
                  style={{ WebkitTextStroke: '2px rgba(255,42,109,0.6)' }}
                >
                  {index + 1}
                </span>
                <h2 className="font-teko uppercase text-2xl leading-none text-white">
                  {step.title}
                </h2>
                <p className="text-white/60 text-sm">
                  {step.before}
                  <StepLink index={index} label={step.linkLabel} />
                  {step.after}
                </p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* FAQ */}
      <section
        aria-labelledby="faq-heading"
        className="border-y border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealFaq.ref}
          className={`mx-auto max-w-7xl px-4 py-16 md:px-6 ${revealFaq.className}`}
        >
          <SectionHeading
            id="faq-heading"
            eyebrow={t.guide.faqEyebrow}
            title={t.guide.faqTitle}
          />

          <div className="mt-10 flex flex-col divide-y divide-bap-line border border-bap-line bg-bap-night transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)]">
            {t.guide.faqs.map((faq) => (
              <details key={faq.question} className="group">
                <summary className="flex cursor-pointer items-center justify-between gap-4 px-5 py-4 font-teko uppercase text-xl leading-none text-white transition-colors hover:text-bap-pink">
                  {faq.question}
                  <span
                    aria-hidden
                    className="shrink-0 text-bap-pink transition-transform duration-200 group-open:rotate-45"
                  >
                    +
                  </span>
                </summary>
                <p className="px-5 pb-5 text-white/60 text-sm leading-relaxed">
                  {faq.answer}
                </p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* CTA band */}
      <section
        aria-label={t.guide.nextStepsLabel}
        className="mx-auto max-w-7xl px-4 py-16 pb-20 md:px-6"
      >
        <div
          ref={revealCta.ref}
          className={`flex flex-col items-center gap-6 border border-bap-line bg-bap-plum px-6 py-12 text-center md:px-12 ${revealCta.className}`}
        >
          <p className="font-display uppercase text-2xl text-white md:text-3xl">
            {t.guide.ctaTitle}
          </p>
          <div className="flex flex-wrap items-center justify-center gap-4">
            <GradientButton to="/mods">{t.guide.browseMods}</GradientButton>
            <GradientButton
              variant="outline"
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
            >
              {t.guide.askOnDiscord}
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
