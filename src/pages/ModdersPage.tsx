import type { ReactNode } from 'react'
import Badge from '../components/Badge'
import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageMeta from '../hooks/usePageMeta'
import useReveal from '../hooks/useReveal'
import { LINKS } from '../data/links'

const TEMPLATES_URL =
  'https://github.com/Sonic0810/bapbaplauncher/tree/main/templates'
const AUTHORING_DOC_URL =
  'https://github.com/Sonic0810/bapbaplauncher/blob/main/docs/BAPHub-Content-Authoring-DE.md'

const publishSteps = [
  {
    title: 'Add your files',
    text: 'Put your mod files under manifest/channels/release/<package-id>/versions/<version>/files/.',
  },
  {
    title: 'Hash every file',
    text: 'Compute a SHA-256 hash per file (lowercase hex) — the launcher refuses anything unverified.',
  },
  {
    title: 'Create version.json',
    text: 'Describe the release: every file gets sourcePath, targetPath and its sha256.',
  },
  {
    title: 'Update package.json',
    text: 'Update <package-id>/package.json with the new version, metadata, links and visuals.',
  },
  {
    title: 'Register in packages.json',
    text: 'Add or update your package entry in the channel-wide packages.json registry.',
  },
  {
    title: 'Add your images',
    text: 'Drop thumbnails, hero shots and gallery images under manifest/assets/packages/.',
  },
  {
    title: 'Push to main',
    text: 'Push (or open a PR) to main and reload the launcher — your mod is live on BAPHub.',
  },
]

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

const imageRoles = [
  {
    name: 'thumbnailPath',
    text: 'Grid tile — square, ~512×512 recommended.',
  },
  { name: 'imagePath', text: 'Card image and general fallback.' },
  { name: 'heroImagePath', text: 'Wide hero on the detail page.' },
  { name: 'gallery[]', text: 'Extra shots only — not used as the card image.' },
]

const validationChecklist = [
  'HTTPS-only download URLs — plain http is rejected.',
  'Every file entry needs a sha256 (lowercase hex).',
  'No unsafe target paths: no ".." and no absolute paths.',
  'Use "Test Connection" (and the effect test card) in the launcher Settings to verify.',
]

