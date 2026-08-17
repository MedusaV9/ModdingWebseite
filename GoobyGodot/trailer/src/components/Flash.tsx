import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';

/** Kurzer warmweißer Blitz auf Schnitten (Frame 0 der Sequence). */
export const Flash: React.FC<{color?: string; dur?: number}> = ({
  color = '#fff6ec',
  dur = 8,
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, dur], [0.9, 0], {
    extrapolateRight: 'clamp',
  });
  if (opacity <= 0.01) {
    return null;
  }
  return <AbsoluteFill style={{backgroundColor: color, opacity, pointerEvents: 'none'}} />;
};
