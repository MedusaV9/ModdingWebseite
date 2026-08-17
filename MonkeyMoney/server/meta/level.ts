// Level-Glue (§7.5 / Ideen-S-12): Kauf-Gates + Level-Up-Erkennung.
// Das Level selbst ist PURE Ableitung der Lifetime-AT (shared/meta.ts,
// levelFuerAt) — hier lebt nur die Server-Seite: welche Käufe ein Level
// verlangen und wann eine Buchung ein Level-Up ausgelöst hat.
import { levelFuerAt, type ShopItem } from "../../shared/meta";

/**
 * Kauf-Sperre für ein Item: Pass-Exklusive sind NIE kaufbar, level-gated
 * Items erst ab minLevel (Basis: Lifetime-AT — Ausgeben senkt nie das Level).
 * null = kaufbar.
 */
export function kaufSperre(item: ShopItem, atGesamt: number): string | null {
  if (item.passExklusiv !== undefined) return "nur-im-pass";
  if (item.minLevel !== undefined && levelFuerAt(atGesamt) < item.minLevel) {
    return "level-zu-niedrig";
  }
  return null;
}

export interface LevelUp {
  von: number;
  zu: number;
}

/** Level-Up zwischen zwei Lifetime-AT-Ständen — null wenn keins. */
export function levelUpZwischen(atVorher: number, atNachher: number): LevelUp | null {
  const von = levelFuerAt(atVorher);
  const zu = levelFuerAt(atNachher);
  return zu > von ? { von, zu } : null;
}
