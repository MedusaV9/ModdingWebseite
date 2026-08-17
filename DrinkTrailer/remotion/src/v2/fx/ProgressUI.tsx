import React from 'react';
import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';

type ProgressUIProps = {
  variant: 'dots' | 'bar' | 'timer';
  /** For 'dots': total dots (scenes) + active index. */
  count?: number;
  activeIndex?: number;
  color?: string;
  accent?: string;
  /** For 'timer': total workout seconds shown counting down. */
  timerTotalSec?: number;
};

const pad = (n: number): string => String(n).padStart(2, '0');

/**
 * Story-style progress UI pinned to the top of the frame:
 * dots (one per scene), a thin fill bar, or a HIIT countdown timer.
 */
export const ProgressUI: React.FC<ProgressUIProps> = ({
  variant,
  count = 5,
  activeIndex = 0,
  color = 'rgba(255,255,255,0.45)',
  accent = '#ffffff',
  timerTotalSec,
}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames, width, height} = useVideoConfig();
  const unit = Math.min(width, height) / 1080;
  const progress = frame / Math.max(1, durationInFrames - 1);

  if (variant === 'bar') {
    return (
      <AbsoluteFill style={{pointerEvents: 'none'}}>
        <div
          style={{
            position: 'absolute',
            top: 24 * unit,
            left: 40 * unit,
            right: 40 * unit,
            height: 8 * unit,
            borderRadius: 4 * unit,
            backgroundColor: color,
            overflow: 'hidden',
          }}
        >
          <div
            style={{
              width: `${progress * 100}%`,
              height: '100%',
              backgroundColor: accent,
              borderRadius: 4 * unit,
            }}
          />
        </div>
      </AbsoluteFill>
    );
  }

  if (variant === 'dots') {
    return (
      <AbsoluteFill style={{pointerEvents: 'none'}}>
        <div
          style={{
            position: 'absolute',
            top: 28 * unit,
            left: 0,
            right: 0,
            display: 'flex',
            justifyContent: 'center',
            gap: 14 * unit,
          }}
        >
          {Array.from({length: count}, (_, i) => (
            <div
              key={i}
              style={{
                width: (i === activeIndex ? 34 : 12) * unit,
                height: 12 * unit,
                borderRadius: 6 * unit,
                backgroundColor: i <= activeIndex ? accent : color,
                transition: 'none',
              }}
            />
          ))}
        </div>
      </AbsoluteFill>
    );
  }

  // variant === 'timer' — HIIT countdown.
  const totalSec = timerTotalSec ?? Math.round(durationInFrames / fps);
  const remaining = Math.max(0, totalSec - frame / fps);
  const sec = Math.floor(remaining);
  const cs = Math.floor((remaining - sec) * 100);
  const urgent = remaining < 5;

  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      <div
        style={{
          position: 'absolute',
          top: 120 * unit,
          left: 0,
          right: 0,
          textAlign: 'center',
          fontFamily: "'DejaVu Sans Mono', 'Courier New', monospace",
          fontWeight: 700,
          fontSize: 96 * unit,
          letterSpacing: '0.04em',
          color: urgent ? accent : '#ffffff',
          textShadow: '0 4px 24px rgba(0,0,0,0.55)',
          transform: urgent && frame % 30 < 15 ? 'scale(1.06)' : 'scale(1)',
        }}
      >
        {pad(Math.floor(sec / 60))}:{pad(sec % 60)}.{pad(cs)}
      </div>
    </AbsoluteFill>
  );
};
