/**
 * TrailerFactory — renders a complete 1080x1920@60 trailer purely from a
 * TrailerStyleConfig:
 *
 *   beat-snapped scene timeline (+ endcard guarantee) → per-scene renderers
 *   → transition-in overlays → global FX (shake/chromatic/glitch) →
 *   GradeFilter → overlays (leaks/burns/grain/letterbox/progress/stickers)
 *   → BrandWatermark → music + SFX plan.
 */
import React from 'react';
import type {PropsWithChildren} from 'react';
import {AbsoluteFill, Audio, Sequence, useCurrentFrame} from 'remotion';
import {BrandWatermark} from '../../shared/BrandWatermark';
import {durationInFrames2} from '../config/types';
import type {SceneSpec, TrailerStyleConfig, TransitionKind} from '../config/types';
import {musicSrc2, sfxSrc2} from '../lib/assets2';
import {beatFrame2, framesPerBeat2, getTrack2} from '../lib/beats2';
import {
  Bloom,
  ChromaticAberration,
  FilmBurn,
  GlitchStack,
  GradeFilter,
  GrainPro,
  Letterbox,
  LightLeak,
  LumaFade,
  MaskReveal,
  ProgressUI,
  ShakeCam,
  StickerLayer,
  StopMotionHold,
  WhipPan,
  ZoomBlurTransition,
} from '../fx';
import {isDarkColor, SceneRenderer} from './scenes';
import type {SceneContext} from './scenes';

// ---------------------------------------------------------------------------
// Transition plumbing
// ---------------------------------------------------------------------------

const TRANSITION_FRAMES: Record<TransitionKind, number> = {
  cut: 0,
  whip_left: 10,
  whip_right: 10,
  whip_up: 10,
  zoom_in: 12,
  zoom_out: 12,
  luma: 16,
  mask_circle: 16,
  mask_bars: 18,
  mask_diagonal: 14,
  mask_can: 20,
  mask_torn: 18,
};

const TransitionIn: React.FC<
  PropsWithChildren<{kind: TransitionKind; darkPalette: boolean}>
> = ({kind, darkPalette, children}) => {
  const frames = TRANSITION_FRAMES[kind];
  switch (kind) {
    case 'cut':
      return <AbsoluteFill>{children}</AbsoluteFill>;
    case 'whip_left':
    case 'whip_right':
    case 'whip_up': {
      const direction = kind === 'whip_left' ? 'left' : kind === 'whip_right' ? 'right' : 'up';
      return (
        <WhipPan mode="in" direction={direction} durationInFrames={frames}>
          {children}
        </WhipPan>
      );
    }
    case 'zoom_in':
    case 'zoom_out':
      return (
        <ZoomBlurTransition
          mode="in"
          direction={kind === 'zoom_in' ? 'in' : 'out'}
          durationInFrames={frames}
        >
          {children}
        </ZoomBlurTransition>
      );
    case 'luma':
      return (
        <LumaFade mode="in" durationInFrames={frames} tone={darkPalette ? 'black' : 'white'}>
          {children}
        </LumaFade>
      );
    case 'mask_circle':
      return (
        <MaskReveal shape="circle" mode="in" durationInFrames={frames}>
          {children}
        </MaskReveal>
      );
    case 'mask_bars':
      return (
        <MaskReveal shape="bars" mode="in" durationInFrames={frames}>
          {children}
        </MaskReveal>
      );
    case 'mask_diagonal':
      return (
        <MaskReveal shape="diagonal" mode="in" durationInFrames={frames}>
          {children}
        </MaskReveal>
      );
    case 'mask_can':
      return (
        <MaskReveal shape="can" mode="in" durationInFrames={frames}>
          {children}
        </MaskReveal>
      );
    case 'mask_torn':
      return (
        <MaskReveal shape="torn" mode="in" durationInFrames={frames}>
          {children}
        </MaskReveal>
      );
  }
};

// ---------------------------------------------------------------------------
// Timeline computation
// ---------------------------------------------------------------------------

type PlacedScene = {
  scene: SceneSpec;
  index: number;
  from: number;
  /** Visible length up to the next cut (transition overlap excluded). */
  duration: number;
  transition: TransitionKind;
  midLine: string | null;
};

const MIN_ENDCARD_FRAMES = 120; // endcard is always at least 2s on screen

const MID_CONSUMERS = new Set(['splash', 'macro', 'lifestyle', 'type', 'quote']);

