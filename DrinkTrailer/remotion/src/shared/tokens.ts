/** EARLY brand design tokens. Single source of truth for colors & gradients. */

export const colors = {
  /** Rosa — peach flavor accent. */
  rose: '#E7B7B7',
  /** Koralle — grapefruit flavor accent. */
  coral: '#F2AC8F',
  /** Limette — lemon-mint flavor accent. */
  lime: '#CBD97A',
  /** Creme — light background. */
  cream: '#FAF3EC',
  /** Ink — dark background / text. */
  ink: '#2A2A2A',
} as const;

export type BrandColor = keyof typeof colors;

/** Flavor accent order used across lineup shots: peach, grapefruit, lemon-mint. */
export const flavorAccents = [colors.rose, colors.coral, colors.lime] as const;

export const gradients = {
  sunrise: `linear-gradient(160deg, ${colors.rose} 0%, ${colors.coral} 55%, ${colors.lime} 120%)`,
  creamFade: `linear-gradient(180deg, ${colors.cream} 0%, ${colors.rose}66 100%)`,
  inkVignette: `radial-gradient(120% 90% at 50% 40%, transparent 40%, ${colors.ink}E6 100%)`,
  bottomScrim: `linear-gradient(180deg, transparent 45%, ${colors.ink}D9 100%)`,
} as const;

/** Neutral fallback plane shown when a render/music-dependent visual is missing. */
export const fallbackPlane = gradients.sunrise;
