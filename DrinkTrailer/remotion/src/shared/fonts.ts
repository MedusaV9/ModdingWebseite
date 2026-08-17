/**
 * Brand fonts, loaded via the FontFace API from staticFile() URLs
 * (files live in DrinkTrailer/assets/fonts/, synced to public/assets/fonts/).
 *
 * All fonts are OFL-licensed; license files sit next to the .woff2 files.
 * loadBrandFonts() is called once from src/Root.tsx.
 */
import {continueRender, delayRender} from 'remotion';
import {assetSrc, hasAsset} from '../lib/assets';

export const fontFamilies = {
  /** Bebas Neue — hype display headlines, uppercase. */
  display: "'Bebas Neue', 'Arial Narrow', sans-serif",
  /** Space Grotesk Bold — headlines / statements. */
  headline: "'Space Grotesk', 'Futura', sans-serif",
  /** Inter — body copy, labels, captions (400/500/600). */
  body: "'Inter', 'Helvetica Neue', sans-serif",
} as const;

type FontSpec = {family: string; file: string; weight: string};

const FONTS: FontSpec[] = [
  {family: 'Inter', file: 'fonts/inter/Inter-Regular.woff2', weight: '400'},
  {family: 'Inter', file: 'fonts/inter/Inter-Medium.woff2', weight: '500'},
  {family: 'Inter', file: 'fonts/inter/Inter-SemiBold.woff2', weight: '600'},
  {family: 'Space Grotesk', file: 'fonts/space-grotesk/SpaceGrotesk-Bold.woff2', weight: '700'},
  {family: 'Bebas Neue', file: 'fonts/bebas-neue/BebasNeue-Regular.woff2', weight: '400'},
];

let started = false;

export const loadBrandFonts = (): void => {
  if (started || typeof document === 'undefined') return;
  started = true;

  for (const spec of FONTS) {
    if (!hasAsset(spec.file)) {
      // eslint-disable-next-line no-console
      console.warn(`[fonts] Missing ${spec.file} — falling back to system font.`);
      continue;
    }
    const handle = delayRender(`Loading font ${spec.family} ${spec.weight}`);
    const face = new FontFace(spec.family, `url(${assetSrc(spec.file)}) format('woff2')`, {
      weight: spec.weight,
    });
    face
      .load()
      .then((loaded) => {
        document.fonts.add(loaded);
        continueRender(handle);
      })
      .catch((err: unknown) => {
        // eslint-disable-next-line no-console
        console.warn(`[fonts] Failed to load ${spec.file}:`, err);
        continueRender(handle);
      });
  }
};
