// Stinkbanane: Wander-Logik, verdeckter Zufalls-Timer (45–75 s), Explosions-
// Ökonomie (−500 ins Glas), Disconnect-Regeln, 2-Spieler-Ping-Pong und die
// statistische Fairness der Explosions-Verteilung über viele Seeds.
import { describe, expect, it } from "vitest";
import type { ContentSlice, Question } from "../../shared/content";
import { asPlayerId, type PlayerId } from "../../shared/ids";
import {
  SB_EXPLOSION_MM,
  SB_FRAGE_MS,
  SB_SPLATTER_MS,
  SB_WEITERGABE_MM,
  SB_ZUENDSCHNUR_MAX_MS,
  SB_ZUENDSCHNUR_MIN_MS,
} from "../../shared/minigames/stinkbanane.meta";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { PlayerAction } from "./_api/plugin";
import { stinkbananePlugin, type StinkbananeState } from "./stinkbanane/index";

const fragen: Question[] = [0, 1].map((i) => ({
  id: `q_sb_${i}`,
  kind: "choice4",
  category: "tiere",
  difficulty: "easy",
  text: `Frage ${i}?`,
  options: ["A", "B", "C", "D"],
  answer: 2,
  erklaerung: "C stimmt.",
}));

function setup(spielerIds: string[] = ["p1", "p2", "p3"], seed = 1) {
  const clock = createTestClock(0);
  const ctx = { clock, rng: createRng(seed) };
  const content: ContentSlice = { questions: fragen };
  const spieler = spielerIds.map(asPlayerId);
  const state = stinkbananePlugin.init(spieler, content, ctx) as StinkbananeState;
  return { clock, ctx, state, spieler };
}

function antwort(
  playerId: string,
  choice: number,
  atServerTime: number,
): PlayerAction<{ type: "answer"; choice: 0 | 1 | 2 | 3 }> {
  return {
    kind: "player",
    playerId: asPlayerId(playerId),
    action: { type: "answer", choice: choice as 0 | 1 | 2 | 3 },
    atServerTime,
  };
}

describe("stinkbanane: Start + Wander-Logik", () => {
  it("startet bei einem Zufallsspieler mit verdeckter Zündschnur in [45 s, 75 s]", () => {
    const { state, spieler } = setup();
    expect(spieler).toContain(state.holder);
    expect(state.zuendschnurEndetAt).toBeGreaterThanOrEqual(SB_ZUENDSCHNUR_MIN_MS);
    expect(state.zuendschnurEndetAt).toBeLessThanOrEqual(SB_ZUENDSCHNUR_MAX_MS);
    expect(state.frageEndsAt).toBe(SB_FRAGE_MS);
  });

  it("richtig = +150 MM und die Banane wandert im Kreis weiter (neue Frage)", () => {
    const { ctx, state } = setup();
    const halter = state.holder!;
    const s = stinkbananePlugin.reduce(state, antwort(halter, 2, 1_000), ctx) as StinkbananeState;
    expect(s.weitergaben[halter]).toBe(1);
    expect(s.holder).not.toBe(halter);
    expect(s.frageIndex).toBe(1);
    expect(s.historie.at(-1)).toMatchObject({ typ: "weitergabe", von: halter, zu: s.holder });
  });

  it("falsch = festhalten + neue Frage; Nicht-Halter-Antworten werden ignoriert", () => {
    const { ctx, state, spieler } = setup();
    const halter = state.holder!;
    const falsch = stinkbananePlugin.reduce(
      state,
      antwort(halter, 0, 1_000),
      ctx,
    ) as StinkbananeState;
    expect(falsch.holder).toBe(halter);
    expect(falsch.frageIndex).toBe(1);
    expect(falsch.weitergaben[halter]).toBeUndefined();

    const zuschauer = spieler.find((p) => p !== halter)!;
    const fremd = stinkbananePlugin.reduce(state, antwort(zuschauer, 2, 1_000), ctx);
    expect(fremd).toBe(state); // unverändert — kein Nicht-Halter-Input
  });

  it("zu langsam (8-s-Timeout im Tick) = festhalten + neue Frage", () => {
    const { clock, ctx, state } = setup();
    clock.advance(SB_FRAGE_MS + 1);
    const s = stinkbananePlugin.tick(state, ctx) as StinkbananeState;
    expect(s.holder).toBe(state.holder);
    expect(s.frageIndex).toBe(1);
    expect(s.historie.at(-1)?.typ).toBe("timeout");
  });
});

