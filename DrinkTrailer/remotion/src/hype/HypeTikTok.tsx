/**
 * EarlyHypeTikTok — 1080x1920 @ 30fps, 48s.
 *
 * Overedited TikTok/IG brand-edit, cut beat-precise on the hype_track grid:
 *   0–206      tease: fizz-open macro + countdown 3-2-1
 *              ("HYDRATION → ABER MACH'S → AESTHETIC") + pre-drop flicker
 *   206 drop1  impact cut → flavor chapters + turntable loop + speed-ramp
 *   617 break  calm slow zooms: slogan + claims stack
 *   823 drop2  fastest montage: 2-beat cuts → 1-beat strobe → EARLY letter slam
 *   1234 outro lineup + CTA endcard (safe zone: bottom 15% copy-free)
 */
import React from 'react';
import {AbsoluteFill, Sequence, useCurrentFrame} from 'remotion';
import {imageSrc} from '../lib/assets';
import {framesPerBeat} from '../lib/beats';
import {BrandWatermark} from '../shared/BrandWatermark';
import {fontFamilies} from '../shared/fonts';
import {BubbleField} from '../shared/motion/BubbleField';
import {GlitchZoom} from '../shared/motion/GlitchZoom';
import {GrainOverlay} from '../shared/motion/GrainOverlay';
import {KenBurnsImage} from '../shared/motion/KenBurnsImage';
import {TypeReveal} from '../shared/motion/TypeReveal';
import {Display, Label} from '../shared/Typography';
import {colors, gradients} from '../shared/tokens';
import {EmojiSticker} from './fx/EmojiSticker';
import {FlashFrame} from './fx/FlashFrame';
import {LoopedClip} from './fx/LoopedClip';
import {PunchWord} from './fx/PunchWord';
import {PunchZoom} from './fx/PunchZoom';
import {renderStillSrc} from './hypeAssets';
import {HypeAudio} from './HypeAudio';
import {
  CountdownBadge,
  CoverImage,
  Endcard,
  ImpactCut,
  LetterSlam,
  PreDropFlicker,
  ClaimsStack,
  SpeedRampScene,
} from './scenes/common';
import type {ImpactCutProps} from './scenes/common';
import {B, BREAK, DROP1, DROP2, OUTRO} from './timeline';

// ---------------------------------------------------------------------------
// Tease (0 → drop1)
// ---------------------------------------------------------------------------

const TeaseFizz: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: colors.ink}}>
    <GlitchZoom zoomFrom={1.04} zoomTo={1.16} intensity={0.55} settleAfter={22} seed="tease-fizz">
      <CoverImage src={imageSrc('macroCondensation9x16')} />
    </GlitchZoom>
    <AbsoluteFill style={{background: gradients.inkVignette, opacity: 0.8}} />
    <BubbleField count={26} color={colors.cream} opacity={0.4} seed="tease-bubbles" />
    <EmojiSticker emoji="🫧" x={70} y={22} size={160} startFrame={6} seed="tease-fizz-sticker" />
  </AbsoluteFill>
);

// ---------------------------------------------------------------------------
// Drop-2 strobe (1-beat cuts) with a pulsing outlined EARLY on top
// ---------------------------------------------------------------------------

const StrobeCut: React.FC<{src: string | null; index: number}> = ({src, index}) => (
  <AbsoluteFill style={{backgroundColor: colors.ink, overflow: 'hidden'}}>
    <CoverImage
      src={src}
      style={{transform: `scale(${index % 2 === 0 ? 1.16 : 1.38}) rotate(${index % 2 === 0 ? -1 : 1}deg)`}}
    />
    <AbsoluteFill
      style={{
        backgroundColor: index % 2 === 0 ? colors.rose : colors.lime,
        opacity: 0.12,
        mixBlendMode: 'overlay',
      }}
    />
  </AbsoluteFill>
);

