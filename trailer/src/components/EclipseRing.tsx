import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, Easing} from 'remotion';
import {PAL, SPRINGS} from '../lib/util';

export interface EclipseRingTiming {
  /** First frame the endcard layer exists (background starts fading in). */
  mount: number;
  /** Disc/corona reveal (SLAM spring start). */
  reveal: number;
  /** Diamond-ring flash. */
  diamond: number;
  /** Hero title slam. */
  title: number;
  /** Subline fade-in start. */
  subline: number;
  /** 1-frame title glitch. */
  titleGlitch: number;
}

const V1_TIMING: EclipseRingTiming = {
  mount: 1560,
  reveal: 1590,
  diamond: 1608,
  title: 1620,
  subline: 1680,
  titleGlitch: 1770,
};

/**
 * Endcard: eclipse disc + corona + ray crown + hero title.
 * Frames are absolute (component sits at the timeline root and checks its own
 * window); the V2 endcard bar passes its own timing (F1706+).
 */
export const EclipseRing: React.FC<{timing?: EclipseRingTiming}> = ({
  timing = V1_TIMING,
}) => {
  const frame = useCurrentFrame();
  const {mount, reveal, diamond, title, subline, titleGlitch} = timing;
  if (frame < mount) return null;
  const local = frame - reveal;

  // Background fades in so the black-hole ring morphs into the disc instead of
  // being cut off by an opaque fill.
  const bgO = interpolate(frame, [mount, reveal], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const discP = spring({frame: frame - reveal, fps: 60, config: SPRINGS.SLAM});
  const discScale = 0.82 + 0.18 * discP;
  const coronaO = interpolate(frame, [reveal, reveal + 30], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const pulse = 0.85 + 0.15 * Math.sin(frame * 0.21);

  // Diamond-ring flash
  const dr = frame - diamond;
  const diamondO = dr < 0 ? 0 : dr < 4 ? 1 : Math.max(0.35, 1 - (dr - 4) / 20);
  const diamondS = dr < 0 ? 0 : dr < 6 ? 1.6 * (dr / 6) : Math.max(1, 1.6 - (dr - 6) / 12);

  // Title: slam, then tracking expand
  const titleP = spring({frame: frame - title, fps: 60, config: SPRINGS.SLAM});
  const titleScale = 1.55 - 0.55 * titleP;
  const titleBlur = interpolate(titleP, [0, 1], [30, 0]);
  const tracking = interpolate(frame, [title, Math.min(title + 160, 1799)], [0.02, 0.24], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const subO = interpolate(frame, [subline, subline + 30], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const glitched = frame === titleGlitch;

  const rayRot = (local * 8) / 60;
  const rayRot2 = (-local * 5) / 60;

  return (
    <AbsoluteFill style={{zIndex: 25, alignItems: 'center', justifyContent: 'center'}}>
      <AbsoluteFill style={{background: PAL.NIGHT, opacity: bgO}} />
      {/* corona glow layers */}
      <div style={{position: 'absolute', top: '50%', left: '50%', transform: `translate(-50%, -62%) scale(${discScale})`, opacity: coronaO * pulse}}>
        <div style={{position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 760, height: 760, borderRadius: '50%', boxShadow: `0 0 40px 12px ${PAL.CORONA_WHITE}`, opacity: 0.9}} />
        <div style={{position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 820, height: 820, borderRadius: '50%', boxShadow: `0 0 120px 40px ${PAL.GLOW_2}`, opacity: 0.6}} />
        <div style={{position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 980, height: 980, borderRadius: '50%', boxShadow: '0 0 320px 120px rgba(124,58,237,0.35)'}} />
        {/* ray crown */}
        <div
          style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            width: 1400,
            height: 1400,
            transform: `translate(-50%,-50%) rotate(${rayRot}deg)`,
            background: 'repeating-conic-gradient(from 0deg, rgba(196,181,253,.5) 0deg 2deg, transparent 2deg 9deg)',
            WebkitMaskImage: 'radial-gradient(circle, transparent 358px, black 362px, black 470px, transparent 640px)',
            maskImage: 'radial-gradient(circle, transparent 358px, black 362px, black 470px, transparent 640px)',
            borderRadius: '50%',
          }}
        />
        <div
          style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            width: 1400,
            height: 1400,
            transform: `translate(-50%,-50%) rotate(${rayRot2}deg)`,
            background: 'repeating-conic-gradient(from 3deg, rgba(232,180,74,.4) 0deg 1.5deg, transparent 1.5deg 7deg)',
            WebkitMaskImage: 'radial-gradient(circle, transparent 358px, black 364px, black 440px, transparent 600px)',
            maskImage: 'radial-gradient(circle, transparent 358px, black 364px, black 440px, transparent 600px)',
            borderRadius: '50%',
            opacity: 0.5,
          }}
        />
        {/* black disc */}
        <div
          style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%,-50%)',
            width: 720,
            height: 720,
            borderRadius: '50%',
            background: PAL.VOID,
            boxShadow: `inset 0 0 4px 1px ${PAL.CORONA_WHITE}`,
          }}
        />
        {/* diamond ring flash (1 o'clock) */}
        <div
          style={{
            position: 'absolute',
            top: 'calc(50% - 255px)',
            left: 'calc(50% + 255px)',
            width: 90,
            height: 60,
            borderRadius: '50%',
            background: PAL.GOLD_HOT,
            filter: 'blur(10px)',
            mixBlendMode: 'screen',
            opacity: diamondO,
            transform: `scale(${diamondS})`,
          }}
        />
      </div>

      {/* Title block */}
      {/* 61 % + tightened gaps: the legal line has to stay clear of the
          2.35:1 letterbox bar (starts at y=1897 on the 4K canvas). */}
      <div style={{position: 'absolute', top: '61%', left: 0, right: 0, textAlign: 'center'}}>
        <div
          style={{
            fontFamily: "'Bebas Neue', Anton, Impact, sans-serif",
            fontSize: 340,
            lineHeight: 0.9,
            color: PAL.GLOW_1,
            letterSpacing: `${tracking}em`,
            opacity: titleP,
            transform: `scale(${titleScale}) translateX(${glitched ? 18 : 0}px)`,
            filter: `blur(${titleBlur}px)`,
            textShadow: `0 0 12px ${PAL.GLOW_1}, 0 0 48px ${PAL.VIOLET_HOT}, 0 0 160px rgba(139,92,246,0.55)`,
          }}
        >
          PROJECT:{' '}
          <span style={{WebkitTextStroke: `3px ${PAL.GOLD}`, color: PAL.GLOW_1}}>ECLIPSE</span>
        </div>
        <div
          style={{
            marginTop: 36,
            fontFamily: "'Space Grotesk', Inter, sans-serif",
            fontWeight: 500,
            fontSize: 72,
            letterSpacing: '0.12em',
            color: PAL.VIOLET_HOT,
            opacity: subO * 0.85,
            textTransform: 'uppercase',
          }}
        >
          Sieben Tage. Ein Ende.
        </div>
        <div
          style={{
            marginTop: 36,
            fontFamily: 'Inter, system-ui, sans-serif',
            fontWeight: 400,
            fontSize: 34,
            letterSpacing: '0.02em',
            color: 'rgba(156,163,175,0.7)',
            opacity: subO,
          }}
        >
          EIN NEOFORGE-EVENT VON SONIC0810
        </div>
      </div>
    </AbsoluteFill>
  );
};
