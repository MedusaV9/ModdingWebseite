// Wächter: Format-Content-Zuordnung (Bild-Fragen ↔ Pixel-Dschungel) und
// Tutorial-Video-Angebot auf der Erklärkarte (Match-Setting tutorialVideos).
// Kette: Content-Loader liefert media-Fragen → plan.waehleFrage routet sie
// NUR an Bild-Formate (bevorzugt!) → Plugin-View zeigt die Media-URL.
import { beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createRng } from "../../shared/rng";
import { defaultSettings, type MatchSettings } from "../../shared/settings";
import { createTestClock } from "../../shared/time";
import { vierLianenPlugin } from "../minigames/vier-lianen/index";
import { createInitialState, reduce, tick, type EngineDeps } from "./engine";
import { passtFrageZuFormat, waehleErsatzFrage, waehleFrage } from "./plan";
import { viewFor, type RoomInfo } from "./views";
import { ERKLAERKARTE_KURZ_MS, INTRO_MS, type Abschnitt, type EngineState } from "./types";
import type { ErklaerkarteView, ScreenView } from "../../shared/views";

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

const bildFrage = (id: string): Question =>
  frage(id, {
    category: "staedte_wahrzeichen",
    media: { bild: `/media/img/generated/pixel/${id}.png` },
  });

const abschnitt = (minigameId: string, patch: Partial<Abschnitt> = {}): Abschnitt => ({
  typ: "runde",
  nr: 1,
  slot: "aufbau",
  wunschMinigameId: minigameId,
  minigameId,
  fragen: 4,
  schwierigkeiten: ["easy", "medium"],
  kategorieWahl: "keine",
  radDanach: false,
  kategorie: null,
  ...patch,
});

/** Minimaler Engine-State für die reinen plan.ts-Helfer. */
function planState(pool: Question[], abschnitte: Abschnitt[] = []): EngineState {
  const s = createInitialState(defaultSettings("quick"));
  return {
    ...s,
    fragenPool: pool,
    plan: { abschnitte, rundenTotal: 1, fragenTotal: 4, ultrahardMax: 1 },
    abschnittIndex: 0,
  };
}

