/**
 * Scenes 3–5: one chapter per flavor (Pfirsich / Grapefruit / Zitrone-Minze).
 * Color-field wipe in the flavor color lands exactly on the downbeat, then the
 * chapter is revealed in place: Blender still with a gentle Ken Burns, the
 * flavor name in large sans-serif type and the exact benefits line beneath.
 * Portrait: tone-on-tone inset panel; landscape: type left, product right.
 */
import React from 'react';
import {AbsoluteFill} from 'remotion';
import {Headline, Label} from '../../shared/Typography';
import {GrainOverlay} from '../../shared/motion/GrainOverlay';
import {KenBurnsImage} from '../../shared/motion/KenBurnsImage';
import {ProgressDots} from '../../shared/motion/ProgressDots';
import {colors} from '../../shared/tokens';
import type {CleanFormat} from '../CleanTrailer';
import type {CleanFlavor} from '../flavors';
import {BENEFITS_LINE, BENEFITS_LINES, CLEAN_FLAVORS, stillSrc} from '../flavors';
import {RiseIn, WipeReveal, easeInOut} from '../motion';
import {WIPE_IN_FRAMES, WIPE_OUT_FRAMES} from '../timeline';

type FlavorChapterProps = {
  format: CleanFormat;
  flavor: CleanFlavor;
  index: number;
  durationInFrames: number;
};

export const FlavorChapter: React.FC<FlavorChapterProps> = ({
  format,
  flavor,
  index,
  durationInFrames,
}) => {
  const portrait = format === 'portrait';
  const zoomIn = index % 2 === 0;
  const kenBurns = {
    from: {scale: zoomIn ? 1.04 : 1.12, y: zoomIn ? -0.6 : 0.6},
    to: {scale: zoomIn ? 1.12 : 1.04, y: zoomIn ? 0.6 : -0.6},
  };
  const nameSize = portrait
    ? flavor.name.length > 11
      ? 100
      : 124
    : flavor.name.length > 11
      ? 108
      : 136;
  const textDelay = WIPE_IN_FRAMES + 6;

  return (
    <WipeReveal
      color={flavor.color}
      coverFrame={WIPE_IN_FRAMES}
      inFrames={WIPE_IN_FRAMES}
      outFrames={WIPE_OUT_FRAMES}
    >
      <AbsoluteFill style={{backgroundColor: flavor.color}}>
        {portrait ? (
          <>
            <div
              style={{
                position: 'absolute',
                top: 120,
                width: '100%',
                display: 'flex',
                justifyContent: 'center',
              }}
            >
              <ProgressDots
                total={CLEAN_FLAVORS.length}
                active={index}
                color={colors.ink}
                inactiveColor={`${colors.ink}2E`}
                size={12}
                gap={16}
              />
            </div>
            <div
              style={{
                position: 'absolute',
                left: 96,
                top: 216,
                width: 888,
                height: 1112,
                borderRadius: 28,
                overflow: 'hidden',
                boxShadow: '0 24px 80px rgba(42, 42, 42, 0.12)',
              }}
            >
              <KenBurnsImage
                src={stillSrc(flavor.still9x16)}
                from={kenBurns.from}
                to={kenBurns.to}
                durationInFrames={durationInFrames}
                easing={easeInOut}
              />
            </div>
            <RiseIn
              delay={textDelay}
              durationInFrames={24}
              distance={28}
              style={{position: 'absolute', top: 1392, width: '100%', textAlign: 'center'}}
            >
              <Headline color={colors.ink} style={{fontSize: nameSize, letterSpacing: '-0.01em'}}>
                {flavor.name}
              </Headline>
            </RiseIn>
            <RiseIn
              delay={textDelay + 10}
              durationInFrames={24}
              distance={20}
              style={{position: 'absolute', top: 1560, width: '100%', textAlign: 'center'}}
            >
              <Label color={colors.ink} style={{fontSize: 20, letterSpacing: '0.26em', opacity: 0.72}}>
                {BENEFITS_LINE}
              </Label>
            </RiseIn>
          </>
        ) : (
          <>
            {/* Product right: full-height still half. */}
            <div
              style={{
                position: 'absolute',
                left: 960,
                top: 0,
                width: 960,
                height: 1080,
                overflow: 'hidden',
              }}
            >
              <KenBurnsImage
                src={stillSrc(flavor.still16x9)}
                from={kenBurns.from}
                to={kenBurns.to}
                durationInFrames={durationInFrames}
                easing={easeInOut}
              />
            </div>
            {/* Type left on the generous color field. */}
            <div
              style={{
                position: 'absolute',
                left: 144,
                top: 0,
                width: 720,
                height: 1080,
                display: 'flex',
                flexDirection: 'column',
                justifyContent: 'center',
                alignItems: 'flex-start',
              }}
            >
              <RiseIn delay={textDelay} durationInFrames={24} distance={28}>
                <Headline color={colors.ink} style={{fontSize: nameSize, letterSpacing: '-0.01em'}}>
                  {flavor.name}
                </Headline>
              </RiseIn>
              <RiseIn delay={textDelay + 10} durationInFrames={24} distance={20} style={{marginTop: 48}}>
                {BENEFITS_LINES.map((line) => (
                  <Label
                    key={line}
                    color={colors.ink}
                    style={{fontSize: 22, letterSpacing: '0.26em', opacity: 0.72, lineHeight: 2}}
                  >
                    {line}
                  </Label>
                ))}
              </RiseIn>
            </div>
            <div style={{position: 'absolute', left: 144, bottom: 96}}>
              <ProgressDots
                total={CLEAN_FLAVORS.length}
                active={index}
                color={colors.ink}
                inactiveColor={`${colors.ink}2E`}
                size={12}
                gap={16}
              />
            </div>
          </>
        )}
        {/* Fine animated dither on the flat color field — prevents banding
            after H.264 compression. */}
        <GrainOverlay opacity={0.028} refreshEveryNFrames={2} />
      </AbsoluteFill>
    </WipeReveal>
  );
};
