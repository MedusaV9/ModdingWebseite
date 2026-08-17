import React, {useId} from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';

export type GrainIntensity = 'subtle' | 'film' | 'heavy';

type GrainProProps = {
  intensity?: GrainIntensity;
  /** Override the preset opacity. */
  opacity?: number;
  /** New noise pattern every N frames (2 ≈ 30Hz shimmer at 60fps). */
  refreshEveryNFrames?: number;
};

const PRESETS: Record<GrainIntensity, {opacity: number; baseFrequency: number}> = {
  subtle: {opacity: 0.045, baseFrequency: 0.9},
  film: {opacity: 0.09, baseFrequency: 0.75},
  heavy: {opacity: 0.17, baseFrequency: 0.55},
};

/** Animated film grain (SVG feTurbulence, reseeded), with intensity presets. */
export const GrainPro: React.FC<GrainProProps> = ({
  intensity = 'film',
  opacity,
  refreshEveryNFrames = 2,
}) => {
  const frame = useCurrentFrame();
  const reactId = useId();
  const preset = PRESETS[intensity];
  const seed = Math.floor(frame / refreshEveryNFrames);
  const filterId = `grain2-${reactId}-${seed}`;

  return (
    <AbsoluteFill
      style={{pointerEvents: 'none', mixBlendMode: 'overlay', opacity: opacity ?? preset.opacity}}
    >
      <svg width="100%" height="100%">
        <filter id={filterId}>
          <feTurbulence
            type="fractalNoise"
            baseFrequency={preset.baseFrequency}
            numOctaves={2}
            seed={seed}
            stitchTiles="stitch"
          />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width="100%" height="100%" filter={`url(#${filterId})`} />
      </svg>
    </AbsoluteFill>
  );
};