const buildTimeline = (config: TrailerStyleConfig): PlacedScene[] => {
  const track = getTrack2(config.track, config.trackFallback ?? 'hype');
  const total = durationInFrames2(config);

  const scenes: SceneSpec[] = [...config.structure];
  if (scenes.length === 0 || scenes[scenes.length - 1].kind !== 'endcard') {
    scenes.push({kind: 'endcard', beats: 8});
  }

  // Beat-snapped raw starts.
  let cumBeats = 0;
  const rawStarts: number[] = scenes.map((scene, i) => {
    const start = i === 0 ? 0 : beatFrame2(track, cumBeats);
    cumBeats += Math.max(0.5, scene.beats);
    return start;
  });

  // Endcard always ends the composition and gets at least 2s.
  const endcardIndex = scenes.length - 1;
  const endcardFrom = Math.max(
    0,
    Math.min(rawStarts[endcardIndex], total - MIN_ENDCARD_FRAMES),
  );

  const placed: PlacedScene[] = [];
  let midCounter = 0;
  for (let i = 0; i < scenes.length; i++) {
    const isEndcard = i === endcardIndex;
    const from = isEndcard ? endcardFrom : rawStarts[i];
    if (!isEndcard && from >= endcardFrom - 12) continue; // no room left before endcard
    const nextFrom = isEndcard
      ? total
      : Math.min(i + 1 <= endcardIndex ? (i + 1 === endcardIndex ? endcardFrom : rawStarts[i + 1]) : total, endcardFrom);
    const duration = Math.max(1, nextFrom - from);
    const scene = scenes[i];
    let midLine: string | null = null;
    if (MID_CONSUMERS.has(scene.kind) && config.copy.mid.length > 0) {
      midLine = config.copy.mid[midCounter % config.copy.mid.length];
      midCounter++;
    }
    placed.push({
      scene,
      index: i,
      from,
      duration,
      transition: scene.transition ?? config.defaultTransition ?? 'cut',
      midLine,
    });
  }
  return placed;
};

// ---------------------------------------------------------------------------
// Factory component
// ---------------------------------------------------------------------------

export type TrailerFactoryProps = {config: TrailerStyleConfig};

