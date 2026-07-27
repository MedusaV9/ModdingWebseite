import React from 'react';
import {Audio, Sequence, interpolate, staticFile} from 'remotion';
import {MUSIC, TOTAL} from '../lib/timings';

/**
 * Ton V2: "Worst Enemy feat. goldN" — Shawn Williams (128 BPM, f-Moll),
 * public/audio/worst_enemy_30s.wav, exakt 30.000 s / 48 kHz stereo PCM.
 *
 * Der Track wird 1:1 ab Frame 0 abgespielt — KEIN zusaetzlicher Audio-Schnitt und
 * bewusst KEINE Duck-Automation: die Dynamik (Chorus -> Breakdown -> Drop -> Peak)
 * steckt bereits im Song. Die Envelope macht nur Fade-in und Safety-Fade-out.
 */

const lin = (db: number) => Math.pow(10, db / 20);

/**
 * Master-Pegel der Musik. Vorgabe = 1.0 (die Dynamik steckt im Song).
 * ACHTUNG: worst_enemy_30s.wav ist ein kommerzieller Loud-Master
 * (gemessen I = -6.4 LUFS, True Peak +0.8 dBFS) — der Mix clippt dadurch
 * bereits ohne SFX. Wer Headroom braucht: hier 0.85 (~ -1.4 dB) setzen ODER
 * (besser) das WAV nach sound_design.md §5 auf -14 LUFS / -1.5 dBTP
 * normalisieren; dann kann dieser Wert auf 1.0 bleiben.
 */
export const MUSIC_GAIN = 1.0;

export const musicVolume = (f: number) =>
  MUSIC_GAIN *
  interpolate(
    f,
    [0, MUSIC.FADE_IN_END, MUSIC.FADE_OUT_START, TOTAL],
    [0, 1, 1, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );

interface SfxSpot {
  f: number;
  src: string;
  db: number;
  /** Harte Laengenbegrenzung in Frames (Sequence-Dauer). */
  dur?: number;
  note: string;
}

/** SFX-Spotting V2 — alle Dateien liegen bereits in public/audio/. */
export const SFX: SfxSpot[] = [
  {f: 30, src: 'sfx_whisper', db: -12, note: 'Fluester-Creep unter V01'},
  {f: 280, src: 'sfx_whisper', db: -12, note: 'Fluester-Creep unter V02'},
  {f: 300, src: 'sfx_bell', db: -10, note: 'Ferne Glocke am Geisterschiff'},
  {f: 450, src: 'sfx_riser', db: -8, dur: 113, note: 'Riser unter dem Build, endet hart auf F563'},
  {f: 559, src: 'sfx_glitch', db: -8, note: 'Glitch-Cut in den Drop'},
  {f: 563, src: 'sfx_impact', db: -3, note: 'DROP-Impact (Sky-Rift)'},
  {f: 896, src: 'sfx_glitch', db: -8, note: 'Glitch-Cut in die 2. Drop-Runde'},
  {f: 900, src: 'sfx_impact', db: -4, note: 'Impact 2 (Herold-Ankunft)'},
  {f: 1346, src: 'sfx_glitch', db: -8, note: 'Glitch-Cut in den Faehrmann'},
  {f: 1360, src: 'sfx_bell', db: -8, note: 'Faehrmann-Signatur'},
  {f: MUSIC.OUTRO, src: 'sfx_sub_boom', db: 0, note: 'Abriss / Schwarzes Loch'},
  {f: 1720, src: 'sfx_unlock', db: -10, note: 'Titel-Slam'},
];

export const TrailerAudio: React.FC = () => (
  <>
    <Audio src={staticFile('audio/worst_enemy_30s.wav')} volume={musicVolume} />
    {SFX.map((s, i) => (
      <Sequence key={`sfx-${i}-${s.src}`} from={s.f} durationInFrames={s.dur} name={`sfx ${s.src} @${s.f}`}>
        <Audio src={staticFile(`audio/${s.src}.wav`)} volume={lin(s.db)} />
      </Sequence>
    ))}
  </>
);
