// Zustandsmaschine des VOLLEN Spiels (GAME-DESIGN §1): lobby → intro →
// [kategorie-wahl → erklaerkarte → (frage → aufloesung)×N → zwischenstand → rad?]
// → … → siegerehrung → ende. Alles pure dank Clock/Rng-Injektion — die
// Test-Clock spult die Show vor, der Seed macht Rad & Los reproduzierbar.
import { beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { MITLEIDS_BANANE, wFinal } from "../../shared/economy";
import { FRAGE_TIMER_MS } from "../../shared/money";
import { createRng } from "../../shared/rng";
import { AB_KETTE_MS, AB_QUICK_KETTE_MS } from "../../shared/minigames/affenbank.meta";
import { defaultSettings, type MatchSettings } from "../../shared/settings";
import { createTestClock } from "../../shared/time";
import { RAD_ERGEBNIS_MS } from "../../shared/wheel";
import { affenbankPlugin } from "../minigames/affenbank/index";
import { vierLianenPlugin, type VierLianenState } from "../minigames/vier-lianen/index";
import { createInitialState, reduce, tick, type EngineDeps } from "./engine";
import { starteFrage } from "./flow";
import { viewFor, type RoomInfo } from "./views";
import {
  AUFLOESUNG_MS,
  ERKLAERKARTE_KURZ_MS,
  INTRO_MS,
  KATEGORIE_WAHL_MS,
  SIEGEREHRUNG_MS,
  VOTING_ERGEBNIS_MS,
  ZWISCHENSTAND_MS,
  type EngineAction,
  type EngineEvent,
  type EngineState,
} from "./types";

// ---------- Test-Bausteine ----------

const frage = (id: string, patch: Partial<Question> = {}): Question => ({
  id,
  kind: "choice4",
  category: "affen",
  difficulty: "easy",
  text: `Frage ${id}?`,
  options: ["A", "B", "C", "D"],
  answer: 1,
  erklaerung: "Weil B.",
  ...patch,
});

/** Ein-Kategorien-Pool, nur easy (Kategorien-Wahl wird übersprungen). */
const einfacherPool = (): Question[] => Array.from({ length: 30 }, (_, i) => frage(`q${i + 1}`));

/** Eine Kategorie, easy + medium (für Schwierigkeits-Progression/Gold-Banane). */
const gemischterPool = (): Question[] => [
  ...Array.from({ length: 15 }, (_, i) => frage(`qe${i + 1}`)),
  ...Array.from({ length: 15 }, (_, i) => frage(`qm${i + 1}`, { difficulty: "medium" })),
];

/** Mehr-Kategorien-Pool: easy „affen" + medium „tiere"/„essen" (Voting-Fall). */
const bunterPool = (): Question[] => [
  ...Array.from({ length: 8 }, (_, i) => frage(`qa${i + 1}`)),
  ...Array.from({ length: 8 }, (_, i) =>
    frage(`qt${i + 1}`, { category: "tiere", difficulty: "medium" }),
  ),
  ...Array.from({ length: 8 }, (_, i) =>
    frage(`qe${i + 1}`, { category: "essen", difficulty: "medium" }),
  ),
];

let clock: ReturnType<typeof createTestClock>;
let ctx: { clock: typeof clock; rng: ReturnType<typeof createRng> };
const deps: EngineDeps = { getPlugin: () => vierLianenPlugin };

beforeEach(() => {
  clock = createTestClock(1_000_000);
  ctx = { clock, rng: createRng(42) };
});

function mitSpielern(anzahl = 2, settings?: Partial<MatchSettings>): EngineState {
  let s = createInitialState({ ...defaultSettings("quick"), autoGm: false, ...settings });
  const namen = ["Anna", "Ben", "Cleo", "Dario"];
  const farben = ["gelb", "rot", "blau", "gruen"] as const;
  for (let i = 0; i < anzahl; i++) {
    s = reduce(
      s,
      { type: "join", playerId: `p${i + 1}`, name: namen[i], avatar: farben[i] },
      deps,
      ctx,
    ).state;
  }
  return s;
}

function gestartet(
  opts: {
    spieler?: number;
    settings?: Partial<MatchSettings>;
    pool?: Question[];
    verfuegbar?: string[];
  } = {},
): EngineState {
  let s = mitSpielern(opts.spieler ?? 2, opts.settings);
  s = reduce(
    s,
    {
      type: "start",
      matchId: "m_test",
      fragenPool: opts.pool ?? einfacherPool(),
      verfuegbareMinigames: opts.verfuegbar ?? ["vier-lianen"],
    },
    deps,
    ctx,
  ).state;
  return s;
}

/** intro → erklaerkarte → frage (Runde 1 hat KEINE Kategorien-Wahl). */
function bisErsteFrage(s: EngineState): EngineState {
  clock.advance(INTRO_MS + 1);
  s = tick(s, deps, ctx).state; // intro → erklaerkarte
  clock.advance(ERKLAERKARTE_KURZ_MS + 1);
  return tick(s, deps, ctx).state; // erklaerkarte → frage
}

function antwort(s: EngineState, playerId: string, choice: number): EngineState {
  return reduce(
    s,
    {
      type: "playerAction",
      playerId,
      minigameId: s.minigameId ?? "vier-lianen",
      action: { type: "answer", choice },
      atServerTime: clock.now(),
    },
    deps,
    ctx,
  ).state;
}

/** Frage beantworten (nach 1 s ⇒ voller Speed-Bonus) und in die Auflösung ticken. */
function beantworte(s: EngineState, choices: Record<string, number>): EngineState {
  clock.advance(1_000);
  for (const [pid, choice] of Object.entries(choices)) s = antwort(s, pid, choice);
  return tick(s, deps, ctx).state; // alle geantwortet ⇒ aufloesung
}

/** Zeit vorspulen + tick (für Server-getaktete Phasen). */
function weiter(s: EngineState, ms: number): EngineState {
  clock.advance(ms + 1);
  return tick(s, deps, ctx).state;
}

// ---------- Lobby + Start ----------

describe("engine: Lobby + Start", () => {
  it("verweigert den Start mit weniger als 2 Spielern", () => {
    let s = createInitialState(defaultSettings("quick"));
    s = reduce(s, { type: "join", playerId: "p1", name: "Solo", avatar: "gelb" }, deps, ctx).state;
    const result = reduce(
      s,
      {
        type: "start",
        matchId: "m",
        fragenPool: einfacherPool(),
        verfuegbareMinigames: ["vier-lianen"],
      },
      deps,
      ctx,
    );
    expect(result.error).toBe("zu-wenige-spieler");
  });

  it("verweigert Join Nr. 9 (2-8-Grenzen) und Join nach Match-Start", () => {
    let s = createInitialState(defaultSettings("quick"));
    for (let i = 1; i <= 8; i++) {
      s = reduce(
        s,
        { type: "join", playerId: `p${i}`, name: `S${i}`, avatar: "gelb" },
        deps,
        ctx,
      ).state;
    }
    expect(
      reduce(s, { type: "join", playerId: "p9", name: "S9", avatar: "rot" }, deps, ctx).error,
    ).toBe("raum-voll");
    const laufend = gestartet();
    expect(
      reduce(laufend, { type: "join", playerId: "px", name: "Spät", avatar: "blau" }, deps, ctx)
        .error,
    ).toBe("match-laeuft");
  });

  it("baut beim Start den Quick-Plan: 4 Runden + Finale, kein Jackpot", () => {
    const s = gestartet();
    expect(s.phase).toBe("intro");
    expect(s.plan?.rundenTotal).toBe(4);
    expect(s.plan?.abschnitte).toHaveLength(5);
    expect(s.plan?.abschnitte[4].typ).toBe("finale");
    expect(s.plan?.abschnitte.some((a) => a.typ === "jackpot")).toBe(false);
    expect(s.plan?.fragenTotal).toBe(15); // 4×3 + 3 Finale
    expect(s.jackpotGlas).toBe(500); // Grundfüllung
  });

  it("Klassik-Plan hat den Jackpot-Beat direkt vor der RISIKO-Runde", () => {
    const s = gestartet({ settings: { ...defaultSettings("klassik"), autoGm: false } });
    const typen = s.plan?.abschnitte.map((a) => a.typ) ?? [];
    const jackpotIdx = typen.indexOf("jackpot");
    expect(jackpotIdx).toBeGreaterThan(0);
    expect(s.plan?.abschnitte[jackpotIdx + 1].slot).toBe("risiko");
  });

  it("teilt beim Start Gratis-Joker aus (nur wenn Joker AN)", () => {
    const mit = gestartet({ settings: { jokerAn: true } });
    expect(mit.players.p1.jokers["bananen-split"]).toBe(1);
    expect(mit.players.p1.jokers["goldene-banane"]).toBe(1);
    expect(mit.players.p1.jokers["portfolio-umschichtung"]).toBe(1);
    const ohne = gestartet(); // Quick-Default: Joker AUS
    expect(ohne.players.p1.jokers).toEqual({});
  });
});

// ---------- Phasen-Fluss ----------

describe("engine: Phasen-Fluss", () => {
  it("läuft lobby → intro → erklaerkarte → frage (Runde 1 ohne Kategorien-Wahl)", () => {
    let s = gestartet();
    expect(s.phase).toBe("intro");
    s = weiter(s, INTRO_MS);
    expect(s.phase).toBe("erklaerkarte");
    expect(s.abschnittIndex).toBe(0);
    s = weiter(s, ERKLAERKARTE_KURZ_MS);
    expect(s.phase).toBe("frage");
    expect(s.minigameId).toBe("vier-lianen");
    expect(s.aktuelleFragen).toHaveLength(1);
  });

  it("Erklärkarte: alle bereit ⇒ Frage startet sofort", () => {
    let s = gestartet();
    s = weiter(s, INTRO_MS);
    s = reduce(s, { type: "playerReady", playerId: "p1" }, deps, ctx).state;
    expect(s.phase).toBe("erklaerkarte");
    s = reduce(s, { type: "playerReady", playerId: "p2" }, deps, ctx).state;
    expect(s.phase).toBe("frage");
  });

  it("Streik-Mehrheit tauscht das Minispiel aufs Frage-Format", () => {
    // Runde 2 (Quick) wünscht kokosnuss-uhr — beide streiken auf der Erklärkarte.
    let s = gestartet({ verfuegbar: ["vier-lianen", "kokosnuss-uhr"] });
    s = bisErsteFrage(s);
    for (let i = 0; i < 3; i++) {
      s = beantworte(s, { p1: 1, p2: 1 });
      s = weiter(s, AUFLOESUNG_MS);
    }
    expect(s.phase).toBe("zwischenstand");
    s = weiter(s, ZWISCHENSTAND_MS); // → Runde 2 (Ein-Kategorien-Pool: Wahl übersprungen)
    expect(s.phase).toBe("erklaerkarte");
    expect(s.plan?.abschnitte[1].minigameId).toBe("kokosnuss-uhr");
    s = reduce(s, { type: "playerStreik", playerId: "p1" }, deps, ctx).state;
    expect(s.plan?.abschnitte[1].minigameId).toBe("kokosnuss-uhr"); // 1 von 2 reicht nicht
    s = reduce(s, { type: "playerStreik", playerId: "p2" }, deps, ctx).state;
    expect(s.plan?.abschnitte[1].minigameId).toBe("vier-lianen"); // Mehrheit ⇒ Tausch
  });

  it("Kategorien-Voting: Mehrheit gewinnt, Frage kommt aus der Sieger-Kategorie", () => {
    let s = gestartet({ pool: bunterPool() });
    s = bisErsteFrage(s);
    for (let i = 0; i < 3; i++) {
      s = beantworte(s, { p1: 1, p2: 1 });
      s = weiter(s, AUFLOESUNG_MS);
    }
    s = weiter(s, ZWISCHENSTAND_MS); // → Runde 2: Kategorien-Wahl (tiere vs. essen)
    expect(s.phase).toBe("kategorie-wahl");
    expect(s.kategorieWahl?.optionen.length).toBeGreaterThanOrEqual(2);
    s = reduce(s, { type: "kategorieVote", playerId: "p1", kategorie: "tiere" }, deps, ctx).state;
    s = reduce(s, { type: "kategorieVote", playerId: "p2", kategorie: "tiere" }, deps, ctx).state;
    // Alle haben gewählt ⇒ Wahl schließt sofort, Erklärkarte startet.
    expect(s.phase).toBe("erklaerkarte");
    expect(s.plan?.abschnitte[1].kategorie).toBe("tiere");
    s = weiter(s, ERKLAERKARTE_KURZ_MS);
    expect(s.aktuelleFragen[0].category).toBe("tiere");
  });

  it("Kategorien-Wahl-Timeout ohne Stimmen ⇒ Auto-Pick", () => {
    let s = gestartet({ pool: bunterPool() });
    s = bisErsteFrage(s);
    for (let i = 0; i < 3; i++) {
      s = beantworte(s, { p1: 1, p2: 1 });
      s = weiter(s, AUFLOESUNG_MS);
    }
    s = weiter(s, ZWISCHENSTAND_MS);
    expect(s.phase).toBe("kategorie-wahl");
    s = weiter(s, KATEGORIE_WAHL_MS);
    expect(s.phase).toBe("erklaerkarte");
    expect(s.plan?.abschnitte[1].kategorie).not.toBeNull();
  });

  it("löst nach Timer-Ablauf auf (Timeout ohne Antwort)", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = weiter(s, FRAGE_TIMER_MS.easy); // easy-Timer
    expect(s.phase).toBe("aufloesung");
    expect(s.players.p1.balance).toBe(0);
  });
});

