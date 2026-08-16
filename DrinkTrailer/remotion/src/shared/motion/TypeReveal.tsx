import React from 'react';
import type {CSSProperties} from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';

type TypeRevealProps = {
  text: string;
  /** Reveal per character or per word. */
  mode?: 'chars' | 'words';
  /** Frames between consecutive units. */
  staggerFrames?: number;
  /** Frame (relative to this component) at which the reveal starts. */
  startFrame?: number;
  /** Vertical offset the units travel from, in em. */
  fromY?: number;
  springConfig?: {damping?: number; mass?: number; stiffness?: number};
  style?: CSSProperties;
};

/** Staggered spring-based text reveal (per char or per word). */
export const TypeReveal: React.FC<TypeRevealProps> = ({
  text,
  mode = 'chars',
  staggerFrames = 2,
  startFrame = 0,
  fromY = 0.6,
  springConfig = {damping: 14, mass: 0.7, stiffness: 130},
  style,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  const units = mode === 'chars' ? text.split('') : text.split(/(\s+)/);

  return (
    <div style={{display: 'inline-block', ...style}}>
      {units.map((unit, i) => {
        const localFrame = frame - startFrame - i * staggerFrames;
        const progress = spring({frame: localFrame, fps, config: springConfig});
        const opacity = interpolate(localFrame, [0, 6], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        });
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              whiteSpace: 'pre',
              opacity,
              transform: `translateY(${(1 - progress) * fromY}em)`,
            }}
          >
            {unit}
          </span>
        );
      })}
    </div>
  );
};
