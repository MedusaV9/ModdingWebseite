// Match-Ende-Meta-Pipeline (Regression): AT-Buchung → Event-Log-Fakten →
// Quest-Verbuchung → Pass-XP → Belohnungen einlösen (Items + AT-Boni, die das
// Level füttern) — alles über den ECHTEN MetaService mit File-Storage.
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { XP_MATCH, XP_SIEG } from "../../shared/quests";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader, KatalogFrage } from "../content-loader/index";
import { createFileStorage, type Storage } from "../persistence/storage";
import { createMetaService, type MetaService } from "./index";

const AUG = Date.UTC(2026, 7, 15);

function frage(id: string, patch: Partial<Question> = {}): Question {
  return {
    id,
    kind: "choice4",
    category: "affen",
    difficulty: "easy",
    text: `Frage ${id}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "Weil B.",
    ...patch,
  };
}

function fakeLoader(fragen: Question[]): ContentLoader {
  const katalog: KatalogFrage[] = fragen.map((f) => ({
    frage: f,
    oberkategorie: f.category === "musik-hits" ? "musik" : "wissen",
    planTyp: "mc4",
    region: "global",
  }));
  return {
    async loadPacks() {},
    pickQuestions: () => [],
    alleFragen: () => katalog,
  };
}

let dir: string;
let storage: Storage;
let clock: ReturnType<typeof createTestClock>;
let meta: MetaService;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-matchmeta-"));
  storage = createFileStorage(dir);
  clock = createTestClock(AUG);
  meta = createMetaService({
    storage,
    clock,
    rng: createRng(7),
    contentLoader: fakeLoader([
      frage("q1", { category: "musik-hits", difficulty: "ultrahard" }),
      frage("q2", { category: "geo", difficulty: "medium" }),
    ]),
  });
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

/** Synthetisches Event-Log EXAKT im JSONL-Format des MatchEventLog schreiben. */
async function schreibeLog(matchId: string, profileId: string): Promise<void> {
  const zeilen = [
    { type: "profile_bound", actor: "p1", payload: { profileId } },
    { type: "player_joined", actor: "p2", payload: { name: "Gast" } },
    {
      type: "runde_gestartet",
      payload: { minigameId: "buzzer-blitz", slot: "warmup", kategorie: "musik-raten" },
    },
    { type: "question_shown", ts: 10_000, questionId: "q1", payload: {} },
    { type: "answer_submitted", ts: 12_000, actor: "p1", payload: {} },
    {
      type: "answer_judged",
      ts: 12_500,
      actor: "p1",
      questionId: "q1",
      payload: { correct: true },
    },
    { type: "question_shown", ts: 30_000, questionId: "q2", payload: {} },
    { type: "answer_submitted", ts: 32_000, actor: "p1", payload: {} },
    {
      type: "answer_judged",
      ts: 32_500,
      actor: "p1",
      questionId: "q2",
      payload: { correct: true },
    },
    { type: "joker_used", ts: 40_000, actor: "p1", payload: { jokerId: "50-50" } },
    {
      type: "match_ended",
      payload: {
        standings: [
          { playerId: "p1", balance: 1500 },
          { playerId: "p2", balance: 400 },
        ],
      },
    },
  ];
  for (const [i, z] of zeilen.entries()) {
    await storage.appendLine(
      `events/${matchId}.jsonl`,
      JSON.stringify({ v: 1, ts: 0, matchId, seq: i, ...z }),
    );
  }
}

describe("meta: Match-Ende vergibt AT + Pass-XP + Quest-Fortschritt (Pipeline)", () => {
  it("volle Kette: XP = Match+Sieg+Quests, Belohnungen landen im Profil", async () => {
    const p = await meta.profile.erstelle({ name: "Anna", avatar: "don-bananas.gelb" });
    const buchungen = [{ profileId: p.profileId, endstand: 1500, at: 1800, sieg: true }];
    await schreibeLog("m_r1", p.profileId);

    const ergebnisse = await meta.profile.bucheMatch("m_r1", buchungen);
    expect(ergebnisse).toHaveLength(1);
    expect(ergebnisse[0].levelUp).toEqual({ von: 0, zu: 1 }); // 1.800 AT ⇒ Lv 1

    const metas = await meta.verbucheMatchMeta("m_r1", ergebnisse, buchungen);
    expect(metas).toHaveLength(1);
    const m = metas[0];
    // XP-Bilanz: 50 (Match) + 50 (Sieg) + alle JETZT abgeschlossenen Quests.
    const questXp = m.quests.reduce((s, q) => s + q.xp, 0);
    expect(m.xp).toBe(XP_MATCH + XP_SIEG + questXp);
    expect(m.quests.length).toBeGreaterThan(0); // Sieg/Endstand bewegen IMMER etwas
    expect(m.stufeNeu).toBeGreaterThanOrEqual(m.stufeVorher);
    expect(m.saisonId).toBe("2026-08");

    // AT-Boni der erreichten Pass-Stufen sind ECHTE Einnahmen im Profil.
    const atBoni = m.belohnungen.reduce((s, b) => s + (b.art === "at" ? (b.at ?? 0) : 0), 0);
    const profil = await meta.profile.hole(p.profileId);
    expect(profil?.at.gesamt).toBe(1800 + atBoni);
    expect(m.atGesamt).toBe(1800 + atBoni);
    // Item-Belohnungen (falls Stufe 5 erreicht) liegen im Besitz.
    for (const b of m.belohnungen) {
      if (b.art === "item" && b.itemId !== undefined) {
        expect(profil?.besitz).toContain(b.itemId);
      }
    }
    // Ergebnis-Puffer fürs Handy-Polling.
    expect(meta.matchErgebnis(p.profileId)?.matchId).toBe("m_r1");
    expect(meta.matchErgebnis("pr_fremd")).toBeNull();
  });

  it("idempotent: dasselbe Match ein zweites Mal verbuchen ist ein No-Op", async () => {
    const p = await meta.profile.erstelle({ name: "Ben", avatar: "gelb" });
    const buchungen = [{ profileId: p.profileId, endstand: 900, at: 500, sieg: false }];
    await schreibeLog("m_r2", p.profileId);
    const e1 = await meta.profile.bucheMatch("m_r2", buchungen);
    await meta.verbucheMatchMeta("m_r2", e1, buchungen);
    const vorher = await meta.season.stand(p.profileId);

    const e2 = await meta.profile.bucheMatch("m_r2", buchungen); // Doppel-Event
    expect(e2).toEqual([]);
    const metas = await meta.verbucheMatchMeta("m_r2", e2, buchungen);
    expect(metas).toEqual([]);
    expect((await meta.season.stand(p.profileId)).xp).toBe(vorher.xp);
    expect((await meta.profile.hole(p.profileId))?.at.gesamt).toBe(500 + vorher.atBonus);
  });

  it("Level-Up auch DURCH Pass-AT-Boni (900 AT Match + 100 AT Stufe 1 = Lv 1)", async () => {
    const p = await meta.profile.erstelle({ name: "Cleo", avatar: "rot" });
    const buchungen = [{ profileId: p.profileId, endstand: 900, at: 900, sieg: false }];
    await schreibeLog("m_r3", p.profileId);
    const e = await meta.profile.bucheMatch("m_r3", buchungen);
    expect(e[0].levelUp).toBeNull(); // 900 AT allein reichen nicht
    const [m] = await meta.verbucheMatchMeta("m_r3", e, buchungen);
    // Ohne Sieg: 50 XP Match + Quest-XP ⇒ mindestens Stufe 1 wäre 100 XP.
    // Falls Stufe 1 erreicht wurde (Quest-XP), kam +100 AT ⇒ Level-Up.
    if (m.stufeNeu >= 1) {
      expect(m.atGesamt).toBeGreaterThanOrEqual(1000);
      expect(m.levelUp).toEqual({ von: 0, zu: 1 });
    } else {
      expect(m.levelUp).toBeNull();
    }
  });

  it("passUebersicht: EIN Read für den Landing-Tab (Leiste + Quests + Archiv)", async () => {
    const p = await meta.profile.erstelle({ name: "Dana", avatar: "blau" });
    const buchungen = [{ profileId: p.profileId, endstand: 2000, at: 1000, sieg: true }];
    await schreibeLog("m_r4", p.profileId);
    const e = await meta.profile.bucheMatch("m_r4", buchungen);
    const [m] = await meta.verbucheMatchMeta("m_r4", e, buchungen);

    const u = await meta.passUebersicht(p.profileId);
    expect(u.saison).toMatchObject({ id: "2026-08", name: "Dschungel-Auftakt", stufen: 30 });
    expect(u.stufe).toBe(m.stufeNeu);
    expect(u.belohnungen).toHaveLength(30);
    for (const b of u.belohnungen) expect(b.erreicht).toBe(b.stufe <= u.stufe);
    // Item-Stufen tragen die aufgelösten Item-Infos (Name/Emoji für die Leiste).
    const itemStufe = u.belohnungen.find((b) => b.art === "item");
    expect(itemStufe?.item?.name).toContain("S1");
    expect(u.quests.length).toBe(6); // 3 Dailies + 3 Monats-Quests
    expect(u.tagKey).toBe("2026-08-15");
    expect(u.archiv).toEqual([]);
  });
});
