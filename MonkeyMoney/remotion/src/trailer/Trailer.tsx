// MONKEY-MONEY-Trailer, 72 s · 1920×1080 · 30 fps (Storyboard §5.2).
// Musik-Bett: „Monkeys Spinning Monkeys" (Kevin MacLeod, CC-BY 4.0 —
// Attribution auf der End-Card in Shot 9), Lautstärke-Kurve mit Fade-Out.
import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate } from "remotion";
import { BananaWipe, CLAMP, M, WhiteFlash } from "../components";
import { PALETTE } from "../tokens";
import {
  ShotCards,
  ShotCta,
  ShotEmotion,
  ShotFeatures,
  ShotHook,
  ShotHow,
  ShotLineup,
  ShotLogo,
  ShotMontage,
} from "./shots";

export const TRAILER_FPS = 30;
export const TRAILER_FRAMES = 2160; // 72 s

// Shot-Grenzen (Frames @30fps)
const T = {
  hook: 150, //      5 s — Logo-Stinger davor
  lineup: 330, //   11 s
  how: 570, //      19 s
  montage: 810, //  27 s
  features: 1170, // 39 s
  emotion: 1410, // 47 s
  cards: 1650, //   55 s
  cta: 1830, //     61 s
};

export const Trailer: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: PALETTE.jungleNight }}>
    <Audio
      src={M("music/MonkeysSpinningMonkeys.mp3")}
      volume={(f) => interpolate(f, [0, 24, 1980, 2140], [0, 0.9, 0.9, 0], CLAMP)}
    />
    <Sequence durationInFrames={T.hook}>
      <ShotLogo />
    </Sequence>
    <Sequence from={T.hook} durationInFrames={T.lineup - T.hook}>
      <ShotHook />
    </Sequence>
    <Sequence from={T.lineup} durationInFrames={T.how - T.lineup}>
      <ShotLineup />
    </Sequence>
    <Sequence from={T.how} durationInFrames={T.montage - T.how}>
      <ShotHow />
    </Sequence>
    <Sequence from={T.montage} durationInFrames={T.features - T.montage}>
      <ShotMontage />
    </Sequence>
    <Sequence from={T.features} durationInFrames={T.emotion - T.features}>
      <ShotFeatures />
    </Sequence>
    <Sequence from={T.emotion} durationInFrames={T.cards - T.emotion}>
      <ShotEmotion />
    </Sequence>
    <Sequence from={T.cards} durationInFrames={T.cta - T.cards}>
      <ShotCards />
    </Sequence>
    <Sequence from={T.cta} durationInFrames={TRAILER_FRAMES - T.cta}>
      <ShotCta />
    </Sequence>

    {/* Übergänge: Bananen-Wipes über den Schnitt gelegt, Weißblitze für harte Cuts */}
    <Sequence from={T.hook - 13} durationInFrames={26}>
      <BananaWipe />
    </Sequence>
    <Sequence from={T.how - 13} durationInFrames={26}>
      <BananaWipe />
    </Sequence>
    <Sequence from={T.cards - 13} durationInFrames={26}>
      <BananaWipe />
    </Sequence>
    <Sequence from={T.cta - 13} durationInFrames={26}>
      <BananaWipe />
    </Sequence>
    <WhiteFlash at={T.lineup} />
    <WhiteFlash at={T.montage} />
    <WhiteFlash at={T.features} />
    <WhiteFlash at={T.emotion} />
  </AbsoluteFill>
);