// ---------- Ökonomie in der Engine ----------

describe("engine: Buchungs-Pipeline", () => {
  it("bucht Grundwert + Speed-Bonus, zählt Streak, zahlt Applaus-Almosen", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = beantworte(s, { p1: 1, p2: 3 }); // p1 richtig, p2 als Einziger falsch
    expect(s.phase).toBe("aufloesung");
    expect(s.players.p1.balance).toBe(150); // 100 + voller Speed-Bonus 50
    expect(s.players.p1.streak).toBe(1);
    expect(s.players.p2.balance).toBe(25); // Applaus-Almosen (§3.4)
    expect(s.players.p2.streak).toBe(0);
  });

  it("Streak 3 ⇒ ×1,5 auf die dritte richtige Antwort", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = beantworte(s, { p1: 1, p2: 0 }); // Q1: p1 +150
    s = weiter(s, AUFLOESUNG_MS);
    s = beantworte(s, { p1: 1, p2: 0 }); // Q2: p1 +150 (Streak 2, ×1)
    s = weiter(s, AUFLOESUNG_MS);
    s = beantworte(s, { p1: 1, p2: 0 }); // Q3: p1 +150×1,5 = 225 → 230 (10er)
    expect(s.players.p1.streak).toBe(3);
    expect(s.players.p1.maxStreak).toBe(3);
    expect(s.players.p1.balance).toBe(150 + 150 + 230);
  });

  it("Rückenwind ×1,5 für den Underdog — Extra bleibt unter der Überhol-Kappe", () => {
    let s = gestartet();
    s = reduce(
      s,
      { type: "gm.scoreAdjust", playerId: "p1", delta: 1000, grund: "test", override: true },
      deps,
      ctx,
    ).state;
    s = bisErsteFrage(s);
    s = beantworte(s, { p1: 1, p2: 1 }); // beide richtig
    // p2: 0 MM = 100 % Rückstand ⇒ ×1,5. Basis 150 + Extra rund(150×0,5)=80 → 230.
    expect(s.players.p2.balance).toBe(230);
    expect(s.players.p1.balance).toBe(1000 + 150);
    expect(s.players.p2.rueckenwindAngekuendigt).toBe(true);
  });

  it("Tipp-Kanone Stufe 1 kostet sichtbar 25 % vom Gewinn", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = reduce(s, { type: "gm.hintGlobal" }, deps, ctx).state;
    expect(s.gm.hintStufeDieseFrage).toBe(1);
    expect((s.minigameState as VierLianenState).gesperrtGlobal).toHaveLength(1);
    s = beantworte(s, { p1: 1, p2: 1 });
    expect(s.players.p1.balance).toBe(110); // 150 × 0,75 = 112,5 → 110
  });

  it("Mitleids-Banane + W_final beim Finale-Start (Quick: Q=3, Faktor 1,25)", () => {
    let s = gestartet();
    s = reduce(
      s,
      { type: "gm.scoreAdjust", playerId: "p1", delta: 3000, grund: "test", override: true },
      deps,
      ctx,
    ).state;
    // Direkt vor das Finale springen (Abschnitt 3 „risiko" ist der letzte davor).
    s = { ...s, abschnittIndex: 3, phase: "zwischenstand", phaseEndsAt: clock.now() };
    clock.advance(1);
    const result = tick(s, deps, ctx);
    s = result.state;
    expect(s.plan?.abschnitte[s.abschnittIndex].typ).toBe("finale");
    expect(s.finaleWert).toBe(wFinal(3000, 3, 1.25)); // 1250
    expect(s.players.p2.balance).toBe(MITLEIDS_BANANE); // Letzter: +300
    expect(
      result.events.some((e) => e.type === "money_changed" && e.grund === "mitleids-banane"),
    ).toBe(true);
  });

  it("Finale bucht ±W_final und klemmt das Konto auf 0", () => {
    let s = gestartet();
    s = { ...s, abschnittIndex: 3, phase: "zwischenstand", phaseEndsAt: clock.now() };
    clock.advance(1);
    s = tick(s, deps, ctx).state; // → Finale-Erklärkarte (p1 kriegt als „Letzter" +300)
    s = weiter(s, ERKLAERKARTE_KURZ_MS);
    expect(s.phase).toBe("frage");
    const w = s.finaleWert ?? 0;
    expect(w).toBe(500); // niemand hat Geld ⇒ Untergrenze
    s = beantworte(s, { p1: 1, p2: 3 });
    expect(s.players.p1.balance).toBe(MITLEIDS_BANANE + w); // +W obendrauf
    expect(s.players.p2.balance).toBe(0); // −W/2 unter 0 ⇒ geklemmt auf 0
  });
});

