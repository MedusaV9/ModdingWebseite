// Wächter: Auto-GM-+10s-Heuristik (engine.tick) — Daten kommen weiter aus
// endsAt+answeredCount im Screen-View, aber meta.autoVerlaengerung === false
// ist jetzt das EXPLIZITE Opt-out (Playtest-1-Befund 3: das Duck-Typing auf
// View-Feldnamen allein war fragil — der Blitz-DJ tappte hinein, bis
// answeredCount in buzzCount umbenannt wurde; der Rename bleibt bestehen,
// zusätzlich schützt jetzt das Meta-Flag).
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import type { PlayerId } from "../../shared/ids";
import { AOB_REVEAL_MS, AOB_SETZEN_MS } from "../../shared/minigames/alles-oder-banane.meta";
import { SONG_SNIPPET_META } from "../../shared/minigames/song-snippet.meta";
import { createRng } from "../../shared/rng";
import { defaultSettings } from "../../shared/settings";
import { createTestClock } from "../../shared/time";
import type { Ctx, MinigamePlugin } from "../minigames/_api/plugin";
import { allesOderBananePlugin, type AllesOderBananeState } from "../minigames/alles-oder-banane";
import { createInitialState, reduce, tick, type EngineDeps } from "./engine";
import { starteFrage } from "./flow";
import type { Abschnitt, EngineState } from "./types";

const frage = (id: string): Question => ({
  id,
  kind: "choice4",
  category: "affen",
  difficulty: "easy",
  text: `Frage ${id}?`,
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: "Weil A.",
});

interface FakeState {
  endetAt: number;
  verlaengert: number;
  fertig: boolean;
}

/** Frage-Format-Attrappe: exponiert endsAt + answeredCount=0 (niemand hat
 * geantwortet) — der klassische Fall, in dem der Auto-GM verlängern SOLL.
 * viewExtra mischt additive View-Signale dazu (z. B. eingabeOffen). */
function fakePlugin(
  metaExtra: {
    autoVerlaengerung?: boolean;
  },
  viewExtra: Record<string, unknown> = {},
): MinigamePlugin<FakeState, { type: "noop" }> {
  return {
    meta: {
      id: "vier-lianen",
      name: "Auto-GM-Attrappe",
      minPlayers: 2,
      maxPlayers: 8,
      formats: ["buttons"],
      contentKind: "quiz",
      ...metaExtra,
    },
    init: (_players: PlayerId[], _content: ContentSlice, ctx: Ctx) => ({
      endetAt: ctx.clock.now() + 15_000,
      verlaengert: 0,
      fertig: false,
    }),
    reduce: (s, action) =>
      action.kind === "gm" && action.type === "timer.extend"
        ? { ...s, endetAt: s.endetAt + action.ms, verlaengert: s.verlaengert + 1 }
        : s,
    tick: (s, ctx) => (ctx.clock.now() >= s.endetAt ? { ...s, fertig: true } : s),
    onDisconnect: (s) => s,
    onReconnect: (s) => s,
    viewFor: (s) => ({ endsAt: s.endetAt, answeredCount: 0, ...viewExtra }),
    isFinished: (s) => s.fertig,
    scores: () => ({}),
  };
}

function inFrage(deps: EngineDeps, ctx: Ctx): EngineState {
  let s = createInitialState({ ...defaultSettings("quick"), autoGm: true });
  s = reduce(s, { type: "join", playerId: "p1", name: "Anna", avatar: "gelb" }, deps, ctx).state;
  s = reduce(s, { type: "join", playerId: "p2", name: "Ben", avatar: "rot" }, deps, ctx).state;
  s = reduce(
    s,
    {
      type: "start",
      matchId: "m",
      fragenPool: Array.from({ length: 30 }, (_, i) => frage(`q${i + 1}`)),
      verfuegbareMinigames: ["vier-lianen"],
    },
    deps,
    ctx,
  ).state;
  const erster = s.plan!.abschnitte.findIndex((a: Abschnitt) => a.typ === "runde");
  return starteFrage({ ...s, abschnittIndex: erster }, deps, ctx).state;
}

describe("Auto-GM-+10s: explizites meta.autoVerlaengerung-Opt-out", () => {
  it("Default (Flag fehlt): <50 % geantwortet + <4 s übrig ⇒ einmalig +10 s", () => {
    const clock = createTestClock(1_000_000);
    const ctx = { clock, rng: createRng(7) };
    const deps: EngineDeps = { getPlugin: () => fakePlugin({}) };
    let s = inFrage(deps, ctx);

    clock.advance(12_000); // 3 s Rest < 4-s-Schwelle
    const r = tick(s, deps, ctx);
    s = r.state;
    expect(r.events.some((e) => e.type === "timer_extended")).toBe(true);
    expect(s.gm.autoTimerVerlaengert).toBe(true);
    expect((s.minigameState as FakeState).verlaengert).toBe(1);
    // Einmal pro Frage: der nächste knappe Moment verlängert NICHT nochmal.
    clock.advance(10_000);
    expect((tick(s, deps, ctx).state.minigameState as FakeState).verlaengert).toBe(1);
  });

  it("meta.autoVerlaengerung: false ⇒ KEINE Verlängerung trotz passender View-Felder", () => {
    const clock = createTestClock(1_000_000);
    const ctx = { clock, rng: createRng(7) };
    const deps: EngineDeps = { getPlugin: () => fakePlugin({ autoVerlaengerung: false }) };
    let s = inFrage(deps, ctx);

    clock.advance(12_000);
    const r = tick(s, deps, ctx);
    s = r.state;
    expect(r.events.some((e) => e.type === "timer_extended")).toBe(false);
    expect(s.gm.autoTimerVerlaengert).toBe(false);
    expect((s.minigameState as FakeState).verlaengert).toBe(0);
    // Die Frage läuft normal aus (Plugin-tick beendet sie selbst).
    clock.advance(3_500);
    expect(tick(s, deps, ctx).state.phase).toBe("aufloesung");
  });

  it("Blitz-DJ deklariert das Opt-out im Meta (zusätzlich zum buzzCount-Rename)", () => {
    expect(SONG_SNIPPET_META.autoVerlaengerung).toBe(false);
  });
});

