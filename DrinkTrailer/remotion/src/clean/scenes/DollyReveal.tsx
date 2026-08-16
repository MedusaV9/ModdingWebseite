/**
 * Scene 2 (chorus → chapter 1): first full product view on the chorus downbeat.
 * Blender dolly renders/early_dolly_peach_16x9.mp4 (2 s @ 24 fps): stretched to
 * 0.6× playback (~3.3 s of motion over the 4.6 s scene). The remaining tail is
 * carried by a continuously accelerating push-in (ease-in scale drift + linear
 * Y drift), so the frame is never static — no visible freeze moment.
 * Landscape shows it full-bleed; portrait crops it elegantly into a
 * letterboxed panel on a cream frame.
 */
import React from 'react';
import {AbsoluteFill, Easing, Freeze, OffthreadVideo, interpolate, useCurrentFrame} from 'remotion';
import {renderSrc} from '../../lib/assets';
import {Label} from '../../shared/Typography';
import {colors} from '../../shared/tokens';
import type {CleanFormat} from '../CleanTrailer';
import {CLAIM_PRODUCT} from '../flavors';
import {RiseIn, easeOut} from '../motion';

const CLIP_RATE = 0.6;
/** Timeline frame at which the (slowed) 2 s clip runs out (0.6 × 98/30 ≈ 1.96 s). */
const CLIP_END_FRAME = 98;

type DollyRevealProps = {
  format: CleanFormat;
  durationInFrames: number;
};

const DollyClip: React.FC<{durationInFrames: number}> = ({durationInFrames}) => {
  const frame = useCurrentFrame();
  const src = renderSrc('dolly_peach_16x9');

  // Push-in that ramps up over the scene: while the clip itself moves, the
  // drift is nearly still; when the clip ends its velocity has taken over and
  // keeps growing gently — there is no frame without motion.
  const progress = interpolate(frame, [0, Math.max(1, durationInFrames - 1)], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const zoom = 1.02 + 0.11 * Easing.in(Easing.quad)(progress);
  const driftY = -12 * progress;

  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <AbsoluteFill style={{transform: `translateY(${driftY}px) scale(${zoom})`}}>
        {src ? (
          <Freeze frame={CLIP_END_FRAME} active={frame >= CLIP_END_FRAME}>
            <OffthreadVideo
              src={src}
              muted
              playbackRate={CLIP_RATE}
              style={{width: '100%', height: '100%', objectFit: 'cover'}}
            />
          </Freeze>
        ) : (
          <AbsoluteFill style={{backgroundColor: colors.rose}} />
        )}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const DollyReveal: React.FC<DollyRevealProps> = ({format, durationInFrames}) => {
  const frame = useCurrentFrame();
  const portrait = format === 'portrait';

  // Fade in from cream right on the chorus downbeat.
  const fadeIn = interpolate(frame, [0, 14], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: easeOut,
  });

  if (!portrait) {
    return (
      <AbsoluteFill style={{backgroundColor: colors.cream}}>
        <AbsoluteFill style={{opacity: fadeIn}}>
          <DollyClip durationInFrames={durationInFrames} />
          <RiseIn
            delay={80}
            durationInFrames={26}
            distance={20}
            style={{position: 'absolute', left: 120, bottom: 112}}
          >
            <div style={{width: 88, height: 2, backgroundColor: colors.ink, opacity: 0.3}} />
            <Label
              color={colors.ink}
              style={{fontSize: 26, letterSpacing: '0.34em', opacity: 0.78, marginTop: 28}}
            >
              {CLAIM_PRODUCT}
            </Label>
          </RiseIn>
        </AbsoluteFill>
      </AbsoluteFill>
    );
  }

  // Portrait: letterboxed panel on the cream frame, bottom ~15% kept free.
  return (
    <AbsoluteFill style={{backgroundColor: colors.cream}}>
      <AbsoluteFill style={{opacity: fadeIn}}>
        <div
          style={{
            position: 'absolute',
            left: 96,
            top: 344,
            width: 888,
            height: 1112,
            borderRadius: 28,
            overflow: 'hidden',
            boxShadow: '0 24px 80px rgba(42, 42, 42, 0.10)',
          }}
        >
          <DollyClip durationInFrames={durationInFrames} />
        </div>
        <RiseIn
          delay={80}
          durationInFrames={26}
          distance={20}
          style={{position: 'absolute', top: 1528, width: '100%', textAlign: 'center'}}
        >
          <Label color={colors.ink} style={{fontSize: 26, letterSpacing: '0.34em', opacity: 0.66}}>
            {CLAIM_PRODUCT}
          </Label>
        </RiseIn>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