describe("stinkbanane: Explosion + Ökonomie", () => {
  it("Explosion: Halter −500 ins Glas + Matsch; nach 2 Durchgängen fertig (Goldens)", () => {
    const { clock, ctx, state } = setup();
    const halter1 = state.holder!;
    // Eine erfolgreiche Weitergabe vor der Explosion.
    let s = stinkbananePlugin.reduce(state, antwort(halter1, 2, 1_000), ctx) as StinkbananeState;
    const halter2 = s.holder!;
    // Durchgang 1 platzt:
    clock.advance(s.zuendschnurEndetAt + 1);
    s = stinkbananePlugin.tick(s, ctx) as StinkbananeState;
    expect(s.explodiert[halter2]).toBe(1);
    expect(s.matsch).toContain(halter2);
    expect(s.jackpotGlas).toBe(SB_EXPLOSION_MM);
    expect(s.phase).toBe("splatter");
    expect(stinkbananePlugin.isFinished(s)).toBe(false);
    // Splatter vorbei ⇒ Durchgang 2 mit frischer Zündschnur:
    clock.advance(SB_SPLATTER_MS + 1);
    s = stinkbananePlugin.tick(s, ctx) as StinkbananeState;
    expect(s.durchgang).toBe(2);
    expect(s.zuendschnurEndetAt).toBeGreaterThanOrEqual(
      ctx.clock.now() + SB_ZUENDSCHNUR_MIN_MS - 1,
    );
    const halter3 = s.holder!;
    // Durchgang 2 platzt ⇒ fertig:
    clock.advance(SB_ZUENDSCHNUR_MAX_MS + 1);
    s = stinkbananePlugin.tick(s, ctx) as StinkbananeState;
    expect(stinkbananePlugin.isFinished(s)).toBe(true);
    expect(s.jackpotGlas).toBe(2 * SB_EXPLOSION_MM);
    // Scores: Weitergaben × 150 − Explosionen × 500.
    const scores = stinkbananePlugin.scores(s);
    const erwartet: Record<string, number> = {};
    for (const p of s.players) {
      erwartet[p] =
        (s.weitergaben[p] ?? 0) * SB_WEITERGABE_MM - (s.explodiert[p] ?? 0) * SB_EXPLOSION_MM;
    }
    expect(scores).toEqual(erwartet);
    expect(scores[halter1]).toBeGreaterThanOrEqual(SB_WEITERGABE_MM - SB_EXPLOSION_MM);
    void halter3;
  });

  it("Antwort mit Server-Empfang VOR dem Explosions-Tick zählt noch, danach nicht", () => {
    const { ctx, state } = setup();
    const halter = state.holder!;
    // Frage-Timeouts bis kurz vor die Zündschnur spulen (frisches Frage-Fenster).
    const kurzVorher = state.zuendschnurEndetAt - 1;
    const s0: StinkbananeState = { ...state, frageEndsAt: state.zuendschnurEndetAt + 5_000 };
    const zaehlt = stinkbananePlugin.reduce(
      s0,
      antwort(halter, 2, kurzVorher),
      ctx,
    ) as StinkbananeState;
    expect(zaehlt.weitergaben[halter]).toBe(1);
    const zaehltNicht = stinkbananePlugin.reduce(
      s0,
      antwort(halter, 2, state.zuendschnurEndetAt),
      ctx,
    );
    expect(zaehltNicht).toBe(s0);
  });

  it("Fairness statistisch über 400 Seeds: Zündschnur gleichmäßig in [45 s, 75 s], Start-Halter gleichverteilt", () => {
    const seeds = 400;
    const spieler = ["p1", "p2", "p3", "p4"].map(asPlayerId);
    const halterZaehler = new Map<string, number>();
    const eimer = [0, 0, 0]; // 45–55 s, 55–65 s, 65–75 s
    let summe = 0;
    for (let seed = 1; seed <= seeds; seed++) {
      const ctx = { clock: createTestClock(0), rng: createRng(seed) };
      const s = stinkbananePlugin.init(spieler, { questions: fragen }, ctx) as StinkbananeState;
      halterZaehler.set(s.holder!, (halterZaehler.get(s.holder!) ?? 0) + 1);
      const dauer = s.zuendschnurEndetAt;
      expect(dauer).toBeGreaterThanOrEqual(SB_ZUENDSCHNUR_MIN_MS);
      expect(dauer).toBeLessThanOrEqual(SB_ZUENDSCHNUR_MAX_MS);
      summe += dauer;
      eimer[Math.min(2, Math.floor((dauer - SB_ZUENDSCHNUR_MIN_MS) / 10_000))]++;
    }
    // Mittelwert nahe 60 s (Gleichverteilung), jeder 10-s-Eimer trägt ~1/3.
    expect(summe / seeds).toBeGreaterThan(58_000);
    expect(summe / seeds).toBeLessThan(62_000);
    for (const anzahl of eimer) {
      expect(anzahl).toBeGreaterThan(seeds / 3 - seeds * 0.12);
      expect(anzahl).toBeLessThan(seeds / 3 + seeds * 0.12);
    }
    // Start-Halter: jeder der 4 Spieler in ±40 % um den Erwartungswert.
    for (const p of spieler) {
      const anzahl = halterZaehler.get(p) ?? 0;
      expect(anzahl).toBeGreaterThan((seeds / 4) * 0.6);
      expect(anzahl).toBeLessThan((seeds / 4) * 1.4);
    }
  });
});

