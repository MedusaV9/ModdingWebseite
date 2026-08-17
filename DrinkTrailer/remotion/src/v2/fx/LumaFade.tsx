import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';

type LumaFadeProps = PropsWithChildren<{
  mode?: 'in' | 'out';
  durationInFrames?: number;
  startAt?: number;
  /** 'white' = exposure blow-out fade, 'black' = dip-from/to-black. */
  tone?: 'white' | 'black';
}>;

/**
 * Luma fade: the content dissolves through its own brightness — highlights
 * blow out first (tone 'white') or shadows swallow the frame (tone 'black').
 * Approximated with an animated brightness/contrast ramp + opacity, which
 * reads exactly like a film-style exposure fade.
 */
export const LumaFade: React.FC<LumaFadeProps> = ({
  mode = 'in',
  durationInFrames = 16,
  startAt = 0,
  tone = 'white',
  children,
}) => {
  const frame = useCurrentFrame();

  // 1 = fully faded, 0 = fully visible.
  const faded =
    mode === 'in'
      ? interpolate(frame, [0, durationInFrames], [1, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.out(Easing.quad),
        })
      : interpolate(frame, [startAt, startAt + durationInFrames], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.in(Easing.quad),
        });

  if (faded < 0.001) {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }

  const brightness = tone === 'white' ? 1 + faded * 5 : Math.max(0, 1 - faded * 1.15);
  const contrast = 1 + faded * (tone === 'white' ? 1.6 : 0.4);
  const opacity = interpolate(faded, [0.75, 1], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill>
      <AbsoluteFill
        style={{filter: `brightness(${brightness}) contrast(${contrast})`, opacity}}
      >
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
