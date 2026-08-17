// Team-Modus „Affenbanden" in der ENGINE (GAME-DESIGN §1.4): Team-Bildung beim
// Match-Start (Wünsche + Stärke), teamWahl/gm.teamAssign in der Lobby, das
// Buzz-pro-Team-Gate (nur EIN Buzz pro Team zählt), team-bezogene Underdog-
// Ziele, Team-Sudden-Death und die Siegerehrung mit AT-Team-Bonus für ALLE
// Mitglieder des Sieger-Teams.
import { beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { atFuerEndstand } from "../../shared/economy";
import { createRng } from "../../shared/rng";
import { defaultSettings, type MatchSettings } from "../../shared/settings";
import { createTestClock } from "../../shared/time";
import type { MinigamePlugin } from "../minigames/_api/plugin";
import { vierLianenPlugin } from "../minigames/vier-lianen/index";
import { createInitialState, reduce } from "./engine";
import { letzterSpieler, naechsterAbschnitt, type EngineDeps } from "./flow";
import type { EngineState } from "./types";

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

/** Mock-Buzzer: protokolliert JEDE angenommene Aktion (Gate-Nachweis). */
const mockBuzzer: MinigamePlugin<{ log: string[] }, { type: string }> = {
  meta: {
    id: "mock-buzzer",
    name: "Mock-Buzzer",
    minPlayers: 2,
    maxPlayers: 8,
    formats: ["buzzer"],
    contentKind: "quiz",
  },
  init: () => ({ log: [] }),
  reduce: (state, action) =>
    action.kind === "player"
      ? { log: [...state.log, `${action.playerId}:${action.action.type}`] }
      : state,
  tick: (state) => state,
  onDisconnect: (state) => state,
  onReconnect: (state) => state,
  viewFor: () => ({}),
  isFinished: () => false,
  scores: () => ({}),
};

let clock: ReturnType<typeof createTestClock>;
let ctx: { clock: typeof clock; rng: ReturnType<typeof createRng> };
const deps: EngineDeps = {
  getPlugin: (id) => (id === "mock-buzzer" ? (mockBuzzer as never) : vierLianenPlugin),
};

beforeEach(() => {
  clock = createTestClock(1_000_000);
  ctx = { clock, rng: createRng(42) };
});

/** Lobby mit N Spielern (2er-Team-Setting) — optional mit Team-Wünschen. */
function lobby(
  spieler: string[],
  settings?: Partial<MatchSettings>,
  wuensche?: Record<string, string>,
): EngineState {
  let s = createInitialState({
    ...defaultSettings("quick"),
    autoGm: false,
    teams: "2er",
    ...settings,
  });
  const farben = ["gelb", "rot", "blau", "gruen", "lila", "orange", "tuerkis", "pink"] as const;
  spieler.forEach((pid, i) => {
    s = reduce(s, { type: "join", playerId: pid, name: pid, avatar: farben[i] }, deps, ctx).state;
  });
  for (const [pid, team] of Object.entries(wuensche ?? {})) {
    s = reduce(s, { type: "teamWahl", playerId: pid, team }, deps, ctx).state;
  }
  return s;
}

/** Match starten (Fragen-Pool 30) — gibt State + Events zurück. */
function starte(s: EngineState, staerke?: Record<string, number>) {
  return reduce(
    s,
    {
      type: "start",
      matchId: "m_teams",
      fragenPool: Array.from({ length: 30 }, (_, i) => frage(`q${i + 1}`)),
      verfuegbareMinigames: ["vier-lianen"],
      staerke,
    },
    deps,
    ctx,
  );
}

/** Gestartetes Team-Match ans PLAN-ENDE spulen (Balances überschreiben). */
function amPlanEnde(balances: Record<string, number>): EngineState {
  const wuensche = { p1: "banane", p2: "banane", p3: "kokos", p4: "kokos" };
  const s0 = lobby(Object.keys(balances), {}, wuensche);
  const s = starte(s0).state;
  const players = { ...s.players };
  for (const [pid, balance] of Object.entries(balances)) {
    players[pid] = { ...players[pid], balance };
  }
  return { ...s, players, abschnittIndex: (s.plan?.abschnitte.length ?? 1) - 1 };
}

describe("Team-Bildung beim Match-Start", () => {
  it("teams=2er + 4 Spieler: Aufstellung + teams_gebildet-Event + Moment", () => {
    const r = starte(lobby(["p1", "p2", "p3", "p4"]));
    expect(r.state.teams).not.toBeNull();
    expect(r.state.teams?.teams).toHaveLength(2);
    expect(Object.keys(r.state.teams?.zuordnung ?? {}).sort()).toEqual(["p1", "p2", "p3", "p4"]);
    expect(r.state.teams?.doppelAffe).toBeNull();
    const ev = r.events.find((e) => e.type === "teams_gebildet");
    expect(ev).toBeDefined();
    expect(r.state.momente.some((m) => m.text.includes("AFFENBANDEN"))).toBe(true);
  });

  it("teams=aus: Match startet individuell (teams=null)", () => {
    const r = starte(lobby(["p1", "p2", "p3", "p4"], { teams: "aus" }));
    expect(r.state.teams).toBeNull();
  });

  it("unter 4 Spielern startet das Match individuell — trotz teams=2er", () => {
    const r = starte(lobby(["p1", "p2", "p3"]));
    expect(r.state.teams).toBeNull();
  });

  it("5 Spieler: Doppel-Affe wird gesetzt + eigener Moment auf dem Screen", () => {
    const r = starte(lobby(["p1", "p2", "p3", "p4", "p5"]));
    expect(r.state.teams?.doppelAffe).not.toBeNull();
    expect(r.state.momente.some((m) => m.text.includes("Doppel-Affe"))).toBe(true);
  });

  it("Lobby-Wünsche werden bei der Bildung respektiert", () => {
    const r = starte(
      lobby(["p1", "p2", "p3", "p4"], {}, { p1: "kokos", p2: "kokos", p3: "banane" }),
    );
    expect(r.state.teams?.zuordnung.p1).toBe("kokos");
    expect(r.state.teams?.zuordnung.p2).toBe("kokos");
    expect(r.state.teams?.zuordnung.p3).toBe("banane");
    expect(r.state.teams?.zuordnung.p4).toBe("banane");
  });
});

describe("teamWahl (Lobby) + gm.teamAssign", () => {
  it("Spieler-Wahl speichert den Wunsch und feuert team_wahl", () => {
    const s = lobby(["p1", "p2", "p3", "p4"]);
    const r = reduce(s, { type: "teamWahl", playerId: "p1", team: "kokos" }, deps, ctx);
    expect(r.state.teamWuensche.p1).toBe("kokos");
    expect(r.events).toContainEqual({ type: "team_wahl", playerId: "p1", team: "kokos" });
  });

  it("teams=aus ⇒ Fehler; unbekanntes Team ⇒ Fehler; nur in der Lobby", () => {
    const aus = lobby(["p1", "p2", "p3", "p4"], { teams: "aus" });
    expect(reduce(aus, { type: "teamWahl", playerId: "p1", team: "banane" }, deps, ctx).error).toBe(
      "teams-aus",
    );
    const s = lobby(["p1", "p2", "p3", "p4"]);
    expect(reduce(s, { type: "teamWahl", playerId: "p1", team: "gold" }, deps, ctx).error).toBe(
      "unbekanntes-team",
    );
    const gestartet = starte(s).state;
    expect(
      reduce(gestartet, { type: "teamWahl", playerId: "p1", team: "banane" }, deps, ctx).error,
    ).toBe("nur-in-lobby");
  });

  it("gm.teamAssign setzt den Wunsch, team=null löscht ihn wieder", () => {
    const s = lobby(["p1", "p2", "p3", "p4"]);
    const r1 = reduce(s, { type: "gm.teamAssign", playerId: "p1", team: "kokos" }, deps, ctx);
    expect(r1.state.teamWuensche.p1).toBe("kokos");
    const r2 = reduce(r1.state, { type: "gm.teamAssign", playerId: "p1", team: null }, deps, ctx);
    expect(r2.state.teamWuensche.p1).toBeUndefined();
    expect(
      reduce(s, { type: "gm.teamAssign", playerId: "p1", team: "gold" }, deps, ctx).error,
    ).toBe("unbekanntes-team");
  });
});

describe("Buzzer-Regel: nur EIN Buzz pro Team zählt (§1.4)", () => {
  /** Team-Match in einer Mock-Buzzer-Frage: banane={p1,p2}, kokos={p3,p4}. */
  function inBuzzerFrage(): EngineState {
    const s = starte(
      lobby(["p1", "p2", "p3", "p4"], {}, { p1: "banane", p2: "banane", p3: "kokos" }),
    ).state;
    return {
      ...s,
      phase: "frage",
      minigameId: "mock-buzzer",
      minigameState: { log: [] },
    };
  }
  const buzz = (s: EngineState, playerId: string) =>
    reduce(
      s,
      {
        type: "playerAction",
        playerId,
        minigameId: "mock-buzzer",
        action: { type: "buzz", finalAt: 1 },
        atServerTime: clock.now(),
      },
      deps,
      ctx,
    );

  it("der erste Team-Buzzer belegt den Slot — der Kollege wird abgelehnt", () => {
    const s = inBuzzerFrage();
    const r1 = buzz(s, "p1");
    expect(r1.error).toBeUndefined();
    expect(r1.state.teams?.buzzVonTeam.banane).toBe("p1");
    const r2 = buzz(r1.state, "p2");
    expect(r2.error).toBe("team-hat-gebuzzt");
    expect((r2.state.minigameState as { log: string[] }).log).toEqual(["p1:buzz"]);
  });

  it("das GEGNER-Team darf weiterhin buzzen (1 Slot PRO Team)", () => {
    let s = buzz(inBuzzerFrage(), "p1").state;
    const r = buzz(s, "p3");
    expect(r.error).toBeUndefined();
    s = r.state;
    expect(s.teams?.buzzVonTeam).toEqual({ banane: "p1", kokos: "p3" });
  });

  it("der Team-Buzzer selbst darf erneut senden (Retry-Pfad bleibt offen)", () => {
    const s = buzz(inBuzzerFrage(), "p1").state;
    expect(buzz(s, "p1").error).toBeUndefined();
  });

  it("Nicht-Buzz-Aktionen (answer) passieren das Gate — MC bleibt individuell", () => {
    const s = inBuzzerFrage();
    const answer = (st: EngineState, playerId: string) =>
      reduce(
        st,
        {
          type: "playerAction",
          playerId,
          minigameId: "mock-buzzer",
          action: { type: "answer", choice: 1 },
          atServerTime: clock.now(),
        },
        deps,
        ctx,
      );
    const r = answer(answer(s, "p1").state, "p2");
    expect(r.error).toBeUndefined();
    expect((r.state.minigameState as { log: string[] }).log).toEqual(["p1:answer", "p2:answer"]);
  });
});

describe("Underdog team-bezogen: letzterSpieler = schwächster Affe des LETZTEN Teams", () => {
  it("zielt aufs letzte TEAM, nicht auf den global ärmsten Spieler", () => {
    // banane={p1:50, p2:2000} (Topf 2050) · kokos={p3:300, p4:400} (Topf 700).
    // Global ärmster ist p1 — aber das LETZTE Team ist kokos ⇒ p3.
    const s = amPlanEnde({ p1: 50, p2: 2000, p3: 300, p4: 400 });
    expect(letzterSpieler(s)).toBe("p3");
  });
});

describe("Plan-Ende: Team-Sudden-Death + Siegerehrung mit AT-Team-Bonus", () => {
  it("Topf-Gleichstand an der Spitze ⇒ Shake mit ALLEN Mitgliedern der Teams", () => {
    const s = amPlanEnde({ p1: 500, p2: 300, p3: 400, p4: 400 }); // 800 vs 800
    const r = naechsterAbschnitt(s, deps, ctx);
    expect(r.state.phase).toBe("tiebreaker");
    expect(r.state.tiebreaker?.teilnehmer.sort()).toEqual(["p1", "p2", "p3", "p4"]);
    expect(r.state.tiebreaker?.betrag).toBe(800);
  });

  it("Individual-Gleichstand OHNE Team-Gleichstand zündet KEINEN Shake", () => {
    const s = amPlanEnde({ p1: 500, p2: 500, p3: 499, p4: 400 }); // 1000 vs 899
    const r = naechsterAbschnitt(s, deps, ctx);
    expect(r.state.phase).toBe("siegerehrung");
  });

  it("Siegerehrung: teamPlatzierungen + team_ergebnis-Event (Ranking nach Topf)", () => {
    const s = amPlanEnde({ p1: 100, p2: 200, p3: 900, p4: 100 }); // 300 vs 1000
    const r = naechsterAbschnitt(s, deps, ctx);
    expect(r.state.phase).toBe("siegerehrung");
    const tp = r.state.siegerehrung?.teamPlatzierungen;
    expect(tp?.map((t) => t.teamId)).toEqual(["kokos", "banane"]);
    expect(tp?.map((t) => t.topf)).toEqual([1000, 300]);
    expect(r.events.some((e) => e.type === "team_ergebnis")).toBe(true);
  });

  it("AT-Team-Bonus: ALLE Mitglieder des Sieger-Teams — auch der Letzte", () => {
    // kokos gewinnt (1000 > 300): p4 ist individuell LETZTER, kriegt aber den
    // Sieger-Bonus; p2 ist individuell ZWEITER, kriegt ihn NICHT (banane).
    const s = amPlanEnde({ p1: 100, p2: 200, p3: 900, p4: 100 });
    const sg = naechsterAbschnitt(s, deps, ctx).state.siegerehrung;
    const at = (pid: string) => sg?.platzierungen.find((p) => p.playerId === pid)?.at;
    expect(at("p4")).toBe(atFuerEndstand(100, true));
    expect(at("p3")).toBe(atFuerEndstand(900, true));
    expect(at("p2")).toBe(atFuerEndstand(200, false));
    expect(at("p1")).toBe(atFuerEndstand(100, false));
    expect(atFuerEndstand(100, true)).toBeGreaterThan(atFuerEndstand(100, false));
  });

  it("Award Bester Einzel-Affe ehrt die beste PERSÖNLICHE Leistung", () => {
    const s = amPlanEnde({ p1: 100, p2: 1200, p3: 900, p4: 800 }); // banane 1300 < kokos 1700
    const sg = naechsterAbschnitt(s, deps, ctx).state.siegerehrung;
    const award = sg?.awards.find((a) => a.titel.includes("Bester Einzel-Affe"));
    expect(award?.playerId).toBe("p2"); // Verlierer-Team, aber solo der Beste
  });
});
