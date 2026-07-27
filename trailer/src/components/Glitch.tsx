import React from 'react';
import {AbsoluteFill} from 'remotion';
import {mulberry32, SEED, PAL} from '../lib/util';

/**
 * Glitch overlay for an active glitch window: horizontal displacement bars +
 * neon scanlines. The real content displacement (jitter) is applied by the
 * parent on the scene wrapper; this adds the visual noise on top.
 */
export const GlitchBars: React.FC<{cutFrame: number; frame: number; strength?: number}> = ({
  cutFrame,
  frame,
  strength = 1,
}) => {
  const t = frame - cutFrame;
  if (t < 0 || t > 9) return null;
  const phase = t <= 3 ? t / 3 : (9 - t) / 6;
  const rng = mulberry32(SEED + cutFrame * 100 + t * 7);
  const slices = Math.round((3 + 6 * phase) * strength);
  const bars: React.ReactNode[] = [];
  for (let i = 0; i < slices; i++) {
    const y = rng() * 2160;
    const h = 60 + rng() * 260;
    const shift = (rng() - 0.5) * 180 * phase * strength;
    const col = rng() < 0.5 ? PAL.GLITCH_R : PAL.GLITCH_C;
    bars.push(
      <div
        key={i}
        style={{
          position: 'absolute',
          top: y,
          left: shift,
          width: '100%',
          height: h,
          background: `linear-gradient(90deg, transparent, ${col}22 30%, transparent 70%)`,
          borderTop: `3px solid ${col}`,
          opacity: 0.6 * phase,
          mixBlendMode: 'screen',
        }}
      />,
    );
  }
  return <AbsoluteFill style={{zIndex: 30}}>{bars}</AbsoluteFill>;
};

/** Deterministic jitter offset for the scene wrapper inside a glitch window. */
export const glitchJitter = (frame: number, cutFrames: number[], strength = 1) => {
  for (const cf of cutFrames) {
    const t = frame - cf;
    if (t >= 0 && t <= 9) {
      const phase = t <= 3 ? t / 3 : (9 - t) / 6;
      const rng = mulberry32(SEED + cf * 71 + t * 13);
      return {
        x: (rng() - 0.5) * 90 * phase * strength,
        y: (rng() - 0.5) * 30 * phase * strength,
        aber: 3 + 15 * phase * strength,
      };
    }
  }
  return {x: 0, y: 0, aber: 3};
};
