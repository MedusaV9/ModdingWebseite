/**
 * Data-driven storyboard (docs/plans_v3/trailer/storyboard.md).
 * Frame ranges are inclusive start, exclusive end (from..to), sum = 1800.
 * Stills live in public/stills/<still>.jpg (1920x1080).
 */

export type Transition = 'cut' | 'glitch' | 'whip' | 'none';

export interface Shot {
  name: string;
  from: number;
  to: number; // exclusive
  still: string;
  /** Ken-Burns scale range (1.0 = fill). */
  scaleFrom: number;
  scaleTo: number;
  /** Drift in px @4K (applied diagonally unless panX given). */
  panX?: number;
  panY?: number;
  rotate?: number;
  /** Transition INTO the next shot. */
  out: Transition;
  /** Extra shake amplitude at shot start. */
  shakeAmp?: number;
  /** Fade in from black (frames). */
  fadeIn?: number;
  focusX?: number; // 0..1 mask anchor
  focusY?: number;
}

export interface TextCardSpec {
  text: string;
  inStart: number;
  inEnd: number;
  outStart: number;
  outEnd: number; // if outEnd < 0: stays
  pop?: boolean;
  gold?: boolean;
  glitchy?: boolean;
  y?: number; // 0..1 vertical anchor, default 0.5
  size?: number;
}

export const SHOTS: Shot[] = [
  // ---- Akt I — Ruhe
  {name: 'S01_eclipse', from: 0, to: 150, still: 'eclipse_sky', scaleFrom: 1.06, scaleTo: 1.12, panY: -40, out: 'cut', fadeIn: 24, focusX: 0.5, focusY: 0.35},
  {name: 'S02_island', from: 150, to: 300, still: 'altar_island', scaleFrom: 1.06, scaleTo: 1.18, panY: 20, out: 'cut', focusX: 0.5, focusY: 0.45},
  // ---- Akt II — Eskalation
  {name: 'S03_skyrift', from: 300, to: 420, still: 'sky_rift', scaleFrom: 1.1, scaleTo: 1.1, panX: 120, out: 'glitch', focusX: 0.5, focusY: 0.3},
  {name: 'S04_crater', from: 420, to: 540, still: 'nether_crater', scaleFrom: 1.08, scaleTo: 1.2, out: 'whip', shakeAmp: 14, focusX: 0.5, focusY: 0.55},
  {name: 'S05_endcall', from: 540, to: 660, still: 'endarrival_pillar', scaleFrom: 1.18, scaleTo: 1.06, rotate: -1.5, out: 'cut', focusX: 0.5, focusY: 0.4},
  {name: 'S06a_wand', from: 660, to: 705, still: 'wand_cast', scaleFrom: 1.06, scaleTo: 1.14, out: 'cut', focusX: 0.5, focusY: 0.5},
  {name: 'S06b_skilltree', from: 705, to: 750, still: 'skilltree_ui', scaleFrom: 1.1, scaleTo: 1.12, panX: -90, out: 'glitch', focusX: 0.5, focusY: 0.5},
  {name: 'S07_hearts', from: 750, to: 840, still: 'heart_ceremony', scaleFrom: 1.05, scaleTo: 1.14, out: 'cut', focusX: 0.5, focusY: 0.5},
  // ---- Horror-Stinger (3 Blitzbilder + Schwarz)
  {name: 'S08a_backrooms', from: 840, to: 858, still: 'backrooms', scaleFrom: 1.1, scaleTo: 1.1, out: 'cut', shakeAmp: 10},
  {name: 'S08b_dome', from: 858, to: 876, still: 'mansion_dome', scaleFrom: 1.12, scaleTo: 1.12, out: 'cut', shakeAmp: 10},
  {name: 'S08c_gravity', from: 876, to: 894, still: 'gravity_rift', scaleFrom: 1.14, scaleTo: 1.14, out: 'none', shakeAmp: 10},
  // 894..900 = hard black (handled in comp)
  // ---- Akt III — Drop-Montage
  {name: 'S09_fogtyrant', from: 900, to: 1005, still: 'storm_wall', scaleFrom: 1.06, scaleTo: 1.24, out: 'whip', shakeAmp: 16, focusX: 0.5, focusY: 0.5},
  {name: 'S10_riftwarden', from: 1005, to: 1110, still: 'rift_warden', scaleFrom: 1.06, scaleTo: 1.2, panX: -110, out: 'glitch', focusX: 0.5, focusY: 0.45},
  {name: 'S11_herald', from: 1110, to: 1215, still: 'herald', scaleFrom: 1.2, scaleTo: 1.08, out: 'cut', focusX: 0.5, focusY: 0.4},
  {name: 'S12a_ship', from: 1215, to: 1265, still: 'limbo_ship', scaleFrom: 1.08, scaleTo: 1.12, panX: 70, out: 'cut', focusX: 0.5, focusY: 0.5},
  {name: 'S12b_ferryman', from: 1265, to: 1320, still: 'ferryman_close', scaleFrom: 1.06, scaleTo: 1.18, out: 'glitch', focusX: 0.5, focusY: 0.42},
  // ---- Feature-Schnellschnitt (6 x 20)
  {name: 'S13a', from: 1320, to: 1340, still: 'chrono_stasis', scaleFrom: 1.08, scaleTo: 1.14, out: 'cut'},
  {name: 'S13b', from: 1340, to: 1360, still: 'resonance_field', scaleFrom: 1.08, scaleTo: 1.14, out: 'cut'},
  {name: 'S13c', from: 1360, to: 1380, still: 'echo_grove', scaleFrom: 1.08, scaleTo: 1.14, out: 'cut'},
  {name: 'S13d', from: 1380, to: 1400, still: 'helix_detail', scaleFrom: 1.1, scaleTo: 1.16, out: 'cut'},
  {name: 'S13e', from: 1400, to: 1420, still: 'shop_ceremony', scaleFrom: 1.08, scaleTo: 1.14, out: 'cut'},
  {name: 'S13f', from: 1420, to: 1440, still: 'skilltree_ui', scaleFrom: 1.12, scaleTo: 1.18, out: 'cut'},
  // ---- Akt IV — Schwarzes Loch (S14: 1440..1590 handled by BlackHole comp on top of this still)
  {name: 'S14_blackhole', from: 1440, to: 1590, still: 'credits_blackhole', scaleFrom: 1.06, scaleTo: 1.14, out: 'none', focusX: 0.5, focusY: 0.5},
  // S15 endcard 1590..1800 is pure 4K design (EclipseRing)
];

