import React from 'react';
import {
  AbsoluteFill,
  Easing,
  Img,
  OffthreadVideo,
  interpolate,
  staticFile,
  useCurrentFrame,
} from 'remotion';
import type {ClipSpec} from '../lib/clips';
import {clipAvailable, clipDuration, sourceFrames} from '../lib/clips';

/**
 * V2-Szenenbild: getrimmtes/beschleunigtes Gameplay-Video mit leichtem
 * Rest-Ken-Burns (Default 1.02 -> 1.06) darueber. Der Ken-Burns kaschiert den
 * 1080p->4K-Upscale und haelt die Szene auch bei Dupe-Frames im Capture in
 * Bewegung (Storyboard §4.1).
 *
 * Fehlt die Videodatei (Pruefung ueber das generierte lib/clipManifest.ts, NICHT
 * zur Laufzeit im Browser), faellt die Szene auf den V1-Still + Ken-Burns zurueck —
 * exakt das Rezept aus components/Still.tsx inkl. Fake-Bloom-Kopie.
 *
 * `muted` ist Pflicht: der komplette Ton kommt zentral aus audio/TrailerAudio.tsx.
 */
export const Clip: React.FC<{clip: ClipSpec}> = ({clip}) => {
  const frame = useCurrentFrame(); // szenenlokal (0 = clip.cutIn)
  const dur = clipDuration(clip);

  const p = interpolate(frame, [0, dur], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.33, 0, 0.67, 1),
  });

  const kb = clip.kenBurns ?? {from: 1.02, to: 1.06};
  const scale = kb.from + (kb.to - kb.from) * p;
  const tx = (kb.panX ?? 0) * p;
  const ty = (kb.panY ?? 0) * p;
  const transform = `scale(${scale}) translate(${tx}px, ${ty}px)`;

  const fade = clip.fadeIn
    ? interpolate(frame, [0, clip.fadeIn], [0, 1], {extrapolateRight: 'clamp'})
    : 1;

  const media: React.CSSProperties = {
    position: 'absolute',
    width: '100%',
    height: '100%',
    objectFit: 'cover',
    transform,
    filter: 'contrast(1.06) saturate(1.06) brightness(1.01)',
  };

  return (
    <AbsoluteFill style={{opacity: fade, backgroundColor: '#030204'}}>
      {clipAvailable(clip) ? (
        <OffthreadVideo
          src={staticFile(clip.src)}
          trimBefore={clip.trimBefore}
          trimAfter={clip.trimBefore + sourceFrames(clip)}
          playbackRate={clip.playbackRate}
          muted
          style={media}
        />
      ) : (
        <>
          <Img src={staticFile(`stills/${clip.fallbackStill}.jpg`)} style={media} />
          {/* Fake-Bloom: vorgeblurrte Kopie, screen-Blend (kein Runtime-Blur) */}
          <Img
            src={staticFile(`stills/${clip.fallbackStill}_blur.jpg`)}
            style={{...media, filter: undefined, mixBlendMode: 'screen', opacity: 0.22}}
          />
        </>
      )}
    </AbsoluteFill>
  );
};
