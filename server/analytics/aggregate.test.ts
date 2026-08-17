// Aggregation: synthetisches Event-Log → 15er-Stats + Fragen-Gesundheit.
// Der Kern (wendeMatchAn) ist pur; der Aggregator-Job wird gegen echte
// JSONL-Dateien im tmp-Verzeichnis getestet (genau-einmal-Garantie).
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createFileStorage } from "../persistence/storage";
import {
  createAggregator,
  leereAggregate,
  parseZeilen,
  wendeMatchAn,
  type LogZeile,
} from "./aggregate";

const T0 = 1_000_000;

function zeile(type: string, patch: Partial<LogZeile> = {}): LogZeile {
  return { v: 1, ts: T0, matchId: "m_1", seq: 0, type, payload: {}, ...patch };
}

/** Mini-Match: 2 Spieler (p1 mit Profil), 2 Fragen, p1 gewinnt. */
function miniMatch(): LogZeile[] {
  return [
    zeile("player_joined", { actor: "p1", payload: { name: "Anna" } }),
    zeile("player_joined", { actor: "p2", payload: { name: "Ben" } }),
    zeile("profile_bound", { actor: "p1", payload: { profileId: "pr_anna" } }),
    zeile("match_started", { payload: { modus: "quick" } }),
    zeile("runde_gestartet", { payload: { slot: "opener", minigameId: "vier-lianen" } }),
    // Frage 1: p1 schnell + richtig (1,2 s), p2 falsch.
    zeile("question_shown", { questionId: "q1", ts: T0 + 1000 }),
    zeile("answer_submitted", { actor: "p1", ts: T0 + 2200 }),
    zeile("answer_submitted", { actor: "p2", ts: T0 + 4000 }),
    zeile("answer_judged", {
      actor: "p1",
      questionId: "q1",
      payload: { correct: true, delta: 100 },
    }),
    zeile("answer_judged", {
      actor: "p2",
      questionId: "q1",
      payload: { correct: false, delta: 0 },
    }),
    // Frage 2 (RISIKO-Slot): p1 nutzt Joker, wieder richtig ⇒ Wette gewonnen.
    zeile("runde_gestartet", { payload: { slot: "risiko", minigameId: "vier-lianen" } }),
    zeile("question_shown", { questionId: "q2", ts: T0 + 10_000 }),
    zeile("joker_used", { actor: "p1", payload: { jokerId: "schmiergeld" } }),
    zeile("answer_submitted", { actor: "p1", ts: T0 + 15_000 }),
    zeile("answer_judged", {
      actor: "p1",
      questionId: "q2",
      payload: { correct: true, delta: 400 },
    }),
    // Finale-Marker: Mitleids-Banane — p2 führt VOR dem Finale.
    zeile("money_changed", { actor: "p1", payload: { delta: 0, balance: 500 } }),
    zeile("money_changed", {
      actor: "p2",
      payload: { delta: 300, balance: 800, grund: "mitleids-banane" },
    }),
    zeile("feedback_given", { actor: "p1", payload: { text: "Mehr Bananen!" } }),
    zeile("match_ended", {
      payload: {
        standings: [
          { playerId: "p1", balance: 1200 },
          { playerId: "p2", balance: 800 },
        ],
      },
    }),
  ];
}

describe("analytics: wendeMatchAn (pur)", () => {
  it("baut die Spieler-Stats aus dem Log (nur gebundene Profile)", () => {
    const agg = leereAggregate();
    wendeMatchAn(agg, miniMatch(), () => ({ kategorie: "affen", schwierigkeit: "easy" }));

    expect(Object.keys(agg.profile)).toEqual(["pr_anna"]); // Gast p2 zählt nicht
    const p = agg.profile.pr_anna;
    expect(p.beantwortet).toBe(2);
    expect(p.richtig).toBe(2);
    expect(p.matrix["affen|easy"]).toEqual({ n: 2, richtig: 2 });
    expect(p.schnellsteAntwortMs).toBe(1200);
    expect(p.schnelleAntworten).toBe(1); // nur die 1,2-s-Antwort war < 2,5 s
    expect(p.matches).toBe(1);
    expect(p.siege).toBe(1);
    expect(p.atLifetime).toBe(180); // 1200/10 = 120 ⇒ Sieger ×1,5
    expect(p.besterEndstand).toBe(1200);
    expect(p.aktuelleSerie).toBe(2);
    expect(p.mitJoker).toEqual({ n: 1, richtig: 1 });
    expect(p.ohneJoker).toEqual({ n: 1, richtig: 1 });
    expect(p.wettenGewonnen).toBe(1); // RISIKO-Slot
    expect(p.groessterWettgewinn).toBe(400);
    // Comeback: p2 führte vor dem Finale ⇒ p1s Sieg zählt als Comeback.
    expect(p.comebackMatches).toBe(1);
    expect(p.comebackSiege).toBe(1);
  });

  it("baut die Fragen-Gesundheit (Ausspielungen, Quote, Tipp-Käufe)", () => {
    const agg = leereAggregate();
    wendeMatchAn(agg, miniMatch(), () => null);
    expect(agg.fragen.q1.ausspielungen).toBe(1);
    expect(agg.fragen.q1.antworten).toBe(2);
    expect(agg.fragen.q1.richtig).toBe(1);
    expect(agg.fragen.q1.zeitN).toBe(2);
    expect(agg.fragen.q2.tippKaeufe).toBe(1); // Schmiergeld-Joker
    expect(agg.fragen.q1.proModus.quick).toEqual({ n: 2, richtig: 1 });
  });

  it("sammelt Feedback-Texte mit Profil-Zuordnung (Inbox §7.6/5)", () => {
    const agg = leereAggregate();
    wendeMatchAn(agg, miniMatch(), () => null);
    expect(agg.feedback).toHaveLength(1);
    expect(agg.feedback[0]).toMatchObject({
      profileId: "pr_anna",
      name: "Anna",
      text: "Mehr Bananen!",
    });
  });

  it("ist idempotent pro matchId (genau-einmal)", () => {
    const agg = leereAggregate();
    wendeMatchAn(agg, miniMatch(), () => null);
    wendeMatchAn(agg, miniMatch(), () => null);
    expect(agg.profile.pr_anna.matches).toBe(1);
  });

  it("parseZeilen überlebt halbe Zeilen (Crash mitten im append)", () => {
    const text = `${JSON.stringify(zeile("match_started"))}\n{"v":1,"ts":123,"mat`;
    expect(parseZeilen(text)).toHaveLength(1);
  });
});

