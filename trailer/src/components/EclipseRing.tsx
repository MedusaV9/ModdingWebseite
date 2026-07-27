import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, Easing} from 'remotion';
import {PAL, SPRINGS} from '../lib/util';

/**
 * S15 endcard (F1590-F1799): eclipse disc + corona + ray crown + title.
 * Frames are absolute (component mounted at root, checks its own window).
 */
export const EclipseRing: React.FC = () => {
  const frame = useCurrentFrame();
  if (frame < 1560) return null;
  const local = frame - 1590;

  const discP = spring({frame: frame - 1590, fps: 60, config: SPRINGS.SLAM});
  const discScale = 0.82 + 0.18 * discP;
  const coronaO = interpolate(frame, [1590, 1620], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const pulse = 0.85 + 0.15 * Math.sin(frame * 0.21);

  // Diamond-ring flash at F1608
  const dr = frame - 1608;
  const diamondO = dr < 0 ? 0 : dr < 4 ? 1 : Math.max(0.35, 1 - (dr - 4) / 20);
  const diamondS = dr < 0 ? 0 : dr < 6 ? 1.6 * (dr / 6) : Math.max(1, 1.6 - (dr - 6) / 12);

  // Title: slam at F1620, tracking expand afterwards
  const titleP = spring({frame: frame - 1620, fps: 60, config: SPRINGS.SLAM});
  const titleScale = 1.55 - 0.55 * titleP;
  const titleBlur = interpolate(titleP, [0, 1], [30, 0]);
  const tracking = interpolate(frame, [1620, 1780], [0.02, 0.24], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const subO = interpolate(frame, [1680, 1710], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  // 1-frame title glitch at F1770
  const glitched = frame === 1770;

  const rayRot = (local * 8) / 60;
  const rayRot2 = (-local * 5) / 60;

  return (
    <AbsoluteFill style={{background: PAL.NIGHT, zIndex: 25, alignItems: 'center', justifyContent: 'center'}}>
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
      <div style={{position: 'absolute', top: '63%', left: 0, right: 0, textAlign: 'center'}}>
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
          MINECRAFT{' '}
          <span style={{WebkitTextStroke: `3px ${PAL.GOLD}`, color: PAL.GLOW_1}}>ECLIPSE</span>
        </div>
        <div
          style={{
            marginTop: 44,
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
            marginTop: 60,
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
