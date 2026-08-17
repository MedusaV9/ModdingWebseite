// FullRelease N1-C — geteilte Papier-Requisiten: Umschlag (Vorder-/Rückseite)
// und Wachssiegel. Alles rein geometrisch (Divs, Gradients, SVG) — kein Text,
// kein Font, kein Bitmap-Asset. Szene 2 stempelt die Vorderseite, Szene 3
// beginnt auf exakt demselben Endzustand und dreht auf die Siegel-Seite.
import React from 'react';
import {PALETTE} from '../look';

export const ENVELOPE = {
  w: 780,
  h: 548,
  centerY: 1216, // optisches Zentrum leicht über Bildmitte (2532/2 = 1266)
} as const;

const paperFace: React.CSSProperties = {
  position: 'absolute',
  inset: 0,
  borderRadius: 12,
  background: `linear-gradient(158deg, #FCF7EB 0%, ${PALETTE.brief} 46%, #EFE7D3 100%)`,
  boxShadow: `inset 0 0 0 2px rgba(227,214,188,0.65), inset 3px 4px 10px rgba(255,252,244,0.55), inset -4px -6px 14px rgba(90,74,56,0.14)`,
};

/** Abstrakte Anschrift: drei Tintenstriche + zwei Tintentropfen (A/B). */
const AddressStrokes: React.FC<{
  drawP: (idx: number) => number;
  dotsP: number;
  inkA: string;
  inkB: string;
}> = ({drawP, dotsP, inkA, inkB}) => {
  const strokes = [
    {y: 292, w: 344, x: 92},
    {y: 362, w: 252, x: 92},
    {y: 432, w: 302, x: 92},
  ];
  return (
    <>
      {strokes.map((st, i) => (
        <div
          key={i}
          style={{
            position: 'absolute',
            left: st.x,
            top: st.y,
            width: st.w,
            height: 9,
            borderRadius: 5,
            background: PALETTE.tinteDunkel,
            opacity: 0.82,
            transform: `scaleX(${drawP(i)})`,
            transformOrigin: '0% 50%',
          }}
        />
      ))}
      {/* zwei kleine Tintentropfen — leiser Vorgriff auf die Zwei-Tinten-Szene */}
      <div
        style={{
          position: 'absolute',
          left: 470,
          top: 466,
          width: 20,
          height: 20,
          borderRadius: '50% 50% 50% 4%',
          transform: 'rotate(45deg)',
          background: inkA,
          opacity: 0.85 * dotsP,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 514,
          top: 470,
          width: 16,
          height: 16,
          borderRadius: '50% 50% 50% 4%',
          transform: 'rotate(45deg)',
          background: inkB,
          opacity: 0.85 * dotsP,
        }}
      />
    </>
  );
};

/** Briefmarke: perforierter Rand, Innenbild = Lampenkegel-Miniatur. Textfrei. */
const Stamp: React.FC<{inkA: string; inkB: string}> = ({inkA, inkB}) => (
  <div
    style={{
      position: 'absolute',
      right: 56,
      top: 46,
      width: 150,
      height: 184,
      transform: 'rotate(2.5deg)',
      background: PALETTE.karton,
      // Perforation: gestanzte Kante als gestrichelte Linie im Papierton
      border: `5px dashed ${PALETTE.brief}`,
      boxShadow: '2px 3px 8px rgba(60,40,24,0.28)',
    }}
  >
    <div
      style={{
        position: 'absolute',
        inset: 10,
        background: `linear-gradient(165deg, ${inkA}55 0%, ${inkB}55 100%), linear-gradient(180deg, #3A2A1E 0%, #241A12 100%)`,
        boxShadow: `inset 0 0 0 2px ${PALETTE.kante}`,
        overflow: 'hidden',
      }}
    >
      {/* Miniatur-Lampenkegel als Markenbild */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: `radial-gradient(90% 70% at 22% 8%, rgba(255,196,107,0.85) 0%, rgba(255,196,107,0.2) 48%, rgba(255,196,107,0) 75%)`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: '20%',
          bottom: '14%',
          width: '60%',
          height: 8,
          borderRadius: 4,
          background: PALETTE.brief,
          opacity: 0.9,
        }}
      />
    </div>
  </div>
);

