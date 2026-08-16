/**
 * Scene 8 (outro marker → end): lineup finale + quiet CTA.
 * Portrait: 9:16 lineup photo settling out of a slow zoom, claim + URL +
 * handle over a strong bottom scrim, above the bottom safe zone.
 * Landscape: type left on cream, the Blender trio render as a card right —
 * consistent with the chapter design language.
 */
import React from 'react';
import {AbsoluteFill} from 'remotion';
import {imageSrc} from '../../lib/assets';
import {Body, Headline, Label} from '../../shared/Typography';
import {KenBurnsImage} from '../../shared/motion/KenBurnsImage';
import {colors} from '../../shared/tokens';
import type {CleanFormat} from '../CleanTrailer';
import {CLAIM_HYDRATION, CTA_HANDLE, CTA_URL, TRIO_STILL_16X9, stillSrc} from '../flavors';
import {RiseIn, SceneFade, easeOut} from '../motion';
import {SCENE_FADE_FRAMES} from '../timeline';

type LineupOutroProps = {
  format: CleanFormat;
  durationInFrames: number;
};

const textShadow = '0 4px 28px rgba(42, 42, 42, 0.45)';

/** Local scrim that starts higher than the shared token — the CTA block sits
 * above the bottom 20% safe zone, so it needs contrast further up. */
const portraitScrim = 'linear-gradient(180deg, transparent 34%, rgba(42, 42, 42, 0.88) 94%)';

export const LineupOutro: React.FC<LineupOutroProps> = ({format, durationInFrames}) => {
  const portrait = format === 'portrait';

  if (!portrait) {
    return (
      <SceneFade fadeIn={SCENE_FADE_FRAMES} style={{backgroundColor: colors.cream}}>
        {/* Trio lineup card right. */}
        <div
          style={{
            position: 'absolute',
            left: 760,
            top: 248,
            width: 1040,
            height: 584,
            borderRadius: 28,
            overflow: 'hidden',
            boxShadow: '0 24px 80px rgba(42, 42, 42, 0.10)',
          }}
        >
          <KenBurnsImage
            src={stillSrc(TRIO_STILL_16X9)}
            from={{scale: 1.1}}
            to={{scale: 1.02}}
            durationInFrames={durationInFrames}
            easing={easeOut}
          />
        </div>
        {/* Quiet CTA block left. */}
        <div
          style={{
            position: 'absolute',
            left: 120,
            top: 0,
            width: 600,
            height: 1080,
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'center',
            alignItems: 'flex-start',
          }}
        >
          <RiseIn delay={12} durationInFrames={26} distance={20}>
            <Label color={colors.ink} style={{fontSize: 26, letterSpacing: '0.3em', opacity: 0.7}}>
              {CLAIM_HYDRATION}
            </Label>
          </RiseIn>
          <RiseIn delay={26} durationInFrames={26} distance={24}>
            <Headline color={colors.ink} style={{fontSize: 72, marginTop: 40}}>
              {CTA_URL}
            </Headline>
          </RiseIn>
          <RiseIn delay={40} durationInFrames={26} distance={16}>
            <Body color={colors.ink} weight={500} style={{fontSize: 24, marginTop: 28, opacity: 0.6}}>
              {CTA_HANDLE}
            </Body>
          </RiseIn>
        </div>
      </SceneFade>
    );
  }

  return (
    <SceneFade fadeIn={SCENE_FADE_FRAMES} style={{backgroundColor: colors.cream}}>
      <KenBurnsImage
        src={imageSrc('lineup9x16')}
        from={{scale: 1.12, y: -1}}
        to={{scale: 1.03, y: -1.8}}
        durationInFrames={durationInFrames}
        easing={easeOut}
      />
      <AbsoluteFill style={{background: portraitScrim}} />
      {/* CTA block ends above y=1504 — the bottom 20% (384 px) stays fully free. */}
      <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 416}}>
        <RiseIn delay={12} durationInFrames={26} distance={20} style={{textAlign: 'center'}}>
          <Label
            color={colors.cream}
            style={{fontSize: 28, letterSpacing: '0.32em', opacity: 0.92, textShadow}}
          >
            {CLAIM_HYDRATION}
          </Label>
        </RiseIn>
        <RiseIn delay={26} durationInFrames={26} distance={24} style={{textAlign: 'center'}}>
          <Headline color={colors.cream} style={{fontSize: 88, marginTop: 32, textShadow}}>
            {CTA_URL}
          </Headline>
        </RiseIn>
        <RiseIn delay={40} durationInFrames={26} distance={16} style={{textAlign: 'center'}}>
          <Body
            color={colors.cream}
            weight={500}
            style={{fontSize: 26, marginTop: 24, opacity: 0.78, textShadow}}
          >
            {CTA_HANDLE}
          </Body>
        </RiseIn>
      </AbsoluteFill>
    </SceneFade>
  );
};
