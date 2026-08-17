/**
 * Shared core of the two clean trailers (EarlyCleanTikTok / EarlyCleanLandscape).
 *
 * Apple-style product film, cut on the clean_track downbeats (105 BPM):
 * off-white typography opening → Blender dolly product reveal on the chorus
 * (with the single fizz_open accent) → three flavor chapters with color-field
 * wipes → macro texture beat on the bridge → benefits recap → lineup finale
 * with a quiet CTA on the outro marker. The music ends musically: gentle duck
 * from the outro marker, eased to full silence by ~41.8 s (see cleanMusicVolume).
 */
import React from 'react';
import {AbsoluteFill, Sequence} from 'remotion';
import {MusicTrack, Sfx} from '../shared/SmartMedia';
import {GrainOverlay} from '../shared/motion/GrainOverlay';
import {colors} from '../shared/tokens';
import {CLEAN_FLAVORS} from './flavors';
import {BenefitsRecap} from './scenes/BenefitsRecap';
import {DollyReveal} from './scenes/DollyReveal';
import {FlavorChapter} from './scenes/FlavorChapter';
import {LineupOutro} from './scenes/LineupOutro';
import {MacroTexture} from './scenes/MacroTexture';
import {Opening} from './scenes/Opening';
import {CLEAN_T, SCENE_FADE_FRAMES, WIPE_IN_FRAMES, cleanMusicVolume} from './timeline';

export type CleanFormat = 'portrait' | 'landscape';

/** Frames a scene keeps rendering underneath the next scene's transition. */
const UNDERLAP = 2;

export const CleanTrailer: React.FC<{format: CleanFormat}> = ({format}) => {
  const chapterBounds = [
    [CLEAN_T.chapter1, CLEAN_T.chapter2],
    [CLEAN_T.chapter2, CLEAN_T.chapter3],
    [CLEAN_T.chapter3, CLEAN_T.bridge],
  ] as const;

  return (
    <AbsoluteFill style={{backgroundColor: colors.cream}}>
      <MusicTrack trailerStyle="clean" volume={cleanMusicVolume} />

      <Sequence durationInFrames={CLEAN_T.chorus} name="Opening">
        <Opening format={format} durationInFrames={CLEAN_T.chorus} />
      </Sequence>

      <Sequence
        from={CLEAN_T.chorus}
        durationInFrames={CLEAN_T.chapter1 - CLEAN_T.chorus + UNDERLAP}
        name="Product Reveal (Dolly)"
      >
        <DollyReveal format={format} durationInFrames={CLEAN_T.chapter1 - CLEAN_T.chorus} />
      </Sequence>

      {CLEAN_FLAVORS.map((flavor, i) => {
        const [start, end] = chapterBounds[i];
        // The wipe starts before the downbeat; the last chapter also stays
        // under the macro crossfade.
        const tail = i === CLEAN_FLAVORS.length - 1 ? SCENE_FADE_FRAMES + UNDERLAP : UNDERLAP;
        const chapterDuration = WIPE_IN_FRAMES + (end - start) + tail;
        return (
          <Sequence
            key={flavor.id}
            from={start - WIPE_IN_FRAMES}
            durationInFrames={chapterDuration}
            name={`Chapter ${i + 1}: ${flavor.name}`}
          >
            <FlavorChapter
              format={format}
              flavor={flavor}
              index={i}
              durationInFrames={chapterDuration}
            />
          </Sequence>
        );
      })}

      <Sequence
        from={CLEAN_T.bridge}
        durationInFrames={CLEAN_T.benefits - CLEAN_T.bridge + SCENE_FADE_FRAMES + UNDERLAP}
        name="Macro Texture"
      >
        <MacroTexture
          durationInFrames={CLEAN_T.benefits - CLEAN_T.bridge + SCENE_FADE_FRAMES}
        />
      </Sequence>

      <Sequence
        from={CLEAN_T.benefits}
        durationInFrames={CLEAN_T.outro - CLEAN_T.benefits + SCENE_FADE_FRAMES + UNDERLAP}
        name="Benefits Recap"
      >
        <BenefitsRecap format={format} />
      </Sequence>

      <Sequence
        from={CLEAN_T.outro}
        durationInFrames={CLEAN_T.end - CLEAN_T.outro}
        name="Lineup Outro"
      >
        <LineupOutro format={format} durationInFrames={CLEAN_T.end - CLEAN_T.outro} />
      </Sequence>

      {/* SFX: fizz_open exactly once on the first product reveal; ticks/pops
          stay far below the music. */}
      <Sequence from={CLEAN_T.chorus} durationInFrames={40} name="SFX fizz_open">
        <Sfx name="fizz_open" volume={0.65} />
      </Sequence>
      {[CLEAN_T.chapter1, CLEAN_T.chapter2, CLEAN_T.chapter3, CLEAN_T.benefits].map((at) => (
        <Sequence key={`tick-${at}`} from={at} durationInFrames={12} name="SFX ui_tick">
          <Sfx name="ui_tick" volume={0.15} />
        </Sequence>
      ))}
      <Sequence from={CLEAN_T.bridge} durationInFrames={20} name="SFX sparkle_pop">
        <Sfx name="sparkle_pop" volume={0.12} />
      </Sequence>

      <GrainOverlay opacity={0.035} />
    </AbsoluteFill>
  );
};
