// Die 9 Shots des Trailers (Storyboard: ART-SOUND-VIDEO-PLAN §5.2, angepasst
// auf vorhandenes Material: echte Gameplay-Screens statt Blender-Stinger).
import React from "react";
import {
  AbsoluteFill,
  Img,
  Sequence,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import {
  BigTitle,
  CLAMP,
  CoinBurst,
  DeviceFrame,
  FakeQr,
  FormatStamp,
  M,
  MoneyRain,
  SlideIn,
  SmallPrint,
  StageBackground,
  StampIn,
  StickerCard,
  WhiteFlash,
} from "../components";
import { FONT_DISPLAY, FONT_TEXT, PALETTE, PLAYER_COLORS } from "../tokens";

// ---------- Shot 1 · Logo-Stinger (0–5 s) ----------
export const ShotLogo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const glow = interpolate(frame, [0, 26], [0, 1], CLAMP);
  const logoScale = spring({
    frame: frame - 18,
    fps,
    config: { damping: 12, stiffness: 120, mass: 0.9 },
  });
  const subOp = interpolate(frame, [72, 92], [0, 1], CLAMP);
  return (
    <AbsoluteFill style={{ backgroundColor: PALETTE.jungleNight }}>
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(circle at 50% 46%, rgba(245,179,1,0.35), rgba(245,179,1,0) 55%)",
          opacity: glow,
          transform: `scale(${0.4 + glow * 1.1})`,
        }}
      />
      <CoinBurst startFrame={24} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
        <Img
          src={M("img/monkey-money-logo.png")}
          style={{
            width: 880,
            transform: `scale(${logoScale})`,
            opacity: frame < 18 ? 0 : 1,
          }}
        />
        {/* Bungee statt Rubik-Uppercase: dessen Ü-Punkte verschluckt Chrome
            in Video-Renders sobald die Opacity-Ebene kollabiert (deterministisch
            reproduzierbar); Bungee rendert das Ü in allen Frames sauber. */}
        <div
          style={{
            opacity: subOp,
            marginTop: -6,
            fontFamily: FONT_DISPLAY,
            fontSize: 40,
            color: PALETTE.ticketPaper,
            textShadow: "4px 5px 0 rgba(26,18,8,0.85)",
          }}
        >
          DIE QUIZ-SHOW FÜR EUER WOHNZIMMER
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ---------- Shot 2 · Problem/Promise (5–11 s) ----------
export const ShotHook: React.FC = () => {
  const frame = useCurrentFrame();
  const chips: Array<[string, string]> = [
    ["📺", "EIN IPAD."],
    ["📱", "EURE HANDYS."],
    ["🎪", "EINE SHOW."],
  ];
  return (
    <AbsoluteFill>
      <StageBackground dim={0.25} />
      {frame < 85 ? (
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", gap: 30 }}>
          <StampIn delay={4} rotate={-2}>
            <div style={{ fontSize: 130, textAlign: "center" }}>😴</div>
          </StampIn>
          <BigTitle size={92} color={PALETTE.ticketPaper}>
            Spieleabend
            <br />
            eingeschlafen?
          </BigTitle>
        </AbsoluteFill>
      ) : (
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", gap: 56 }}>
          <div style={{ display: "flex", gap: 44 }}>
            {chips.map(([emoji, text], i) => (
              <StampIn key={text} delay={88 + i * 16} rotate={i % 2 === 0 ? -3 : 3}>
                <StickerCard style={{ textAlign: "center", padding: "34px 46px" }}>
                  <div style={{ fontSize: 96 }}>{emoji}</div>
                  <div
                    style={{
                      fontFamily: FONT_DISPLAY,
                      fontSize: 52,
                      color: PALETTE.outline,
                      marginTop: 10,
                    }}
                  >
                    {text}
                  </div>
                </StickerCard>
              </StampIn>
            ))}
          </div>
          <StampIn delay={140}>
            <BigTitle size={64} color={PALETTE.banana}>
              Kein Download. Nur Buzzer-Daumen.
            </BigTitle>
          </StampIn>
        </AbsoluteFill>
      )}
      <WhiteFlash at={85} />
    </AbsoluteFill>
  );
};

