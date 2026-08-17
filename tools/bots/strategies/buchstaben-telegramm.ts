// Bot-Lauf 7-Buchstaben-Telegramm: 4 Bots (⇒ 2 Paare, 4 Beats, Rollen
// rotieren) spielen die Runde komplett durch. Der BESCHREIBER-BOT ist die
// Task-Vorgabe in Code: er tippt DETERMINISTISCH die ersten maxZeichen
// sinnvollen Zeichen des Begriffs (btHinweisAusTitel — ohne Leerzeichen/
// Sonderzeichen, Umlaute transliteriert) und sendet dann. Der RATE-BOT
// dekodiert das Telegramm ebenso deterministisch: er wählt die Option, deren
// Telegramm-Zeichenkette mit dem Hinweis beginnt (Präfix-Match).
// Der Lauf beweist end-zu-end: Koop-Prämie 250/250 je Erfolg, Budget-Abzug
// = Σ getippter Zeichen (Rest-Anzeige in der Auflösung), Paar-/Rollen-
// Rotation über 4 Beats — und die Leak-Wache: der BEGRIFF erscheint NIE im
// View eines Ratenden, answer/correctIndex nie in Spieler-Views.
//
// Aufruf: npx tsx tools/bots/strategies/buchstaben-telegramm.ts [--seed 7]
import { buchstabenTelegrammPlugin } from "../../../server/minigames/buchstaben-telegramm/index";
import type { Question } from "../../../shared/content";
import {
  BT_ERFOLG_MM,
  BT_MATCH_BUDGET,
  btHinweisAusTitel,
  btTelegrammZeichen,
} from "../../../shared/minigames/buchstaben-telegramm.meta";
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

// 4 Slot-Fragen ⇒ 4 Beats (2 Paare × 2 Auftritte — die Rollen rotieren).
const FRAGEN: Question[] = Array.from({ length: 4 }, (_, i) => ({
  id: `bt-slot-${i + 1}`,
  kind: "choice4",
  category: "show",
  difficulty: "medium",
  text: "Telegramm-Slot",
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: "Der Begriff kommt aus dem eingebauten Pool, nicht aus der Frage.",
}));

const NAMEN = ["Morse-Mia", "Rate-Rudi", "Telegraf-Theo", "Tipp-Tina"];

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 7;
}

interface BtHistorieEintrag {
  beatNr: number;
  beschreiber: string;
  ratende: string[];
  begriffText: string;
  art: string;
  hinweis: string;
  richtige: string[];
  falsche: string[];
  uebersprungen: boolean;
  praemieJe: number;
}

interface BtView {
  questionId?: string;
  beatNr?: number;
  phase?: "vorstellung" | "tippen" | "raten" | "aufdeckung";
  hinweis?: string;
  maxZeichen?: number;
  hinweisGesendet?: boolean;
  budget?: Record<string, number>;
  optionen?: string[] | null;
  duBistBeschreiber?: boolean;
  duBistRatender?: boolean;
  begriffText?: string | null;
  restBudget?: number;
  yourChoice?: number | null;
  historie?: BtHistorieEintrag[];
  finished?: boolean;
  aufloesung?: { perPlayer: { playerId: string; delta: number; restBudget?: number }[] } | null;
  answer?: unknown;
  correctIndex?: unknown;
  antworten?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({
    plugin: buchstabenTelegrammPlugin,
    fragen: FRAGEN,
    seed,
  });
  const runde = await spawneRunde(server, NAMEN, "telegramm-bots");
  const stopPolling = starteSyncPolling(runde);

  // ---------- Screen-Beobachter: Beat-Historie + Leak-Wache ----------
  const historie = new Map<number, BtHistorieEintrag>();
  runde.screen.onView((view) => {
    const mg = view.minigame?.view as BtView | null;
    for (const h of mg?.historie ?? []) historie.set(h.beatNr, h);
    if (mg && mg.phase !== "aufdeckung" && !mg.aufloesung && mg.begriffText !== undefined) {
      runde.probleme.push("Screen-View trägt den Begriff VOR der Aufdeckung!");
    }
    if (mg && mg.correctIndex !== undefined) {
      runde.probleme.push("Screen-View leakt correctIndex!");
    }
  });

  // ---------- Spieler-Bots: Beschreiber morst, Ratende dekodieren ----------
  const getippt = new Map<string, number>(); // playerId ⇒ Σ getippte Zeichen
  for (let i = 0; i < NAMEN.length; i++) {
    const name = NAMEN[i];
    const { bot, playerId } = runde.spieler[i];
    const beschrieben = new Set<number>();
    const geraten = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as BtView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame || mg.finished) return;
      const minigameId = view.minigame.id;
      const beatNr = mg.beatNr ?? 0;

      // LEAK-WACHE: der Begriff gehört NUR aufs Beschreiber-Handy.
      if (mg.duBistBeschreiber !== true && mg.phase !== "aufdeckung") {
        if (mg.begriffText !== undefined && mg.begriffText !== null) {
          runde.probleme.push(`${name}: Begriff leakt im Nicht-Beschreiber-View!`);
        }
      }
      if (mg.answer !== undefined || mg.correctIndex !== undefined || mg.antworten !== undefined) {
        runde.probleme.push(`${name}: answer/correctIndex/antworten leakt im Spieler-View!`);
      }

