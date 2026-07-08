import type { ReactNode } from 'react'
import Badge from '../components/Badge'
import Icon from '../components/brand/Icon'
import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { useI18n } from '../i18n/context'
import { LINKS } from '../data/links'

const TEMPLATES_URL =
  'https://github.com/Sonic0810/bapbaplauncher/tree/main/templates'
const AUTHORING_DOC_URL =
  'https://github.com/Sonic0810/bapbaplauncher/blob/main/docs/BAPHub-Content-Authoring-DE.md'

const repoTree = `manifest/
├─ index.json                     ← global config, secretUnlocks[]
├─ game-versions.json             ← tracks & archived builds
├─ assets/
│  └─ packages/                   ← thumbnails, heroes, gallery shots
└─ channels/
   └─ release/
      ├─ packages.json            ← registry of every package
      └─ <package-id>/
         ├─ package.json          ← metadata, visuals, links
         └─ versions/
            └─ <version>/
               ├─ version.json    ← files[] with hashes
               └─ files/          ← your .dll(s)`

const versionJsonExample = `{
  "version": "1.0.0",
  "files": [
    {
      "sourcePath": "files/BAPBAPHpNumbers.dll",
      "targetPath": "Mods/BAPBAPHpNumbers.dll",
      "sha256": "<lowercase hex sha-256 of the file>"
    }
  ]
}`

const powershellHash = `$h = Get-FileHash -Algorithm SHA256 .\\BAPBAPHpNumbers.dll
$h.Hash.ToLower()`

const supportedTracks = ['bapbap', 'latest', 'boss-rush', 'battle-royale']

const visualPresets = [
  'default',
  'featured',
  'shiny',
  'holo',
  'neon',
  'frost',
  'ember',
  'prism',
  'glitch',
  'aurora',
  'frozen',
  'plasma',
  'toxic',
  'cosmic',
  'vapor',
  'storm',
  'inferno',
  'velvet',
  'matrix',
  'ghost',
  'crystal',
  'chrome',
  'noir',
  'sunset',
  'void',
  'candy',
  'dev',
  'event',
]

const ribbonTags = [
  'host-only',
  'secret',
  'featured',
  'recommended',
  'new',
  'experimental',
  'beta',
  'hot',
  'sneakpeek',
]

// Technical identifiers only — descriptions come from t.modders.visuals
// .imageRoles in the same order.
const imageRoleNames = ['thumbnailPath', 'imagePath', 'heroImagePath', 'gallery[]']

function TerminalCard({
  title,
  children,
}: {
  title: string
  children: ReactNode
}) {
  return (
    <div className="flex flex-col border border-bap-line bg-bap-black transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)]">
      <div className="flex items-center justify-between border-b border-bap-line px-5 py-3">
        <span className="font-teko uppercase text-xl leading-none tracking-widest text-white">
          {title}
        </span>
        <span className="flex gap-1.5">
          <span className="h-2.5 w-2.5 rounded-full bg-bap-red" />
          <span className="h-2.5 w-2.5 rounded-full bg-bap-amber" />
          <span className="h-2.5 w-2.5 rounded-full bg-bap-pink" />
        </span>
      </div>
      {children}
    </div>
  )
}

