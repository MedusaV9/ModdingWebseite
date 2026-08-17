/**
 * Scene 7 (beat 56 → outro): quiet spec-sheet moment on cream — the three
 * exact benefit claims, each with a small flavor-color square, staggered in
 * on consecutive beats (105 BPM ≈ 17 frames).
 */
import React from 'react';
import {AbsoluteFill} from 'remotion';
import {Label} from '../../shared/Typography';
import {colors, flavorAccents} from '../../shared/tokens';
import type {CleanFormat} from '../CleanTrailer';
import {CLAIM_BENEFITS} from '../flavors';
import {RiseIn, SceneFade} from '../motion';
import {SCENE_FADE_FRAMES} from '../timeline';

const BEAT_FRAMES = 17;

type BenefitsRecapProps = {
  format: CleanFormat;
};

export const BenefitsRecap: React.FC<BenefitsRecapProps> = ({format}) => {
  const portrait = format === 'portrait';

  return (
    <SceneFade fadeIn={SCENE_FADE_FRAMES} style={{backgroundColor: colors.cream}}>
      <RiseIn
        delay={6}
        durationInFrames={24}
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
          paddingLeft: portrait ? 0 : 168,
        }}
      >
        <div style={{display: 'flex', flexDirection: 'column', gap: 88}}>
          {CLAIM_BENEFITS.map((claim, i) => (
            <RiseIn key={claim} delay={10 + i * BEAT_FRAMES} durationInFrames={26} distance={28}>
              <div style={{display: 'flex', alignItems: 'center', gap: 40}}>
                <div style={{width: 24, height: 24, backgroundColor: flavorAccents[i]}} />
                <Label color={colors.ink} style={{fontSize: 40, letterSpacing: '0.22em'}}>
                  {claim}
                </Label>
              </div>
            </RiseIn>
          ))}
        </div>
      </AbsoluteFill>
    </SceneFade>
  );
};
