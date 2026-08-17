// Wiederverwendbare Bausteine im Sticker-Stil (Plan §1.3): Bühne, Stempel,
// Geräte-Rahmen, Money-Regen, Münz-Burst, Bananen-Wipe, Fake-QR.
import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  random,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { FONT_DISPLAY, FONT_TEXT, PALETTE, STICKER_BORDER, STICKER_SHADOW } from "./tokens";

export const M = (p: string): string => staticFile(`material/${p}`);

export const CLAMP = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;

const Leaf: React.FC<{ style: React.CSSProperties }> = ({ style }) => (
  <div
    style={{
      position: "absolute",
      width: 460,
      height: 260,
      borderRadius: "50% 50% 50% 8%",
      background: PALETTE.deepPalm,
      opacity: 0.55,
      ...style,
    }}
  />
);

/** Studio-Hintergrund: Jungle Night + max. 2 Radial-Verläufe (Gesetz 4). */
export const StageBackground: React.FC<{ floor?: boolean; dim?: number }> = ({
  floor = false,
  dim = 0,
}) => (
  <AbsoluteFill style={{ backgroundColor: PALETTE.jungleNight }}>
    <AbsoluteFill
      style={{
        background:
          "radial-gradient(ellipse 62% 58% at 50% -12%, rgba(245,179,1,0.20), rgba(245,179,1,0) 70%)",
      }}
    />
    <AbsoluteFill
      style={{
        background:
          "radial-gradient(ellipse 48% 42% at 50% 110%, rgba(34,165,89,0.22), rgba(34,165,89,0) 70%)",
      }}
    />
    <Leaf style={{ left: -180, top: -110, transform: "rotate(28deg)" }} />
    <Leaf style={{ right: -200, top: -90, transform: "rotate(-34deg) scaleX(-1)" }} />
    <Leaf style={{ left: -230, bottom: -60, transform: "rotate(-18deg)" }} />
    <Leaf style={{ right: -240, bottom: -80, transform: "rotate(22deg) scaleX(-1)" }} />
    {floor ? (
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: 96,
          background: PALETTE.deepPalm,
          borderTop: STICKER_BORDER,
        }}
      >
        <div
          style={{
            height: 12,
            background: PALETTE.vaultGold,
            borderBottom: `4px solid ${PALETTE.outline}`,
          }}
        />
      </div>
    ) : null}
    {dim > 0 ? <AbsoluteFill style={{ background: `rgba(10, 20, 14, ${dim})` }} /> : null}
  </AbsoluteFill>
);