// ---------- Shot 3 · Die 8 Affen im Lineup (11–19 s) ----------
const MONKEYS: Array<[string, string]> = [
  ["don-bananas.svg", "Don Bananas"],
  ["gitti-giro.svg", "Gitti Giro"],
  ["kiki-krawall.svg", "Kiki Krawall"],
  ["baron-von-bananenstein.svg", "Baron Bodo"],
  ["oma-zinseszins.svg", "Oma Zinseszins"],
  ["pumper-paule.svg", "Pumper-Paule"],
  ["schnarch-schorsch.svg", "Schnarch-Schorsch"],
  ["glitzer-gina.svg", "Glitzer-Gina"],
];

export const ShotLineup: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill>
      <StageBackground floor />
      <StampIn delay={4} rotate={-2} style={{ position: "absolute", top: 58, width: "100%" }}>
        <BigTitle size={96}>Die Bande</BigTitle>
      </StampIn>
      <div
        style={{
          position: "absolute",
          bottom: 104,
          left: 0,
          right: 0,
          display: "flex",
          justifyContent: "center",
          alignItems: "flex-end",
          gap: 24,
        }}
      >
        {MONKEYS.map(([file, name], i) => {
          const bob = Math.sin(frame / 9 + i * 1.3) * 6;
          return (
            <SlideIn key={file} delay={14 + i * 11} from="bottom" dist={520}>
              <div
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  gap: 12,
                  transform: `translateY(${bob}px)`,
                }}
              >
                <Img src={M(`monkeys/${file}`)} style={{ width: 200 }} />
                <div
                  style={{
                    background: PLAYER_COLORS[i],
                    border: `5px solid ${PALETTE.outline}`,
                    borderRadius: 14,
                    boxShadow: "5px 6px 0 rgba(26,18,8,0.4)",
                    padding: "6px 14px",
                    fontFamily: FONT_TEXT,
                    fontWeight: 700,
                    fontSize: 24,
                    color: PALETTE.outline,
                    whiteSpace: "nowrap",
                    transform: `rotate(${i % 2 === 0 ? -2 : 2}deg)`,
                  }}
                >
                  {name}
                </div>
              </div>
            </SlideIn>
          );
        })}
      </div>
      <StampIn
        delay={130}
        style={{ position: "absolute", top: 190, width: "100%", textAlign: "center" }}
      >
        <SmallPrint style={{ fontSize: 40, fontWeight: 700 }}>
          8 Affen. 8 Egos. Ein Jackpot.
        </SmallPrint>
      </StampIn>
    </AbsoluteFill>
  );
};

// ---------- Shot 4 · So funktioniert's (19–27 s) ----------
export const ShotHow: React.FC = () => (
  <AbsoluteFill>
    <StageBackground dim={0.15} />
    <StampIn delay={2} rotate={-2} style={{ position: "absolute", top: 48, width: "100%" }}>
      <BigTitle size={72} color={PALETTE.studioLed}>
        So funktioniert&apos;s
      </BigTitle>
    </StampIn>
    <SlideIn
      delay={10}
      from="left"
      dist={700}
      style={{ position: "absolute", left: 120, top: 218 }}
    >
      <DeviceFrame src={M("screens/mm_tour_02_studio_lobby.png")} width={960} height={600} />
    </SlideIn>
    <SlideIn
      delay={26}
      from="right"
      dist={700}
      style={{ position: "absolute", right: 150, top: 200 }}
    >
      <DeviceFrame
        src={M("screens/mm_tour_01_phone_join_affenwahl.png")}
        width={286}
        height={618}
        kind="phone"
        style={{ transform: "rotate(3deg)" }}
      />
    </SlideIn>
    <StampIn
      delay={48}
      rotate={-2}
      style={{
        position: "absolute",
        bottom: 64,
        width: "100%",
        display: "flex",
        justifyContent: "center",
      }}
    >
      <StickerCard style={{ textAlign: "center", padding: "24px 56px" }}>
        <div style={{ fontFamily: FONT_DISPLAY, fontSize: 54, color: PALETTE.outline }}>
          Handy = Buzzer. Kein Download.
        </div>
        <div
          style={{
            fontFamily: FONT_TEXT,
            fontSize: 32,
            fontWeight: 600,
            color: PALETTE.outline,
            marginTop: 8,
          }}
        >
          QR scannen · Affen aussuchen · drin — in 10 Sekunden.
        </div>
      </StickerCard>
    </StampIn>
  </AbsoluteFill>
);

