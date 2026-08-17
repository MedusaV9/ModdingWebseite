import React from 'react';
import type {ReactNode} from 'react';
import {AbsoluteFill, random, spring, useCurrentFrame, useVideoConfig} from 'remotion';

export type CollageItem = {
  node: ReactNode;
  /** Center position, % of frame. Auto-scattered when omitted. */
  x?: number;
  y?: number;
  /** Width, % of frame width. */
  w?: number;
  /** Height, % of frame height (default: square-ish 0.62*w visual). */
  h?: number;
  rotateDeg?: number;
};

type CollageCutoutProps = {
  items: CollageItem[];
  seed?: number;
  /** Frames between consecutive scrap pop-ins. */
  staggerFrames?: number;
  startAt?: number;
  paperColor?: string;
};

/** Torn-edge polygon (objectBoundingBox-like % coords for CSS clip-path). */
const tornEdge = (seed: number): string => {
  const pts: string[] = [];
  const steps = 7;
  for (let i = 0; i <= steps; i++) {
    pts.push(`${(i / steps) * 100}% ${(random(`ct-${seed}-t${i}`) * 4).toFixed(2)}%`);
  }
  for (let i = 0; i <= steps; i++) {
    pts.push(`${(100 - (i / steps) * 100).toFixed(2)}% ${(100 - random(`ct-${seed}-b${i}`) * 4).toFixed(2)}%`);
  }
  return `polygon(${pts.join(', ')})`;
};

/**
 * Paper-scrap collage: items get a white paper border, torn edges
 * (jittered clip-path), drop shadows, random rotation, staggered spring
 * pop-in and a slow idle drift.
 */
export const CollageCutout: React.FC<CollageCutoutProps> = ({
  items,
  seed = 11,
  staggerFrames = 6,
  startAt = 0,
  paperColor = '#faf6ef',
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  return (
    <AbsoluteFill>
      {items.map((item, i) => {
        const r = (salt: number) => random(`collage-${seed}-${i}-${salt}`);
        const x = item.x ?? 18 + r(0) * 64;
        const y = item.y ?? 12 + r(1) * 56;
        const w = item.w ?? 34 + r(2) * 18;
        const h = item.h ?? w * 0.72;
        const rot = item.rotateDeg ?? (r(3) - 0.5) * 22;
        const at = startAt + i * staggerFrames;
        if (frame < at) return null;
        const pop = spring({frame: frame - at, fps, config: {damping: 12, stiffness: 160, mass: 0.8}});
        const drift = Math.sin((frame - at) / 34 + i * 2.1) * 1.1;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: `${x}%`,
              top: `${y}%`,
              width: `${w}%`,
              height: `${h}%`,
              transform: `translate(-50%, -50%) rotate(${rot + drift}deg) scale(${0.6 + 0.4 * pop})`,
              opacity: Math.min(1, pop * 1.6),
              filter: 'drop-shadow(0 18px 30px rgba(0,0,0,0.35))',
            }}
          >
            <div
              style={{
                width: '100%',
                height: '100%',
                backgroundColor: paperColor,
                clipPath: tornEdge(seed * 100 + i),
                padding: '3.5%',
                boxSizing: 'border-box',
              }}
            >
              <div style={{width: '100%', height: '100%', overflow: 'hidden', position: 'relative'}}>
                {item.node}
              </div>
            </div>
          </div>
        );
      })}
    </AbsoluteFill>
  );
};
