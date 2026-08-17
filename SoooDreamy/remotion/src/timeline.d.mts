// FullRelease N1-C — Typdeklaration für die JS-Timeline (eine Quelle für
// Kompositionen UND Manifest-Export, deshalb .mjs statt .ts: der Export läuft
// als plain-node-Skript ohne TS-Loader).
export declare const FPS: number;
export declare const WIDTH: number;
export declare const HEIGHT: number;

export type BeatType = 'tap' | 'success' | 'soft';

export interface Beat {
  t: number;
  type: BeatType;
  i: number;
  s: number;
  d: number;
}

export interface SoundCue {
  t: number;
  id: string;
}

export interface SceneTimeline<T extends Record<string, number> = Record<string, number>> {
  composition: string;
  video: string;
  durationSec: number;
  posterTime: number;
  t: T;
  beats: Beat[];
  cues: SoundCue[];
}

export declare const SCENES: {
  scene2: SceneTimeline<{
    holdIn: number;
    envelopeIn: number;
    envelopeLand: number;
    addressStart: number;
    stamp: number;
    stampEcho: number;
    holdFrom: number;
  }>;
  scene3: SceneTimeline<{
    holdIn: number;
    sealTension: number;
    sealCrack: number;
    crackEcho: number;
    letterOut: number;
    unfoldTop: number;
    unfoldBottom: number;
    unfoldDone: number;
    inkLines: number;
    holdFrom: number;
  }>;
  scene6: SceneTimeline<{
    holdIn: number;
    dropIn: number;
    land: number;
    developStart: number;
    rockA: number;
    rockB: number;
    glint: number;
    developDone: number;
    holdFrom: number;
  }>;
};
