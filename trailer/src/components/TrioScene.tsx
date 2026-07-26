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
              width: 442,
              height: 932,
              borderRadius: 38,
              overflow: 'hidden',
              boxShadow: '0 18px 60px rgba(74, 59, 54, 0.3)',
              border: `10px solid ${COLORS.white}`,
              transform: `scale(${pop}) rotate(${rots[i % 3]}deg)`,
              backgroundColor: COLORS.white,
            }}
          >
            <OffthreadVideo
              muted
              src={staticFile(clip.src)}
              startFrom={clip.startFrom ?? 0}
              style={{width: '100%', height: '100%', objectFit: 'cover'}}
            />
          </div>
        );
      })}
    </AbsoluteFill>
  );
};
