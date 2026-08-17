/**
 * WAVE B — styles 04..19 (built by the wave_b style agent).
 *
 * Copy a style from wave_a.ts as a starting point and follow this template:
 *
 *   {
 *     id: 4,                              // fixed — see PLANNED_SLUGS in index.ts
 *     slug: 'y2k_hyperpop',               // fixed slug for this id
 *     displayName: 'Y2K Hyperpop',
 *     durationSec: 18,                    // 15..40
 *     track: 'hyperpop_150',              // key in beat_grid_v2.json (music agent)
 *     trackFallback: 'hype',              // 'hype' 140bpm | 'clean' 105bpm until then
 *     palette: {bg, ink, accent, accent2},
 *     fontPreset: 'y2k',                  // 'hype'|'clean'|'serif'|'mono'|'y2k'
 *     gradePreset: 'neon',                // see GradePreset in config/types.ts
 *     effects: ['stickers', 'chromatic'], // see EffectId in config/types.ts
 *     defaultTransition: 'zoom_in',
 *     structure: [ ... ],                 // beats must sum ≈ durationSec/beatSec;
 *                                         // last scene 'endcard' (auto-added else)
 *     copy: {hook, mid: [...], cta},      // *word* = accent color
 *     sfxPlan: {cues: [...], onSceneCut: 'whoosh'},
 *   }
 *
 * Rules: image keys from IMAGES2 (src/v2/lib/assets2.ts), render keys from
 * RENDERS2. Keep core copy out of the bottom 20% (SafeArea does this for
 * factory scenes). Check your style with:
 *   npx remotion still Early35-NN-your-slug out/test.png --frame=120
 */
import type {TrailerStyleConfig} from '../config/types';

export const WAVE_B: TrailerStyleConfig[] = [];