/** Skaliert Kinder per Spring-Overshoot ein („stempelt sich ein"). */
export const StampIn: React.FC<{
  delay?: number;
  rotate?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ delay = 0, rotate = 0, children, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({
    frame: frame - delay,
    fps,
    config: { damping: 11, stiffness: 170, mass: 0.7 },
  });
  return (
    <div
      style={{
        transform: `scale(${s}) rotate(${rotate}deg)`,
        opacity: frame < delay ? 0 : 1,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

/** Gleitet Kinder aus einer Richtung ein (Spring, ohne Blur). */
export const SlideIn: React.FC<{
  delay?: number;
  from?: "left" | "right" | "bottom" | "top";
  dist?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ delay = 0, from = "bottom", dist = 420, children, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({
    frame: frame - delay,
    fps,
    config: { damping: 14, stiffness: 130, mass: 0.8 },
  });
  const off = (1 - p) * dist;
  const t =
    from === "left"
      ? `translateX(${-off}px)`
      : from === "right"
        ? `translateX(${off}px)`
        : from === "top"
          ? `translateY(${-off}px)`
          : `translateY(${off}px)`;
  return <div style={{ transform: t, opacity: frame < delay ? 0 : 1, ...style }}>{children}</div>;
};

/** Papier-Karte im Sticker-Prinzip (Fläche + Outline + harter Schatten). */
export const StickerCard: React.FC<{
  bg?: string;
  style?: React.CSSProperties;
  children: React.ReactNode;
}> = ({ bg = PALETTE.ticketPaper, style, children }) => (
  <div
    style={{
      background: bg,
      border: STICKER_BORDER,
      borderRadius: 28,
      boxShadow: STICKER_SHADOW,
      padding: "28px 44px",
      ...style,
    }}
  >
    {children}
  </div>
);

/** Display-Headline in Bungee mit hartem Versatz-Schatten. */
export const BigTitle: React.FC<{
  size?: number;
  color?: string;
  style?: React.CSSProperties;
  children: React.ReactNode;
}> = ({ size = 110, color = PALETTE.banana, style, children }) => (
  <div
    style={{
      fontFamily: FONT_DISPLAY,
      fontSize: size,
      color,
      textTransform: "uppercase",
      textAlign: "center",
      lineHeight: 1.1,
      textShadow: "6px 7px 0 rgba(26,18,8,0.85)",
      ...style,
    }}
  >
    {children}
  </div>
);

/** Rotierter Format-Stempel (z. B. „GLÜCKSRAD!"). */
export const FormatStamp: React.FC<{
  text: string;
  bg?: string;
  color?: string;
  delay?: number;
  rotate?: number;
  size?: number;
  style?: React.CSSProperties;
}> = ({
  text,
  bg = PALETTE.banana,
  color = PALETTE.outline,
  delay = 0,
  rotate = -4,
  size = 60,
  style,
}) => (
  <StampIn delay={delay} rotate={rotate} style={style}>
    <div
      style={{
        background: bg,
        border: STICKER_BORDER,
        borderRadius: 22,
        boxShadow: STICKER_SHADOW,
        padding: "16px 42px",
        fontFamily: FONT_DISPLAY,
        fontSize: size,
        color,
        whiteSpace: "nowrap",
      }}
    >
      {text}
    </div>
  </StampIn>
);

/** iPad-/iPhone-Mockup als Rounded-Rect mit Gold-Rahmen (Casino-Gold = Rahmen). */
export const DeviceFrame: React.FC<{
  src: string;
  width: number;
  height: number;
  kind?: "phone" | "tablet";
  style?: React.CSSProperties;
}> = ({ src, width, height, kind = "tablet", style }) => {
  const pad = kind === "phone" ? 14 : 20;
  const radius = kind === "phone" ? 46 : 34;
  return (
    <div
      style={{
        background: PALETTE.outline,
        padding: pad,
        borderRadius: radius,
        border: `5px solid ${PALETTE.vaultGold}`,
        boxShadow: STICKER_SHADOW,
        ...style,
      }}
    >
      {kind === "phone" ? (
        <div
          style={{
            width: 84,
            height: 8,
            borderRadius: 4,
            background: "#3a3125",
            margin: "0 auto 8px",
          }}
        />
      ) : null}
      <Img
        src={src}
        style={{
          width,
          height,
          borderRadius: radius - pad,
          display: "block",
          objectFit: "cover",
        }}
      />
    </div>
  );
};

/** Deterministischer Money-Regen (Banana-Buck-Scheine, reine Frame-Funktion). */
export const MoneyRain: React.FC<{ count?: number; opacity?: number }> = ({
  count = 60,
  opacity = 1,
}) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  return (
    <AbsoluteFill style={{ opacity, pointerEvents: "none" }}>
      {Array.from({ length: count }).map((_, i) => {
        const x0 = random(`mr-x-${i}`) * (width + 80) - 40;
        const speed = 300 + random(`mr-s-${i}`) * 260;
        const phase = random(`mr-p-${i}`) * 900;
        const w = 68 + random(`mr-w-${i}`) * 52;
        const t = (frame + phase) / fps;
        const y = ((speed * t) % (height + 260)) - 160;
        const sway = Math.sin(t * 2.2 + i) * 46;
        const rot = Math.sin(t * 2.8 + i * 1.7) * 50;
        return (
          <Img
            key={i}
            src={M("img/schein.svg")}
            style={{
              position: "absolute",
              left: x0 + sway,
              top: y,
              width: w,
              transform: `rotate(${rot}deg)`,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

/** Münzen-Burst vom Zentrum (Logo-Stinger), ballistisch + deterministisch. */
export const CoinBurst: React.FC<{ startFrame?: number; count?: number }> = ({
  startFrame = 0,
  count = 16,
}) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = (frame - startFrame) / fps;
  if (t < 0) return null;
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {Array.from({ length: count }).map((_, i) => {
        const a = (i / count) * Math.PI * 2 + random(`cb-a-${i}`) * 0.5;
        const v = 520 + random(`cb-v-${i}`) * 520;
        const vx = Math.cos(a) * v;
        const vy = -Math.abs(Math.sin(a)) * v - 260;
        const x = width / 2 + vx * t;
        const y = height / 2 + 40 + vy * t + 0.5 * 1900 * t * t;
        const rot = t * (120 + random(`cb-r-${i}`) * 240);
        const size = 44 + random(`cb-s-${i}`) * 40;
        if (y > height + 120) return null;
        return (
          <Img
            key={i}
            src={M("img/muenze.svg")}
            style={{
              position: "absolute",
              left: x - size / 2,
              top: y - size / 2,
              width: size,
              transform: `rotate(${rot}deg)`,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

/** 2-Frame-Weißblitz für harte TV-Schnitte (Plan §3.2). */
export const WhiteFlash: React.FC<{ at: number }> = ({ at }) => {
  const frame = useCurrentFrame();
  if (frame < at || frame > at + 4) return null;
  const opacity = interpolate(frame, [at, at + 1, at + 4], [0.85, 0.75, 0], CLAMP);
  return <AbsoluteFill style={{ background: "#fff", opacity }} />;
};

/** Bananen-Wipe: gelbes Band fegt (mit Banane an der Kante) übers Bild. */
export const BananaWipe: React.FC<{ duration?: number }> = ({ duration = 24 }) => {
  const frame = useCurrentFrame();
  const x = interpolate(frame, [0, duration], [-3000, 3000], {
    ...CLAMP,
    easing: Easing.inOut(Easing.cubic),
  });
  return (
    <AbsoluteFill style={{ overflow: "hidden", pointerEvents: "none" }}>
      <div
        style={{
          position: "absolute",
          top: -420,
          left: -100,
          width: 2600,
          height: 2000,
          background: PALETTE.banana,
          borderLeft: `14px solid ${PALETTE.outline}`,
          borderRight: `14px solid ${PALETTE.outline}`,
          transform: `translateX(${x}px) rotate(-8deg)`,
        }}
      >
        <Img
          src={M("img/timer-banane.svg")}
          style={{
            position: "absolute",
            right: -150,
            top: "46%",
            width: 260,
            transform: "rotate(24deg)",
          }}
        />
      </div>
    </AbsoluteFill>
  );
};

/** QR-Platzhalter (deterministisches Muster, kein echter Code). */
export const FakeQr: React.FC<{ size?: number }> = ({ size = 300 }) => {
  const n = 21;
  const cell = size / n;
  const inFinder = (r: number, c: number): boolean =>
    (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);
  const cells: Array<[number, number]> = [];
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (inFinder(r, c)) continue;
      if (random(`qr-${r}-${c}`) > 0.52) cells.push([r, c]);
    }
  }
  const finder = (cx: number, cy: number) => (
    <g key={`f-${cx}-${cy}`}>
      <rect x={cx * cell} y={cy * cell} width={7 * cell} height={7 * cell} fill={PALETTE.outline} />
      <rect
        x={(cx + 1) * cell}
        y={(cy + 1) * cell}
        width={5 * cell}
        height={5 * cell}
        fill="#fff"
      />
      <rect
        x={(cx + 2) * cell}
        y={(cy + 2) * cell}
        width={3 * cell}
        height={3 * cell}
        fill={PALETTE.outline}
      />
    </g>
  );
  return (
    <div
      style={{
        background: "#fff",
        padding: 20,
        borderRadius: 18,
        border: STICKER_BORDER,
        boxShadow: STICKER_SHADOW,
        display: "inline-block",
      }}
    >
      <svg width={size} height={size}>
        {cells.map(([r, c]) => (
          <rect
            key={`${r}-${c}`}
            x={c * cell}
            y={r * cell}
            width={cell * 0.92}
            height={cell * 0.92}
            fill={PALETTE.outline}
          />
        ))}
        {finder(0, 0)}
        {finder(n - 7, 0)}
        {finder(0, n - 7)}
      </svg>
    </div>
  );
};

/** Kleiner Rubik-Hinweistext (z. B. Credits, „echtes Gameplay"). */
export const SmallPrint: React.FC<{
  style?: React.CSSProperties;
  children: React.ReactNode;
}> = ({ style, children }) => (
  <div
    style={{
      fontFamily: FONT_TEXT,
      fontSize: 26,
      color: "rgba(255, 246, 227, 0.78)",
      textAlign: "center",
      lineHeight: 1.5,
      ...style,
    }}
  >
    {children}
  </div>
);
