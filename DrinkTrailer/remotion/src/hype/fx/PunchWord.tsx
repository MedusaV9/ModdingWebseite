import React from 'react';
import type {CSSProperties} from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {fontFamilies} from '../../shared/fonts';
import {colors} from '../../shared/tokens';

type PunchWordProps = {
  text: string;
  /** Font size in px. */
  size: number;
  color?: string;
  /** Outline-only ghost copy behind the word (adds the brand-edit depth). */
  ghost?: boolean;
  /** Frame (relative to this component) at which the word slams in. */
  startFrame?: number;
  /** Scale the word slams in from. */
  slamFrom?: number;
  /** Slight resting tilt in degrees. */
  tilt?: number;
  style?: CSSProperties;
};

/**
 * Kinetic punch word: slams in oversized on the beat (spring scale-down),
 * with an optional outlined ghost echo scaling the opposite way behind it.
 */
export const PunchWord: React.FC<PunchWordProps> = ({
  text,
  size,
  color = colors.cream,
  ghost = true,
  startFrame = 0,
  slamFrom = 1.9,
  tilt = 0,
  style,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const local = frame - startFrame;

  const p = spring({
    frame: local,
    fps,
    config: {damping: 13, mass: 0.55, stiffness: 210},
  });
  const scale = slamFrom + (1 - slamFrom) * p;
  const opacity = interpolate(local, [0, 2], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const base: CSSProperties = {
    fontFamily: fontFamilies.display,
    fontWeight: 400,
    textTransform: 'uppercase',
    letterSpacing: '0.02em',
    lineHeight: 0.9,
    fontSize: size,
    textAlign: 'center',
    whiteSpace: 'pre-line',
  };

  return (
    <div
      style={{
        position: 'relative',
        display: 'grid',
        placeItems: 'center',
        opacity,
        transform: `rotate(${tilt}deg)`,
        ...style,
      }}
    >
      {ghost ? (
        <div
          style={{
            ...base,
            gridArea: '1 / 1',
            color: 'transparent',
            WebkitTextStroke: `3px ${color}`,
            opacity: 0.4,
            transform: `scale(${scale * 1.12})`,
          }}
        >
          {text}
        </div>
      ) : null}
      <div
        style={{
          ...base,
          gridArea: '1 / 1',
          color,
          textShadow: '0 8px 46px rgba(0,0,0,0.55)',
          transform: `scale(${scale})`,
        }}
      >
        {text}
      </div>
    </div>
  );
};
