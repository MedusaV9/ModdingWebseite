import React from 'react';
import type {CSSProperties} from 'react';
import {AbsoluteFill, Easing, Img, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {fallbackPlane} from '../tokens';

type KenBurnsTransform = {
  scale?: number;
  /** Horizontal pan in % of the image width (positive = right). */
  x?: number;
  /** Vertical pan in % of the image height (positive = down). */
  y?: number;
};

type KenBurnsImageProps = {
  /** staticFile() URL — pass null (e.g. from imageSrc()) to get a fallback plane. */
  src: string | null;
  from?: KenBurnsTransform;
  to?: KenBurnsTransform;
  /** Defaults to the duration of the surrounding <Sequence>. */
  durationInFrames?: number;
  easing?: (t: number) => number;
  style?: CSSProperties;
  imgStyle?: CSSProperties;
  /** Background of the fallback plane when src is null. */
  fallbackBackground?: string;
};

/** Slow zoom/pan on a still image — the workhorse for photo-based scenes. */
export const KenBurnsImage: React.FC<KenBurnsImageProps> = ({
  src,
  from = {scale: 1.05, x: 0, y: 0},
  to = {scale: 1.18, x: 0, y: 0},
  durationInFrames,
  easing = Easing.inOut(Easing.quad),
  style,
  imgStyle,
  fallbackBackground = fallbackPlane,
}) => {
  const frame = useCurrentFrame();
  const {durationInFrames: sequenceDuration} = useVideoConfig();
  const duration = durationInFrames ?? sequenceDuration;

  if (!src) {
    return <AbsoluteFill style={{background: fallbackBackground, ...style}} />;
  }

  const progress = interpolate(frame, [0, Math.max(1, duration - 1)], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing,
  });

  const lerp = (a: number, b: number) => a + (b - a) * progress;
  const scale = lerp(from.scale ?? 1, to.scale ?? 1);
  const x = lerp(from.x ?? 0, to.x ?? 0);
  const y = lerp(from.y ?? 0, to.y ?? 0);

  return (
    <AbsoluteFill style={{overflow: 'hidden', ...style}}>
      <Img
        src={src}
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform: `translate(${x}%, ${y}%) scale(${scale})`,
          transformOrigin: 'center center',
          ...imgStyle,
        }}
      />
    </AbsoluteFill>
  );
};
