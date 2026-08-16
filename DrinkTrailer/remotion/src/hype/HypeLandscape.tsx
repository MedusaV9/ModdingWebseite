/**
 * EarlyHypeLandscape — 1920x1080 @ 30fps, 48s.
 *
 * NOT a scaled port of the TikTok cut: same beat skeleton, but scenes are
 * recomposed for 16:9 — split-screens with side typo columns, the Blender
 * dolly clip as full-bleed impact footage, the 9:16 turntable as a split
 * panel, 16:9 stills preferred, and a triple-split strobe in drop 2.
 */
import React from 'react';
import type {ReactNode} from 'react';
import {AbsoluteFill, Sequence, useCurrentFrame} from 'remotion';
import {imageSrc} from '../lib/assets';
import {framesPerBeat} from '../lib/beats';
import {BrandWatermark} from '../shared/BrandWatermark';
import {fontFamilies} from '../shared/fonts';
import {BubbleField} from '../shared/motion/BubbleField';
import {GlitchZoom} from '../shared/motion/GlitchZoom';
import {GrainOverlay} from '../shared/motion/GrainOverlay';
import {KenBurnsImage} from '../shared/motion/KenBurnsImage';
import {ShakeWrapper} from '../shared/motion/ShakeWrapper';
import {TypeReveal} from '../shared/motion/TypeReveal';
import {Display, Label} from '../shared/Typography';
import {colors, gradients} from '../shared/tokens';
import {EmojiSticker} from './fx/EmojiSticker';
import {FlashFrame} from './fx/FlashFrame';
import {LoopedClip} from './fx/LoopedClip';
import {PunchWord} from './fx/PunchWord';
import {PunchZoom} from './fx/PunchZoom';
import {RgbSplit} from './fx/RgbSplit';
import {renderStillSrc} from './hypeAssets';
import {HypeAudio} from './HypeAudio';
import {
  ClaimsStack,
  CountdownBadge,
  CoverImage,
  Endcard,
  ImpactCut,
  LetterSlam,
  PreDropFlicker,
  SpeedRampScene,
} from './scenes/common';
import type {StickerSpec} from './scenes/common';
import {B, BREAK, DROP1, DROP2, OUTRO} from './timeline';

// ---------------------------------------------------------------------------
// Landscape-only layout pieces
// ---------------------------------------------------------------------------

/** Split-screen: media panel on one side, ink typo column on the other. */
const SplitCut: React.FC<{
  media: ReactNode;
  word: string;
  wordSize?: number;
  /** Side the MEDIA panel sits on. */
  mediaSide: 'left' | 'right';
  /** Media panel width in % of the frame. */
  mediaWidth?: number;
  sticker?: StickerSpec;
  accent?: string;
  badge?: string;
  seed?: string;
}> = ({
  media,
  word,
  wordSize = 150,
  mediaSide,
  mediaWidth = 56,
  sticker,
  accent = colors.coral,
  badge,
  seed = 'split',
}) => {
  const mediaPanel = (
    <div style={{width: `${mediaWidth}%`, position: 'relative', overflow: 'hidden'}}>
      <PunchZoom from={1.24} to={1.05}>
        {media}
      </PunchZoom>
    </div>
  );
  const typoPanel = (
    <div
      style={{
        width: `${100 - mediaWidth}%`,
        position: 'relative',
        backgroundColor: colors.ink,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        alignItems: 'center',
        gap: 36,
      }}
    >
      <BubbleField count={12} color={accent} opacity={0.25} seed={`${seed}-bubbles`} />
      {badge ? <CountdownBadge n={badge} x={50} y={20} size={130} /> : null}
      <Label color={accent} style={{fontSize: 26}}>
        EARLY
      </Label>
      <PunchWord text={word} size={wordSize} startFrame={2} />
      <div style={{width: 120, height: 5, backgroundColor: accent}} />
    </div>
  );
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <ShakeWrapper
        amplitude={6}
        rotationAmplitude={0.3}
        seed={`${seed}-shake`}
        envelope={(f) => 0.4 + 0.6 * Math.exp(-f / 12)}
      >
        <AbsoluteFill style={{flexDirection: 'row'}}>
          {mediaSide === 'left' ? mediaPanel : typoPanel}
          {mediaSide === 'left' ? typoPanel : mediaPanel}
        </AbsoluteFill>
      </ShakeWrapper>
      {sticker ? (
        <EmojiSticker
          emoji={sticker.emoji}
          x={sticker.x}
          y={sticker.y}
          size={sticker.size ?? 140}
          startFrame={sticker.delay ?? 3}
          seed={`${seed}-sticker`}
        />
      ) : null}
    </AbsoluteFill>
  );
};

