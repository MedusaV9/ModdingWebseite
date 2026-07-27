import React, {useRef, useEffect} from 'react';
import {useCurrentFrame} from 'remotion';
import {mulberry32, SEED} from '../lib/util';

interface Particle {
  x0: number;
  y0: number;
  z: number;
  w: number;
  h: number;
  color: string;
  vx: number;
  vy: number;
  rotZ: number;
  wz: number;
  wx: number;
  phi: number;
  alpha: number;
}

const makeParticles = (count: number): Particle[] => {
  const rng = mulberry32(SEED + 4242);
  const colors = ['#1E1433', '#5B21B6', '#8B5CF6', '#E8B44A'];
  const weights = [0.6, 0.85, 0.95, 1.0];
  const out: Particle[] = [];
  for (let i = 0; i < count; i++) {
    const z = 0.35 + rng() * 0.65;
    const size = (8 + rng() * 40) * z;
    const rect = rng() < 0.3;
    const cr = rng();
    let color = colors[3];
    for (let c = 0; c < 4; c++) {
      if (cr <= weights[c]) {
        color = colors[c];
        break;
      }
    }
    out.push({
      x0: rng() * 3840,
      y0: rng() * 2160,
      z,
      w: rect ? size * 2 : size,
      h: size,
      color,
      vx: (rng() - 0.5) * 16,
      vy: -(20 + rng() * 40) * z,
      rotZ: rng() * Math.PI * 2,
      wz: (10 + rng() * 30) * (Math.PI / 180),
      wx: (15 + rng() * 20) * (Math.PI / 180),
      phi: rng() * Math.PI * 2,
      alpha: 0.25 + 0.65 * z,
    });
  }
  return out;
};

const PARTICLES = makeParticles(300);

/**
 * Deterministic block-debris field (canvas 2D, stateless per frame).
 * From F1320 particles accelerate radially into the centre (black hole pull).
 */
export const Debris: React.FC<{opacity?: number; pullFrom?: number}> = ({
  opacity = 1,
  pullFrom = 1320,
}) => {
  const frame = useCurrentFrame();
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, 3840, 2160);
    const tSec = frame / 60;
    const pull = frame > pullFrom ? Math.min(1, (frame - pullFrom) / 60) * 0.9 : 0;
    const cx = 1920;
    const cy = 1080;
    for (const p of PARTICLES) {
      let x = ((p.x0 + p.vx * tSec) % 3840 + 3840) % 3840;
      let y = ((p.y0 + p.vy * tSec) % 2160 + 2160) % 2160;
      if (pull > 0) {
        const s = pull * pull;
        x = x + (cx - x) * s;
        y = y + (cy - y) * s;
      }
      const rot = p.rotZ + p.wz * tSec;
      const squash = Math.abs(Math.cos(p.wx * tSec + p.phi));
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(rot);
      ctx.scale(Math.max(0.08, squash), 1);
      ctx.globalAlpha = p.alpha * opacity;
      ctx.fillStyle = p.color;
      ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
      ctx.restore();
    }
  }, [frame, opacity, pullFrom]);

  return (
    <canvas
      ref={ref}
      width={3840}
      height={2160}
      style={{position: 'absolute', inset: 0, zIndex: 12, pointerEvents: 'none'}}
    />
  );
};
