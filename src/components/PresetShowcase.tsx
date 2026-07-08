import { useRef, useState } from 'react'
import Badge from './Badge'
import Icon from './brand/Icon'
import SectionHeading from './SectionHeading'
import useClipboard from '../hooks/useClipboard'
import useReveal from '../hooks/useReveal'
import { useI18n } from '../i18n/context'
import { PRESETS } from '../data/presets'
import type { PresetId } from '../data/presets'

/**
 * Live, CSS-only showcase of the launcher's 28 `visual.preset` card tokens.
 * Effect styling lives in src/index.css as `.fx-<id>` classes: the container
 * carries the static layer, the `.fx-layer` child carries the motion layer.
 * Motion runs only on :hover / :focus-visible / .fx-active (the test card),
 * so the 28 swatches never animate concurrently while idle.
 */
export default function PresetShowcase() {
  const { t } = useI18n()
  const [selected, setSelected] = useState<PresetId>('shiny')
  const { copied, copy } = useClipboard()
  const codeRef = useRef<HTMLElement>(null)
  const reveal = useReveal()

  const snippet = `"visual": { "preset": "${selected}" }`

  async function handleCopy() {
    if (await copy(snippet)) return

    // Clipboard API unavailable (permissions / insecure context):
    // select the snippet text so the user can copy it manually.
    const node = codeRef.current
    const selection = window.getSelection()
    if (node && selection) {
      const range = document.createRange()
      range.selectNodeContents(node)
      selection.removeAllRanges()
      selection.addRange(range)
    }
  }

  return (
    <section
      id="preset-gallery"
      tabIndex={-1}
      aria-labelledby="preset-gallery-heading"
      className="mx-auto max-w-7xl px-4 py-16 md:px-6"
    >
      <div ref={reveal.ref} className={reveal.className}>
        <SectionHeading
          id="preset-gallery-heading"
          eyebrow={t.modders.gallery.eyebrow}
          title={t.modders.gallery.title}
          subtitle={t.modders.gallery.subtitle}
        />

        <div className="mt-10 grid grid-cols-1 gap-10 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)] lg:gap-12">
          {/* Effect test card + snippet (sticky while scrolling the grid) */}
          <div className="flex flex-col gap-4 lg:sticky lg:top-24 lg:self-start">
            <div
              className={`fx-active relative overflow-hidden border p-6 fx-${selected}`}
            >
              <div className="flex flex-col gap-3">
                <h3 className="fx-title font-display uppercase text-xl text-white">
                  {t.modders.gallery.testCardTitle}
                </h3>
                <p className="text-white/60 text-sm">
                  {t.modders.gallery.testCardSummary}
                </p>
                <div className="flex flex-wrap gap-1.5">
                  {t.modders.gallery.testCardBadges.map((badge) => (
                    <Badge key={badge}>{badge}</Badge>
                  ))}
                </div>
              </div>
              <span aria-hidden className="fx-layer" />
            </div>

            <p className="text-white/60 text-sm">
              {t.modders.gallery.descriptions[selected]}
            </p>

            <pre className="bg-bap-black border border-bap-line p-4 text-sm text-white/80 overflow-x-auto">
              <code ref={codeRef}>{snippet}</code>
            </pre>

            <div className="flex flex-wrap items-center gap-3">
              <button
                type="button"
                onClick={handleCopy}
                className="inline-flex items-center gap-2 font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 border border-bap-line text-white/60 hover:text-bap-pink transition cursor-pointer"
              >
                <Icon
                  name={copied ? 'check' : 'copy'}
                  className="h-4 w-4 -mt-[3px]"
                />
                {t.modders.gallery.copy}
              </button>
              <span
                aria-live="polite"
                className="font-teko uppercase text-lg leading-none text-bap-pink"
              >
                {copied ? t.modders.gallery.copied : ''}
              </span>
            </div>
          </div>

          {/* Swatch grid — one mini-card button per preset */}
          <div className="flex flex-col gap-4">
            <div
              role="group"
              aria-label={t.modders.gallery.chooseLabel}
              className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-4"
            >
              {PRESETS.map(({ id }) => (
                <button
                  key={id}
                  type="button"
                  aria-pressed={selected === id}
                  onClick={() => setSelected(id)}
                  className={`relative flex aspect-[4/3] items-end overflow-hidden border p-3 text-left transition cursor-pointer fx-${id} ${
                    selected === id ? 'fx-selected' : ''
                  }`}
                >
                  <span className="fx-title font-teko uppercase text-lg leading-none text-white">
                    {id}
                  </span>
                  <span aria-hidden className="fx-layer" />
                </button>
              ))}
            </div>
            <p className="text-white/50 text-sm">
              {t.modders.gallery.hiddenNote}
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}