// ---------- Joker-Framework ----------

describe("engine: Joker", () => {
  const jokerAn: Partial<MatchSettings> = { jokerAn: true };

  it("Bananen-Split (50:50): Gratis-Ladung reißt 2 falsche Optionen ab", () => {
    let s = gestartet({ settings: jokerAn });
    s = bisErsteFrage(s);
    const result = reduce(
      s,
      { type: "jokerUse", playerId: "p1", jokerId: "bananen-split" },
      deps,
      ctx,
    );
    expect(result.error).toBeUndefined();
    s = result.state;
    const mg = s.minigameState as VierLianenState;
    expect(mg.gesperrt.p1).toHaveLength(2);
    expect(mg.gesperrt.p1).not.toContain(1); // die richtige bleibt stehen
    expect(s.players.p1.jokers["bananen-split"]).toBe(0);
    expect(s.players.p1.balance).toBe(0); // Gratis-Ladung kostet nichts
  });

  it("Info-Joker-Grenze: nach 50:50 ist Schmiergeld in DERSELBEN Frage gesperrt", () => {
    let s = gestartet({ settings: jokerAn });
    s = bisErsteFrage(s);
    s = reduce(s, { type: "jokerUse", playerId: "p1", jokerId: "bananen-split" }, deps, ctx).state;
    const result = reduce(
      s,
      { type: "jokerUse", playerId: "p1", jokerId: "schmiergeld", stufe: 2 },
      deps,
      ctx,
    );
    expect(result.error).toBe("info-joker-limit");
  });

  it("Schmiergeld Stufe 2 flüstert den Anfangsbuchstaben (Kauf-und-Zünden)", () => {
    let s = gestartet({ settings: jokerAn });
    s = bisErsteFrage(s);
    s = reduce(
      s,
      { type: "gm.scoreAdjust", playerId: "p1", delta: 200, grund: "test" },
      deps,
      ctx,
    ).state;
    s = reduce(
      s,
      { type: "jokerUse", playerId: "p1", jokerId: "schmiergeld", stufe: 2 },
      deps,
      ctx,
    ).state;
    expect(s.hinweis.p1).toContain("B"); // Antwort „B" ⇒ Anfangsbuchstabe B
    expect(s.players.p1.balance).toBe(200 - 40); // 35 % von 100 → 40 (10er-Rundung)
  });

  it("Goldene Banane: vor-Frage-Fenster, ×2 auf den Gewinn der nächsten Frage", () => {
    let s = gestartet({ settings: jokerAn, pool: gemischterPool() });
    s = bisErsteFrage(s);
    const zu = reduce(
      s,
      { type: "jokerUse", playerId: "p1", jokerId: "goldene-banane" },
      deps,
      ctx,
    );
    expect(zu.error).toBe("fenster-zu"); // während der Frage nicht zündbar
    s = beantworte(s, { p1: 1, p2: 1 });
    s = reduce(s, { type: "jokerUse", playerId: "p1", jokerId: "goldene-banane" }, deps, ctx).state;
    expect(s.modifiers.some((m) => m.id === "goldene-banane" && m.betroffen.includes("p1"))).toBe(
      true,
    );
    expect(
      reduce(s, { type: "jokerUse", playerId: "p1", jokerId: "goldene-banane" }, deps, ctx).error,
    ).toBe("ausverkauft"); // 1× pro Match, keine Nachkäufe
    const vorher = s.players.p1.balance;
    s = weiter(s, AUFLOESUNG_MS); // Goldene Banane hebt die nächste Frage auf MEDIUM
    expect(s.aktuelleFragen[0].difficulty).toBe("medium");
    s = beantworte(s, { p1: 1, p2: 0 });
    // medium 250 + Speed 130 = 380, ×2 = 760.
    expect(s.players.p1.balance - vorher).toBe(760);
  });

  it("Bananentresor: Schild bis Ziel-Runde, Preis 10 % vom Konto", () => {
    let s = gestartet({ settings: jokerAn });
    s = reduce(
      s,
      { type: "gm.scoreAdjust", playerId: "p1", delta: 400, grund: "test" },
      deps,
      ctx,
    ).state;
    s = bisErsteFrage(s);
    s = beantworte(s, { p1: 1, p2: 1 });
    const result = reduce(
      s,
      { type: "jokerUse", playerId: "p1", jokerId: "bananentresor" },
      deps,
      ctx,
    );
    expect(result.error).toBeUndefined();
    s = result.state;
    expect(s.players.p1.schildBisRunde).toBe(1); // in der Auflösung: schützt DIESE Runde
    expect(s.players.p1.balance).toBe(400 + 150 - 60); // 10 % von 550 → 60 (10er)
  });

  it("Joker sind im Finale gesperrt", () => {
    let s = gestartet({ settings: jokerAn });
    s = { ...s, abschnittIndex: 4, phase: "aufloesung" }; // Finale-Abschnitt
    expect(
      reduce(s, { type: "jokerUse", playerId: "p1", jokerId: "goldene-banane" }, deps, ctx).error,
    ).toBe("im-finale-gesperrt");
  });

  it("jokerBuy: Nachkauf bis maxKaeufe, dann ausverkauft", () => {
    let s = gestartet({ settings: jokerAn });
    s = reduce(
      s,
      { type: "gm.scoreAdjust", playerId: "p1", delta: 400, grund: "test" },
      deps,
      ctx,
    ).state;
    s = reduce(
      s,
      { type: "jokerBuy", playerId: "p1", jokerId: "ueberziehungskredit" },
      deps,
      ctx,
    ).state;
    expect(s.players.p1.balance).toBe(250); // flat 150
    expect(s.players.p1.jokers.ueberziehungskredit).toBe(1);
    s = reduce(
      s,
      { type: "jokerBuy", playerId: "p1", jokerId: "ueberziehungskredit" },
      deps,
      ctx,
    ).state;
    expect(s.players.p1.balance).toBe(100);
    expect(
      reduce(s, { type: "jokerBuy", playerId: "p1", jokerId: "ueberziehungskredit" }, deps, ctx)
        .error,
    ).toBe("ausverkauft"); // maxKaeufe 2
  });
});

