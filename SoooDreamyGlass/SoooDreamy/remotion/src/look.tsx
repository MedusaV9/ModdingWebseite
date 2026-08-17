// FullRelease N1-C — gemeinsamer Papier&Licht-Look aller Kino-Szenen.
// Rein geometrisch/gradient-basiert, TEXTFREI. Farbwerte sind die Token aus
// docs/styles/DIRECTION_PAPIER_LICHT.md; die Lampe sitzt auf 10 Uhr
// (Licht von oben-links, Schatten nach unten-rechts — Do #5).
import React, {useMemo} from 'react';
import {AbsoluteFill, Easing, interpolate, random} from 'remotion';

export const PALETTE = {
  zimmerOben: '#201613',
  zimmerMitte: '#2A1D16',
  zimmerUnten: '#33241B',
  lichtkegel: '#4A3320',
  lampengold: '#FFC46B',
  glut: '#E8845E',
  brief: '#F7F1E4',
  karton: '#EFE6D2',
  kante: '#E3D6BC',
  polaroid: '#FAF6EC',
  tinteDunkel: '#2E2318',
  tinteSekundaer: '#5A4A38',
  wachs: '#B33A3A',
  wachsTief: '#7E2727',
  aufNacht: '#F3EAD9',
} as const;

// Type-Alias statt interface: Remotions <Composition> verlangt Props, die
// Record<string, unknown> erfüllen — Interfaces tun das strukturell nicht.
export type InkProps = {
  /** Tinte von Partner A — Prop mit Default, Laufzeit-Paarfarben bleiben prozedural. */
  inkA: string;
  /** Tinte von Partner B. */
  inkB: string;
};

export const DEFAULT_INKS: InkProps = {inkA: '#FF5C8A', inkB: '#60A5FA'};

// Choreografie-Kurven: weiches Ankommen (entprellt), getragenes Ein/Aus.
export const easeSettle = Easing.bezier(0.22, 1, 0.36, 1);
export const easeInOutSoft = Easing.bezier(0.45, 0, 0.25, 1);
export const easeDraw = Easing.bezier(0.65, 0, 0.35, 1);

export const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

/** Fortschritt 0→1 zwischen zwei Sekunden-Marken, deterministisch aus dem Frame. */
export const phase = (
  frame: number,
  fps: number,
  fromSec: number,
  toSec: number,
  easing: (v: number) => number = easeInOutSoft,
): number =>
  interpolate(frame, [fromSec * fps, toSec * fps], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing,
  });

/**
 * Deterministische Lichtwanderung des Lampenkegels: der Kegel atmet (±2 %
 * Intensität) UND wandert minimal über die Szene (<1 % Bildbreite, zwei
 * inkommensurable Sinusfrequenzen — nie ein sichtbarer Loop). Der goldene
 * Kern wandert etwas stärker als der weite Falloff (Quellen-Parallaxe).
 * Eine Quelle für Room UND LampCast, damit Kegel und Cast nie driften.
 */
export const lampDrift = (frame: number, fps: number) => {
  const tSec = frame / fps;
  return {
    breath: 1 + 0.02 * Math.sin(tSec * 1.1 * Math.PI),
    x: 0.9 * Math.sin(tSec * 0.37),
    y: 0.55 * Math.sin(tSec * 0.23 + 1.7),
  };
};

/**
 * Das Sepia-Zimmer: vertikaler Raumverlauf, doppelter Lampenkegel von 10 Uhr
 * (weiter warmer Falloff + goldener Kern) und eine Vignette. `lampDrift`
 * lässt das Licht kaum merklich atmen und wandern — deterministisch.
 */
