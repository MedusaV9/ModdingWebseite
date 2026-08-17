import React from 'react';
import type {CSSProperties, PropsWithChildren} from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {noise2D} from '@remotion/noise';

type ShakeWrapperProps = PropsWithChildren<{
  /** Max translation in px. */
  amplitude?: number;
  /** Max rotation in degrees. */
  rotationAmplitude?: number;
  /** Noise speed — higher = more nervous. */
  frequency?: number;
  /** Optional per-frame multiplier (e.g. decay after an impact). */
  envelope?: (frame: number) => number;
  seed?: string;
  style?: CSSProperties;
}>;

/** Smooth camera-shake using coherent noise (deterministic per seed). */
export const ShakeWrapper: React.FC<ShakeWrapperProps> = ({
  children,
  amplitude = 8,
  rotationAmplitude = 0.6,
  frequency = 0.14,
  envelope,
  seed = 'shake',
  style,
}) => {
  const frame = useCurrentFrame();
  const t = frame * frequency;
  const env = envelope ? envelope(frame) : 1;

  const dx = noise2D(`${seed}-x`, t, 0) * amplitude * env;
  const dy = noise2D(`${seed}-y`, t, 0) * amplitude * env;
  const rot = noise2D(`${seed}-r`, t, 0) * rotationAmplitude * env;

  return (
    <AbsoluteFill style={{transform: `translate(${dx}px, ${dy}px) rotate(${rot}deg)`, ...style}}>
      {children}
    </AbsoluteFill>
  );
};
