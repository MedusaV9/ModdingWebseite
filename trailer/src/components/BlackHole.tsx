import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame, Easing} from 'remotion';
import {PAL} from '../lib/util';

/**
 * Finale overlay: the Einstein ring grows over the (already collapsing) scene
 * while the wrapper spirals into the centre; the disc then hands over to the
 * EclipseRing endcard.
 *
 * Timings are expressed as fractions of the window so the same recipe works for
 * the V1 layout (F1440, 160 F) and the V2 endcard bar (F1688, 64 F).
 */
export const BlackHole: React.FC<{start?: number; dur?: number}> = ({
  start = 1440,
  dur = 160,
}) => {
  const frame = useCurrentFrame();
  if (frame < start || frame >= start + dur) return null;

  /** fraction of the window -> absolute frame */
  const at = (q: number) => start + q * dur;

  const ringO = interpolate(frame, [at(0.19), at(0.44)], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const ringScale = interpolate(frame, [at(0.19), at(0.94)], [0.6, 1.05], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.7, 0, 0.84, 0),
  });
  // conic streak overlay (radial suction streaks)
  const streakRot = interpolate(frame, [at(0.19), at(0.94)], [0, -540], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const streakO = interpolate(
    frame,
    [at(0.19), at(0.5), at(0.84), at(0.94)],
    [0, 0.8, 0.5, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );
  // darkness closing in
  const darkO = interpolate(frame, [at(0.375), at(0.91)], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.in(Easing.cubic),
  });
  const gradRot = ((frame - start) * 30) / 60;

  return (
    <AbsoluteFill style={{zIndex: 24, alignItems: 'center', justifyContent: 'center'}}>
      {/* radial suction streaks */}
      <AbsoluteFill
        style={{
          background:
            'repeating-conic-gradient(from 0deg, rgba(167,139,250,.28) 0deg 1.2deg, transparent 1.2deg 7deg)',
          mixBlendMode: 'screen',
          transform: `rotate(${streakRot}deg) scale(1.5)`,
          opacity: streakO,
        }}
      />
      {/* Einstein ring */}
      <svg
        width={3840}
        height={2160}
        viewBox="0 0 3840 2160"
        style={{position: 'absolute', opacity: ringO, transform: `translateY(-8%) scale(${ringScale})`}}
      >
        <defs>
          <linearGradient id="photonRing" x1="0%" y1="0%" x2="100%" y2="100%" gradientTransform={`rotate(${gradRot} 0.5 0.5)`}>
            <stop offset="0%" stopColor={PAL.GOLD_HOT} />
            <stop offset="50%" stopColor={PAL.GOLD} />
            <stop offset="100%" stopColor={PAL.ECLIPSE_VIOLET} />
          </linearGradient>
        </defs>
        {/* glow copy */}
        <circle cx={1920} cy={1080} r={340} fill="none" stroke="url(#photonRing)" strokeWidth={60} opacity={0.5} filter="blur(40px)" />
        <circle cx={1920} cy={1080} r={340} fill="none" stroke="url(#photonRing)" strokeWidth={22} filter="blur(4px)" />
        {/* lensing arcs */}
        <ellipse cx={1920} cy={860} rx={520} ry={190} fill="none" stroke={PAL.VIOLET_HOT} strokeWidth={10} opacity={0.7 * ringO}
          strokeDasharray={2600} strokeDashoffset={interpolate(frame, [at(0.31), at(0.5)], [2600, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
        <ellipse cx={1920} cy={1300} rx={520} ry={190} fill="none" stroke={PAL.VIOLET_HOT} strokeWidth={10} opacity={0.7 * ringO}
          strokeDasharray={2600} strokeDashoffset={interpolate(frame, [at(0.375), at(0.56)], [-2600, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
        {/* event horizon */}
        <circle cx={1920} cy={1080} r={310} fill={PAL.VOID} />
      </svg>
      {/* closing darkness */}
      <AbsoluteFill
        style={{
          background: 'radial-gradient(circle at 50% 46%, transparent 8%, #000 60%)',
          opacity: darkO,
        }}
      />
    </AbsoluteFill>
  );
};
