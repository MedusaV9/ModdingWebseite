import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, random, useCurrentFrame} from 'remotion';

type GlitchStackProps = PropsWithChildren<{
  /** Local frames at which glitch bursts start. */
  burstFrames: number[];
  burstDurationInFrames?: number;
  /** 0..1 — displacement + noise strength. */
  intensity?: number;
  slices?: number;
  seed?: number;
}>;

/**
 * Digital glitch bursts: during a burst window the content is cut into
 * horizontal slices that are displaced sideways, an RGB ghost pair splits
 * off, and noise bars flicker. Outside bursts the content passes through
 * untouched (single render).
 */
export const GlitchStack: React.FC<GlitchStackProps> = ({
  burstFrames,
  burstDurationInFrames = 9,
  intensity = 1,
  slices = 7,
  seed = 1,
  children,
}) => {
  const frame = useCurrentFrame();

  let life = 0;
  for (const start of burstFrames) {
    if (frame >= start && frame < start + burstDurationInFrames) {
      const t = (frame - start) / burstDurationInFrames;
      life = Math.max(life, (1 - t) * intensity);
    }
  }

  if (life <= 0.01) {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }

  const rnd = (i: number, salt: number) => random(`glitch-${seed}-${frame}-${i}-${salt}`);
  const sliceHeight = 100 / slices;
  const rgbShift = 6 * life;

  return (
    <AbsoluteFill style={{backgroundColor: '#000'}}>
      {/* RGB ghost pair */}
      <AbsoluteFill
        style={{
          transform: `translateX(${-rgbShift}px)`,
          opacity: 0.5 * life,
          filter: 'saturate(3) hue-rotate(-60deg)',
          mixBlendMode: 'screen',
        }}
      >
        {children}
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          transform: `translateX(${rgbShift}px)`,
          opacity: 0.5 * life,
          filter: 'saturate(3) hue-rotate(150deg)',
          mixBlendMode: 'screen',
        }}
      >
        {children}
      </AbsoluteFill>
      {/* Displaced slices */}
      {Array.from({length: slices}, (_, i) => {
        const displaced = rnd(i, 0) < 0.55;
        const dx = displaced ? (rnd(i, 1) - 0.5) * 90 * life : 0;
        const top = i * sliceHeight;
        return (
          <AbsoluteFill
            key={i}
            style={{
              clipPath: `inset(${top}% 0 ${100 - top - sliceHeight}% 0)`,
              transform: `translateX(${dx}px)`,
            }}
          >
            {children}
          </AbsoluteFill>
        );
      })}
      {/* Noise bars */}
      {Array.from({length: 3}, (_, i) =>
        rnd(i, 2) < 0.6 ? (
          <div
            key={`bar-${i}`}
            style={{
              position: 'absolute',
              left: 0,
              right: 0,
              top: `${rnd(i, 3) * 92}%`,
              height: `${1 + rnd(i, 4) * 3}%`,
              backgroundColor: rnd(i, 5) < 0.5 ? 'rgba(255,255,255,0.85)' : 'rgba(0,255,230,0.6)',
              opacity: life,
              mixBlendMode: 'exclusion',
            }}
          />
        ) : null,
      )}
    </AbsoluteFill>
  );
};
