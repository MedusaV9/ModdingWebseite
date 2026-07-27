import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, Easing} from 'remotion';
import type {Shot} from '../lib/shots';

/**
 * Ken-Burns still: pre-upscaled JPEG + pre-blurred bloom copy
 * (screen blend) instead of runtime CSS blur (SwiftShader perf).
 */
export const Still: React.FC<{shot: Shot}> = ({shot}) => {
  const frame = useCurrentFrame(); // relative to sequence start
  const dur = shot.to - shot.from;
  const p = interpolate(frame, [0, dur], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.33, 0, 0.67, 1),
  });
  const scale = shot.scaleFrom + (shot.scaleTo - shot.scaleFrom) * p;
  const tx = (shot.panX ?? 0) * p;
  const ty = (shot.panY ?? 0) * p;
  const rot = (shot.rotate ?? 0) * p;
  const fade = shot.fadeIn
    ? interpolate(frame, [0, shot.fadeIn], [0, 1], {extrapolateRight: 'clamp'})
    : 1;

  const transform = `scale(${scale}) translate(${tx}px, ${ty}px) rotate(${rot}deg)`;

  return (
    <AbsoluteFill style={{opacity: fade, backgroundColor: '#030204'}}>
      <Img
        src={staticFile(`stills/${shot.still}.jpg`)}
        style={{
          position: 'absolute',
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform,
          filter: 'contrast(1.06) saturate(1.06) brightness(1.01)',
        }}
      />
      {/* Fake bloom: pre-blurred copy, screen blend */}
      <Img
        src={staticFile(`stills/${shot.still}_blur.jpg`)}
        style={{
          position: 'absolute',
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform,
          mixBlendMode: 'screen',
          opacity: 0.22,
        }}
      />
    </AbsoluteFill>
  );
};
