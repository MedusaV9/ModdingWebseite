import React from 'react';
import type {CSSProperties} from 'react';
import {interpolate, random, useCurrentFrame, useVideoConfig} from 'remotion';
import type {FontPreset} from '../config/types';
import {fontPair} from '../lib/fonts2';

type NeonGlowTextProps = {
  text: string;
  /** Tube color (the glow). */
  color: string;
  /** Second tube color for alternating lines (falls back to `color`). */
  altColor?: string;
  fontPreset?: FontPreset;
  fontSize?: number;
  /** Neon sign flicker (seeded dips + startup sputter). */
  flicker?: boolean;
  /** Frame at which the sign "powers on". */
  startAt?: number;
  /** Outline-only look (transparent fill) vs. filled tube core. */
  outlineOnly?: boolean;
  style?: CSSProperties;
};

/**
 * Neon sign typography: layered text-shadow glow, tube-core stroke, seeded
 * power-on sputter and occasional brightness dips. Lines split on '|'.
 */
export const NeonGlowText: React.FC<NeonGlowTextProps> = ({
  text,
  color,
  altColor,
  fontPreset = 'hype',
  fontSize = 150,
  flicker = true,
  startAt = 0,
  outlineOnly = true,
  style,
}) => {
  const frame = useCurrentFrame();
  const {width} = useVideoConfig();
  const unit = width / 1080;
  const pair = fontPair(fontPreset);
  const lines = text.split(/\||\n/).map((l) => l.trim()).filter(Boolean);

  const local = frame - startAt;
  // Power-on sputter: a few hard on/off flashes, then steady.
  let power = local < 0 ? 0 : 1;
  if (flicker && local >= 0 && local < 26) {
    power = random(`neon-boot-${Math.floor(local / 3)}`) < 0.45 ? 0.15 : 1;
  } else if (flicker && local >= 26) {
    const dip = random(`neon-dip-${Math.floor(local / 7)}`);
    power = dip < 0.06 ? 0.55 : 1;
  }

  const appear = interpolate(local, [0, 10], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <div
      style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0.3 * fontSize * unit, ...style}}
    >
      {lines.map((line, i) => {
        const tube = i % 2 === 1 && altColor ? altColor : color;
        const glow = [
          `0 0 ${6 * unit}px #ffffff`,
          `0 0 ${14 * unit}px ${tube}`,
          `0 0 ${34 * unit}px ${tube}`,
          `0 0 ${70 * unit}px ${tube}`,
          `0 0 ${120 * unit}px ${tube}66`,
        ].join(', ');
        return (
          <div
            key={i}
            style={{
              fontFamily: pair.display,
              ...pair.displayStyle,
              textTransform: pair.uppercase ? 'uppercase' : 'none',
              letterSpacing: '0.08em',
              fontSize: fontSize * unit,
              lineHeight: 1.05,
              color: outlineOnly ? 'transparent' : '#ffffff',
              WebkitTextStroke: `${Math.max(2, 3 * unit)}px ${tube}`,
              textShadow: glow,
              opacity: appear * power,
              textAlign: 'center',
            }}
          >
            {line}
          </div>
        );
      })}
    </div>
  );
};
