import { useRef } from 'react'
import type { ReactNode } from 'react'
import { Link, useParams } from 'react-router-dom'
import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import ModCard from '../components/ModCard'
import ModImage from '../components/ModImage'
import useClipboard from '../hooks/useClipboard'
import usePageMeta from '../hooks/usePageMeta'
import { useI18n } from '../i18n/context'
import { LINKS } from '../data/links'
import { MODS } from '../data/mods'
import type { Mod } from '../data/mods'
import NotFound from './NotFound'

/** Render plain text, turning any http(s) URLs into styled external links. */
function linkify(text: string) {
  return text.split(/(https?:\/\/\S+)/g).map((part, index) =>
    /^https?:\/\//.test(part) ? (
      <a
        key={index}
        href={part}
        target="_blank"
        rel="noreferrer"
        className="text-bap-pink hover:underline"
      >
        {part}
      </a>
    ) : (
      part
    ),
  )
}

function CopyIdRow({ id }: { id: string }) {
  const { t } = useI18n()
  const { copied, copy } = useClipboard()
  const codeRef = useRef<HTMLElement>(null)

  async function handleCopy() {
    if (await copy(id)) return

    // Clipboard API unavailable (permissions / insecure context):
    // select the id text so the user can copy it manually.
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
    <div className="flex flex-wrap items-center gap-3 border border-bap-line bg-bap-plum px-4 py-3">
      <span className="font-teko uppercase text-lg leading-none tracking-wide text-white/40">
        {t.modDetail.modId}
      </span>
      <code ref={codeRef} className="font-mono text-sm text-white/80 break-all">
        {id}
      </code>
      <button
        type="button"
        onClick={handleCopy}
        className="ml-auto font-teko uppercase text-lg leading-none pt-[7px] px-3 pb-1 border border-bap-line text-white/60 hover:text-bap-pink transition cursor-pointer"
      >
        {t.modDetail.copy}
      </button>
      <span aria-live="polite" className="font-teko uppercase text-lg leading-none text-bap-pink">
        {copied ? t.modDetail.copied : ''}
      </span>
    </div>
  )
}

function ModDetail({ mod }: { mod: Mod }) {
  const { t } = useI18n()
  // Mod name/summary are data and stay English in the meta, in both locales.
  usePageMeta(mod.name, `${mod.name} — ${mod.summary}`)

  const related = MODS.filter((other) => other.id !== mod.id)
    .map((other) => ({
      mod: other,
      score:
        ((other.track ?? null) === (mod.track ?? null) ? 2 : 0) +
        (other.type === mod.type ? 1 : 0),
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 3)
    .map((entry) => entry.mod)

  const meta: { term: string; detail: ReactNode }[] = [
    { term: t.modDetail.version, detail: `v${mod.version}` },
    {
      term: t.modDetail.author,
      detail: mod.authorUrl ? (
        <a
          href={mod.authorUrl}
          target="_blank"
          rel="noreferrer"
          className="text-bap-pink hover:underline"
        >
          {mod.author}
        </a>
      ) : (
        mod.author
      ),
    },
    { term: t.modDetail.added, detail: mod.added },
    { term: t.modDetail.updated, detail: mod.updated },
    { term: t.modDetail.requires, detail: mod.requires },
    {
      term: t.modDetail.track,
      detail: mod.track === 'boss-rush' ? 'Boss Rush' : t.modDetail.allTracks,
    },
    { term: t.modDetail.type, detail: mod.type },
  ]

  return (
    <section className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28">
      <Link
        to="/mods"
        className="inline-block font-teko uppercase text-lg leading-none tracking-wide text-white/60 hover:text-bap-pink transition"
      >
        {t.modDetail.allMods}
      </Link>

      <div className="mt-8 grid grid-cols-1 gap-10 lg:grid-cols-2 lg:gap-16">
        <div className="flex flex-col gap-6">
          <div className="relative">
            <ModImage mod={mod} className="aspect-video border border-bap-line" />
            {mod.ribbon === 'host-only' && (
              <Badge tone="amber" className="absolute top-2 left-2">
                HOST-ONLY
              </Badge>
            )}
            {mod.ribbon === 'new' && (
              <Badge tone="pink" className="absolute top-2 left-2">
                NEW
              </Badge>
            )}
          </div>

          <dl className="grid grid-cols-2 gap-x-6 gap-y-4 border border-bap-line bg-bap-plum p-5 sm:grid-cols-3">
            {meta.map((entry) => (
              <div key={entry.term} className="flex flex-col gap-1">
                <dt className="font-teko uppercase text-lg leading-none tracking-wide text-white/40">
                  {entry.term}
                </dt>
                <dd className="text-white text-sm">{entry.detail}</dd>
              </div>
            ))}
          </dl>

          <CopyIdRow id={mod.id} />
        </div>

        <div className="flex flex-col gap-6">
          <h1 className="font-display uppercase text-3xl text-white md:text-4xl">
            {mod.name}
          </h1>
          {/* Mod descriptions are data (English) — DE flags that with a badge. */}
          {t.modDetail.englishNote && (
            <Badge tone="neutral" className="self-start">
              {t.modDetail.englishNote}
            </Badge>
          )}
          <p className="text-white/80">{mod.summary}</p>
          <p className="text-white/60 text-sm">{mod.description}</p>
          {mod.longDescription && (
            <p className="text-white/60 text-sm">{linkify(mod.longDescription)}</p>
          )}

          <div className="flex flex-wrap gap-1.5">
            {mod.tags.map((tag) => (
              <Badge key={tag}>{tag}</Badge>
            ))}
          </div>

          <div className="flex flex-col border border-bap-line bg-bap-black">
            <div className="border-b border-bap-line px-5 py-3">
              <span className="font-teko uppercase text-xl leading-none tracking-widest text-white">
                {t.modDetail.versionHistory}
              </span>
            </div>
            <ul className="flex flex-col divide-y divide-bap-line">
              {mod.versions.map((entry) => (
                <li key={entry.version} className="flex flex-col gap-1 px-5 py-4">
                  <span className="font-teko uppercase text-xl leading-none text-bap-pink">
                    v{entry.version}
                  </span>
                  <p className="text-white/80 text-sm">{entry.changelog}</p>
                </li>
              ))}
            </ul>
          </div>

          <div className="flex flex-wrap items-center gap-4">
            <GradientButton to="/launcher">
              {t.modDetail.installViaLauncher}
            </GradientButton>
            <GradientButton
              variant="outline"
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
            >
              {t.modDetail.getHelpOnDiscord}
            </GradientButton>
          </div>
        </div>
      </div>

      <div className="mt-20 flex flex-col gap-6">
        <h2 className="font-display uppercase text-2xl text-white">
          {t.modDetail.moreMods}
        </h2>
        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {related.map((other) => (
            <ModCard key={other.id} mod={other} />
          ))}
        </div>
      </div>
    </section>
  )
}

export default function ModDetailPage() {
  const { id } = useParams<'id'>()
  const mod = MODS.find((entry) => entry.id === id)

  if (!mod) return <NotFound />

  return <ModDetail key={mod.id} mod={mod} />
}
