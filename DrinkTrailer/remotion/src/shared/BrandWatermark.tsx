import React from 'react';
import {useVideoConfig} from 'remotion';
import {fontFamilies} from './fonts';
import {colors} from './tokens';

type Corner = 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right';

type BrandWatermarkProps = {
  position?: Corner;
  /** 'light' = cream text (dark footage), 'dark' = ink text (light footage). */
  tone?: 'light' | 'dark';
  label?: string;
  /** Optional small second line, e.g. a handle or claim. */
  sub?: string;
  opacity?: number;
};

/** Small, always-on brand watermark pinned to a corner. */
export const BrandWatermark: React.FC<BrandWatermarkProps> = ({
  position = 'top-right',
  tone = 'light',
  label = 'EARLY',
  sub,
  opacity = 0.85,
}) => {
  const {width, height} = useVideoConfig();
  // Scale relative to the short edge so it looks identical in 9:16 and 16:9.
  const unit = Math.min(width, height) / 1080;
  const margin = 56 * unit;
  const color = tone === 'light' ? colors.cream : colors.ink;

  const corner: React.CSSProperties = {
    'top-left': {top: margin, left: margin, textAlign: 'left' as const},
    'top-right': {top: margin, right: margin, textAlign: 'right' as const},
    'bottom-left': {bottom: margin, left: margin, textAlign: 'left' as const},
    'bottom-right': {bottom: margin, right: margin, textAlign: 'right' as const},
  }[position];

  return (
    <div style={{position: 'absolute', ...corner, opacity, pointerEvents: 'none'}}>
      <div
        style={{
          fontFamily: fontFamilies.display,
          fontSize: 52 * unit,
          letterSpacing: '0.14em',
          lineHeight: 1,
          color,
          textShadow: tone === 'light' ? `0 ${2 * unit}px ${12 * unit}px rgba(0,0,0,0.35)` : 'none',
        }}
      >
        {label}
      </div>
      {sub ? (
        <div
          style={{
            fontFamily: fontFamilies.body,
            fontWeight: 500,
            fontSize: 22 * unit,
            letterSpacing: '0.18em',
            textTransform: 'uppercase',
            marginTop: 8 * unit,
            color,
            opacity: 0.8,
          }}
        >
          {sub}
        </div>
      ) : null}
    </div>
  );
};
