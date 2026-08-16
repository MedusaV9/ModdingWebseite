import React from 'react';
import type {CSSProperties, PropsWithChildren} from 'react';
import {fontFamilies} from './fonts';
import {colors} from './tokens';

type TextProps = PropsWithChildren<{
  color?: string;
  style?: CSSProperties;
}>;

/** Bebas Neue — huge uppercase hype headlines. Size via style.fontSize. */
export const Display: React.FC<TextProps> = ({children, color = colors.cream, style}) => (
  <div
    style={{
      fontFamily: fontFamilies.display,
      fontWeight: 400,
      textTransform: 'uppercase',
      letterSpacing: '0.02em',
      lineHeight: 0.92,
      color,
      ...style,
    }}
  >
    {children}
  </div>
);

/** Space Grotesk Bold — statements & section headlines. */
export const Headline: React.FC<TextProps> = ({children, color = colors.ink, style}) => (
  <div
    style={{
      fontFamily: fontFamilies.headline,
      fontWeight: 700,
      letterSpacing: '-0.02em',
      lineHeight: 1.05,
      color,
      ...style,
    }}
  >
    {children}
  </div>
);

/** Inter 400/500 — body copy & captions. */
export const Body: React.FC<TextProps & {weight?: 400 | 500}> = ({
  children,
  color = colors.ink,
  weight = 400,
  style,
}) => (
  <div
    style={{
      fontFamily: fontFamilies.body,
      fontWeight: weight,
      lineHeight: 1.4,
      color,
      ...style,
    }}
  >
    {children}
  </div>
);

/** Inter SemiBold — small uppercase labels with wide tracking. */
export const Label: React.FC<TextProps> = ({children, color = colors.ink, style}) => (
  <div
    style={{
      fontFamily: fontFamilies.body,
      fontWeight: 600,
      textTransform: 'uppercase',
      letterSpacing: '0.28em',
      lineHeight: 1.2,
      color,
      ...style,
    }}
  >
    {children}
  </div>
);
