import React, {useId, useMemo} from 'react';
import type {CSSProperties} from 'react';
import {interpolate, random, useCurrentFrame, useVideoConfig} from 'remotion';
import {colors} from '../tokens';

type BubbleFieldProps = {
  count?: number;
  color?: string;
  /** Overall opacity multiplier for the whole field. */
  opacity?: number;
  minRadius?: number;
  maxRadius?: number;
  /** Frames a bubble needs to rise through the full frame [min, max]. */
  riseDurationRange?: [number, number];
  /** Horizontal wobble amplitude in % of the width. */
  wobbleAmplitude?: number;
  seed?: string;
  style?: CSSProperties;
};

/** Animated SVG carbonation bubbles rising through the frame (looping). */
export const BubbleField: React.FC<BubbleFieldProps> = ({
  count = 26,
  color = colors.cream,
  opacity = 0.5,
  minRadius = 6,
  maxRadius = 26,
  riseDurationRange = [150, 320],
  wobbleAmplitude = 1.6,
  seed = 'bubbles',
  style,
}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const gradientId = useId();

  const bubbles = useMemo(
    () =>
      new Array(count).fill(0).map((_, i) => ({
        x: random(`${seed}-x-${i}`) * 100,
        radius: minRadius + random(`${seed}-r-${i}`) * (maxRadius - minRadius),
        riseDuration:
          riseDurationRange[0] +
          random(`${seed}-d-${i}`) * (riseDurationRange[1] - riseDurationRange[0]),
        phase: random(`${seed}-p-${i}`),
        wobbleFreq: 1.5 + random(`${seed}-w-${i}`) * 3,
      })),
    [count, seed, minRadius, maxRadius, riseDurationRange],
  );

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      style={{position: 'absolute', inset: 0, width: '100%', height: '100%', ...style}}
    >
      <defs>
        <radialGradient id={gradientId} cx="35%" cy="30%" r="70%">
          <stop offset="0%" stopColor="#ffffff" stopOpacity={0.9} />
          <stop offset="55%" stopColor={color} stopOpacity={0.35} />
          <stop offset="100%" stopColor={color} stopOpacity={0} />
        </radialGradient>
      </defs>
      {bubbles.map((bubble, i) => {
        const progress = ((frame / bubble.riseDuration + bubble.phase) % 1 + 1) % 1;
        const wobble =
          Math.sin(progress * Math.PI * 2 * bubble.wobbleFreq + bubble.phase * Math.PI * 2) *
          wobbleAmplitude;
        const cx = ((bubble.x + wobble) / 100) * width;
        const cy = ((105 - progress * 115) / 100) * height;
        const fade =
          interpolate(progress, [0, 0.08, 0.85, 1], [0, 1, 1, 0], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }) * opacity;
        return (
          <circle
            key={i}
            cx={cx}
            cy={cy}
            r={bubble.radius}
            fill={`url(#${gradientId})`}
            stroke={color}
            strokeOpacity={0.35 * fade}
            strokeWidth={2}
            opacity={fade}
          />
        );
      })}
    </svg>
  );
};
