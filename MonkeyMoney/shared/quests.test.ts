// Bananen-Pass & Quests (Meta-Agent 2): Saison-Kalender, XP-Kurve mit
// Stufen-Grenzen, generierte Saison-Items, deterministische Quest-Rotation
// und die Match-Fakten-Ableitung aus synthetischen Event-Log-Zeilen.
import { describe, expect, it } from "vitest";
import {
  DAILY_QUESTS,
  MONATS_QUESTS,
  PASS_STUFEN,
  QUEST_MAP,
  XP_DAILY,
  XP_MATCH,
  XP_SIEG,
  dailyQuestIdsFuer,
  itemFuer,
  matchFakten,
  monatsQuestIdsFuer,
  passBelohnungen,
  passStufeFuerXp,
  saisonEndeMs,
  saisonIdFuer,
  saisonItems,
  saisonName,
  saisonNummer,
  tagKeyFuer,
  xpKostenFuerStufe,
  xpKumulativFuerStufe,
  type QuestLogZeile,
} from "./quests";

const AUG = Date.UTC(2026, 7, 15, 20, 0, 0); // 15.08.2026, 20:00 UTC

describe("quests: Saison-Kalender (UTC)", () => {
  it("Saison-Id = Kalendermonat; Tages-Key = UTC-Datum", () => {
    expect(saisonIdFuer(AUG)).toBe("2026-08");
    expect(tagKeyFuer(AUG)).toBe("2026-08-15");
    // Monatsgrenze: 31.08. 23:59:59 UTC ist noch August, 1 s später September.
    const ende = Date.UTC(2026, 7, 31, 23, 59, 59);
    expect(saisonIdFuer(ende)).toBe("2026-08");
    expect(saisonIdFuer(ende + 1000)).toBe("2026-09");
  });

  it("Saison-Nummer + Jahres-Übergang + Saison-Ende", () => {
    expect(saisonNummer("2026-08")).toBe(1);
    expect(saisonNummer("2026-12")).toBe(5);
    expect(saisonNummer("2027-01")).toBe(6);
    expect(saisonEndeMs("2026-08")).toBe(Date.UTC(2026, 8, 1));
    expect(saisonEndeMs("2026-12")).toBe(Date.UTC(2027, 0, 1));
    expect(saisonName("2026-08")).toBe("Dschungel-Auftakt");
  });
});

describe("quests: Pass-XP-Kurve + Stufen-Grenzen", () => {
  it("Stufenkosten steigen in 3 Blöcken (100/150/200 XP)", () => {
    expect(xpKostenFuerStufe(1)).toBe(100);
    expect(xpKostenFuerStufe(10)).toBe(100);
    expect(xpKostenFuerStufe(11)).toBe(150);
    expect(xpKostenFuerStufe(20)).toBe(150);
    expect(xpKostenFuerStufe(21)).toBe(200);
    expect(xpKostenFuerStufe(30)).toBe(200);
  });

  it("kumulativ: Stufe 30 = 4.500 XP (≈ 8-10 Spielabende)", () => {
    expect(xpKumulativFuerStufe(10)).toBe(1000);
    expect(xpKumulativFuerStufe(20)).toBe(2500);
    expect(xpKumulativFuerStufe(PASS_STUFEN)).toBe(4500);
  });

  it("passStufeFuerXp: exakte Grenzen, 0-XP-Fall, alles jenseits von Stufe 30", () => {
    expect(passStufeFuerXp(0)).toBe(0);
    expect(passStufeFuerXp(99)).toBe(0);
    expect(passStufeFuerXp(100)).toBe(1);
    expect(passStufeFuerXp(999)).toBe(9);
    expect(passStufeFuerXp(1000)).toBe(10);
    expect(passStufeFuerXp(4499)).toBe(29);
    expect(passStufeFuerXp(4500)).toBe(30);
    expect(passStufeFuerXp(1_000_000)).toBe(30); // hart gedeckelt
  });
});

