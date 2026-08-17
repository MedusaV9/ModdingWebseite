import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, random, useCurrentFrame} from 'remotion';

type ShakeCamProps = PropsWithChildren<{
  /** Local frames at which impacts hit. */
  impactFrames: number[];
  /** Peak displacement in px. */
  amplitude?: number;
  /** Exponential decay length in frames. */
  decayFrames?: number;
  /** Ghost copies for pseudo motion blur while shaking hard. */
  motionBlurGhosts?: boolean;
  seed?: number;
}>;

/**
 * Impact camera shake with exponential decay; while the shake is strong,
 * ghost copies trail behind the motion for a pseudo motion blur.
 */
export const ShakeCam: React.FC<ShakeCamProps> = ({
  impactFrames,
  amplitude = 26,
  decayFrames = 12,
  motionBlurGhosts = true,
  seed = 5,
  children,
}) => {
  const frame = useCurrentFrame();

  let dx = 0;
  let dy = 0;
  let energy = 0;
  for (let i = 0; i < impactFrames.length; i++) {
    const t = frame - impactFrames[i];
    if (t < 0) continue;
    const env = Math.exp(-t / decayFrames);
    if (env < 0.02) continue;
    const angle = random(`shake-${seed}-${i}`) * Math.PI * 2;
    const wobble = Math.sin(t * 1.9 + i) * Math.cos(t * 1.3);
    dx += Math.cos(angle) * amplitude * env * wobble;
    dy += Math.sin(angle) * amplitude * env * wobble * 0.7;
    energy = Math.max(energy, env);
  }

  if (energy < 0.02) {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }

  const scale = 1 + energy * 0.03;

  return (
    <AbsoluteFill>
      {motionBlurGhosts && energy > 0.25 ? (
        <>
          <AbsoluteFill
            style={{
              transform: `translate(${dx * 1.7}px, ${dy * 1.7}px) scale(${scale})`,
              opacity: 0.22 * energy,
            }}
          >
            {children}
          </AbsoluteFill>
          <AbsoluteFill
            style={{
              transform: `translate(${dx * 2.6}px, ${dy * 2.6}px) scale(${scale})`,
              opacity: 0.12 * energy,
            }}
          >
            {children}
          </AbsoluteFill>
        </>
      ) : null}
      <AbsoluteFill style={{transform: `translate(${dx}px, ${dy}px) scale(${scale})`}}>
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
