/**
 * Scene 1 (frame 0 → chorus): off-white opening on cream.
 * "Hydration." → "Aber schöner." in fine typography with lots of padding,
 * then a hairline + the exact product claim as a quiet prelude to the reveal.
 */
import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {Headline, Label} from '../../shared/Typography';
import {colors} from '../../shared/tokens';
import type {CleanFormat} from '../CleanTrailer';
import {CLAIM_PRODUCT} from '../flavors';
import {RiseIn, WordReveal, easeOut, useSlowZoom} from '../motion';

type OpeningProps = {
  format: CleanFormat;
  durationInFrames: number;
};

export const Opening: React.FC<OpeningProps> = ({format, durationInFrames}) => {
  const frame = useCurrentFrame();
  const portrait = format === 'portrait';

  // Fade to cream just before the chorus downbeat (the dolly fades in from cream).
  const fadeOut = interpolate(frame, [durationInFrames - 16, durationInFrames - 4], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: easeOut,
  });
  const scale = useSlowZoom(durationInFrames, 1, 1.025);

  const headlineSize = portrait ? 128 : 148;

  return (
    <AbsoluteFill style={{backgroundColor: colors.cream}}>
      <AbsoluteFill style={{opacity: fadeOut}}>
        {/* Tiny brand anchor at the top. */}
        <RiseIn
          delay={8}
          durationInFrames={28}
          distance={16}
          style={{
            position: 'absolute',
            top: portrait ? 208 : 136,
            left: portrait ? 0 : 168,
            width: portrait ? '100%' : undefined,
            textAlign: portrait ? 'center' : 'left',
          }}
        >
          <Label color={colors.ink} style={{fontSize: 30, letterSpacing: '0.42em', opacity: 0.5}}>
            EARLY
          </Label>
        </RiseIn>

        <AbsoluteFill
          style={{
            justifyContent: 'center',
            alignItems: portrait ? 'center' : 'flex-start',
            padding: portrait ? '0 96px' : '0 168px',
            transform: `scale(${scale})`,
            transformOrigin: portrait ? 'center center' : 'left center',
          }}
        >
          <Headline
            color={colors.ink}
            style={{fontSize: headlineSize, textAlign: portrait ? 'center' : 'left'}}
          >
            <WordReveal text="Hydration." startFrame={20} staggerFrames={8} fromY={0.3} />
          </Headline>
          <Headline
            color={colors.ink}
            style={{
              fontSize: headlineSize,
              marginTop: 24,
              textAlign: portrait ? 'center' : 'left',
            }}
          >
            <WordReveal text="Aber schöner." startFrame={137} staggerFrames={9} fromY={0.3} />
          </Headline>

          <RiseIn
            delay={206}
            durationInFrames={26}
            distance={20}
            style={{
              marginTop: 88,
              display: 'flex',
              flexDirection: 'column',
              alignItems: portrait ? 'center' : 'flex-start',
              alignSelf: portrait ? 'center' : 'flex-start',
            }}
          >
            <div style={{width: 88, height: 2, backgroundColor: colors.ink, opacity: 0.25}} />
            <Label
              color={colors.ink}
              style={{fontSize: 26, letterSpacing: '0.34em', opacity: 0.62, marginTop: 32}}
            >
              {CLAIM_PRODUCT}
            </Label>
          </RiseIn>
        </AbsoluteFill>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
