import { useNavigate, useSearchParams } from 'react-router-dom'
import Icon from '../components/brand/Icon'
import ModCard from '../components/ModCard'
import SectionHeading from '../components/SectionHeading'
import useClipboard from '../hooks/useClipboard'
import usePageMeta from '../hooks/usePageMeta'
import { MODS } from '../data/mods'
import type { Mod } from '../data/mods'
import { randomModId } from '../lib/randomMod'

type TypeFilter = 'all' | 'mods' | 'tools' | 'boss-rush'
type Sort = 'name' | 'newest' | 'updated'

const typeTabs: { id: TypeFilter; label: string; match: (mod: Mod) => boolean }[] = [
  { id: 'all', label: 'ALL', match: () => true },
  { id: 'mods', label: 'MODS', match: (mod) => mod.type === 'mod' },
  { id: 'tools', label: 'TOOLS', match: (mod) => mod.type === 'tool' },
  {
    id: 'boss-rush',
    label: 'BOSS RUSH',
    match: (mod) => mod.track === 'boss-rush',
  },
]

const sortOptions: { id: Sort; label: string }[] = [
  { id: 'name', label: 'NAME A–Z' },
  { id: 'newest', label: 'NEWEST' },
  { id: 'updated', label: 'RECENTLY UPDATED' },
]

const ALL_TAGS = [...new Set(MODS.flatMap((mod) => mod.tags))].sort((a, b) =>
  a.localeCompare(b),
)

const inputClasses =
  'bg-bap-plum border border-bap-line focus:border-bap-pink focus:outline-none px-4 py-2 text-white placeholder-white/40'

const tabClasses = (active: boolean) =>
  `font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 transition cursor-pointer ${
    active
      ? 'text-white bg-[linear-gradient(to_left,#eb204f,#ff2a6d)]'
      : 'border border-bap-line text-white/60 hover:text-bap-pink'
  }`