export const Room: React.FC<{
  frame: number;
  fps: number;
  intensity?: number;
}> = ({frame, fps, intensity = 1}) => {
  const drift = lampDrift(frame, fps);
  const k = intensity * drift.breath;
  return (
    <AbsoluteFill>
      <AbsoluteFill
        style={{
          background: `linear-gradient(180deg, ${PALETTE.zimmerOben} 0%, ${PALETTE.zimmerMitte} 52%, ${PALETTE.zimmerUnten} 100%)`,
        }}
      />
      {/* weiter Kegel-Falloff (Umbra → nichts) — wandert mit der Lampe */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(130% 96% at ${16 + drift.x}% ${4 + drift.y}%, rgba(74,51,32,${0.62 * k}) 0%, rgba(74,51,32,${0.3 * k}) 34%, rgba(74,51,32,0) 68%)`,
        }}
      />
      {/* goldener Lampen-Kern — wandert etwas stärker (Quellen-Parallaxe) */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(56% 40% at ${14 + drift.x * 1.4}% ${2 + drift.y * 1.4}%, rgba(255,196,107,${0.34 * k}) 0%, rgba(255,196,107,${0.12 * k}) 44%, rgba(255,196,107,0) 72%)`,
        }}
      />
      {/* warme Glut, die vom Boden zurückstrahlt */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(80% 34% at 42% 104%, rgba(232,132,94,${0.1 * k}) 0%, rgba(232,132,94,0) 70%)`,
        }}
      />
      {/* Vignette — hält den Blick im Kegel */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(140% 112% at 46% 42%, rgba(0,0,0,0) 52%, rgba(10,6,4,0.5) 100%)`,
        }}
      />
    </AbsoluteFill>
  );
};

/**
 * Statisches Papier-/Filmkorn als SVG-Turbulenz (fester Seed — Do #10 und
 * Recon §4.1: KEIN animiertes Korn, sonst explodiert die Bitrate).
 * `id` muss pro Einsatzstelle eindeutig sein (SVG-Filter-Namespace).
 */
export const Grain: React.FC<{
  id: string;
  opacity?: number;
  baseFrequency?: number;
  numOctaves?: number;
}> = ({id, opacity = 0.05, baseFrequency = 0.82, numOctaves = 2}) => (
  <svg
    width="100%"
    height="100%"
    style={{
      position: 'absolute',
      inset: 0,
      opacity,
      mixBlendMode: 'overlay',
      pointerEvents: 'none',
    }}
  >
    <filter id={id} x="0" y="0" width="100%" height="100%">
      <feTurbulence
        type="fractalNoise"
        baseFrequency={baseFrequency}
        numOctaves={numOctaves}
        seed={47}
        stitchTiles="stitch"
      />
      <feColorMatrix
        type="matrix"
        values="0 0 0 0 0.93  0 0 0 0 0.87  0 0 0 0 0.76  0 0 0 0.6 0"
      />
    </filter>
    <rect width="100%" height="100%" filter={`url(#${id})`} />
  </svg>
);

/**
 * Anti-Banding-Dither fürs ganze Zimmer (Kino-Final-Eval): die weichen
 * Radial-Verläufe des Raums neigen nach HEVC-Quantisierung zu Banding-
 * Ringen — feine Turbulenz allein (Filmkorn) bricht nur die höchsten
 * Frequenzen. Diese Doppellage kombiniert das dichtere Korn mit einer
 * langwelligen, sehr leisen Luminanz-Turbulenz, die die Ringe unterhalb
 * der Sichtbarkeitsschwelle verwürfelt. STATISCH (fester Seed, Do #10) —
 * das Muster steht, nur das Licht bewegt sich; die Bitrate bleibt zahm.
 */
export const RoomDither: React.FC<{id: string}> = ({id}) => (
  <>
    <Grain id={`${id}-fine`} opacity={0.085} baseFrequency={0.55} />
    <Grain id={`${id}-broad`} opacity={0.05} baseFrequency={0.11} numOctaves={1} />
  </>
);

/**
 * Staubpartikel, die im Lichtkegel treiben. Positionen/Phasen kommen aus der
 * seeded remotion-`random()`-API — nie Math.random() (Determinismus-Gate!).
 */
