// Bot-Lauf Bananen-Basics: 4 Bots spielen den OPENER (4 MC-4-Fragen) komplett
// in Echtzeit durch.
//   · Blitz-Bela     antwortet nach ~500 ms, immer richtig (voller Speed-Bonus)
//   · Solide-Sofia   antwortet nach ~3 s, immer richtig
//   · Zocker-Zoe     antwortet nach ~1 s, nur zu 50 % richtig (seeded Rng)
//   · Träge-Timo     antwortet nach ~13,5 s, richtig (Speed-Bonus ≈ 0)
// Der Lauf beweist die §2.1-Goldens LIVE: richtig = Grundwert + Speed-Bonus
// (Bela > Timo bei gleicher Frage), falsch = 0 OHNE Strafe (der sanfte
// Einstieg). Leak-Checks: correctIndex/aufloesung erscheinen NIE vor finished.
//
// Aufruf: npx tsx tools/bots/strategies/bananen-basics.ts [--seed 7]
import { bananenBasicsPlugin } from "../../../server/minigames/bananen-basics/index";
import type { Question } from "../../../shared/content";
import { FRAGE_WERTE } from "../../../shared/money";
import { createRng } from "../../../shared/rng";
import {
  beende,
  delay,
  pruefeKontoKorridor,
  sende,
  spawneRunde,
  spieleBisEnde,
  starteSyncPolling,
  starteTestServer,
} from "./_harness";

const THEMEN: [string, string[], number][] = [
  ["Welche Farbe hat eine reife Banane?", ["Blau", "Gelb", "Lila", "Karo"], 1],
  ["Was frisst ein Affe am liebsten?", ["Bananen", "Steine", "Autos", "Wolken"], 0],
  ["Wo schläft ein Affe?", ["Im Baum", "Im Auto", "Im Kühlschrank", "Im Briefkasten"], 0],
  ["Wie klingt ein Affe?", ["Muh", "Miau", "Uh-uh-ah-ah", "Piep"], 2],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Eine Spielshow", "Ein Gewürz", "Ein Planet"], 1],
  ["Womit klettert der Affe?", ["Mit Lianen", "Mit Leitern", "Mit Aufzügen", "Mit Raketen"], 0],
  ["Was liegt im Jackpot-Glas?", ["Sand", "Wasser", "Kekse", "MONKEY MONEY"], 3],
  ["Wer wohnt im Dschungel?", ["Der Pinguin", "Der Affe", "Das Walross", "Der Elch"], 1],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `bb-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "medium",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));
const GRUNDWERT = FRAGE_WERTE.medium; // 250
const MAX_GEWINN = 380; // 250 + voller Speed-Bonus 130 (Design-Golden §3.1)

interface Profil {
  name: string;
  antwortNachMs: number;
  trefferquote: number; // 0–1
}
const PROFILE: Profil[] = [
  { name: "Blitz-Bela", antwortNachMs: 500, trefferquote: 1 },
  { name: "Solide-Sofia", antwortNachMs: 3_000, trefferquote: 1 },
  { name: "Zocker-Zoe", antwortNachMs: 1_000, trefferquote: 0.5 },
  { name: "Traege-Timo", antwortNachMs: 13_500, trefferquote: 1 },
];
const FRAGEN_ZIEL = 4; // Opener-Runde der Klassik-Blaupause: 4 Fragen

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 7;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({ plugin: bananenBasicsPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(
    server,
    PROFILE.map((p) => p.name),
    "bananen-basics-bots",
  );
  const stopPolling = starteSyncPolling(runde);
  const botRng = createRng(seed * 1_000 + 1);

  // ---------- Spieler-Bots: pro Frage einmal antworten (Profil-Tempo) ----------
  for (let i = 0; i < PROFILE.length; i++) {
    const profil = PROFILE[i];
    const { bot, playerId } = runde.spieler[i];
    const beantwortet = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        finished?: boolean;
        correctIndex?: unknown;
        aufloesung?: unknown;
      } | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      // LEAK-CHECKS: Lösung + Auflösung dürfen VOR finished nie im Player-View stehen.
      if (!mg.finished && mg.correctIndex !== undefined) {
        runde.probleme.push(`${profil.name}: correctIndex leakt vor der Auflösung!`);
      }
      if (!mg.finished && mg.aufloesung !== null && mg.aufloesung !== undefined) {
        runde.probleme.push(`${profil.name}: aufloesung leakt vor finished!`);
      }
      if (mg.finished || beantwortet.has(mg.questionId)) return;
      const questionId = mg.questionId;
      // Plan-Position ≠ Plugin-Id im Injektions-Harness: die Id kommt aus dem View.
      const minigameId = view.minigame.id;
      beantwortet.add(questionId);
      const korrekt = ANTWORT.get(questionId.split("~")[0]) ?? 0;
      const richtig = botRng.next() < profil.trefferquote;
      const choice = richtig ? korrekt : (korrekt + 1) % 4;
      void (async () => {
        await delay(profil.antwortNachMs);
        const antwort = await sende(bot, "player.action", {
          minigameId,
          actionId: "answer",
          payload: { choice },
          idemKey: `${playerId}-${questionId}-answer`,
        });
        if (antwort?.ok) {
          runde.log(
            `${profil.name} tippt nach ${profil.antwortNachMs} ms ` +
              `${richtig ? "richtig" : "FALSCH"} (${questionId})`,
          );
        }
      })();
    });
  }

  await spieleBisEnde(runde, 60_000, { endeNachAufloesungen: FRAGEN_ZIEL });

  // ---------- Auswertung: §2.1-Scoring-Goldens auf JEDER Auflösung ----------
  if (runde.aufloesungen.length < FRAGEN_ZIEL) {
    runde.probleme.push(
      `Erwartet ≥ ${FRAGEN_ZIEL} Auflösungen, gesehen: ${runde.aufloesungen.length}`,
    );
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  for (const a of runde.aufloesungen) {
    for (const r of a.perPlayer) {
      const korrekt = r.correct === true;
      if (korrekt && (r.delta < GRUNDWERT || r.delta > MAX_GEWINN || r.delta % 10 !== 0)) {
        runde.probleme.push(
          `${r.playerId}: richtig, aber Delta ${r.delta} ∉ [${GRUNDWERT}, ${MAX_GEWINN}] (10er)`,
        );
      }
      if (!korrekt && r.delta !== 0) {
        runde.probleme.push(`${r.playerId}: falsch/keine Antwort, aber Delta ${r.delta} ≠ 0`);
      }
    }
    // Speed-Bonus-Beweis: Bela (~0,5 s) schlägt Timo (~13,5 s) bei GLEICHER Frage.
    const bela = a.perPlayer.find((r) => r.playerId === idVon.get("Blitz-Bela"));
    const timo = a.perPlayer.find((r) => r.playerId === idVon.get("Traege-Timo"));
    if (bela?.correct === true && timo?.correct === true && bela.delta <= timo.delta) {
      runde.probleme.push(
        `Speed-Bonus verletzt (${a.questionId}): Bela ${bela.delta} ≤ Timo ${timo.delta}`,
      );
    }
  }
  const ids = new Set(runde.aufloesungen.map((a) => a.questionId));
  if (ids.size !== runde.aufloesungen.length) {
    runde.probleme.push("Doppelte questionIds — der Fragen-Pool hat nicht rotiert");
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
