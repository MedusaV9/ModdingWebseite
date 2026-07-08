import { useNavigate, useSearchParams } from 'react-router-dom'
import Icon from '../components/brand/Icon'
import ModCard from '../components/ModCard'
import SectionHeading from '../components/SectionHeading'
import useClipboard from '../hooks/useClipboard'
import usePageMeta from '../hooks/usePageMeta'
import { useI18n } from '../i18n/context'
import { MODS } from '../data/mods'
import type { Mod } from '../data/mods'
import { AUTHORS } from '../lib/authors'
import { randomModId } from '../lib/randomMod'

type TypeFilter = 'all' | 'mods' | 'tools' | 'boss-rush'
type Sort = 'name' | 'newest' | 'updated'

// Ids double as the URL param VALUES (type=…, sort=…) and never change;
// labels come from the active dict in-component (t.mods.typeTabs/sortOptions).
const typeTabs: { id: TypeFilter; match: (mod: Mod) => boolean }[] = [
  { id: 'all', match: () => true },
  { id: 'mods', match: (mod) => mod.type === 'mod' },
  { id: 'tools', match: (mod) => mod.type === 'tool' },
  {
    id: 'boss-rush',
    match: (mod) => mod.track === 'boss-rush',
  },
]

const sortIds: Sort[] = ['name', 'newest', 'updated']

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
  const { t } = useI18n()
  usePageMeta(t.meta.mods.title, t.meta.mods.description)

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
  const sort: Sort = sortIds.some((id) => id === sortParam)
    ? (sortParam as Sort)
    : 'name'
  // Exact-name match against the derived author list — anything else
  // (typos, hand-edited URLs) is silently ignored.
  const authorParam = searchParams.get('author')
  const author = AUTHORS.some((entry) => entry.name === authorParam)
    ? authorParam
    : null

  function updateParams(
    updates: Partial<Record<'q' | 'type' | 'tags' | 'sort' | 'author', string>>,
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

  const hasFilters = q !== '' || type !== 'all' || tags.length > 0 || author !== null

  function clearFilters() {
    updateParams({ q: '', type: '', tags: '', author: '' })
  }

  const activeTab = typeTabs.find((tab) => tab.id === type) ?? typeTabs[0]
  const query = q.trim().toLowerCase()

  const visible = MODS.filter((mod) => {
    if (!activeTab.match(mod)) return false
    if (author && mod.author !== author) return false
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
        eyebrow={t.mods.eyebrow}
        title={t.mods.title}
        subtitle={t.mods.subtitle}
      />

      <div className="mt-10 flex flex-col gap-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-end">
          <div className="flex flex-1 flex-col gap-1.5">
            <label
              htmlFor="mod-search"
              className="font-teko uppercase text-lg leading-none tracking-wide text-white/60"
            >
              {t.mods.searchLabel}
            </label>
            <input
              id="mod-search"
              type="search"
              value={q}
              onChange={(event) => updateParams({ q: event.target.value }, true)}
              placeholder={t.mods.searchPlaceholder}
              className={`w-full ${inputClasses}`}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label
              htmlFor="mod-sort"
              className="font-teko uppercase text-lg leading-none tracking-wide text-white/60"
            >
              {t.mods.sortLabel}
            </label>
            <select
              id="mod-sort"
              value={sort}
              onChange={(event) => updateParams({ sort: event.target.value })}
              className={`cursor-pointer ${inputClasses}`}
            >
              {sortIds.map((id) => (
                <option key={id} value={id}>
                  {t.mods.sortOptions[id]}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div
          role="group"
          aria-label={t.mods.filterByType}
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
              {t.mods.typeTabs[tab.id]}
            </button>
          ))}
        </div>

        <div
          role="group"
          aria-label={t.mods.filterByCreator}
          className="flex flex-wrap gap-1.5"
        >
          {AUTHORS.map((entry) => {
            const active = author === entry.name
            return (
              <button
                key={entry.name}
                type="button"
                aria-pressed={active}
                onClick={() =>
                  updateParams({ author: active ? '' : entry.name })
                }
                className={`inline-flex items-center border font-teko uppercase tracking-wider text-sm leading-none pt-[5px] px-2 pb-[2px] transition cursor-pointer ${
                  active
                    ? 'text-bap-pink border-bap-pink/50 bg-bap-pink/10'
                    : 'text-white/70 border-bap-line bg-white/5 hover:text-bap-pink'
                }`}
              >
                {entry.name} ({entry.modCount})
              </button>
            )
          })}
        </div>

        <div
          role="group"
          aria-label={t.mods.filterByTag}
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
            {t.mods.showing(visible.length, MODS.length)}
          </p>
          {hasFilters && (
            <button
              type="button"
              onClick={clearFilters}
              className="font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 border border-bap-line text-white/60 hover:text-bap-pink transition cursor-pointer"
            >
              {t.mods.clearFilters}
            </button>
          )}
          <button
            type="button"
            aria-label={t.mods.surpriseMeLabel}
            onClick={() => navigate(`/mods/${randomModId()}`)}
            className="inline-flex items-center gap-2 font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 border border-bap-line text-white/60 hover:text-bap-pink transition cursor-pointer"
          >
            <Icon name="shuffle" className="h-4 w-4 -mt-[3px]" />
            {t.mods.surpriseMe}
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
              {copied ? t.mods.copied : t.mods.copyFilterLink}
            </button>
          )}
          <span aria-live="polite" className="sr-only">
            {copied ? t.mods.copiedAnnouncement : ''}
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
            {t.mods.emptyTitle}
          </p>
          <p className="text-white/60 text-sm">{t.mods.emptyText}</p>
          <button
            type="button"
            onClick={clearFilters}
            className="font-teko uppercase text-lg leading-none pt-[11px] px-4 pb-1.5 text-white bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] transition cursor-pointer hover:brightness-110"
          >
            {t.mods.clearFilters}
          </button>
        </div>
      )}
    </section>
  )
}
