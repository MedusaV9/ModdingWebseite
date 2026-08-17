import React, {useId} from 'react';
import type {CSSProperties} from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';

type GrainOverlayProps = {
  opacity?: number;
  /** New noise pattern every N frames (1 = every frame, more filmic = 2). */
  refreshEveryNFrames?: number;
  blendMode?: CSSProperties['mixBlendMode'];
};

/** Animated film-grain overlay (SVG feTurbulence, reseeded over time). */
export const GrainOverlay: React.FC<GrainOverlayProps> = ({
  opacity = 0.07,
  refreshEveryNFrames = 2,
  blendMode = 'overlay',
}) => {
  const frame = useCurrentFrame();
  const reactId = useId();
  const seed = Math.floor(frame / refreshEveryNFrames);
  const filterId = `grain-${reactId}-${seed}`;

  return (
    <AbsoluteFill style={{pointerEvents: 'none', mixBlendMode: blendMode, opacity}}>
      <svg width="100%" height="100%">
        <filter id={filterId}>
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.8"
            numOctaves="2"
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
