import React, {useId} from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, Easing, interpolate, random, useCurrentFrame} from 'remotion';

export type MaskShape = 'circle' | 'bars' | 'diagonal' | 'can' | 'torn';

type MaskRevealProps = PropsWithChildren<{
  shape?: MaskShape;
  mode?: 'in' | 'out';
  durationInFrames?: number;
  startAt?: number;
  /** Number of bars for shape 'bars'. */
  bars?: number;
  seed?: number;
}>;

/**
 * Masked reveal via SVG clipPath (objectBoundingBox units): expanding
 * circle, staggered bars, diagonal wipe, growing can silhouette, or a
 * torn-paper edge sweeping across.
 */
export const MaskReveal: React.FC<MaskRevealProps> = ({
  shape = 'circle',
  mode = 'in',
  durationInFrames = 16,
  startAt = 0,
  bars = 5,
  seed = 3,
  children,
}) => {
  const frame = useCurrentFrame();
  const reactId = useId();
  const clipId = `mask2-${reactId}`;

  const raw = interpolate(frame, [startAt, startAt + durationInFrames], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.cubic),
  });
  const progress = mode === 'in' ? raw : 1 - raw;

  if (progress >= 0.999) {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }
  if (progress <= 0.001) {
    return null;
  }

  let clipContent: React.ReactNode;
  if (shape === 'circle') {
    // r=0.75 covers the full 9:16 frame from the center.
    clipContent = <circle cx="0.5" cy="0.5" r={progress * 0.78} />;
  } else if (shape === 'bars') {
    const barH = 1 / bars;
    clipContent = (
      <>
        {Array.from({length: bars}, (_, i) => {
          const stagger = i / (bars * 2.2);
          const local = Math.max(0, Math.min(1, (progress * 1.6 - stagger) / 0.8));
          const w = local;
          const fromLeft = i % 2 === 0;
          return (
            <rect
              key={i}
              x={fromLeft ? 0 : 1 - w}
              y={i * barH}
              width={w}
              height={barH + 0.002}
            />
          );
        })}
      </>
    );
  } else if (shape === 'diagonal') {
    // Diagonal wipe: slanted edge sweeps top-left → bottom-right; the
    // revealed region grows from the left until it covers the frame.
    const topX = progress * 1.6;
    const bottomX = progress * 1.6 - 0.6;
    clipContent = <polygon points={`0,0 ${topX},0 ${bottomX},1 0,1`} />;
  } else if (shape === 'can') {
    // Growing can silhouette (rounded slim body + lid/base) from the center.
    // Base geometry in a 0..1 box: body x 0.30..0.70, y 0.06..0.94.
    const s = 0.15 + progress * 2.6;
    const cx = 0.5;
    const cy = 0.5;
    const t = (x: number, y: number) => `${cx + (x - 0.5) * s},${cy + (y - 0.5) * s}`;
    // Approximate the can with a polygon (slim cylinder with chamfered ends).
    const pts = [
      t(0.34, 0.06), t(0.66, 0.06), t(0.70, 0.10), t(0.70, 0.90),
      t(0.66, 0.94), t(0.34, 0.94), t(0.30, 0.90), t(0.30, 0.10),
    ];
    clipContent = <polygon points={pts.join(' ')} />;
  } else {
    // torn: jagged edge sweeping left → right.
    const points: string[] = ['0,0'];
    const steps = 14;
    const edgeX = progress * 1.35 - 0.15;
    for (let i = 0; i <= steps; i++) {
      const y = i / steps;
      const jitter = (random(`torn-${seed}-${i}`) - 0.5) * 0.12;
      points.push(`${Math.max(0, Math.min(1, edgeX + jitter))},${y}`);
    }
    points.push('0,1');
    clipContent = <polygon points={points.join(' ')} />;
  }

  return (
    <AbsoluteFill>
      <svg width="0" height="0" style={{position: 'absolute'}}>
        <defs>
          <clipPath id={clipId} clipPathUnits="objectBoundingBox">
            {clipContent}
          </clipPath>
        </defs>
      </svg>
      <AbsoluteFill style={{clipPath: `url(#${clipId})`}}>{children}</AbsoluteFill>
    </AbsoluteFill>
  );
};
