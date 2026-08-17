import React from 'react';
import {
  AbsoluteFill,
  OffthreadVideo,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {COLORS} from '../theme';

/**
 * Hochkant-Triptychon: drei Portrait-Minigames als „Handy-Karten“
 * nebeneinander, leicht rotiert, federn nacheinander ein.
 */
const CARD_W = 442;
const CARD_H = 932;
/**
 * Quellvideo (720×1280) und Spiel-Canvas darin (Host-Chrome außenrum).
 * Nach dem G4-Letterbox-Umbau neu vermessen (Bewegungs-Differenz):
 * Canvas = 472×1028 @ (124,60) — praktisch unverändert zu v3.
 */
const SRC_W = 720;
const SRC_H = 1280;
const RECT = {x: 124, y: 60, w: 472, h: 1028};
const S = Math.max(CARD_W / RECT.w, CARD_H / RECT.h);
const TX = -(RECT.x * S - (CARD_W - RECT.w * S) / 2);
const TY = -(RECT.y * S - (CARD_H - RECT.h * S) / 2);

export const TrioScene: React.FC<{
  clips: {src: string; startFrom?: number}[];
}> = ({clips}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const rots = [-4, 0, 4];
  return (
    <AbsoluteFill
      style={{
        backgroundColor: COLORS.cream,
        flexDirection: 'row',
        justifyContent: 'center',
        alignItems: 'center',
        gap: 44,
      }}
    >
      {clips.map((clip, i) => {
        const pop = spring({
          frame: frame - i * 5,
          fps,
          config: {damping: 12, stiffness: 150, mass: 0.7},
        });
        return (
          <div
            key={clip.src}
            style={{
              width: CARD_W,
              height: CARD_H,
              borderRadius: 38,
              overflow: 'hidden',
              boxShadow: '0 18px 60px rgba(74, 59, 54, 0.3)',
              border: `10px solid ${COLORS.white}`,
              transform: `scale(${pop}) rotate(${rots[i % 3]}deg)`,
              backgroundColor: COLORS.white,
              position: 'relative',
            }}
          >
            <OffthreadVideo
              muted
              src={staticFile(clip.src)}
              startFrom={clip.startFrom ?? 0}
              style={{
                position: 'absolute',
                top: 0,
                left: 0,
                width: SRC_W * S,
                height: SRC_H * S,
                transform: `translate(${TX}px, ${TY}px)`,
              }}
            />
          </div>
        );
      })}
    </AbsoluteFill>
  );
};
