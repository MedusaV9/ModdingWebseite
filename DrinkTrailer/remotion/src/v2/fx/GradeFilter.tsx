import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, random, useCurrentFrame, useVideoConfig} from 'remotion';
import type {GradePreset, PaletteConfig} from '../config/types';

type GradeFilterProps = PropsWithChildren<{
  preset: GradePreset;
  palette: PaletteConfig;
}>;

const pad = (n: number): string => String(n).padStart(2, '0');

/** VHS corner UI: PLAY marker + running timecode (mono, phosphor green). */
const VhsHud: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  const unit = Math.min(width, height) / 1080;
  const totalSec = Math.floor(frame / fps);
  const tc = `0:${pad(Math.floor(totalSec / 60))}:${pad(totalSec % 60)}`;
  const hudStyle: React.CSSProperties = {
    position: 'absolute',
    fontFamily: "'DejaVu Sans Mono', 'Courier New', monospace",
    fontSize: 34 * unit,
    fontWeight: 700,
    color: 'rgba(235,255,235,0.92)',
    textShadow: '0 0 8px rgba(120,255,160,0.8), 2px 0 0 rgba(255,60,60,0.35)',
    letterSpacing: '0.08em',
  };
  return (
    <>
      <div style={{...hudStyle, top: 54 * unit, left: 54 * unit}}>▶ PLAY</div>
      <div style={{...hudStyle, top: 54 * unit + 46 * unit, left: 54 * unit, fontSize: 27 * unit}}>
        SP {tc}
      </div>
    </>
  );
};

/**
 * LUT-like whole-trailer color grades, built from CSS filters + blend
 * layers. VHS additionally applies tape wobble, chroma fringe, scanlines,
 * a drifting tracking band and a timecode HUD; neon adds a bloom pass
 * (blurred duplicate, screen-blended); bw_accent/noir use a duotone trick
 * (grayscale + accent multiply/screen sandwich).
 */