describe("stinkbanane: Disconnect-Regeln + 2 Spieler", () => {
  it("Halter-Disconnect: Banane wandert automatisch weiter, KEINE Strafe, kein +150", () => {
    const { ctx, state } = setup();
    const halter = state.holder!;
    const s = stinkbananePlugin.onDisconnect(state, halter, ctx) as StinkbananeState;
    expect(s.holder).not.toBe(halter);
    expect(s.holder).not.toBeNull();
    expect(s.weitergaben[halter]).toBeUndefined();
    expect(stinkbananePlugin.scores(s)[halter]).toBe(0);
  });

  it("alle offline: Banane liegt am Boden, Explosion trifft NIEMANDEN; Rückkehrer nimmt sie auf", () => {
    const { clock, ctx, state, spieler } = setup();
    let s = state;
    for (const p of spieler) s = stinkbananePlugin.onDisconnect(s, p, ctx) as StinkbananeState;
    expect(s.holder).toBeNull();
    clock.advance(SB_ZUENDSCHNUR_MAX_MS + 1);
    s = stinkbananePlugin.tick(s, ctx) as StinkbananeState;
    expect(s.jackpotGlas).toBe(0); // keine Strafe
    expect(Object.keys(s.explodiert)).toHaveLength(0);
    s = stinkbananePlugin.onReconnect(s, spieler[1], ctx) as StinkbananeState;
    if (s.phase === "ticken") expect(s.holder).toBe(spieler[1]);
  });

  it("2 Spieler: Ping-Pong funktioniert", () => {
    const { ctx, state } = setup(["a", "b"]);
    const erster = state.holder!;
    const zweiter = erster === "a" ? "b" : "a";
    let s = stinkbananePlugin.reduce(state, antwort(erster, 2, 500), ctx) as StinkbananeState;
    expect(s.holder).toBe(zweiter);
    s = stinkbananePlugin.reduce(s, antwort(zweiter, 2, 1_500), ctx) as StinkbananeState;
    expect(s.holder).toBe(erster);
  });
});