export const TEXTS: TextCardSpec[] = [
  {text: 'Sieben Tage.', inStart: 40, inEnd: 60, outStart: 125, outEnd: 145},
  {text: 'Eine Welt, die wächst.', inStart: 190, inEnd: 210, outStart: 275, outEnd: 295},
  {text: 'Und ein Himmel, der bricht.', inStart: 330, inEnd: 345, outStart: 400, outEnd: 415},
  {text: 'Tag 2.', inStart: 430, inEnd: 440, outStart: 470, outEnd: 480, pop: true},
  {text: 'Der Altar ruft.', inStart: 575, inEnd: 590, outStart: 640, outEnd: 655},
  {text: '30 Zauber. Dein Pfad.', inStart: 668, inEnd: 680, outStart: 735, outEnd: 747},
  {text: 'Zahl mit Herzen.', inStart: 775, inEnd: 790, outStart: 822, outEnd: 837, gold: true},
  {text: 'Sie warten auf dich.', inStart: 910, inEnd: 920, outStart: 985, outEnd: 1000, pop: true, glitchy: true},
  {text: 'Tag 7.', inStart: 1120, inEnd: 1130, outStart: 1160, outEnd: 1170, pop: true},
  {text: 'Der Fährmann wartet.', inStart: 1270, inEnd: 1282, outStart: 1305, outEnd: 1317},
  {text: 'Eine Woche. Keine zweite Chance.', inStart: 1330, inEnd: 1342, outStart: 1420, outEnd: 1435, y: 0.78, size: 96},
  {text: 'Am Ende bleibt nichts.', inStart: 1470, inEnd: 1490, outStart: 1545, outEnd: 1565},
];

/** Frames with a 1-frame white flash (glitch cut centres + hero slam). */
export const CUT_FLASHES = [424, 704, 754, 904, 1112, 1444];
