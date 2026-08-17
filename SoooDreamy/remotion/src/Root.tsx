// FullRelease N1-C — Kompositions-Registrierung. Eine Auflösung, eine
// Sprachfassung: die Videos sind TEXTFREI (kein Font-Problem auf Linux,
// halbes Budget), Sprache lebt in nativen SwiftUI-Overlays der App
// (RECON_REMOTION_PIPELINE.md §6.1 Option A). Die Tintenfarben sind Props
// mit Defaults — Laufzeit-Paarfarben bleiben der prozeduralen Hälfte.
import React from 'react';
import {Composition} from 'remotion';
import {DEFAULT_INKS} from './look';
import {Scene2Envelope} from './scenes/Scene2Envelope';
import {Scene3SealBreak} from './scenes/Scene3SealBreak';
import {Scene6Polaroid} from './scenes/Scene6Polaroid';
import {FPS, HEIGHT, SCENES, WIDTH} from './timeline.mjs';

export const Root: React.FC = () => (
  <>
    <Composition
      id={SCENES.scene2.composition}
      component={Scene2Envelope}
      durationInFrames={SCENES.scene2.durationSec * FPS}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
      defaultProps={DEFAULT_INKS}
    />
    <Composition
      id={SCENES.scene3.composition}
      component={Scene3SealBreak}
      durationInFrames={SCENES.scene3.durationSec * FPS}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
      defaultProps={DEFAULT_INKS}
    />
    <Composition
      id={SCENES.scene6.composition}
      component={Scene6Polaroid}
      durationInFrames={SCENES.scene6.durationSec * FPS}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
      defaultProps={DEFAULT_INKS}
    />
  </>
);
