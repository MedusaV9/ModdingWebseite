import React from 'react';
import type {CSSProperties, PropsWithChildren} from 'react';
import {
  AbsoluteFill,
  Easing,
  interpolate,
  random,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

type GlitchZoomProps = PropsWithChildren<{
  /** Defaults to the duration of the surrounding <Sequence>. */
  durationInFrames?: number;
  zoomFrom?: number;
  zoomTo?: number;
  /** 0..1 — strength of jitter and slice displacement. */
  intensity?: number;
  /** Frame (relative to this component) after which the glitch settles. */
  settleAfter?: number;
  /** Number of horizontal displacement slices. */
  sliceCount?: number;
  seed?: string;
  style?: CSSProperties;
}>;

/**
 * Zooms its children while applying a digital glitch: quantized position/scale
 * jitter plus horizontally displaced clip-path slices. Glitch strength fades
 * to zero towards `settleAfter`, leaving a clean zoom.
 */
export const GlitchZoom: React.FC<GlitchZoomProps> = ({
  children,
  durationInFrames,
  zoomFrom = 1,
  zoomTo = 1.12,
  intensity = 1,
  settleAfter,
  sliceCount = 3,
  seed = 'glitch',
  style,
}) => {
  const frame = useCurrentFrame();
  const {durationInFrames: sequenceDuration} = useVideoConfig();
  const duration = durationInFrames ?? sequenceDuration;
  const settle = settleAfter ?? Math.round(duration * 0.55);

  const zoom = interpolate(frame, [0, Math.max(1, duration - 1)], [zoomFrom, zoomTo], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });

  // Glitch envelope: full strength early, fades out over the 12 frames before `settle`.
  const envelope = interpolate(frame, [Math.max(0, settle - 12), settle], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const strength = intensity * envelope;

  // Quantize to 2-frame steps so the jitter looks like digital stutter.
  const step = Math.floor(frame / 2);
  const jx = (random(`${seed}-jx-${step}`) - 0.5) * 34 * strength;
  const jy = (random(`${seed}-jy-${step}`) - 0.5) * 18 * strength;
  const js = 1 + (random(`${seed}-js-${step}`) - 0.5) * 0.1 * strength;

  const slices =
    strength <= 0.01
      ? []
      : new Array(sliceCount).fill(0).map((_, i) => {
          const visible = random(`${seed}-v-${step}-${i}`) < 0.6;
          const top = random(`${seed}-t-${step}-${i}`) * 82;
          const heightPct = 4 + random(`${seed}-h-${step}-${i}`) * 12;
          const offset = (random(`${seed}-o-${step}-${i}`) - 0.5) * 90 * strength;
          return {visible, top, heightPct, offset};
        });

  return (
    <AbsoluteFill style={{overflow: 'hidden', ...style}}>
      <AbsoluteFill style={{transform: `translate(${jx}px, ${jy}px) scale(${zoom * js})`}}>
        {children}
      </AbsoluteFill>
      {slices.map((slice, i) =>
        slice.visible ? (
          <AbsoluteFill
            key={i}
            style={{
              clipPath: `inset(${slice.top}% 0 ${Math.max(0, 100 - slice.top - slice.heightPct)}% 0)`,
              transform: `translate(${jx + slice.offset}px, ${jy}px) scale(${zoom * js})`,
              opacity: 0.9,
            }}
          >
            {children}
          </AbsoluteFill>
        ) : null,
      )}
    </AbsoluteFill>
  );
};