describe("quests: Saison-Items + Pass-Belohnungen", () => {
  it("Saison 1 „Dschungel-Auftakt“: 6 konkrete Exklusive, alle passExklusiv + unverkäuflich", () => {
    const items = saisonItems("2026-08");
    expect(items.map((i) => i.id)).toEqual([
      "titel-s1-dschungel-novize",
      "namestil-s1-lianengruen",
      "banner-s1-dschungelmorgen",
      "konfetti-s1-blaetterwirbel",
      "banner-s1-lianendickicht",
      "titel-s1-dschungel-legende",
    ]);
    for (const i of items) {
      expect(i.passExklusiv).toBe("2026-08");
      expect(i.preis).toBe(0);
    }
  });

  it("spätere Saisons generieren 5 Themen-Items; itemFuer findet sie per Id", () => {
    const items = saisonItems("2026-09");
    expect(items).toHaveLength(5);
    for (const i of items) {
      expect(i.passExklusiv).toBe("2026-09");
      expect(itemFuer(i.id)?.name).toBe(i.name);
    }
    // itemFuer kennt auch den Katalog + lehnt Unsinn ab.
    expect(itemFuer("hut-zylinder")?.slot).toBe("hut");
    expect(itemFuer("gibts-nicht")).toBeUndefined();
  });

  it("Belohnungen: 30 Stufen, S1-Items auf 5/10/15/20/25/30, Rest AT-Boni", () => {
    const b = passBelohnungen("2026-08");
    expect(b).toHaveLength(PASS_STUFEN);
    const itemStufen = b.filter((x) => x.art === "item").map((x) => x.stufe);
    expect(itemStufen).toEqual([5, 10, 15, 20, 25, 30]);
    const atSumme = b.reduce((s, x) => s + (x.at ?? 0), 0);
    expect(atSumme).toBe(6250); // dokumentierter Saison-Gesamtbonus (24 AT-Stufen)
    for (const x of b) {
      if (x.art === "item") expect(itemFuer(x.itemId ?? "")).toBeDefined();
    }
  });
});

describe("quests: Rotation (deterministisch, injizierter Hash-Seed)", () => {
  it("3 Dailies pro Tag aus dem 20er-Pool — stabil pro Tag, wechselnd über Tage", () => {
    expect(DAILY_QUESTS.length).toBeGreaterThanOrEqual(20);
    const heute = dailyQuestIdsFuer("2026-08-15");
    expect(heute).toHaveLength(3);
    expect(new Set(heute).size).toBe(3);
    expect(heute).toEqual(dailyQuestIdsFuer("2026-08-15")); // deterministisch
    for (const id of heute) expect(QUEST_MAP.get(id)?.art).toBe("daily");
    // Über eine Woche rotiert die Auswahl sichtbar.
    const alle = new Set(
      [15, 16, 17, 18, 19, 20, 21].flatMap((t) => dailyQuestIdsFuer(`2026-08-${t}`)),
    );
    expect(alle.size).toBeGreaterThan(3);
  });

  it("Monats-Quests: immer 3, m-pass-15 IMMER dabei, S1 fix wie designt", () => {
    expect(monatsQuestIdsFuer("2026-08")).toEqual(["m-siege-5", "m-fragen-100", "m-pass-15"]);
    for (const saison of ["2026-09", "2026-10", "2027-03"]) {
      const ids = monatsQuestIdsFuer(saison);
      expect(ids).toHaveLength(3);
      expect(ids).toContain("m-pass-15");
      for (const id of ids) expect(QUEST_MAP.get(id)?.art).toBe("monat");
    }
    expect(MONATS_QUESTS.length).toBeGreaterThanOrEqual(6);
  });
});

// ---------- Match-Fakten aus synthetischen Event-Logs ----------

function zeile(
  type: string,
  patch: Partial<QuestLogZeile> & { payload?: Record<string, unknown> } = {},
): QuestLogZeile {
  return {
    ts: patch.ts ?? 0,
    type,
    actor: patch.actor,
    questionId: patch.questionId,
    payload: patch.payload ?? {},
  };
}

/** Mini-Match: Anna (Profil pr_a) gewinnt, Ben (pr_b) verliert, Carl ist Gast. */
function miniMatch(): QuestLogZeile[] {
  return [
    zeile("profile_bound", { actor: "p1", payload: { profileId: "pr_a" } }),
    zeile("profile_bound", { actor: "p2", payload: { profileId: "pr_b" } }),
    zeile("runde_gestartet", {
      payload: { minigameId: "buzzer-blitz", slot: "warmup", kategorie: "musik-raten" },
    }),
    // Frage 1 (ultrahard): Anna buzzert nach 2 s richtig, Ben nach 6 s falsch.
    zeile("question_shown", { ts: 10_000, questionId: "q1" }),
    zeile("answer_submitted", { ts: 12_000, actor: "p1" }),
    zeile("answer_submitted", { ts: 16_000, actor: "p2" }),
    zeile("answer_judged", {
      ts: 16_500,
      actor: "p1",
      questionId: "q1",
      payload: { correct: true },
    }),
    zeile("answer_judged", {
      ts: 16_500,
      actor: "p2",
      questionId: "q1",
      payload: { correct: false },
    }),
    // Frage 2 (RISIKO): Anna nutzt einen Joker und gewinnt die Wette.
    zeile("runde_gestartet", {
      payload: { minigameId: "buzzer-blitz", slot: "risiko", kategorie: "wissen" },
    }),
    zeile("question_shown", { ts: 30_000, questionId: "q2" }),
    zeile("joker_used", { ts: 31_000, actor: "p1", payload: { jokerId: "50-50" } }),
    zeile("answer_submitted", { ts: 32_500, actor: "p1" }),
    zeile("answer_judged", {
      ts: 33_000,
      actor: "p1",
      questionId: "q2",
      payload: { correct: true },
    }),
    // Taschendieb: Anna stiehlt 300 MM.
    zeile("runde_gestartet", {
      payload: { minigameId: "taschendieb", slot: "normal", kategorie: "action" },
    }),
    zeile("money_changed", { actor: "p1", payload: { delta: 300, balance: 1500, grund: "klau" } }),
    zeile("money_changed", { actor: "p2", payload: { delta: -300, balance: 400, grund: "klau" } }),
    zeile("feedback_given", { actor: "p2", payload: { text: "war super" } }),
    zeile("match_ended", {
      payload: {
        standings: [
          { playerId: "p1", balance: 1500 },
          { playerId: "p2", balance: 400 },
          { playerId: "p3", balance: 100 }, // Gast ohne Profil
        ],
      },
    }),
  ];
}

