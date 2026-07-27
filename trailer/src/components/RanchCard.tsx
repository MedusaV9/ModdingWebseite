import React from 'react';
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {COLORS, FONT_FAMILY} from '../theme';

/**
 * Kapitel-Karte „GOOBY RANCH“: das Key-Artwork (Gooby auf dem Pony vor der
 * Scheune) mit langsamem Push-in, darüber federt das Holzschild-Logo ein,
 * darunter eine Claim-Pill. Markiert die große Wendung des Trailers.
 */
export const RanchCard: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const zoom = interpolate(frame, [0, durationInFrames], [1.04, 1.12], {
    easing: Easing.inOut(Easing.ease),
    extrapolateRight: 'clamp',
  });
  const logo = spring({frame: frame - 4, fps, config: {damping: 11, stiffness: 120, mass: 0.9}});
  const pill = spring({frame: frame - 26, fps, config: {damping: 13, stiffness: 140}});
  const wobble = Math.sin(frame / 15) * 1.6;

  return (
    <AbsoluteFill style={{backgroundColor: COLORS.cream, overflow: 'hidden'}}>
      <AbsoluteFill style={{transform: `scale(${zoom})`}}>
        <Img
          src={staticFile('img/key_artwork_gooby_ranch.webp')}
          style={{width: '100%', height: '100%', objectFit: 'cover'}}
        />
      </AbsoluteFill>
      {/* Leichte Abdunklung unten, damit Logo + Pill sicher lesbar sind. */}
      <AbsoluteFill
        style={{
          background:
            'linear-gradient(180deg, rgba(74,59,54,0.18) 0%, rgba(74,59,54,0) 30%, rgba(74,59,54,0) 62%, rgba(74,59,54,0.30) 100%)',
        }}
      />
      <AbsoluteFill style={{justifyContent: 'flex-start', alignItems: 'center'}}>
        <Img
          src={staticFile('img/logo_gooby_ranch_frei.webp')}
          style={{
            width: 760,
            marginTop: 40,
            transform: `scale(${logo}) rotate(${wobble}deg)`,
            filter: 'drop-shadow(0 18px 44px rgba(74, 59, 54, 0.45))',
          }}
        />
      </AbsoluteFill>
      <div
        style={{
          position: 'absolute',
          bottom: 64,
          left: '50%',
          transform: `translateX(-50%) scale(${Math.max(pill, 0.001)})`,
          fontFamily: FONT_FAMILY,
          fontWeight: 800,
          fontSize: 54,
          color: COLORS.white,
          backgroundColor: COLORS.pink,
          borderRadius: 999,
          padding: '12px 52px 17px',
          boxShadow: '0 12px 40px rgba(224, 95, 141, 0.5)',
          whiteSpace: 'nowrap',
        }}
      >
        Das große neue Kapitel
      </div>
    </AbsoluteFill>
  );
};
