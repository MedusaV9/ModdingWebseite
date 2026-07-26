import React from 'react';
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {COLORS, FONT_FAMILY} from '../theme';

const DOTS = [
  {x: 14, y: 18, s: 26, c: COLORS.pink, d: 0},
  {x: 82, y: 14, s: 34, c: COLORS.teal, d: 4},
  {x: 8, y: 72, s: 42, c: COLORS.yellow, d: 8},
  {x: 90, y: 66, s: 22, c: COLORS.pink, d: 12},
  {x: 26, y: 88, s: 18, c: COLORS.teal, d: 6},
  {x: 68, y: 86, s: 30, c: COLORS.gold, d: 10},
  {x: 44, y: 8, s: 18, c: COLORS.gold, d: 14},
];

/** Titelkarte: Icon federt ein, „GOOBY 5.0“, Pastel-Punkte treiben. */
export const TitleCard: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pop = spring({frame: frame - 6, fps, config: {damping: 10, stiffness: 120, mass: 0.9}});
  const titel = spring({frame: frame - 26, fps, config: {damping: 12, stiffness: 140}});
  const sub = spring({frame: frame - 48, fps, config: {damping: 13, stiffness: 130}});
  const wobble = Math.sin(frame / 14) * 2.4;

  return (
    <AbsoluteFill
      style={{
        backgroundColor: COLORS.cream,
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      {DOTS.map((dot, i) => {
        const ds = spring({frame: frame - dot.d, fps, config: {damping: 12, stiffness: 90}});
        const drift = Math.sin((frame + i * 31) / 42) * 10;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: `${dot.x}%`,
              top: `${dot.y}%`,
              width: dot.s,
              height: dot.s,
              borderRadius: '50%',
              backgroundColor: dot.c,
              opacity: 0.55 * ds,
              transform: `translateY(${drift}px) scale(${ds})`,
            }}
          />
        );
      })}
      <Img
        src={staticFile('img/icon.png')}
        style={{
          width: 380,
          height: 380,
          borderRadius: 84,
          boxShadow: '0 24px 80px rgba(74, 59, 54, 0.3)',
          transform: `scale(${pop}) rotate(${wobble}deg)`,
        }}
      />
      <div
        style={{
          fontFamily: FONT_FAMILY,
          fontWeight: 800,
          fontSize: 150,
          color: COLORS.brown,
          marginTop: 30,
          letterSpacing: 6,
          transform: `scale(${Math.max(titel, 0.001)})`,
          textShadow: '0 6px 0 rgba(255, 123, 169, 0.35)',
        }}
      >
        GOOBY 5.0
      </div>
      <div
        style={{
          fontFamily: FONT_FAMILY,
          fontWeight: 700,
          fontSize: 52,
          color: COLORS.white,
          backgroundColor: COLORS.pink,
          borderRadius: 999,
          padding: '10px 44px 14px',
          marginTop: 18,
          transform: `scale(${Math.max(sub, 0.001)})`,
          boxShadow: '0 10px 30px rgba(224, 95, 141, 0.4)',
        }}
      >
        Das Godot-Engine-Update
      </div>
    </AbsoluteFill>
  );
};