export const DustMotes: React.FC<{
  frame: number;
  fps: number;
  width: number;
  height: number;
  count?: number;
}> = ({frame, fps, width, height, count = 26}) => {
  const motes = useMemo(
    () =>
      new Array(count).fill(0).map((_, i) => ({
        // Startpunkte im Kegel-Dreieck oben-links
        u: random(`dust-u-${i}`),
        v: random(`dust-v-${i}`),
        r: 2 + random(`dust-r-${i}`) * 3.6,
        speed: 0.35 + random(`dust-s-${i}`) * 0.75,
        phi: random(`dust-p-${i}`) * Math.PI * 2,
        tw: 0.5 + random(`dust-t-${i}`) * 1.1,
      })),
    [count],
  );
  const tSec = frame / fps;
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {motes.map((m, i) => {
        // Kegelachse: von (14 %, 2 %) diagonal nach unten-rechts. Partikel
        // driften langsam die Achse entlang und pendeln quer dazu.
        const along = (m.v + tSec * 0.012 * m.speed) % 1;
        const spread = along * 0.52 + 0.05;
        const cx = 0.14 + along * 0.52 + (m.u - 0.5) * spread * 1.5;
        const cy = 0.02 + along * 0.78 + Math.sin(tSec * m.speed + m.phi) * 0.012;
        const twinkle = 0.5 + 0.5 * Math.sin(tSec * m.tw * 2 + m.phi * 3);
        // Nur im Kegel sichtbar: seitlich der Achse blendet der Staub aus.
        const axisDist = Math.abs(m.u - 0.5) * 2;
        const inCone = clamp01(1 - axisDist) * clamp01(1.15 - along);
        const opacity = 0.22 * twinkle * inCone;
        if (opacity < 0.01) return null;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: cx * width,
              top: cy * height,
              width: m.r,
              height: m.r,
              borderRadius: '50%',
              background: PALETTE.lampengold,
              opacity,
              filter: 'blur(0.6px)',
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

/**
 * Warmer Lampen-Cast über der ganzen Bühne (soft-light): Papier im Kegel
 * nimmt das Lampengold an, statt kaltweiß aus dem Sepia-Zimmer zu stechen.
 * Wandert mit derselben `lampDrift`-Quelle wie der Kegel im Room.
 */
export const LampCast: React.FC<{
  frame: number;
  fps: number;
  opacity?: number;
}> = ({frame, fps, opacity = 0.5}) => {
  const drift = lampDrift(frame, fps);
  return (
    <AbsoluteFill
      style={{
        pointerEvents: 'none',
        mixBlendMode: 'soft-light',
        opacity,
        background: `radial-gradient(120% 90% at ${16 + drift.x}% ${4 + drift.y}%, rgba(255,196,107,0.9) 0%, rgba(255,196,107,0.35) 40%, rgba(32,22,19,0.5) 78%, rgba(32,22,19,0.7) 100%)`,
      }}
    />
  );
};

/**
 * Weicher Wurfschatten unter Papierobjekten — Licht 10 Uhr → Schatten 16 Uhr.
 * `parallaxX/Y` (Schattenparallaxe, Kino-Final-Eval): die Szenen reichen die
 * Objektbewegung GEGENLÄUFIG gedämpft hinein — der Schatten hängt physisch
 * der Bewegung nach, statt starr am Objekt zu kleben.
 */
export const PaperShadow: React.FC<{
  width: number;
  height: number;
  lift?: number; // 0 = liegt auf, 1 = schwebt hoch (weicher, größer, versetzt)
  opacity?: number;
  parallaxX?: number;
  parallaxY?: number;
}> = ({width, height, lift = 0, opacity = 0.42, parallaxX = 0, parallaxY = 0}) => (
  <div
    style={{
      position: 'absolute',
      left: '50%',
      top: '50%',
      width: width * (1 + lift * 0.16),
      height: height * (1 + lift * 0.16),
      transform: `translate(-50%, -50%) translate(${18 + lift * 46 + parallaxX}px, ${26 + lift * 70 + parallaxY}px)`,
      background: 'rgba(8,5,3,1)',
      opacity: opacity * (1 - lift * 0.45),
      borderRadius: 24,
      filter: `blur(${26 + lift * 40}px)`,
    }}
  />
);