describe("analytics: Aggregator-Job (Dateien)", () => {
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "mm-agg-"));
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("verarbeitet nur FERTIGE Matches und materialisiert meta/stats.json", async () => {
    const storage = createFileStorage(dir);
    for (const z of miniMatch()) await storage.appendLine("events/m_1.jsonl", JSON.stringify(z));
    // Laufendes Match (kein match_ended) — darf NICHT einfließen.
    await storage.appendLine(
      "events/m_2.jsonl",
      JSON.stringify(zeile("match_started", { matchId: "m_2" })),
    );

    const aggregator = createAggregator(
      storage,
      () => null,
      () => 99,
    );
    const agg = await aggregator.aktualisiere();
    expect(agg.verarbeitet).toEqual(["m_1"]);
    expect(agg.profile.pr_anna.matches).toBe(1);
    expect(agg.aktualisiertTs).toBe(99);

    // Zweiter Lauf: nichts Neues ⇒ keine Doppel-Zählung; lese() liefert den Stand.
    await aggregator.aktualisiere();
    expect((await aggregator.lese()).profile.pr_anna.matches).toBe(1);
  });

  it("Ruhefenster: frisch beendete Matches warten (Abspann-Feedback kommt noch)", async () => {
    const storage = createFileStorage(dir);
    for (const z of miniMatch()) await storage.appendLine("events/m_1.jsonl", JSON.stringify(z));

    let jetzt = T0 + 10_000; // Match GERADE beendet — Log ruht noch nicht
    const aggregator = createAggregator(
      storage,
      () => null,
      () => jetzt,
      90_000,
    );
    expect((await aggregator.aktualisiere()).verarbeitet).toEqual([]);

    // Abspann-Feedback trudelt nach match_ended ein — darf NICHT verloren gehen.
    await storage.appendLine(
      "events/m_1.jsonl",
      JSON.stringify(zeile("feedback_given", { actor: "p2", payload: { text: "Zugabe!" } })),
    );
    jetzt = T0 + 200_000; // Log ruht ⇒ jetzt einarbeiten, inkl. Nachzügler
    const agg = await aggregator.aktualisiere();
    expect(agg.verarbeitet).toEqual(["m_1"]);
    expect(agg.feedback.map((f) => f.text)).toEqual(["Mehr Bananen!", "Zugabe!"]);
  });

  it("Ruhefenster ankert am match_ended — presence-Events verschieben es NICHT (P1 Eval 4)", async () => {
    const storage = createFileStorage(dir);
    // match_ended trägt ts=T0; danach trudeln laufend presence-Events ein
    // (Handy-Disconnects/Reconnects in der Siegerehrung).
    for (const z of miniMatch()) await storage.appendLine("events/m_1.jsonl", JSON.stringify(z));
    await storage.appendLine(
      "events/m_1.jsonl",
      JSON.stringify(zeile("player_left", { actor: "p2", ts: T0 + 80_000 })),
    );
    await storage.appendLine(
      "events/m_1.jsonl",
      JSON.stringify(zeile("player_joined", { actor: "p2", ts: T0 + 91_000 })),
    );

    const aggregator = createAggregator(
      storage,
      () => null,
      // 95 s nach Match-Ende: letzte Zeile ist erst 4 s alt — früher hätte
      // das den Lauf blockiert, jetzt zählt NUR der match_ended-Zeitstempel.
      () => T0 + 95_000,
      90_000,
    );
    const agg = await aggregator.aktualisiere();
    expect(agg.verarbeitet).toEqual(["m_1"]);
    expect(agg.profile.pr_anna.matches).toBe(1);
  });
});