// ---------- Glücksrad ----------

describe("engine: Glücksrad", () => {
  /** Runde 1 durchspielen; letzte Frage reißt die Streak (saubere Folge-Rechnungen). */
  function imZwischenstand(): EngineState {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = beantworte(s, { p1: 1, p2: 0 });
    s = weiter(s, AUFLOESUNG_MS);
    s = beantworte(s, { p1: 1, p2: 0 });
    s = weiter(s, AUFLOESUNG_MS);
    s = beantworte(s, { p1: 0, p2: 0 }); // beide falsch — Streaks zurück auf 0
    s = weiter(s, AUFLOESUNG_MS);
    expect(s.phase).toBe("zwischenstand");
    return s;
  }

  it("gm.wheelSpin nur im Zwischenstand; Dreh ist deterministisch per Seed", () => {
    const basis = imZwischenstand();
    expect(reduce(gestartet(), { type: "gm.wheelSpin" }, deps, ctx).error).toBe(
      "nur-im-zwischenstand",
    );
    const a = reduce(basis, { type: "gm.wheelSpin" }, deps, { clock, rng: createRng(7) });
    const b = reduce(basis, { type: "gm.wheelSpin" }, deps, { clock, rng: createRng(7) });
    expect(a.state.rad?.ergebnis).toBe(b.state.rad?.ergebnis);
    expect(a.state.rad?.segmente).toEqual(b.state.rad?.segmente);
    expect(a.state.phase).toBe("rad");
    expect(a.state.rad?.subphase).toBe("dreh");
  });

  it("gerigged: rigTarget wird das Ergebnis, Modifier wirkt auf die nächste Frage", () => {
    let s = imZwischenstand();
    s = reduce(s, { type: "gm.wheelSpin", rigTarget: "doppelter-zaster" }, deps, ctx).state;
    expect(s.rad?.ergebnis).toBe("doppelter-zaster");
    expect(s.rad?.rigged).toBe(true);
    s = weiter(s, s.rad?.drehDauerMs ?? 0); // Dreh vorbei → Wirkung → Ergebnis-Karte
    expect(s.rad?.subphase).toBe("ergebnis");
    expect(s.modifiers.some((m) => m.id === "doppelter-zaster")).toBe(true);
    s = weiter(s, RAD_ERGEBNIS_MS); // Ergebnis-Karte vorbei → nächster Abschnitt
    expect(s.phase).toBe("erklaerkarte");
    s = weiter(s, ERKLAERKARTE_KURZ_MS);
    const vorher = s.players.p1.balance;
    s = beantworte(s, { p1: 1, p2: 0 });
    // easy-Pool: 100 + 50 Speed = 150, ×2 (Doppelter Zaster) = 300.
    expect(s.players.p1.balance - vorher).toBe(300);
    expect(s.modifiers.some((m) => m.id === "doppelter-zaster")).toBe(false); // verbraucht
  });

  it("Umarmungs-Bonus: Interaktion zahlt +50 pro gedrücktem „Umarmt!“", () => {
    let s = imZwischenstand();
    const p1Vorher = s.players.p1.balance;
    s = reduce(s, { type: "gm.wheelSpin", rigTarget: "umarmungs-bonus" }, deps, ctx).state;
    s = weiter(s, s.rad?.drehDauerMs ?? 0);
    expect(s.rad?.subphase).toBe("interaktion");
    s = reduce(s, { type: "radAktion", playerId: "p1", wahl: "umarmt" }, deps, ctx).state;
    s = reduce(s, { type: "radAktion", playerId: "p2", wahl: "umarmt" }, deps, ctx).state;
    clock.advance(50);
    s = tick(s, deps, ctx).state; // alle gewählt ⇒ sofort auflösen
    expect(s.rad?.subphase).toBe("ergebnis");
    expect(s.players.p1.balance).toBe(p1Vorher + 50);
  });

  it("Pech-Schutz: dasselbe Segment kommt nicht 2× in Folge", () => {
    let s = imZwischenstand();
    s = reduce(s, { type: "gm.wheelSpin", rigTarget: "doppelter-zaster" }, deps, ctx).state;
    expect(s.radHistorie.letztesSegment).toBe("doppelter-zaster");
    s = weiter(s, s.rad?.drehDauerMs ?? 0);
    s = weiter(s, RAD_ERGEBNIS_MS);
    // Zurück in einen Zwischenstand zwingen und dasselbe Segment nochmal riggen:
    s = { ...s, phase: "zwischenstand", phaseEndsAt: null, rad: null };
    const nochmal = reduce(s, { type: "gm.wheelSpin", rigTarget: "doppelter-zaster" }, deps, ctx);
    expect(nochmal.state.rad?.rigged).toBe(false); // Rig griff nicht — Pech-Schutz
    expect(nochmal.state.rad?.ergebnis).not.toBe("doppelter-zaster");
  });
});

