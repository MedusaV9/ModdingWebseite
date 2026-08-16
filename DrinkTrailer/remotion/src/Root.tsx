import React from 'react';
import {Composition} from 'remotion';
import {CleanLandscape} from './clean/CleanLandscape';
import {CleanTikTok} from './clean/CleanTikTok';
import {CLEAN_DURATION_IN_FRAMES, FPS, HYPE_DURATION_IN_FRAMES} from './config/timing';
import {HypeLandscape} from './hype/HypeLandscape';
import {HypeTikTok} from './hype/HypeTikTok';
import {loadBrandFonts} from './shared/fonts';

loadBrandFonts();

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="EarlyHypeTikTok"
        component={HypeTikTok}
        durationInFrames={HYPE_DURATION_IN_FRAMES}
        fps={FPS}
        width={1080}
        height={1920}
      />
      <Composition
        id="EarlyHypeLandscape"
        component={HypeLandscape}
        durationInFrames={HYPE_DURATION_IN_FRAMES}
        fps={FPS}
        width={1920}
        height={1080}
      />
      <Composition
        id="EarlyCleanTikTok"
        component={CleanTikTok}
        durationInFrames={CLEAN_DURATION_IN_FRAMES}
        fps={FPS}
        width={1080}
        height={1920}
      />
      <Composition
        id="EarlyCleanLandscape"
        component={CleanLandscape}
        durationInFrames={CLEAN_DURATION_IN_FRAMES}
        fps={FPS}
        width={1920}
        height={1080}
      />
    </>
  );
};
