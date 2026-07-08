import SectionHeading from '../components/SectionHeading'
import useReveal from '../hooks/useReveal'
import { useI18n } from '../i18n/context'

export default function HowItWorks() {
  const { t } = useI18n()
  const steps = t.howItWorks.steps
  const reveal = useReveal({ stagger: true })

  return (
    <section
      id="how-it-works"
      aria-labelledby="how-it-works-heading"
      className="border-y border-bap-line bg-bap-plum/30"
    >
      <div
        ref={reveal.ref}
        className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28"
      >
        <div className={reveal.className}>
          <SectionHeading
            id="how-it-works-heading"
            eyebrow={t.howItWorks.eyebrow}
            title={t.howItWorks.title}
          />
        </div>

        <ol className="mt-12 grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-4">
          {steps.map((step, index) => (
            <li
              key={step.title}
              className={`group flex flex-col gap-3 ${reveal.className}`}
              style={reveal.childStyle(index)}
            >
              {/* Outlined numeral cross-fades to solid pink on hover */}
              <span
                aria-hidden
                className="relative font-display text-7xl leading-none"
              >
                <span
                  className="text-transparent transition-opacity duration-150 group-hover:opacity-0"
                  style={{ WebkitTextStroke: '2px rgba(255,42,109,0.6)' }}
                >
                  {index + 1}
                </span>
                <span className="absolute inset-0 text-bap-pink opacity-0 transition-opacity duration-150 group-hover:opacity-100">
                  {index + 1}
                </span>
              </span>
              <h3 className="font-teko uppercase text-2xl leading-none text-white">
                {step.title}
              </h3>
              <p className="text-white/60 text-sm">{step.text}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  )
}
