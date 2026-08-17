// Bot-Lauf Monkey Market: 4 Bots spielen 2 Handels-Fragen in Echtzeit durch.
//   · Mut-Mio         ALLES AUF EINS auf die richtige Tür (answer-Draht) —
//                     der Mut-Bonus-Beweis: +25 % auf die volle Auszahlung
//   · Hedge-Hanna     verteilt Chip für Chip 6/4 auf richtig/falsch (chip-Draht)
//   · Falsch-Fiona    ALLES AUF EINS auf eine falsche Tür (Bank-Chips ⇒ 0)
//   · Zoeger-Zita     legt 2 Chips, nimmt 1 ZURÜCK (zurueck-Draht) und lässt
//                     den Rest liegen — der Markt läuft deshalb den vollen Timer
// Der Lauf beweist die exakte Auszahlung mmAuszahlung(chipsRichtig, chipWert,
// mutBonus) auf JEDER Auflösung, die Chip-Rücknahme und die Leak-Wachen
// (kein correctIndex, keine fremden Chip-Verteilungen im Player-View).
//
// Aufruf: npx tsx tools/bots/strategies/monkey-market.ts [--seed 7]
import { monkeyMarketPlugin } from "../../../server/minigames/monkey-market/index";
import type { Question } from "../../../shared/content";
import { MM_MARKT_CHIPS, mmAuszahlung } from "../../../shared/minigames/monkey-market.meta";
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
  ["Welche Falltür führt zur Banane?", ["Blau", "Gelb", "Lila", "Karo"], 1],
  ["Was frisst ein Affe am liebsten?", ["Bananen", "Steine", "Autos", "Wolken"], 0],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `mkt-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "hard", // W = 500 ⇒ Chip-Wert 50
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Mut-Mio", "Hedge-Hanna", "Falsch-Fiona", "Zoeger-Zita"];
const FRAGEN_ZIEL = 2;
const HANNA_RICHTIG = 6; // 6 Chips richtig, 4 falsch — Hedge-Beweis

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 7;
}

interface MktView {
  questionId?: string;
  finished?: boolean;
  chipWert?: number;
  chipsFrei?: number;
  yourChips?: number[];
  tuerSummen?: number[];
  correctIndex?: unknown;
  chips?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({ plugin: monkeyMarketPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "mkt-bots");
  const stopPolling = starteSyncPolling(runde);

  let chipWert = 0; // aus dem View (hard ⇒ 50) — Basis der Exakt-Mathe

  // ---------- Spieler-Bots: 4 Handels-Profile ----------
  for (let i = 0; i < NAMEN.length; i++) {
    const name = NAMEN[i];
    const { bot, playerId } = runde.spieler[i];
    const gehandelt = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as MktView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const questionId = mg.questionId;
      const minigameId = view.minigame.id;

      // LEAK-CHECKS: Lösung + fremde Chip-Verteilungen bleiben auf dem Server.
      if (!mg.finished && mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.chips !== undefined) {
        runde.probleme.push(`${name}: fremde Chip-Verteilungen leaken im Player-View!`);
      }
      if (mg.finished || gehandelt.has(questionId)) return;
      gehandelt.add(questionId);
      if (typeof mg.chipWert === "number") chipWert = mg.chipWert;

      const korrekt = ANTWORT.get(questionId.split("~")[0]) ?? 0;
      const falsch = (korrekt + 1) % 4;
      void (async () => {
        await delay(400 + i * 150);
        if (name === "Mut-Mio") {
          // ALLES AUF EINS (richtig) über den generischen answer-Draht.
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice: korrekt },
            idemKey: `${playerId}-${questionId}-allin`,
          });
          runde.log("Mut-Mio geht ALL-IN auf die richtige Tür (Mut-Bonus-Beweis)");
        } else if (name === "Hedge-Hanna") {
          // Chip für Chip: 6 richtig, 4 falsch (Hedging über den chip-Draht).
          for (let c = 0; c < MM_MARKT_CHIPS; c++) {
            await sende(bot, "player.action", {
              minigameId,
              actionId: "chip",
              payload: { tuer: c < HANNA_RICHTIG ? korrekt : falsch },
              idemKey: `${playerId}-${questionId}-chip${c}`,
            });
            await delay(80);
          }
          runde.log(`Hedge-Hanna hedgt ${HANNA_RICHTIG}/${MM_MARKT_CHIPS - HANNA_RICHTIG}`);
        } else if (name === "Falsch-Fiona") {
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice: falsch },
            idemKey: `${playerId}-${questionId}-allin`,
          });
          runde.log("Falsch-Fiona geht ALL-IN auf eine falsche Tür (Bank-Chips ⇒ 0)");
        } else {
          // Zoeger-Zita: 2 Chips drauf, 1 zurück — der Markt bleibt offen.
          for (let c = 0; c < 2; c++) {
            await sende(bot, "player.action", {
              minigameId,
              actionId: "chip",
              payload: { tuer: korrekt },
              idemKey: `${playerId}-${questionId}-chip${c}`,
            });
            await delay(80);
          }
          await sende(bot, "player.action", {
            minigameId,
            actionId: "zurueck",
            payload: { tuer: korrekt },
            idemKey: `${playerId}-${questionId}-zurueck`,
          });
          runde.log("Zoeger-Zita legt 2 Chips und nimmt 1 ZURÜCK (Rücknahme-Beweis)");
        }
      })();
    });
  }

  await spieleBisEnde(runde, 90_000, { endeNachAufloesungen: FRAGEN_ZIEL });

  // ---------- Auswertung: mmAuszahlung EXAKT auf jeder Auflösung ----------
  if (runde.aufloesungen.length < FRAGEN_ZIEL) {
    runde.probleme.push(
      `Erwartet ≥ ${FRAGEN_ZIEL} Auflösungen, gesehen: ${runde.aufloesungen.length}`,
    );
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  for (const [nr, a] of runde.aufloesungen.entries()) {
    const correctIndex = (a.mgView.aufloesung as { correctIndex?: unknown } | null)?.correctIndex;
    if (typeof correctIndex !== "number") {
      runde.probleme.push(`F${nr + 1}: Auflösung ohne correctIndex`);
      continue;
    }
    for (const r of a.perPlayer) {
      const chips = r.chips as number[] | undefined;
      const mutBonus = r.mutBonus === true;
      if (!Array.isArray(chips)) {
        runde.probleme.push(`${r.playerId} (F${nr + 1}): Auflösung ohne Chip-Verteilung`);
        continue;
      }
      const gesamt = chips.reduce((s, c) => s + c, 0);
      const richtig = chips[correctIndex] ?? 0;
      const erwartet = mmAuszahlung(
        richtig,
        chipWert,
        gesamt === MM_MARKT_CHIPS && richtig === MM_MARKT_CHIPS,
      );
      if (r.delta !== erwartet) {
        runde.probleme.push(
          `${r.playerId} (F${nr + 1}): Delta ${r.delta} ≠ mmAuszahlung ${erwartet} ` +
            `(chips=${chips.join("/")}, chipWert=${chipWert})`,
        );
      }
      if (mutBonus !== (gesamt === MM_MARKT_CHIPS && richtig === MM_MARKT_CHIPS)) {
        runde.probleme.push(`${r.playerId} (F${nr + 1}): Mut-Bonus-Flag falsch`);
      }
    }
    // Profil-Beweise: Mio voll + Bonus, Hanna 6/4, Fiona 0 richtig, Zita 1 Chip.
    const zeile = (spielerName: string) =>
      a.perPlayer.find((r) => r.playerId === idVon.get(spielerName));
    const mio = zeile("Mut-Mio");
    if (mio?.mutBonus !== true) runde.probleme.push(`F${nr + 1}: Mio ohne Mut-Bonus`);
    const hanna = zeile("Hedge-Hanna");
    if ((hanna?.chips as number[] | undefined)?.[correctIndex] !== HANNA_RICHTIG) {
      runde.probleme.push(`F${nr + 1}: Hanna hat nicht ${HANNA_RICHTIG} Chips richtig platziert`);
    }
    const zita = zeile("Zoeger-Zita");
    const zitaGesamt = ((zita?.chips as number[] | undefined) ?? []).reduce((s, c) => s + c, 0);
    if (zitaGesamt !== 1) {
      runde.probleme.push(`F${nr + 1}: Zita hält ${zitaGesamt} statt 1 Chip (Rücknahme-Bug?)`);
    }
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
