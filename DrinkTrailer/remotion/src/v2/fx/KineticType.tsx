import React from 'react';
import type {CSSProperties} from 'react';
import {Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import type {FontPreset} from '../config/types';
import {fontPair} from '../lib/fonts2';

export type KineticMode = 'slam' | 'lines' | 'tracking';

type KineticTypeProps = {
  /**
   * Text. Accent words: wrap in asterisks ("NO *SUGAR*"). Line breaks for
   * mode 'lines': split on '|' or '\n'.
   */
  text: string;
  mode?: KineticMode;
  fontPreset: FontPreset;
  color: string;
  accentColor: string;
  /** Font size in px (1080-wide frame). Auto-scaled per length if omitted. */
  fontSize?: number;
  /**
   * Local frames at which unit n (word for 'slam', line for 'lines')
   * appears. Missing entries continue the spacing of the last two.
   */
  timing?: number[];
  /** Fallback spacing between units when `timing` is omitted. */
  framesPerUnit?: number;
  align?: 'center' | 'left';
  style?: CSSProperties;
};

type Unit = {content: string; accent: boolean};

const parseAccents = (raw: string): Unit[] =>
  raw
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => {
      const accent = /^\*.*\*$/.test(word);
      return {content: word.replace(/\*/g, ''), accent};
    });

const unitAppearFrame = (index: number, timing: number[] | undefined, spacing: number): number => {
  if (timing && index < timing.length) return timing[index];
  if (timing && timing.length >= 2) {
    const last = timing[timing.length - 1];
    const step = Math.max(1, last - timing[timing.length - 2]);
    return last + step * (index - timing.length + 1);
  }
  if (timing && timing.length === 1) return timing[0] + spacing * index;
  return spacing * index;
};

/**
 * Kinetic typography: word-by-word slams, staggered line reveals, or an
 * Apple-style tracking expand. Timing can be pinned to beat frames.
 */
export const KineticType: React.FC<KineticTypeProps> = ({
  text,
  mode = 'slam',
  fontPreset,
  color,
  accentColor,
  fontSize,
  timing,
  framesPerUnit = 12,
  align = 'center',
  style,
}) => {
  const frame = useCurrentFrame();
  const {fps, width} = useVideoConfig();
  const pair = fontPair(fontPreset);
  const unit = width / 1080;

  const baseStyle: CSSProperties = {
    fontFamily: pair.display,
    letterSpacing: pair.displayTracking,
    textTransform: pair.uppercase ? 'uppercase' : 'none',
    lineHeight: 1.02,
    ...pair.displayStyle,
  };

  if (mode === 'tracking') {
    const clean = text.replace(/\*/g, '');
    const size = (fontSize ?? Math.min(150, 1600 / Math.max(6, clean.length))) * unit;
    const progress = interpolate(frame, [0, 40], [0, 1], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
      easing: Easing.out(Easing.cubic),
    });
    const tracking = interpolate(progress, [0, 1], [0.55, 0.1]);
    return (
      <div
        style={{
          ...baseStyle,
          fontSize: size,
          color,
          letterSpacing: `${tracking}em`,
          opacity: progress,
          textAlign: 'center',
          whiteSpace: 'pre-wrap',
          // Compensate trailing letter-spacing so the block stays centered.
          marginRight: `${-tracking}em`,
          ...style,
        }}
      >
        {clean}
      </div>
    );
  }

  if (mode === 'lines') {
    const lines = text.split(/\||\n/).map((l) => l.trim()).filter(Boolean);
    const size = (fontSize ?? 92) * unit;
    return (
      <div style={{display: 'flex', flexDirection: 'column', gap: 0.28 * size, ...style}}>
        {lines.map((line, i) => {
          const at = unitAppearFrame(i, timing, framesPerUnit);
          const p = spring({frame: frame - at, fps, config: {damping: 16, stiffness: 130}});
          const words = parseAccents(line);
          return (
            <div key={i} style={{overflow: 'hidden'}}>
              <div
                style={{
                  ...baseStyle,
                  fontSize: size,
                  color,
                  textAlign: align,
                  transform: `translateY(${(1 - p) * 110}%)`,
                  opacity: frame >= at ? 1 : 0,
                }}
              >
                {words.map((w, wi) => (
                  <span key={wi} style={{color: w.accent ? accentColor : color}}>
                    {w.content}
                    {wi < words.length - 1 ? ' ' : ''}
                  </span>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    );
  }

  // mode === 'slam'
  const units = parseAccents(text);
  const size = (fontSize ?? Math.min(190, 200 - units.length * 8)) * unit;
  return (
    <div
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        justifyContent: align === 'center' ? 'center' : 'flex-start',
        alignItems: 'baseline',
        columnGap: 0.24 * size,
        rowGap: 0.06 * size,
        textAlign: align,
        ...style,
      }}
    >
      {units.map((w, i) => {
        const at = unitAppearFrame(i, timing, framesPerUnit);
        if (frame < at) return null;
        const p = spring({frame: frame - at, fps, config: {damping: 11, stiffness: 210, mass: 0.7}});
        const scale = 1.65 - 0.65 * p;
        const rot = (i % 2 === 0 ? -1 : 1) * (1 - p) * 5;
        return (
          <span
            key={i}
            style={{
              ...baseStyle,
              display: 'inline-block',
              fontSize: size,
              color: w.accent ? accentColor : color,
              transform: `scale(${scale}) rotate(${rot}deg)`,
              opacity: Math.min(1, p * 2),
              textShadow: w.accent ? `0 0 ${0.35 * size}px ${accentColor}55` : undefined,
            }}
          >
            {w.content}
          </span>
        );
      })}
    </div>
  );
};
