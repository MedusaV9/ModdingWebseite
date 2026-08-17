// FullRelease N1-C — Szene 3 „Der Siegelbruch" (Decision 3.9 #3):
// Erster Frame = letzter Frame von Szene 2 (gestempelter Umschlag im Kegel),
// der Umschlag dreht auf die Siegel-Seite, das neutrale Wachssiegel bricht,
// der Brief entfaltet sich — BLANK: „Ein Ort für zwei…" legt die App als
// natives SwiftUI-Overlay darüber (deshalb bleibt die Papiermitte ruhig).
import React from 'react';
import {
  AbsoluteFill,
  Easing,
  interpolate,
  random,
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
  easeSettle,
  phase,
} from '../look';
import {ENVELOPE, EnvelopeBack, EnvelopeFront, WaxSeal} from './Envelope';
import {SCENES} from '../timeline.mjs';

const T = SCENES.scene3.t;

const SEAL_SIZE = 330;
// Risslinie in Siegel-Prozenten — auch die Clip-Polygone der Hälften folgen ihr.
const CRACK = [
  [50, 2],
  [43, 27],
  [57, 47],
  [44, 69],
  [52, 98],
] as const;
const crackPolygon = (side: 'left' | 'right') => {
  const pts = CRACK.map(([px, py]) => `${px}% ${py}%`);
  return side === 'left'
    ? `polygon(0% 0%, ${pts.join(', ')}, 0% 100%)`
    : `polygon(100% 0%, 100% 100%, ${[...pts].reverse().join(', ')})`;
};

const LETTER = {w: 700, h: 1120, centerY: 1266} as const;
const PANEL = LETTER.h / 3;

