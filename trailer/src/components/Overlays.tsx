import React, {useMemo} from 'react';
import {AbsoluteFill, interpolate, interpolateColors, useCurrentFrame, Easing} from 'remotion';
import {mulberry32, SEED} from '../lib/util';

/** 2.35:1 letterbox bars (263 px), sliding in during F0-F30. */
export const Letterbox: React.FC = () => {
  const frame = useCurrentFrame();
  const h = interpolate(frame, [0, 30], [0, 263], {
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const bar: React.CSSProperties = {
    position: 'absolute',
    left: 0,
    right: 0,
    height: h,
    background: '#000',
    zIndex: 40,
  };
  return (
    <>
      <div style={{...bar, top: 0}} />
      <div style={{...bar, bottom: 0}} />
    </>
  );
};

/** Global colour grade: cool -> violet -> black/gold (mix-blend color+multiply). */
export const GradeOverlay: React.FC = () => {
  const frame = useCurrentFrame();
  const grade = interpolateColors(
    frame,
    [0, 540, 720, 1320, 1560],
    ['#5A7A9E', '#5A7A9E', '#8B5CF6', '#8B5CF6', '#2A1245'],
  );
  const mult = interpolateColors(
    frame,
    [0, 540, 720, 1320, 1560],
    ['#16222E', '#16222E', '#1E1433', '#1E1433', '#050308'],
  );
  const gradeOpacity = interpolate(frame, [1560, 1620], [0.22, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const multOpacity = interpolate(frame, [1560, 1620], [0.3, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return (
    <>
      <AbsoluteFill style={{background: grade, mixBlendMode: 'color', opacity: gradeOpacity, zIndex: 20}} />
      <AbsoluteFill style={{background: mult, mixBlendMode: 'multiply', opacity: multOpacity, zIndex: 20}} />
      {/* black lift: never fully crushed shadows */}
      <AbsoluteFill style={{background: '#0B0614', mixBlendMode: 'lighten', opacity: 0.5, zIndex: 20}} />
    </>
  );
};

export const Vignette: React.FC = () => {
  const frame = useCurrentFrame();
  const o = interpolate(frame, [0, 1320, 1440], [0.38, 0.38, 0.55], {
    extrapolateRight: 'clamp',
  });
  return (
    <AbsoluteFill
      style={{
        background:
          'radial-gradient(ellipse 72% 62% at 50% 46%, transparent 55%, rgba(3,2,4,0.62) 100%)',
        opacity: o,
        zIndex: 21,
      }}
    />
  );
};

/** Deterministic film grain: 3 pre-generated 1024px tiles cycled every 2 frames. */
export const Grain: React.FC = () => {
  const frame = useCurrentFrame();
  const tiles = useMemo(() => {
    const out: string[] = [];
    for (let t = 0; t < 3; t++) {
      const c = document.createElement('canvas');
      c.width = 512;
      c.height = 512;
      const ctx = c.getContext('2d')!;
      const img = ctx.createImageData(512, 512);
      const rng = mulberry32(SEED + t * 7919);
      for (let i = 0; i < img.data.length; i += 4) {
        const v = 96 + Math.floor(rng() * 64);
        img.data[i] = v;
        img.data[i + 1] = v;
        img.data[i + 2] = v;
        img.data[i + 3] = 255;
      }
      ctx.putImageData(img, 0, 0);
      out.push(c.toDataURL());
    }
    return out;
  }, []);
  const idx = Math.floor(frame / 2) % 3;
  const rng = mulberry32(SEED + Math.floor(frame / 2) * 131);
  const ox = Math.floor(rng() * 512);
  const oy = Math.floor(rng() * 512);
  const opacity = frame >= 1320 ? 0.09 : 0.06;
  return (
    <AbsoluteFill
      style={{
        backgroundImage: `url(${tiles[idx]})`,
        backgroundRepeat: 'repeat',
        backgroundPosition: `${ox}px ${oy}px`,
        mixBlendMode: 'overlay',
        opacity,
        zIndex: 22,
      }}
    />
  );
};

/** 1-frame white flash + short decay used on cuts/impacts. */
export const Flash: React.FC<{at: number[]}> = ({at}) => {
  const frame = useCurrentFrame();
  let o = 0;
  for (const f of at) {
    const t = frame - f;
    if (t === 0) o = Math.max(o, 0.85);
    else if (t === 1) o = Math.max(o, 0.4);
    else if (t === 2) o = Math.max(o, 0.18);
    else if (t === 3) o = Math.max(o, 0.06);
  }
  if (o === 0) return null;
  return <AbsoluteFill style={{background: '#FFF6E9', opacity: o, zIndex: 35}} />;
};
