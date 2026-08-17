import React, {useId} from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';

type RgbSplitProps = PropsWithChildren<{
  /** Frame (relative to this component) at which the split bursts. */
  startFrame?: number;
  /** Frames until the fringes have fully re-converged. */
  durationInFrames?: number;
  /** Max channel offset in px at the burst peak. */
  maxOffset?: number;
}>;

/**
 * Chromatic-aberration burst: the child is duplicated into a red-only and a
 * cyan-only copy (SVG feColorMatrix), screen-blended over black and pushed
 * apart horizontally. Offset decays to zero over `durationInFrames`, after
 * which the child renders once, untouched. Meant for 6–14 frame drop hits.
 */
export const RgbSplit: React.FC<RgbSplitProps> = ({
  children,
  startFrame = 0,
  durationInFrames = 10,
  maxOffset = 26,
}) => {
  const frame = useCurrentFrame();
  const id = useId();
  const local = frame - startFrame;

  const offset =
    local < 0
      ? 0
      : interpolate(local, [0, durationInFrames], [maxOffset, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        });

  if (offset < 0.75) {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }

  const redId = `rgb-red-${id}`;
  const cyanId = `rgb-cyan-${id}`;

  return (
    <AbsoluteFill style={{backgroundColor: '#000'}}>
      <svg width="0" height="0" style={{position: 'absolute'}}>
        <filter id={redId}>
          <feColorMatrix
            type="matrix"
            values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0"
          />
        </filter>
        <filter id={cyanId}>
          <feColorMatrix
            type="matrix"
            values="0 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0"
          />
        </filter>
      </svg>
      <AbsoluteFill
        style={{
          filter: `url(#${redId})`,
          transform: `translateX(${-offset}px)`,
          mixBlendMode: 'screen',
        }}
      >
        {children}
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          filter: `url(#${cyanId})`,
          transform: `translateX(${offset}px)`,
          mixBlendMode: 'screen',
        }}
      >
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