export const Scene3SealBreak: React.FC<InkProps> = ({inkA, inkB}) => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  const tSec = frame / fps;

  // ── Akt 1: Wenden des Umschlags (Vorderseite → Siegel-Seite) ──────────────
  const flipP = phase(frame, fps, T.holdIn, T.holdIn + 0.55, easeInOutSoft);
  const showFront = flipP < 0.5;
  const faceScaleX = Math.abs(Math.cos(Math.PI * flipP));
  const flipLift = Math.sin(Math.PI * flipP);

  // ── Akt 2: Spannung im Wachs, Riss wandert, dann der Bruch ────────────────
  const tensionP = phase(frame, fps, T.sealTension, T.sealCrack);
  const crackF = T.sealCrack * fps;
  const afterCrack = frame >= crackF;
  const tremor = tensionP * Math.sin(tSec * 44) * 0.55;
  const sealScale = 1 + tensionP * 0.05 + tensionP * 0.008 * Math.sin(tSec * 30);
  const halvesQ = phase(frame, fps, T.sealCrack, T.sealCrack + 0.9, Easing.in(Easing.quad));
  const halvesFade = 1 - phase(frame, fps, T.sealCrack + 0.55, T.sealCrack + 0.9);
  const recoil = interpolate(frame, [crackF, crackF + 2, crackF + 12], [0, 6, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // ── Akt 3: Brief hebt sich, Umschlag verabschiedet sich nach unten ────────
  const riseP = phase(frame, fps, T.letterOut, T.letterOut + 0.8, easeSettle);
  const recenterP = phase(frame, fps, T.letterOut + 0.9, T.unfoldBottom + 0.7, easeInOutSoft);
  const envExitP = phase(frame, fps, T.letterOut + 0.6, T.letterOut + 1.5, Easing.in(Easing.quad));

  // ── Akt 4: Entfalten (obere Falz, dann untere), Linien + zwei Tinten ──────
  const openTop = phase(frame, fps, T.unfoldTop, T.unfoldTop + 0.8, easeInOutSoft);
  const openBottom = phase(frame, fps, T.unfoldBottom, T.unfoldBottom + 0.85, easeInOutSoft);
  const linesP = phase(frame, fps, T.unfoldDone + 0.2, T.unfoldDone + 1.0);
  const flourishP = phase(frame, fps, T.inkLines, T.inkLines + 1.0, easeInOutSoft);

  const packetY = interpolate(riseP, [0, 1], [ENVELOPE.centerY, 890]);
  const letterCenterY = interpolate(recenterP, [0, 1], [packetY, LETTER.centerY]);
  const letterRot = -2 * recenterP;
  const letterShadowP = Math.max(envExitP, recenterP);

  const envY = envExitP * (height - ENVELOPE.centerY + ENVELOPE.h * 0.8);
  const envOpacity = 1 - phase(frame, fps, T.letterOut + 1.1, T.letterOut + 1.5);

  // Wachs-Krümel beim Bruch (seeded — Determinismus-Gate!)
  const crumbs = new Array(7).fill(0).map((_, i) => {
    const ang = random(`crumb-a-${i}`) * Math.PI * 2;
    const speed = 90 + random(`crumb-s-${i}`) * 200;
    return {
      vx: Math.cos(ang) * speed,
      vy: Math.sin(ang) * speed * 0.5 - 160 - random(`crumb-u-${i}`) * 120,
      r: 4 + random(`crumb-r-${i}`) * 7,
    };
  });
  const crumbT = Math.max(0, (frame - crackF) / fps);

  const panelFace: React.CSSProperties = {
    position: 'absolute',
    left: 0,
    width: LETTER.w,
    height: PANEL + 1,
    background: `linear-gradient(160deg, #FBF6EA 0%, ${PALETTE.brief} 55%, #F0E8D6 100%)`,
    boxShadow: `inset 0 0 0 2px rgba(227,214,188,0.5)`,
  };

  return (
    <AbsoluteFill>
      <Room frame={frame} fps={fps} />

      {/* ── Brief (liegt hinter dem Umschlag, steigt aus ihm auf) ─────────── */}
      {frame >= T.letterOut * fps - 4 ? (
        <div style={{position: 'absolute', left: width / 2, top: letterCenterY}}>
          {/* Schattenparallaxe: beim Aufstieg hängt der Schatten nach unten
              nach, beim Absetzen weicht er nach oben aus — gegenläufig. */}
          <PaperShadow
            width={LETTER.w}
            height={PANEL + (PANEL * openTop + PANEL * openBottom)}
            lift={0.15}
            opacity={0.4 * letterShadowP}
            parallaxY={
              14 * Math.sin(Math.PI * riseP) * (1 - recenterP) -
              10 * Math.sin(Math.PI * recenterP)
            }
          />
          <div
            style={{
              position: 'absolute',
              left: -LETTER.w / 2,
              top: -LETTER.h / 2,
              width: LETTER.w,
              height: LETTER.h,
              transform: `rotate(${letterRot}deg)`,
            }}
          >
            {/* obere Falz — klappt nach oben auf. Falztiefe (Kino-Final-
                Eval): der Schatten sitzt AN der Falz (Unterkante dieses
                Panels), zieht sich beim Öffnen zusammen und lässt einen
                leisen Rest stehen — Papier liegt nie perfekt plan. */}
            <div
              style={{
                ...panelFace,
                top: 0,
                transform: `scaleY(${openTop})`,
                transformOrigin: '50% 100%',
              }}
            >
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `linear-gradient(0deg, rgba(63,45,29,${0.42 * (1 - openTop) + 0.1}) 0%, rgba(63,45,29,0) ${34 + 28 * openTop}%)`,
                }}
              />
              <Grain id="s3-letter-top" opacity={0.06} />
            </div>
            {/* Mittelbahn — beim Aufstieg zeigt sie die Karton-Außenseite;
                die beiden Falz-Schatten der Nachbarpanels spiegeln sich
                leise an ihren Kanten (Gegenrichtung je Falz). */}
            <div style={{...panelFace, top: PANEL}}>
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `linear-gradient(160deg, #F2EAD8 0%, ${PALETTE.karton} 60%, #E4D8BE 100%)`,
                  opacity: 1 - openTop,
                }}
              />
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `linear-gradient(180deg, rgba(63,45,29,${0.16 * openTop}) 0%, rgba(63,45,29,0) 18%, rgba(63,45,29,0) 82%, rgba(63,45,29,${0.2 * openBottom}) 100%)`,
                }}
              />
              <Grain id="s3-letter-mid" opacity={0.06} />
            </div>
            {/* untere Falz — klappt nach unten auf; ihr Schatten sitzt an
                der OBERkante (der Falz), Gegenrichtung zur oberen. */}
            <div
              style={{
                ...panelFace,
                top: PANEL * 2,
                transform: `scaleY(${openBottom})`,
                transformOrigin: '50% 0%',
              }}
            >
              <div
                style={{
                  position: 'absolute',
                  inset: 0,
                  background: `linear-gradient(180deg, rgba(63,45,29,${0.42 * (1 - openBottom) + 0.12}) 0%, rgba(63,45,29,0) ${34 + 28 * openBottom}%)`,
                }}
              />
              <Grain id="s3-letter-bottom" opacity={0.06} />
            </div>
            {/* Falz-Knicke: asymmetrisch je Falzrichtung — Licht von 10 Uhr
                fängt bei der oberen Falz die untere Flanke (Schatten oben,
                Lichtkante unten), bei der unteren Falz die obere. */}
            {[
              {y: PANEL, open: openTop, flip: false},
              {y: PANEL * 2, open: openBottom, flip: true},
            ].map((crease, i) => (
              <div
                key={i}
                style={{
                  position: 'absolute',
                  left: 0,
                  top: crease.y - 3,
                  width: LETTER.w,
                  height: 6,
                  background: crease.flip
                    ? `linear-gradient(180deg, rgba(255,252,244,0.4) 0%, rgba(255,252,244,0.06) 38%, rgba(90,74,56,0.3) 100%)`
                    : `linear-gradient(180deg, rgba(90,74,56,0.3) 0%, rgba(90,74,56,0.08) 62%, rgba(255,252,244,0.4) 100%)`,
                  opacity: crease.open,
                }}
              />
            ))}
            {/* Linierung — bewusst blass: die Mitte gehört dem Caption-Overlay */}
            <svg
              width={LETTER.w}
              height={LETTER.h}
              viewBox={`0 0 ${LETTER.w} ${LETTER.h}`}
              style={{position: 'absolute', inset: 0, opacity: linesP}}
            >
              <g stroke={PALETTE.kante} strokeWidth={2.5} opacity={0.55}>
                {new Array(8).fill(0).map((_, i) => (
                  <line key={i} x1={84} y1={332 + i * 96} x2={LETTER.w - 84} y2={332 + i * 96} />
                ))}
              </g>
              {/* Briefkopf: zwei Tinten-Schwünge, die aufeinander zulaufen */}
              <g fill="none" strokeWidth={8} strokeLinecap="round">
                <path
                  d={`M 96 208 C 200 150, 260 240, ${LETTER.w / 2 - 22} 196`}
                  stroke={inkA}
                  opacity={0.8}
                  pathLength={1}
                  strokeDasharray={1}
                  strokeDashoffset={1 - flourishP}
                />
                <path
                  d={`M ${LETTER.w - 96} 208 C ${LETTER.w - 200} 150, ${LETTER.w - 260} 240, ${LETTER.w / 2 + 22} 196`}
                  stroke={inkB}
                  opacity={0.8}
                  pathLength={1}
                  strokeDasharray={1}
                  strokeDashoffset={1 - flourishP}
                />
              </g>
            </svg>
          </div>
        </div>
      ) : null}

      {/* ── Umschlag mit Siegel ───────────────────────────────────────────── */}
      <div
        style={{
          position: 'absolute',
          left: width / 2,
          top: ENVELOPE.centerY,
          opacity: envOpacity,
        }}
      >
        <div style={{position: 'absolute', transform: `translate(0px, ${envY + recoil}px)`}}>
          {/* Gegenläufiger Schatten: Bruch-Recoil und Abgang nach unten
              lassen den Wurfschatten leicht nach oben ausweichen. */}
          <PaperShadow
            width={ENVELOPE.w}
            height={ENVELOPE.h}
            lift={flipLift * 0.5}
            parallaxY={-recoil * 0.6 - envY * 0.04}
          />
          <div
            style={{
              position: 'absolute',
              left: -ENVELOPE.w / 2,
              top: -ENVELOPE.h / 2,
              width: ENVELOPE.w,
              height: ENVELOPE.h,
              transform: `rotate(${-5 + flipLift * 2.5}deg) scaleX(${faceScaleX}) scale(${1 + flipLift * 0.05})`,
            }}
          >
            {showFront ? (
              <EnvelopeFront
                inkA={inkA}
                inkB={inkB}
                addressDrawP={() => 1}
                inkDotsP={1}
                postmarkScale={1}
                postmarkOpacity={1}
                postmarkSpread={1}
              />
            ) : (
              <EnvelopeBack>
                {/* Siegel-Anker an der Klappenspitze */}
                <div
                  style={{
                    position: 'absolute',
                    left: ENVELOPE.w / 2 - SEAL_SIZE / 2,
                    top: ENVELOPE.h * 0.62 - SEAL_SIZE / 2 - 26,
                    width: SEAL_SIZE,
                    height: SEAL_SIZE,
                  }}
                >
                  {afterCrack ? (
                    <>
                      {/* zwei Hälften fallen auseinander */}
                      {(['left', 'right'] as const).map((side) => {
                        const dir = side === 'left' ? -1 : 1;
                        const dx = dir * SEAL_SIZE * (0.18 + (side === 'right' ? 0.04 : 0)) * halvesQ;
                        const dy =
                          SEAL_SIZE * (side === 'left' ? 0.62 : 0.84) * halvesQ * halvesQ +
                          34 * halvesQ;
                        const drot = dir * (side === 'left' ? -15 : 12) * halvesQ;
                        return (
                          <div
                            key={side}
                            style={{
                              position: 'absolute',
                              inset: 0,
                              clipPath: crackPolygon(side),
                              transform: `translate(${dx}px, ${dy}px) rotate(${drot}deg)`,
                              opacity: halvesFade,
                            }}
                          >
                            <WaxSeal size={SEAL_SIZE} />
                          </div>
                        );
                      })}
                      {/* Wachs-Krümel */}
                      {crumbs.map((c, i) => (
                        <div
                          key={i}
                          style={{
                            position: 'absolute',
                            left: SEAL_SIZE / 2 + c.vx * crumbT,
                            top: SEAL_SIZE / 2 + c.vy * crumbT + 900 * crumbT * crumbT,
                            width: c.r,
                            height: c.r,
                            borderRadius: '40%',
                            background: PALETTE.wachsTief,
                            opacity: halvesFade,
                          }}
                        />
                      ))}
                    </>
                  ) : (
                    <div
                      style={{
                        position: 'absolute',
                        inset: 0,
                        transform: `scale(${sealScale}) rotate(${tremor}deg)`,
                      }}
                    >
                      <WaxSeal size={SEAL_SIZE} />
                      {/* der wandernde Riss */}
                      <svg
                        width={SEAL_SIZE}
                        height={SEAL_SIZE}
                        viewBox="0 0 100 100"
                        style={{position: 'absolute', inset: 0}}
                      >
                        <polyline
                          points={CRACK.map(([px, py]) => `${px},${py}`).join(' ')}
                          fill="none"
                          stroke="#4A1212"
                          strokeWidth={2.4}
                          strokeLinejoin="round"
                          strokeLinecap="round"
                          pathLength={1}
                          strokeDasharray={1}
                          strokeDashoffset={1 - tensionP}
                          opacity={0.9}
                        />
                      </svg>
                    </div>
                  )}
                </div>
              </EnvelopeBack>
            )}
            <Grain id="s3-paper" opacity={0.06} />
          </div>
        </div>
      </div>

      <LampCast frame={frame} fps={fps} />
      <DustMotes frame={frame} fps={fps} width={width} height={height} />
      <RoomDither id="s3-room" />
    </AbsoluteFill>
  );
};
