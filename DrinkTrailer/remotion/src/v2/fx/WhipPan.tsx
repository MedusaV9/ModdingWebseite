import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';

export type WhipDirection = 'left' | 'right' | 'up' | 'down';

type WhipPanProps = PropsWithChildren<{
  /** 'in' = scene whips into place (start of scene), 'out' = whips away. */
  mode?: 'in' | 'out';
  direction?: WhipDirection;
  durationInFrames?: number;
  /** For mode 'out': local frame at which the whip-out starts. */
  startAt?: number;
  /** Max fake directional blur in px. */
  blurPx?: number;
}>;

const AXIS: Record<WhipDirection, {x: number; y: number}> = {
  left: {x: -1, y: 0},
  right: {x: 1, y: 0},
  up: {x: 0, y: -1},
  down: {x: 0, y: 1},
};

/**
 * Whip-pan transition: the content slams in from (or out to) one side with a
 * directional motion-blur fake (ghost copies offset along the motion axis).
 */
export const WhipPan: React.FC<WhipPanProps> = ({
  mode = 'in',
  direction = 'left',
  durationInFrames = 10,
  startAt = 0,
  blurPx = 26,
  children,
}) => {
  const frame = useCurrentFrame();
  const axis = AXIS[direction];

  const raw =
    mode === 'in'
      ? interpolate(frame, [0, durationInFrames], [1, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.out(Easing.cubic),
        })
      : interpolate(frame, [startAt, startAt + durationInFrames], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.in(Easing.cubic),
        });

  // Offscreen distance: 110% of the travelled axis.
  const tx = axis.x * raw * 110;
  const ty = axis.y * raw * 110;
  const speed = Math.abs(raw) > 0.001 ? Math.min(1, Math.abs(raw) * 2.2) : 0;
  const blur = speed * blurPx;

  if (speed === 0) {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }

  // PERF: ghosts fake the directional smear purely via offset + opacity (no
  // blur filter) — only the main copy pays for a real blur. Blurred ghost
  // copies stack multiplicatively inside glitch/chromatic wrappers and can
  // freeze the software-rendered tab.
  const ghost = (mult: number, opacity: number) => (
    <AbsoluteFill
      style={{
        transform: `translate(${tx + axis.x * blur * mult * 0.12}%, ${ty + axis.y * blur * mult * 0.12}%)`,
        opacity,
      }}
    >
      {children}
    </AbsoluteFill>
  );

  return (
    <AbsoluteFill>
      {ghost(-1.6, 0.25 * speed)}
      {ghost(1.6, 0.25 * speed)}
      <AbsoluteFill
        style={{transform: `translate(${tx}%, ${ty}%)`, filter: `blur(${blur * 0.2}px)`}}
      >
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