const StrobeOverlay: React.FC = () => {
  const frame = useCurrentFrame();
  const fpb = framesPerBeat('hype');
  const beatPhase = (frame % fpb) / fpb;
  const scale = 1.02 + 0.12 * Math.exp(-beatPhase * 4);
  return (
    <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
      <div
        style={{
          fontFamily: fontFamilies.display,
          fontSize: 330,
          letterSpacing: '0.06em',
          color: 'transparent',
          WebkitTextStroke: `6px ${colors.cream}`,
          transform: `scale(${scale})`,
          opacity: 0.9,
        }}
      >
        EARLY
      </div>
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------
// Cut lists (all boundaries snapped to the exact beat grid)
// ---------------------------------------------------------------------------

type PortraitCut = {from: number; to: number; cut: Omit<ImpactCutProps, 'seed'>};

const DROP1_CUTS: PortraitCut[] = [
  {
    from: DROP1,
    to: B(20),
    cut: {
      src: imageSrc('heroPeach9x16'),
      word: 'WEISSER\nPFIRSICH',
      wordSize: 175,
      rgb: true,
      shakeAmplitude: 14,
      sticker: {emoji: '🍑', x: 76, y: 24, size: 150},
    },
  },
  {
    from: B(24),
    to: B(28),
    cut: {
      src: imageSrc('heroGrapefruit9x16'),
      word: 'GRAPEFRUIT',
      wordSize: 158,
      tilt: -3,
      sticker: {emoji: '⚡', x: 74, y: 27, size: 140},
    },
  },
  {
    from: B(28),
    to: B(32),
    cut: {
      src: imageSrc('heroLemonMint9x16'),
      word: 'ZITRONE-MINZE',
      wordSize: 132,
      tilt: 2,
      sticker: {emoji: '🫧', x: 26, y: 26, size: 140},
    },
  },
  {
    from: B(36),
    to: B(40),
    cut: {
      src: imageSrc('lifestyleGym9x16'),
      word: 'VITAMINE +\nELEKTROLYTE',
      wordSize: 130,
    },
  },
  {
    from: B(40),
    to: B(42),
    cut: {src: imageSrc('pourGlass9x16'), word: 'ISOTONISCH', wordSize: 150, tilt: -2},
  },
  {
    from: B(42),
    to: B(44),
    cut: {src: imageSrc('macroCondensation9x16'), word: 'KALORIENARM', wordSize: 140, tilt: 2},
  },
  {
    from: B(44),
    to: B(46),
    cut: {src: imageSrc('splashPeach9x16'), shakeAmplitude: 15, zoomFrom: 1.34},
  },
  {
    from: B(46),
    to: BREAK,
    cut: {src: imageSrc('bubblesUnderwater9x16'), zoomFrom: 1.12, zoomTo: 1.2, shakeAmplitude: 5},
  },
];

const DROP2_CUTS: PortraitCut[] = [
  {
    from: B(64),
    to: B(66),
    cut: {
      src: imageSrc('heroPeach9x16'),
      word: 'WEISSER PFIRSICH',
      wordSize: 118,
      rgb: true,
      shakeAmplitude: 14,
      sticker: {emoji: '🍑', x: 78, y: 26, size: 120, delay: 1},
    },
  },
  {
    from: B(66),
    to: B(68),
    cut: {
      src: imageSrc('heroGrapefruit9x16'),
      word: 'GRAPEFRUIT',
      wordSize: 150,
      tilt: 3,
      sticker: {emoji: '⚡', x: 24, y: 26, size: 120, delay: 1},
    },
  },
  {
    from: B(68),
    to: B(70),
    cut: {
      src: imageSrc('heroLemonMint9x16'),
      word: 'ZITRONE-MINZE',
      wordSize: 128,
      tilt: -3,
      sticker: {emoji: '🫧', x: 75, y: 25, size: 120, delay: 1},
    },
  },
  {
    from: B(72),
    to: B(74),
    cut: {src: renderStillSrc('stillPeach9x16'), word: 'ISOTONISCH', wordSize: 150, tilt: 2},
  },
  {
    from: B(74),
    to: B(76),
    cut: {
      src: renderStillSrc('stillGrapefruit9x16'),
      word: 'KALORIENARM',
      wordSize: 140,
      tilt: -2,
      zoomFrom: 1.02,
      zoomTo: 1.2,
    },
  },
  {
    from: B(76),
    to: B(78),
    cut: {
      src: renderStillSrc('stillLemonMint9x16'),
      word: 'VITAMINE +\nELEKTROLYTE',
      wordSize: 118,
    },
  },
  {
    from: B(78),
    to: B(80),
    cut: {
      src: imageSrc('splashPeach9x16'),
      word: 'AESTHETIC',
      wordSize: 165,
      shakeAmplitude: 14,
      sticker: {emoji: '⚡', x: 72, y: 68, size: 120, delay: 1},
    },
  },
];

const STROBE_IMAGES: (string | null)[] = [
  imageSrc('splashLemonMint9x16'),
  imageSrc('macroCondensation9x16'),
  imageSrc('splashPeach9x16'),
  imageSrc('bubblesUnderwater9x16'),
  imageSrc('heroPeach9x16'),
  imageSrc('pourGlass9x16'),
  imageSrc('splashGrapefruit16x9'),
  imageSrc('lifestyleGym9x16'),
];

// Global 2–3 frame flash frames on every hard cut (white/rosa alternating).
const WHITE_FLASHES = [DROP1, B(24), B(32), B(40), B(44), DROP2, B(68), B(72), B(76)];
const ROSE_FLASHES = [B(20), B(28), B(36), B(42), B(46), B(66), B(70), B(78), OUTRO];
const STROBE_FLASHES = new Array(8).fill(0).map((_, i) => B(80 + i));

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

/** 1080x1920 @ 30fps — registered as composition ID "EarlyHypeTikTok". */
export const HypeTikTok: React.FC = () => {
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <HypeAudio />

      {/* ---- Tease: fizz + countdown --------------------------------- */}
      <Sequence durationInFrames={B(4)} name="Tease: Fizz">
        <TeaseFizz />
      </Sequence>
      <Sequence from={B(4)} durationInFrames={B(8) - B(4)} name="Tease: Hydration">
        <ImpactCut
          src={imageSrc('pourGlass9x16')}
          word="HYDRATION"
          wordSize={168}
          shakeAmplitude={6}
          zoomFrom={1.2}
          seed="tease-1"
        >
          <CountdownBadge n="3" x={50} y={21} />
        </ImpactCut>
      </Sequence>
      <Sequence from={B(8)} durationInFrames={B(12) - B(8)} name="Tease: Aber machs">
        <ImpactCut
          src={imageSrc('bubblesUnderwater9x16')}
          word="ABER MACH'S"
          wordSize={148}
          shakeAmplitude={6}
          zoomFrom={1.02}
          zoomTo={1.18}
          seed="tease-2"
        >
          <CountdownBadge n="2" x={50} y={21} />
        </ImpactCut>
      </Sequence>
      <Sequence from={B(12)} durationInFrames={B(15) - B(12)} name="Tease: Aesthetic">
        <ImpactCut
          src={imageSrc('minimalFloat9x16')}
          word="AESTHETIC"
          wordSize={172}
          shakeAmplitude={7}
          tilt={-2}
          seed="tease-3"
        >
          <CountdownBadge n="1" x={50} y={21} />
        </ImpactCut>
      </Sequence>
      <Sequence from={B(15)} durationInFrames={DROP1 - B(15)} name="Pre-drop flicker">
        <PreDropFlicker wordSize={210} />
      </Sequence>

      {/* ---- Drop 1: flavor chapters --------------------------------- */}
      {DROP1_CUTS.map((c, i) => (
        <Sequence key={`d1-${i}`} from={c.from} durationInFrames={c.to - c.from} name={`Drop1 ${i}`}>
          <ImpactCut {...c.cut} seed={`d1-${i}`} />
        </Sequence>
      ))}
      <Sequence from={B(20)} durationInFrames={B(24) - B(20)} name="Drop1 Turntable">
        <AbsoluteFill style={{backgroundColor: colors.ink}}>
          <PunchZoom from={1.3} to={1.1}>
            <LoopedClip name="turntable_peach_9x16" loopFrames={90} />
          </PunchZoom>
          <AbsoluteFill style={{background: gradients.bottomScrim, opacity: 0.7}} />
          <div
            style={{
              position: 'absolute',
              left: 0,
              right: 0,
              // Caption sits at ~70% word-center — clear of the bottom 20% zone.
              top: '68%',
              display: 'flex',
              justifyContent: 'center',
            }}
          >
            <PunchWord text="WEISSER PFIRSICH" size={92} startFrame={2} />
          </div>
          <EmojiSticker emoji="🍑" x={22} y={18} size={130} startFrame={3} seed="tt-peach" />
        </AbsoluteFill>
      </Sequence>
      <Sequence from={B(32)} durationInFrames={B(36) - B(32)} name="Drop1 SpeedRamp">
        <SpeedRampScene src={imageSrc('splashLemonMint9x16')} />
      </Sequence>

      {/* ---- Break: calm slogan + claims ------------------------------ */}
      <Sequence from={BREAK} durationInFrames={B(56) - BREAK} name="Break: Slogan">
        <AbsoluteFill style={{backgroundColor: colors.ink}}>
          <KenBurnsImage
            src={imageSrc('bubblesUnderwater9x16')}
            from={{scale: 1.26}}
            to={{scale: 1.06}}
          />
          <AbsoluteFill style={{background: gradients.inkVignette, opacity: 0.75}} />
          <BubbleField count={30} color={colors.rose} opacity={0.45} seed="break-bubbles" />
          <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', gap: 34}}>
            <Label color={colors.lime} style={{fontSize: 32}}>
              <TypeReveal text="EARLY" startFrame={6} staggerFrames={3} />
            </Label>
            <Display style={{fontSize: 122, textAlign: 'center'}}>
              <TypeReveal text="HYDRATION" mode="words" startFrame={14} staggerFrames={7} />
            </Display>
            <Display style={{fontSize: 122, textAlign: 'center'}}>
              <TypeReveal text="WITH BENEFITS" mode="words" startFrame={26} staggerFrames={7} />
            </Display>
          </AbsoluteFill>
        </AbsoluteFill>
      </Sequence>
      <Sequence from={B(56)} durationInFrames={DROP2 - B(56)} name="Break: Claims">
        <AbsoluteFill style={{backgroundColor: colors.ink}}>
          <KenBurnsImage
            src={imageSrc('minimalFloat9x16')}
            from={{scale: 1.04}}
            to={{scale: 1.22}}
          />
          <AbsoluteFill style={{background: gradients.inkVignette, opacity: 0.7}} />
          <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
            <ClaimsStack
              claims={['VITAMINE + ELEKTROLYTE', 'ISOTONISCH', 'KALORIENARM']}
              fontSize={96}
              startFrame={10}
              staggerFrames={17}
            />
          </AbsoluteFill>
        </AbsoluteFill>
      </Sequence>

      {/* ---- Drop 2: fastest montage ---------------------------------- */}
      {DROP2_CUTS.map((c, i) => (
        <Sequence key={`d2-${i}`} from={c.from} durationInFrames={c.to - c.from} name={`Drop2 ${i}`}>
          <ImpactCut {...c.cut} seed={`d2-${i}`} />
        </Sequence>
      ))}
      <Sequence from={B(70)} durationInFrames={B(72) - B(70)} name="Drop2 Turntable">
        <AbsoluteFill style={{backgroundColor: colors.ink}}>
          <PunchZoom from={1.42} to={1.16}>
            <LoopedClip name="turntable_peach_9x16" loopFrames={90} />
          </PunchZoom>
          <div
            style={{
              position: 'absolute',
              left: 0,
              right: 0,
              top: '44%',
              transform: 'translateY(-50%)',
              display: 'flex',
              justifyContent: 'center',
            }}
          >
            <PunchWord text="HYDRATION" size={155} />
          </div>
        </AbsoluteFill>
      </Sequence>
      {STROBE_IMAGES.map((src, i) => (
        <Sequence
          key={`strobe-${i}`}
          from={B(80 + i)}
          durationInFrames={B(81 + i) - B(80 + i)}
          name={`Strobe ${i}`}
        >
          <StrobeCut src={src} index={i} />
        </Sequence>
      ))}
      <Sequence from={B(80)} durationInFrames={B(88) - B(80)} name="Strobe overlay">
        <StrobeOverlay />
      </Sequence>
      <Sequence from={B(88)} durationInFrames={OUTRO - B(88)} name="Letter slam">
        <LetterSlam backgroundSrc={imageSrc('splashPeach9x16')} letterSize={300} />
      </Sequence>

      {/* ---- Outro: staggered can fan + CTA endcard ------------------- */}
      <Sequence from={OUTRO} name="Endcard">
        <Endcard
          aspect="portrait"
          lineupSrc={imageSrc('lineup9x16')}
          canSrcs={[
            renderStillSrc('stillGrapefruit9x16'),
            renderStillSrc('stillPeach9x16'),
            renderStillSrc('stillLemonMint9x16'),
          ]}
        />
      </Sequence>

      {/* ---- Global overlays ------------------------------------------ */}
      <BubbleField count={12} color={colors.cream} opacity={0.14} seed="global-bubbles" />
      <FlashFrame at={WHITE_FLASHES} durationInFrames={3} peak={0.92} />
      <FlashFrame at={ROSE_FLASHES} durationInFrames={3} color={colors.rose} peak={0.85} />
      <FlashFrame at={STROBE_FLASHES} durationInFrames={2} peak={0.45} />
      <BrandWatermark position="top-right" tone="light" sub="@drink.early" />
      <GrainOverlay opacity={0.09} />
    </AbsoluteFill>
  );
};
