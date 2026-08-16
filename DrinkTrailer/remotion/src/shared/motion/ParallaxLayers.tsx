import React from 'react';
import type {CSSProperties, ReactNode} from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

export type ParallaxLayer = {
  element: ReactNode;
  /** 0 = static background, 1 = full drift. Negative values move opposite. */
  depth: number;
};

type ParallaxLayersProps = {
  layers: ParallaxLayer[];
  /** Total horizontal drift in px at depth 1 over the full duration. */
  driftX?: number;
  /** Total vertical drift in px at depth 1 over the full duration. */
  driftY?: number;
  /** Defaults to the duration of the surrounding <Sequence>. */
  durationInFrames?: number;
  easing?: (t: number) => number;
  /** Extra scale per depth unit so drifting layers never reveal edges. */
  overscan?: number;
  style?: CSSProperties;
};

/** Layered drift: each layer moves proportionally to its depth. */
export const ParallaxLayers: React.FC<ParallaxLayersProps> = ({
  layers,
  driftX = 0,
  driftY = 40,
  durationInFrames,
  easing = Easing.inOut(Easing.quad),
  overscan = 0.06,
  style,
}) => {
  const frame = useCurrentFrame();
  const {durationInFrames: sequenceDuration} = useVideoConfig();
  const duration = durationInFrames ?? sequenceDuration;

  // Centered progress −0.5 … +0.5 so the mid-frame is the neutral pose.
  const progress =
    interpolate(frame, [0, Math.max(1, duration - 1)], [0, 1], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
      easing,
    }) - 0.5;

  return (
    <AbsoluteFill style={{overflow: 'hidden', ...style}}>
      {layers.map((layer, i) => {
        const tx = driftX * layer.depth * progress;
        const ty = driftY * layer.depth * progress;
        const scale = 1 + Math.abs(layer.depth) * overscan;
        return (
          <AbsoluteFill
            key={i}
            style={{transform: `translate(${tx}px, ${ty}px) scale(${scale})`}}
          >
            {layer.element}
          </AbsoluteFill>
        );
      })}
    </AbsoluteFill>
  );
};
