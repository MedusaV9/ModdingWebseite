import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, Freeze, random, useCurrentFrame} from 'remotion';

type StopMotionHoldProps = PropsWithChildren<{
  /** Frames each pose is held (5 @60fps ≈ 12fps stop-motion look). */
  holdFrames?: number;
  /** Random per-pose offset in px (handheld "misregistered frame" feel). */
  jitterPx?: number;
  /** Random per-pose rotation in degrees. */
  jitterRotationDeg?: number;
  seed?: string;
}>;

/**
 * Frame-quantized playback: children are frozen on every `holdFrames`-th
 * frame (via <Freeze>, so nested Sequences/animations quantize too), plus a
 * small per-pose position/rotation jitter for a handmade stop-motion feel.
 */
export const StopMotionHold: React.FC<StopMotionHoldProps> = ({
  holdFrames = 5,
  jitterPx = 5,
  jitterRotationDeg = 0.5,
  seed = 'stopmo',
  children,
}) => {
  const frame = useCurrentFrame();
  const hold = Math.max(1, Math.round(holdFrames));
  const pose = Math.floor(frame / hold);
  const quantized = pose * hold;

  const dx = (random(`${seed}-x-${pose}`) - 0.5) * 2 * jitterPx;
  const dy = (random(`${seed}-y-${pose}`) - 0.5) * 2 * jitterPx;
  const rot = (random(`${seed}-r-${pose}`) - 0.5) * 2 * jitterRotationDeg;

  return (
    <AbsoluteFill
      style={{transform: `translate(${dx}px, ${dy}px) rotate(${rot}deg) scale(1.015)`}}
    >
      <Freeze frame={quantized}>{children}</Freeze>
    </AbsoluteFill>
  );
};