      // ---------- BESCHREIBER: erste maxZeichen sinnvolle Zeichen + senden ----------
      if (
        mg.duBistBeschreiber === true &&
        mg.phase === "tippen" &&
        mg.hinweisGesendet !== true &&
        typeof mg.begriffText === "string" &&
        !beschrieben.has(beatNr)
      ) {
        beschrieben.add(beatNr);
        const hinweis = btHinweisAusTitel(mg.begriffText, mg.maxZeichen ?? 0);
        getippt.set(playerId, (getippt.get(playerId) ?? 0) + hinweis.length);
        void (async () => {
          for (let z = 0; z < hinweis.length; z++) {
            await delay(120);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "buchstabe",
              payload: { zeichen: hinweis[z] },
              idemKey: `${playerId}-b${beatNr}-z${z}`,
            });
          }
          await delay(150);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "senden",
            payload: {},
            idemKey: `${playerId}-b${beatNr}-senden`,
          });
          runde.log(`${name} morst Beat ${beatNr}: „${hinweis}" (${hinweis.length} Zeichen) 📮`);
        })();
        return;
      }

      // ---------- RATENDE(R): Präfix-Match Hinweis ⇒ Option ----------
      if (
        mg.duBistRatender === true &&
        mg.phase === "raten" &&
        Array.isArray(mg.optionen) &&
        mg.yourChoice == null &&
        !geraten.has(beatNr)
      ) {
        geraten.add(beatNr);
        const hinweis = mg.hinweis ?? "";
        const optionen = mg.optionen;
        const treffer = optionen.findIndex(
          (o) => hinweis.length > 0 && btTelegrammZeichen(o).startsWith(hinweis),
        );
        const choice = treffer >= 0 ? treffer : 0;
        void (async () => {
          await delay(300 + i * 150);
          const antwort = await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-b${beatNr}-answer`,
          });
          if (!antwort?.ok) {
            runde.probleme.push(`${name}: answer abgelehnt (${String(antwort?.error)})`);
            return;
          }
          runde.log(`${name} dekodiert Beat ${beatNr}: „${hinweis}" ⇒ „${optionen[choice]}" 🔍`);
        })();
      }
    });
  }

  // roundBased: EINE Auflösung; Phase „frage" steht ~60 s am Stück.
  await spieleBisEnde(runde, 150_000, { endeNachAufloesungen: 1 });

  // ---------- Beweise: Koop-Prämie, Budget-Mathe, Rotation ----------
  const beats = [...historie.values()].sort((a, b) => a.beatNr - b.beatNr);
  if (beats.length !== FRAGEN.length) {
    runde.probleme.push(`Erwartet ${FRAGEN.length} Beats, gesehen: ${beats.length}`);
  }
  const erfolgVon = new Map<string, number>(); // playerId ⇒ Σ Soll-Prämien
  const beschreiberProSpieler = new Map<string, number>();
  for (const b of beats) {
    beschreiberProSpieler.set(b.beschreiber, (beschreiberProSpieler.get(b.beschreiber) ?? 0) + 1);
    if (b.uebersprungen) {
      runde.probleme.push(`Beat ${b.beatNr} wurde übersprungen (kein Disconnect geplant!)`);
      continue;
    }
    if (b.hinweis.length === 0 || b.hinweis.length > 8 || !/^[A-Z0-9]+$/.test(b.hinweis)) {
      runde.probleme.push(`Beat ${b.beatNr}: Hinweis „${b.hinweis}" verletzt die Telegramm-Regel`);
    }
    if (!btTelegrammZeichen(b.begriffText).startsWith(b.hinweis)) {
      runde.probleme.push(
        `Beat ${b.beatNr}: Hinweis „${b.hinweis}" ist kein Präfix von „${b.begriffText}"`,
      );
    }
    if (b.richtige.length === 0) {
      runde.probleme.push(
        `Beat ${b.beatNr}: Präfix-Dekoder scheiterte an „${b.begriffText}" (Hinweis „${b.hinweis}")`,
      );
      continue;
    }
    for (const r of b.richtige) erfolgVon.set(r, (erfolgVon.get(r) ?? 0) + BT_ERFOLG_MM);
    erfolgVon.set(b.beschreiber, (erfolgVon.get(b.beschreiber) ?? 0) + BT_ERFOLG_MM);
    runde.log(
      `Beat ${b.beatNr} („${b.begriffText}", ${b.art}): „${b.hinweis}" zugestellt ⇒ ` +
        `je +${BT_ERFOLG_MM} MM für Paar ✓`,
    );
  }
  // Rollen-Rotation: bei 4 Spielern/4 Beats beschreibt JEDER genau einmal.
  for (const { playerId, name } of runde.spieler) {
    if ((beschreiberProSpieler.get(playerId) ?? 0) !== 1) {
      runde.probleme.push(
        `${name} beschrieb ${beschreiberProSpieler.get(playerId) ?? 0}× (erwartet 1× — Rotation!)`,
      );
    }
  }
  // Auflösung: Deltas = Soll-Prämien, Rest-Budget = 60 − Σ getippte Zeichen.
  for (const a of runde.aufloesungen) {
    for (const r of a.perPlayer) {
      const sollDelta = erfolgVon.get(r.playerId) ?? 0;
      if (r.delta !== sollDelta) {
        runde.probleme.push(`${r.playerId}: Delta ${r.delta} ≠ Soll-Prämie ${sollDelta}`);
      }
      const sollRest = BT_MATCH_BUDGET - (getippt.get(r.playerId) ?? 0);
      if (r.restBudget !== sollRest) {
        runde.probleme.push(
          `${r.playerId}: Rest-Budget ${String(r.restBudget)} ≠ ${BT_MATCH_BUDGET} − getippt = ${sollRest}`,
        );
      }
    }
  }
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Runden-Auflösung, gesehen: ${runde.aufloesungen.length}`);
  } else {
    const budgets = runde.spieler
      .map((s) => `${s.name} ${BT_MATCH_BUDGET - (getippt.get(s.playerId) ?? 0)}`)
      .join(" · ");
    runde.log(`Budget-Bilanz (Rest von ${BT_MATCH_BUDGET}): ${budgets} ✓`);
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
