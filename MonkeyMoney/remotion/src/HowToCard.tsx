// Tutorial-Template „HowToCard" (Plan §5.2): EIN parametrisiertes Template
// für alle Minispiel-Erklärvideos — Props rein, 18-s-Video raus.
// Musik-Bett: „Fluffing a Duck" (Kevin MacLeod, CC-BY 4.0 — Credit im Outro).
import React from "react";
import { AbsoluteFill, Audio, Img, interpolate, useCurrentFrame } from "remotion";
import {
  BigTitle,
  CLAMP,
  DeviceFrame,
  FormatStamp,
  M,
  SlideIn,
  SmallPrint,
  StageBackground,
  StampIn,
  StickerCard,
} from "./components";
import { FONT_DISPLAY, FONT_TEXT, PALETTE } from "./tokens";

export const HOWTO_FPS = 30;
export const HOWTO_FRAMES = 540; // 18 s

export type HowToProps = {
  spielName: string;
  untertitel: string;
  icon: string;
  accentColor: string;
  regeln: [string, string, string];
  rewardLine: string;
  screenshot: string;
  screenshotKind: "phone" | "screen";
};

const RULE_DELAYS = [80, 185, 290];
const REWARD_AT = 400;
const OUTRO_AT = 478;

export const HowToCard: React.FC<HowToProps> = ({
  spielName,
  untertitel,
  icon,
  accentColor,
  regeln,
  rewardLine,
  screenshot,
  screenshotKind,
}) => {
  const frame = useCurrentFrame();
  const outro = interpolate(frame, [OUTRO_AT, OUTRO_AT + 22], [0, 1], CLAMP);
  const fade = interpolate(frame, [HOWTO_FRAMES - 24, HOWTO_FRAMES], [0, 1], CLAMP);
  return (
    <AbsoluteFill style={{ backgroundColor: PALETTE.jungleNight }}>
      <Audio
        src={M("music/FluffingADuck.mp3")}
        volume={(f) => interpolate(f, [0, 20, 470, 530], [0, 0.65, 0.65, 0], CLAMP)}
      />
      <StageBackground floor />

      {/* Kopf: Icon + Spielname + „SO GEHT'S" */}
      <div
        style={{
          position: "absolute",
          top: 44,
          width: "100%",
          display: "flex",
          justifyContent: "center",
          alignItems: "center",
          gap: 30,
        }}
      >
        <StampIn delay={4} rotate={-6}>
          <div
            style={{
              width: 120,
              height: 120,
              borderRadius: 32,
              background: accentColor,
              border: `6px solid ${PALETTE.outline}`,
              boxShadow: "8px 9px 0 rgba(26,18,8,0.4)",
              display: "flex",
              justifyContent: "center",
              alignItems: "center",
              fontSize: 70,
            }}
          >
            {icon}
          </div>
        </StampIn>
        <StampIn delay={8}>
          <div>
            <div
              style={{
                fontFamily: FONT_TEXT,
                fontWeight: 700,
                fontSize: 30,
                letterSpacing: 4,
                color: accentColor,
              }}
            >
              SO GEHT&apos;S:
            </div>
            <BigTitle size={84} color={PALETTE.banana} style={{ textAlign: "left" }}>
              {spielName}
            </BigTitle>
            <div
              style={{
                fontFamily: FONT_TEXT,
                fontWeight: 600,
                fontSize: 30,
                color: "rgba(255,246,227,0.85)",
              }}
            >
              {untertitel}
            </div>
          </div>
        </StampIn>
      </div>

      {/* Links: Geräte-Mockup mit echtem Screen */}
      <SlideIn
        delay={22}
        from="left"
        dist={640}
        style={{ position: "absolute", left: 110, top: screenshotKind === "phone" ? 300 : 360 }}
      >
        {screenshotKind === "phone" ? (
          <DeviceFrame
            src={M(screenshot)}
            width={296}
            height={640}
            kind="phone"
            style={{ transform: "rotate(-3deg)" }}
          />
        ) : (
          <DeviceFrame
            src={M(screenshot)}
            width={780}
            height={487}
            style={{ transform: "rotate(-2deg)" }}
          />
        )}
      </SlideIn>

      {/* Rechts: die 3 Regeln */}
      <div
        style={{
          position: "absolute",
          right: 90,
          top: 300,
          width: screenshotKind === "phone" ? 1250 : 860,
          display: "flex",
          flexDirection: "column",
          gap: 34,
        }}
      >
        {regeln.map((regel, i) => (
          <SlideIn key={regel} delay={RULE_DELAYS[i]} from="right" dist={520}>
            <div style={{ display: "flex", alignItems: "center", gap: 26 }}>
              <div
                style={{
                  minWidth: 92,
                  height: 92,
                  borderRadius: "50%",
                  background: PALETTE.banana,
                  border: `6px solid ${PALETTE.outline}`,
                  boxShadow: "6px 7px 0 rgba(26,18,8,0.4)",
                  display: "flex",
                  justifyContent: "center",
                  alignItems: "center",
                  fontFamily: FONT_DISPLAY,
                  fontSize: 46,
                  color: PALETTE.outline,
                  transform: `rotate(${i % 2 === 0 ? -4 : 4}deg)`,
                }}
              >
                {i + 1}
              </div>
              <StickerCard style={{ flex: 1, padding: "22px 34px" }}>
                <div
                  style={{
                    fontFamily: FONT_TEXT,
                    fontWeight: 600,
                    fontSize: 37,
                    lineHeight: 1.35,
                    color: PALETTE.outline,
                  }}
                >
                  {regel}
                </div>
              </StickerCard>
            </div>
          </SlideIn>
        ))}
      </div>

      {/* Belohnungs-Zeile */}
      <div
        style={{
          position: "absolute",
          bottom: 120,
          width: "100%",
          display: "flex",
          justifyContent: "center",
        }}
      >
        <FormatStamp
          text={rewardLine}
          bg={accentColor}
          color={PALETTE.outline}
          delay={REWARD_AT}
          rotate={-2}
          size={48}
        />
      </div>

      {/* Outro: Logo-Bumper + Credit */}
      <AbsoluteFill
        style={{
          background: `rgba(10, 20, 14, ${outro * 0.82})`,
          justifyContent: "center",
          alignItems: "center",
          opacity: outro > 0 ? 1 : 0,
          pointerEvents: "none",
        }}
      >
        <StampIn delay={OUTRO_AT + 6}>
          <Img src={M("img/monkey-money-logo.png")} style={{ width: 520 }} />
        </StampIn>
        <SmallPrint style={{ position: "absolute", bottom: 30, width: "100%", fontSize: 22 }}>
          Musik: „Fluffing a Duck“ — Kevin MacLeod (incompetech.com) · CC BY 4.0
        </SmallPrint>
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "#000", opacity: fade, pointerEvents: "none" }} />
    </AbsoluteFill>
  );
};

