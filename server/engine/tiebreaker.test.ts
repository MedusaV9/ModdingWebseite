// SUDDEN-DEATH (v2): Kokosnuss-Shake-Tiebreaker — Trigger bei Gleichstand an
// der Spitze nach dem Plan, Tap-Frenzy mit Server-Kappe, Re-Shake bei erneutem
// Gleichstand (max. 3, dann Los) und Sieger-Sortierung in der Siegerehrung.
// Dazu: die Replay-Highlights-Phase zwischen Plan-Ende und Siegerehrung.
import { beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { defaultSettings } from "../../shared/settings";
import { createTestClock } from "../../shared/time";
import { vierLianenPlugin } from "../minigames/vier-lianen/index";
import { createInitialState, reduce, tick } from "./engine";
import { naechsterAbschnitt, type EngineDeps } from "./flow";
import type { ChronikEintrag } from "./highlights";
import { viewFor } from "./views";
import {
  HIGHLIGHT_KARTE_MS,
  TIEBREAKER_COUNTDOWN_MS,
  TIEBREAKER_ERGEBNIS_MS,
  TIEBREAKER_SHAKE_MS,
  type EngineState,
} from "./types";

const frage = (id: string): Question => ({
  id,
  kind: "choice4",
  category: "affen",
  difficulty: "easy",
  text: `Frage ${id}?`,
  options: ["A", "B", "C", "D"],
  answer: 1,
  erklaerung: "Weil B.",
});

let clock: ReturnType<typeof createTestClock>;
let ctx: { clock: typeof clock; rng: ReturnType<typeof createRng> };
const deps: EngineDeps = { getPlugin: () => vierLianenPlugin };

beforeEach(() => {
  clock = createTestClock(1_000_000);
  ctx = { clock, rng: createRng(42) };
});

/** Match mit N Spielern starten und ans PLAN-ENDE spulen (letzter Abschnitt). */
function amPlanEnde(balances: Record<string, number>, chronik: ChronikEintrag[] = []): EngineState {
  let s = createInitialState({ ...defaultSettings("quick"), autoGm: false });
  const farben = ["gelb", "rot", "blau", "gruen"] as const;
  Object.keys(balances).forEach((pid, i) => {
    s = reduce(
      s,
      { type: "join", playerId: pid, name: `P${i + 1}`, avatar: farben[i] },
      deps,
      ctx,
    ).state;
  });
  s = reduce(
    s,
    {
      type: "start",
      matchId: "m_tb",
      fragenPool: Array.from({ length: 30 }, (_, i) => frage(`q${i + 1}`)),
      verfuegbareMinigames: ["vier-lianen"],
    },
    deps,
    ctx,
  ).state;
  const players = { ...s.players };
  for (const [pid, balance] of Object.entries(balances)) {
    players[pid] = { ...players[pid], balance };
  }
  return {
    ...s,
    players,
    chronik,
    // Letzter Abschnitt „läuft" — naechsterAbschnitt springt dahinter.
    abschnittIndex: (s.plan?.abschnitte.length ?? 1) - 1,
  };
}

describe("tiebreaker: Trigger bei Gleichstand an der Spitze", () => {
  it("zündet den Kokosnuss-Shake, wenn 2 Spieler exakt gleichauf führen", () => {
    const s0 = amPlanEnde({ p1: 800, p2: 800, p3: 300 });
    const r = naechsterAbschnitt(s0, deps, ctx);
    expect(r.state.phase).toBe("tiebreaker");
    expect(r.state.tiebreaker?.teilnehmer).toEqual(["p1", "p2"]);
    expect(r.state.tiebreaker?.subphase).toBe("countdown");
    expect(r.state.tiebreaker?.betrag).toBe(800);
    expect(r.events.some((e) => e.type === "tiebreaker_gestartet")).toBe(true);
  });

  it("zündet bei 3-fachem Gleichstand mit allen dreien", () => {
    const r = naechsterAbschnitt(amPlanEnde({ p1: 500, p2: 500, p3: 500 }), deps, ctx);
    expect(r.state.tiebreaker?.teilnehmer).toEqual(["p1", "p2", "p3"]);
  });

  it("KEIN Tiebreaker ohne Gleichstand — es geht direkt Richtung Siegerehrung", () => {
    const r = naechsterAbschnitt(amPlanEnde({ p1: 900, p2: 500 }), deps, ctx);
    expect(r.state.phase).toBe("siegerehrung"); // leere Chronik ⇒ keine Highlights
    expect(r.state.tiebreaker).toBeNull();
  });

  it("Gleichstand NICHT an der Spitze (2. + 3.) zündet nichts", () => {
    const r = naechsterAbschnitt(amPlanEnde({ p1: 900, p2: 400, p3: 400 }), deps, ctx);
    expect(r.state.phase).toBe("siegerehrung");
  });
});

describe("tiebreaker: Shake-Ablauf", () => {
  function imShake(): EngineState {
    let s = naechsterAbschnitt(amPlanEnde({ p1: 800, p2: 800 }), deps, ctx).state;
    clock.advance(TIEBREAKER_COUNTDOWN_MS + 1);
    s = tick(s, deps, ctx).state;
    expect(s.tiebreaker?.subphase).toBe("shake");
    return s;
  }

  it("countdown → shake: Taps zählen erst im Shake-Fenster", () => {
    let s = naechsterAbschnitt(amPlanEnde({ p1: 800, p2: 800 }), deps, ctx).state;
    expect(reduce(s, { type: "shakeTap", playerId: "p1", taps: 5 }, deps, ctx).error).toBe(
      "shake-laeuft-nicht",
    );
    clock.advance(TIEBREAKER_COUNTDOWN_MS + 1);
    s = tick(s, deps, ctx).state;
    const r = reduce(s, { type: "shakeTap", playerId: "p1", taps: 5 }, deps, ctx);
    expect(r.state.tiebreaker?.taps.p1).toBe(5);
    expect(r.events).toEqual([{ type: "shake_tap", playerId: "p1", taps: 5 }]);
  });

  it("kappt Monster-Batches auf 40 und weist Nicht-Teilnehmer ab", () => {
    const s = imShake();
    const r = reduce(s, { type: "shakeTap", playerId: "p1", taps: 400 }, deps, ctx);
    expect(r.state.tiebreaker?.taps.p1).toBe(40);
    // p3 ist gar nicht im Raum — und ein Fremder erst recht nicht im Shake.
    expect(reduce(s, { type: "shakeTap", playerId: "p9", taps: 3 }, deps, ctx).error).toBe(
      "nicht-im-shake",
    );
  });

  it("mehr Taps gewinnen: Ergebnis + Sieger-Sortierung + Award", () => {
    let s = imShake();
    s = reduce(s, { type: "shakeTap", playerId: "p1", taps: 12 }, deps, ctx).state;
    s = reduce(s, { type: "shakeTap", playerId: "p1", taps: 9 }, deps, ctx).state;
    s = reduce(s, { type: "shakeTap", playerId: "p2", taps: 14 }, deps, ctx).state;
    clock.advance(TIEBREAKER_SHAKE_MS + 1);
    const erg = tick(s, deps, ctx);
    expect(erg.state.tiebreaker?.subphase).toBe("ergebnis");
    expect(erg.state.tiebreaker?.sieger).toBe("p1"); // 21 > 14
    expect(erg.events.some((e) => e.type === "tiebreaker_ergebnis" && e.sieger === "p1")).toBe(
      true,
    );
    // Ergebnis-Fenster vorbei ⇒ Siegerehrung: p1 VOR p2 trotz gleicher Balance.
    clock.advance(TIEBREAKER_ERGEBNIS_MS + 1);
    s = tick(erg.state, deps, ctx).state;
    expect(s.phase).toBe("siegerehrung");
    expect(s.siegerehrung?.platzierungen[0].playerId).toBe("p1");
    expect(s.siegerehrung?.platzierungen[1].playerId).toBe("p2");
    const award = s.siegerehrung?.awards.find((a) => a.titel.includes("Sudden-Death"));
    expect(award?.playerId).toBe("p1");
    expect(award?.wert).toContain("21");
  });

  it("Tap-Gleichstand ⇒ Re-Shake (Runde 2), nach 3 Runden entscheidet das Los", () => {
    let s = imShake();
    // Runde 1: beide 7 Taps — Re-Shake.
    s = reduce(s, { type: "shakeTap", playerId: "p1", taps: 7 }, deps, ctx).state;
    s = reduce(s, { type: "shakeTap", playerId: "p2", taps: 7 }, deps, ctx).state;
    clock.advance(TIEBREAKER_SHAKE_MS + 1);
    s = tick(s, deps, ctx).state;
    expect(s.tiebreaker?.subphase).toBe("countdown");
    expect(s.tiebreaker?.runde).toBe(2);
    expect(s.tiebreaker?.taps).toEqual({});
    // Runden 2 + 3: niemand tippt — nach Runde 3 MUSS ein Los-Sieger stehen.
    for (let runde = 2; runde <= 3; runde++) {
      clock.advance(TIEBREAKER_COUNTDOWN_MS + 1);
      s = tick(s, deps, ctx).state;
      clock.advance(TIEBREAKER_SHAKE_MS + 1);
      s = tick(s, deps, ctx).state;
    }
    expect(s.tiebreaker?.subphase).toBe("ergebnis");
    expect(["p1", "p2"]).toContain(s.tiebreaker?.sieger);
  });

  it("View: Taps sind ÖFFENTLICH (Drama!) — Screen sieht das Live-Duell", () => {
    let s = imShake();
    s = reduce(s, { type: "shakeTap", playerId: "p1", taps: 3 }, deps, ctx).state;
    const room = { roomCode: "TEST", joinUrl: "u", qrPath: "q", gmPin: "0000", gmLog: [] };
    const view = viewFor(s, "screen", deps, room, ctx) as {
      tiebreaker: { subphase: string; teilnehmer: { playerId: string; taps: number }[] } | null;
    };
    expect(view.tiebreaker?.subphase).toBe("shake");
    expect(view.tiebreaker?.teilnehmer.find((t) => t.playerId === "p1")?.taps).toBe(3);
  });
});

describe("highlights-Phase: Sequenz zwischen Plan-Ende und Siegerehrung", () => {
  const chronik: ChronikEintrag[] = [
    { art: "klau", dieb: "p1", opfer: "p2", betrag: 300, frageNr: 5 },
    { art: "jackpot", playerId: "p2", betrag: 500, frageNr: 9 },
  ];

  it("zeigt die Karten nacheinander (Tick) und endet in der Siegerehrung", () => {
    let s = naechsterAbschnitt(amPlanEnde({ p1: 900, p2: 500 }, chronik), deps, ctx).state;
    expect(s.phase).toBe("highlights");
    expect(s.highlights?.karten).toHaveLength(2);
    expect(s.highlights?.index).toBe(0);
    clock.advance(HIGHLIGHT_KARTE_MS + 1);
    s = tick(s, deps, ctx).state;
    expect(s.highlights?.index).toBe(1);
    clock.advance(HIGHLIGHT_KARTE_MS + 1);
    s = tick(s, deps, ctx).state;
    expect(s.phase).toBe("siegerehrung");
  });

  it("gm.next skippt Karte für Karte (skippable!)", () => {
    let s = naechsterAbschnitt(amPlanEnde({ p1: 900, p2: 500 }, chronik), deps, ctx).state;
    s = reduce(s, { type: "gm.next" }, deps, ctx).state;
    expect(s.phase).toBe("highlights");
    expect(s.highlights?.index).toBe(1);
    s = reduce(s, { type: "gm.next" }, deps, ctx).state;
    expect(s.phase).toBe("siegerehrung");
  });

  it("Punkte-Kommandos sind in tiebreaker + highlights tabu (Podest fixiert)", () => {
    const hl = naechsterAbschnitt(amPlanEnde({ p1: 900, p2: 500 }, chronik), deps, ctx).state;
    expect(
      reduce(hl, { type: "gm.scoreAdjust", playerId: "p1", delta: 100, grund: "x" }, deps, ctx)
        .error,
    ).toBe("podest-fixiert");
    const tb = naechsterAbschnitt(amPlanEnde({ p1: 800, p2: 800 }), deps, ctx).state;
    expect(
      reduce(tb, { type: "gm.scoreAdjust", playerId: "p1", delta: 100, grund: "x" }, deps, ctx)
        .error,
    ).toBe("podest-fixiert");
  });
});