/** Tease opener: centered vertical macro panel over a giant ghost EARLY. */
const TeaseFizzWide: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: colors.ink}}>
    <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
      <div
        style={{
          fontFamily: fontFamilies.display,
          fontSize: 560,
          letterSpacing: '0.04em',
          color: 'transparent',
          WebkitTextStroke: `3px ${colors.cream}`,
          opacity: 0.16,
        }}
      >
        EARLY
      </div>
    </AbsoluteFill>
    <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
      <div style={{width: '30%', height: '86%', position: 'relative', overflow: 'hidden'}}>
        <GlitchZoom zoomFrom={1.06} zoomTo={1.18} intensity={0.55} settleAfter={22} seed="tease-fizz-l">
          <CoverImage src={imageSrc('macroCondensation9x16')} />
        </GlitchZoom>
      </div>
    </AbsoluteFill>
    <BubbleField count={24} color={colors.cream} opacity={0.35} seed="tease-bubbles-l" />
    <EmojiSticker emoji="🫧" x={66} y={22} size={150} startFrame={6} seed="tease-fizz-sticker-l" />
  </AbsoluteFill>
);

/** Third tease step: three panels + centered word (landscape only). */
const TripleTease: React.FC = () => {
  const panels = [
    imageSrc('pourGlass9x16'),
    imageSrc('minimalFloat16x9'),
    imageSrc('bubblesUnderwater9x16'),
  ];
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <AbsoluteFill style={{flexDirection: 'row', gap: 6}}>
        {panels.map((src, i) => (
          <div key={i} style={{flex: 1, position: 'relative', overflow: 'hidden'}}>
            <PunchZoom from={1.3 - i * 0.06} to={1.06}>
              <CoverImage src={src} />
            </PunchZoom>
            <AbsoluteFill style={{backgroundColor: colors.ink, opacity: i === 1 ? 0 : 0.35}} />
          </div>
        ))}
      </AbsoluteFill>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <PunchWord text="AESTHETIC" size={190} startFrame={1} tilt={-2} />
      </AbsoluteFill>
      <CountdownBadge n="1" x={50} y={16} size={130} />
    </AbsoluteFill>
  );
};

/** Full-bleed dolly clip impact (16:9 Blender footage). */
const DollyImpact: React.FC<{word?: string; rgb?: boolean; seed?: string}> = ({
  word,
  rgb = true,
  seed = 'dolly',
}) => {
  const footage = (
    <ShakeWrapper
      amplitude={11}
      rotationAmplitude={0.5}
      seed={`${seed}-shake`}
      envelope={(f) => 0.4 + 0.6 * Math.exp(-f / 13)}
    >
      <PunchZoom from={1.2} to={1.03}>
        <LoopedClip name="dolly_peach_16x9" loopFrames={60} />
      </PunchZoom>
    </ShakeWrapper>
  );
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      {rgb ? <RgbSplit maxOffset={30} durationInFrames={10}>{footage}</RgbSplit> : footage}
      <AbsoluteFill style={{background: gradients.inkVignette, opacity: 0.4}} />
      {word ? (
        <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
          <PunchWord text={word} size={165} />
        </AbsoluteFill>
      ) : null}
      <EmojiSticker emoji="🍑" x={82} y={22} size={150} startFrame={3} seed={`${seed}-sticker`} />
    </AbsoluteFill>
  );
};

