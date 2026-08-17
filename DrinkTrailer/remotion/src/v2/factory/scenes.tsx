/**
 * Scene renderers for the v2 TrailerFactory — one renderer per SceneKind.
 * Every renderer works purely from the TrailerStyleConfig (palette, fonts,
 * copy) + defensive assets2 lookups, so any config renders end-to-end even
 * while assets/music are still being produced.
 */
import React from 'react';
import type {CSSProperties, PropsWithChildren} from 'react';
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {BOTTOM_SAFE_FRACTION, CTA_LINE} from '../config/types';
import type {SceneSpec, TrailerStyleConfig} from '../config/types';
import {imageSrc2, productStill2, renderSrc2} from '../lib/assets2';
import {fontPair} from '../lib/fonts2';
import {CollageCutout} from '../fx/CollageCutout';
import {InfiniteZoom} from '../fx/InfiniteZoom';
import {KineticType} from '../fx/KineticType';
import {NeonGlowText} from '../fx/NeonGlowText';
import {SpeedRampClip} from '../fx/SpeedRampClip';
import {SplitGrid} from '../fx/SplitGrid';
import type {SplitVariant} from '../fx/SplitGrid';

// ---------------------------------------------------------------------------
// Context handed to every scene renderer by the factory
// ---------------------------------------------------------------------------

export type SceneContext = {
  config: TrailerStyleConfig;
  scene: SceneSpec;
  sceneIndex: number;
  /** This scene's length in frames (excluding transition overlap). */
  durationInFrames: number;
  /** Frames per beat of the resolved track. */
  framesPerBeat: number;
  /** The next line from copy.mid this scene may consume (round-robin). */
  midLine: string | null;
};

// Brand flavor constants (lineup/endcard chips — independent of palette).
const FLAVORS = [
  {name: 'PFIRSICH', color: '#E7B7B7', image: 'heroPeach'},
  {name: 'GRAPEFRUIT', color: '#F2AC8F', image: 'heroGrapefruit'},
  {name: 'ZITRONE-MINZE', color: '#CBD97A', image: 'heroLemonMint'},
] as const;

/** Media-frame loop points (frames @60fps) for the known Blender clips. */
const RENDER_LOOP_FRAMES: Record<string, number> = {
  turntablePeach: 170,
  dollyPeach16x9: 112,
};

const relativeLuminance = (hex: string): number => {
  const m = hex.replace('#', '');
  const full = m.length === 3 ? m.split('').map((c) => c + c).join('') : m;
  const int = parseInt(full.slice(0, 6), 16);
  if (Number.isNaN(int)) return 0.5;
  const r = (int >> 16) & 255;
  const g = (int >> 8) & 255;
  const b = int & 255;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
};

export const isDarkColor = (hex: string): boolean => relativeLuminance(hex) < 0.45;

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

type CoverProps = {
  src: string | null;
  from?: {scale?: number; x?: number; y?: number};
  to?: {scale?: number; x?: number; y?: number};
  fallback: string;
  easing?: (t: number) => number;
};

/** Full-bleed image with a slow zoom/pan; palette-gradient fallback plane. */
const Cover: React.FC<PropsWithChildren<CoverProps>> = ({
  src,
  from = {scale: 1.06},
  to = {scale: 1.2},
  fallback,
  easing = Easing.inOut(Easing.quad),
  children,
}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const p = interpolate(frame, [0, Math.max(1, durationInFrames - 1)], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing,
  });
  const lerp = (a = 0, b = 0) => a + (b - a) * p;
  if (!src) {
    return <AbsoluteFill style={{background: fallback}}>{children}</AbsoluteFill>;
  }
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Img
        src={src}
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform: `scale(${lerp(from.scale ?? 1, to.scale ?? 1)}) translate(${lerp(from.x, to.x)}%, ${lerp(from.y, to.y)}%)`,
        }}
      />
      {children}
    </AbsoluteFill>
  );
};

const paletteGradient = (c: TrailerStyleConfig): string =>
  `linear-gradient(165deg, ${c.palette.accent} 0%, ${c.palette.bg} 58%, ${c.palette.accent2} 130%)`;

