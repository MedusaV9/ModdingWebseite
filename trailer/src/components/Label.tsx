import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {COLORS, FONT_FAMILY} from '../theme';

/**
 * Untertitel-Pill im GOOBY-Look: federt von unten ein, kleiner Akzentbalken
 * links. `from` = Startframe innerhalb der Sequence, `out` = Frame, ab dem
 * das Label wieder hinausrutscht (optional).
 */
export const Label: React.FC<{
  text: string;
  from?: number;
  out?: number;
  accent?: string;
}> = ({text, from = 8, out, accent = COLORS.pink}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enter = spring({
    frame: frame - from,
    fps,
    config: {damping: 14, stiffness: 160, mass: 0.8},
  });
  const exit =
    out === undefined
      ? 0
      : interpolate(frame, [out, out + 14], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        });
  const y = interpolate(enter, [0, 1], [140, 0]) + exit * 160;
  return (
    <div
      style={{
        position: 'absolute',
        left: 64,
        bottom: 56,
        transform: `translateY(${y}px)`,
        backgroundColor: COLORS.frost,
        borderRadius: 26,
        padding: '18px 36px 20px 30px',
        display: 'flex',
        alignItems: 'center',
        gap: 20,
        boxShadow: '0 10px 36px rgba(74, 59, 54, 0.28)',
      }}
    >
      <div
        style={{
          width: 12,
          height: 46,
          borderRadius: 6,
          backgroundColor: accent,
        }}
      />
      <div
        style={{
          fontFamily: FONT_FAMILY,
          fontWeight: 700,
          fontSize: 44,
          color: COLORS.brown,
          whiteSpace: 'nowrap',
        }}
      >
        {text}
      </div>
    </div>
  );
};
