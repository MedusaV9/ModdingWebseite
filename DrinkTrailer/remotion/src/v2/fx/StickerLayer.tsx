import React from 'react';
import {AbsoluteFill, random, spring, useCurrentFrame, useVideoConfig} from 'remotion';

type StickerLayerProps = {
  /** Emoji (or short strings) to scatter. */
  stickers: string[];
  /** Total sticker instances (cycles through `stickers`). */
  count?: number;
  seed?: number;
  /** Frame at which the first sticker pops in. */
  startAt?: number;
  /** Frames between consecutive pops. */
  staggerFrames?: number;
  sizePx?: number;
  /** Keep the middle band free for copy (default true). */
  avoidCenter?: boolean;
};

/**
 * Emoji/shape sticker layer: deterministic scatter, spring bounce-in,
 * idle wiggle + float. Stays out of the center copy band and the bottom
 * safe zone by default.
 */
export const StickerLayer: React.FC<StickerLayerProps> = ({
  stickers,
  count = 8,
  seed = 7,
  startAt = 0,
  staggerFrames = 5,
  sizePx = 110,
  avoidCenter = true,
}) => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  const unit = Math.min(width, height) / 1080;

  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {Array.from({length: count}, (_, i) => {
        const r = (salt: number) => random(`sticker-${seed}-${i}-${salt}`);
        const x = 6 + r(0) * 78;
        // Rows: top band (8..30%) or lower band (52..72%) — never bottom 25%.
        let y = 8 + r(1) * 64;
        if (avoidCenter) {
          y = r(1) < 0.5 ? 8 + r(2) * 22 : 52 + r(2) * 20;
        }
        const at = startAt + i * staggerFrames;
        const pop = spring({frame: frame - at, fps, config: {damping: 9, stiffness: 190, mass: 0.6}});
        if (frame < at) return null;
        const baseRot = (r(3) - 0.5) * 34;
        const wiggle = Math.sin((frame - at) / 9 + i * 1.7) * 6;
        const float = Math.sin((frame - at) / 22 + i) * 8 * unit;
        const size = sizePx * (0.7 + r(4) * 0.7) * unit;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: `${x}%`,
              top: `${y}%`,
              fontSize: size,
              transform: `translateY(${float}px) scale(${pop}) rotate(${baseRot + wiggle}deg)`,
              filter: 'drop-shadow(0 6px 14px rgba(0,0,0,0.3))',
            }}
          >
            {stickers[i % stickers.length]}
          </div>
        );
      })}
    </AbsoluteFill>
  );
};