/**
 * Content area that respects the bottom TikTok safe zone. NOTE: CSS
 * percentage padding resolves against the WIDTH, so the bottom padding is
 * computed in px from the composition height (20% of 1920 = 384px).
 */
const SafeArea: React.FC<PropsWithChildren<{style?: CSSProperties}>> = ({style, children}) => {
  const {width, height} = useVideoConfig();
  return (
    <AbsoluteFill
      style={{
        paddingBottom: height * BOTTOM_SAFE_FRACTION,
        paddingLeft: width * 0.07,
        paddingRight: width * 0.07,
        paddingTop: height * 0.06,
        boxSizing: 'border-box',
        ...style,
      }}
    >
      {children}
    </AbsoluteFill>
  );
};

const BottomScrim: React.FC<{color: string}> = ({color}) => (
  <AbsoluteFill
    style={{
      background: `linear-gradient(180deg, transparent 42%, ${color}E8 100%)`,
      pointerEvents: 'none',
    }}
  />
);

/** Small uppercase kicker line (brand claim). */
const Kicker: React.FC<{ctx: SceneContext; text: string; style?: CSSProperties}> = ({
  ctx,
  text,
  style,
}) => {
  const frame = useCurrentFrame();
  const pair = fontPair(ctx.config.fontPreset);
  const opacity = interpolate(frame, [4, 18], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return (
    <div
      style={{
        fontFamily: pair.body,
        fontWeight: 600,
        fontSize: 30,
        letterSpacing: '0.34em',
        textTransform: 'uppercase',
        color: ctx.config.palette.accent,
        opacity,
        ...style,
      }}
    >
      {text}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Scene renderers
// ---------------------------------------------------------------------------

const HeroScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const {config, scene, framesPerBeat} = ctx;
  return (
    <Cover
      src={imageSrc2(scene.assetKey ?? 'heroPeach')}
      from={{scale: 1.08}}
      to={{scale: 1.22, y: -1.5}}
      fallback={paletteGradient(config)}
    >
      <BottomScrim color={config.palette.bg} />
      <SafeArea style={{justifyContent: 'flex-end', alignItems: 'center', gap: 26}}>
        <Kicker ctx={ctx} text="EARLY — SPARKLING VITAMIN DRINK" />
        <KineticType
          text={scene.text ?? config.copy.hook}
          mode="slam"
          fontPreset={config.fontPreset}
          color={config.palette.ink}
          accentColor={config.palette.accent}
          framesPerUnit={Math.max(4, Math.round(framesPerBeat / 2))}
        />
      </SafeArea>
    </Cover>
  );
};

const SplashScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const {config, scene} = ctx;
  const word = scene.text ?? ctx.midLine ?? 'FRISCHE!';
  const pop = spring({frame: frame - 4, fps, config: {damping: 10, stiffness: 200, mass: 0.8}});
  const pair = fontPair(config.fontPreset);
  return (
    <Cover
      src={imageSrc2(scene.assetKey ?? 'splashPeach')}
      from={{scale: 1.34}}
      to={{scale: 1.06}}
      fallback={paletteGradient(config)}
      easing={Easing.out(Easing.exp)}
    >
      <AbsoluteFill
        style={{
          background: `radial-gradient(60% 34% at 50% 55%, ${config.palette.accent}55 0%, transparent 70%)`,
        }}
      />
      <SafeArea style={{justifyContent: 'center', alignItems: 'center'}}>
        {frame >= 4 ? (
          <div
            style={{
              fontFamily: pair.display,
              ...pair.displayStyle,
              fontSize: Math.min(230, 1250 / Math.max(4, word.replace(/\*/g, '').length)),
              letterSpacing: pair.displayTracking,
              textTransform: pair.uppercase ? 'uppercase' : 'none',
              color: config.palette.ink,
              transform: `scale(${0.6 + 0.4 * pop}) rotate(${(1 - pop) * -6}deg)`,
              opacity: Math.min(1, pop * 1.8),
              textShadow: `0 10px 60px ${config.palette.bg}CC, 0 0 90px ${config.palette.accent}66`,
              textAlign: 'center',
            }}
          >
            {word.replace(/\*/g, '')}
          </div>
        ) : null}
      </SafeArea>
    </Cover>
  );
};

const MacroScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const {config, scene} = ctx;
  const pair = fontPair(config.fontPreset);
  const caption = scene.text ?? ctx.midLine ?? 'EISKALT. SPRITZIG.';
  return (
    <Cover
      src={imageSrc2(scene.assetKey ?? 'macroCondensation')}
      from={{scale: 1.16, x: 1}}
      to={{scale: 1.3, x: -1}}
      fallback={paletteGradient(config)}
    >
      <BottomScrim color={config.palette.bg} />
      <SafeArea style={{justifyContent: 'flex-end', alignItems: 'flex-start', gap: 18}}>
        <div style={{width: 84, height: 6, backgroundColor: config.palette.accent}} />
        <div
          style={{
            fontFamily: pair.body,
            fontWeight: 600,
            fontSize: 44,
            letterSpacing: '0.16em',
            textTransform: 'uppercase',
            color: config.palette.ink,
            maxWidth: '80%',
          }}
        >
          {caption}
        </div>
      </SafeArea>
    </Cover>
  );
};

const LifestyleScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const {config, scene} = ctx;
  const line = scene.text ?? ctx.midLine ?? config.copy.hook;
  return (
    <Cover
      src={imageSrc2(scene.assetKey ?? 'picnic')}
      from={{scale: 1.18, x: -2.5}}
      to={{scale: 1.18, x: 2.5}}
      fallback={paletteGradient(config)}
      easing={Easing.inOut(Easing.cubic)}
    >
      <BottomScrim color={config.palette.bg} />
      <SafeArea style={{justifyContent: 'flex-end', alignItems: 'center'}}>
        <KineticType
          text={line}
          mode="lines"
          fontPreset={config.fontPreset}
          color={config.palette.ink}
          accentColor={config.palette.accent}
          fontSize={78}
          framesPerUnit={Math.max(5, Math.round(ctx.framesPerBeat))}
        />
      </SafeArea>
    </Cover>
  );
};

const LineupScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const {config, scene} = ctx;
  const pair = fontPair(config.fontPreset);

  if (scene.variant === 'grid') {
    return (
      <AbsoluteFill style={{backgroundColor: config.palette.bg}}>
        <SplitGrid
          variant="3v"
          background={config.palette.bg}
          gapPx={8}
          staggerFrames={Math.max(3, Math.round(ctx.framesPerBeat / 2))}
          cells={FLAVORS.map((flavor) => (
            <AbsoluteFill key={flavor.name} style={{backgroundColor: flavor.color}}>
              <Cover
                src={imageSrc2(flavor.image)}
                from={{scale: 1.05}}
                to={{scale: 1.16}}
                fallback={`linear-gradient(180deg, ${flavor.color}, ${config.palette.bg})`}
              />
              <div
                style={{
                  position: 'absolute',
                  bottom: '24%',
                  left: 0,
                  right: 0,
                  textAlign: 'center',
                  fontFamily: pair.body,
                  fontWeight: 600,
                  fontSize: 26,
                  letterSpacing: '0.2em',
                  color: '#fff',
                  textShadow: '0 2px 14px rgba(0,0,0,0.6)',
                }}
              >
                {flavor.name}
              </div>
            </AbsoluteFill>
          ))}
        />
      </AbsoluteFill>
    );
  }

  return (
    <Cover
      src={imageSrc2(scene.assetKey ?? 'lineup')}
      from={{scale: 1.12}}
      to={{scale: 1.04}}
      fallback={paletteGradient(config)}
    >
      <BottomScrim color={config.palette.bg} />
      <SafeArea style={{justifyContent: 'flex-end', alignItems: 'center', gap: 24}}>
        <div style={{display: 'flex', gap: 20}}>
          {FLAVORS.map((flavor, i) => {
            const p = spring({
              frame: frame - i * Math.max(3, Math.round(ctx.framesPerBeat / 2)),
              fps,
              config: {damping: 13, stiffness: 170},
            });
            return (
              <div
                key={flavor.name}
                style={{
                  transform: `scale(${p})`,
                  backgroundColor: flavor.color,
                  color: '#2A2A2A',
                  fontFamily: pair.body,
                  fontWeight: 600,
                  fontSize: 27,
                  letterSpacing: '0.12em',
                  padding: '14px 26px',
                  borderRadius: 999,
                }}
              >
                {flavor.name}
              </div>
            );
          })}
        </div>
        <div
          style={{
            fontFamily: pair.body,
            fontWeight: 500,
            fontSize: 30,
            letterSpacing: '0.22em',
            textTransform: 'uppercase',
            color: config.palette.ink,
            opacity: 0.85,
          }}
        >
          DREI SORTEN. NULL KOMPROMISSE.
        </div>
      </SafeArea>
    </Cover>
  );
};

const TypeScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const {config, scene} = ctx;
  if (scene.variant === 'neon') {
    return (
      <AbsoluteFill
        style={{
          backgroundColor: config.palette.bg,
          background: `radial-gradient(80% 50% at 50% 42%, ${config.palette.accent}14 0%, ${config.palette.bg} 70%)`,
        }}
      >
        <SafeArea style={{justifyContent: 'center', alignItems: 'center'}}>
          <NeonGlowText
            text={scene.text ?? ctx.midLine ?? config.copy.hook}
            color={config.palette.accent}
            altColor={config.palette.accent2}
            fontPreset={config.fontPreset}
            fontSize={128}
            startAt={4}
          />
        </SafeArea>
      </AbsoluteFill>
    );
  }
  const mode =
    scene.variant === 'lines' || scene.variant === 'tracking' || scene.variant === 'slam'
      ? scene.variant
      : 'slam';
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(90% 60% at 50% 40%, ${config.palette.bg} 55%, ${config.palette.bg}DD 100%)`,
        backgroundColor: config.palette.bg,
      }}
    >
      <SafeArea style={{justifyContent: 'center', alignItems: 'center'}}>
        <KineticType
          text={scene.text ?? ctx.midLine ?? config.copy.hook}
          mode={mode}
          fontPreset={config.fontPreset}
          color={config.palette.ink}
          accentColor={config.palette.accent}
          framesPerUnit={Math.max(4, Math.round(ctx.framesPerBeat / 2))}
        />
      </SafeArea>
    </AbsoluteFill>
  );
};

const Render3dScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const {config, scene, durationInFrames} = ctx;
  const key = scene.assetKey ?? 'turntablePeach';
  const src = renderSrc2(key);
  const loop = RENDER_LOOP_FRAMES[key] ?? 110;
  const pair = fontPair(config.fontPreset);
  return (
    <SpeedRampClip
      src={src}
      segments={[
        {fromFrame: 0, speed: 0.55},
        {fromFrame: Math.round(durationInFrames * 0.3), speed: 1.9},
        {fromFrame: Math.round(durationInFrames * 0.68), speed: 0.7},
      ]}
      loopAfterFrames={loop}
      fallbackBackground={paletteGradient(config)}
    >
      <AbsoluteFill
        style={{
          background: `radial-gradient(110% 80% at 50% 45%, transparent 55%, ${config.palette.bg}B3 100%)`,
          pointerEvents: 'none',
        }}
      />
      <SafeArea style={{justifyContent: 'flex-end', alignItems: 'center'}}>
        <div
          style={{
            fontFamily: pair.body,
            fontWeight: 600,
            fontSize: 32,
            letterSpacing: '0.3em',
            textTransform: 'uppercase',
            color: config.palette.ink,
            textShadow: `0 2px 18px ${config.palette.bg}`,
          }}
        >
          {scene.text ?? 'HYDRATION WITH BENEFITS'}
        </div>
      </SafeArea>
    </SpeedRampClip>
  );
};

const IngredientsScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const {config, scene} = ctx;
  const pair = fontPair(config.fontPreset);
  const items = (scene.text ?? 'ISOTONISCH|KALORIENARM|VITAMINE + ELEKTROLYTE')
    .split('|')
    .map((s) => s.trim())
    .filter(Boolean);
  const step = Math.max(6, Math.round(ctx.framesPerBeat));
  return (
    <AbsoluteFill style={{backgroundColor: config.palette.bg}}>
      <SafeArea style={{justifyContent: 'center', gap: 0}}>
        <Kicker ctx={ctx} text="WAS DRIN IST" style={{marginBottom: 48}} />
        {items.map((item, i) => {
          const at = 10 + i * step;
          const p = spring({frame: frame - at, fps, config: {damping: 15, stiffness: 140}});
          return (
            <div key={i} style={{overflow: 'hidden', borderBottom: `2px solid ${config.palette.ink}22`}}>
              <div
                style={{
                  display: 'flex',
                  alignItems: 'baseline',
                  gap: 28,
                  padding: '30px 0',
                  transform: `translateY(${(1 - p) * 105}%)`,
                  opacity: frame >= at ? 1 : 0,
                }}
              >
                <span
                  style={{
                    fontFamily: pair.body,
                    fontWeight: 600,
                    fontSize: 30,
                    color: config.palette.accent,
                  }}
                >
                  {String(i + 1).padStart(2, '0')}
                </span>
                <span
                  style={{
                    fontFamily: pair.display,
                    ...pair.displayStyle,
                    fontSize: 66,
                    letterSpacing: pair.displayTracking,
                    textTransform: pair.uppercase ? 'uppercase' : 'none',
                    color: config.palette.ink,
                  }}
                >
                  {item}
                </span>
              </div>
            </div>
          );
        })}
      </SafeArea>
    </AbsoluteFill>
  );
};

const CountdownScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const frame = useCurrentFrame();
  const {config, scene, framesPerBeat} = ctx;
  const startNum = Math.max(1, Math.min(9, parseInt(scene.text ?? '3', 10) || 3));
  const pair = fontPair(config.fontPreset);
  const beat = Math.max(1, Math.round(framesPerBeat));
  const index = Math.min(startNum - 1, Math.floor(frame / beat));
  const num = startNum - index;
  const local = frame - index * beat;
  const p = interpolate(local, [0, beat * 0.8], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const bgSrc = scene.assetKey ? imageSrc2(scene.assetKey) : null;
  return (
    <AbsoluteFill style={{backgroundColor: config.palette.bg}}>
      {bgSrc ? (
        <Cover src={bgSrc} from={{scale: 1.2}} to={{scale: 1.28}} fallback={config.palette.bg}>
          <AbsoluteFill style={{backgroundColor: `${config.palette.bg}A6`}} />
        </Cover>
      ) : null}
      <SafeArea style={{justifyContent: 'center', alignItems: 'center'}}>
        <div
          style={{
            position: 'absolute',
            width: 560,
            height: 560,
            borderRadius: '50%',
            border: `6px solid ${config.palette.accent}`,
            opacity: (1 - p) * 0.8,
            transform: `scale(${0.7 + p * 0.9})`,
          }}
        />
        <div
          style={{
            fontFamily: pair.display,
            ...pair.displayStyle,
            fontSize: 460,
            color: config.palette.ink,
            textShadow: `0 0 110px ${config.palette.accent}88`,
            transform: `scale(${1.5 - p * 0.5})`,
            opacity: Math.min(1, p * 2.5),
            lineHeight: 1,
          }}
        >
          {num}
        </div>
      </SafeArea>
    </AbsoluteFill>
  );
};

const QuoteScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const frame = useCurrentFrame();
  const {config, scene} = ctx;
  const pair = fontPair(config.fontPreset);
  const raw = scene.text ?? ctx.midLine ?? config.copy.hook;
  const [quote, author] = raw.split(/\s+—\s+|\s+--\s+/);
  const opacity = interpolate(frame, [0, 20], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const rise = interpolate(frame, [0, 26], [40, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  return (
    <AbsoluteFill style={{backgroundColor: config.palette.bg}}>
      <SafeArea style={{justifyContent: 'center', alignItems: 'flex-start', gap: 36}}>
        <div
          style={{
            fontFamily: pair.display,
            fontSize: 220,
            lineHeight: 0.6,
            color: config.palette.accent,
            opacity,
          }}
        >
          “
        </div>
        <div
          style={{
            fontFamily: pair.display,
            ...pair.displayStyle,
            fontSize: 88,
            lineHeight: 1.18,
            letterSpacing: pair.displayTracking,
            textTransform: pair.uppercase ? 'uppercase' : 'none',
            color: config.palette.ink,
            opacity,
            transform: `translateY(${rise}px)`,
            maxWidth: '92%',
          }}
        >
          {quote}
        </div>
        {author ? (
          <div
            style={{
              fontFamily: pair.body,
              fontWeight: 500,
              fontSize: 34,
              letterSpacing: '0.22em',
              textTransform: 'uppercase',
              color: config.palette.accent,
              opacity,
              transform: `translateY(${rise}px)`,
            }}
          >
            — {author}
          </div>
        ) : null}
      </SafeArea>
    </AbsoluteFill>
  );
};

const EndcardScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const {config, scene} = ctx;
  const pair = fontPair(config.fontPreset);
  const flavor =
    scene.assetKey === 'grapefruit' || scene.assetKey === 'lemonmint' ? scene.assetKey : 'peach';
  const still =
    productStill2(flavor) ?? productStill2('peach') ?? imageSrc2('minimalFloat');
  const pop = spring({frame: frame - 6, fps, config: {damping: 14, stiffness: 120, mass: 1.1}});
  const glowPulse = 0.5 + Math.sin(frame / 18) * 0.2;
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(85% 55% at 50% 38%, ${config.palette.accent}33 0%, ${config.palette.bg} 62%)`,
        backgroundColor: config.palette.bg,
      }}
    >
      <SafeArea style={{alignItems: 'center', justifyContent: 'flex-end', gap: 30}}>
        <AbsoluteFill style={{alignItems: 'center', justifyContent: 'flex-start', paddingTop: '12%'}}>
          <div
            style={{
              width: '62%',
              height: '54%',
              transform: `scale(${0.75 + 0.25 * pop}) translateY(${(1 - pop) * 60}px)`,
              opacity: Math.min(1, pop * 1.5),
              filter: `drop-shadow(0 40px 90px ${config.palette.accent}${Math.round(glowPulse * 99).toString(16).padStart(2, '0')})`,
            }}
          >
            {still ? (
              <Img src={still} style={{width: '100%', height: '100%', objectFit: 'contain'}} />
            ) : (
              <div
                style={{
                  width: '52%',
                  height: '100%',
                  margin: '0 auto',
                  borderRadius: 60,
                  background: `linear-gradient(180deg, ${config.palette.accent}, ${config.palette.accent2})`,
                }}
              />
            )}
          </div>
        </AbsoluteFill>
        <KineticType
          text={scene.text ?? config.copy.cta}
          mode="slam"
          fontPreset={config.fontPreset}
          color={config.palette.ink}
          accentColor={config.palette.accent}
          fontSize={96}
          framesPerUnit={Math.max(4, Math.round(ctx.framesPerBeat / 2))}
        />
        <div
          style={{
            fontFamily: pair.body,
            fontWeight: 600,
            fontSize: 40,
            letterSpacing: '0.14em',
            color: config.palette.ink,
            opacity: interpolate(frame, [18, 34], [0, 1], {
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
            }),
            padding: '18px 44px',
            borderRadius: 999,
            border: `3px solid ${config.palette.accent}`,
            backgroundColor: `${config.palette.bg}CC`,
          }}
        >
          {CTA_LINE}
        </div>
      </SafeArea>
    </AbsoluteFill>
  );
};

const SplitScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const {config, scene} = ctx;
  const pair = fontPair(config.fontPreset);
  const keys = scene.assetKeys ?? ['poolSplash', 'gymChalk'];
  const labels = (scene.text ?? '').split('|').map((s) => s.trim());
  const variant: SplitVariant =
    scene.variant === '3v' || scene.variant === '2x2' || scene.variant === '1+2'
      ? scene.variant
      : '2v';
  return (
    <AbsoluteFill style={{backgroundColor: config.palette.bg}}>
      <SplitGrid
        variant={variant}
        background={config.palette.bg}
        gapPx={10}
        staggerFrames={Math.max(3, Math.round(ctx.framesPerBeat / 2))}
        cells={keys.map((key, i) => (
          <AbsoluteFill key={key}>
            <Cover
              src={imageSrc2(key)}
              from={{scale: 1.06}}
              to={{scale: 1.2, x: i % 2 === 0 ? 1.5 : -1.5}}
              fallback={paletteGradient(config)}
            />
            {labels[i] ? (
              <div
                style={{
                  position: 'absolute',
                  bottom: '10%',
                  left: 0,
                  right: 0,
                  textAlign: 'center',
                  fontFamily: pair.body,
                  fontWeight: 600,
                  fontSize: 30,
                  letterSpacing: '0.22em',
                  textTransform: 'uppercase',
                  color: '#fff',
                  textShadow: '0 2px 16px rgba(0,0,0,0.65)',
                }}
              >
                {labels[i]}
              </div>
            ) : null}
          </AbsoluteFill>
        ))}
      />
    </AbsoluteFill>
  );
};

const CollageScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const {config, scene} = ctx;
  const keys = scene.assetKeys ?? ['heroPeach', 'poolSplash', 'botanical', 'picnic'];
  const caption = scene.text ?? ctx.midLine;
  return (
    <AbsoluteFill
      style={{
        backgroundColor: config.palette.bg,
        background: `linear-gradient(170deg, ${config.palette.bg} 0%, ${config.palette.accent2}33 100%)`,
      }}
    >
      <CollageCutout
        staggerFrames={Math.max(4, Math.round(ctx.framesPerBeat / 2))}
        items={keys.map((key, i) => ({
          node: (
            <Cover
              src={imageSrc2(key)}
              from={{scale: 1.05}}
              to={{scale: 1.18}}
              fallback={paletteGradient(config)}
            />
          ),
          x: [30, 70, 34, 66, 50][i % 5],
          y: [20, 32, 54, 62, 40][i % 5],
          w: 44 - (i % 3) * 5,
        }))}
      />
      {caption ? (
        <SafeArea style={{justifyContent: 'flex-end', alignItems: 'center'}}>
          <KineticType
            text={caption}
            mode="slam"
            fontPreset={config.fontPreset}
            color={config.palette.ink}
            accentColor={config.palette.accent}
            fontSize={92}
            framesPerUnit={Math.max(4, Math.round(ctx.framesPerBeat / 2))}
          />
        </SafeArea>
      ) : null}
    </AbsoluteFill>
  );
};

const BeforeAfterScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const frame = useCurrentFrame();
  const {config, scene, durationInFrames} = ctx;
  const pair = fontPair(config.fontPreset);
  const keys = scene.assetKeys ?? ['studyDesk', 'poolSplash'];
  const labels = (scene.text ?? 'OHNE|MIT EARLY').split('|').map((s) => s.trim());
  // Diagonal edge sweeps left → right through the middle 60% of the scene.
  const p = interpolate(
    frame,
    [durationInFrames * 0.22, durationInFrames * 0.72],
    [0, 1],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.cubic)},
  );
  const topX = p * 160;
  const bottomX = p * 160 - 45;
  const labelStyle: React.CSSProperties = {
    position: 'absolute',
    top: '12%',
    fontFamily: pair.body,
    fontWeight: 600,
    fontSize: 34,
    letterSpacing: '0.26em',
    textTransform: 'uppercase',
    color: '#fff',
    textShadow: '0 2px 18px rgba(0,0,0,0.7)',
    padding: '12px 22px',
    border: '2px solid rgba(255,255,255,0.85)',
  };
  return (
    <AbsoluteFill style={{backgroundColor: config.palette.bg}}>
      {/* BEFORE: drab (desaturated, darker). */}
      <AbsoluteFill style={{filter: 'grayscale(0.75) brightness(0.82) contrast(0.95)'}}>
        <Cover
          src={imageSrc2(keys[0])}
          from={{scale: 1.12}}
          to={{scale: 1.18}}
          fallback={`linear-gradient(180deg, #4a4a4a, ${config.palette.bg})`}
        />
      </AbsoluteFill>
      {labels[0] ? <div style={{...labelStyle, left: '7%'}}>{labels[0]}</div> : null}
      {/* AFTER: fresh, revealed by the diagonal wipe. */}
      <AbsoluteFill
        style={{clipPath: `polygon(0 0, ${topX}% 0, ${bottomX}% 100%, 0 100%)`}}
      >
        <Cover
          src={imageSrc2(keys[1])}
          from={{scale: 1.18}}
          to={{scale: 1.08}}
          fallback={paletteGradient(config)}
        />
        {labels[1] ? <div style={{...labelStyle, left: '7%'}}>{labels[1]}</div> : null}
      </AbsoluteFill>
      {/* Wipe edge highlight. */}
      {p > 0.001 && p < 0.999 ? (
        <AbsoluteFill
          style={{
            clipPath: `polygon(${topX - 1.2}% 0, ${topX + 1.2}% 0, ${bottomX + 1.2}% 100%, ${bottomX - 1.2}% 100%)`,
            backgroundColor: config.palette.accent,
            opacity: 0.9,
          }}
        />
      ) : null}
    </AbsoluteFill>
  );
};

