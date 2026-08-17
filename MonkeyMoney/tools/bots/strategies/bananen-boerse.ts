// Bot-Lauf Bananen-Börse: 4 Bots handeln 2 Börsen-Fragen in Echtzeit durch.
//   · Fruehe-Frida  kauft die richtige Option SOFORT (Block 0 ⇒ Quote 3,0)
//   · Herden-Hugo   kauft dieselbe Option erst in Block 1 — die Herden-Quote
//                   ist dann GEDRÜCKT (< 3,0): der Herdenverhalten-Beweis
//   · Panik-Paula   kauft FALSCH, VERKAUFT (Spread!) und schichtet in Block 1
//                   auf die richtige Option um (kaufen/halten/verkaufen)
//   · Halte-Hektor  kauft falsch und hält stur bis zum Börsenschluss (−E)
// Der Lauf beweist die EXAKTE Abrechnung delta = (richtig ? gewinn(E, quote)
// : −E) − verkaeufe × spread auf jeder Auflösung, die eingefrorenen Quoten
// und die Leak-Wache (kein correctIndex im Player-View vor dem Schluss).
//
// Aufruf: npx tsx tools/bots/strategies/bananen-boerse.ts [--seed 17]
import { bananenBoersePlugin } from "../../../server/minigames/bananen-boerse/index";
import type { Question } from "../../../shared/content";
import {
  BOERSE_QUOTE_START,
  boerseGewinn,
  boerseSpreadVerlust,
} from "../../../shared/minigames/bananen-boerse.meta";
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
  ["Welche Aktie steigt heute?", ["Banana Inc", "Kokos AG", "Liane SE", "Palme KG"], 0],
  ["Was frisst ein Affe am liebsten?", ["Steine", "Bananen", "Autos", "Wolken"], 1],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `brs-bot-${i + 1}`,
  kind: "choice4",
  category: "boerse",
  difficulty: "hard", // W = 500 ⇒ Einsatz E = 250, Spread 60
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Fruehe-Frida", "Herden-Hugo", "Panik-Paula", "Halte-Hektor"];
const FRAGEN_ZIEL = 2;
const BLOCK1_DELAY_MS = 6_200; // sicher im Block 1 (Blöcke à 5 s)

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 17;
}

