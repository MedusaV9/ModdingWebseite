import React from 'react';
import type {CSSProperties, PropsWithChildren} from 'react';
import {AbsoluteFill, Loop, OffthreadVideo} from 'remotion';
import {renderSrc} from '../../lib/assets';
import {fallbackPlane} from '../../shared/tokens';

type LoopedClipProps = PropsWithChildren<{
  /** Clip name, resolved via renderSrc() (e.g. "turntable_peach_9x16"). */
  name: string;
  /**
   * Loop length in timeline frames (source length × 30fps):
   * turntable_peach_9x16 = 3s → 90, dolly_peach_16x9 = 2s → 60.
   */
  loopFrames: number;
  style?: CSSProperties;
  videoStyle?: CSSProperties;
}>;

/**
 * Seamlessly loop-wraps a short Blender render (OffthreadVideo inside <Loop>)
 * so it can fill beat segments longer than the source clip. Falls back to the
 * brand gradient plane while the clip does not exist.
 */
export const LoopedClip: React.FC<LoopedClipProps> = ({
  name,
  loopFrames,
  style,
  videoStyle,
  children,
}) => {
  const src = renderSrc(name);
  if (!src) {
    return (
      <AbsoluteFill style={{background: fallbackPlane, ...style}}>{children}</AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill style={{overflow: 'hidden', ...style}}>
      <Loop durationInFrames={loopFrames} layout="absolute-fill">
        <OffthreadVideo
          src={src}
          muted
          style={{width: '100%', height: '100%', objectFit: 'cover', ...videoStyle}}
        />
      </Loop>
      {children}
    </AbsoluteFill>
  );
};
