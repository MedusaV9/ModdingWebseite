import { MODS } from '../data/mods'

/**
 * Pick a random mod id from the catalog — shared by the command palette's
 * "Surprise me" action, the mods page SURPRISE ME button and the 404 page.
 */
export function randomModId(): string {
  return MODS[Math.floor(Math.random() * MODS.length)].id
}
