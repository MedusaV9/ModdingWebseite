import React from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';

type LightLeakProps = {
  /** Overall strength 0..1. */
  intensity?: number;
  /** Leak colors (two drifting blobs + one streak). */
  colors?: [string, string];
  /** Drift speed multiplier. */
  speed?: number;
  seedOffset?: number;
};

/**
 * Animated light leaks: two large radial-gradient blobs and a diagonal
 * streak drift slowly across the frame, screen-blended — the classic
 * "expired film stock" overlay.
 */
export const LightLeak: React.FC<LightLeakProps> = ({
  intensity = 0.5,
  colors = ['rgba(255,140,66,0.9)', 'rgba(255,80,180,0.75)'],
  speed = 1,
  seedOffset = 0,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = ((frame + seedOffset * 37) / fps) * speed;

  const x1 = 50 + Math.sin(t * 0.45) * 42;
  const y1 = 22 + Math.cos(t * 0.31) * 26;
  const x2 = 50 + Math.cos(t * 0.27 + 2.1) * 46;
  const y2 = 74 + Math.sin(t * 0.38 + 0.7) * 22;
  const streakAngle = 24 + Math.sin(t * 0.2) * 14;
  const streakPos = 30 + Math.sin(t * 0.33 + 1.3) * 35;

  return (
    <AbsoluteFill style={{pointerEvents: 'none', mixBlendMode: 'screen', opacity: intensity}}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(55% 42% at ${x1}% ${y1}%, ${colors[0]} 0%, transparent 70%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(60% 48% at ${x2}% ${y2}%, ${colors[1]} 0%, transparent 72%)`,
          opacity: 0.8,
        }}
      />
      <AbsoluteFill
        style={{
          background: `linear-gradient(${streakAngle}deg, transparent ${streakPos - 9}%, rgba(255,236,200,0.55) ${streakPos}%, transparent ${streakPos + 9}%)`,
          opacity: 0.7,
        }}
      />
    </AbsoluteFill>
  );
};
