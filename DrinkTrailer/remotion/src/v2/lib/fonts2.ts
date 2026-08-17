/**
 * Font preset resolution for v2 styles.
 *
 * Real webfonts (loaded by src/shared/fonts.ts via loadBrandFonts() in
 * Root.tsx): Bebas Neue (display), Space Grotesk Bold, Inter 400/500/600.
 * 'serif' and 'mono' use system stacks until dedicated font files are added
 * to assets/fonts/ — safe on the Linux render host (DejaVu fallbacks).
 */
import type {CSSProperties} from 'react';
import type {FontPreset} from '../config/types';

export type FontPair = {
  /** Big display/headline font stack. */
  display: string;
  /** Body/label font stack. */
  body: string;
  /** Extra styling applied to display text (italics, tracking, …). */
  displayStyle?: CSSProperties;
  /** Default letter-spacing for display text (em). */
  displayTracking: string;
  /** Uppercase display text? */
  uppercase: boolean;
};

const BEBAS = "'Bebas Neue', 'Arial Narrow', sans-serif";
const GROTESK = "'Space Grotesk', 'Futura', sans-serif";
const INTER = "'Inter', 'Helvetica Neue', sans-serif";
const SERIF = "Georgia, 'DejaVu Serif', 'Times New Roman', serif";
const MONO = "'DejaVu Sans Mono', 'Courier New', monospace";

export const FONT_PAIRS: Record<FontPreset, FontPair> = {
  hype: {
    display: BEBAS,
    body: INTER,
    displayTracking: '0.04em',
    uppercase: true,
  },
  clean: {
    display: GROTESK,
    body: INTER,
    displayStyle: {fontWeight: 700},
    displayTracking: '-0.01em',
    uppercase: false,
  },
  serif: {
    display: SERIF,
    body: INTER,
    displayStyle: {fontWeight: 400, fontStyle: 'italic'},
    displayTracking: '0.01em',
    uppercase: false,
  },
  mono: {
    display: MONO,
    body: MONO,
    displayStyle: {fontWeight: 700},
    displayTracking: '0.02em',
    uppercase: true,
  },
  y2k: {
    display: GROTESK,
    body: INTER,
    displayStyle: {fontWeight: 700, fontStyle: 'italic'},
    displayTracking: '0.06em',
    uppercase: true,
  },
};

export const fontPair = (preset: FontPreset): FontPair => FONT_PAIRS[preset];
