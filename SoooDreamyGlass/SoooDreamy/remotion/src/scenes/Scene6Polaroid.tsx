// FullRelease N1-C — Szene 6 „Das leere Polaroid" (Decision 3.9 #6):
// Ein Polaroid segelt in den Kegel, entwickelt sich von Weiß zu
// Papier.polaroid — und BLEIBT leer. „Eure erste Erinnerung fehlt noch"
// spricht die App als natives Overlay; das Bildfenster bleibt darum frei.
// Zum Abschluss setzt sich ein kleiner Wachssiegel-Sticker auf die Ecke
// (die Ikonografie des App-Icons: das versiegelte Polaroid).
import React from 'react';
import {
  AbsoluteFill,
  Easing,
  interpolate,
  interpolateColors,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {
  DustMotes,
  Grain,
  InkProps,
  LampCast,
  PALETTE,
  PaperShadow,
  Room,
  RoomDither,
  easeInOutSoft,
  phase,
} from '../look';
import {WaxSeal} from './Envelope';
import {SCENES} from '../timeline.mjs';

const T = SCENES.scene6.t;

const FRAME_W = 866;
const FRAME_H = 1046;
const MARGIN = 56;
const WINDOW_W = FRAME_W - MARGIN * 2;
const WINDOW_H = 700;
const CENTER_Y = 1216;
const SEAL_SIZE = 190;

export const Scene6Polaroid: React.FC<InkProps> = ({inkA, inkB}) => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  const tSec = frame / fps;

  // ── Fallen & Landen: Papier segelt, pendelt quer, setzt weich auf ─────────
  const fallP = phase(frame, fps, T.dropIn, T.land, easeInOutSoft);
  const y = (fallP - 1) * (CENTER_Y + FRAME_H);
  const sway = Math.sin(fallP * Math.PI * 2.2) * 90 * (1 - fallP);
  // Nachwippen wie frisch geschüttelt: gedämpfte Sinus-Schwingung nach der
  // Landung — die Scheitel liegen auf den rockA/rockB-Beats des Manifests.
  const sinceLand = Math.max(0, tSec - T.land);
  const rock = fallP >= 1 ? Math.exp(-sinceLand * 2.1) * Math.sin(sinceLand * 9) * 2.4 : 0;
  const rot = -16 + 11 * fallP + rock;
  const landSquish = interpolate(
    frame,
    [T.land * fps, T.land * fps + 3, T.land * fps + 14],
    [0, 6, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );

  // ── Entwicklung: Weiß → Papierton, das Fenster wird zur leeren Nacht ──────
  const devP = phase(frame, fps, T.developStart, T.developDone, easeInOutSoft);
  const frameColor = interpolateColors(devP, [0, 1], ['#FFFFFF', PALETTE.polaroid]);
  // Chemie-Schimmer: eine leise Zwei-Tinten-Irisierung wandert übers Fenster,
  // stärkste Sichtbarkeit in der Mitte der Entwicklung.
  const shimmerOpacity = 0.09 * Math.sin(Math.PI * devP);
  const shimmerX = interpolate(devP, [0, 1], [-WINDOW_W * 0.7, WINDOW_W * 0.7]);

  // ── Lampen-Glanz streicht einmal über die glänzende Fläche ────────────────
  const glintP = phase(frame, fps, T.glint, T.glint + 0.9, easeInOutSoft);
  const glintX = interpolate(glintP, [0, 1], [-WINDOW_W, WINDOW_W * 1.6]);
  const glintOpacity = glintP > 0 && glintP < 1 ? 0.12 * Math.sin(Math.PI * glintP) : 0;

  // ── Siegel-Sticker: presst sich auf, sobald die Entwicklung fertig ist ────
  const sealFall = phase(frame, fps, T.developDone - 0.12, T.developDone, Easing.in(Easing.quad));
  const sealScale = interpolate(sealFall, [0, 1], [1.8, 1]);
  const sealOpacity = interpolate(sealFall, [0, 0.3, 1], [0, 0.4, 1]);
  const sealDip = interpolate(
    frame,
    [T.developDone * fps, T.developDone * fps + 2, T.developDone * fps + 12],
    [0, 5, 0],
    {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
  );

  return (
    <AbsoluteFill>
      <Room frame={frame} fps={fps} />

      <div style={{position: 'absolute', left: width / 2, top: CENTER_Y}}>
        <div style={{position: 'absolute', transform: `translate(${sway}px, ${y + landSquish + sealDip}px)`}}>
          {/* Schattenparallaxe: der Schatten pendelt dem Segeln gegenläufig
              nach und weicht Landungs-Squish und Siegel-Dip nach oben aus. */}
          <PaperShadow
            width={FRAME_W}
            height={FRAME_H}
            lift={1 - fallP}
            parallaxX={-sway * 0.35}
            parallaxY={-24 * (1 - fallP) - (landSquish + sealDip) * 0.55}
          />
          <div
            style={{
              position: 'absolute',
              left: -FRAME_W / 2,
              top: -FRAME_H / 2,
              width: FRAME_W,
              height: FRAME_H,
              transform: `rotate(${rot}deg)`,
            }}
          >
            {/* Rahmen */}
            <div
              style={{
                position: 'absolute',
                inset: 0,
                borderRadius: 18,
                background: `linear-gradient(160deg, rgba(255,255,255,0.55), rgba(0,0,0,0.02)), ${frameColor}`,
                boxShadow:
                  'inset 3px 4px 10px rgba(255,255,255,0.6), inset -4px -6px 14px rgba(90,74,56,0.18)',
              }}
            />
            {/* Bildfenster */}
            <div
              style={{
                position: 'absolute',
                left: MARGIN,
                top: MARGIN,
                width: WINDOW_W,
                height: WINDOW_H,
                overflow: 'hidden',
                boxShadow: 'inset 0 0 0 2px rgba(90,74,56,0.22), inset 0 3px 8px rgba(0,0,0,0.18)',
              }}
            >
              {/* fertige, leere Nacht — bleibt leer (Decision #6) */}
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `radial-gradient(120% 120% at 30% 18%, #241A14 0%, #170F0B 55%, #110B08 100%)`,
                }}
              />
              {/* Lampen-Reflex im Glanz des Fensters */}
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `radial-gradient(60% 42% at 18% 8%, rgba(255,196,107,0.12) 0%, rgba(255,196,107,0) 70%)`,
                }}
              />
              {/* Entwicklungs-Schleier: zwei versetzte, WARME Radialgradienten
                  heben sich unterschiedlich schnell — die Chemie arbeitet
                  ungleichmäßig. (Kaltes Weiß über warmem Dunkel las grau —
                  Still-Review-Befund; Polaroids entwickeln milchig-creme.) */}
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `radial-gradient(130% 110% at 64% 70%, rgba(252,246,232,1) 0%, rgba(243,233,212,0.97) 100%)`,
                  opacity: 1 - devP,
                }}
              />
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `radial-gradient(90% 80% at 30% 30%, rgba(255,250,238,0.95) 0%, rgba(255,250,238,0) 75%)`,
                  opacity: (1 - devP) * (1 - devP),
                }}
              />
              {/* Sepia-Zwischenphase: kurz nach der Mitte schimmert die Chemie warm */}
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `radial-gradient(110% 100% at 45% 45%, rgba(180,140,92,0.5) 0%, rgba(120,88,56,0.35) 100%)`,
                  opacity: Math.sin(Math.PI * devP) * 0.5,
                }}
              />
              {/* Zwei-Tinten-Irisierung der Entwickler-Chemie */}
              <div
                style={{
                  position: 'absolute',
                  inset: -40,
                  transform: `translateX(${shimmerX}px) rotate(18deg)`,
                  background: `linear-gradient(90deg, transparent 0%, ${inkA} 38%, ${inkB} 62%, transparent 100%)`,
                  opacity: shimmerOpacity,
                }}
              />
              {/* der eine Lampen-Glint */}
              <div
                style={{
                  position: 'absolute',
                  top: -80,
                  bottom: -80,
                  left: 0,
                  width: 180,
                  transform: `translateX(${glintX}px) rotate(14deg)`,
                  background:
                    'linear-gradient(90deg, rgba(255,244,220,0) 0%, rgba(255,244,220,1) 50%, rgba(255,244,220,0) 100%)',
                  opacity: glintOpacity,
                }}
              />
            </div>
            {/* Siegel-Sticker auf der unteren rechten Rahmenecke */}
            <div
              style={{
                position: 'absolute',
                left: FRAME_W - SEAL_SIZE * 0.72,
                top: FRAME_H - SEAL_SIZE * 0.78,
                width: SEAL_SIZE,
                height: SEAL_SIZE,
                transform: `rotate(9deg) scale(${sealScale})`,
                opacity: sealOpacity,
              }}
            >
              <WaxSeal size={SEAL_SIZE} />
            </div>
            <Grain id="s6-paper" opacity={0.055} />
          </div>
        </div>
      </div>

      <LampCast frame={frame} fps={fps} />
      <DustMotes frame={frame} fps={fps} width={width} height={height} />
      <RoomDither id="s6-room" />
    </AbsoluteFill>
  );
};