// ---------- Shot 5 · Gameplay-Montage (27–39 s) ----------
const MontageClip: React.FC<{
  src: string;
  stamp: string;
  stampBg: string;
  stampColor?: string;
}> = ({ src, stamp, stampBg, stampColor = PALETTE.outline }) => {
  const frame = useCurrentFrame();
  const zoom = interpolate(frame, [0, 90], [1, 1.06]);
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <div style={{ transform: `scale(${zoom})` }}>
        <DeviceFrame src={src} width={1180} height={737} />
      </div>
      <div style={{ position: "absolute", left: 110, bottom: 74 }}>
        <FormatStamp text={stamp} bg={stampBg} color={stampColor} delay={6} rotate={-5} />
      </div>
    </AbsoluteFill>
  );
};

const MontagePhones: React.FC = () => {
  const frame = useCurrentFrame();
  const zoom = interpolate(frame, [0, 90], [1, 1.05]);
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <div style={{ display: "flex", gap: 70, transform: `scale(${zoom})` }}>
        <SlideIn delay={2} from="bottom" dist={260}>
          <DeviceFrame
            src={M("screens/mm_tour_06_phone_frage.png")}
            width={300}
            height={649}
            kind="phone"
            style={{ transform: "rotate(-3deg)" }}
          />
        </SlideIn>
        <SlideIn delay={10} from="bottom" dist={260}>
          <DeviceFrame
            src={M("screens/mm_tour_07_phone_muenz_lockin.png")}
            width={300}
            height={649}
            kind="phone"
            style={{ transform: "rotate(3deg) translateY(30px)" }}
          />
        </SlideIn>
      </div>
      <div style={{ position: "absolute", left: 110, bottom: 74 }}>
        <FormatStamp text="MÜNZE REIN = EINGELOGGT" bg={PALETTE.banana} delay={8} rotate={-5} />
      </div>
    </AbsoluteFill>
  );
};

export const ShotMontage: React.FC = () => (
  <AbsoluteFill>
    <StageBackground dim={0.2} />
    <Sequence durationInFrames={90}>
      <MontageClip
        src={M("screens/mm_tour_05_frage_ledwand.png")}
        stamp="VIER LIANEN 🌴"
        stampBg={PALETTE.studioLed}
      />
    </Sequence>
    <Sequence from={90} durationInFrames={90}>
      <MontagePhones />
    </Sequence>
    <Sequence from={180} durationInFrames={90}>
      <MontageClip
        src={M("screens/mm_test1_doc_stinkbanane_sitzkreis.png")}
        stamp="DIE STINKBANANE 💥"
        stampBg={PALETTE.curtain}
        stampColor={PALETTE.ticketPaper}
      />
    </Sequence>
    <Sequence from={270} durationInFrames={90}>
      <MontageClip
        src={M("screens/mm_tour_08_aufloesung_podium.png")}
        stamp="RICHTIG = MONEY! 💵"
        stampBg={PALETTE.leaf}
      />
    </Sequence>
    <WhiteFlash at={90} />
    <WhiteFlash at={180} />
    <WhiteFlash at={270} />
    <div
      style={{
        position: "absolute",
        top: 44,
        right: 60,
        background: "rgba(26,18,8,0.72)",
        border: `4px solid ${PALETTE.banana}`,
        borderRadius: 14,
        padding: "10px 22px",
        fontFamily: FONT_TEXT,
        fontWeight: 700,
        fontSize: 28,
        color: PALETTE.banana,
        transform: "rotate(2deg)",
      }}
    >
      ● ECHTES GAMEPLAY
    </div>
  </AbsoluteFill>
);

// ---------- Shot 6 · Feature-Blitze (39–47 s) ----------
const KATEGORIEN = [
  "musik.svg",
  "sport.svg",
  "gaming.svg",
  "geographie.svg",
  "essen_trinken.svg",
  "filme_serien.svg",
  "wissenschaft.svg",
  "tiere_natur.svg",
  "internet_memes.svg",
  "geschichte.svg",
  "technik_autos.svg",
  "kurioses_mixed.svg",
];

const JOKER = [
  "j1-bananen-split.svg",
  "j2-ueberziehungskredit.svg",
  "j3-goldene-banane.svg",
  "j4-schmiergeld.svg",
  "j5-rueckgaberecht.svg",
  "j6-bananentresor.svg",
  "j7-portfolio-umschichtung.svg",
];