// ---------- GM-Werkzeuge ----------

describe("engine: GM-Werkzeuge", () => {
  it("score.adjust: Grund-Pflicht + Soft-Cap (Override erlaubt mehr)", () => {
    const s = mitSpielern();
    expect(
      reduce(s, { type: "gm.scoreAdjust", playerId: "p1", delta: 500, grund: "" }, deps, ctx).error,
    ).toBe("grund-pflicht");
    expect(
      reduce(s, { type: "gm.scoreAdjust", playerId: "p1", delta: 500, grund: "Show" }, deps, ctx)
        .error,
    ).toBe("soft-cap:400");
    const ok = reduce(
      s,
      { type: "gm.scoreAdjust", playerId: "p1", delta: 500, grund: "Show", override: true },
      deps,
      ctx,
    );
    expect(ok.state.players.p1.balance).toBe(500);
  });

  it("score.adjust: Begründungs-Chip wird ÖFFENTLICH inszeniert (Moment, §4.2/1)", () => {
    const s = mitSpielern();
    const r = reduce(
      s,
      { type: "gm.scoreAdjust", playerId: "p1", delta: 100, grund: "Stil-Punkte" },
      deps,
      ctx,
    );
    const m = r.state.momente[r.state.momente.length - 1];
    expect(m?.text).toContain("Stil-Punkte");
    expect(m?.text).toContain("Anna");
    expect(r.events.some((e) => e.type === "moment")).toBe(true);
  });

  it("moodPoll: Blitz-Stimmung erscheint in der Player-View (Emoji-Poll am Handy)", () => {
    const roomInfo: RoomInfo = {
      roomCode: "TEST",
      joinUrl: "http://x/j/TEST",
      qrPath: "/api/qr?code=TEST",
      gmPin: "0000",
      gmLog: [],
    };
    let s = gestartet();
    expect((viewFor(s, "player", deps, roomInfo, ctx, "p1") as { mood: unknown }).mood).toBeNull();
    s = reduce(s, { type: "gm.moodPoll" }, deps, ctx).state;
    s = reduce(s, { type: "voteCast", playerId: "p1", option: 3 }, deps, ctx).state;
    const view = viewFor(s, "player", deps, roomInfo, ctx, "p2") as {
      mood: { endetAt: number; deineWahl: number | null } | null;
    };
    expect(view.mood).not.toBeNull();
    expect(view.mood?.deineWahl).toBeNull(); // p2 hat noch nicht getippt
    const viewP1 = viewFor(s, "player", deps, roomInfo, ctx, "p1") as {
      mood: { deineWahl: number | null } | null;
    };
    expect(viewP1.mood?.deineWahl).toBe(3);
  });

  it("timer.extend: rettet eine ablaufende Frage, max. 2× pro Frage", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    clock.advance(FRAGE_TIMER_MS.easy + 1); // eigentlich abgelaufen …
    s = reduce(s, { type: "gm.timerExtend", ms: 15_000 }, deps, ctx).state;
    s = tick(s, deps, ctx).state;
    expect(s.phase).toBe("frage"); // … aber der GM hat verlängert
    s = reduce(s, { type: "gm.timerExtend", ms: 15_000 }, deps, ctx).state;
    expect(reduce(s, { type: "gm.timerExtend", ms: 15_000 }, deps, ctx).error).toBe(
      "max-verlaengerungen",
    );
  });

  it("pause friert ein (auch Antworten), resume verschiebt Deadlines fair", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = reduce(s, { type: "gm.pause", text: "Pinkelpause" }, deps, ctx).state;
    expect(s.paused).not.toBeNull();
    expect(
      reduce(
        s,
        {
          type: "playerAction",
          playerId: "p1",
          minigameId: "vier-lianen",
          action: { type: "answer", choice: 1 },
          atServerTime: clock.now(),
        },
        deps,
        ctx,
      ).error,
    ).toBe("keine-frage-aktiv");
    clock.advance(60_000);
    s = tick(s, deps, ctx).state;
    expect(s.phase).toBe("frage"); // Timer lief NICHT weiter
    s = reduce(s, { type: "gm.resume" }, deps, ctx).state;
    s = weiter(s, FRAGE_TIMER_MS.easy - 1_000);
    expect(s.phase).toBe("frage"); // Restzeit läuft normal
    s = weiter(s, 2_000);
    expect(s.phase).toBe("aufloesung");
  });

  it("Timeout-Screen: Pause mit Countdown resumed automatisch", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = reduce(s, { type: "gm.pause", text: "Pizza-Pause", dauerMs: 600_000 }, deps, ctx).state;
    expect(s.paused?.bis).toBe(clock.now() + 600_000);
    s = weiter(s, 600_000);
    expect(s.paused).toBeNull();
    expect(s.phase).toBe("frage");
  });

  it("gm.next skippt universell (frage → aufloesung → nächste frage)", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = reduce(s, { type: "gm.next" }, deps, ctx).state;
    expect(s.phase).toBe("aufloesung");
    s = reduce(s, { type: "gm.next" }, deps, ctx).state;
    expect(s.phase).toBe("frage");
    expect(s.frageInAbschnitt).toBe(1);
  });

  it("markBroken (annul) in der Auflösung wickelt die letzte Buchung zurück", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = beantworte(s, { p1: 1, p2: 3 });
    expect(s.players.p1.balance).toBe(150);
    expect(s.players.p2.balance).toBe(25);
    const result = reduce(
      s,
      { type: "gm.markBroken", grund: "doppeldeutig", refund: "annul" },
      deps,
      ctx,
    );
    expect(result.state.players.p1.balance).toBe(0);
    expect(result.state.players.p2.balance).toBe(0);
    expect(result.events.some((e) => e.type === "frage_annulliert")).toBe(true);
  });

  it("markBroken (grantAll) während der Frage: Grundwert für alle, keine Buchung", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = reduce(s, { type: "gm.markBroken", grund: "kaputt", refund: "grantAll" }, deps, ctx).state;
    expect(s.phase).toBe("aufloesung");
    expect(s.players.p1.balance).toBe(100); // easy-Grundwert als Reklamation
    expect(s.players.p2.balance).toBe(100);
  });

  it("punish: Bananensteuer füllt das Glas, Anti-Mobbing blockt 2× in Folge", () => {
    let s = gestartet();
    s = reduce(s, { type: "gm.punish", playerId: "p1", strafe: "bananensteuer" }, deps, ctx).state;
    expect(s.players.p1.balance).toBe(-100);
    expect(s.jackpotGlas).toBe(600); // 500 Start + 100
    expect(reduce(s, { type: "gm.punish", playerId: "p1", strafe: "clown" }, deps, ctx).error).toBe(
      "anti-mobbing",
    );
    s = reduce(s, { type: "gm.punish", playerId: "p2", strafe: "clown" }, deps, ctx).state;
    expect(s.players.p2.clownBisRunde).not.toBeNull();
  });

  it("boost: Grund-Pflicht, max. 1/Runde, x2 wirkt auf die nächste Frage", () => {
    let s = gestartet();
    expect(
      reduce(s, { type: "gm.boost", playerId: "p2", art: "x2", grund: "" }, deps, ctx).error,
    ).toBe("grund-pflicht");
    s = reduce(
      s,
      { type: "gm.boost", playerId: "p2", art: "x2", grund: "Underdog" },
      deps,
      ctx,
    ).state;
    expect(s.modifiers.some((m) => m.id === "boost-x2" && m.betroffen.includes("p2"))).toBe(true);
    expect(
      reduce(s, { type: "gm.boost", playerId: "p2", art: "plus300", grund: "nochmal" }, deps, ctx)
        .error,
    ).toBe("max-boosts");
    s = bisErsteFrage(s);
    s = beantworte(s, { p1: 1, p2: 1 });
    expect(s.players.p2.balance).toBe(300); // 150 × 2
  });

  it("jokerGrant: Budget 6 Chips, „alle“ kostet pro Kopf", () => {
    let s = gestartet({ settings: { jokerAn: true } });
    s = reduce(
      s,
      { type: "gm.jokerGrant", ziel: "alle", jokerId: "bananen-split" },
      deps,
      ctx,
    ).state;
    expect(s.gm.jokerChips).toBe(4);
    expect(s.players.p1.jokers["bananen-split"]).toBe(2); // 1 gratis + 1 Grant
    for (let i = 0; i < 4; i++) {
      s = reduce(
        s,
        { type: "gm.jokerGrant", ziel: "p2", jokerId: "bananen-split" },
        deps,
        ctx,
      ).state;
    }
    expect(s.gm.jokerChips).toBe(0);
    expect(
      reduce(s, { type: "gm.jokerGrant", ziel: "p2", jokerId: "bananen-split" }, deps, ctx).error,
    ).toBe("joker-budget-leer");
  });

  it("hintWhisper: privater Tipp landet im State, max. 2 pro Spieler/Runde", () => {
    let s = gestartet();
    s = reduce(s, { type: "gm.hintWhisper", playerId: "p2", text: "Denk an B!" }, deps, ctx).state;
    expect(s.fluesterTipp.p2).toBe("Denk an B!");
    s = reduce(s, { type: "gm.hintWhisper", playerId: "p2", text: "Wirklich B!" }, deps, ctx).state;
    expect(
      reduce(s, { type: "gm.hintWhisper", playerId: "p2", text: "B!!" }, deps, ctx).error,
    ).toBe("max-fluester");
  });

  it("voteStart + voteCast: Ergebnis kommt, sobald alle gewählt haben", () => {
    let s = gestartet();
    s = reduce(
      s,
      { type: "gm.voteStart", frage: "Nochmal so eine Runde?", optionen: ["Ja", "Nein"] },
      deps,
      ctx,
    ).state;
    expect(s.voting).not.toBeNull();
    s = reduce(s, { type: "voteCast", playerId: "p1", option: 0 }, deps, ctx).state;
    const result = reduce(s, { type: "voteCast", playerId: "p2", option: 0 }, deps, ctx);
    expect(result.state.voting).toBeNull();
    expect(result.events.some((e) => e.type === "vote_result")).toBe(true);
  });

  it("moodPoll: Budget 3, Ergebnis-Histogramm in der Historie", () => {
    let s = gestartet();
    s = reduce(s, { type: "gm.moodPoll" }, deps, ctx).state;
    expect(s.gm.blitzStimmungen).toBe(2);
    s = reduce(s, { type: "voteCast", playerId: "p1", option: 4 }, deps, ctx).state;
    s = reduce(s, { type: "voteCast", playerId: "p2", option: 3 }, deps, ctx).state;
    expect(s.mood).toBeNull();
    expect(s.gm.stimmungsHistorie[0].werte).toEqual([0, 0, 0, 1, 1]);
  });

  it("encore: +1 Frage in dieser Runde (nur in der Auflösung, max. 2)", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    expect(reduce(s, { type: "gm.encore" }, deps, ctx).error).toBe("nur-in-aufloesung");
    s = beantworte(s, { p1: 1, p2: 1 });
    s = reduce(s, { type: "gm.encore" }, deps, ctx).state;
    expect(s.plan?.abschnitte[0].fragen).toBe(4);
    expect(s.plan?.fragenTotal).toBe(16);
  });

  it("gameSkip (keepPoints=false): Runde sofort in den Zwischenstand, ohne Buchung", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    clock.advance(1_000);
    s = antwort(s, "p1", 1);
    s = reduce(s, { type: "gm.gameSkip", keepPoints: false }, deps, ctx).state;
    expect(s.phase).toBe("zwischenstand");
    expect(s.players.p1.balance).toBe(0); // nichts gebucht
  });

  it("gm.ende: Abkürzung zur Siegerehrung, dort nochmal ⇒ ende", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = reduce(s, { type: "gm.ende" }, deps, ctx).state;
    expect(s.phase).toBe("siegerehrung");
    expect(s.siegerehrung?.platzierungen).toHaveLength(2);
    s = reduce(s, { type: "gm.ende" }, deps, ctx).state;
    expect(s.phase).toBe("ende");
    expect(s.feedbackAngefragt).toBe(true);
  });

  it("settings: Modus nur in der Lobby wechselbar", () => {
    let s = mitSpielern();
    s = reduce(s, { type: "gm.settings", patch: { modus: "klassik" } }, deps, ctx).state;
    expect(s.settings.modus).toBe("klassik");
    let laufend = gestartet();
    laufend = reduce(
      laufend,
      { type: "gm.settings", patch: { modus: "marathon", kurzeShow: false } },
      deps,
      ctx,
    ).state;
    expect(laufend.settings.modus).toBe("quick"); // Modus-Patch verworfen
    expect(laufend.settings.kurzeShow).toBe(false); // Rest übernommen
  });
});

