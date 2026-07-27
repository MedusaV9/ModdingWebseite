/**
 * V2-Szenen-Manifest (11 Video-Clips statt V1-Stills).
 * Quelle: docs/plans_v3/trailer/v2_storyboard.md §2/§4 + angepasstes Bar-Grid
 * aus der Musik-Analyse (Drop auf F563 statt F450).
 *
 * cutIn = inklusive, cutOut = exklusive. Summe aller Szenen = 1800 (Assertion unten).
 * trimBefore/playbackRate sind reine Remotion-Parameter — nachjustierbar OHNE Re-Encode.
 */

import {CUT, TOTAL} from './timings';
import {hasClip} from './clipManifest';

export interface ClipSpec {
  /** Szenen-ID (v01 … v11). */
  id: string;
  /** Pfad relativ zu public/ (staticFile()). */
  src: string;
  /** V1-Still (public/stills/<name>.jpg) — Notnagel, wenn der Clip fehlt. */
  fallbackStill: string;
  /** Composition-Frame, auf dem die Szene beginnt (Downbeat). */
  cutIn: number;
  /** Composition-Frame, auf dem die naechste Szene beginnt. */
  cutOut: number;
  /** Zeitraffer-Faktor auf der Quelle (Storyboard §2). */
  playbackRate: number;
  /** Vorlauf im Quellvideo in Quell-Frames (60 fps) — pro Clip nachjustieren. */
  trimBefore: number;
  /** Zugehoeriger Text-Overlay (siehe lib/texts.ts), oder undefined. */
  textId?: string;
  /** Rest-Ken-Burns ueber dem Video (kaschiert 1080p->4K-Upscale). */
  kenBurns?: {from: number; to: number; panX?: number; panY?: number};
  /** Fade aus Schwarz in Frames (nur V01). */
  fadeIn?: number;
  /** Zusatz-Shake beim Szenenstart. */
  shakeAmp?: number;
  /** Gold-Grade-Akzent ueber der Szene (nur V04). */
  gold?: boolean;
  /** Kurzbeschreibung fuer Studio/Debug. */
  label: string;
}

const KB_DEFAULT = {from: 1.02, to: 1.06};