describe("quests: matchFakten aus dem Event-Log (pur, synthetisch)", () => {
  const info = (qid: string) =>
    qid === "q1"
      ? { kategorie: "musik-hits", oberkategorie: "musik", schwierigkeit: "ultrahard" }
      : { kategorie: "geo", oberkategorie: "wissen", schwierigkeit: "medium" };

  it("leitet Sieg/Platz/Endstand + Antwort-Zähler pro PROFIL ab (Gäste fehlen)", () => {
    const fakten = matchFakten(miniMatch(), info);
    expect([...fakten.keys()].sort()).toEqual(["pr_a", "pr_b"]);
    const anna = fakten.get("pr_a")!;
    expect(anna.sieg).toBe(true);
    expect(anna.platz).toBe(1);
    expect(anna.endstand).toBe(1500);
    expect(anna.beantwortet).toBe(2);
    expect(anna.richtig).toBe(2);
    expect(anna.besteSerie).toBe(2);
    const ben = fakten.get("pr_b")!;
    expect(ben.sieg).toBe(false);
    expect(ben.platz).toBe(2);
    expect(ben.richtig).toBe(0);
  });

  it("erkennt Blitz-Antworten, Joker, Wetten, Klau, Musik-Runde und Kategorien", () => {
    const anna = matchFakten(miniMatch(), info).get("pr_a")!;
    expect(anna.unter3s).toBe(2); // 2,0 s und 2,5 s nach Frage-Start
    expect(anna.richtigUnter5s).toBe(2);
    expect(anna.schnellsteAbgaben).toBe(2); // beide Male ERSTE Abgabe
    expect(anna.jokerGenutzt).toBe(1);
    expect(anna.ultrahardRichtig).toBe(1);
    expect(anna.wettenGewonnen).toBe(1); // RISIKO-Slot richtig
    expect(anna.gestohlen).toBe(300);
    expect(anna.musikRunde).toBe(true); // Kategorie "musik-raten" der Runde
    expect(anna.kategorien.sort()).toEqual(["musik", "wissen"]);
    expect(anna.minigames).toContain("taschendieb");
    const ben = matchFakten(miniMatch(), info).get("pr_b")!;
    expect(ben.feedback).toBe(true);
    expect(ben.gestohlen).toBe(0); // negatives Delta zählt nicht als Klau
  });

  it("Quest-misst-Funktionen greifen auf die Fakten (Beispiele aus dem Pool)", () => {
    const fakten = matchFakten(miniMatch(), info);
    const anna = fakten.get("pr_a")!;
    const q = (id: string) => QUEST_MAP.get(id)!;
    expect(q("d-match-500").misst(anna)).toBe(1); // 1500 ≥ 500 MM
    expect(q("d-sieg").misst(anna)).toBe(1);
    expect(q("d-joker").misst(anna)).toBe(1);
    expect(q("d-musik").misst(anna)).toBe(1);
    expect(q("d-blitz-5").misst(anna)).toBe(2); // 2 von 5 unter 3 s
    expect(q("d-ultrahard").misst(anna)).toBe(1);
    expect(q("d-wette").misst(anna)).toBe(1);
    expect(q("d-dieb").misst(anna)).toBe(1);
    expect(q("m-fragen-100").misst(anna)).toBe(2);
    expect(q("m-matches-12").misst(anna)).toBe(1);
    const ben = fakten.get("pr_b")!;
    expect(q("d-sieg").misst(ben)).toBe(0);
    expect(q("d-feedback").misst(ben)).toBe(1);
  });

  it("XP-Konstanten: Match 50, Sieg +50, Daily 80 (Anzeige-Versprechen)", () => {
    expect(XP_MATCH).toBe(50);
    expect(XP_SIEG).toBe(50);
    expect(XP_DAILY).toBe(80);
    for (const d of DAILY_QUESTS) expect(d.xp).toBe(XP_DAILY);
  });
});