// ---------- Presence ----------

describe("engine: Presence", () => {
  it("markiert Spieler offline (Grace) und wieder online", () => {
    let s = mitSpielern();
    s = reduce(
      s,
      { type: "presence", playerId: "p1", connected: false, graceUntil: clock.now() + 180_000 },
      deps,
      ctx,
    ).state;
    expect(s.players.p1.connected).toBe(false);
    expect(s.players.p1.graceUntil).not.toBeNull();
    s = reduce(
      s,
      { type: "presence", playerId: "p1", connected: true, graceUntil: null },
      deps,
      ctx,
    ).state;
    expect(s.players.p1.connected).toBe(true);
  });

  it("AFK friert die Streak ein (keine Antwort + offline)", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = beantworte(s, { p1: 1, p2: 1 });
    expect(s.players.p2.streak).toBe(1);
    s = weiter(s, AUFLOESUNG_MS); // Frage 2 startet
    s = reduce(
      s,
      { type: "presence", playerId: "p2", connected: false, graceUntil: null },
      deps,
      ctx,
    ).state;
    clock.advance(1_000);
    s = antwort(s, "p1", 1);
    s = weiter(s, FRAGE_TIMER_MS.easy); // Timeout — p2 hat (offline) nicht geantwortet
    expect(s.phase).toBe("aufloesung");
    expect(s.players.p2.streak).toBe(1); // eingefroren statt gerissen
  });
});

