import React from 'react';
import '@fontsource/bebas-neue';
import '@fontsource/anton';
import '@fontsource/space-grotesk/500.css';
import '@fontsource/space-grotesk/700.css';
import '@fontsource/jetbrains-mono/500.css';
import {AbsoluteFill, Sequence, interpolate, useCurrentFrame, Easing} from 'remotion';
import {CLIPS, clipDuration} from './lib/clips';
import type {ClipSpec} from './lib/clips';
import {TEXTS} from './lib/texts';
import {ACT, ENDCARD, FLASHES, GLITCH_CUTS, WHIP} from './lib/timings';
import {shake, idleWobble} from './lib/util';
import {Clip} from './components/Clip';
import {
  Letterbox,
  GradeOverlay,
  GoldAccent,
  Vignette,
  Grain,
  Flash,
} from './components/Overlays';
import {GlitchBars, glitchJitter} from './components/Glitch';
import {Debris} from './components/Debris';
import {TextCard} from './components/TextCard';
import {EclipseRing} from './components/EclipseRing';
import {BlackHole} from './components/BlackHole';
import {TrailerAudio} from './audio/TrailerAudio';

/** 2 Frames Schwarz direkt vor den beiden Impacts ("Atem anhalten"). */
const BLACK_STINGERS = [ACT.I_TO_II, ACT.II_A_TO_II_B];
const isHardBlack = (f: number) => BLACK_STINGERS.some((b) => f >= b - 2 && f < b);

/** Szenen mit Gold-Grade-Akzent (aktuell nur V04). */
const GOLD_SCENES: ClipSpec[] = CLIPS.filter((c) => c.gold);

export const EclipseTrailer: React.FC = () => {
  const frame = useCurrentFrame();

  // ---- master scene transform (wobble + shakes + glitch jitter + whip + suction)
  const wob = idleWobble(frame);
  let sx = wob.x;
  let sy = wob.y;
  let rot = 0;

  for (const c of CLIPS) {
    if (c.shakeAmp && frame >= c.cutIn) {
      const sh = shake(frame, c.cutIn, c.shakeAmp);
      sx += sh.x;
      sy += sh.y;
      rot += sh.rot;
    }
  }

  const jit = glitchJitter(frame, GLITCH_CUTS);
  sx += jit.x;
  sy += jit.y;

  // Whip-Pan-Fake V07 -> V08
  let whipX = 0;
  if (frame >= WHIP.from && frame < WHIP.to) {
    whipX =
      frame < WHIP.mid
        ? interpolate(frame, [WHIP.from, WHIP.mid], [0, -900], {
            easing: Easing.in(Easing.cubic),
          })
        : interpolate(frame, [WHIP.mid, WHIP.to], [700, 0], {
            easing: Easing.out(Easing.cubic),
          });
  }

  // Radialer Sog ab dem Endcard-Downbeat (F1688)
  let suckScale = 1;
  let suckRot = 0;
  if (frame >= ENDCARD.suckFrom) {
    const p = interpolate(frame, [ENDCARD.suckFrom, ENDCARD.suckTo], [0, 1], {
      extrapolateRight: 'clamp',
      easing: Easing.bezier(0.7, 0, 0.84, 0),
    });
    suckScale = 1 - 0.96 * p;
    suckRot = -320 * p;
  }

  const sceneTransform = `scale(${1.02 * suckScale}) translate(${sx + whipX}px, ${sy}px) rotate(${rot + suckRot}deg)`;

  const debrisOpacity = interpolate(
    frame,
    [0, 200, ACT.I_TO_II, ACT.II_A_TO_II_B, ACT.II_TO_III, ENDCARD.start, ENDCARD.suckTo],
    [0.22, 0.3, 0.5, 0.85, 1, 0.8, 0],
    {extrapolateRight: 'clamp'},
  );

  return (
    <AbsoluteFill style={{backgroundColor: '#030204', overflow: 'hidden'}}>
      {/* ---------- scene stack (11 Gameplay-Clips, Fallback = V1-Still) */}
      <AbsoluteFill style={{transform: sceneTransform}}>
        {CLIPS.map((c) => (
          <Sequence
            key={c.id}
            from={c.cutIn}
            durationInFrames={c.id === 'v11' ? ENDCARD.clipFrames : clipDuration(c)}
            name={`${c.id} — ${c.label}`}
          >
            <Clip clip={c} />
          </Sequence>
        ))}
      </AbsoluteFill>

      {/* ---------- debris field */}
      {frame < ENDCARD.suckTo && (
        <Debris opacity={debrisOpacity} pullFrom={ENDCARD.suckFrom} />
      )}

      {/* ---------- grade / vignette / grain */}
      <GradeOverlay />
      {GOLD_SCENES.map((c) => (
        <GoldAccent key={`gold-${c.id}`} from={c.cutIn} to={c.cutOut} />
      ))}
      <Vignette />
      <Grain />

      {/* ---------- black hole -> eclipse ring morph -> endcard */}
      <BlackHole start={ENDCARD.holeFrom} dur={ENDCARD.holeDur} />
      <EclipseRing
        timing={{
          mount: ENDCARD.ringMount,
          reveal: ENDCARD.ringReveal,
          diamond: ENDCARD.diamond,
          title: ENDCARD.title,
          subline: ENDCARD.subline,
          titleGlitch: ENDCARD.titleGlitch,
        }}
      />

      {/* ---------- glitch bars */}
      {GLITCH_CUTS.map((cf) => (
        <GlitchBars key={cf} cutFrame={cf} frame={frame} />
      ))}

      {/* ---------- hard stinger black */}
      {isHardBlack(frame) && <AbsoluteFill style={{background: '#000', zIndex: 34}} />}

      {/* ---------- texts T1-T9 (T10/T11 = Endcard) */}
      {TEXTS.map((t) => (
        <TextCard key={t.id} spec={t} />
      ))}

      {/* ---------- flashes + letterbox */}
      <Flash at={FLASHES} />
      <Letterbox />

      {/* ---------- audio */}
      <TrailerAudio />
    </AbsoluteFill>
  );
};
