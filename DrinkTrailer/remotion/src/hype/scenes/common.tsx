/**
 * Scene building blocks shared by HypeTikTok and HypeLandscape.
 * The two formats assemble these into DIFFERENT layouts (full-bleed vs.
 * split-screens) — nothing in here hardcodes an aspect ratio.
 */
import React from 'react';
import type {CSSProperties, ReactNode} from 'react';
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {BubbleField} from '../../shared/motion/BubbleField';
import {GlitchZoom} from '../../shared/motion/GlitchZoom';
import {KenBurnsImage} from '../../shared/motion/KenBurnsImage';
import {ShakeWrapper} from '../../shared/motion/ShakeWrapper';
import {SpeedRampCut} from '../../shared/motion/SpeedRampCut';
import {TypeReveal} from '../../shared/motion/TypeReveal';
import {Body, Display, Headline, Label} from '../../shared/Typography';
import {fontFamilies} from '../../shared/fonts';
import {colors, gradients} from '../../shared/tokens';
import {EmojiSticker} from '../fx/EmojiSticker';
import {FlashFrame} from '../fx/FlashFrame';
import {PunchWord} from '../fx/PunchWord';
import {PunchZoom} from '../fx/PunchZoom';
import {RgbSplit} from '../fx/RgbSplit';
import {B} from '../timeline';

export type HypeAspect = 'portrait' | 'landscape';

export type StickerSpec = {emoji: string; x: number; y: number; size?: number; delay?: number};

// ---------------------------------------------------------------------------
// Cover image (with fallback plane) — the raw pixel layer of most cuts.
// ---------------------------------------------------------------------------

export const CoverImage: React.FC<{src: string | null; style?: CSSProperties}> = ({
  src,
  style,
}) => {
  if (!src) return <AbsoluteFill style={{background: gradients.sunrise, ...style}} />;
  return (
    <Img
      src={src}
      style={{width: '100%', height: '100%', objectFit: 'cover', display: 'block', ...style}}
    />
  );
};

// ---------------------------------------------------------------------------
// ImpactCut — one full-bleed montage cut: punch-in zoom + shake + optional
// RGB-split burst, punch word, emoji sticker. Used for nearly every beat cut.
// ---------------------------------------------------------------------------

export type ImpactCutProps = {
  src: string | null;
  word?: string;
  wordSize?: number;
  wordColor?: string;
  /** Vertical center of the word block in % of the frame height. */
  wordY?: number;
  tilt?: number;
  sticker?: StickerSpec;
  /** Chromatic-aberration burst on the first frames of the cut. */
  rgb?: boolean;
  shakeAmplitude?: number;
  zoomFrom?: number;
  zoomTo?: number;
  seed?: string;
  children?: ReactNode;
};

export const ImpactCut: React.FC<ImpactCutProps> = ({
  src,
  word,
  wordSize = 150,
  wordColor = colors.cream,
  wordY = 44,
  tilt = 0,
  sticker,
  rgb = false,
  shakeAmplitude = 9,
  zoomFrom = 1.26,
  zoomTo = 1.06,
  seed = 'cut',
  children,
}) => {
  const picture = (
    <ShakeWrapper
      amplitude={shakeAmplitude}
      rotationAmplitude={0.55}
      seed={`${seed}-shake`}
      envelope={(f) => 0.45 + 0.55 * Math.exp(-f / 14)}
    >
      <PunchZoom from={zoomFrom} to={zoomTo}>
        <CoverImage src={src} />
      </PunchZoom>
    </ShakeWrapper>
  );

  return (
    <AbsoluteFill style={{backgroundColor: colors.ink, overflow: 'hidden'}}>
      {rgb ? <RgbSplit maxOffset={26} durationInFrames={10}>{picture}</RgbSplit> : picture}
      <AbsoluteFill style={{background: gradients.inkVignette, opacity: 0.5}} />
      {word ? (
        <div
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            top: `${wordY}%`,
            transform: 'translateY(-50%)',
            display: 'flex',
            justifyContent: 'center',
          }}
        >
          <PunchWord text={word} size={wordSize} color={wordColor} tilt={tilt} />
        </div>
      ) : null}
      {sticker ? (
        <EmojiSticker
          emoji={sticker.emoji}
          x={sticker.x}
          y={sticker.y}
          size={sticker.size ?? 130}
          startFrame={sticker.delay ?? 2}
          seed={`${seed}-sticker`}
        />
      ) : null}
      {children}
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------
// SpeedRampScene — whip-zoom over a splash still: fast → slo-mo → fast, with
// flash frames on the ramp boundaries (the mandated speed-ramp sequence).
// ---------------------------------------------------------------------------

