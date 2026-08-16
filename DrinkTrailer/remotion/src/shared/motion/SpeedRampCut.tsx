import React from 'react';
import type {ReactNode} from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';

export type SpeedSegment = {
  /** Wall-clock frame (relative to this component) where the segment starts. */
  fromFrame: number;
  /** Playback speed from this frame on (1 = realtime, 3 = 3x, 0.2 = slo-mo). */
  speed: number;
};

/**
 * Remaps a wall-clock frame through piecewise-constant speed segments.
 * Returns the "media time" frame to display.
 */
export const remapSpeed = (frame: number, segments: SpeedSegment[]): number => {
  let accumulated = 0;
  for (let i = 0; i < segments.length; i++) {
    const start = segments[i].fromFrame;
    const end = i + 1 < segments.length ? segments[i + 1].fromFrame : Infinity;
    if (frame <= start) break;
    const overlap = Math.min(frame, end) - start;
    if (overlap > 0) accumulated += overlap * segments[i].speed;
  }
  return accumulated;
};

type SpeedRampCutProps = {
  /** Must start with {fromFrame: 0, ...}. Each boundary is treated as a cut. */
  segments: SpeedSegment[];
  /** Render prop receiving the remapped ("media time") frame. */
  children: (remappedFrame: number) => ReactNode;
  /** Show a short flash at every segment boundary (classic speed-ramp cut). */
  flashOnCut?: boolean;
  flashDurationInFrames?: number;
  flashColor?: string;
};

/**
 * Speed-ramp helper: children get a remapped frame that speeds up / slows down
 * according to `segments`, with an optional white flash at each cut point.
 *
 * Example:
 *   <SpeedRampCut segments={[{fromFrame: 0, speed: 3}, {fromFrame: 30, speed: 0.4}]}>
 *     {(f) => <MyFootage frame={f} />}
 *   </SpeedRampCut>
 */
export const SpeedRampCut: React.FC<SpeedRampCutProps> = ({
  segments,
  children,
  flashOnCut = true,
  flashDurationInFrames = 5,
  flashColor = 'rgba(255,255,255,0.85)',
}) => {
  const frame = useCurrentFrame();
  const remapped = remapSpeed(frame, segments);

  let flashOpacity = 0;
  if (flashOnCut) {
    for (const segment of segments.slice(1)) {
      if (frame >= segment.fromFrame && frame < segment.fromFrame + flashDurationInFrames) {
        flashOpacity = interpolate(
          frame,
          [segment.fromFrame, segment.fromFrame + flashDurationInFrames],
          [1, 0],
        );
        break;
      }
    }
  }

  return (
    <AbsoluteFill>
      {children(remapped)}
      {flashOpacity > 0 ? (
        <AbsoluteFill style={{backgroundColor: flashColor, opacity: flashOpacity}} />
      ) : null}
    </AbsoluteFill>
  );
};
