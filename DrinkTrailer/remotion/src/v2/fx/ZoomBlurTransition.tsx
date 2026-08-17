import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';

type ZoomBlurTransitionProps = PropsWithChildren<{
  /** 'in' = crash-zoom from large scale down to 1, 'out' = zoom away. */
  mode?: 'in' | 'out';
  direction?: 'in' | 'out';
  durationInFrames?: number;
  startAt?: number;
  /** Peak zoom factor at the hardest point of the transition. */
  maxScale?: number;
}>;

/**
 * Crash-zoom transition with a radial-blur fake: while the zoom is fast,
 * stacked scaled copies of the content approximate a zoom blur streak.
 */
export const ZoomBlurTransition: React.FC<ZoomBlurTransitionProps> = ({
  mode = 'in',
  direction = 'in',
  durationInFrames = 12,
  startAt = 0,
  maxScale = 1.65,
  children,
}) => {
  const frame = useCurrentFrame();

  // progress 1 → 0 (in) or 0 → 1 (out); 0 = at rest.
  const progress =
    mode === 'in'
      ? interpolate(frame, [0, durationInFrames], [1, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.out(Easing.exp),
        })
      : interpolate(frame, [startAt, startAt + durationInFrames], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.in(Easing.quad),
        });

  if (progress < 0.001) {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }

  const zoomAmount = (maxScale - 1) * progress;
  const scale = direction === 'in' ? 1 + zoomAmount : 1 / (1 + zoomAmount);
  const flash = interpolate(progress, [0.55, 1], [0, 0.35], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Radial blur fake: ghost copies at slightly different scales.
  const ghostSteps = [0.5, 1, 1.6];

  return (
    <AbsoluteFill>
      {ghostSteps.map((step, i) => (
        <AbsoluteFill
          key={i}
          style={{
            transform: `scale(${scale * (1 + zoomAmount * 0.14 * step)})`,
            opacity: 0.22 * progress,
            filter: `blur(${2 + 6 * progress}px)`,
          }}
        >
          {children}
        </AbsoluteFill>
      ))}
      <AbsoluteFill style={{transform: `scale(${scale})`, filter: `blur(${progress * 2}px)`}}>
        {children}
      </AbsoluteFill>
      {flash > 0 ? (
        <AbsoluteFill style={{backgroundColor: '#ffffff', opacity: flash}} />
      ) : null}
    </AbsoluteFill>
  );
};
