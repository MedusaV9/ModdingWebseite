import SectionHeading from '../components/SectionHeading'

const steps = [
  {
    title: 'Install BAPBAP Nexus',
    text: 'Grab the launcher. It handles MelonLoader and updates for you.',
  },
  {
    title: 'Pick your track',
    text: 'Latest build, Boss Rush, Battle Royale — or any archived version.',
  },
  {
    title: 'One-click install mods',
    text: 'Browse BAPHub and install verified mods instantly.',
  },
  {
    title: 'BAP away',
    text: 'Jump into the party. Your setup stays clean and switchable.',
  },
]

export default function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="border-y border-bap-line bg-bap-plum/30"
    >
      <div className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28">
        <SectionHeading eyebrow="ZERO FRICTION" title="HOW MODDING WORKS" />

        <ol className="mt-12 grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-4">
          {steps.map((step, index) => (
            <li key={step.title} className="flex flex-col gap-3">
              <span
                aria-hidden
                className="font-display text-7xl leading-none text-transparent"
                style={{ WebkitTextStroke: '2px rgba(255,42,109,0.6)' }}
              >
                {index + 1}
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