export const vierLianenProps: HowToProps = {
  spielName: "Vier Lianen",
  untertitel: "Das Quiz-Grundformat — jede Frage, vier Lianen",
  icon: "🌴",
  accentColor: "#29D9D5",
  regeln: [
    "Frage auf der LED-Wand — vier Lianen: A 🍌 B 🥥 C 🐒 D 🌴",
    "Antwort auf dem Handy antippen, Münze einwerfen = eingeloggt",
    "Richtig = Money aufs Podium — schnelle Affen kassieren extra!",
  ],
  rewardLine: "PRO TREFFER: MONEY! 💵",
  screenshot: "screens/mm_tour_06_phone_frage.png",
  screenshotKind: "phone",
};

export const stinkbananeProps: HowToProps = {
  spielName: "Die Stinkbanane",
  untertitel: "Heiße Kartoffel mit Zündschnur — nur härter",
  icon: "🍌",
  accentColor: "#C2183B",
  regeln: [
    "Die Stinkbanane wandert im Sitzkreis — wer sie hält, muss antworten",
    "Richtig beantwortet = weitergeben: +150 MM pro Weitergabe",
    "PLATZT sie bei dir: −500 MM — direkt ins Jackpot-Glas!",
  ],
  rewardLine: "2 DURCHGÄNGE. NERVEN BEHALTEN! 💥",
  screenshot: "screens/mm_test1_doc_stinkbanane_sitzkreis.png",
  screenshotKind: "screen",
};