export default function ModdersPage() {
  const { t } = useI18n()
  usePageMeta(t.meta.modders.title, t.meta.modders.description)

  const revealSteps = useReveal()
  const revealFiles = useReveal()
  const revealCards = useReveal()
  const revealCta = useReveal()

  return (
    <>
      {/* Publish flow */}
      <section
        aria-labelledby="modders-heading"
        className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28"
      >
        <div ref={revealSteps.ref} className={revealSteps.className}>
          <SectionHeading
            id="modders-heading"
            eyebrow={t.modders.eyebrow}
            title={t.modders.title}
            subtitle={t.modders.subtitle}
          />

          <ol className="mt-12 grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-4">
            {t.modders.steps.map((step, index) => (
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
                <p className="text-white/60 text-sm">{step.text}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* Repo structure + version.json */}
      <section
        aria-label={t.modders.filesLabel}
        className="border-y border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealFiles.ref}
          className={`mx-auto grid max-w-7xl grid-cols-1 gap-6 px-4 py-16 md:px-6 lg:grid-cols-2 ${revealFiles.className}`}
        >
          <TerminalCard title={t.modders.repoStructure}>
            <pre className="bg-bap-black p-4 text-sm text-white/80 overflow-x-auto">
              {repoTree}
            </pre>
          </TerminalCard>

          <TerminalCard title={t.modders.versionJson}>
            <div className="flex flex-col divide-y divide-bap-line">
              <pre className="bg-bap-black p-4 text-sm text-white/80 overflow-x-auto">
                <code>{versionJsonExample}</code>
              </pre>
              <div className="flex flex-col gap-2 p-4">
                <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                  {t.modders.hashIt}
                </span>
                <pre className="text-sm text-bap-amber overflow-x-auto">
                  <code>{powershellHash}</code>
                </pre>
              </div>
            </div>
          </TerminalCard>
        </div>
      </section>

      {/* Detail cards */}
      <section
        aria-label={t.modders.detailsLabel}
        className="mx-auto max-w-7xl px-4 py-16 md:px-6"
      >
        <div
          ref={revealCards.ref}
          className={`grid grid-cols-1 gap-6 lg:grid-cols-2 ${revealCards.className}`}
        >
          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)] md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              {t.modders.targeting.title}
            </h2>
            <p className="text-white/60 text-sm">
              {t.modders.targeting.p1Before}
              <code className="text-white/80">supportedTracks</code>
              {t.modders.targeting.p1After}
            </p>
            <div className="flex flex-wrap gap-1.5">
              {supportedTracks.map((track) => (
                <Badge key={track} tone="pink">
                  {track}
                </Badge>
              ))}
            </div>
            <p className="text-white/60 text-sm">
              {t.modders.targeting.p2Before}
              <code className="text-white/80">compatibility</code>
              {t.modders.targeting.p2Middle}
              <code className="text-white/80">links[]</code>
              {t.modders.targeting.p2After}
            </p>
          </div>

          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)] md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              {t.modders.secret.title}
            </h2>
            <p className="text-white/60 text-sm">
              {t.modders.secret.p1a}
              <code className="text-white/80">visibility: "secret"</code>
              {t.modders.secret.p1b}
              <code className="text-white/80">secretUnlockId</code>
              {t.modders.secret.p1c}
              <code className="text-white/80">
                manifest/index.json → secretUnlocks[]
              </code>
              {t.modders.secret.p1d}
            </p>
            <p className="text-white/60 text-sm">
              <code className="text-white/80">unlockAtUtc</code>
              {t.modders.secret.p2a}
              <span className="text-bap-amber">2026-04-10T22:50:00Z</span>
              {t.modders.secret.p2b}
            </p>
          </div>

          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)] md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              {t.modders.visuals.title}
            </h2>
            <div className="flex flex-col gap-2">
              <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                {t.modders.visuals.presetsLabel}
              </span>
              <div className="flex flex-wrap gap-1.5">
                {visualPresets.map((preset) => (
                  <Badge key={preset}>{preset}</Badge>
                ))}
              </div>
              <p className="text-white/60 text-sm">
                {t.modders.visuals.presetsText}
              </p>
            </div>
            <div className="flex flex-col gap-2 border-t border-bap-line pt-4">
              <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                {t.modders.visuals.ribbonLabel}
              </span>
              <div className="flex flex-wrap gap-1.5">
                {ribbonTags.map((tag) => (
                  <Badge key={tag} tone="amber">
                    {tag}
                  </Badge>
                ))}
              </div>
              <p className="text-white/60 text-sm">
                {t.modders.visuals.ribbonText}
              </p>
            </div>
            <div className="flex flex-col gap-2 border-t border-bap-line pt-4">
              <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                {t.modders.visuals.imageRolesLabel}
              </span>
              <ul className="flex flex-col gap-1.5">
                {imageRoleNames.map((name, index) => (
                  <li key={name} className="text-sm text-white/60">
                    <code className="text-white/80">{name}</code> —{' '}
                    {t.modders.visuals.imageRoles[index]}
                  </li>
                ))}
              </ul>
            </div>
          </div>

          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink hover:shadow-[6px_6px_0_0_rgba(255,42,109,0.35)] md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              {t.modders.validation.title}
            </h2>
            <ul className="flex flex-col gap-3">
              {t.modders.validation.items.map((item) => (
                <li key={item} className="flex items-start gap-2">
                  <Icon
                    name="shield"
                    className="mt-0.5 h-4 w-4 shrink-0 text-bap-pink"
                  />
                  <span className="text-white/70 text-sm">{item}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </section>

      {/* CTA row */}
      <section
        aria-label={t.modders.resourcesLabel}
        className="mx-auto max-w-7xl px-4 pb-20 md:px-6"
      >
        <div
          ref={revealCta.ref}
          className={`flex flex-col items-center gap-6 border border-bap-line bg-bap-plum px-6 py-12 text-center md:px-12 ${revealCta.className}`}
        >
          <p className="font-display uppercase text-2xl text-white md:text-3xl">
            {t.modders.ctaTitle}
          </p>
          <div className="flex flex-wrap items-center justify-center gap-4">
            <GradientButton
              variant="outline"
              href={TEMPLATES_URL}
              target="_blank"
              rel="noreferrer"
            >
              {t.modders.starterTemplates}
            </GradientButton>
            <GradientButton
              variant="outline"
              href={AUTHORING_DOC_URL}
              target="_blank"
              rel="noreferrer"
            >
              {t.modders.authoringDoc}
            </GradientButton>
            <GradientButton
              variant="outline"
              href={LINKS.github}
              target="_blank"
              rel="noreferrer"
            >
              {t.modders.openManifest}
            </GradientButton>
            <GradientButton
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
            >
              {t.modders.getHelpPublishing}
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
