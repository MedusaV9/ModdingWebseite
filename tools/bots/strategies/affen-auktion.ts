// Bot-Lauf Affen-Auktion: 4 Bots versteigern 2 Fragen in Echtzeit.
//   · Bieter-Boris  bietet in F1 sofort hoch („erhöhe auf 300" — die Server-
//                   Klemme kappt aufs persönliche Limit) und gewinnt; in F2
//                   kontert er mit dem +25-Hammer, wenn sein Konto es hergibt
//   · Konter-Karla  versucht in F1 zu überbieten (Limit-Wache!), eröffnet F2
//   · Passive-Pia   bietet nie (ihr Anteil kommt aus dem Falsch-Fall)
//   · Schlaf-Sam    bietet nie
// GEWINNER-POLICY: die F1-Auktion wird RICHTIG beantwortet (+Gebot aus der
// Bank), die F2-Auktion FALSCH (das Gebot wandert nullsummig an alle anderen).
// Der Lauf beweist die exakte Abrechnung beider Pfade, die Gebots-Klemme
// (25er-Raster, Konto-Limit) und die Leak-Wache (Frage-Text/Optionen bleiben
// im Bieter-Fenster auf dem Server; Optionen sieht nur der Gewinner).
//
// Aufruf: npx tsx tools/bots/strategies/affen-auktion.ts [--seed 19]
import { affenAuktionPlugin } from "../../../server/minigames/affen-auktion/index";
import type { Question } from "../../../shared/content";
import { AA_SCHRITT, aaVerteilAnteil } from "../../../shared/minigames/affen-auktion.meta";
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
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `auk-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "hard",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Bieter-Boris", "Konter-Karla", "Passive-Pia", "Schlaf-Sam"];
const FRAGEN_ZIEL = 2;

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 19;
}

interface AukView {
  questionId?: string;
  phase?: string;
  finished?: boolean;
  text?: string | null;
  options?: string[] | null;
  hoechstgebot?: number;
  einsatzMax?: number;
  yourEinsatz?: { betrag: number } | null;
  duBistGewinner?: boolean;
  correctIndex?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({ plugin: affenAuktionPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "auk-bots");
  const stopPolling = starteSyncPolling(runde);

  // Auktions-Reihenfolge aus Sicht des Screens (F1 = richtig, F2 = falsch).
  const frageReihenfolge: string[] = [];
  runde.screen.onView((view) => {
    const mg = view.minigame?.view as AukView | null;
    if (view.phase === "frage" && mg?.questionId && !frageReihenfolge.includes(mg.questionId)) {
      frageReihenfolge.push(mg.questionId);
    }
  });

  // ---------- Spieler-Bots ----------
  for (let i = 0; i < NAMEN.length; i++) {
    const name = NAMEN[i];
    const { bot, playerId } = runde.spieler[i];
    const geboten = new Set<string>();
    const beantwortet = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as AukView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const questionId = mg.questionId;
      const minigameId = view.minigame.id;
      const frageNr = frageReihenfolge.indexOf(questionId) + 1;

      // LEAK-WACHEN: im Bieter-Fenster bleiben Text + Optionen auf dem Server;
      // die Lösung sieht NIE ein Spieler.
      if (mg.phase === "setzen" && (typeof mg.text === "string" || Array.isArray(mg.options))) {
        runde.probleme.push(`${name}: Frage leakt im Bieter-Fenster!`);
      }
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.finished) return;

      // 1) AUKTION: Profil-Gebote (einsatz = „erhöhe auf", bieten = +25).
      if (mg.phase === "setzen" && !geboten.has(questionId)) {
        geboten.add(questionId);
        void (async () => {
          if (name === "Bieter-Boris" && frageNr === 1) {
            await delay(500);
            const antwort = await sende(bot, "player.action", {
              minigameId,
              actionId: "einsatz",
              payload: { betrag: 300 },
              idemKey: `${playerId}-${questionId}-einsatz`,
            });
            if (antwort?.ok) runde.log("Boris bietet „erhöhe auf 300“ (Klemme kappt aufs Limit)");
          } else if (name === "Konter-Karla" && frageNr === 1) {
            // Konter-Versuch NACH Boris: das Konto-Limit (100) blockt ihn.
            await delay(1_500);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "bieten",
              payload: {},
              idemKey: `${playerId}-${questionId}-konter`,
            });
            runde.log("Karla versucht zu kontern (Limit-Wache greift)");
          } else if (name === "Konter-Karla" && frageNr === 2) {
            await delay(500);
            const antwort = await sende(bot, "player.action", {
              minigameId,
              actionId: "einsatz",
              payload: { betrag: 100 },
              idemKey: `${playerId}-${questionId}-einsatz`,
            });
            if (antwort?.ok) runde.log("Karla eröffnet F2 mit 100");
          } else if (name === "Bieter-Boris" && frageNr === 2) {
            // +25-Hammer NACH Karlas Eröffnung — nur wenn das Konto es hergibt.
            await delay(1_800);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "bieten",
              payload: {},
              idemKey: `${playerId}-${questionId}-hammer`,
            });
            runde.log("Boris drückt den +25-Hammer (F2)");
          }
        })();
      }

      // 2) FRAGE: NUR der Gewinner sieht Optionen — F1 richtig, F2 FALSCH.
      if (
        mg.phase === "frage" &&
        mg.duBistGewinner === true &&
        Array.isArray(mg.options) &&
        !beantwortet.has(questionId)
      ) {
        beantwortet.add(questionId);
        const korrekt = ANTWORT.get(questionId.split("~")[0]) ?? 0;
        const choice = frageNr === 1 ? korrekt : (korrekt + 1) % 4;
        void (async () => {
          await delay(800);
          const antwort = await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-${questionId}-answer`,
          });
          if (antwort?.ok) {
            runde.log(
              `${name} beantwortet F${frageNr} als Gewinner ${frageNr === 1 ? "RICHTIG" : "FALSCH"}`,
            );
          }
        })();
      }
      // Zuschauer-Wache: Nicht-Gewinner dürfen KEINE options sehen.
      if (mg.phase === "frage" && mg.duBistGewinner !== true && Array.isArray(mg.options)) {
        runde.probleme.push(`${name}: Antwort-Optionen leaken an einen Zuschauer!`);
      }
    });
  }

  // Auktionen laufen den vollen 20-s-Hammer — großzügiger Phasen-Timeout.
  await spieleBisEnde(runde, 120_000, { endeNachAufloesungen: FRAGEN_ZIEL });

  // ---------- Auswertung: beide Abrechnungs-Pfade EXAKT ----------
  if (runde.aufloesungen.length < FRAGEN_ZIEL) {
    runde.probleme.push(
      `Erwartet ≥ ${FRAGEN_ZIEL} Auflösungen, gesehen: ${runde.aufloesungen.length}`,
    );
  }
  for (const [nr, a] of runde.aufloesungen.entries()) {
    const gewinner = a.perPlayer.filter((r) => r.gebot !== null && r.gebot !== undefined);
    if (gewinner.length !== 1) {
      runde.probleme.push(`F${nr + 1}: ${gewinner.length} Gewinner statt 1`);
      continue;
    }
    const g = gewinner[0];
    const gebot = g.gebot as number;
    const andere = a.perPlayer.filter((r) => r.playerId !== g.playerId);
    if (gebot % AA_SCHRITT !== 0 || gebot < AA_SCHRITT) {
      runde.probleme.push(`F${nr + 1}: Gebot ${gebot} verletzt das 25er-Raster`);
    }
    if (nr === 0) {
      // F1: RICHTIG ⇒ Gewinner +Gebot aus der Bank, alle anderen 0.
      if (g.correct !== true || g.delta !== gebot) {
        runde.probleme.push(
          `F1: Gewinner-Abrechnung falsch (correct=${String(g.correct)}, ` +
            `delta=${g.delta} ≠ +${gebot})`,
        );
      }
      for (const r of andere) {
        if (r.delta !== 0) runde.probleme.push(`F1: ${r.playerId} delta ${r.delta} ≠ 0`);
      }
    } else {
      // F2: FALSCH ⇒ Anteil je Mitspieler, Gewinner zahlt EXAKT die Summe.
      const anteil = aaVerteilAnteil(gebot, andere.length);
      if (g.correct !== false || g.delta !== -anteil * andere.length) {
        runde.probleme.push(
          `F2: Falsch-Abrechnung falsch (delta=${g.delta} ≠ ${-anteil * andere.length})`,
        );
      }
      for (const r of andere) {
        if (r.delta !== anteil) {
          runde.probleme.push(`F2: ${r.playerId} Anteil ${r.delta} ≠ ${anteil}`);
        }
      }
      const summe = a.perPlayer.reduce((s, r) => s + r.delta, 0);
      if (summe !== 0) runde.probleme.push(`F2: Nullsummen-Invariante verletzt (Σ ${summe})`);
    }
    // Exklusivität: nur der Gewinner hat eine choice.
    for (const r of andere) {
      if (r.choice !== null && r.choice !== undefined) {
        runde.probleme.push(`F${nr + 1}: ${r.playerId} hat als Zuschauer geantwortet`);
      }
    }
    runde.log(
      `F${nr + 1}: Gewinner ${g.playerId} @ ${gebot} MM → ` +
        (nr === 0 ? `richtig, +${gebot} aus der Bank ✓` : `falsch, Verteilung nullsummig ✓`),
    );
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
