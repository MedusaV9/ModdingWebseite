// Tutorial-Rollout (Plan §5.2): HowToCard-Props für ALLE Formate, die noch
// kein Tutorial-MP4 haben — abgeleitet aus den explainCard-Texten der
// Client-Plugins (client/shared/minigames/*/index.ts). Die Gameplay-Screens
// liefert tools/screenshots/tutorial-shots.mjs (Marathon-Walk), sync-assets.sh
// kopiert sie nach public/material/screens/. Render:
// bash scripts/render-tutorials.sh (1 Prozess pro Video — Chunk-Prinzip).
import type { HowToProps } from "./HowToCard";
import { PALETTE } from "./tokens";

export interface TutorialEintrag {
  /** Minigame-Id (= Datei tutorial_<id>.mp4 + TUTORIAL_VIDEOS-Key). */
  id: string;
  /** Remotion-Kompositions-Id (Tutorial + PascalCase). */
  kompId: string;
  props: HowToProps;
}

const shot = (id: string): string => `screens/mm_play_${id}.png`;

export const TUTORIALS: TutorialEintrag[] = [
  {
    id: "bananen-basics",
    kompId: "TutorialBananenBasics",
    props: {
      spielName: "Bananen-Basics",
      untertitel: "Lockeres Aufwärmen — alle spielen jede Frage",
      icon: "🍌",
      accentColor: PALETTE.studioLed,
      regeln: [
        "Alle beantworten dieselbe Frage — vier Antworten auf dem Handy",
        "Richtig = Grundwert + Speed-Bonus für schnelle Affen",
        "Jede richtige Antwort verlängert deine Streak-Kette!",
      ],
      rewardLine: "BAUT EURE STREAK AUF! 🔥",
      screenshot: shot("bananen-basics"),
      screenshotKind: "screen",
    },
  },
  {
    id: "kokosnuss-uhr",
    kompId: "TutorialKokosnussUhr",
    props: {
      spielName: "Stopp die Kokosnuss-Uhr",
      untertitel: "Der schrumpfende Geldsack tickt",
      icon: "🥥",
      accentColor: PALETTE.banana,
      regeln: [
        "Der Geldsack über der Frage schrumpft alle paar Sekunden um 50 MM",
        "Deine Antwort friert DEINEN Sack ein — früh lohnt sich",
        "Richtig = eingefrorener Betrag, falsch = 0",
      ],
      rewardLine: "FRÜH ANTWORTEN = MEHR MONEY! ❄️",
      screenshot: shot("kokosnuss-uhr"),
      screenshotKind: "screen",
    },
  },
  {
    id: "bananen-tresor",
    kompId: "TutorialBananenTresor",
    props: {
      spielName: "Der Bananen-Tresor",
      untertitel: "Die Schätzfrage mit dem Zahlenstrahl",
      icon: "🔐",
      accentColor: PALETTE.vaultGold,
      regeln: [
        "Schätzfrage! Zieh den Slider auf deinen Tipp",
        "Wer am nächsten dran ist, kassiert — schätzen lohnt IMMER",
        "Exakter Volltreffer sprengt den Tresor!",
      ],
      rewardLine: "VOLLTREFFER SPRENGT DEN TRESOR! 💥",
      screenshot: shot("bananen-tresor"),
      screenshotKind: "screen",
    },
  },
  {
    id: "affenleiter",
    kompId: "TutorialAffenleiter",
    props: {
      spielName: "Affenleiter",
      untertitel: "Sortieren gegen die Uhr",
      icon: "🪜",
      accentColor: PALETTE.bananaLeaf,
      regeln: [
        "Bring die 4 Dinge in die richtige Reihenfolge",
        "Ziehen oder antippen zum Tauschen",
        "Jede richtige Sprosse zahlt — die perfekte Leiter gibt fetten Bonus!",
      ],
      rewardLine: "PERFEKTE LEITER = FETTER BONUS! 🥇",
      screenshot: shot("affenleiter"),
      screenshotKind: "screen",
    },
  },
  {
    id: "pixel-dschungel",
    kompId: "TutorialPixelDschungel",
    props: {
      spielName: "Pixel-Dschungel",
      untertitel: "Das Bild wird scharf — der Jackpot schrumpft",
      icon: "🖼️",
      accentColor: PALETTE.leaf,
      regeln: [
        "Ein Bild wird in 8 Stufen scharf — der Jackpot schrumpft mit!",
        "Früh antworten bringt mehr Money",
        "Falsch = 0 und gesperrt — Mut mit Köpfchen!",
      ],
      rewardLine: "FRÜH TIPPEN LOHNT! 👀",
      screenshot: shot("pixel-dschungel"),
      screenshotKind: "screen",
    },
  },
  {
    id: "taschendieb",
    kompId: "TutorialTaschendieb",
    props: {
      spielName: "Der Taschendieb-Affe",
      untertitel: "Die schnellste Antwort darf klauen",
      icon: "🦹",
      accentColor: PALETTE.curtain,
      regeln: [
        "Alle kriegen dieselbe Frage — die schnellste richtige Antwort gewinnt",
        "Der Sieger klaut beim Wunsch-Opfer: 300/500 MM (max. 25 %)",
        "Mitmachen lohnt: alle anderen Richtigen kriegen den halben Grundwert",
      ],
      rewardLine: "KLAU DIR DEINE BEUTE! 🤚",
      screenshot: shot("taschendieb"),
      screenshotKind: "screen",
    },
  },
  {
    id: "affenbank",
    kompId: "TutorialAffenbank",
    props: {
      spielName: "Die Affenbank",
      untertitel: "Schnellfeuer + der BANK!-Moment",
      icon: "🏦",
      accentColor: PALETTE.vaultGold,
      regeln: [
        "Schnellfeuer-Fragen im 10-Sekunden-Takt",
        "Antwortet die MEHRHEIT richtig, wächst der Pott: 50 → 1.600",
        "Wer BANK! drückt, sichert sich alles — die Kette reißt für alle!",
      ],
      rewardLine: "BANK! IM RICHTIGEN MOMENT 🔗",
      screenshot: shot("affenbank"),
      screenshotKind: "screen",
    },
  },
  {
    id: "alles-oder-banane",
    kompId: "TutorialAllesOderBanane",
    props: {
      spielName: "Alles oder Banane",
      untertitel: "Blind setzen, dann antworten",
      icon: "🥁",
      accentColor: PALETTE.spotlightPink,
      regeln: [
        "Erst wird NUR Kategorie + Schwierigkeit verraten",
        "Dann setzt jeder GEHEIM auf die eigene Antwort",
        "Richtig = Einsatz verdoppelt, falsch = Einsatz weg!",
      ],
      rewardLine: "MUT ZAHLT DOPPELT! 🎲",
      screenshot: shot("alles-oder-banane"),
      screenshotKind: "screen",
    },
  },
  {
    id: "lianen-finale",
    kompId: "TutorialLianenFinale",
    props: {
      spielName: "Das große Lianen-Finale",
      untertitel: "Das Finale über dem Krokodil-Fluss",
      icon: "🐊",
      accentColor: PALETTE.curtain,
      regeln: [
        "Jeder hängt an seiner Liane über dem Krokodil-Fluss",
        "Richtig = W_final rauf, falsch = die Hälfte runter",
        "Niemand scheidet aus — aber das Krokodil schnappt!",
      ],
      rewardLine: "JEDE FRAGE ZÄHLT W_FINAL! 🏆",
      screenshot: shot("lianen-finale"),
      screenshotKind: "screen",
    },
  },
  {
    id: "monkey-market",
    kompId: "TutorialMonkeyMarket",
    props: {
      spielName: "Monkey Market",
      untertitel: "10 Chips auf 4 Falltüren",
      icon: "💱",
      accentColor: PALETTE.billGreen,
      regeln: [
        "Die Bank gibt dir 10 Markt-Chips — verteil sie auf die 4 Falltüren",
        "Chips auf der richtigen Tür zahlen ×2, der Rest verfällt",
        "Alle 10 auf eine Tür und richtig? MUT-BONUS +25 %!",
      ],
      rewardLine: "STREUEN ODER ALL-IN? 🚪",
      screenshot: shot("monkey-market"),
      screenshotKind: "screen",
    },
  },
  {
    id: "bananen-bluff",
    kompId: "TutorialBananenBluff",
    props: {
      spielName: "Bananen-Bluff",
      untertitel: "Wahrheit oder frecher Bluff?",
      icon: "🤥",
      accentColor: PALETTE.spotlightPink,
      regeln: [
        "Einer wird zum VERKÜNDER: nur er kennt die richtige Antwort",
        "Er verkündet Wahrheit oder Bluff — alle urteilen: WAHR oder GELOGEN?",
        "Wer dem Bluff glaubt, zahlt an den Lügner",
      ],
      rewardLine: "POKERFACE AUFSETZEN! 🎙️",
      screenshot: shot("bananen-bluff"),
      screenshotKind: "screen",
    },
  },
  {
    id: "bananen-boerse",
    kompId: "TutorialBananenBoerse",
    props: {
      spielName: "Bananen-Börse",
      untertitel: "Der Antwort-Kurs lebt",
      icon: "📈",
      accentColor: PALETTE.leaf,
      regeln: [
        "Frage + Optionen liegen offen — gehandelt wird an der Börse!",
        "KAUFEN friert deine Quote ein — die Herde drückt den Kurs",
        "Kalte Füße? VERKAUFEN kostet Spread",
      ],
      rewardLine: "GEGEN DIE HERDE GEWINNT! 💹",
      screenshot: shot("bananen-boerse"),
      screenshotKind: "screen",
    },
  },
  {
    id: "affen-auktion",
    kompId: "TutorialAffenAuktion",
    props: {
      spielName: "Affen-Auktion",
      untertitel: "Die Frage unterm Hammer",
      icon: "🔨",
      accentColor: PALETTE.vaultGold,
      regeln: [
        "Geboten wird BLIND — nur Kategorie + Schwierigkeit sind bekannt",
        "Der Höchstbietende antwortet exklusiv",
        "Richtig = Gebot ×2 zurück, falsch = Gebot an alle anderen!",
      ],
      rewardLine: "WER BIETET MEHR? 💰",
      screenshot: shot("affen-auktion"),
      screenshotKind: "screen",
    },
  },
  {
    id: "lianensteg-duell",
    kompId: "TutorialLianenstegDuell",
    props: {
      spielName: "Duell am Lianensteg",
      untertitel: "1 gegen 1 auf dem Hängesteg",
      icon: "⚔️",
      accentColor: PALETTE.studioLed,
      regeln: [
        "Der Letzte fordert heraus: Best-of-5 Speed-Fragen",
        "Wer schneller RICHTIG antwortet, schubst!",
        "Alle anderen wetten 50 MM — Sieger: 300 MM + 100 MM vom Verlierer",
      ],
      rewardLine: "SCHUBS IHN VOM STEG! 🌉",
      screenshot: shot("lianensteg-duell"),
      screenshotKind: "screen",
    },
  },
  {
    id: "goldener-affe",
    kompId: "TutorialGoldenerAffe",
    props: {
      spielName: "Der Goldene Affe",
      untertitel: "Das 3-Stufen-Finale im goldenen Tempel",
      icon: "👑",
      accentColor: PALETTE.vaultGold,
      regeln: [
        "Stufe 1: Money-Drop — 10 Chips auf 4 Türen, Einsatz = 50 % vom Konto!",
        "Stufe 2: Schätz-Showdown — die 2 Nächsten werden Finalisten",
        "Stufe 3: Buzzer-Best-of-3 — der Sieger nimmt 20 % der Konten ALLER!",
      ],
      rewardLine: "HOL DIR DEN GOLDENEN AFFEN! 🐵✨",
      screenshot: shot("goldener-affe"),
      screenshotKind: "screen",
    },
  },
  {
    id: "buchstaben-telegramm",
    kompId: "TutorialBuchstabenTelegramm",
    props: {
      spielName: "Das 7-Buchstaben-Telegramm",
      untertitel: "Das Paar-Spiel am Morse-Streifen",
      icon: "📮",
      accentColor: PALETTE.studioLed,
      regeln: [
        "Der Beschreiber tippt NUR Buchstaben — max. 8 pro Telegramm",
        "Das Match-Konto hat nur 60 Zeichen — der Rest verfällt!",
        "Der Partner rät aus 4 Optionen — Erfolg zahlt BEIDEN je 250 MM",
      ],
      rewardLine: "ZUGESTELLT = DOPPELT KASSE! 💌",
      screenshot: shot("buchstaben-telegramm"),
      screenshotKind: "screen",
    },
  },
  {
    id: "musikvideo-raten",
    kompId: "TutorialMusikvideoRaten",
    props: {
      spielName: "Stummfilm-Studio",
      untertitel: "Musikvideo ohne Ton — erkennst du den Song?",
      icon: "🎬",
      accentColor: PALETTE.spotlightPink,
      regeln: [
        "Auf dem Screen läuft ein Musikvideo — 3 Sekunden, STUMM!",
        "Wer den Song früh erkennt, kassiert den vollen Wert",
        "Wer wartet, bekommt einen Ton-Schnipsel — für die halbe Gage",
      ],
      rewardLine: "AUGEN STATT OHREN! 🔇",
      screenshot: shot("musikvideo-raten"),
      screenshotKind: "screen",
    },
  },
  {
    id: "song-rueckwaerts",
    kompId: "TutorialSongRueckwaerts",
    props: {
      spielName: "Rückwärts-Banane",
      untertitel: "Der Song läuft verkehrt herum",
      icon: "⏪",
      accentColor: PALETTE.bananaLeaf,
      regeln: [
        "Ein Song läuft RÜCKWÄRTS — alle raten gleichzeitig aus 4 Optionen",
        "Schnell sein bringt Speed-Bonus",
        "Die Auflösung spielt das Intro vorwärts: der Aha-Moment!",
      ],
      rewardLine: "ERKENN DEN RÜCKWÄRTS-BREI! ▶️",
      screenshot: shot("song-rueckwaerts"),
      screenshotKind: "screen",
    },
  },
  {
    id: "song-snippet",
    kompId: "TutorialSongSnippet",
    props: {
      spielName: "Der Blitz-DJ",
      untertitel: "0,1 Sekunden Song — wer buzzert?",
      icon: "⚡",
      accentColor: PALETTE.curtain,
      regeln: [
        "0,1 Sekunden Song — wer buzzert, rät allein aus 4 Optionen!",
        "Keiner dran oder falsch? Längeres Snippet, weniger Money",
        "Falsch-Buzz = Sperre + Strafe ins Glas",
      ],
      rewardLine: "BLITZOHREN GEWINNEN! 🎧",
      screenshot: shot("song-snippet"),
      screenshotKind: "screen",
    },
  },
];
