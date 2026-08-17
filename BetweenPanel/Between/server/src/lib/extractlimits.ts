/**
 * Shared safety limits for archive extraction (zip + tar).
 *
 * Uploads are capped at 4 GiB, but a small archive can decompress to
 * petabytes (classic zip bomb) or contain millions of entries. Every
 * extraction path (file manager, installer downloads, SteamCMD bootstrap,
 * backup restore) enforces a cumulative uncompressed-byte budget and an
 * entry-count budget. Both are configurable for hosts with unusually large
 * legitimate archives.
 */

function positiveIntEnv(name: string, fallback: number): number {
  const raw = process.env[name]
  if (raw === undefined || raw.trim() === '') return fallback
  const n = Number.parseInt(raw, 10)
  return Number.isFinite(n) && n > 0 ? n : fallback
}

export const EXTRACT_LIMITS = {
  /**
   * Max cumulative uncompressed bytes one extraction may produce. The GiB
   * value is clamped to 1 PiB so `maxBytes` stays well under
   * Number.MAX_SAFE_INTEGER even with an absurd env override (otherwise the
   * `used > maxBytes` comparisons would lose integer precision).
   */
  maxBytes: Math.min(positiveIntEnv('BETWEEN_MAX_EXTRACT_GIB', 64), 1024 * 1024) * 1024 * 1024 * 1024,
  /** Max number of archive entries (headers) one extraction may process. */
  maxEntries: positiveIntEnv('BETWEEN_MAX_EXTRACT_ENTRIES', 200_000),
  /** Max size of a single tar metadata record (GNU long name / pax). */
  maxMetaBytes: 1024 * 1024,
}

export function fmtBytes(n: number): string {
  if (n >= 1024 ** 3) return `${(n / 1024 ** 3).toFixed(1)} GiB`
  if (n >= 1024 ** 2) return `${(n / 1024 ** 2).toFixed(1)} MiB`
  if (n >= 1024) return `${(n / 1024).toFixed(1)} KiB`
  return `${n} B`
}