describe("Format-Content-Zuordnung (plan.ts)", () => {
  it("passtFrageZuFormat: media-Fragen nur an pixel-dschungel", () => {
    const bild = bildFrage("qb1");
    const normal = frage("qn1");
    expect(passtFrageZuFormat(bild, "pixel-dschungel")).toBe(true);
    expect(passtFrageZuFormat(bild, "vier-lianen")).toBe(false);
    expect(passtFrageZuFormat(bild, "affenbank")).toBe(false);
    expect(passtFrageZuFormat(normal, "vier-lianen")).toBe(true);
    expect(passtFrageZuFormat(normal, "pixel-dschungel")).toBe(true);
  });

  it("waehleFrage: pixel-dschungel zieht BEVORZUGT bild_pixel-Fragen (media)", () => {
    const pool = [
      ...Array.from({ length: 20 }, (_, i) => frage(`qn${i + 1}`)),
      bildFrage("qb1"),
      bildFrage("qb2"),
    ];
    let s = planState(pool, [abschnitt("pixel-dschungel")]);
    const rng = createRng(7);
    // Beide Bild-Fragen kommen ZUERST — trotz 20 normaler Kandidaten im Pool.
    const erste = waehleFrage(s, s.plan!.abschnitte[0], rng).frage;
    expect(erste.media?.bild).toMatch(/^\/media\//);
    s = { ...s, usedQuestionIds: [erste.id] };
    const zweite = waehleFrage(s, s.plan!.abschnitte[0], rng).frage;
    expect(zweite.media?.bild).toMatch(/^\/media\//);
    expect(zweite.id).not.toBe(erste.id);
    // Bild-Fragen aufgebraucht ⇒ Fallback auf normale Fragen (Platzhalter-Weg).
    s = { ...s, usedQuestionIds: [erste.id, zweite.id] };
    const dritte = waehleFrage(s, s.plan!.abschnitte[0], rng).frage;
    expect(dritte.media).toBeUndefined();
  });

  it("waehleFrage: andere Formate MEIDEN media-Fragen", () => {
    const pool = [bildFrage("qb1"), bildFrage("qb2"), bildFrage("qb3"), frage("qn1")];
    const s = planState(pool, [abschnitt("vier-lianen")]);
    const rng = createRng(3);
    const { frage: gewaehlt } = waehleFrage(s, s.plan!.abschnitte[0], rng);
    expect(gewaehlt.id).toBe("qn1");
    // Not-Ausstieg: NUR noch media-Fragen übrig ⇒ lieber Format-fremd als keine.
    const leer = { ...s, usedQuestionIds: ["qn1"] };
    const not = waehleFrage(leer, leer.plan!.abschnitte[0], rng);
    expect(not.frage).toBeDefined();
  });

  it("waehleErsatzFrage: Ersatz im Nicht-Bild-Format ist nie eine media-Frage", () => {
    const pool = [bildFrage("qb1"), frage("qn1"), frage("qn2", { difficulty: "medium" })];
    const s = planState(pool, [abschnitt("vier-lianen")]);
    for (let seed = 1; seed <= 10; seed++) {
      const ersatz = waehleErsatzFrage(s, createRng(seed), { schwierigkeit: "easy" });
      expect(ersatz?.media).toBeUndefined();
    }
  });
});

// ---------- Erklärkarte: Tutorial-Video-Angebot (Match-Setting) ----------

const clockStart = 1_000_000;
let clock: ReturnType<typeof createTestClock>;
let ctx: { clock: ReturnType<typeof createTestClock>; rng: ReturnType<typeof createRng> };
const deps: EngineDeps = { getPlugin: () => vierLianenPlugin };
const roomInfo: RoomInfo = {
  roomCode: "AFFE",
  joinUrl: "http://x/j/AFFE",
  qrPath: "/api/qr?code=AFFE",
  gmPin: "1234",
  gmLog: [],
};

beforeEach(() => {
  clock = createTestClock(clockStart);
  ctx = { clock, rng: createRng(42) };
});

function bisErklaerkarte(settings: Partial<MatchSettings>): EngineState {
  let s = createInitialState({ ...defaultSettings("quick"), autoGm: false, ...settings });
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
  clock.advance(INTRO_MS + 1);
  return tick(s, deps, ctx).state; // intro → erklaerkarte
}

function erklaerkarteVon(s: EngineState): ErklaerkarteView | null {
  const view = viewFor(s, "screen", deps, roomInfo, ctx) as ScreenView;
  return view.erklaerkarte;
}

describe("Erklärkarte: Tutorial-Videos (Setting tutorialVideos, Default AUS)", () => {
  it("Default AUS: keine videoUrl auf der Karte (Tempo!)", () => {
    const s = bisErklaerkarte({});
    const ek = erklaerkarteVon(s);
    expect(ek?.minigameId).toBe("vier-lianen");
    expect(ek?.videoUrl).toBeUndefined();
  });

  it("AN: vier-lianen-Karte bietet das Tutorial-Video an (per /media-URL)", () => {
    const s = bisErklaerkarte({ tutorialVideos: true });
    const ek = erklaerkarteVon(s);
    expect(ek?.videoUrl).toBe("/media/video/tutorial_vier-lianen.mp4");
    // Skip-Verhalten unangetastet: Karte läuft nach Ablauf normal weiter.
    clock.advance(ERKLAERKARTE_KURZ_MS + 1);
    const danach = tick(s, deps, ctx).state;
    expect(danach.phase).toBe("frage");
  });

  it("AN, aber Format ohne Video (frisches Plugin): kein Knopf — Text wie bisher", () => {
    // Seit dem Tutorial-Rollout haben ALLE 21 Formate ein Video — der Fall
    // bleibt für künftige Plugins relevant, darum eine Kunst-Id ohne Eintrag.
    const s = bisErklaerkarte({ tutorialVideos: true });
    // Karte eines Formats ohne Video simulieren: Abschnitt umbiegen.
    const plan = s.plan!;
    const abschnitte = plan.abschnitte.map((a, i) =>
      i === s.abschnittIndex ? { ...a, minigameId: "prototyp-ohne-video" } : a,
    );
    const sOhne = { ...s, plan: { ...plan, abschnitte } };
    const deps2: EngineDeps = {
      getPlugin: () => ({
        ...vierLianenPlugin,
        meta: { ...vierLianenPlugin.meta, id: "prototyp-ohne-video" },
      }),
    };
    const view = viewFor(sOhne, "screen", deps2, roomInfo, ctx) as ScreenView;
    expect(view.erklaerkarte?.videoUrl).toBeUndefined();
  });
});
