/**
 * Defensive media components: they render nothing / a branded fallback plane
 * when the underlying asset (music track, SFX, Blender render) does not exist
 * yet, so the compositions stay renderable at every stage of production.
 */
import React from 'react';
import type {CSSProperties, PropsWithChildren} from 'react';
import {AbsoluteFill, Audio, OffthreadVideo} from 'remotion';
import {findMusicTrack, findSfx, renderSrc} from '../lib/assets';
import type {TrailerStyle} from '../lib/assets';
import {fallbackPlane} from './tokens';

type MusicTrackProps = {
  trailerStyle: TrailerStyle;
  volume?: number | ((frame: number) => number);
};

/** Plays the style's music track if one exists in assets/music/, else silent. */
export const MusicTrack: React.FC<MusicTrackProps> = ({trailerStyle, volume = 1}) => {
  const src = findMusicTrack(trailerStyle);
  if (!src) return null;
  return <Audio src={src} volume={volume} />;
};

type SfxProps = {
  name: string;
  volume?: number | ((frame: number) => number);
};

/** Plays an SFX (matched by name in assets/music/sfx_*), else silent. */
export const Sfx: React.FC<SfxProps> = ({name, volume = 1}) => {
  const src = findSfx(name);
  if (!src) return null;
  return <Audio src={src} volume={volume} />;
};

type RenderClipProps = PropsWithChildren<{
  /** Clip name, resolved via renderSrc() (e.g. "can_spin" → renders/early_can_spin.mp4). */
  name: string;
  muted?: boolean;
  /** Style applied to the video element (and the fallback plane). */
  style?: CSSProperties;
  /** Background of the fallback plane when the clip is missing. */
  fallbackBackground?: string;
}>;

/**
 * Plays a Blender render clip full-bleed — or, while the clip does not exist
 * yet, shows a brand-gradient color plane (with optional overlay children).
 */
export const RenderClip: React.FC<RenderClipProps> = ({
  name,
  muted = true,
  style,
  fallbackBackground = fallbackPlane,
  children,
}) => {
  const src = renderSrc(name);
  if (!src) {
    return (
      <AbsoluteFill
        style={{background: fallbackBackground, justifyContent: 'center', alignItems: 'center', ...style}}
      >
        {children}
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill style={style}>
      <OffthreadVideo
        src={src}
        muted={muted}
        style={{width: '100%', height: '100%', objectFit: 'cover'}}
      />
      {children}
    </AbsoluteFill>
  );
};