interface BrsView {
  questionId?: string;
  finished?: boolean;
  einsatz?: number;
  options?: string[] | null;
  yourPosition?: { option: number; quote: number } | null;
  kannVerkaufen?: boolean;
  correctIndex?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({ plugin: bananenBoersePlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "brs-bots");
  const stopPolling = starteSyncPolling(runde);

  let einsatz = 0; // aus dem View (hard ⇒ 250) — Basis der Exakt-Mathe
  const hugoQuoten: number[] = []; // Herden-Beweis: Hugos Kauf-Quoten < 3,0

  // ---------- Spieler-Bots: 4 Parkett-Profile ----------
  for (let i = 0; i < NAMEN.length; i++) {
    const name = NAMEN[i];
    const { bot, playerId } = runde.spieler[i];
    const gehandelt = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as BrsView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const questionId = mg.questionId;
      const minigameId = view.minigame.id;

      // LEAK-WACHE: die Lösung bleibt bis zum Börsenschluss auf dem Server.
      if (!mg.finished && mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.finished || gehandelt.has(questionId)) return;
      gehandelt.add(questionId);
      if (typeof mg.einsatz === "number") einsatz = mg.einsatz;

      const korrekt = ANTWORT.get(questionId.split("~")[0]) ?? 0;
      const falsch = (korrekt + 1) % 4;
      const kaufe = async (choice: number, idem: string): Promise<boolean> => {
        const antwort = await sende(bot, "player.action", {
          minigameId,
          actionId: "answer",
          payload: { choice },
          idemKey: `${playerId}-${questionId}-${idem}`,
        });
        return antwort?.ok === true;
      };
      void (async () => {
        if (name === "Fruehe-Frida") {
          await delay(400);
          if (await kaufe(korrekt, "kauf")) runde.log("Fruehe-Frida kauft SOFORT (Quote 3,0)");
        } else if (name === "Herden-Hugo") {
          await delay(BLOCK1_DELAY_MS);
          if (await kaufe(korrekt, "kauf")) {
            runde.log("Herden-Hugo kauft in Block 1 (Herden-Quote gedrückt)");
          }
        } else if (name === "Panik-Paula") {
          await delay(600);
          await kaufe(falsch, "fehlkauf");
          await delay(1_500);
          const verkauf = await sende(bot, "player.action", {
            minigameId,
            actionId: "verkaufen",
            payload: {},
            idemKey: `${playerId}-${questionId}-verkauf`,
          });
          if (verkauf?.ok) runde.log("Panik-Paula VERKAUFT (Spread) …");
          await delay(BLOCK1_DELAY_MS - 2_100);
          if (await kaufe(korrekt, "umschichtung")) {
            runde.log("… und schichtet auf die richtige Option um");
          }
        } else {
          await delay(900);
          if (await kaufe(falsch, "kauf")) runde.log("Halte-Hektor kauft falsch und HÄLT (−E)");
        }
      })();
    });
  }

  await spieleBisEnde(runde, 90_000, { endeNachAufloesungen: FRAGEN_ZIEL });

  // ---------- Auswertung: Abrechnungs-Formel EXAKT auf jeder Auflösung ----------
  if (runde.aufloesungen.length < FRAGEN_ZIEL) {
    runde.probleme.push(
      `Erwartet ≥ ${FRAGEN_ZIEL} Auflösungen, gesehen: ${runde.aufloesungen.length}`,
    );
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const spread = boerseSpreadVerlust(einsatz);
  for (const [nr, a] of runde.aufloesungen.entries()) {
    for (const r of a.perPlayer) {
      const quote = r.quote as number | null;
      const verkaeufe = (r.verkaeufe as number | undefined) ?? 0;
      const position =
        r.choice === null ? 0 : r.correct === true ? boerseGewinn(einsatz, quote ?? 0) : -einsatz;
      const soll = position - verkaeufe * spread;
      if (r.delta !== soll) {
        runde.probleme.push(
          `${r.playerId} (F${nr + 1}): Delta ${r.delta} ≠ Formel ${soll} ` +
            `(correct=${String(r.correct)}, quote=${String(quote)}, verkaeufe=${verkaeufe})`,
        );
      }
    }
    // Profil-Beweise pro Frage:
    const zeile = (spielerName: string) =>
      a.perPlayer.find((r) => r.playerId === idVon.get(spielerName));
    const frida = zeile("Fruehe-Frida");
    if (frida?.quote !== BOERSE_QUOTE_START || frida?.correct !== true) {
      runde.probleme.push(`F${nr + 1}: Frida ohne Start-Quote 3,0 (${String(frida?.quote)})`);
    }
    const paula = zeile("Panik-Paula");
    if (paula?.verkaeufe !== 1 || paula?.correct !== true) {
      runde.probleme.push(`F${nr + 1}: Paulas Umschichtung fehlt (verkaeufe/correct)`);
    }
    const hektor = zeile("Halte-Hektor");
    if (hektor?.correct !== false || hektor?.delta !== -einsatz) {
      runde.probleme.push(`F${nr + 1}: Hektor nicht exakt −E (${String(hektor?.delta)})`);
    }
    // Herden-Beweis: Hugos Block-1-Kauf-Quote ist GEDRÜCKT (Frida hält schon).
    const hugo = zeile("Herden-Hugo");
    if (typeof hugo?.quote === "number") hugoQuoten.push(hugo.quote);
  }
  if (hugoQuoten.length < FRAGEN_ZIEL) {
    runde.probleme.push(`Hugo hat nur ${hugoQuoten.length}/${FRAGEN_ZIEL} Käufe platziert`);
  }
  for (const q of hugoQuoten) {
    if (q >= BOERSE_QUOTE_START) {
      runde.probleme.push(`Herden-Quote nicht gedrückt: Hugo kaufte zu ×${q}`);
    }
  }
  runde.log(`Hugos Herden-Quoten: ${hugoQuoten.map((q) => `×${q}`).join(", ")} (alle < 3,0) ✓`);

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