function TerminalCard({
  title,
  children,
}: {
  title: string
  children: ReactNode
}) {
  return (
    <div className="flex flex-col border border-bap-line bg-bap-black">
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
  usePageMeta(
    'For Modders',
    'Publish your own BAPBAP mod on BAPHub — manifest format, SHA-256 hashing, card visuals and secret drops explained.',
  )

  const revealSteps = useReveal()
  const revealFiles = useReveal()
  const revealCards = useReveal()
  const revealCta = useReveal()

  return (
    <>
      {/* Publish flow */}
      <section
        aria-labelledby="modders-heading"
        className="mx-auto max-w-7xl px-4 py-20 md:px-6"
      >
        <div ref={revealSteps.ref} className={revealSteps.className}>
          <SectionHeading
            id="modders-heading"
            eyebrow="BAPHUB"
            title="PUBLISH YOUR MOD"
            subtitle="BAPHub is a git-backed mod registry — publishing is a pull request."
          />

          <ol className="mt-12 grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-4">
            {publishSteps.map((step, index) => (
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
        aria-label="Repository structure and version.json example"
        className="border-y border-bap-line bg-bap-plum/30"
      >
        <div
          ref={revealFiles.ref}
          className={`mx-auto grid max-w-7xl grid-cols-1 gap-6 px-4 py-16 md:px-6 lg:grid-cols-2 ${revealFiles.className}`}
        >
          <TerminalCard title="REPO STRUCTURE">
            <pre className="bg-bap-black p-4 text-sm text-white/80 overflow-x-auto">
              {repoTree}
            </pre>
          </TerminalCard>

          <TerminalCard title="VERSION.JSON">
            <div className="flex flex-col divide-y divide-bap-line">
              <pre className="bg-bap-black p-4 text-sm text-white/80 overflow-x-auto">
                <code>{versionJsonExample}</code>
              </pre>
              <div className="flex flex-col gap-2 p-4">
                <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                  HASH IT (POWERSHELL)
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
        aria-label="Publishing details"
        className="mx-auto max-w-7xl px-4 py-16 md:px-6"
      >
        <div
          ref={revealCards.ref}
          className={`grid grid-cols-1 gap-6 lg:grid-cols-2 ${revealCards.className}`}
        >
          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              TARGETING TRACKS
            </h2>
            <p className="text-white/60 text-sm">
              Set <code className="text-white/80">supportedTracks</code> to
              control where your mod shows up. Omit it and the mod is visible
              for all tracks.
            </p>
            <div className="flex flex-wrap gap-1.5">
              {supportedTracks.map((track) => (
                <Badge key={track} tone="pink">
                  {track}
                </Badge>
              ))}
            </div>
            <p className="text-white/60 text-sm">
              Optional <code className="text-white/80">compatibility</code>{' '}
              narrows things further: tracks[], environments[] and platforms[]
              (e.g. windows-x64). Add <code className="text-white/80">links[]</code>{' '}
              entries ({'{'}label, url, kind{'}'}) for source, docs or donations.
            </p>
          </div>

          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              SECRET &amp; TIMED DROPS
            </h2>
            <p className="text-white/60 text-sm">
              Set <code className="text-white/80">visibility: "secret"</code>{' '}
              (plus an optional{' '}
              <code className="text-white/80">secretUnlockId</code>) to
              password-gate a mod. Passwords are stored as SHA-256 hashes in{' '}
              <code className="text-white/80">
                manifest/index.json → secretUnlocks[]
              </code>{' '}
              — the launcher never sees plaintext.
            </p>
            <p className="text-white/60 text-sm">
              <code className="text-white/80">unlockAtUtc</code> seals a package
              until trusted network time: the launcher reads the HTTP Date
              header from timeSourceUrl, not the local clock. Real example: the
              three April boss-rush mods unlocked at{' '}
              <span className="text-bap-amber">2026-04-10T22:50:00Z</span>.
            </p>
          </div>

          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              CARD VISUALS
            </h2>
            <div className="flex flex-col gap-2">
              <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                VISUAL.PRESET — 28 PRESETS
              </span>
              <div className="flex flex-wrap gap-1.5">
                {visualPresets.map((preset) => (
                  <Badge key={preset}>{preset}</Badge>
                ))}
              </div>
              <p className="text-white/60 text-sm">
                Plus badges[], ribbon, frame (border/glow/pulse) and overlay.
                hidden_&lt;token&gt; variants apply the effect without showing
                the tag chip.
              </p>
            </div>
            <div className="flex flex-col gap-2 border-t border-bap-line pt-4">
              <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                RIBBON TAGS
              </span>
              <div className="flex flex-wrap gap-1.5">
                {ribbonTags.map((tag) => (
                  <Badge key={tag} tone="amber">
                    {tag}
                  </Badge>
                ))}
              </div>
              <p className="text-white/60 text-sm">
                Only one primary ribbon shows, and UPDATE outranks HOST ONLY.
                &quot;update-available&quot; is dynamic — never set it manually.
              </p>
            </div>
            <div className="flex flex-col gap-2 border-t border-bap-line pt-4">
              <span className="font-teko uppercase text-lg leading-none tracking-widest text-white/60">
                IMAGE ROLES
              </span>
              <ul className="flex flex-col gap-1.5">
                {imageRoles.map((role) => (
                  <li key={role.name} className="text-sm text-white/60">
                    <code className="text-white/80">{role.name}</code> —{' '}
                    {role.text}
                  </li>
                ))}
              </ul>
            </div>
          </div>

          <div className="flex flex-col gap-4 border border-bap-line bg-bap-night p-6 transition duration-150 hover:border-bap-pink md:p-8">
            <h2 className="font-display uppercase text-2xl text-white">
              VALIDATION CHECKLIST
            </h2>
            <ul className="flex flex-col gap-3">
              {validationChecklist.map((item) => (
                <li key={item} className="flex items-start gap-2">
                  <span className="mt-1 h-2.5 w-2.5 shrink-0 bg-bap-pink" />
                  <span className="text-white/70 text-sm">{item}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </section>

      {/* CTA row */}
      <section
        aria-label="Modder resources"
        className="mx-auto max-w-7xl px-4 pb-20 md:px-6"
      >
        <div
          ref={revealCta.ref}
          className={`flex flex-col items-center gap-6 border border-bap-line bg-bap-plum px-6 py-12 text-center md:px-12 ${revealCta.className}`}
        >
          <p className="font-display uppercase text-2xl text-white md:text-3xl">
            EVERYTHING YOU NEED TO SHIP
          </p>
          <div className="flex flex-wrap items-center justify-center gap-4">
            <GradientButton
              variant="outline"
              href={TEMPLATES_URL}
              target="_blank"
              rel="noreferrer"
            >
              STARTER TEMPLATES
            </GradientButton>
            <GradientButton
              variant="outline"
              href={AUTHORING_DOC_URL}
              target="_blank"
              rel="noreferrer"
            >
              FULL AUTHORING DOC (DE)
            </GradientButton>
            <GradientButton
              variant="outline"
              href={LINKS.github}
              target="_blank"
              rel="noreferrer"
            >
              OPEN THE MANIFEST
            </GradientButton>
            <GradientButton
              href={LINKS.discord}
              target="_blank"
              rel="noreferrer"
            >
              GET HELP PUBLISHING
            </GradientButton>
          </div>
        </div>
      </section>
    </>
  )
}
