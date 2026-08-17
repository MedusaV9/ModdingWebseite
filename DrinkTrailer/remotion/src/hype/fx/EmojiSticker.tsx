import React from 'react';
import {interpolate, random, spring, useCurrentFrame, useVideoConfig} from 'remotion';

type EmojiStickerProps = {
  emoji: string;
  /** Position of the sticker center, in % of the frame. */
  x: number;
  y: number;
  size?: number;
  /** Frame (relative to this component) at which the sticker pops in. */
  startFrame?: number;
  /** Static rotation in degrees (wobble is added on top). */
  rotate?: number;
  /** Idle bounce amplitude in px. */
  bounce?: number;
  seed?: string;
};

/**
 * TikTok-style emoji sticker: spring-pops in oversized, then idles with a
 * bouncy float + wobble. Rendered as text (Noto Color Emoji).
 */
export const EmojiSticker: React.FC<EmojiStickerProps> = ({
  emoji,
  x,
  y,
  size = 130,
  startFrame = 0,
  rotate = 0,
  bounce = 14,
  seed = 'sticker',
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const local = frame - startFrame;

  const pop = spring({
    frame: local,
    fps,
    config: {damping: 9, mass: 0.5, stiffness: 200},
  });
  const opacity = interpolate(local, [0, 3], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const phase = random(`${seed}-phase`) * Math.PI * 2;
  const idleY = Math.sin(local * 0.24 + phase) * bounce;
  const wobble = Math.sin(local * 0.17 + phase) * 6;

  return (
    <div
      style={{
        position: 'absolute',
        left: `${x}%`,
        top: `${y}%`,
        fontSize: size,
        lineHeight: 1,
        opacity,
        transform: `translate(-50%, -50%) translateY(${idleY}px) scale(${pop}) rotate(${rotate + wobble}deg)`,
        filter: 'drop-shadow(0 8px 22px rgba(0,0,0,0.35))',
        pointerEvents: 'none',
      }}
    >
      {emoji}
    </div>
  );
};