const ZoomThroughScene: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  const {config, scene, durationInFrames} = ctx;
  const keys = scene.assetKeys ?? ['heroPeach', 'macroCondensation', 'poolSplash'];
  const layers: React.ReactNode[] = keys.map((key) => (
    <Cover
      key={key}
      src={imageSrc2(key)}
      from={{scale: 1.02}}
      to={{scale: 1.1}}
      fallback={paletteGradient(config)}
    />
  ));
  // Final layer: type card so the zoom lands on copy.
  layers.push(
    <AbsoluteFill
      key="type-card"
      style={{backgroundColor: config.palette.bg, justifyContent: 'center', alignItems: 'center'}}
    >
      <KineticType
        text={scene.text ?? config.copy.hook}
        mode="slam"
        fontPreset={config.fontPreset}
        color={config.palette.ink}
        accentColor={config.palette.accent}
        framesPerUnit={4}
      />
    </AbsoluteFill>,
  );
  return (
    <InfiniteZoom
      layers={layers}
      framesPerLayer={Math.max(20, Math.floor(durationInFrames / Math.max(1, layers.length - 1)))}
      windowScale={0.34}
      frameColor={config.palette.accent}
    />
  );
};

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

export const SceneRenderer: React.FC<{ctx: SceneContext}> = ({ctx}) => {
  switch (ctx.scene.kind) {
    case 'hero':
      return <HeroScene ctx={ctx} />;
    case 'splash':
      return <SplashScene ctx={ctx} />;
    case 'macro':
      return <MacroScene ctx={ctx} />;
    case 'lifestyle':
      return <LifestyleScene ctx={ctx} />;
    case 'lineup':
      return <LineupScene ctx={ctx} />;
    case 'type':
      return <TypeScene ctx={ctx} />;
    case 'render3d':
      return <Render3dScene ctx={ctx} />;
    case 'ingredients':
      return <IngredientsScene ctx={ctx} />;
    case 'countdown':
      return <CountdownScene ctx={ctx} />;
    case 'quote':
      return <QuoteScene ctx={ctx} />;
    case 'split':
      return <SplitScene ctx={ctx} />;
    case 'collage':
      return <CollageScene ctx={ctx} />;
    case 'beforeafter':
      return <BeforeAfterScene ctx={ctx} />;
    case 'zoomthrough':
      return <ZoomThroughScene ctx={ctx} />;
    case 'endcard':
      return <EndcardScene ctx={ctx} />;
  }
};