// ---------- Kompakte Quick-Affenbank (§6.2): baueMods reicht das Tuning durch ----------

describe("engine: kompakte Quick-Affenbank", () => {
  const abDeps: EngineDeps = { getPlugin: () => affenbankPlugin };

  /** Match starten und die GELD-Runde (Affenbank) direkt anspielen. */
  function affenbankFrage(settings: Partial<MatchSettings>): EngineState {
    let s = createInitialState({ ...defaultSettings("quick"), autoGm: false, ...settings });
    s = reduce(
      s,
      { type: "join", playerId: "p1", name: "Anna", avatar: "gelb" },
      abDeps,
      ctx,
    ).state;
    s = reduce(s, { type: "join", playerId: "p2", name: "Ben", avatar: "rot" }, abDeps, ctx).state;
    s = reduce(
      s,
      {
        type: "start",
        matchId: "m_ab",
        fragenPool: einfacherPool(),
        verfuegbareMinigames: ["affenbank"],
      },
      abDeps,
      ctx,
    ).state;
    // Direkt zum Affenbank-Abschnitt springen und die Runde starten.
    const index = s.plan!.abschnitte.findIndex((a) => a.minigameId === "affenbank");
    expect(index).toBeGreaterThanOrEqual(0);
    s = { ...s, abschnittIndex: index };
    return starteFrage(s, abDeps, ctx).state;
  }

  it("Quick: init bekommt mods.affenbank = 1 Durchgang × 45 s", () => {
    const s = affenbankFrage({});
    expect(s.minigameId).toBe("affenbank");
    const mg = s.minigameState as { durchgaengeTotal: number; ketteMs: number };
    expect(mg.durchgaengeTotal).toBe(1);
    expect(mg.ketteMs).toBe(AB_QUICK_KETTE_MS);
  });

  it("Klassik behält die vollen 2 Durchgänge × 90 s", () => {
    const s = affenbankFrage({ modus: "klassik" });
    const mg = s.minigameState as { durchgaengeTotal: number; ketteMs: number };
    expect(mg.durchgaengeTotal).toBe(2);
    expect(mg.ketteMs).toBe(AB_KETTE_MS);
  });
});

// ---------- Der Beweis: komplettes Quick-Match, deterministisch simuliert ----------

describe("engine: komplettes Quick-Match (alle Phasen)", () => {
  it("spielt lobby → … → siegerehrung → ende komplett durch", () => {
    // 3 Spieler, bunter Pool (Kategorien-Wahl aktiv), Auto-GM AN (Heuristiken laufen mit).
    let s = gestartet({ spieler: 3, pool: bunterPool(), settings: { autoGm: true } });
    const phasen = new Set<string>([s.phase]);
    const events: EngineEvent[] = [];
    const sammle = (r: { state: EngineState; events: EngineEvent[] }): EngineState => {
      events.push(...r.events);
      return r.state;
    };
    const spielerAktion = (pid: string, choice: number): EngineAction => ({
      type: "playerAction",
      playerId: pid,
      minigameId: s.minigameId ?? "vier-lianen",
      action: { type: "answer", choice },
      atServerTime: clock.now(),
    });

    let schritte = 0;
    while (s.phase !== "ende" && schritte < 5_000) {
      schritte += 1;
      clock.advance(500);
      s = sammle(tick(s, deps, ctx));
      phasen.add(s.phase);

      if (s.phase === "frage") {
        const richtig = s.aktuelleFragen[0]?.answer ?? 1;
        // p1 + p3 antworten richtig, p2 immer falsch (Underdog-Systeme feuern).
        s = sammle(reduce(s, spielerAktion("p1", richtig), deps, ctx));
        s = sammle(reduce(s, spielerAktion("p2", (richtig + 1) % 4), deps, ctx));
        s = sammle(reduce(s, spielerAktion("p3", richtig), deps, ctx));
      } else if (s.phase === "erklaerkarte") {
        for (const pid of ["p1", "p2", "p3"]) {
          s = sammle(reduce(s, { type: "playerReady", playerId: pid }, deps, ctx));
        }
      } else if (s.phase === "kategorie-wahl" && s.kategorieWahl) {
        const wahl = s.kategorieWahl.optionen[0];
        for (const pid of ["p1", "p2", "p3"]) {
          s = sammle(
            reduce(s, { type: "kategorieVote", playerId: pid, kategorie: wahl }, deps, ctx),
          );
        }
      } else if (s.phase === "rad" && s.rad?.subphase === "interaktion") {
        const wahl =
          s.rad.ergebnis === "boersen-roulette"
            ? "long"
            : s.rad.ergebnis === "umarmungs-bonus"
              ? "umarmt"
              : "ja";
        for (const pid of ["p1", "p2", "p3"]) {
          s = sammle(reduce(s, { type: "radAktion", playerId: pid, wahl }, deps, ctx));
        }
      }
      phasen.add(s.phase);
    }

    // 1) Das Match ist durch — inklusive ALLER Phasen.
    expect(s.phase).toBe("ende");
    for (const p of [
      "intro",
      "kategorie-wahl",
      "erklaerkarte",
      "frage",
      "aufloesung",
      "zwischenstand",
      "rad",
      "siegerehrung",
      "ende",
    ]) {
      expect([...phasen], `Phase ${p} muss vorkommen`).toContain(p);
    }

    // 2) Alle 15 Fragen des Quick-Plans wurden gestellt (4×3 + 3 Finale).
    expect(s.fragenZaehler).toBeGreaterThanOrEqual(15);

    // 3) Endstand + Events: Underdog-Momente und Rad sind gelaufen.
    expect(s.siegerehrung?.platzierungen).toHaveLength(3);
    expect(s.siegerehrung?.platzierungen[0].balance).toBeGreaterThan(0);
    expect(s.siegerehrung?.platzierungen[0].at).toBeGreaterThan(0);
    expect(events.some((e) => e.type === "money_changed" && e.grund === "mitleids-banane")).toBe(
      true,
    );
    expect(events.some((e) => e.type === "rad_gestartet")).toBe(true);
    expect(events.some((e) => e.type === "kategorie_gewaehlt")).toBe(true);
    expect(events.some((e) => e.type === "match_ended")).toBe(true);

    // 4) Feedback-Formular ist am Ende freigeschaltet.
    expect(s.feedbackAngefragt).toBe(true);
    const fb = reduce(
      s,
      { type: "feedbackText", playerId: "p2", text: "Mehr Bananen!" },
      deps,
      ctx,
    );
    expect(fb.state.feedback).toEqual([{ playerId: "p2", text: "Mehr Bananen!" }]);
  }, 20_000);
});

