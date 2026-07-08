import { MODS } from '../data/mods'

export type Author = { name: string; url?: string; modCount: number }

function deriveAuthors(): Author[] {
  const byName = new Map<string, Author>()
  for (const mod of MODS) {
    const existing = byName.get(mod.author)
    if (existing) {
      existing.modCount += 1
      // url comes from the first mod (in catalog order) that has authorUrl.
      if (!existing.url && mod.authorUrl) existing.url = mod.authorUrl
    } else {
      byName.set(mod.author, {
        name: mod.author,
        url: mod.authorUrl,
        modCount: 1,
      })
    }
  }
  return [...byName.values()].sort(
    (a, b) => b.modCount - a.modCount || a.name.localeCompare(b.name),
  )
}

/** Unique mod authors from the catalog, sorted by modCount desc. */
export const AUTHORS: Author[] = deriveAuthors()