// ---------- P1-Fix (Eval 1): input-lose Sub-Phasen melden eingabeOffen=false ----------

describe("Auto-GM-+10s: view.eingabeOffen-Signal (input-lose Sub-Phasen)", () => {
  it("eingabeOffen: false ⇒ KEINE Verlängerung trotz endsAt+answeredCount", () => {
    const clock = createTestClock(1_000_000);
    const ctx = { clock, rng: createRng(7) };
    const deps: EngineDeps = { getPlugin: () => fakePlugin({}, { eingabeOffen: false }) };
    let s = inFrage(deps, ctx);

    clock.advance(12_000); // 3 s Rest < 4-s-Schwelle
    const r = tick(s, deps, ctx);
    s = r.state;
    expect(r.events.some((e) => e.type === "timer_extended")).toBe(false);
    expect((s.minigameState as FakeState).verlaengert).toBe(0);
  });

  it("eingabeOffen: true ⇒ Alt-Verhalten (Verlängerung greift)", () => {
    const clock = createTestClock(1_000_000);
    const ctx = { clock, rng: createRng(7) };
    const deps: EngineDeps = { getPlugin: () => fakePlugin({}, { eingabeOffen: true }) };
    let s = inFrage(deps, ctx);

    clock.advance(12_000);
    const r = tick(s, deps, ctx);
    s = r.state;
    expect(r.events.some((e) => e.type === "timer_extended")).toBe(true);
    expect((s.minigameState as FakeState).verlaengert).toBe(1);
  });

  it("AOB: Setzen/Reveal ohne Dead-Air (Reveal EXAKT 6 s trotz Auto-GM), Frage-Fenster verlängert weiter", () => {
    const clock = createTestClock(2_000_000);
    const ctx = { clock, rng: createRng(11) };
    const deps: EngineDeps = { getPlugin: () => allesOderBananePlugin as never };
    let s = inFrage(deps, ctx);

    // ---------- Phase SETZEN (12 s): knapper Moment ⇒ KEINE +10 s ----------
    let mg = s.minigameState as AllesOderBananeState;
    expect(mg.phase).toBe("setzen");
    expect(
      (allesOderBananePlugin.viewFor(mg, "screen") as { eingabeOffen: boolean }).eingabeOffen,
    ).toBe(false);
    clock.advance(AOB_SETZEN_MS - 1_000); // 1 s Rest < 4-s-Schwelle
    let r = tick(s, deps, ctx);
    s = r.state;
    expect(r.events.some((e) => e.type === "timer_extended")).toBe(false);

    // Setzen läuft regulär aus ⇒ Reveal beginnt (Auto-Minimum für alle).
    clock.advance(1_000);
    s = tick(s, deps, ctx).state;
    mg = s.minigameState as AllesOderBananeState;
    expect(mg.phase).toBe("reveal");
    const revealStart = clock.now();
    expect(
      (allesOderBananePlugin.viewFor(mg, "screen") as { eingabeOffen: boolean }).eingabeOffen,
    ).toBe(false);

    // ---------- Phase REVEAL (6 s): knapper Moment ⇒ KEINE +10 s ----------
    clock.advance(AOB_REVEAL_MS - 2_000); // 2 s Rest < 4-s-Schwelle
    r = tick(s, deps, ctx);
    s = r.state;
    expect(r.events.some((e) => e.type === "timer_extended")).toBe(false);
    expect((s.minigameState as AllesOderBananeState).phase).toBe("reveal");

    // Reveal endet PÜNKTLICH nach AOB_REVEAL_MS — das war der 16-s-Dead-Air-Bug.
    clock.advance(2_000);
    s = tick(s, deps, ctx).state;
    mg = s.minigameState as AllesOderBananeState;
    expect(mg.phase).toBe("frage");
    expect(clock.now() - revealStart).toBe(AOB_REVEAL_MS);

    // ---------- Phase FRAGE: antwortbar ⇒ Heuristik greift WEITER ----------
    expect(
      (allesOderBananePlugin.viewFor(mg, "screen") as { eingabeOffen: boolean }).eingabeOffen,
    ).toBe(true);
    clock.advance(mg.timerMs - 3_000); // 3 s Rest, niemand hat geantwortet
    r = tick(s, deps, ctx);
    s = r.state;
    expect(r.events.some((e) => e.type === "timer_extended")).toBe(true);
    expect(s.gm.autoTimerVerlaengert).toBe(true);
  });
});
