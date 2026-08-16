import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, spring, useCurrentFrame, useVideoConfig} from 'remotion';

type PunchZoomProps = PropsWithChildren<{
  /** Scale on the very first frame of the cut. */
  from?: number;
  /** Scale the punch settles into. */
  to?: number;
  /** Extra slow drift added after the punch settles (per 100 frames). */
  drift?: number;
  rotateFrom?: number;
  startFrame?: number;
}>;

/**
 * The signature "overedited" punch-in: every cut slams in oversized and
 * springs down to its resting scale within ~8 frames, then keeps drifting.
 */
export const PunchZoom: React.FC<PunchZoomProps> = ({
  children,
  from = 1.28,
  to = 1.06,
  drift = 0.04,
  rotateFrom = 0,
  startFrame = 0,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const local = frame - startFrame;

  const p = spring({
    frame: local,
    fps,
    config: {damping: 16, mass: 0.6, stiffness: 190},
  });
  const scale = from + (to - from) * p + Math.max(0, local) * (drift / 100);
  const rotate = rotateFrom * (1 - p);

  return (
    <AbsoluteFill style={{transform: `scale(${scale}) rotate(${rotate}deg)`, overflow: 'hidden'}}>
      {children}
    </AbsoluteFill>
  );
};
