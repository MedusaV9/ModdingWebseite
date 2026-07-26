import React from 'react';
import {spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {COLORS, FONT_FAMILY} from '../theme';

/** Spielname-Sticker in der Minispiel-Montage (federt oben rechts rein). */
export const MontageBadge: React.FC<{text: string; accent?: string}> = ({
  text,
  accent = COLORS.teal,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pop = spring({frame: frame - 3, fps, config: {damping: 11, stiffness: 170, mass: 0.6}});
  return (
    <div
      style={{
        position: 'absolute',
        top: 44,
        right: 56,
        transform: `scale(${pop}) rotate(2deg)`,
        fontFamily: FONT_FAMILY,
        fontWeight: 800,
        fontSize: 40,
        color: COLORS.white,
        backgroundColor: accent,
        borderRadius: 999,
        padding: '8px 30px 12px',
        boxShadow: '0 8px 26px rgba(74, 59, 54, 0.3)',
      }}
    >
      {text}
    </div>
  );
};
