import React from 'react';
import type {CSSProperties, PropsWithChildren} from 'react';
import {AbsoluteFill, Freeze, OffthreadVideo, useCurrentFrame} from 'remotion';

export type SpeedSegment2 = {
  /** Local frame at which this segment starts (first must be 0). */
  fromFrame: number;
  /** Playback speed from here on (1 = realtime, 3 = 3x, 0.25 = slo-mo). */
  speed: number;
};

/** Piecewise-constant speed remap: wall-clock frame → media frame. */
export const remapSpeed2 = (frame: number, segments: SpeedSegment2[]): number => {
  let acc = 0;
  for (let i = 0; i < segments.length; i++) {
    const start = segments[i].fromFrame;
    const end = i + 1 < segments.length ? segments[i + 1].fromFrame : Infinity;
    if (frame <= start) break;
    const overlap = Math.min(frame, end) - start;
    if (overlap > 0) acc += overlap * segments[i].speed;
  }
  return acc;
};

type SpeedRampClipProps = PropsWithChildren<{
  /** Video URL (e.g. renderSrc2(...)); null shows the fallback. */
  src: string | null;
  segments?: SpeedSegment2[];
  /** Media frame offset before remapping. */
  startFrom?: number;
  /** Loop point: media frames modulo this (for short turntable loops). */
  loopAfterFrames?: number;
  style?: CSSProperties;
  /** Fallback plane background when src is null (children overlay both). */
  fallbackBackground?: string;
}>;

/**
 * Speed-ramped video: each output frame freezes the underlying
 * OffthreadVideo at the remapped media frame, so arbitrary ramps
 * (slow-mo ↔ speed-up) work frame-exactly during rendering.
 */
export const SpeedRampClip: React.FC<SpeedRampClipProps> = ({
  src,
  segments = [{fromFrame: 0, speed: 1}],
  startFrom = 0,
  loopAfterFrames,
  style,
  fallbackBackground = 'linear-gradient(160deg, #E7B7B7 0%, #F2AC8F 55%, #CBD97A 120%)',
  children,
}) => {
  const frame = useCurrentFrame();

  if (!src) {
    return (
      <AbsoluteFill
        style={{background: fallbackBackground, justifyContent: 'center', alignItems: 'center', ...style}}
      >
        {children}
      </AbsoluteFill>
    );
  }

  let mediaFrame = startFrom + remapSpeed2(frame, segments);
  if (loopAfterFrames && loopAfterFrames > 0) {
    mediaFrame = mediaFrame % loopAfterFrames;
  }

  return (
    <AbsoluteFill style={style}>
      <Freeze frame={Math.floor(mediaFrame)}>
        <OffthreadVideo
          src={src}
          muted
          style={{width: '100%', height: '100%', objectFit: 'cover'}}
        />
      </Freeze>
      {children}
    </AbsoluteFill>
  );
};