/**
 * „TAG 1" als GEOMETRIE (Kino-Final-Eval): vier monolinige Stempel-Glyphen
 * (T, A, G, 1) plus Wortabstand, EINMAL als Pfad-Konstanten in einer
 * 8×14-Einheitsbox definiert — KEIN Font, kein Text-Rendering (das
 * Linux-Font-Gate der Pipeline bleibt unberührt). Die Monolinie mit runden
 * Kappen ist die Letterform eines geprägten Datumstempels.
 */
const STAMP_GLYPHS: ReadonlyArray<{d: string; w: number}> = [
  // T: Balken + Stamm
  {d: 'M 0.6 0.9 L 7.4 0.9 M 4 0.9 L 4 13.1', w: 8},
  // A: zwei Schenkel + Querstrich
  {d: 'M 0.4 13.1 L 4 0.9 L 7.6 13.1 M 1.8 8.8 L 6.2 8.8', w: 8},
  // G: offener Bogen (Ellipsenbogen linksherum) + Innenbalken
  {d: 'M 7.3 2.9 A 3.9 5.2 0 1 0 7.3 11.1 L 7.3 7.7 L 4.7 7.7', w: 8},
  // Wortabstand (Leerraum-„Glyphe" — nur Vorschub, kein Pfad)
  {d: '', w: 3.4},
  // 1: Anstrich + Stamm + Fuß
  {d: 'M 1.6 3.2 L 4.4 0.9 L 4.4 13.1 M 1.8 13.1 L 7 13.1', w: 7},
];
const GLYPH_H = 14;
const GLYPH_TRACKING = 3.2;
const GLYPH_STROKE = 1.9;

/** Die Stempelzeile, zentriert um (cx, cy) in Stempel-Koordinaten. */
const StampLettering: React.FC<{cx: number; cy: number; scale: number}> = ({
  cx,
  cy,
  scale,
}) => {
  const totalW =
    STAMP_GLYPHS.reduce((sum, g) => sum + g.w, 0) +
    GLYPH_TRACKING * (STAMP_GLYPHS.length - 1);
  let penX = cx - (totalW * scale) / 2;
  const top = cy - (GLYPH_H * scale) / 2;
  return (
    <g strokeWidth={GLYPH_STROKE} strokeLinecap="round" strokeLinejoin="round">
      {STAMP_GLYPHS.map((glyph, i) => {
        const x = penX;
        penX += (glyph.w + GLYPH_TRACKING) * scale;
        if (!glyph.d) return null;
        return (
          <path
            key={i}
            d={glyph.d}
            transform={`translate(${x}, ${top}) scale(${scale})`}
          />
        );
      })}
    </g>
  );
};

/**
 * Poststempel: Doppelring, Kerben-Kranz, „TAG 1" als monolinige Glyphen-
 * Pfade (lesbar, aber fontlos) und Entwertungswellen nach links.
 * Wachs-Rot, multiply.
 */