const BlitzScreen: React.FC<{
  src: string;
  stamp: string;
  stampBg: string;
  stampColor?: string;
}> = ({ src, stamp, stampBg, stampColor }) => (
  <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
    <SlideIn delay={0} from="bottom" dist={200}>
      <DeviceFrame src={src} width={1010} height={631} />
    </SlideIn>
    <div style={{ position: "absolute", top: 90, width: "100%", textAlign: "center" }}>
      <FormatStamp
        text={stamp}
        bg={stampBg}
        color={stampColor}
        delay={4}
        rotate={-3}
        size={78}
        style={{ display: "inline-block" }}
      />
    </div>
  </AbsoluteFill>
);

const BlitzIcons: React.FC<{
  stamp: string;
  stampBg: string;
  icons: string[];
  folder: string;
  iconSize?: number;
}> = ({ stamp, stampBg, icons, folder, iconSize = 130 }) => (
  <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", gap: 48 }}>
    <FormatStamp text={stamp} bg={stampBg} delay={2} rotate={-3} size={84} />
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        justifyContent: "center",
        gap: 30,
        width: 1300,
      }}
    >
      {icons.map((f, i) => (
        <StampIn key={f} delay={6 + i * 2} rotate={i % 2 === 0 ? -3 : 3}>
          <div
            style={{
              background: PALETTE.ticketPaper,
              border: `5px solid ${PALETTE.outline}`,
              borderRadius: 22,
              boxShadow: "6px 7px 0 rgba(26,18,8,0.4)",
              padding: 16,
            }}
          >
            <Img src={M(`${folder}/${f}`)} style={{ width: iconSize, display: "block" }} />
          </div>
        </StampIn>
      ))}
    </div>
  </AbsoluteFill>
);

export const ShotFeatures: React.FC = () => (
  <AbsoluteFill>
    <StageBackground dim={0.2} />
    <Sequence durationInFrames={60}>
      <BlitzScreen
        src={M("screens/mm_tour_10_gluecksrad_dreh.png")}
        stamp="GLÜCKSRAD! 🎡"
        stampBg={PALETTE.spotlightPink}
        stampColor={PALETTE.ticketPaper}
      />
    </Sequence>
    <Sequence from={60} durationInFrames={60}>
      <BlitzScreen
        src={M("screens/mm_test2_gm_cockpit_regal_werkzeuge.png")}
        stamp="GM-COCKPIT! 🎛️"
        stampBg={PALETTE.studioLed}
      />
    </Sequence>
    <Sequence from={120} durationInFrames={60}>
      <BlitzIcons
        stamp="90 KATEGORIEN!"
        stampBg={PALETTE.banana}
        icons={KATEGORIEN}
        folder="kategorien"
      />
    </Sequence>
    <Sequence from={180} durationInFrames={60}>
      <BlitzIcons
        stamp="JOKER! 🃏"
        stampBg={PALETTE.bananaLeaf}
        icons={JOKER}
        folder="joker"
        iconSize={150}
      />
    </Sequence>
    <WhiteFlash at={60} />
    <WhiteFlash at={120} />
    <WhiteFlash at={180} />
  </AbsoluteFill>
);

// ---------- Shot 7 · Emotion-Peak: Siegerehrung + Money-Regen (47–55 s) ----------
export const ShotEmotion: React.FC = () => {
  const frame = useCurrentFrame();
  const zoom = interpolate(frame, [0, 240], [1, 1.08]);
  return (
    <AbsoluteFill>
      <StageBackground dim={0.25} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
        <div style={{ transform: `scale(${zoom})` }}>
          <DeviceFrame src={M("screens/mm_tour_12_siegerehrung.png")} width={1240} height={775} />
        </div>
      </AbsoluteFill>
      <MoneyRain count={64} />
      <div
        style={{
          position: "absolute",
          bottom: 66,
          width: "100%",
          display: "flex",
          justifyContent: "center",
        }}
      >
        <FormatStamp
          text="AM ENDE REGNET'S MONEY."
          bg={PALETTE.vaultGold}
          delay={36}
          rotate={-2}
          size={64}
        />
      </div>
    </AbsoluteFill>
  );
};

