import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame, Easing} from 'remotion';
import {PAL} from '../lib/util';

/**
 * S14 finale overlay (F1440-F1590): Einstein ring grows over the credits
 * still while the scene wrapper (handled by parent) spirals into the centre.
 * At F1590 the disc hands over to the EclipseRing endcard.
 */
export const BlackHole: React.FC = () => {
  const frame = useCurrentFrame();
  if (frame < 1440 || frame >= 1600) return null;

  const ringO = interpolate(frame, [1470, 1510], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const ringScale = interpolate(frame, [1470, 1590], [0.6, 1.05], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.7, 0, 0.84, 0),
  });
  // conic streak overlay (radial suction streaks)
  const streakRot = interpolate(frame, [1470, 1590], [0, -540], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const streakO = interpolate(frame, [1470, 1520, 1575, 1590], [0, 0.8, 0.5, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  // darkness closing in
  const darkO = interpolate(frame, [1500, 1585], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.in(Easing.cubic),
  });
  const gradRot = ((frame - 1440) * 30) / 60;

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
          strokeDasharray={2600} strokeDashoffset={interpolate(frame, [1490, 1520], [2600, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
        <ellipse cx={1920} cy={1300} rx={520} ry={190} fill="none" stroke={PAL.VIOLET_HOT} strokeWidth={10} opacity={0.7 * ringO}
          strokeDasharray={2600} strokeDashoffset={interpolate(frame, [1500, 1530], [-2600, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
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