export default function ModsPage() {
  usePageMeta(
    'Mods',
    'Browse all 12 community mods & tools for BAPBAP — searchable, filterable and one-click installable via the BAPBAP Nexus launcher.',
  )

  const [searchParams, setSearchParams] = useSearchParams()
  const navigate = useNavigate()
  const { copied, copy } = useClipboard()

  const q = searchParams.get('q') ?? ''
  const typeParam = searchParams.get('type')
  const type: TypeFilter = typeTabs.some((tab) => tab.id === typeParam)
    ? (typeParam as TypeFilter)
    : 'all'
  const tags = (searchParams.get('tags') ?? '')
    .split(',')
    .filter((tag) => ALL_TAGS.includes(tag))
  const sortParam = searchParams.get('sort')
  const sort: Sort = sortOptions.some((option) => option.id === sortParam)
    ? (sortParam as Sort)
    : 'name'

  function updateParams(
    updates: Partial<Record<'q' | 'type' | 'tags' | 'sort', string>>,
    replace = false,
  ) {
    const next = new URLSearchParams(searchParams)
    for (const [key, value] of Object.entries(updates)) {
      const isDefault =
        !value || (key === 'type' && value === 'all') || (key === 'sort' && value === 'name')
      if (isDefault) {
        next.delete(key)
      } else {
        next.set(key, value)
      }
    }
    setSearchParams(next, { replace })
  }

  function toggleTag(tag: string) {
    const next = tags.includes(tag)
      ? tags.filter((existing) => existing !== tag)
      : [...tags, tag]
    updateParams({ tags: next.join(',') })
  }

  const hasFilters = q !== '' || type !== 'all' || tags.length > 0

  function clearFilters() {
    updateParams({ q: '', type: '', tags: '' })
  }

  const activeTab = typeTabs.find((tab) => tab.id === type) ?? typeTabs[0]
  const query = q.trim().toLowerCase()

  const visible = MODS.filter((mod) => {
    if (!activeTab.match(mod)) return false
    if (!tags.every((tag) => mod.tags.includes(tag))) return false
    if (query) {
      const haystack = [mod.name, mod.summary, mod.author, mod.id, ...mod.tags]
        .join(' ')
        .toLowerCase()
      if (!haystack.includes(query)) return false
    }
    return true
  }).sort((a, b) => {
    if (sort === 'newest') {
      return b.added.localeCompare(a.added) || a.name.localeCompare(b.name)
    }
    if (sort === 'updated') {
      return b.updated.localeCompare(a.updated) || a.name.localeCompare(b.name)
    }
    return a.name.localeCompare(b.name)
  })

  return (
    <section
      aria-labelledby="mods-heading"
      className="mx-auto max-w-7xl px-4 py-20 md:px-6 md:py-28"
    >
      <SectionHeading
        id="mods-heading"
        eyebrow="BAPHUB CATALOG"
        title="ALL MODS & TOOLS"
        subtitle="The full BAPHub catalog — every mod and tool installs in one click through the BAPBAP Nexus launcher."
      />

      <div className="mt-10 flex flex-col gap-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-end">
          <div className="flex flex-1 flex-col gap-1.5">
            <label
              htmlFor="mod-search"
              className="font-teko uppercase text-lg leading-none tracking-wide text-white/60"
            >
              SEARCH
            </label>
            <input
              id="mod-search"
              type="search"
              value={q}
              onChange={(event) => updateParams({ q: event.target.value }, true)}
              placeholder="Search mods, tags, authors…"
              className={`w-full ${inputClasses}`}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label
              htmlFor="mod-sort"
              className="font-teko uppercase text-lg leading-none tracking-wide text-white/60"
            >
              SORT BY
            </label>
            <select
              id="mod-sort"
              value={sort}
              onChange={(event) => updateParams({ sort: event.target.value })}
              className={`cursor-pointer ${inputClasses}`}
            >
              {sortOptions.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div
          role="group"
          aria-label="Filter by type"
          className="flex flex-wrap gap-3"
        >
          {typeTabs.map((tab) => (
            <button
              key={tab.id}
              type="button"
              aria-pressed={type === tab.id}
              onClick={() => updateParams({ type: tab.id })}
              className={tabClasses(type === tab.id)}
            >
              {tab.label}
            </button>
          ))}
        </div>

        <div
          role="group"
          aria-label="Filter by tag"
          className="flex flex-wrap gap-1.5"
        >
          {ALL_TAGS.map((tag) => {
            const active = tags.includes(tag)
            return (
              <button
                key={tag}
                type="button"
                aria-pressed={active}
                onClick={() => toggleTag(tag)}
                className={`inline-flex items-center border font-teko uppercase tracking-wider text-sm leading-none pt-[5px] px-2 pb-[2px] transition cursor-pointer ${
                  active
                    ? 'text-bap-pink border-bap-pink/50 bg-bap-pink/10'
                    : 'text-white/70 border-bap-line bg-white/5 hover:text-bap-pink'
                }`}
              >
                {tag}
              </button>
            )
          })}
        </div>

        <div className="flex flex-wrap items-center gap-4">
          <p aria-live="polite" className="text-white/60 text-sm">
            Showing {visible.length} of {MODS.length}
          </p>
          {hasFilters && (
            <button
              type="button"
              onClick={clearFilters}
              className="font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 border border-bap-line text-white/60 hover:text-bap-pink transition cursor-pointer"
            >
              CLEAR FILTERS
            </button>
          )}
          <button
            type="button"
            aria-label="Open a random mod"
            onClick={() => navigate(`/mods/${randomModId()}`)}
            className="inline-flex items-center gap-2 font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 border border-bap-line text-white/60 hover:text-bap-pink transition cursor-pointer"
          >
            <Icon name="shuffle" className="h-4 w-4 -mt-[3px]" />
            SURPRISE ME
          </button>
          {hasFilters && (
            <button
              type="button"
              onClick={() => void copy(window.location.href)}
              className="inline-flex items-center gap-2 font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 border border-bap-line text-white/60 hover:text-bap-pink transition cursor-pointer"
            >
              <Icon
                name={copied ? 'check' : 'copy'}
                className="h-4 w-4 -mt-[3px]"
              />
              {copied ? 'COPIED!' : 'COPY FILTER LINK'}
            </button>
          )}
          <span aria-live="polite" className="sr-only">
            {copied ? 'Filter link copied to clipboard' : ''}
          </span>
        </div>
      </div>

      {visible.length > 0 ? (
        <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {visible.map((mod) => (
            <ModCard key={mod.id} mod={mod} />
          ))}
        </div>
      ) : (
        <div className="mt-10 flex flex-col items-center gap-4 border border-bap-line bg-bap-plum px-6 py-16 text-center">
          <p className="font-display uppercase text-2xl text-white md:text-3xl">
            NO MODS MATCH
          </p>
          <p className="text-white/60 text-sm">
            Try different keywords or drop a filter.
          </p>
          <button
            type="button"
            onClick={clearFilters}
            className="font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 text-white bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] transition cursor-pointer hover:brightness-110"
          >
            CLEAR FILTERS
          </button>
        </div>
      )}
    </section>
  )
}