const Postmark: React.FC<{scale: number; opacity: number; spread: number}> = ({
  scale,
  opacity,
  spread,
}) => {
  const ticks = new Array(28).fill(0);
  return (
    <svg
      width={620}
      height={360}
      viewBox="0 0 620 360"
      style={{
        position: 'absolute',
        left: 210,
        top: 66,
        opacity: opacity * 0.78,
        mixBlendMode: 'multiply',
        transform: `scale(${scale * (1 + spread * 0.012)}) rotate(-7deg)`,
        transformOrigin: '420px 170px',
        filter: `blur(${spread * 0.5}px)`,
      }}
    >
      <g stroke={PALETTE.wachs} fill="none">
        <circle cx={420} cy={170} r={140} strokeWidth={10} />
        <circle cx={420} cy={170} r={106} strokeWidth={4} />
        {ticks.map((_, i) => {
          const a = (i / ticks.length) * Math.PI * 2;
          const r0 = 114;
          const r1 = 130;
          return (
            <line
              key={i}
              x1={420 + Math.cos(a) * r0}
              y1={170 + Math.sin(a) * r0}
              x2={420 + Math.cos(a) * r1}
              y2={170 + Math.sin(a) * r1}
              strokeWidth={5}
              strokeLinecap="round"
            />
          );
        })}
        {/* „TAG 1" — geometrische Glyphen-Pfade in der Stempelmitte */}
        <StampLettering cx={420} cy={170} scale={3.9} />
        {/* Entwertungswellen */}
        {[130, 170, 210].map((y, i) => (
          <path
            key={y}
            d={`M ${292 - i * 6} ${y} q -30 -16 -60 0 t -60 0 t -60 0 t -60 0`}
            strokeWidth={7}
            strokeLinecap="round"
          />
        ))}
      </g>
    </svg>
  );
};

export interface EnvelopeFrontProps {
  inkA: string;
  inkB: string;
  addressDrawP: (idx: number) => number;
  inkDotsP: number;
  postmarkScale: number;
  postmarkOpacity: number;
  postmarkSpread: number;
  flash?: number;
}

/** Vorderseite: Anschrift-Striche, Briefmarke, Poststempel. */
export const EnvelopeFront: React.FC<EnvelopeFrontProps> = ({
  inkA,
  inkB,
  addressDrawP,
  inkDotsP,
  postmarkScale,
  postmarkOpacity,
  postmarkSpread,
  flash = 0,
}) => (
  <div style={{position: 'absolute', inset: 0}}>
    <div style={paperFace} />
    <AddressStrokes drawP={addressDrawP} dotsP={inkDotsP} inkA={inkA} inkB={inkB} />
    <Stamp inkA={inkA} inkB={inkB} />
    <Postmark scale={postmarkScale} opacity={postmarkOpacity} spread={postmarkSpread} />
    {/* Aufprall-Blitz beim Stempeln (2 Frames, kaum sichtbar, aber fühlbar) */}
    {flash > 0 ? (
      <div
        style={{
          position: 'absolute',
          inset: 0,
          borderRadius: 12,
          background: `radial-gradient(60% 60% at 66% 26%, rgba(255,244,220,${flash}) 0%, rgba(255,244,220,0) 70%)`,
        }}
      />
    ) : null}
  </div>
);

/** Rückseite: Taschen-Nähte + Klappe. Das Siegel setzt die Szene selbst drauf. */
export const EnvelopeBack: React.FC<{children?: React.ReactNode}> = ({children}) => (
  <div style={{position: 'absolute', inset: 0}}>
    <div style={paperFace} />
    {/* Taschen-Nähte von den unteren Ecken zur Mitte */}
    <svg
      width={ENVELOPE.w}
      height={ENVELOPE.h}
      viewBox={`0 0 ${ENVELOPE.w} ${ENVELOPE.h}`}
      style={{position: 'absolute', inset: 0}}
    >
      <g stroke={PALETTE.kante} strokeWidth={3} fill="none" opacity={0.85}>
        <path d={`M 6 ${ENVELOPE.h - 8} L ${ENVELOPE.w / 2} 306`} />
        <path d={`M ${ENVELOPE.w - 6} ${ENVELOPE.h - 8} L ${ENVELOPE.w / 2} 306`} />
      </g>
    </svg>
    {/* Klappe: dunkleres Karton-Dreieck mit Kantenlicht oben-links */}
    <div
      style={{
        position: 'absolute',
        inset: 0,
        clipPath: `polygon(0 0, 100% 0, 50% 62%)`,
        background: `linear-gradient(168deg, #F2EAD8 0%, ${PALETTE.karton} 42%, #E2D6BC 100%)`,
        borderRadius: 12,
        boxShadow: 'inset 3px 4px 8px rgba(255,252,244,0.5)',
      }}
    />
    <svg
      width={ENVELOPE.w}
      height={ENVELOPE.h}
      viewBox={`0 0 ${ENVELOPE.w} ${ENVELOPE.h}`}
      style={{position: 'absolute', inset: 0}}
    >
      <g stroke="rgba(90,74,56,0.4)" strokeWidth={3} fill="none">
        <path d={`M 4 4 L ${ENVELOPE.w / 2} ${ENVELOPE.h * 0.62}`} />
        <path d={`M ${ENVELOPE.w - 4} 4 L ${ENVELOPE.w / 2} ${ENVELOPE.h * 0.62}`} />
      </g>
    </svg>
    {children}
  </div>
);