export const GradeFilter: React.FC<GradeFilterProps> = ({preset, palette, children}) => {
  const frame = useCurrentFrame();

  if (preset === 'none') {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }

  if (preset === 'warm') {
    return (
      <AbsoluteFill>
        <AbsoluteFill
          style={{filter: 'saturate(1.14) contrast(1.06) brightness(1.03) sepia(0.16) hue-rotate(-6deg)'}}
        >
          {children}
        </AbsoluteFill>
        <AbsoluteFill
          style={{
            background: 'linear-gradient(200deg, rgba(255,170,80,0.30) 0%, transparent 55%, rgba(255,110,60,0.18) 100%)',
            mixBlendMode: 'soft-light',
            pointerEvents: 'none',
          }}
        />
      </AbsoluteFill>
    );
  }

  if (preset === 'cool') {
    return (
      <AbsoluteFill>
        <AbsoluteFill style={{filter: 'saturate(1.04) contrast(1.09) brightness(1.01) hue-rotate(7deg)'}}>
          {children}
        </AbsoluteFill>
        <AbsoluteFill
          style={{
            background: 'linear-gradient(180deg, rgba(120,200,255,0.20) 0%, transparent 45%, rgba(40,90,140,0.28) 100%)',
            mixBlendMode: 'soft-light',
            pointerEvents: 'none',
          }}
        />
      </AbsoluteFill>
    );
  }

  if (preset === 'bw_accent') {
    return (
      <AbsoluteFill style={{backgroundColor: '#0a0a0a'}}>
        <AbsoluteFill style={{filter: 'grayscale(1) contrast(1.18) brightness(1.04)'}}>
          {children}
        </AbsoluteFill>
        {/* Duotone: accent multiplies into highlights, deep tone lifts shadows. */}
        <AbsoluteFill
          style={{backgroundColor: palette.accent, mixBlendMode: 'multiply', opacity: 0.34, pointerEvents: 'none'}}
        />
        <AbsoluteFill
          style={{backgroundColor: palette.accent2, mixBlendMode: 'screen', opacity: 0.10, pointerEvents: 'none'}}
        />
      </AbsoluteFill>
    );
  }

  if (preset === 'noir') {
    return (
      <AbsoluteFill style={{backgroundColor: '#000'}}>
        <AbsoluteFill style={{filter: 'grayscale(1) contrast(1.5) brightness(0.97)'}}>
          {children}
        </AbsoluteFill>
        <AbsoluteFill
          style={{backgroundColor: palette.accent, mixBlendMode: 'multiply', opacity: 0.14, pointerEvents: 'none'}}
        />
        <AbsoluteFill
          style={{
            background: 'radial-gradient(115% 85% at 50% 42%, transparent 46%, rgba(0,0,0,0.88) 100%)',
            pointerEvents: 'none',
          }}
        />
      </AbsoluteFill>
    );
  }

  if (preset === 'pastel') {
    return (
      <AbsoluteFill>
        <AbsoluteFill style={{filter: 'saturate(0.84) contrast(0.9) brightness(1.07)'}}>
          {children}
        </AbsoluteFill>
        {/* Milky wash + lifted blacks. */}
        <AbsoluteFill
          style={{backgroundColor: 'rgba(250,243,236,0.14)', pointerEvents: 'none'}}
        />
        <AbsoluteFill
          style={{backgroundColor: 'rgba(70,60,75,0.35)', mixBlendMode: 'lighten', pointerEvents: 'none'}}
        />
      </AbsoluteFill>
    );
  }

  if (preset === 'neon') {
    return (
      <AbsoluteFill style={{backgroundColor: '#05030a'}}>
        <AbsoluteFill style={{filter: 'saturate(1.55) contrast(1.14) brightness(1.02)'}}>
          {children}
        </AbsoluteFill>
        {/* Bloom pass: blurred duplicate, screen-blended. */}
        <AbsoluteFill
          style={{
            filter: 'saturate(2.1) brightness(1.5) blur(22px)',
            mixBlendMode: 'screen',
            opacity: 0.45,
            pointerEvents: 'none',
          }}
        >
          {children}
        </AbsoluteFill>
        <AbsoluteFill
          style={{
            background: `linear-gradient(160deg, ${palette.accent}26 0%, transparent 45%, ${palette.accent2}26 100%)`,
            mixBlendMode: 'screen',
            pointerEvents: 'none',
          }}
        />
      </AbsoluteFill>
    );
  }

  // preset === 'vhs'
  const wobbleY = (random(`vhs-y-${frame}`) - 0.5) * 5;
  const wobbleSkew = (random(`vhs-s-${frame}`) - 0.5) * 0.5;
  const bigJump = random(`vhs-j-${Math.floor(frame / 40)}`) < 0.12;
  const trackingY = ((frame * 0.35) % 130) - 15;
  const fringe = 3.2;

  return (
    <AbsoluteFill style={{backgroundColor: '#050505'}}>
      <AbsoluteFill
        style={{
          transform: `translateY(${wobbleY + (bigJump ? 9 : 0)}px) skewX(${wobbleSkew}deg) scale(1.012)`,
          filter: 'saturate(1.38) contrast(1.1) brightness(1.05)',
        }}
      >
        {children}
      </AbsoluteFill>
      {/* Chroma fringe: hue-shifted ghosts left/right. */}
      <AbsoluteFill
        style={{
          transform: `translate(${-fringe}px, ${wobbleY}px) scale(1.012)`,
          filter: 'saturate(3) hue-rotate(-70deg) brightness(0.9)',
          mixBlendMode: 'screen',
          opacity: 0.28,
        }}
      >
        {children}
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          transform: `translate(${fringe}px, ${wobbleY}px) scale(1.012)`,
          filter: 'saturate(3) hue-rotate(140deg) brightness(0.9)',
          mixBlendMode: 'screen',
          opacity: 0.28,
        }}
      >
        {children}
      </AbsoluteFill>
      {/* Scanlines */}
      <AbsoluteFill
        style={{
          background: 'repeating-linear-gradient(180deg, rgba(0,0,0,0.24) 0px, rgba(0,0,0,0.24) 2px, transparent 2px, transparent 5px)',
          pointerEvents: 'none',
        }}
      />
      {/* Drifting tracking band */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: `${trackingY}%`,
          height: '3.5%',
          background: 'linear-gradient(180deg, transparent, rgba(255,255,255,0.10), transparent)',
          pointerEvents: 'none',
        }}
      />
      {/* Soft CRT vignette */}
      <AbsoluteFill
        style={{
          background: 'radial-gradient(120% 100% at 50% 50%, transparent 62%, rgba(0,0,0,0.5) 100%)',
          pointerEvents: 'none',
        }}
      />
      <VhsHud />
    </AbsoluteFill>
  );
};
