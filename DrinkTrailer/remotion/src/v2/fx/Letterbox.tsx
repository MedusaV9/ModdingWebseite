import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

type LetterboxProps = {
  /**
   * Visible aspect ratio (w/h) of the picture between the bars, e.g. 0.8 for
   * a tighter cinema crop inside 9:16. Ignored when barFraction is set.
   */
  ratio?: number;
  /** Bar height as fraction of the frame (each bar). Default 0.11. */
  barFraction?: number;
  color?: string;
  /** Bars slide in over this many frames (0 = static). */
  enterDurationInFrames?: number;
};

/** Cinema letterbox bars (top + bottom), optionally sliding in. */
export const Letterbox: React.FC<LetterboxProps> = ({
  ratio,
  barFraction = 0.11,
  color = '#000',
  enterDurationInFrames = 0,
}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();

  let fraction = barFraction;
  if (ratio !== undefined && ratio > 0) {
    const visibleH = Math.min(height, width / ratio);
    fraction = Math.max(0, (height - visibleH) / (2 * height));
  }

  const progress =
    enterDurationInFrames > 0
      ? interpolate(frame, [0, enterDurationInFrames], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.out(Easing.cubic),
        })
      : 1;

  const barPct = fraction * 100 * progress;

  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      <div
        style={{position: 'absolute', top: 0, left: 0, right: 0, height: `${barPct}%`, backgroundColor: color}}
      />
      <div
        style={{position: 'absolute', bottom: 0, left: 0, right: 0, height: `${barPct}%`, backgroundColor: color}}
      />
    </AbsoluteFill>
  );
};