export const CLIPS: ClipSpec[] = [
  {
    id: 'v01',
    src: 'clips/v01_eclipse_island.mp4',
    fallbackStill: 'eclipse_sky',
    cutIn: CUT[0], // 0
    cutOut: CUT[2], // 225 — 2 Takte
    playbackRate: 2,
    trimBefore: 60,
    textId: 't1',
    kenBurns: {from: 1.02, to: 1.07, panY: -18},
    fadeIn: 24,
    label: 'Eclipse-Insel, Spectator-Push-in',
  },
  {
    id: 'v02',
    src: 'clips/v02_ghost_ship.mp4',
    fallbackStill: 'limbo_ship',
    cutIn: CUT[2], // 225
    cutOut: CUT[5], // 563 — 3 Takte, laeuft ueber den Musik-Breakdown
    playbackRate: 1.5,
    trimBefore: 60,
    textId: 't2',
    kenBurns: {from: 1.02, to: 1.06, panX: 24},
    label: 'Geisterschiff-Dolly mit Deckhands (Breakdown)',
  },
  {
    id: 'v03',
    src: 'clips/v03_sky_rift.mp4',
    fallbackStill: 'sky_rift',
    cutIn: CUT[5], // 563 — DROP
    cutOut: CUT[6], // 675
    playbackRate: 3,
    trimBefore: 60,
    textId: 't3',
    kenBurns: {from: 1.04, to: 1.09},
    shakeAmp: 36,
    label: 'Sky-Rift reisst auf (DROP)',
  },
  {
    id: 'v04',
    src: 'clips/v04_altar_deposit.mp4',
    fallbackStill: 'heart_ceremony',
    cutIn: CUT[6], // 675
    cutOut: CUT[7], // 788
    playbackRate: 2,
    trimBefore: 60,
    textId: 't4',
    kenBurns: KB_DEFAULT,
    gold: true,
    label: 'Altar-Einzahlung POV (Gold-Akzent)',
  },
  {
    id: 'v05',
    src: 'clips/v05_wand_fight.mp4',
    fallbackStill: 'wand_cast',
    cutIn: CUT[7], // 788
    cutOut: CUT[8], // 900
    playbackRate: 3,
    trimBefore: 60,
    textId: 't5',
    kenBurns: {from: 1.02, to: 1.07},
    label: 'Zauberstab-Kampf POV',
  },
  {
    id: 'v06',
    src: 'clips/v06_herald_arrival.mp4',
    fallbackStill: 'herald',
    cutIn: CUT[8], // 900 — 2. Drop-Runde
    cutOut: CUT[10], // 1125
    playbackRate: 2.5,
    trimBefore: 60,
    textId: 't6',
    kenBurns: {from: 1.06, to: 1.02},
    shakeAmp: 30,
    label: 'Herold-Ankunft (Saeule -> Spawn)',
  },
  {
    id: 'v07',
    src: 'clips/v07_village_storm.mp4',
    fallbackStill: 'storm_wall',
    cutIn: CUT[10], // 1125
    cutOut: CUT[11], // 1238
    playbackRate: 2,
    trimBefore: 60,
    textId: 't7',
    kenBurns: {from: 1.02, to: 1.06, panX: -18},
    label: 'Dorf + Sturmwand',
  },
  {
    id: 'v08',
    src: 'clips/v08_gravity_orbitals.mp4',
    fallbackStill: 'gravity_rift',
    cutIn: CUT[11], // 1238
    cutOut: CUT[12], // 1350
    playbackRate: 3,
    trimBefore: 60,
    kenBurns: {from: 1.03, to: 1.08},
    label: 'Gravity-Orbital-POV-Kampf (textfrei)',
  },
  {
    id: 'v09',
    src: 'clips/v09_ferryman_boss.mp4',
    fallbackStill: 'ferryman_close',
    cutIn: CUT[12], // 1350 — Musik-Peak
    cutOut: CUT[14], // 1575
    playbackRate: 2,
    trimBefore: 60,
    textId: 't8',
    kenBurns: {from: 1.02, to: 1.07},
    shakeAmp: 18,
    label: 'Faehrmann-Bosskampf (Peak)',
  },
  {
    id: 'v10',
    src: 'clips/v10_end_helix.mp4',
    fallbackStill: 'endarrival_pillar',
    cutIn: CUT[14], // 1575
    cutOut: CUT[15], // 1688
    playbackRate: 4,
    trimBefore: 60,
    textId: 't9',
    kenBurns: {from: 1.06, to: 1.02},
    label: 'End-Ankunfts-Helix (Zeitraffer)',
  },
  {
    id: 'v11',
    src: 'clips/v11_blackhole.mp4',
    fallbackStill: 'credits_blackhole',
    cutIn: CUT[15], // 1688
    cutOut: CUT[16], // 1800
    playbackRate: 2,
    trimBefore: 60,
    kenBurns: {from: 1.02, to: 1.06},
    shakeAmp: 24,
    label: 'Schwarzes Loch -> Sog -> Endcard',
  },
];

export const clipById = (id: string): ClipSpec => {
  const c = CLIPS.find((x) => x.id === id);
  if (!c) throw new Error(`Unbekannte Clip-ID: ${id}`);
  return c;
};

export const clipDuration = (c: ClipSpec) => c.cutOut - c.cutIn;

/** Wie viele Quell-Frames die Szene verbraucht (fuer trimAfter). */
export const sourceFrames = (c: ClipSpec) =>
  Math.ceil(clipDuration(c) * c.playbackRate);

/** true, wenn die Videodatei laut generiertem Manifest existiert. */
export const clipAvailable = (c: ClipSpec) => hasClip(c.src);

// ---------------------------------------------------------------- Assertions
const sum = CLIPS.reduce((a, c) => a + clipDuration(c), 0);
if (sum !== TOTAL) {
  throw new Error(`clips.ts: Summe der Szenendauern = ${sum}, erwartet ${TOTAL}`);
}
CLIPS.forEach((c, i) => {
  if (i > 0 && CLIPS[i - 1].cutOut !== c.cutIn) {
    throw new Error(`clips.ts: Luecke/Ueberlappung vor ${c.id}`);
  }
  if (!CUT.includes(c.cutIn)) {
    throw new Error(`clips.ts: ${c.id} beginnt nicht auf einem Downbeat (${c.cutIn})`);
  }
});
