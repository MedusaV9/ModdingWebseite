import React from 'react';
import type {ReactNode} from 'react';
import {AbsoluteFill, spring, useCurrentFrame, useVideoConfig} from 'remotion';

export type SplitVariant = '2v' | '3v' | '2x2' | '1+2';

type SplitGridProps = {
  cells: ReactNode[];
  /** 2v = two vertical panels, 3v = three, 2x2 = quad, 1+2 = big top + two. */
  variant?: SplitVariant;
  /** Gap between panels in px (1080-wide frame). */
  gapPx?: number;
  /** Frames between consecutive panel slide-ins. */
  staggerFrames?: number;
  startAt?: number;
  background?: string;
};

type Rect = {left: number; top: number; width: number; height: number; fromX: number; fromY: number};

const layout = (variant: SplitVariant): Rect[] => {
  switch (variant) {
    case '2v':
      return [
        {left: 0, top: 0, width: 50, height: 100, fromX: -100, fromY: 0},
        {left: 50, top: 0, width: 50, height: 100, fromX: 100, fromY: 0},
      ];
    case '3v':
      return [
        {left: 0, top: 0, width: 100 / 3, height: 100, fromX: 0, fromY: -100},
        {left: 100 / 3, top: 0, width: 100 / 3, height: 100, fromX: 0, fromY: 100},
        {left: 200 / 3, top: 0, width: 100 / 3, height: 100, fromX: 0, fromY: -100},
      ];
    case '2x2':
      return [
        {left: 0, top: 0, width: 50, height: 50, fromX: -100, fromY: 0},
        {left: 50, top: 0, width: 50, height: 50, fromX: 0, fromY: -100},
        {left: 0, top: 50, width: 50, height: 50, fromX: 0, fromY: 100},
        {left: 50, top: 50, width: 50, height: 50, fromX: 100, fromY: 0},
      ];
    case '1+2':
      return [
        {left: 0, top: 0, width: 100, height: 58, fromX: 0, fromY: -100},
        {left: 0, top: 58, width: 50, height: 42, fromX: -100, fromY: 0},
        {left: 50, top: 58, width: 50, height: 42, fromX: 100, fromY: 0},
      ];
  }
};

/**
 * 2/3/4-panel split layout with staggered directional slide-in reveals.
 * Extra cells beyond the layout are ignored; missing cells stay empty.
 */
export const SplitGrid: React.FC<SplitGridProps> = ({
  cells,
  variant = '2v',
  gapPx = 10,
  staggerFrames = 6,
  startAt = 0,
  background = '#000',
}) => {
  const frame = useCurrentFrame();
  const {fps, width} = useVideoConfig();
  const unit = width / 1080;
  const rects = layout(variant);

  return (
    <AbsoluteFill style={{backgroundColor: background}}>
      {rects.map((rect, i) => {
        if (i >= cells.length) return null;
        const at = startAt + i * staggerFrames;
        const p = spring({frame: frame - at, fps, config: {damping: 15, stiffness: 140}});
        const tx = rect.fromX * (1 - p);
        const ty = rect.fromY * (1 - p);
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: `${rect.left}%`,
              top: `${rect.top}%`,
              width: `${rect.width}%`,
              height: `${rect.height}%`,
              padding: (gapPx / 2) * unit,
              boxSizing: 'border-box',
              opacity: frame >= at ? 1 : 0,
            }}
          >
            <div
              style={{
                width: '100%',
                height: '100%',
                overflow: 'hidden',
                position: 'relative',
                transform: `translate(${tx}%, ${ty}%)`,
              }}
            >
              {cells[i]}
            </div>
          </div>
        );
      })}
    </AbsoluteFill>
  );
};
