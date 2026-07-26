import React from 'react';
import {
  AbsoluteFill,
  Easing,
  interpolate,
  OffthreadVideo,
  staticFile,
  useCurrentFrame,
} from 'remotion';
import {COLORS} from '../theme';
import {Label} from './Label';

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
  children,
}) => {
  const frame = useCurrentFrame();
  const zoom = interpolate(frame, [0, durationInFrames], [zoomFrom, zoomTo], {
    easing: Easing.inOut(Easing.ease),
    extrapolateRight: 'clamp',
  });
  return (
    <AbsoluteFill style={{backgroundColor: COLORS.cream, overflow: 'hidden'}}>
      <AbsoluteFill style={{transform: `scale(${zoom})`}}>
        <OffthreadVideo
          muted
          src={staticFile(src)}
          startFrom={startFrom}
          style={{width: '100%', height: '100%', objectFit: 'cover'}}
        />
      </AbsoluteFill>
      {label ? <Label text={label} out={labelOut} accent={accent} /> : null}
      {children}
    </AbsoluteFill>
  );
};