// ---------- Shot 8 · Feature-Karten + Social Proof (55–61 s) ----------
export const ShotCards: React.FC = () => {
  const cards: Array<[string, string, string]> = [
    ["👥", "2–8 SPIELER", "Ein Screen, alle Handys"],
    ["🎉", "PARTY · FAMILIE · BÜRO", "Späti-Modus inklusive"],
    ["🧠", "90 KATEGORIEN", "Jede Woche neue Fragen"],
  ];
  return (
    <AbsoluteFill>
      <StageBackground dim={0.15} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", gap: 60 }}>
        <div style={{ display: "flex", gap: 46 }}>
          {cards.map(([emoji, title, sub], i) => (
            <StampIn key={title} delay={4 + i * 14} rotate={i % 2 === 0 ? -3 : 3}>
              <StickerCard style={{ width: 430, textAlign: "center", padding: "36px 24px" }}>
                <div style={{ fontSize: 84 }}>{emoji}</div>
                <div
                  style={{
                    fontFamily: FONT_DISPLAY,
                    fontSize: 42,
                    color: PALETTE.outline,
                    marginTop: 14,
                  }}
                >
                  {title}
                </div>
                <div
                  style={{
                    fontFamily: FONT_TEXT,
                    fontWeight: 600,
                    fontSize: 30,
                    color: "#4a3f2c",
                    marginTop: 8,
                  }}
                >
                  {sub}
                </div>
              </StickerCard>
            </StampIn>
          ))}
        </div>
        <StampIn delay={64} rotate={-1}>
          <StickerCard bg={PALETTE.banana} style={{ maxWidth: 1150, textAlign: "center" }}>
            <div
              style={{
                fontFamily: FONT_TEXT,
                fontStyle: "italic",
                fontWeight: 700,
                fontSize: 44,
                color: PALETTE.outline,
              }}
            >
              „Der Affe hat meine Punkte GEKLAUT?!“
            </div>
            <div
              style={{
                fontFamily: FONT_TEXT,
                fontSize: 30,
                color: "#4a3f2c",
                marginTop: 10,
              }}
            >
              — Lena, Platz 4
            </div>
          </StickerCard>
        </StampIn>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ---------- Shot 9 · Call-to-Action + Credits (61–72 s) ----------
// TODO(Trailer-QR): Echten QR-Code parametrisieren, sobald die Launch-URL
// feststeht. Parametrisierungs-Stelle: die <FakeQr>-Layer unten ersetzen —
// z. B. per `npx qrcode -o remotion/public/material/img/qr_launch.png <URL>`
// rendern und hier als <Img src={M("img/qr_launch.png")} style={{ width: 250 }} />
// einhängen; danach den Text „QR-Platzhalter — Link folgt zum Launch" auf die
// echte URL ändern und NUR Shot 9 neu rendern (Chunk 4 der Render-Pipeline).
export const ShotCta: React.FC = () => {
  const frame = useCurrentFrame();
  const fade = interpolate(frame, [285, 330], [0, 1], CLAMP);
  return (
    <AbsoluteFill>
      <StageBackground />
      <MoneyRain count={22} opacity={0.5} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", gap: 8 }}>
        <StampIn delay={6}>
          <Img src={M("img/monkey-money-logo.png")} style={{ width: 560 }} />
        </StampIn>
        <StampIn delay={32} rotate={-1}>
          <BigTitle size={76}>Bring die Bande zusammen.</BigTitle>
        </StampIn>
        <div style={{ display: "flex", alignItems: "center", gap: 54, marginTop: 44 }}>
          <StampIn delay={56} rotate={-3}>
            <FakeQr size={250} />
          </StampIn>
          <StampIn delay={68}>
            <div style={{ textAlign: "left" }}>
              <div
                style={{
                  fontFamily: FONT_DISPLAY,
                  fontSize: 44,
                  color: PALETTE.ticketPaper,
                  textShadow: "4px 5px 0 rgba(26,18,8,0.85)",
                }}
              >
                Scannen &amp; losbuzzern
              </div>
              <div
                style={{
                  fontFamily: FONT_TEXT,
                  fontWeight: 600,
                  fontSize: 30,
                  color: "rgba(255,246,227,0.85)",
                  marginTop: 10,
                }}
              >
                QR-Platzhalter — Link folgt zum Launch
              </div>
            </div>
          </StampIn>
        </div>
      </AbsoluteFill>
      <SmallPrint style={{ position: "absolute", bottom: 34, width: "100%", fontSize: 24 }}>
        Musik: „Monkeys Spinning Monkeys“ — Kevin MacLeod (incompetech.com) · Licensed under CC BY
        4.0
        <br />
        Echte Gameplay-Screens · Fonts: Bungee &amp; Rubik (SIL OFL 1.1)
      </SmallPrint>
      <AbsoluteFill style={{ background: "#000", opacity: fade, pointerEvents: "none" }} />
    </AbsoluteFill>
  );
};