export const SpeedRampScene: React.FC<{
  src: string | null;
  panPerFrame?: number;
  zoomPerFrame?: number;
  baseZoom?: number;
}> = ({src, panPerFrame = 0.05, zoomPerFrame = 0.0024, baseZoom = 1.2}) => (
  <AbsoluteFill style={{backgroundColor: colors.ink}}>
    <SpeedRampCut
      segments={[
        {fromFrame: 0, speed: 2.8},
        {fromFrame: 18, speed: 0.35},
        {fromFrame: 40, speed: 1.6},
      ]}
      flashDurationInFrames={4}
    >
      {(f) => (
        <AbsoluteFill style={{overflow: 'hidden'}}>
          {src ? (
            <Img
              src={src}
              style={{
                width: '100%',
                height: '100%',
                objectFit: 'cover',
                transform: `translateX(${-2 + f * panPerFrame}%) scale(${baseZoom + f * zoomPerFrame})`,
              }}
            />
          ) : (
            <AbsoluteFill style={{background: gradients.sunrise}} />
          )}
        </AbsoluteFill>
      )}
    </SpeedRampCut>
    <AbsoluteFill style={{background: gradients.inkVignette, opacity: 0.45}} />
  </AbsoluteFill>
);

// ---------------------------------------------------------------------------
// Countdown badge (tease section: 3 → 2 → 1).
// ---------------------------------------------------------------------------