describe("stinkbanane: Leak-Schutz + Vertrag", () => {
  it("der Explosions-Zeitpunkt verlässt den Server NIE Richtung Screen/Player", () => {
    const { state, spieler } = setup();
    const screenView = JSON.stringify(stinkbananePlugin.viewFor(state, "screen"));
    const playerView = JSON.stringify(stinkbananePlugin.viewFor(state, "player", spieler[0]));
    expect(screenView).not.toContain("zuendschnur");
    expect(playerView).not.toContain("zuendschnur");
    const gmView = stinkbananePlugin.viewFor(state, "gm") as { zuendschnurEndetAt: number };
    expect(gmView.zuendschnurEndetAt).toBe(state.zuendschnurEndetAt);
  });

  it("NUR der Halter sieht die Frage (Design-Regel)", () => {
    const { state, spieler } = setup();
    const halter = state.holder as PlayerId;
    const zuschauer = spieler.find((p) => p !== halter)!;
    const halterView = stinkbananePlugin.viewFor(state, "player", halter) as {
      frage: unknown;
      istHalter: boolean;
    };
    const zuschauerView = stinkbananePlugin.viewFor(state, "player", zuschauer) as {
      frage: unknown;
      istHalter: boolean;
    };
    expect(halterView.istHalter).toBe(true);
    expect(halterView.frage).not.toBeNull();
    expect(zuschauerView.frage).toBeNull();
    // Auch der Fragen-TEXT darf bei Zuschauern/Screen nicht auftauchen.
    expect(JSON.stringify(zuschauerView)).not.toContain(fragen[0].text);
    expect(JSON.stringify(stinkbananePlugin.viewFor(state, "screen"))).not.toContain(
      fragen[0].text,
    );
  });

  it("hält den State JSON-serialisierbar (Contract-Grundlage)", () => {
    const { ctx, state } = setup();
    const s = stinkbananePlugin.reduce(state, antwort(state.holder!, 2, 800), ctx);
    const kopie = JSON.parse(JSON.stringify(s)) as StinkbananeState;
    expect(stinkbananePlugin.scores(kopie)).toEqual(stinkbananePlugin.scores(s));
  });
});

describe("stinkbanane: Maßanzug (mods.fragenProSpieler — Befund-Fix)", () => {
  /** Startspieler ist seed-deterministisch: erst schauen, wer die Banane kriegt. */
  function setupMitZuweisung(eigene: Question) {
    const wer = setup().state.holder!;
    const clock = createTestClock(0);
    const ctx = { clock, rng: createRng(1) };
    const content: ContentSlice = {
      questions: fragen,
      mods: { fragenProSpieler: { [wer]: eigene } },
    };
    const spieler = ["p1", "p2", "p3"].map(asPlayerId);
    const state = stinkbananePlugin.init(spieler, content, ctx) as StinkbananeState;
    return { wer, clock, ctx, state };
  }

  it("Halter mit Zuweisung kriegt SEINE Frage — nach der Antwort ist sie verbraucht", () => {
    const eigene: Question = { ...fragen[0], id: "q_eigen", text: "Eigene Frage?", answer: 0 };
    const { wer, ctx, state } = setupMitZuweisung(eigene);
    expect(state.holder).toBe(wer);
    // Das Handy des Halters zeigt die EIGENE Frage:
    const view = stinkbananePlugin.viewFor(state, "player", wer) as {
      frage: { text: string } | null;
    };
    expect(view.frage?.text).toBe("Eigene Frage?");
    // Antwort 0 ist an der EIGENEN Frage richtig (Basis-Fragen: answer 2):
    const s = stinkbananePlugin.reduce(state, antwort(wer, 0, 1_000), ctx) as StinkbananeState;
    expect(s.weitergaben[wer]).toBe(1); // als richtig gewertet ⇒ Banane wandert
    expect(s.fragenProSpieler[wer]).toBeUndefined(); // Zuweisung verbraucht
  });

  it("Timeout verbraucht die zugewiesene Frage ebenfalls (kein Dauer-Maßanzug)", () => {
    const eigene: Question = { ...fragen[0], id: "q_eigen", answer: 0 };
    const { wer, clock, ctx, state } = setupMitZuweisung(eigene);
    clock.advance(SB_FRAGE_MS + 1); // 8-s-Fenster verpasst
    const s = stinkbananePlugin.tick(state, ctx) as StinkbananeState;
    expect(s.historie.at(-1)?.typ).toBe("timeout");
    expect(s.fragenProSpieler[wer]).toBeUndefined();
  });
});
