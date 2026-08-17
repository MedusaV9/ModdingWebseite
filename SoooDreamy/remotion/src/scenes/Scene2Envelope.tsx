// FullRelease N1-C — Szene 2 „Der Umschlag" (Decision 3.9 #2):
// Ein Umschlag schiebt sich in den Lampenkegel, die Anschrift zieht sich als
// abstrakte Tintenstriche, der Poststempel prägt sich auf. Beginnt und endet
// auf einem ruhigen Hold-Frame (unsichtbare Naht im AVQueuePlayer).
import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {
  DustMotes,
  Grain,
  InkProps,
  LampCast,
  PaperShadow,
  Room,
  RoomDither,
  easeDraw,
  easeSettle,
  phase,
} from '../look';
import {ENVELOPE, EnvelopeFront} from './Envelope';
import {SCENES} from '../timeline.mjs';

const T = SCENES.scene2.t;

export const Scene2Envelope: React.FC<InkProps> = ({inkA, inkB}) => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();

  // ── Einzug: der Umschlag gleitet von unten-rechts in den Kegel ────────────
  const enter = phase(frame, fps, T.envelopeIn, T.envelopeLand, easeSettle);
  const landF = T.envelopeLand * fps;
  const stampF = T.stamp * fps;

  // Mikro-Nachfedern beim Aufsetzen und beim Stempelschlag (frame-genau auf
  // den Manifest-Beats — Bild und Haptik teilen dieselbe Timeline-Quelle).
  const landDip = interpolate(frame, [landF, landF + 3, landF + 16], [0, 8, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const pressDip = interpolate(frame, [stampF, stampF + 2, stampF + 14], [0, 10, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const pressKick = interpolate(frame, [stampF, stampF + 2, stampF + 18], [0, 0.7, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const x = (1 - enter) * 150;
  const y = (1 - enter) * (height - ENVELOPE.centerY + ENVELOPE.h) + landDip + pressDip;
  const rot = -5 + (1 - enter) * 13 + pressKick;
  const lift = 1 - enter;

  // ── Anschrift: drei Striche, gestaffelt gezogen; danach zwei Tintentropfen ─
  const addressDrawP = (i: number) =>
    phase(frame, fps, T.addressStart + i * 0.28, T.addressStart + i * 0.28 + 0.55, easeDraw);
  const inkDotsP = phase(frame, fps, T.addressStart + 1.05, T.addressStart + 1.4);

  // ── Poststempel: fällt in 0,12 s auf — Impact exakt auf dem Beat (t=5,2 s) ─
  const stampFall = phase(frame, fps, T.stamp - 0.12, T.stamp, Easing.in(Easing.quad));
  const postmarkScale = interpolate(stampFall, [0, 1], [2.1, 1]);
  const postmarkOpacity = interpolate(stampFall, [0, 0.35, 1], [0, 0.35, 1]);
  const postmarkSpread = phase(frame, fps, T.stamp + 0.05, T.stamp + 0.6);
  const flash = interpolate(frame, [stampF, stampF + 1, stampF + 5], [0, 0.07, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill>
      <Room frame={frame} fps={fps} />
      <AbsoluteFill>
        {/* Requisiten-Bühne: Schatten + Umschlag teilen denselben Anker */}
        <div
          style={{
            position: 'absolute',
            left: width / 2,
            top: ENVELOPE.centerY,
            width: 0,
            height: 0,
          }}
        >
          <div style={{position: 'absolute', transform: `translate(${x}px, ${y}px)`}}>
            {/* Schattenparallaxe: der Wurfschatten hängt dem Einzug nach
                (Richtung Herkunft) und weicht dem Stempel-Dip gegenläufig
                aus — Papier und Schatten sind zwei Körper, nicht einer. */}
            <PaperShadow
              width={ENVELOPE.w}
              height={ENVELOPE.h}
              lift={lift}
              parallaxX={x * 0.14}
              parallaxY={-(landDip + pressDip) * 0.55}
            />
            <div
              style={{
                position: 'absolute',
                left: -ENVELOPE.w / 2,
                top: -ENVELOPE.h / 2,
                width: ENVELOPE.w,
                height: ENVELOPE.h,
                transform: `rotate(${rot}deg)`,
              }}
            >
              <EnvelopeFront
                inkA={inkA}
                inkB={inkB}
                addressDrawP={addressDrawP}
                inkDotsP={inkDotsP}
                postmarkScale={postmarkScale}
                postmarkOpacity={postmarkOpacity}
                postmarkSpread={postmarkSpread}
                flash={flash}
              />
              <Grain id="s2-paper" opacity={0.06} />
            </div>
          </div>
        </div>
      </AbsoluteFill>
      <LampCast frame={frame} fps={fps} />
      <DustMotes frame={frame} fps={fps} width={width} height={height} />
      <RoomDither id="s2-room" />
    </AbsoluteFill>
  );
};