export const TrailerFactory: React.FC<TrailerFactoryProps> = ({config}) => {
  const frame = useCurrentFrame();
  const track = getTrack2(config.track, config.trackFallback ?? 'hype');
  const total = durationInFrames2(config);
  const fpb = framesPerBeat2(track);
  const timeline = buildTimeline(config);
  const darkPalette = isDarkColor(config.palette.bg);
  const has = (effect: string) => config.effects.includes(effect as never);

  // All beat frames inside the composition.
  const beatFrames: number[] = [];
  for (let b = 0; ; b++) {
    const f = beatFrame2(track, b);
    if (f >= total) break;
    beatFrames.push(f);
    if (b > 4000) break;
  }
  const cutFrames = timeline.filter((p) => p.index > 0).map((p) => p.from);

  // --- Scene stack -------------------------------------------------------
  const activeIndex = Math.max(
    0,
    timeline.findIndex((p) => frame >= p.from && frame < p.from + p.duration),
  );

  let stack: React.ReactNode = (
    <AbsoluteFill style={{backgroundColor: config.palette.bg}}>
      {timeline.map((p, i) => {
        const next = timeline[i + 1];
        const overlap = next ? TRANSITION_FRAMES[next.transition] : 0;
        const ctx: SceneContext = {
          config,
          scene: p.scene,
          sceneIndex: p.index,
          durationInFrames: p.duration,
          framesPerBeat: fpb,
          midLine: p.midLine,
        };
        return (
          <Sequence
            key={`${p.index}-${p.scene.kind}`}
            from={p.from}
            durationInFrames={p.duration + overlap}
            layout="absolute-fill"
          >
            <TransitionIn kind={i === 0 ? 'cut' : p.transition} darkPalette={darkPalette}>
              <SceneRenderer ctx={ctx} />
            </TransitionIn>
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );

  // --- Global motion FX (innermost → outermost) --------------------------
  // PERF: chromatic (3x children via SVG channel filters) and glitch bursts
  // (2 RGB ghosts + N slices) multiply — stacked they explode to dozens of
  // full-frame filtered layers and freeze the software-rendered tab. So the
  // chromatic pulse is suppressed while a glitch burst runs (the burst's own
  // RGB ghosts cover the split look during those frames).
  const glitchBursts = has('glitch_bursts')
    ? [...cutFrames, ...beatFrames.filter((_, b) => b > 0 && b % 8 === 0)]
    : [];
  const inGlitchBurst = glitchBursts.some((f) => frame >= f - 1 && frame < f + 10);

  if (has('shake_on_beat')) {
    const impacts = beatFrames.filter((_, b) => b % 4 === 0);
    stack = (
      <ShakeCam impactFrames={impacts} amplitude={20} decayFrames={10}>
        {stack}
      </ShakeCam>
    );
  }
  if (has('chromatic')) {
    // RGB split pulses on each beat and decays — passthrough between beats.
    let amount = 0;
    if (!inGlitchBurst) {
      for (const bf of beatFrames) {
        const t = frame - bf;
        if (t >= 0 && t < 10) amount = Math.max(amount, 7 * Math.exp(-t / 3.2));
      }
    }
    stack = <ChromaticAberration amount={amount}>{stack}</ChromaticAberration>;
  }
  if (has('glitch_bursts')) {
    stack = (
      <GlitchStack burstFrames={glitchBursts} burstDurationInFrames={8} intensity={0.9} slices={6}>
        {stack}
      </GlitchStack>
    );
  }
  if (has('stop_motion')) {
    // 5-frame holds @60fps ≈ 12fps stop-motion cadence (freezes nested
    // Sequences too — apply before the grade so overlays stay smooth).
    stack = <StopMotionHold holdFrames={5}>{stack}</StopMotionHold>;
  }
  if (has('bloom')) {
    stack = <Bloom intensity={0.42} radiusPx={30}>{stack}</Bloom>;
  }

  // --- Grade -------------------------------------------------------------
  stack = (
    <GradeFilter preset={config.gradePreset} palette={config.palette}>
      {stack}
    </GradeFilter>
  );

  return (
    <AbsoluteFill style={{backgroundColor: config.palette.bg}}>
      {stack}

      {/* --- Overlays (above the grade) --- */}
      {has('light_leak') ? (
        <LightLeak
          intensity={0.45}
          colors={[`${config.palette.accent}E6`, `${config.palette.accent2}CC`]}
        />
      ) : null}
      {has('film_burn')
        ? cutFrames.map((f) => <FilmBurn key={f} atFrame={f} durationInFrames={14} />)
        : null}
      {has('grain') ? <GrainPro intensity="film" /> : null}
      {has('grain_heavy') ? <GrainPro intensity="heavy" /> : null}
      {has('vignette') ? (
        <AbsoluteFill
          style={{
            background: 'radial-gradient(120% 90% at 50% 44%, transparent 52%, rgba(0,0,0,0.55) 100%)',
            pointerEvents: 'none',
          }}
        />
      ) : null}
      {has('letterbox') ? <Letterbox barFraction={0.09} enterDurationInFrames={18} /> : null}
      {has('stickers') ? (
        <StickerLayer
          stickers={config.stickers ?? ['⚡', '💦', '🍑', '✨']}
          count={7}
          startAt={Math.round(fpb)}
          staggerFrames={Math.max(3, Math.round(fpb / 2))}
        />
      ) : null}
      {has('progress_dots') ? (
        <ProgressUI
          variant="dots"
          count={timeline.length}
          activeIndex={activeIndex}
          accent={config.palette.accent}
        />
      ) : null}
      {has('progress_bar') ? <ProgressUI variant="bar" accent={config.palette.accent} /> : null}
      {has('hiit_timer') ? (
        <ProgressUI variant="timer" accent={config.palette.accent} timerTotalSec={config.durationSec} />
      ) : null}

      <BrandWatermark
        tone={darkPalette ? 'light' : 'dark'}
        position="top-right"
        sub="@drink.early"
      />

      {/* --- Audio --- */}
      <TrailerAudio config={config} timeline={timeline} total={total} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------
// Audio: music track (v2 → v1 fallback), SFX plan, cut whooshes
// ---------------------------------------------------------------------------

const TrailerAudio: React.FC<{
  config: TrailerStyleConfig;
  timeline: PlacedScene[];
  total: number;
}> = ({config, timeline, total}) => {
  const track = getTrack2(config.track, config.trackFallback ?? 'hype');
  const music = musicSrc2(config.track, config.trackFallback ?? 'hype');
  const baseVolume = config.musicVolume ?? 1;
  const cutSfx = config.sfxPlan.onSceneCut ? sfxSrc2(config.sfxPlan.onSceneCut) : null;

  return (
    <>
      {music ? (
        <Audio
          src={music}
          volume={(f) =>
            Math.max(0, Math.min(baseVolume, (baseVolume * (total - f)) / 30))
          }
        />
      ) : null}
      {config.sfxPlan.cues.map((cue, i) => {
        const src = sfxSrc2(cue.name);
        if (!src) return null;
        const from = Math.max(0, beatFrame2(track, cue.beat));
        if (from >= total - 5) return null;
        return (
          <Sequence key={`cue-${i}`} from={from}>
            <Audio src={src} volume={cue.volume ?? 0.8} />
          </Sequence>
        );
      })}
      {cutSfx
        ? timeline
            .filter((p) => p.index > 0 && p.transition !== 'cut')
            .map((p) => (
              <Sequence key={`cut-${p.index}`} from={Math.max(0, p.from - 8)}>
                <Audio src={cutSfx} volume={config.sfxPlan.cutVolume ?? 0.55} />
              </Sequence>
            ))
        : null}
    </>
  );
};
