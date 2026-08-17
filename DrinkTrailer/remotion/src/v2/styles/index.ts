/**
 * All 35 v2 style configs, ordered 01..35. Each file exports `style`;
 * registerV2() turns every entry into an "EarlyV2-{NN}-{slug}" composition.
 *
 * Style ↔ track matrix: see each file header. Tracks that don't exist yet in
 * assets/music/v2/ fall back to the v1 hype/clean track (per trackFallback)
 * and their BPM grid — configs light up automatically once the music agent
 * delivers the file + beat_grid_v2.json entry.
 */
import type {TrailerStyleConfig} from '../config/types';
import {style as s01} from './01_hype_phonk';
import {style as s02} from './02_clean_air';
import {style as s03} from './03_y2k_hyperpop';
import {style as s04} from './04_vhs_retro';
import {style as s05} from './05_noir_peach';
import {style as s06} from './06_gym_power';
import {style as s07} from './07_lofi_morning';
import {style as s08} from './08_club_strobe';
import {style as s09} from './09_nature_fresh';
import {style as s10} from './10_type_only';
import {style as s11} from './11_split_duo';
import {style as s12} from './12_macro_sensory';
import {style as s13} from './13_speedrun_tour';
import {style as s14} from './14_cinematic_epic';
import {style as s15} from './15_glitchcore';
import {style as s16} from './16_pastel_collage';
import {style as s17} from './17_swiss_grid';
import {style as s18} from './18_golden_hour';
import {style as s19} from './19_underwater';
import {style as s20} from './20_countdown_drop';
import {style as s21} from './21_quote_cards';
import {style as s22} from './22_flavor_peach';
import {style as s23} from './23_flavor_grapefruit';
import {style as s24} from './24_flavor_lemonmint';
import {style as s25} from './25_ingredient_story';
import {style as s26} from './26_before_after';
import {style as s27} from './27_stop_motion';
import {style as s28} from './28_neon_outline';
import {style as s29} from './29_paper_torn';
import {style as s30} from './30_zoom_through';
import {style as s31} from './31_emoji_storm';
import {style as s32} from './32_luxury_serif';
import {style as s33} from './33_interval_timer';
import {style as s34} from './34_confetti_pop';
import {style as s35} from './35_grand_finale';

export const V2_STYLES: TrailerStyleConfig[] = [
  s01, s02, s03, s04, s05, s06, s07, s08, s09, s10,
  s11, s12, s13, s14, s15, s16, s17, s18, s19, s20,
  s21, s22, s23, s24, s25, s26, s27, s28, s29, s30,
  s31, s32, s33, s34, s35,
];

// Fail fast at module load if a style file drifts out of order.
V2_STYLES.forEach((style, i) => {
  if (style.id !== i + 1) {
    throw new Error(
      `V2 style order mismatch: index ${i} has id ${style.id} (${style.slug})`,
    );
  }
  if (style.durationSec < 15 || style.durationSec > 40) {
    throw new Error(`V2 style ${style.slug}: durationSec ${style.durationSec} out of range`);
  }
});
const slugs = new Set(V2_STYLES.map((s) => s.slug));
if (slugs.size !== V2_STYLES.length) {
  throw new Error('V2 styles contain duplicate slugs');
}