/** CSS-Herz (Quadrat + zwei Kreise, 45° gedreht) — die Siegel-Prägung. */
const Heart: React.FC<{size: number; color: string; left: number; top: number}> = ({
  size,
  color,
  left,
  top,
}) => {
  const lobe: React.CSSProperties = {
    position: 'absolute',
    width: size,
    height: size,
    borderRadius: '50%',
    background: color,
  };
  return (
    <div
      style={{
        position: 'absolute',
        left,
        top,
        width: size,
        height: size,
        transform: 'rotate(45deg)',
      }}
    >
      <div style={{position: 'absolute', inset: 0, background: color}} />
      <div style={{...lobe, left: -size / 2, top: 0}} />
      <div style={{...lobe, left: 0, top: -size / 2}} />
    </div>
  );
};

/**
 * Wachssiegel: unregelmäßiger Blob, Licht von 10 Uhr, geprägtes Herz
 * (gedrückt: Licht-Gegenkante unten-rechts), drei Wachs-Nasen am Rand.
 */
export const WaxSeal: React.FC<{size: number}> = ({size}) => {
  const heartSize = size * 0.3;
  // Wachs-Nasen sitzen seitlich/unten und bleiben nah am Blob-Rand —
  // weiter außen/oben lasen sie wie Ohren (Still-Review-Befund).
  const drips = [
    {a: 0.055, r: 0.09},
    {a: 0.42, r: 0.075},
    {a: 0.24, r: 0.065},
  ];
  return (
    <div style={{position: 'absolute', width: size, height: size}}>
      {drips.map((d, i) => {
        const ang = d.a * Math.PI * 2;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: size / 2 + Math.cos(ang) * size * 0.43 - size * d.r,
              top: size / 2 + Math.sin(ang) * size * 0.43 - size * d.r,
              width: size * d.r * 2,
              height: size * d.r * 2,
              borderRadius: '50%',
              background: PALETTE.wachsTief,
            }}
          />
        );
      })}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          borderRadius: '48% 52% 50% 47% / 51% 46% 53% 49%',
          background: `radial-gradient(circle at 36% 30%, #C74B45 0%, ${PALETTE.wachs} 46%, #96302F 76%, ${PALETTE.wachsTief} 100%)`,
          boxShadow: `inset 5px 7px 12px rgba(255,214,178,0.3), inset -7px -9px 16px rgba(50,8,8,0.55), 8px 12px 22px rgba(0,0,0,0.4)`,
        }}
      />
      {/* Prägerand */}
      <div
        style={{
          position: 'absolute',
          inset: size * 0.13,
          borderRadius: '50%',
          border: `${Math.max(2, size * 0.02)}px solid rgba(110,31,31,0.7)`,
          boxShadow: 'inset 2px 3px 5px rgba(50,8,8,0.4), 1px 2px 2px rgba(255,214,178,0.18)',
        }}
      />
      {/* Herz-Prägung: helle Gegenkante unten-rechts, dunkle Prägung oben drauf */}
      <Heart
        size={heartSize}
        color="rgba(255,214,178,0.32)"
        left={size / 2 - heartSize / 2 + size * 0.014}
        top={size / 2 - heartSize / 3 + size * 0.018}
      />
      <Heart
        size={heartSize}
        color="rgba(94,20,20,0.92)"
        left={size / 2 - heartSize / 2}
        top={size / 2 - heartSize / 3}
      />
    </div>
  );
};
