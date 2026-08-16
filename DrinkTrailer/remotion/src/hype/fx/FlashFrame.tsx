import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {colors} from '../../shared/tokens';

type FlashFrameProps = {
  /** Frames (relative to this component) at which a flash fires. */
  at: number[];
  /** Flash length — the classic overedited look is 2–3 frames. */
  durationInFrames?: number;
  color?: string;
  /** Peak opacity of the flash. */
  peak?: number;
};

/** Hard 2–3 frame flash frames (white or brand-rosa) at given frames. */
export const FlashFrame: React.FC<FlashFrameProps> = ({
  at,
  durationInFrames = 3,
  color = '#ffffff',
  peak = 0.95,
}) => {
  const frame = useCurrentFrame();

  let opacity = 0;
  for (const start of at) {
    if (frame >= start && frame < start + durationInFrames) {
      // Full hit on the first frame, then a fast linear falloff.
      opacity = peak * (1 - (frame - start) / durationInFrames);
      break;
    }
  }

  if (opacity <= 0) return null;
  return <AbsoluteFill style={{backgroundColor: color, opacity, pointerEvents: 'none'}} />;
};

/** Brand-rosa flash color, exported so scenes alternate white/rosa flashes. */
export const FLASH_ROSE = colors.rose;
