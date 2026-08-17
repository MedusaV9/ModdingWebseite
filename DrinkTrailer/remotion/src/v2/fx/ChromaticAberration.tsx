import React, {useId} from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill} from 'remotion';

type ChromaticAberrationProps = PropsWithChildren<{
  /** Horizontal channel offset in px (can be animated by the caller). */
  amount?: number;
  /** Vertical offset in px. */
  amountY?: number;
}>;

/**
 * True RGB-split: the content is rendered three times through SVG
 * feColorMatrix channel-isolation filters (R/G/B), screen-blended on black,
 * with the red and blue channels offset in opposite directions.
 *
 * Note: renders children 3x — use around scene content, not around
 * already-stacked effect trees.
 */
export const ChromaticAberration: React.FC<ChromaticAberrationProps> = ({
  amount = 4,
  amountY = 0,
  children,
}) => {
  const reactId = useId();
  const rId = `ca-r-${reactId}`;
  const gId = `ca-g-${reactId}`;
  const bId = `ca-b-${reactId}`;

  if (Math.abs(amount) < 0.05 && Math.abs(amountY) < 0.05) {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }

  return (
    <AbsoluteFill style={{backgroundColor: '#000'}}>
      <svg width="0" height="0" style={{position: 'absolute'}}>
        <defs>
          <filter id={rId}>
            <feColorMatrix
              type="matrix"
              values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0"
            />
          </filter>
          <filter id={gId}>
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0"
            />
          </filter>
          <filter id={bId}>
            <feColorMatrix
              type="matrix"
              values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0"
            />
          </filter>
        </defs>
      </svg>
      <AbsoluteFill
        style={{
          filter: `url(#${rId})`,
          transform: `translate(${-amount}px, ${-amountY}px)`,
          mixBlendMode: 'screen',
        }}
      >
        {children}
      </AbsoluteFill>
      <AbsoluteFill style={{filter: `url(#${gId})`, mixBlendMode: 'screen'}}>
        {children}
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          filter: `url(#${bId})`,
          transform: `translate(${amount}px, ${amountY}px)`,
          mixBlendMode: 'screen',
        }}
      >
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
