/**
 * AUTO-GENERIERT von tools/gen_clip_manifest.mjs — NICHT von Hand editieren.
 * Liste der tatsaechlich in public/clips/ vorhandenen Videodateien.
 * Fehlt eine Datei hier, faellt die Szene in Clip.tsx auf ihren V1-Still zurueck.
 */

export const AVAILABLE_CLIPS: readonly string[] = [
  'clips/v01_eclipse_island.mp4',
  'clips/v02_ghost_ship.mp4',
  'clips/v05_wand_fight.mp4',
  'clips/v06_herald_arrival.mp4',
  'clips/v10_end_helix.mp4',
  'clips/v11_blackhole.mp4',
];

export const hasClip = (src: string): boolean => AVAILABLE_CLIPS.includes(src);
