/**
 * Hype-only asset helpers on top of src/lib/assets.ts (read-only lib):
 * typed access to the Blender render STILLS (renders/early_still_*.png,
 * renders/early_trio_16x9.png) that the generic imageSrc() does not cover.
 */
import {assetSrc, hasAsset} from '../lib/assets';

const RENDER_STILLS = {
  stillPeach9x16: 'renders/early_still_peach_9x16.png',
  stillGrapefruit9x16: 'renders/early_still_grapefruit_9x16.png',
  stillLemonMint9x16: 'renders/early_still_lemonmint_9x16.png',
  stillPeach16x9: 'renders/early_still_peach_16x9.png',
  stillGrapefruit16x9: 'renders/early_still_grapefruit_16x9.png',
  stillLemonMint16x9: 'renders/early_still_lemonmint_16x9.png',
  trio16x9: 'renders/early_trio_16x9.png',
} as const satisfies Record<string, string>;

export type RenderStillKey = keyof typeof RENDER_STILLS;

/** staticFile() URL of a Blender render still, or null if not synced yet. */
export const renderStillSrc = (key: RenderStillKey): string | null =>
  hasAsset(RENDER_STILLS[key]) ? assetSrc(RENDER_STILLS[key]) : null;
