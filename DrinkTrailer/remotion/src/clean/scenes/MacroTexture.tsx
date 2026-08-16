/**
 * Scene 6 (bridge → beat 56): macro condensation as a living texture beat.
 * No copy — a clearly perceptible slow push-in, a soft light streak sweeping
 * across the droplets, and two slowly gliding water-drop highlights.
 */
import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';
import {imageSrc} from '../../lib/assets';
import {KenBurnsImage} from '../../shared/motion/KenBurnsImage';
import {colors, gradients} from '../../shared/tokens';
import {SceneFade, easeInOut} from '../motion';
import {SCENE_FADE_FRAMES} from '../timeline';

type MacroTextureProps = {
  durationInFrames: number;
};

/** Soft diagonal light streak sweeping slowly across the frame (screen blend). */
const SheenSweep: React.FC<{durationInFrames: number}> = ({durationInFrames}) => {
  const frame = useCurrentFrame();
  const x = interpolate(frame, [0, Math.max(1, durationInFrames - 1)], [-75, 95], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.sin),
  });
  return (
    <AbsoluteFill style={{overflow: 'hidden', pointerEvents: 'none'}}>
      <div
        style={{
          position: 'absolute',
          top: '-25%',
          left: 0,
          width: '100%',
          height: '150%',
          transform: `translateX(${x}%) rotate(16deg)`,
          background:
            'linear-gradient(90deg, transparent 30%, rgba(255,255,255,0.55) 50%, transparent 70%)',
          mixBlendMode: 'screen',
          opacity: 0.16,
        }}
      />
    </AbsoluteFill>
  );
};

type Glint = {
  /** Position in % of the frame. */
  x: number;
  y: number;
  size: number;
  /** Total downward glide in px over the scene. */
  glide: number;
  delayFraction: number;
};

const GLINTS: Glint[] = [
  {x: 63, y: 30, size: 30, glide: 64, delayFraction: 0.04},
  {x: 27, y: 52, size: 20, glide: 88, delayFraction: 0.3},
];

/** 1–2 slowly gliding highlight glints, reading as light caught in droplets. */
const DropGlints: React.FC<{durationInFrames: number}> = ({durationInFrames}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {GLINTS.map((glint, i) => {
        const start = glint.delayFraction * durationInFrames;
        const local = interpolate(frame, [start, durationInFrames - 1], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        });
        const y = glint.glide * Easing.inOut(Easing.sin)(local);
        const opacity =
          interpolate(local, [0, 0.2, 0.8, 1], [0, 1, 1, 0], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
            easing: Easing.inOut(Easing.sin),
          }) * 0.5;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: `${glint.x}%`,
              top: `${glint.y}%`,
              width: glint.size,
              height: glint.size * 1.35,
              transform: `translateY(${y}px)`,
              borderRadius: '50%',
              background:
                'radial-gradient(ellipse at 40% 30%, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0.35) 45%, transparent 72%)',
              mixBlendMode: 'screen',
              filter: 'blur(1.5px)',
              opacity,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

export const MacroTexture: React.FC<MacroTextureProps> = ({durationInFrames}) => {
  return (
    <SceneFade fadeIn={SCENE_FADE_FRAMES} style={{backgroundColor: colors.ink}}>
      <KenBurnsImage
        src={imageSrc('macroCondensation9x16')}
        from={{scale: 1.02, y: -1.2}}
        to={{scale: 1.24, y: 1.2}}
        durationInFrames={durationInFrames}
        easing={easeInOut}
      />
      <SheenSweep durationInFrames={durationInFrames} />
      <DropGlints durationInFrames={durationInFrames} />
      <AbsoluteFill style={{background: gradients.inkVignette, opacity: 0.22}} />
    </SceneFade>
  );
};