describe("engine: Siegerehrung → ende (Timer)", () => {
  it("wechselt nach SIEGEREHRUNG_MS automatisch in den Abspann", () => {
    let s = gestartet();
    s = reduce(s, { type: "gm.ende" }, deps, ctx).state;
    expect(s.phase).toBe("siegerehrung");
    s = weiter(s, SIEGEREHRUNG_MS);
    expect(s.phase).toBe("ende");
  });
});

// ---------- Befund-Fixes (Playthrough-Testberichte) ----------

describe("engine: Voting-Ergebnis-Einblendung (Befund: Ergebnis erschien nie)", () => {
  const roomInfo: RoomInfo = {
    roomCode: "TEST",
    joinUrl: "http://x/j/TEST",
    qrPath: "/api/qr?code=TEST",
    gmPin: "0000",
    gmLog: [],
  };

  it("nach Voting-Schluss steht das Ergebnis ~7 s in allen Views, dann räumt der Tick auf", () => {
    let s = gestartet();
    s = reduce(
      s,
      { type: "gm.voteStart", frage: "Pizza bestellen?", optionen: ["Ja", "Nein"] },
      deps,
      ctx,
    ).state;
    s = reduce(s, { type: "voteCast", playerId: "p1", option: 0 }, deps, ctx).state;
    s = reduce(s, { type: "voteCast", playerId: "p2", option: 0 }, deps, ctx).state;
    // Alle haben gestimmt ⇒ Voting zu, Ergebnis-Einblendung an (Balken + Sieger).
    expect(s.voting).toBeNull();
    expect(s.votingErgebnis).toMatchObject({
      frage: "Pizza bestellen?",
      stimmen: [2, 0],
      gewinnerIndex: 0,
    });
    expect(s.votingErgebnis?.endetAt).toBe(clock.now() + VOTING_ERGEBNIS_MS);
    // Screen UND Handy sehen die Einblendung (ViewBase.votingErgebnis):
    for (const rolle of ["screen", "player"] as const) {
      const view = viewFor(s, rolle, deps, roomInfo, ctx, "p1") as {
        votingErgebnis: { gewinnerIndex: number | null } | null;
      };
      expect(view.votingErgebnis?.gewinnerIndex).toBe(0);
    }
    // Nach ~7 s verschwindet sie wieder (Event triggert den Broadcast).
    clock.advance(VOTING_ERGEBNIS_MS + 1);
    const r = tick(s, deps, ctx);
    expect(r.state.votingErgebnis).toBeNull();
    expect(r.events).toContainEqual({ type: "vote_ergebnis_ende" });
  });

  it("ohne abgegebene Stimme: Timeout liefert gewinnerIndex null (keine Fake-Sieger)", () => {
    let s = gestartet();
    s = reduce(
      s,
      { type: "gm.voteStart", frage: "Noch eine Runde?", optionen: ["Ja", "Nein"], dauerMs: 5000 },
      deps,
      ctx,
    ).state;
    clock.advance(5001);
    s = tick(s, deps, ctx).state;
    expect(s.voting).toBeNull();
    expect(s.votingErgebnis?.gewinnerIndex).toBeNull();
    expect(s.votingErgebnis?.stimmen).toEqual([0, 0]);
  });
});

describe("engine: Podest fixiert ab Siegerehrung (Befund: score.adjust im Finale)", () => {
  it("lehnt scoreAdjust/punish/boost in siegerehrung UND ende ab", () => {
    let s = gestartet();
    s = bisErsteFrage(s);
    s = reduce(s, { type: "gm.ende" }, deps, ctx).state;
    expect(s.phase).toBe("siegerehrung");
    const kommandos: EngineAction[] = [
      { type: "gm.scoreAdjust", playerId: "p1", delta: 500, grund: "Show", override: true },
      { type: "gm.punish", playerId: "p1", strafe: "bananensteuer" },
      { type: "gm.boost", playerId: "p1", art: "plus300", grund: "Underdog" },
    ];
    const vorher = s.players.p1.balance;
    for (const cmd of kommandos) {
      const r = reduce(s, cmd, deps, ctx);
      expect(r.error).toBe("podest-fixiert");
      expect(r.state.players.p1.balance).toBe(vorher);
    }
    s = reduce(s, { type: "gm.ende" }, deps, ctx).state;
    expect(s.phase).toBe("ende");
    expect(reduce(s, kommandos[0], deps, ctx).error).toBe("podest-fixiert");
  });
});

describe("engine: Maßanzug nur für per-Spieler-Formate (Befund: wirkungslos außer vier-lianen)", () => {
  it("Plugin MIT meta.perSpielerFragen konsumiert die Zuweisung (eigene Frage für p1)", () => {
    let s = gestartet();
    s = reduce(s, { type: "gm.questionAssign", playerId: "p1", questionId: "q9" }, deps, ctx).state;
    s = bisErsteFrage(s);
    expect(s.phase).toBe("frage");
    expect(s.zuweisungen).toEqual({}); // konsumiert
    const mg = s.minigameState as VierLianenState;
    expect(mg.fragenProSpieler.p1?.id).toBe("q9");
    expect(s.usedQuestionIds).toContain("q9");
  });

  it("Plugin OHNE das Flag lässt die Zuweisung STEHEN (greift beim nächsten Format)", () => {
    const ohneFlag: EngineDeps = {
      getPlugin: () => ({
        ...vierLianenPlugin,
        meta: { ...vierLianenPlugin.meta, perSpielerFragen: false },
      }),
    };
    let s = mitSpielern();
    s = reduce(
      s,
      {
        type: "start",
        matchId: "m_test",
        fragenPool: einfacherPool(),
        verfuegbareMinigames: ["vier-lianen"],
      },
      ohneFlag,
      ctx,
    ).state;
    s = reduce(
      s,
      { type: "gm.questionAssign", playerId: "p1", questionId: "q9" },
      ohneFlag,
      ctx,
    ).state;
    clock.advance(INTRO_MS + 1);
    s = tick(s, ohneFlag, ctx).state;
    clock.advance(ERKLAERKARTE_KURZ_MS + 1);
    s = tick(s, ohneFlag, ctx).state;
    expect(s.phase).toBe("frage");
    expect(s.zuweisungen).toEqual({ p1: "q9" }); // NICHT konsumiert
    expect((s.minigameState as VierLianenState).fragenProSpieler).toEqual({});
  });
});

describe("engine: GM-Wechsel-Moment (Befund: 2. GM-Verbindung still parallel)", () => {
  it("gm.wechsel erzeugt den Screen-Toast (takeover vs. nachgerückt)", () => {
    const takeover = reduce(gestartet(), { type: "gm.wechsel", grund: "takeover" }, deps, ctx);
    expect(takeover.state.momente.at(-1)?.text).toContain("PIN übernommen");
    const nachrueckt = reduce(gestartet(), { type: "gm.wechsel", grund: "nachrueckt" }, deps, ctx);
    expect(nachrueckt.state.momente.at(-1)?.text).toContain("übernimmt das Cockpit");
  });
});
