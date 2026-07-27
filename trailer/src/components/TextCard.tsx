import React from 'react';
import {interpolate, spring, useCurrentFrame} from 'remotion';
import {PAL, SPRINGS, mulberry32, SEED} from '../lib/util';
import type {TextCardSpec} from '../lib/shots';

/**
 * German tagline card: per-letter blur-in stagger (RISE spring) or hard pop.
 * Rendered in absolute frames (component sits at timeline root).
 */
export const TextCard: React.FC<{spec: TextCardSpec}> = ({spec}) => {
  const frame = useCurrentFrame();
  if (frame < spec.inStart - 5 || (spec.outEnd >= 0 && frame > spec.outEnd + 5)) return null;

  const chars = spec.text.split('');
  const color = spec.gold ? PAL.GOLD_HOT : PAL.GLOW_2;
  const size = spec.size ?? 112;
  const yPos = spec.y ?? 0.5;

  // Global out fade
  const outO =
    spec.outEnd < 0
      ? 1
      : interpolate(frame, [spec.outStart, spec.outEnd], [1, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        });

  let inner: React.ReactNode;
  if (spec.pop) {
    const on = frame >= spec.inStart && (spec.outEnd < 0 || frame <= spec.outEnd);
    if (!on) return null;
    let jx = 0;
    let jy = 0;
    if (spec.glitchy) {
      const rng = mulberry32(SEED + Math.floor(frame / 2) * 37);
      jx = (rng() - 0.5) * 14;
      jy = (rng() - 0.5) * 8;
    }
    inner = (
      <div style={{position: 'relative', transform: `translate(${jx}px, ${jy}px)`}}>
        {spec.glitchy && (
          <>
            <div style={{position: 'absolute', inset: 0, color: PAL.GLITCH_R, transform: 'translateX(-5px)', opacity: 0.55}}>{spec.text}</div>
            <div style={{position: 'absolute', inset: 0, color: PAL.GLITCH_C, transform: 'translateX(5px)', opacity: 0.55}}>{spec.text}</div>
          </>
        )}
        <div style={{position: 'relative', color}}>{spec.text}</div>
      </div>
    );
  } else {
    inner = (
      <div>
        {chars.map((ch, i) => {
          const p = spring({
            frame: frame - spec.inStart - i * 2,
            fps: 60,
            config: SPRINGS.RISE,
          });
          const blur = interpolate(p, [0, 1], [18, 0]);
          return (
            <span
              key={i}
              style={{
                display: 'inline-block',
                opacity: p,
                transform: `translateY(${(1 - p) * 46}px)`,
                filter: `blur(${blur}px)`,
                whiteSpace: 'pre',
                color,
              }}
            >
              {ch}
            </span>
          );
        })}
      </div>
    );
  }

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        top: `${yPos * 100}%`,
        transform: 'translateY(-50%)',
        textAlign: 'center',
        fontFamily: "'Space Grotesk', Inter, sans-serif",
        fontWeight: 700,
        fontSize: size,
        letterSpacing: '0.22em',
        textTransform: 'uppercase',
        opacity: outO,
        zIndex: 32,
        textShadow: '0 0 24px rgba(139,92,246,0.55), 0 4px 32px rgba(0,0,0,0.8)',
      }}
    >
      {inner}
    </div>
  );
};