/** Drop-2 strobe: triple split with the highlight rotating every beat. */
const TripleStrobe: React.FC = () => {
  const frame = useCurrentFrame();
  const fpb = framesPerBeat('hype');
  const beat = Math.floor(frame / fpb);
  const active = beat % 3;
  const panels = [
    imageSrc('heroPeach9x16'),
    imageSrc('heroGrapefruit9x16'),
    imageSrc('heroLemonMint9x16'),
  ];
  const beatPhase = (frame % fpb) / fpb;
  const pulse = 1.02 + 0.12 * Math.exp(-beatPhase * 4);
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <AbsoluteFill style={{flexDirection: 'row', gap: 6}}>
        {panels.map((src, i) => (
          <div key={i} style={{flex: 1, position: 'relative', overflow: 'hidden'}}>
            <CoverImage
              src={src}
              style={{transform: `scale(${i === active ? 1.28 : 1.08})`}}
            />
            <AbsoluteFill
              style={{backgroundColor: colors.ink, opacity: i === active ? 0 : 0.55}}
            />
          </div>
        ))}
      </AbsoluteFill>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <div
          style={{
            fontFamily: fontFamilies.display,
            fontSize: 380,
            letterSpacing: '0.08em',
            color: 'transparent',
            WebkitTextStroke: `6px ${colors.cream}`,
            transform: `scale(${pulse})`,
            opacity: 0.92,
          }}
        >
          EARLY
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** Full-bleed 16:9 cut with the copy set as a left-aligned typo block. */
const WideCut: React.FC<{
  src: string | null;
  word?: string;
  wordSize?: number;
  align?: 'center' | 'left';
  tilt?: number;
  rgb?: boolean;
  sticker?: StickerSpec;
  zoomFrom?: number;
  zoomTo?: number;
  shakeAmplitude?: number;
  seed?: string;
}> = ({
  src,
  word,
  wordSize = 150,
  align = 'center',
  tilt = 0,
  rgb = false,
  sticker,
  zoomFrom = 1.22,
  zoomTo = 1.05,
  shakeAmplitude = 8,
  seed = 'wide',
}) => (
  <ImpactCut
    src={src}
    rgb={rgb}
    sticker={sticker}
    zoomFrom={zoomFrom}
    zoomTo={zoomTo}
    shakeAmplitude={shakeAmplitude}
    seed={seed}
  >
    {word ? (
      align === 'center' ? (
        <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
          <PunchWord text={word} size={wordSize} tilt={tilt} />
        </AbsoluteFill>
      ) : (
        <div style={{position: 'absolute', left: 110, top: '58%'}}>
          <PunchWord
            text={word}
            size={wordSize}
            tilt={tilt}
            style={{justifyItems: 'start', textAlign: 'left'}}
          />
        </div>
      )
    ) : null}
  </ImpactCut>
);

// ---------------------------------------------------------------------------
// Drop-2 cut list (16:9 sources preferred; boundaries on the beat grid)
// ---------------------------------------------------------------------------

type WideCutSpec = {
  from: number;
  to: number;
  props: React.ComponentProps<typeof WideCut>;
};

const DROP2_CUTS: WideCutSpec[] = [
  {
    from: B(66),
    to: B(68),
    props: {
      src: renderStillSrc('stillGrapefruit16x9'),
      word: 'GRAPEFRUIT',
      wordSize: 160,
      tilt: 3,
      sticker: {emoji: '⚡', x: 20, y: 28, size: 130, delay: 1},
    },
  },
  {
    from: B(68),
    to: B(70),
    props: {
      src: renderStillSrc('stillLemonMint16x9'),
      word: 'ZITRONE-MINZE',
      wordSize: 140,
      tilt: -3,
      sticker: {emoji: '🫧', x: 80, y: 26, size: 130, delay: 1},
    },
  },
  {
    from: B(70),
    to: B(72),
    props: {
      src: imageSrc('splashGrapefruit16x9'),
      word: 'HYDRATION',
      wordSize: 170,
      shakeAmplitude: 13,
    },
  },
  {
    from: B(72),
    to: B(74),
    props: {
      src: imageSrc('lifestyleFriends16x9'),
      word: 'AESTHETIC',
      wordSize: 165,
      tilt: 2,
    },
  },
  {
    from: B(74),
    to: B(76),
    props: {
      src: renderStillSrc('stillPeach16x9'),
      word: 'ISOTONISCH',
      wordSize: 160,
      tilt: -2,
      zoomFrom: 1.02,
      zoomTo: 1.2,
    },
  },
  {
    from: B(76),
    to: B(78),
    props: {
      src: imageSrc('minimalFloat16x9'),
      word: 'KALORIENARM',
      wordSize: 150,
    },
  },
  {
    from: B(78),
    to: B(80),
    props: {
      src: renderStillSrc('trio16x9'),
      word: 'VITAMINE + ELEKTROLYTE',
      wordSize: 118,
      shakeAmplitude: 12,
    },
  },
];

// Global 2–3 frame flash frames on every hard cut (white/rosa alternating).
const WHITE_FLASHES = [DROP1, B(24), B(32), B(40), B(44), DROP2, B(68), B(72), B(76)];
const ROSE_FLASHES = [B(20), B(28), B(36), B(42), B(46), B(66), B(70), B(78), OUTRO];
const STROBE_FLASHES = new Array(8).fill(0).map((_, i) => B(80 + i));

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

/** 1920x1080 @ 30fps — registered as composition ID "EarlyHypeLandscape". */
export const HypeLandscape: React.FC = () => {
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <HypeAudio />

      {/* ---- Tease: fizz + countdown splits --------------------------- */}
      <Sequence durationInFrames={B(4)} name="Tease: Fizz">
        <TeaseFizzWide />
      </Sequence>
      <Sequence from={B(4)} durationInFrames={B(8) - B(4)} name="Tease: Hydration">
        <SplitCut
          media={<CoverImage src={imageSrc('pourGlass9x16')} />}
          word="HYDRATION"
          wordSize={150}
          mediaSide="left"
          badge="3"
          accent={colors.lime}
          seed="tease-1-l"
        />
      </Sequence>
      <Sequence from={B(8)} durationInFrames={B(12) - B(8)} name="Tease: Aber machs">
        <SplitCut
          media={<CoverImage src={imageSrc('bubblesUnderwater9x16')} />}
          word="ABER MACH'S"
          wordSize={135}
          mediaSide="right"
          badge="2"
          accent={colors.rose}
          seed="tease-2-l"
        />
      </Sequence>
      <Sequence from={B(12)} durationInFrames={B(15) - B(12)} name="Tease: Aesthetic">
        <TripleTease />
      </Sequence>
      <Sequence from={B(15)} durationInFrames={DROP1 - B(15)} name="Pre-drop flicker">
        <PreDropFlicker wordSize={260} />
      </Sequence>

      {/* ---- Drop 1: dolly impact + flavor splits --------------------- */}
      <Sequence from={DROP1} durationInFrames={B(20) - DROP1} name="Drop1 Dolly">
        <DollyImpact word="WEISSER PFIRSICH" seed="d1-dolly" />
      </Sequence>
      <Sequence from={B(20)} durationInFrames={B(24) - B(20)} name="Drop1 Turntable split">
        <SplitCut
          media={<LoopedClip name="turntable_peach_9x16" loopFrames={90} />}
          word={'WEISSER\nPFIRSICH'}
          wordSize={165}
          mediaSide="left"
          mediaWidth={38}
          accent={colors.rose}
          sticker={{emoji: '🍑', x: 88, y: 20, size: 140}}
          seed="d1-tt-l"
        />
      </Sequence>
      <Sequence from={B(24)} durationInFrames={B(28) - B(24)} name="Drop1 Grapefruit split">
        <SplitCut
          media={<CoverImage src={imageSrc('heroGrapefruit9x16')} />}
          word="GRAPEFRUIT"
          wordSize={150}
          mediaSide="right"
          accent={colors.coral}
          sticker={{emoji: '⚡', x: 14, y: 22, size: 140}}
          seed="d1-gf-l"
        />
      </Sequence>
      <Sequence from={B(28)} durationInFrames={B(32) - B(28)} name="Drop1 Lemonmint split">
        <SplitCut
          media={<CoverImage src={imageSrc('heroLemonMint9x16')} />}
          word={'ZITRONE-\nMINZE'}
          wordSize={165}
          mediaSide="left"
          accent={colors.lime}
          sticker={{emoji: '🫧', x: 86, y: 24, size: 140}}
          seed="d1-lm-l"
        />
      </Sequence>
      <Sequence from={B(32)} durationInFrames={B(36) - B(32)} name="Drop1 SpeedRamp">
        <SpeedRampScene src={imageSrc('splashGrapefruit16x9')} panPerFrame={0.06} baseZoom={1.14} />
      </Sequence>
      <Sequence from={B(36)} durationInFrames={B(40) - B(36)} name="Drop1 Vitamins">
        <WideCut
          src={imageSrc('lifestyleFriends16x9')}
          word={'VITAMINE +\nELEKTROLYTE'}
          wordSize={130}
          align="left"
          seed="d1-vit-l"
        />
      </Sequence>
      <Sequence from={B(40)} durationInFrames={B(42) - B(40)} name="Drop1 Isotonic">
        <WideCut
          src={imageSrc('minimalFloat16x9')}
          word="ISOTONISCH"
          wordSize={160}
          tilt={-2}
          seed="d1-iso-l"
        />
      </Sequence>
      <Sequence from={B(42)} durationInFrames={B(44) - B(42)} name="Drop1 Lowcal">
        <WideCut
          src={renderStillSrc('stillPeach16x9')}
          word="KALORIENARM"
          wordSize={150}
          tilt={2}
          seed="d1-cal-l"
        />
      </Sequence>
      <Sequence from={B(44)} durationInFrames={B(46) - B(44)} name="Drop1 Splash">
        <WideCut
          src={imageSrc('splashGrapefruit16x9')}
          zoomFrom={1.4}
          zoomTo={1.12}
          shakeAmplitude={15}
          seed="d1-splash-l"
        />
      </Sequence>
      <Sequence from={B(46)} durationInFrames={BREAK - B(46)} name="Drop1 Calm-down">
        <WideCut
          src={renderStillSrc('stillLemonMint16x9')}
          zoomFrom={1.12}
          zoomTo={1.18}
          shakeAmplitude={4}
          seed="d1-calm-l"
        />
      </Sequence>

      {/* ---- Break: slow zooms + side typo columns -------------------- */}
      <Sequence from={BREAK} durationInFrames={B(56) - BREAK} name="Break: Slogan">
        <AbsoluteFill style={{backgroundColor: colors.ink}}>
          <KenBurnsImage
            src={imageSrc('minimalFloat16x9')}
            from={{scale: 1.22, x: 2}}
            to={{scale: 1.05, x: 0}}
          />
          <AbsoluteFill
            style={{
              background: `linear-gradient(90deg, ${colors.ink}E6 0%, ${colors.ink}99 34%, transparent 62%)`,
            }}
          />
          <BubbleField count={22} color={colors.rose} opacity={0.4} seed="break-bubbles-l" />
          <AbsoluteFill
            style={{justifyContent: 'center', alignItems: 'flex-start', paddingLeft: 130}}
          >
            <Label color={colors.lime} style={{fontSize: 30, marginBottom: 34}}>
              <TypeReveal text="EARLY" startFrame={6} staggerFrames={3} />
            </Label>
            <Display style={{fontSize: 132, textAlign: 'left'}}>
              <TypeReveal text="HYDRATION" mode="words" startFrame={14} staggerFrames={7} />
            </Display>
            <Display style={{fontSize: 132, textAlign: 'left', marginTop: 12}}>
              <TypeReveal text="WITH BENEFITS" mode="words" startFrame={26} staggerFrames={7} />
            </Display>
          </AbsoluteFill>
        </AbsoluteFill>
      </Sequence>
      <Sequence from={B(56)} durationInFrames={DROP2 - B(56)} name="Break: Claims">
        <AbsoluteFill style={{backgroundColor: colors.ink}}>
          <KenBurnsImage
            src={renderStillSrc('trio16x9')}
            from={{scale: 1.04, x: -1}}
            to={{scale: 1.2, x: 1}}
          />
          <AbsoluteFill
            style={{
              background: `linear-gradient(270deg, ${colors.ink}E6 0%, ${colors.ink}99 34%, transparent 62%)`,
            }}
          />
          <AbsoluteFill
            style={{justifyContent: 'center', alignItems: 'flex-end', paddingRight: 150}}
          >
            <ClaimsStack
              claims={['VITAMINE + ELEKTROLYTE', 'ISOTONISCH', 'KALORIENARM']}
              fontSize={88}
              align="flex-start"
              startFrame={10}
              staggerFrames={17}
            />
          </AbsoluteFill>
        </AbsoluteFill>
      </Sequence>

      {/* ---- Drop 2: fastest montage ---------------------------------- */}
      <Sequence from={DROP2} durationInFrames={B(66) - DROP2} name="Drop2 Dolly">
        <DollyImpact word="WEISSER PFIRSICH" seed="d2-dolly" />
      </Sequence>
      {DROP2_CUTS.map((c, i) => (
        <Sequence key={`d2-${i}`} from={c.from} durationInFrames={c.to - c.from} name={`Drop2 ${i}`}>
          <WideCut {...c.props} seed={`d2-${i}-l`} />
        </Sequence>
      ))}
      <Sequence from={B(80)} durationInFrames={B(88) - B(80)} name="Triple strobe">
        <TripleStrobe />
      </Sequence>
      <Sequence from={B(88)} durationInFrames={OUTRO - B(88)} name="Letter slam">
        <LetterSlam
          backgroundSrc={renderStillSrc('stillPeach16x9')}
          letterSize={330}
          letterGap={0.24}
        />
      </Sequence>

      {/* ---- Outro: lineup + CTA endcard ------------------------------ */}
      <Sequence from={OUTRO} name="Endcard">
        <Endcard aspect="landscape" lineupSrc={imageSrc('lineup16x9')} />
      </Sequence>

      {/* ---- Global overlays ------------------------------------------ */}
      <BubbleField count={12} color={colors.cream} opacity={0.13} seed="global-bubbles-l" />
      <FlashFrame at={WHITE_FLASHES} durationInFrames={3} peak={0.92} />
      <FlashFrame at={ROSE_FLASHES} durationInFrames={3} color={colors.rose} peak={0.85} />
      <FlashFrame at={STROBE_FLASHES} durationInFrames={2} peak={0.45} />
      <BrandWatermark position="top-right" tone="light" sub="@drink.early" />
      <GrainOverlay opacity={0.09} />
    </AbsoluteFill>
  );
};
