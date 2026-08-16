import React from 'react';
import type {CSSProperties} from 'react';
import {useVideoConfig} from 'remotion';
import {colors} from '../tokens';

type ProgressDotsProps = {
  total: number;
  /** Index of the active dot (0-based). */
  active: number;
  color?: string;
  inactiveColor?: string;
  /** Dot diameter in px (at 1080p short edge — scales with resolution). */
  size?: number;
  gap?: number;
  style?: CSSProperties;
};

/** Story-style progress indicator: N dots, active one stretched to a pill. */
export const ProgressDots: React.FC<ProgressDotsProps> = ({
  total,
  active,
  color = colors.ink,
  inactiveColor = `${colors.ink}44`,
  size = 14,
  gap = 14,
  style,
}) => {
  const {width, height} = useVideoConfig();
  const unit = Math.min(width, height) / 1080;

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: gap * unit,
        ...style,
      }}
    >
      {new Array(total).fill(0).map((_, i) => {
        const isActive = i === active;
        return (
          <div
            key={i}
            style={{
              width: (isActive ? size * 2.8 : size) * unit,
              height: size * unit,
              borderRadius: size * unit,
              backgroundColor: isActive ? color : inactiveColor,
            }}
          />
        );
      })}
    </div>
  );
};
