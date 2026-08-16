/**
 * Clean-style motion primitives: everything is easing-based (no springs with
 * overshoot, no shakes) — slow, controlled, Apple-like movement.
 */
import React from 'react';
import type {CSSProperties, PropsWithChildren} from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';

export const easeOut = Easing.out(Easing.cubic);
export const easeInOut = Easing.inOut(Easing.cubic);
/** Soft "Apple" settle curve — fast start, long gentle landing, no overshoot. */
export const appleEaseOut = Easing.bezier(0.22, 1, 0.36, 1);
/** Smooth symmetric bezier for opacity/drift fades (no linear segments). */
export const appleEaseInOut = Easing.bezier(0.4, 0, 0.2, 1);

type RiseInProps = PropsWithChildren<{
  /** Local frame at which the element starts appearing. */
  delay?: number;
  durationInFrames?: number;
  /** Pixels the element travels up while fading in. */
  distance?: number;
  style?: CSSProperties;
}>;

/** Eased fade + gentle rise — the standard clean text entrance. */
export const RiseIn: React.FC<RiseInProps> = ({
  delay = 0,
  durationInFrames = 24,
  distance = 24,
  style,
  children,
}) => {
  const frame = useCurrentFrame();
  const progress = interpolate(frame, [delay, delay + durationInFrames], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: appleEaseOut,
  });
  return (
    <div
      style={{
        opacity: progress,
        transform: `translateY(${(1 - progress) * distance}px)`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

type WordRevealProps = {
  text: string;
  /** Local frame at which the first word starts appearing. */
  startFrame?: number;
  /** Frames between consecutive words. */
  staggerFrames?: number;
  /** Frames each word takes to fade/drift in. */
  durationInFrames?: number;
  /** Vertical drift distance in em. */
  fromY?: number;
  style?: CSSProperties;
};

/**
 * Per-word text reveal on soft bezier curves (opacity + slight Y drift) —
 * no springs, no linear opacity ramps.
 */
export const WordReveal: React.FC<WordRevealProps> = ({
  text,
  startFrame = 0,
  staggerFrames = 8,
  durationInFrames = 30,
  fromY = 0.32,
  style,
}) => {
  const frame = useCurrentFrame();
  const units = text.split(/(\s+)/);
  let wordIndex = 0;
  return (
    <div style={{display: 'inline-block', ...style}}>
      {units.map((unit, i) => {
        const isWord = unit.trim().length > 0;
        const begin = startFrame + wordIndex * staggerFrames;
        if (isWord) wordIndex++;
        const progress = interpolate(frame, [begin, begin + durationInFrames], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: appleEaseInOut,
        });
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              whiteSpace: 'pre',
              opacity: progress,
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

type WipeRevealProps = PropsWithChildren<{
  /** Color of the sweeping panel (flavor color). */
  color: string;
  /** Local frame at which the panel fully covers the screen (the downbeat). */
  coverFrame: number;
  inFrames?: number;
  outFrames?: number;
}>;

/**
 * Full-screen color-field wipe: a panel sweeps in from the left, fully covers
 * the screen exactly on `coverFrame` (put that on a downbeat), then continues
 * to the right, revealing the children in place behind its trailing edge.
 */
export const WipeReveal: React.FC<WipeRevealProps> = ({
  color,
  coverFrame,
  inFrames = 14,
  outFrames = 20,
  children,
}) => {
  const frame = useCurrentFrame();

  // Panel left edge in % of the viewport width: -105 → 0 (cover) → +105.
  const panelX =
    frame <= coverFrame
      ? interpolate(frame, [coverFrame - inFrames, coverFrame], [-105, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.in(Easing.quad),
        })
      : interpolate(frame, [coverFrame, coverFrame + outFrames], [0, 105], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
          easing: Easing.out(Easing.cubic),
        });

  const wipeDone = frame >= coverFrame + outFrames;
  // Children are revealed left of the panel's trailing edge.
  const visibleRight = Math.max(0, Math.min(100, panelX));

  return (
    <AbsoluteFill>
      <AbsoluteFill
        style={wipeDone ? undefined : {clipPath: `inset(0 ${100 - visibleRight}% 0 0)`}}
      >
        {children}
      </AbsoluteFill>
      {wipeDone ? null : (
        <AbsoluteFill
          style={{backgroundColor: color, transform: `translateX(${panelX}%)`}}
        />
      )}
    </AbsoluteFill>
  );
};

type SceneFadeProps = PropsWithChildren<{
  /** Frames of the eased fade-in at the start of the scene. */
  fadeIn?: number;
  style?: CSSProperties;
}>;

/** Quiet eased crossfade wrapper for scene entrances (macro/benefits/outro). */
export const SceneFade: React.FC<SceneFadeProps> = ({fadeIn = 16, style, children}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, fadeIn], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: easeOut,
  });
  return <AbsoluteFill style={{opacity, ...style}}>{children}</AbsoluteFill>;
};

/** Very slow eased zoom used to keep full scenes gently alive. */
export const useSlowZoom = (
  durationInFrames: number,
  from = 1,
  to = 1.04,
): number => {
  const frame = useCurrentFrame();
  return interpolate(frame, [0, Math.max(1, durationInFrames - 1)], [from, to], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: easeInOut,
  });
};