export const CountdownBadge: React.FC<{n: string; x: number; y: number; size?: number}> = ({
  n,
  x,
  y,
  size = 150,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pop = spring({frame, fps, config: {damping: 10, mass: 0.5, stiffness: 220}});
  return (
    <div
      style={{
        position: 'absolute',
        left: `${x}%`,
        top: `${y}%`,
        width: size,
        height: size,
        transform: `translate(-50%, -50%) scale(${pop}) rotate(${(1 - pop) * -18}deg)`,
        borderRadius: '50%',
        border: `5px solid ${colors.lime}`,
        display: 'grid',
        placeItems: 'center',
        backgroundColor: `${colors.ink}B3`,
      }}
    >
      <Display color={colors.lime} style={{fontSize: size * 0.62, lineHeight: 1}}>
        {n}
      </Display>
    </div>
  );
};

// ---------------------------------------------------------------------------
// PreDropFlicker — the 13 stutter frames right before drop 1.
// ---------------------------------------------------------------------------

export const PreDropFlicker: React.FC<{wordSize?: number}> = ({wordSize = 200}) => {
  const frame = useCurrentFrame();
  const jitterScale = 0.92 + (frame % 4) * 0.045;
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <GlitchZoom intensity={1.2} settleAfter={999} seed="pre-drop" zoomFrom={1} zoomTo={1.04}>
        <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
          <Display style={{fontSize: wordSize, transform: `scale(${jitterScale})`}}>
            EARLY
          </Display>
        </AbsoluteFill>
      </GlitchZoom>
      <FlashFrame at={[0, 8]} durationInFrames={2} peak={0.55} />
      <FlashFrame at={[4]} durationInFrames={2} color={colors.rose} peak={0.6} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------
// LetterSlam — E·A·R·L·Y slamming in letter-by-letter on the beat
// (drop-2 finale, starts at B(88); letters land on beats 88..92).
// ---------------------------------------------------------------------------

export const LetterSlam: React.FC<{
  backgroundSrc: string | null;
  letterSize: number;
  letterGap?: number;
  sublineDelay?: number;
}> = ({backgroundSrc, letterSize, letterGap = 0.18, sublineDelay = 65}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const letters = ['E', 'A', 'R', 'L', 'Y'];
  const slamStart = B(88);

  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <KenBurnsImage
        src={backgroundSrc}
        from={{scale: 1.06}}
        to={{scale: 1.2}}
        durationInFrames={durationInFrames}
      />
      <AbsoluteFill style={{backgroundColor: `${colors.ink}99`}} />
      <BubbleField count={16} color={colors.rose} opacity={0.3} seed="slam-bubbles" />
      <ShakeWrapper amplitude={5} rotationAmplitude={0.3} seed="slam-shake">
        <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
          <div style={{display: 'flex', gap: `${letterGap}em`, fontSize: letterSize}}>
            {letters.map((letter, i) => {
              const localStart = B(88 + i) - slamStart;
              const p = spring({
                frame: frame - localStart,
                fps,
                config: {damping: 12, mass: 0.6, stiffness: 220},
              });
              const opacity = frame >= localStart ? 1 : 0;
              return (
                <Display
                  key={letter + i}
                  style={{
                    fontSize: letterSize,
                    opacity,
                    transform: `scale(${2.4 - 1.4 * p}) translateY(${(1 - p) * -0.2}em)`,
                    textShadow: '0 10px 60px rgba(0,0,0,0.6)',
                  }}
                >
                  {letter}
                </Display>
              );
            })}
          </div>
          <Label color={colors.lime} style={{fontSize: letterSize * 0.14, marginTop: '0.4em'}}>
            <TypeReveal
              text="HYDRATION WITH BENEFITS"
              mode="words"
              startFrame={sublineDelay}
              staggerFrames={4}
            />
          </Label>
        </AbsoluteFill>
      </ShakeWrapper>
      <FlashFrame at={letters.map((_, i) => B(88 + i) - slamStart)} durationInFrames={2} peak={0.4} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------
// Endcard — CTA block + lineup.
//
// Portrait is a dedicated vertical composition: the three cans appear as a
// staggered fan of rounded tiles (nothing ever crops outside the frame) and
// the whole CTA block is balanced so at least the bottom 20% of the frame
// stays copy-free (TikTok safe zone). Landscape keeps the 16:9 lineup image.
// ---------------------------------------------------------------------------

type CtaStackProps = {
  logoSize: number;
  sloganSize: number;
  pillPadding: string;
  pillTextSize: number;
  linkSize: number;
};

/** Logo → slogan → pill → links, springing in on the shared endcard timing. */
const CtaStack: React.FC<CtaStackProps> = ({
  logoSize,
  sloganSize,
  pillPadding,
  pillTextSize,
  linkSize,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  const logo = spring({frame: frame - 20, fps, config: {damping: 13, mass: 0.6, stiffness: 200}});
  const pill = spring({frame: frame - 52, fps, config: {damping: 11, mass: 0.5, stiffness: 180}});
  const pillPulse = 1 + Math.sin(Math.max(0, frame - 70) * 0.16) * 0.02;
  const sloganIn = interpolate(frame, [40, 52], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const linksIn = interpolate(frame, [66, 80], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <>
      <div style={{opacity: Math.min(1, logo * 1.2), transform: `scale(${2 - logo})`}}>
        <Display
          style={{
            fontSize: logoSize,
            letterSpacing: '0.08em',
            textShadow: '0 12px 70px rgba(0,0,0,0.65)',
          }}
        >
          EARLY
        </Display>
      </div>
      <Label color={colors.lime} style={{fontSize: sloganSize, marginTop: 24, opacity: sloganIn}}>
        HYDRATION WITH BENEFITS
      </Label>
      <div
        style={{
          marginTop: 42,
          transform: `scale(${pill * pillPulse})`,
          backgroundColor: colors.lime,
          borderRadius: 999,
          padding: pillPadding,
          boxShadow: `0 10px 60px ${colors.lime}66`,
        }}
      >
        <Headline color={colors.ink} style={{fontSize: pillTextSize}}>
          JETZT PROBIEREN
        </Headline>
      </div>
      <div style={{display: 'flex', gap: 28, alignItems: 'center', marginTop: 38, opacity: linksIn}}>
        <Body color={colors.cream} weight={500} style={{fontSize: linkSize}}>
          drinkearly.com
        </Body>
        <div style={{width: 10, height: 10, borderRadius: '50%', backgroundColor: colors.coral}} />
        <Body color={colors.cream} weight={500} style={{fontSize: linkSize}}>
          @drink.early
        </Body>
      </div>
    </>
  );
};

/** Portrait endcard: staggered can fan (top ~42%) + CTA stack ending ≤73%. */
const EndcardPortrait: React.FC<{canSrcs: (string | null)[]}> = ({canSrcs}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  // Fan tiles: [grapefruit left, lemon-mint right, peach front-center].
  // Positions/sizes are chosen so every rotated tile stays fully in frame.
  const tiles = [
    {src: canSrcs[0], x: 26.5, y: 27, w: 340, h: 580, rot: -11, delay: 10, z: 1},
    {src: canSrcs[2], x: 73.5, y: 27, w: 340, h: 580, rot: 11, delay: 14, z: 1},
    {src: canSrcs[1], x: 50, y: 24, w: 400, h: 690, rot: 0, delay: 4, z: 2},
  ];

  return (
    <AbsoluteFill
      style={{
        background: `linear-gradient(180deg, ${colors.ink} 0%, #453232 55%, ${colors.ink} 100%)`,
      }}
    >
      <AbsoluteFill
        style={{
          background: `radial-gradient(62% 32% at 50% 26%, ${colors.rose}66 0%, transparent 72%)`,
        }}
      />
      <BubbleField count={20} color={colors.lime} opacity={0.28} seed="endcard-bubbles" />
      {tiles.map((tile, i) => {
        const p = spring({
          frame: frame - tile.delay,
          fps,
          config: {damping: 13, mass: 0.6, stiffness: 170},
        });
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: `${tile.x}%`,
              top: `${tile.y}%`,
              width: tile.w,
              height: tile.h,
              zIndex: tile.z,
              transform: `translate(-50%, -50%) rotate(${tile.rot}deg) scale(${0.62 + 0.38 * p}) translateY(${(1 - p) * 70}px)`,
              opacity: Math.min(1, p * 1.4),
              borderRadius: 30,
              overflow: 'hidden',
              boxShadow: '0 30px 90px rgba(0,0,0,0.55)',
              border: `2px solid ${colors.cream}26`,
            }}
          >
            <CoverImage src={tile.src} style={{transform: 'scale(1.12)'}} />
          </div>
        );
      })}
      {/* CTA block: starts at 46% height; links end ≈73% → bottom 27% copy-free. */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: '46%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          zIndex: 3,
        }}
      >
        <CtaStack
          logoSize={230}
          sloganSize={34}
          pillPadding="26px 74px"
          pillTextSize={50}
          linkSize={36}
        />
      </div>
    </AbsoluteFill>
  );
};

/** Landscape endcard: 16:9 lineup image + centered CTA stack. */
const EndcardLandscape: React.FC<{lineupSrc: string | null}> = ({lineupSrc}) => {
  const {durationInFrames} = useVideoConfig();
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <KenBurnsImage
        src={lineupSrc}
        from={{scale: 1.18}}
        to={{scale: 1.04}}
        durationInFrames={durationInFrames}
      />
      <AbsoluteFill style={{background: gradients.bottomScrim}} />
      <AbsoluteFill style={{background: gradients.inkVignette, opacity: 0.65}} />
      <BubbleField count={20} color={colors.lime} opacity={0.28} seed="endcard-bubbles" />
      <AbsoluteFill
        style={{justifyContent: 'center', alignItems: 'center', paddingTop: 200, paddingBottom: 40}}
      >
        <CtaStack
          logoSize={230}
          sloganSize={30}
          pillPadding="22px 64px"
          pillTextSize={46}
          linkSize={32}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const Endcard: React.FC<{
  aspect: HypeAspect;
  lineupSrc: string | null;
  /** Portrait only: [grapefruit, peach, lemon-mint] can stills for the fan. */
  canSrcs?: (string | null)[];
}> = ({aspect, lineupSrc, canSrcs = []}) =>
  aspect === 'portrait' ? (
    <EndcardPortrait canSrcs={canSrcs} />
  ) : (
    <EndcardLandscape lineupSrc={lineupSrc} />
  );

// ---------------------------------------------------------------------------
// TypoColumn — landscape-only side column with slamming copy (also used by
// portrait break for the claims stack).
// ---------------------------------------------------------------------------

export const ClaimsStack: React.FC<{
  claims: string[];
  fontSize: number;
  align?: 'center' | 'flex-start';
  staggerFrames?: number;
  startFrame?: number;
}> = ({claims, fontSize, align = 'center', staggerFrames = 16, startFrame = 8}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: align,
        gap: fontSize * 0.75,
      }}
    >
      {claims.map((claim, i) => {
        const local = frame - startFrame - i * staggerFrames;
        const p = spring({frame: local, fps, config: {damping: 14, mass: 0.6, stiffness: 160}});
        const opacity = interpolate(local, [0, 6], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        });
        return (
          <div
            key={claim}
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: align,
              gap: 14,
              opacity,
              transform: `translateY(${(1 - p) * 40}px)`,
            }}
          >
            <div
              style={{
                fontFamily: fontFamilies.display,
                fontSize,
                textTransform: 'uppercase',
                letterSpacing: '0.04em',
                lineHeight: 1,
                color: colors.cream,
                textShadow: '0 6px 36px rgba(0,0,0,0.5)',
              }}
            >
              {claim}
            </div>
            <div style={{width: fontSize * 1.4, height: 4, backgroundColor: colors.coral}} />
          </div>
        );
      })}
    </div>
  );
};
