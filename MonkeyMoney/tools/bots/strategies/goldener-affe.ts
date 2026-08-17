// Bot-Lauf Der Goldene Affe: 4 Bots spielen das komplette 3-Stufen-Finale in
// Echtzeit gegen den echten Server (Money-Drop → Schätz-Showdown → Wetten →
// Buzzer-Best-of-3 → Krönung mit 20-%-Tribut).
//   · Finale-Fina  (1000 MM) — setzt alle 10 Chips auf die richtige Tür
//                  (+500), wird Finalistin (früheste Schätz-Abgabe) und holt
//                  im Buzzer-Finale 2 schnelle richtige Antworten (SIEGERIN)
//   · Zweite-Dora  (500 MM) — 5/5-Split (Drop ±0), Finalistin, buzzt FALSCH
//   · Wett-Waldo   (500 MM) — verzockt alle Chips auf die falsche Tür (−250),
//                  scheidet aus und wettet 50 MM auf Fina (RICHTIG ⇒ +100)
//   · Schätz-Susi  (500 MM) — 2/8-Split (−150), scheidet aus, wettet auf
//                  Dora (FALSCH ⇒ −50)
// Alle vier schätzen DENSELBEN Wert (eingabeMin) — die Finalisten-Plätze
// entscheidet die Abgabe-Reihenfolge (Distanz-Gleichstand ⇒ frühere Abgabe:
// Fina vor Dora vor Waldo vor Susi). Der Lauf beweist die EXAKTE Abrechnung
// aller drei Stufen (Drop-Mathe aus dem ECHTEN Konto, ×3-Wette, nullsummiger
// 20-%-Transfer der projizierten Konten) und die View-Leak-Wachen (Richtwert
// geheim, Buzzer-Optionen nur für Finalisten, Wetten geheim bis Wettschluss).
//
// Aufruf: npx tsx tools/bots/strategies/goldener-affe.ts [--seed 22]
import { goldenerAffePlugin } from "../../../server/minigames/goldener-affe/index";
import type { Question } from "../../../shared/content";
import {
  GA_WETTE_FAKTOR,
  GA_WETTE_MM,
  gaDropDelta,
  gaEinsatz,
  gaTransfer,
} from "../../../shared/minigames/goldener-affe.meta";
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
  ["Hinter welcher Tür liegt der Bananenschatz?", ["Nord", "Ost", "Süd", "West"], 2],
  ["Was frisst ein Affe am liebsten?", ["Bananen", "Steine", "Autos", "Wolken"], 0],
  ["Welche Farbe hat eine reife Banane?", ["Blau", "Gelb", "Lila", "Karo"], 1],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `ga-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "hard",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Finale-Fina", "Zweite-Dora", "Wett-Waldo", "Schaetz-Susi"];
const STARTKAPITAL: Record<string, number> = {
  "Finale-Fina": 1_000,
  "Zweite-Dora": 500,
  "Wett-Waldo": 500,
  "Schaetz-Susi": 500,
};
/** Chips pro Bot auf die RICHTIGE Tür (Rest wandert auf eine falsche). */
const CHIPS_RICHTIG: Record<string, number> = {
  "Finale-Fina": 10,
  "Zweite-Dora": 5,
  "Wett-Waldo": 0,
  "Schaetz-Susi": 2,
};
/** Schätz-Abgabe-Staffelung (ms): Distanz-Gleichstand ⇒ frühere Abgabe siegt. */
const SCHAETZ_VERZUG: Record<string, number> = {
  "Finale-Fina": 200,
  "Zweite-Dora": 800,
  "Wett-Waldo": 1_400,
  "Schaetz-Susi": 2_000,
};

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 22;
}

interface GaBotView {
  questionId?: string;
  frageNonce?: number;
  phase?: string;
  finished?: boolean;
  finalisten?: string[];
  ausgeschieden?: string[];
  punkte?: Record<string, number>;
  options?: string[] | null;
  zuschauerOptionen?: string[] | null;
  schaetz?: { richtwert: number | null; eingabeMin: number } | null;
  eingabeMin?: number;
  wetten?: Record<string, string> | null;
  dropErgebnis?: {
    correctIndex: number;
    chips: Record<string, number[]>;
    perPlayer: Record<string, { einsatz: number; gratis: boolean; delta: number }>;
  } | null;
  ergebnis?: {
    sieger: string | null;
    kampflos: boolean;
    abgebrochen: boolean;
    transferSumme: number;
  } | null;
  duBistFinalist?: boolean;
  duBistAusgeschieden?: boolean;
  correctIndex?: unknown;
  richtwert?: unknown;
  tipps?: unknown;
  balances?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() fürs ganze Finale (Drop-Frage + Buzzer-Serie).
  const server = await starteTestServer({ plugin: goldenerAffePlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "goldener-affe-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const finaId = idVon.get("Finale-Fina")!;
  const doraId = idVon.get("Zweite-Dora")!;
  const waldoId = idVon.get("Wett-Waldo")!;
  const susiId = idVon.get("Schaetz-Susi")!;

  // ---------- GM verteilt Startkapital (Einsatz- und Transfer-Basis!) ----------
  const gmAnpassungen = new Map<string, number>();
  for (const { playerId, name } of runde.spieler) {
    const delta = STARTKAPITAL[name];
    const ack = await runde.gm.emitAck("gm.cmd", {
      cmd: "score.adjust",
      args: { playerId, delta, grund: "startkapital-botlauf", override: true },
      cmdId: `kapital-${name}`,
    });
    if (!ack.ok) throw new Error(`Startkapital für ${name} abgelehnt: ${String(ack.error)}`);
    gmAnpassungen.set(playerId, delta);
  }
  runde.log("Startkapital: Fina 1000, Dora/Waldo/Susi je 500 MM (ECHTE Einsatz-Basis)");

  // ---------- Beobachtungs-Sammler ----------
  let richtwertGeheimGeprueft = false; // während des Schätzens war der Richtwert null
  let richtwertLeak = false;
  let zuschauerOptionenLeak = false; // Ausgeschiedene sahen options im Buzzer
  let wettenLeak = false; // Wetten sichtbar VOR Wettschluss

  // ---------- Spieler-Bots ----------
  for (let i = 0; i < NAMEN.length; i++) {
    const name = NAMEN[i];
    const { bot, playerId } = runde.spieler[i];
    let chipsGesetzt = false;
    let geschaetzt = false;
    let gewettet = false;
    const gebuzzert = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as GaBotView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;

      // LEAK-WACHEN: Lösungen/Richtwerte/Server-Interna bleiben auf dem Server.
      if (mg.correctIndex !== undefined || mg.richtwert !== undefined) {
        runde.probleme.push(`${name}: correctIndex/richtwert leakt im Player-View!`);
      }
      if (mg.balances !== undefined) {
        runde.probleme.push(`${name}: balances leaken im Player-View!`);
      }
      if (mg.phase === "schaetzen" && mg.schaetz) {
        richtwertGeheimGeprueft = true;
        if (mg.schaetz.richtwert !== null) richtwertLeak = true;
      }
      if (mg.phase === "wetten" && mg.wetten !== null && mg.wetten !== undefined) {
        wettenLeak = true;
      }
      if (mg.phase === "buzzer" && mg.duBistFinalist !== true && Array.isArray(mg.options)) {
        zuschauerOptionenLeak = true;
      }
      if (mg.finished) return;

      // STUFE 1: komplette Chip-Verteilung (letzter Stand zählt).
      if (mg.phase === "drop" && !chipsGesetzt && Array.isArray(mg.options)) {
        chipsGesetzt = true;
        const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        const richtig = CHIPS_RICHTIG[name];
        const verteilung = [0, 0, 0, 0];
        verteilung[korrekt] = richtig;
        verteilung[(korrekt + 1) % 4] = 10 - richtig;
        void (async () => {
          await delay(500 + i * 300);
          const ack = await sende(bot, "player.action", {
            minigameId,
            actionId: "chips",
            payload: { verteilung },
            idemKey: `${playerId}-chips`,
          });
          if (ack?.ok) runde.log(`${name} verteilt Chips: ${richtig} auf die richtige Tür`);
        })();
      }

      // STUFE 2: alle schätzen DENSELBEN Wert — die Reihenfolge entscheidet.
      if (mg.phase === "schaetzen" && !geschaetzt && typeof mg.eingabeMin === "number") {
        geschaetzt = true;
        const wert = mg.eingabeMin;
        void (async () => {
          await delay(SCHAETZ_VERZUG[name]);
          const ack = await sende(bot, "player.action", {
            minigameId,
            actionId: "einloggen",
            payload: { wert },
            idemKey: `${playerId}-schaetzung`,
          });
          if (ack?.ok) runde.log(`${name} loggt ${wert} ein (Staffel-Platz ${i + 1})`);
        })();
      }

      // WETT-BEAT: Waldo → Fina (richtig), Susi → Dora (falsch).
      if (
        mg.phase === "wetten" &&
        !gewettet &&
        mg.duBistAusgeschieden === true &&
        (name === "Wett-Waldo" || name === "Schaetz-Susi")
      ) {
        gewettet = true;
        const auf = name === "Wett-Waldo" ? finaId : doraId;
        void (async () => {
          await delay(name === "Wett-Waldo" ? 400 : 900);
          const ack = await sende(bot, "player.action", {
            minigameId,
            actionId: "wette",
            payload: { auf },
            idemKey: `${playerId}-wette`,
          });
          if (ack?.ok) {
            runde.log(
              `${name} wettet ${GA_WETTE_MM} MM auf ${auf === finaId ? "Fina" : "Dora"} (×${GA_WETTE_FAKTOR})`,
            );
          }
        })();
      }

      // STUFE 3: Fina buzzt richtig (schnell), Dora falsch (langsamer).
      const nonce = mg.frageNonce ?? 0;
      if (
        mg.phase === "buzzer" &&
        mg.duBistFinalist === true &&
        Array.isArray(mg.options) &&
        !gebuzzert.has(nonce)
      ) {
        gebuzzert.add(nonce);
        const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        const choice = name === "Finale-Fina" ? korrekt : (korrekt + 1) % 4;
        void (async () => {
          await delay(name === "Finale-Fina" ? 400 : 900);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-n${nonce}-answer`,
          });
        })();
      }
    });
  }

  // Ein Finale = Drop + Schätzen + Wetten + 2 Buzzer-Fragen + Krönung
  // (~60 s Echtzeit mit Früh-Schlüssen) — die Engine-Phase „frage" steht dabei.
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: EXAKTE 3-Stufen-Abrechnung ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Finale), gesehen: ${runde.aufloesungen.length}`);
  }
  const a = runde.aufloesungen[0];
  if (a !== undefined) {
    const mg = a.mgView as GaBotView;
    if (mg.ergebnis?.sieger !== finaId) {
      runde.probleme.push(`Siegerin falsch: ${String(mg.ergebnis?.sieger)} ≠ Fina`);
    }
    if (
      JSON.stringify([...(mg.finalisten ?? [])].sort()) !== JSON.stringify([doraId, finaId].sort())
    ) {
      runde.probleme.push(
        `Finalisten falsch: ${JSON.stringify(mg.finalisten)} (Staffel-Reihenfolge?)`,
      );
    }
    // Erwartete Deltas aus den geteilten Helfern (Single Source of Truth):
    // Drop aus dem ECHTEN Konto, ×3-Wette, dann 20 % der PROJIZIERTEN Konten.
    const drop: Record<string, number> = {};
    for (const { playerId, name } of runde.spieler) {
      drop[playerId] = gaDropDelta(gaEinsatz(STARTKAPITAL[name]), CHIPS_RICHTIG[name]);
    }
    const wett: Record<string, number> = {
      [finaId]: 0,
      [doraId]: 0,
      [waldoId]: GA_WETTE_MM * (GA_WETTE_FAKTOR - 1), // auf Fina: richtig
      [susiId]: -GA_WETTE_MM, // auf Dora: falsch
    };
    const erwartet: Record<string, number> = {};
    let transferSumme = 0;
    for (const { playerId, name } of runde.spieler) {
      if (playerId === finaId) continue;
      const projektion = STARTKAPITAL[name] + drop[playerId] + wett[playerId];
      const transfer = gaTransfer(projektion);
      erwartet[playerId] = drop[playerId] + wett[playerId] - transfer;
      transferSumme += transfer;
    }
    erwartet[finaId] = drop[finaId] + wett[finaId] + transferSumme;
    for (const r of a.perPlayer) {
      if (r.delta !== erwartet[r.playerId]) {
        runde.probleme.push(
          `Delta falsch: ${r.playerId} hat ${r.delta}, erwartet ${erwartet[r.playerId]}`,
        );
      }
    }
    // Nullsummen-Invariante des Tributs: Siegerin bekommt EXAKT die Summe.
    if (mg.ergebnis?.transferSumme !== transferSumme) {
      runde.probleme.push(
        `Tribut-Summe im View ${String(mg.ergebnis?.transferSumme)} ≠ berechnet ${transferSumme}`,
      );
    }
    // Drop-Abrechnung im View gegen die Meta-Helfer prüfen.
    for (const { playerId, name } of runde.spieler) {
      const d = mg.dropErgebnis?.perPlayer[playerId];
      const einsatz = gaEinsatz(STARTKAPITAL[name]);
      if (d?.einsatz !== einsatz.betrag || d?.delta !== drop[playerId]) {
        runde.probleme.push(
          `Drop-Abrechnung falsch für ${name}: ${JSON.stringify(d)} ≠ ` +
            `einsatz ${einsatz.betrag}, delta ${drop[playerId]}`,
        );
      }
    }
    runde.log(
      `Abrechnung exakt: Fina +${erwartet[finaId]} (Drop +${drop[finaId]} + Tribut ${transferSumme}), ` +
        `Dora ${erwartet[doraId]}, Waldo ${erwartet[waldoId]}, Susi ${erwartet[susiId]} ✓`,
    );
  }
  if (!richtwertGeheimGeprueft)
    runde.probleme.push("Schätz-Fenster nie in einem Player-View gesehen");
  if (richtwertLeak) runde.probleme.push("Richtwert leakt WÄHREND des Schätzens!");
  if (wettenLeak) runde.probleme.push("Wetten leaken VOR Wettschluss!");
  if (zuschauerOptionenLeak) {
    runde.probleme.push(
      "Buzzer-Optionen leaken an Ausgeschiedene (options statt zuschauerOptionen)!",
    );
  }

  stopPolling();
  pruefeKontoKorridor(runde, gmAnpassungen);
  beende(server, runde);
}

void main();
