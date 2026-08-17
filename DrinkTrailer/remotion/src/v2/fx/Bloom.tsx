import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill} from 'remotion';

type BloomProps = PropsWithChildren<{
  /** Glow strength 0..1 (opacity of the blurred screen pass). */
  intensity?: number;
  /** Blur radius of the glow pass in px. */
  radiusPx?: number;
  /** Extra brightness applied to the glow pass. */
  brightness?: number;
}>;

/**
 * Bloom-ish glow: children render normally plus a blurred, brightened
 * duplicate that is screen-blended on top — highlights bleed softly.
 */
export const Bloom: React.FC<BloomProps> = ({
  intensity = 0.4,
  radiusPx = 26,
  brightness = 1.4,
  children,
}) => (
  <AbsoluteFill>
    <AbsoluteFill>{children}</AbsoluteFill>
    <AbsoluteFill
      style={{
        filter: `blur(${radiusPx}px) brightness(${brightness}) saturate(1.25)`,
        mixBlendMode: 'screen',
        opacity: intensity,
        pointerEvents: 'none',
      }}
    >
      {children}
    </AbsoluteFill>
  </AbsoluteFill>
);
