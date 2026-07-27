/**
 * Beat-/Schnitt-Raster V2 — "Worst Enemy feat. goldN" (Shawn Williams), 128 BPM, f-Moll.
 * Quelle: docs/plans_v3/trailer/v2_storyboard.md §1 + Energie-Analyse des echten Songs.
 *
 * 128 BPM @ 60 fps  ->  1 Beat = 28.125 F,  1 Takt (4 Beats) = 112.5 F
 * 30 s = 1800 F = exakt 16 Takte. Jeder Schnitt liegt auf einem Downbeat.
 */

export const FPS = 60;
export const TOTAL = 1800;

export const BPM = 128;
/** Frames pro Beat (28.125). */
export const BEAT = (FPS * 60) / BPM;
/** Frames pro Takt (112.5). */
export const BAR = BEAT * 4;

/** Downbeat n (0-basiert) als ganzzahliger Frame; .5 wird aufgerundet. */
export const bar = (n: number) => Math.round(n * BAR);

/** CUT[0..16] — Downbeat-Raster (Storyboard §1.2). */
export const CUT: number[] = Array.from({length: 17}, (_, i) => bar(i));
// [0, 113, 225, 338, 450, 563, 675, 788, 900, 1013, 1125, 1238, 1350, 1463, 1575, 1688, 1800]

/**
 * Gemessene Energie-Struktur des 30-s-WAV (ebur128 Momentary):
 *  0.0– 5.6 s  voller Chorus (heiss)
 *  6.0– 9.4 s  Breakdown (leise, Minimum -10.9 LUFS-M @ 6.5 s)
 *  9.4 s       DROP-Return (groesster Energie-Step) -> Frame 563
 * 12.5 s       1-Takt-Breather                      -> Frame 750
 * 22.5–26.2 s  Peak-Energie                         -> Frames 1350–1575
 * 27.5–30.0 s  leichtes Taper
 */
export const MUSIC = {
  /** Groesster Energie-Step im Track = Bild-Drop. */
  DROP: 563,
  /** 2. Drop-Runde / Wiedereinstieg. */
  DROP_2: 900,
  /** Beginn des Peak-Fensters. */
  PEAK_IN: 1350,
  /** Ende des Peak-Fensters. */
  PEAK_OUT: 1575,
  /** Abriss / Endcard-Downbeat (Takt 16). */
  OUTRO: 1688,
  FADE_IN_END: 20,
  FADE_OUT_START: 1770,
} as const;

/** Akt-Grenzen fuer Grade/FX (V2: F563 / F900 / F1688). */
export const ACT = {
  I_TO_II: MUSIC.DROP,
  II_A_TO_II_B: MUSIC.DROP_2,
  II_TO_III: MUSIC.PEAK_IN,
  ENDCARD: MUSIC.OUTRO,
} as const;

/** Glitch-Cuts (Cut-Frame minus 4 F Vorlauf, Storyboard §4.2). */
export const GLITCH_CUTS = [559, 896, 1346];

/** Impact-Weissblitze. */
export const FLASHES = [MUSIC.DROP, MUSIC.DROP_2, 1350];

/** Whip-Pan-Fake V07 -> V08 (Storyboard §2). */
export const WHIP = {from: 1232, mid: 1238, to: 1244} as const;

/** Endcard-Timings innerhalb V11 (F1688–1800). */
export const ENDCARD = {
  /** Cut auf V11 + Sub-Boom. */
  start: MUSIC.OUTRO,
  /** So viele Frames laeuft das Clip-Material, danach ist es weggesogen. */
  clipFrames: 40,
  /** Radialer Sog (scale/rotate) auf dem Szenen-Wrapper. */
  suckFrom: MUSIC.OUTRO,
  suckTo: 1712,
  /** Schwarzes-Loch-Ebene; Einstein-Ring ist ab ~F1696 sichtbar. */
  holeFrom: MUSIC.OUTRO,
  holeDur: 40,
  /** Eclipse-Ring-Morph: Mount blendet die Endcard-Flaeche ueber den
   *  Einstein-Ring (dieser Crossfade IST der Morph), Reveal startet
   *  Scheibe/Korona. */
  ringMount: 1708,
  ringReveal: 1716,
  diamond: 1730,
  /** Titel-SLAM "PROJECT: ECLIPSE". */
  title: 1720,
  /** Subline "Sieben Tage. Ein Ende." */
  subline: 1760,
  titleGlitch: 1786,
} as const;
