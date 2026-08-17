/**
 * Flavor chapter data + exact brand copy for the clean trailers.
 * Claims are verbatim brand wording — do not reword.
 */
import {assetSrc, hasAsset} from '../lib/assets';
import {colors} from '../shared/tokens';

/** Resolve a manifest-relative still (e.g. Blender render PNG), or null. */
export const stillSrc = (relativePath: string): string | null =>
  hasAsset(relativePath) ? assetSrc(relativePath) : null;

export type CleanFlavor = {
  id: string;
  /** Chapter display name (DE). */
  name: string;
  /** Brand flavor accent used for the chapter color field. */
  color: string;
  still9x16: string;
  still16x9: string;
};

export const CLEAN_FLAVORS: CleanFlavor[] = [
  {
    id: 'peach',
    name: 'Pfirsich',
    color: colors.rose,
    still9x16: 'renders/early_still_peach_9x16.png',
    still16x9: 'renders/early_still_peach_16x9.png',
  },
  {
    id: 'grapefruit',
    name: 'Grapefruit',
    color: colors.coral,
    still9x16: 'renders/early_still_grapefruit_9x16.png',
    still16x9: 'renders/early_still_grapefruit_16x9.png',
  },
  {
    id: 'lemonmint',
    name: 'Zitrone-Minze',
    color: colors.lime,
    still9x16: 'renders/early_still_lemonmint_9x16.png',
    still16x9: 'renders/early_still_lemonmint_16x9.png',
  },
];

/** Exact brand claims. */
export const CLAIM_PRODUCT = 'SPARKLING VITAMIN DRINK';
export const CLAIM_HYDRATION = 'HYDRATION WITH BENEFITS';
export const CLAIM_BENEFITS = ['ISOTONISCH', 'KALORIENARM', 'VITAMINE + ELEKTROLYTE'];
export const BENEFITS_LINE = CLAIM_BENEFITS.join(' · ');
/** Deliberate two-line break for narrow columns (landscape chapter block). */
export const BENEFITS_LINES = ['ISOTONISCH · KALORIENARM', 'VITAMINE + ELEKTROLYTE'];

export const CTA_URL = 'drinkearly.com';
export const CTA_HANDLE = '@drink.early';

/** 16:9 Blender lineup render used for the landscape finale. */
export const TRIO_STILL_16X9 = 'renders/early_trio_16x9.png';
