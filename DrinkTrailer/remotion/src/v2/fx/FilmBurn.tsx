import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';

type FilmBurnProps = {
  /** Local frame at which the burn peaks (typically a scene cut). */
  atFrame: number;
  durationInFrames?: number;
  intensity?: number;
};

/**
 * Film-burn flash: an orange/white blob blows up from one edge around a cut
 * point and dies off — screen-blended over the footage.
 */
export const FilmBurn: React.FC<FilmBurnProps> = ({
  atFrame,
  durationInFrames = 14,
  intensity = 0.85,
}) => {
  const frame = useCurrentFrame();
  const start = atFrame - Math.round(durationInFrames * 0.4);
  const end = start + durationInFrames;
  if (frame < start || frame > end) return null;

  const up = interpolate(frame, [start, atFrame], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.in(Easing.quad),
  });
  const down = interpolate(frame, [atFrame, end], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const life = Math.min(up, down) * intensity;
  const spread = 30 + up * 95;

  return (
    <AbsoluteFill style={{pointerEvents: 'none', mixBlendMode: 'screen'}}>
      <AbsoluteFill
        style={{
          opacity: life,
          background: `radial-gradient(${spread}% ${spread * 0.8}% at 12% 88%,
            #fff6e8 0%, #ffb35c 28%, #ff5c1f 52%, transparent 76%)`,
        }}
      />
      <AbsoluteFill
        style={{
          opacity: life * 0.75,
          background: `radial-gradient(${spread * 0.9}% ${spread * 0.7}% at 92% 6%,
            #ffe9c9 0%, #ff8a3d 40%, transparent 70%)`,
        }}
      />
      <AbsoluteFill style={{opacity: life * 0.5, backgroundColor: '#fff3df'}} />
    </AbsoluteFill>
  );
};
