import React from 'react';
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {COLORS, FONT_FAMILY} from '../theme';

const FEATURES = [
  'Komplett neu in 3D',
  '36 Minispiele',
  'NEU: Gooby Ranch',
  'Offene Welt & Wetter',
  'Turnier-Liga',
  'Multiplayer & Ausritte',
  'Quests & NPCs',
  'Gestalten-Modus',
  '92 Kosmetik-Teile',
  'Bauen & GOUHBUS',
];

const CHIP_COLORS = [
  COLORS.pink,
  COLORS.teal,
  COLORS.gold,
  COLORS.tealDark,
  COLORS.pinkDark,
  COLORS.yellow,
  COLORS.teal,
  COLORS.pink,
  COLORS.tealDark,
  COLORS.gold,
];

/** Gelb/Gold-Chips brauchen dunklen Text. */
const DUNKLE_SCHRIFT = new Set([2, 5, 9]);

/** Outro: Feature-Chips wirbeln um das Logo, dann Claim + Musik-Credit. */
export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const logo = spring({frame: frame - 4, fps, config: {damping: 11, stiffness: 130}});
  const claim = spring({frame: frame - 40, fps, config: {damping: 12, stiffness: 130}});
  const wobble = Math.sin(frame / 16) * 2;
  const creditOpacity = interpolate(frame, [70, 95], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: COLORS.cream,
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      {FEATURES.map((feat, i) => {
        const winkel = (i / FEATURES.length) * Math.PI * 2 - Math.PI / 2;
        const chip = spring({
          frame: frame - 10 - i * 4,
          fps,
          config: {damping: 13, stiffness: 110},
        });
        // Bei 10 Chips liegen die Diagonalen nah am Claim-Text — Ellipse
        // groß genug, damit nichts überlappt (1080p-Layout geprüft).
        const radiusX = 740;
        const radiusY = 450;
        const x = Math.cos(winkel) * radiusX * chip;
        const y = Math.sin(winkel) * radiusY * chip;
        return (
          <div
            key={feat}
            style={{
              position: 'absolute',
              left: '50%',
              top: '46%',
              transform: `translate(calc(-50% + ${x}px), calc(-50% + ${y}px)) scale(${chip}) rotate(${(i % 2 === 0 ? 1 : -1) * 3}deg)`,
              fontFamily: FONT_FAMILY,
              fontWeight: 700,
              fontSize: 33,
              color: DUNKLE_SCHRIFT.has(i) ? COLORS.brown : COLORS.white,
              backgroundColor: CHIP_COLORS[i],
              borderRadius: 999,
              padding: '10px 30px 13px',
              boxShadow: '0 8px 26px rgba(74, 59, 54, 0.22)',
              whiteSpace: 'nowrap',
            }}
          >
            {feat}
          </div>
        );
      })}
      <Img
        src={staticFile('img/icon.png')}
        style={{
          width: 300,
          height: 300,
          borderRadius: 66,
          boxShadow: '0 20px 70px rgba(74, 59, 54, 0.3)',
          transform: `scale(${logo}) rotate(${wobble}deg)`,
          marginTop: -110,
        }}
      />
      <div
        style={{
          fontFamily: FONT_FAMILY,
          fontWeight: 800,
          fontSize: 108,
          color: COLORS.brown,
          marginTop: 26,
          transform: `scale(${Math.max(claim, 0.001)})`,
          textShadow: '0 5px 0 rgba(89, 201, 185, 0.35)',
        }}
      >
        GOOBY 5.0
      </div>
      <div
        style={{
          fontFamily: FONT_FAMILY,
          fontWeight: 700,
          fontSize: 46,
          color: COLORS.inkSoft,
          marginTop: 2,
          transform: `scale(${Math.max(claim, 0.001)})`,
        }}
      >
        Godot Engine Update — jetzt spielen!
      </div>
      <div
        style={{
          position: 'absolute',
          bottom: 28,
          fontFamily: FONT_FAMILY,
          fontWeight: 600,
          fontSize: 24,
          color: COLORS.inkSoft,
          opacity: creditOpacity,
        }}
      >
        Musik: „Glitter Blast“ — Kevin MacLeod (incompetech.com), CC BY 4.0
      </div>
    </AbsoluteFill>
  );
};
