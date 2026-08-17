import React from 'react';
import {
  AbsoluteFill,
  Easing,
  interpolate,
  OffthreadVideo,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {COLORS} from '../theme';
import {Label} from './Label';

/** Teilrechteck des Quellvideos, das den Bildschirm füllen soll. */
export type SourceRect = {x: number; y: number; w: number; h: number};

/**
 * Vollbild-Gameplay-Clip mit sanftem Ken-Burns-Zoom (damit auch ruhige
 * Aufnahmen leben), optionalem Label und Eingangs-Pop.
 */
export const ClipScene: React.FC<{
  src: string;
  /** Startversatz im Quellvideo (Frames à 60 fps). */
  startFrom?: number;
  label?: string;
  labelOut?: number;
  accent?: string;
  /** 1.0 = kein Zoom; z. B. 1.06 → langsamer Push-in über die Szene. */
  zoomTo?: number;
  zoomFrom?: number;
  /** Dauer der Szene (für den Zoomverlauf). */
  durationInFrames: number;
  /**
   * Optional: nur diesen Ausschnitt des Quellvideos zeigen (cover-Logik,
   * zentriert). Für die Minigame-Aufnahmen: der MinigameHost rendert das
   * Spiel in einen Teilbereich des Fensters (Host-Chrome außenrum) — im
   * Trailer soll aber das SPIEL das Bild füllen.
   */
  sourceRect?: SourceRect;
  children?: React.ReactNode;
}> = ({
  src,
  startFrom = 0,
  label,
  labelOut,
  accent,
  zoomFrom = 1.0,
  zoomTo = 1.05,
  durationInFrames,
  sourceRect,
  children,
}) => {
  const frame = useCurrentFrame();
  const {width: W, height: H} = useVideoConfig();
  const zoom = interpolate(frame, [0, durationInFrames], [zoomFrom, zoomTo], {
    easing: Easing.inOut(Easing.ease),
    extrapolateRight: 'clamp',
  });
  let video: React.ReactNode;
  if (sourceRect) {
    // Quellvideo hat Kompositionsgröße; Ausschnitt per scale+translate
    // bildschirmfüllend legen (wie objectFit:cover, nur fürs Teilrechteck).
    const s = Math.max(W / sourceRect.w, H / sourceRect.h);
    const tx = -(sourceRect.x * s - (W - sourceRect.w * s) / 2);
    const ty = -(sourceRect.y * s - (H - sourceRect.h * s) / 2);
    video = (
      <OffthreadVideo
        muted
        src={staticFile(src)}
        startFrom={startFrom}
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          width: W * s,
          height: H * s,
          transform: `translate(${tx}px, ${ty}px)`,
        }}
      />
    );
  } else {
    video = (
      <OffthreadVideo
        muted
        src={staticFile(src)}
        startFrom={startFrom}
        style={{width: '100%', height: '100%', objectFit: 'cover'}}
      />
    );
  }
  return (
    <AbsoluteFill style={{backgroundColor: COLORS.cream, overflow: 'hidden'}}>
      <AbsoluteFill style={{transform: `scale(${zoom})`}}>{video}</AbsoluteFill>
      {label ? <Label text={label} out={labelOut} accent={accent} /> : null}
      {children}
    </AbsoluteFill>
  );
};
