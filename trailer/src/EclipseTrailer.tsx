import React from 'react';
import '@fontsource/bebas-neue';
import '@fontsource/anton';
import '@fontsource/space-grotesk/500.css';
import '@fontsource/space-grotesk/700.css';
import '@fontsource/jetbrains-mono/500.css';
import {
  AbsoluteFill,
  Audio,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  Easing,
} from 'remotion';
import {SHOTS, TEXTS} from './lib/shots';
import {shake, idleWobble} from './lib/util';
import {Still} from './components/Still';
import {Letterbox, GradeOverlay, Vignette, Grain, Flash} from './components/Overlays';
import {GlitchBars, glitchJitter} from './components/Glitch';
import {Debris} from './components/Debris';
import {TextCard} from './components/TextCard';
import {EclipseRing} from './components/EclipseRing';
import {BlackHole} from './components/BlackHole';

// Transition-derived event frames
const GLITCH_CUTS = SHOTS.filter((s) => s.out === 'glitch').map((s) => s.to - 5);
const WHIPS = SHOTS.filter((s) => s.out === 'whip').map((s) => s.to);
const FLASHES = [...GLITCH_CUTS.map((f) => f + 4), ...WHIPS, 1620];

const SFX: {f: number; src: string; db: number}[] = [
  {f: 30, src: 'sfx_whisper', db: -12},
  {f: 40, src: 'sfx_sub_boom', db: -16},
  {f: 150, src: 'sfx_bell', db: -10},
  {f: 300, src: 'sfx_impact', db: -6},
  {f: 420, src: 'sfx_sub_boom', db: -12},
  {f: 480, src: 'sfx_glitch', db: -8},
  {f: 747, src: 'sfx_riser', db: -4},
  {f: 891, src: 'sfx_shatter', db: -3},
  {f: 1005, src: 'sfx_impact', db: -6},
  {f: 1110, src: 'sfx_glitch', db: -8},
  {f: 1206, src: 'sfx_bell', db: -8},
  {f: 1320, src: 'sfx_glitch', db: -8},
  {f: 1440, src: 'sfx_impact', db: -4},
  {f: 1560, src: 'sfx_sub_boom', db: 0},
  {f: 1620, src: 'sfx_unlock', db: -10},
];
const lin = (db: number) => Math.pow(10, db / 20);

const musicVolume = (f: number) =>
  interpolate(
    f,
    [0, 45, 300, 620, 747, 880, 900, 1005, 1015, 1035, 1435, 1445, 1465, 1755, 1800],
    [0, 0.85, 0.9, 0.9, 0.8, 0.6, 1, 1, 0.8, 1, 1, 0.8, 1, 1, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );

export const EclipseTrailer: React.FC = () => {
  const frame = useCurrentFrame();

  // ---- master scene transform (wobble + shakes + glitch jitter + whip + suction)
  const wob = idleWobble(frame);
  let sx = wob.x;
  let sy = wob.y;
  let rot = 0;

  for (const s of SHOTS) {
    if (s.shakeAmp && frame >= s.from) {
      const sh = shake(frame, s.from, s.shakeAmp);
      sx += sh.x;
      sy += sh.y;
      rot += sh.rot;
    }
  }
  // impacts: drop (900, heavy) + outro hit (1440)
  const dropShake = shake(frame, 900, 36);
  const outroShake = shake(frame, 1440, 24);
  sx += dropShake.x + outroShake.x;
  sy += dropShake.y + outroShake.y;
  rot += dropShake.rot + outroShake.rot;

  const jit = glitchJitter(frame, GLITCH_CUTS);
  sx += jit.x;
  sy += jit.y;

  // whip transitions
  let whipY = 0;
  let whipX = 0;
  if (frame >= 532 && frame < 548) {
    whipY = frame < 540
      ? interpolate(frame, [532, 540], [0, -700], {easing: Easing.in(Easing.cubic)})
      : interpolate(frame, [540, 548], [500, 0], {easing: Easing.out(Easing.cubic)});
  }
  if (frame >= 997 && frame < 1013) {
    whipX = frame < 1005
      ? interpolate(frame, [997, 1005], [0, -900], {easing: Easing.in(Easing.cubic)})
      : interpolate(frame, [1005, 1013], [700, 0], {easing: Easing.out(Easing.cubic)});
  }

  // black hole suction 1490-1590
  let suckScale = 1;
  let suckRot = 0;
  if (frame >= 1490) {
    const p = interpolate(frame, [1490, 1590], [0, 1], {
      extrapolateRight: 'clamp',
      easing: Easing.bezier(0.7, 0, 0.84, 0),
    });
    suckScale = 1 - 0.96 * p;
    suckRot = -320 * p;
    const sh = shake(frame, 1500, 18, 20);
    sx += sh.x;
    sy += sh.y;
  }

  const sceneTransform = `scale(${1.02 * suckScale}) translate(${sx + whipX}px, ${sy + whipY}px) rotate(${rot + suckRot}deg)`;

  const hardBlack = frame >= 894 && frame < 900;
  const debrisOpacity = interpolate(
    frame,
    [0, 200, 300, 900, 1440, 1590, 1620],
    [0.25, 0.3, 0.5, 0.9, 1, 0.6, 0],
    {extrapolateRight: 'clamp'},
  );

  return (
    <AbsoluteFill style={{backgroundColor: '#030204', overflow: 'hidden'}}>
      {/* ---------- scene stack */}
      <AbsoluteFill style={{transform: sceneTransform}}>
        {SHOTS.map((s) => (
          <Sequence key={s.name} from={s.from} durationInFrames={s.to - s.from}>
            <Still shot={s} />
          </Sequence>
        ))}
      </AbsoluteFill>

      {/* ---------- debris field */}
      {frame < 1620 && <Debris opacity={debrisOpacity} />}

      {/* ---------- grade / vignette / grain */}
      <GradeOverlay />
      <Vignette />
      <Grain />

      {/* ---------- black hole + endcard */}
      <BlackHole />
      <EclipseRing />

      {/* ---------- glitch bars */}
      {GLITCH_CUTS.map((cf) => (
        <GlitchBars key={cf} cutFrame={cf} frame={frame} />
      ))}

      {/* ---------- hard stinger black */}
      {hardBlack && <AbsoluteFill style={{background: '#000', zIndex: 34}} />}

      {/* ---------- texts */}
      {TEXTS.map((t, i) => (
        <TextCard key={i} spec={t} />
      ))}

      {/* ---------- flashes + letterbox */}
      <Flash at={FLASHES} />
      <Letterbox />

      {/* ---------- audio */}
      <Audio src={staticFile('audio/trailer_music.wav')} volume={musicVolume} />
      {SFX.map((s, i) => (
        <Sequence key={`sfx${i}`} from={s.f}>
          <Audio src={staticFile(`audio/${s.src}.wav`)} volume={lin(s.db)} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
