// Quest-Store: Verbuchen von Match-Fakten in die AKTIVEN Quests (idempotent
// pro matchId), XP nur beim erstmaligen Abschluss, Tages-/Saison-Rollover
// und die m-pass-15-Sondermechanik (Fortschritt = Pass-Stufe).
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  QUEST_MAP,
  dailyQuestIdsFuer,
  leereFakten,
  monatsQuestIdsFuer,
  type MatchFakten,
} from "../../shared/quests";
import { createTestClock } from "../../shared/time";
import { createFileStorage } from "../persistence/storage";
import { createQuestService, type QuestService } from "./quests";

const AUG = Date.UTC(2026, 7, 15);

let dir: string;
let clock: ReturnType<typeof createTestClock>;
let service: QuestService;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-quests-"));
  clock = createTestClock(AUG);
  service = createQuestService(createFileStorage(dir), clock);
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

/** Fakten, die JEDE aktive Quest maximal bewegen (Ziele in einem Match). */
function starkeFakten(): MatchFakten {
  return {
    ...leereFakten(),
    endstand: 5000,
    sieg: true,
    platz: 1,
    beantwortet: 100,
    richtig: 100,
    besteSerie: 10,
    unter3s: 10,
    richtigUnter5s: 10,
    schnellsteAbgaben: 10,
    jokerGenutzt: 10,
    ultrahardRichtig: 3,
    wettenGewonnen: 2,
    gestohlen: 500,
    minigames: ["bananen-tresor", "pixel-dschungel", "taschendieb"],
    kategorien: ["musik", "wissen", "sport"],
    musikRunde: true,
    feedback: true,
  };
}

describe("quests: Verbuchen am Match-Ende", () => {
  it("bewegt die 3 Dailies + Monats-Quests; XP nur bei Abschluss", async () => {
    const { deltas, xp } = await service.verbucheMatch("m_1", "pr_a", starkeFakten());
    // m-pass-15 misst 0 aus Match-Fakten — bewegt sich hier nie.
    expect(deltas.every((d) => d.questId !== "m-pass-15")).toBe(true);
    const fertige = deltas.filter((d) => d.fertigJetzt);
    expect(fertige.length).toBeGreaterThanOrEqual(3); // alle 3 Dailies sofort
    expect(xp).toBe(fertige.reduce((s, d) => s + d.xp, 0));
    for (const d of deltas) {
      expect(d.nachher).toBeGreaterThan(d.vorher);
      expect(d.nachher).toBeLessThanOrEqual(d.ziel); // nie über das Ziel hinaus
    }
  });

  it("idempotent pro matchId: das gleiche Match bucht nie doppelt", async () => {
    const erste = await service.verbucheMatch("m_1", "pr_a", starkeFakten());
    expect(erste.xp).toBeGreaterThan(0);
    const zweite = await service.verbucheMatch("m_1", "pr_a", starkeFakten());
    expect(zweite).toEqual({ deltas: [], xp: 0 });
  });

  it("abgeschlossene Quests geben in Folge-Matches KEIN weiteres XP/Delta", async () => {
    await service.verbucheMatch("m_1", "pr_a", starkeFakten());
    const fertigNachM1 = new Set(
      (await service.stand("pr_a")).quests.filter((q) => q.fertig).map((q) => q.questId),
    );
    expect(fertigNachM1.size).toBeGreaterThanOrEqual(3);
    const nochmal = await service.verbucheMatch("m_2", "pr_a", starkeFakten());
    for (const d of nochmal.deltas) expect(fertigNachM1.has(d.questId)).toBe(false);
  });

  it("Fortschritt über MEHRERE Matches summiert (z. B. m-fragen-100)", async () => {
    if (!monatsQuestIdsFuer("2026-08").includes("m-fragen-100")) return;
    const halb = { ...leereFakten(), beantwortet: 40 };
    const e1 = await service.verbucheMatch("m_1", "pr_a", halb);
    const d1 = e1.deltas.find((d) => d.questId === "m-fragen-100")!;
    expect(d1).toMatchObject({ vorher: 0, nachher: 40, fertigJetzt: false, xp: 0 });
    const e2 = await service.verbucheMatch("m_2", "pr_a", { ...halb, beantwortet: 60 });
    const d2 = e2.deltas.find((d) => d.questId === "m-fragen-100")!;
    expect(d2).toMatchObject({ vorher: 40, nachher: 100, fertigJetzt: true });
    expect(d2.xp).toBe(QUEST_MAP.get("m-fragen-100")!.xp);
  });
});

describe("quests: Rollover + Anzeige-Stand", () => {
  it("neuer Tag: frische Daily-Rotation, Monats-Fortschritt bleibt", async () => {
    await service.verbucheMatch("m_1", "pr_a", starkeFakten());
    clock.advance(24 * 3600 * 1000); // → 16.08.
    const stand = await service.stand("pr_a");
    expect(stand.tagKey).toBe("2026-08-16");
    const dailies = stand.quests.filter((q) => q.art === "daily");
    expect(dailies.map((q) => q.questId)).toEqual(dailyQuestIdsFuer("2026-08-16"));
    expect(dailies.every((q) => !q.fertig && q.fortschritt === 0)).toBe(true);
    // Monats-Quests haben den Vortages-Fortschritt behalten.
    const monat = stand.quests.find((q) => q.questId === "m-siege-5");
    expect(monat?.fortschritt).toBe(1);
  });

  it("neue Saison: auch die Monats-Quests starten frisch", async () => {
    await service.verbucheMatch("m_1", "pr_a", starkeFakten());
    clock.advance(31 * 24 * 3600 * 1000); // → 15.09.
    const stand = await service.stand("pr_a");
    expect(stand.saisonId).toBe("2026-09");
    expect(stand.quests.filter((q) => q.art === "monat").every((q) => q.fortschritt === 0)).toBe(
      true,
    );
  });

  it("m-pass-15: Fortschritt = erreichte Pass-Stufe, XP einmalig bei 15", async () => {
    const d1 = await service.aktualisierePassStufe("pr_a", 7);
    expect(d1).toMatchObject({ questId: "m-pass-15", vorher: 0, nachher: 7, fertigJetzt: false });
    expect(await service.aktualisierePassStufe("pr_a", 7)).toBeNull(); // kein Delta
    expect(await service.aktualisierePassStufe("pr_a", 3)).toBeNull(); // sinkt nie
    const fertig = await service.aktualisierePassStufe("pr_a", 16);
    expect(fertig).toMatchObject({ nachher: 15, fertigJetzt: true });
    expect(fertig?.xp).toBe(QUEST_MAP.get("m-pass-15")!.xp);
    expect(await service.aktualisierePassStufe("pr_a", 30)).toBeNull(); // Ziel gedeckelt
  });
});
