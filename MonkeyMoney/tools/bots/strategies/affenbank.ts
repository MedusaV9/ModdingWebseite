// Bot-Lauf Die Affenbank: 4 Bots spielen EIN komplettes Spiel (2 Durchgänge à
// 90 s Kette, 10-s-Schnellfeuer) in Echtzeit durch — die Money-Signatur-Runde.
//   · Streber-Sten    antwortet immer richtig, bankt NIE (Team-Player)
//   · Zocker-Zoe      antwortet richtig und drückt BANK! sobald der Pott ≥ 400
//   · Nachzügler-Nino antwortet richtig und springt in ZOES 1-s-Sammelfenster
//   · Schnarch-Sami   antwortet richtig — und DISCONNECTET bei t=100 s (D2)
// Der Lauf beweist: die Kette wächst nur bei Mehrheits-Treffern (50→…→1.600),
// BANK! sichert den Pott persönlich und reißt die Kette, alle Drücker im selben
// 1-s-Fenster sichern DENSELBEN Betrag, ungesicherte Pötte verbrennen am
// Durchgangs-Ende, und Offline-Spieler fallen aus der Mehrheits-Basis (die
// Kette wächst zu dritt weiter). Leak-Check: kein correctIndex im Player-View.
//
// Aufruf: npx tsx tools/bots/strategies/affenbank.ts [--seed 13]
import { affenbankPlugin } from "../../../server/minigames/affenbank/index";
import type { Question } from "../../../shared/content";
import { AB_KETTE, type AbHistorieEintrag } from "../../../shared/minigames/affenbank.meta";
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
  ["Wie viele Beine hat eine Spinne?", ["Sechs", "Acht", "Zehn", "Vier"], 1],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  ["Wer wohnt im Dschungel?", ["Der Pinguin", "Der Affe", "Das Walross", "Der Elch"], 1],
  ["Was liegt im Jackpot-Glas?", ["Sand", "MONKEY MONEY", "Wasser", "Kekse"], 1],
  ["Womit trommelt der Gorilla?", ["Mit Töpfen", "Mit Stöcken", "Mit den Fäusten", "Löffeln"], 2],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `ab-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "easy",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Streber-Sten", "Zocker-Zoe", "Nachzuegler-Nino", "Schnarch-Sami"];
const ZOE_BANKT_AB = 400; // Verrats-Schwelle: Pott ≥ 400 ⇒ BANK!
const SAMI_DISCONNECT_NACH_MS = 100_000; // mitten in Durchgang 2

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 13;
}

interface AbView {
  questionId?: string;
  frageNonce?: number;
  phase?: string;
  durchgang?: number;
  pott?: number;
  bankFenster?: { betrag: number; drueckerIds: string[] } | null;
  gebankt?: Record<string, number>;
  historie?: AbHistorieEintrag[];
  options?: string[] | null;
  finished?: boolean;
  correctIndex?: unknown;
  answers?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() für die ganze Runde — die Kette rotiert die Fragen.
  const server = await starteTestServer({ plugin: affenbankPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "affenbank-bots");
  const stopPolling = starteSyncPolling(runde);

  // ---------- Screen-Beobachter: volle Historie einsammeln (View slict auf 8) ----------
  const historie = new Map<string, AbHistorieEintrag>();
  let samiOfflineAbMs: number | null = null; // Spiel-Zeit (atMs), ab der Sami weg ist
  runde.screen.onView((view) => {
    const mg = view.minigame?.view as AbView | null;
    for (const h of mg?.historie ?? []) {
      historie.set(`${h.typ}:${h.playerId ?? "-"}:${h.atMs}:${h.durchgang}`, h);
    }
  });

  // ---------- Spieler-Bots ----------
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  for (let i = 0; i < NAMEN.length; i++) {
    const name = NAMEN[i];
    const { bot, playerId } = runde.spieler[i];
    const beantwortet = new Set<number>();
    let letzteBankNonce = -1;
    let ninoFenster = "";
    bot.onView((view) => {
      const mg = view.minigame?.view as AbView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      // LEAK-CHECKS: Lösung + fremde Antworten bleiben auf dem Server.
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.answers !== undefined) {
        runde.probleme.push(`${name}: answers-Map leakt im Player-View!`);
      }
      if (mg.finished || mg.phase !== "kette") return;
      // Plan-Position ≠ Plugin-Id im Injektions-Harness: die Id kommt aus dem View.
      const minigameId = view.minigame.id;

      // Antworten: EINMAL pro frageNonce (zyklisch rotierte Fragen sind NEU).
      const nonce = mg.frageNonce ?? 0;
      if (!beantwortet.has(nonce) && Array.isArray(mg.options)) {
        beantwortet.add(nonce);
        const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        void (async () => {
          await delay(600 + i * 250);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice: korrekt },
            idemKey: `${playerId}-n${nonce}-answer`,
          });
        })();
      }

      // Zocker-Zoe: der Verrats-Moment — Pott ≥ 400 ⇒ BANK!
      if (name === "Zocker-Zoe" && (mg.pott ?? 0) >= ZOE_BANKT_AB && letzteBankNonce !== nonce) {
        letzteBankNonce = nonce;
        const pott = mg.pott ?? 0;
        void (async () => {
          const antwort = await sende(bot, "player.action", {
            minigameId,
            actionId: "bank",
            payload: {},
            idemKey: `${playerId}-bank-n${nonce}`,
          });
          if (antwort?.ok) runde.log(`Zocker-Zoe drückt BANK! bei ${pott} MM (Verrat!)`);
        })();
      }

      // Nachzügler-Nino: springt in ein OFFENES Sammelfenster (1 s), in dem er fehlt.
      const fenster = mg.bankFenster;
      if (
        name === "Nachzuegler-Nino" &&
        fenster &&
        fenster.betrag > 0 &&
        !fenster.drueckerIds.includes(playerId)
      ) {
        const key = `${nonce}:${fenster.betrag}`;
        if (ninoFenster !== key) {
          ninoFenster = key;
          void (async () => {
            const antwort = await sende(bot, "player.action", {
              minigameId,
              actionId: "bank",
              payload: {},
              idemKey: `${playerId}-bank-${key}`,
            });
            if (antwort?.ok) {
              runde.log(`Nachzügler-Nino springt ins Sammelfenster (${fenster.betrag} MM)`);
            }
          })();
        }
      }
    });
  }

  // Sami-Disconnect bei t=100 s (Durchgang 2) — Mehrheits-Basis schrumpft auf 3.
  const samiTimer = setTimeout(() => {
    samiOfflineAbMs = 100_000;
    runde.spieler[3].bot.socket.disconnect();
    runde.log("Schnarch-Sami hat die Verbindung verloren (geplant, t=100 s)");
  }, SAMI_DISCONNECT_NACH_MS);

  // Ein Spiel = 2×90 s Kette + Pause — die Engine-Phase „frage" steht ~3 min.
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });
  clearTimeout(samiTimer);

  // ---------- Auswertung: Pott-Kette, Verrat, Sammelfenster, Offline-Basis ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Spiel), gesehen: ${runde.aufloesungen.length}`);
  }
  const eintraege = [...historie.values()].sort((a, b) => a.atMs - b.atMs);
  const gebankte = eintraege.filter((h) => h.typ === "gebankt");
  const kette = new Set<number>(AB_KETTE);
  for (const g of gebankte) {
    if (!kette.has(g.betrag)) {
      runde.probleme.push(`Gebankter Betrag ${g.betrag} liegt nicht auf der Kette ${AB_KETTE}`);
    }
  }
  // Deltas = Summe der persönlich gebankten Beträge (exakte Topf-Mathe).
  for (const a of runde.aufloesungen) {
    for (const r of a.perPlayer) {
      const erwartet = gebankte
        .filter((g) => g.playerId === r.playerId)
        .reduce((sum, g) => sum + g.betrag, 0);
      if (r.delta !== erwartet) {
        runde.probleme.push(`${r.playerId}: Delta ${r.delta} ≠ Σ gebankt ${erwartet}`);
      }
    }
  }
  const zoeId = idVon.get("Zocker-Zoe") ?? "";
  const ninoId = idVon.get("Nachzuegler-Nino") ?? "";
  const stenId = idVon.get("Streber-Sten") ?? "";
  const samiId = idVon.get("Schnarch-Sami") ?? "";
  const summe = (p: string): number =>
    gebankte.filter((g) => g.playerId === p).reduce((s, g) => s + g.betrag, 0);
  if (summe(zoeId) < ZOE_BANKT_AB) {
    runde.probleme.push(`Zoe hat nie ≥ ${ZOE_BANKT_AB} gebankt (${summe(zoeId)})`);
  }
  if (summe(ninoId) <= 0) {
    runde.probleme.push("Nino hat das 1-s-Sammelfenster nie erwischt");
  }
  // Sammelfenster-Beweis: JEDER Nino-Bank hat einen Zoe-Bank mit GLEICHEM Betrag ≤ 1 s davor.
  for (const n of gebankte.filter((g) => g.playerId === ninoId)) {
    const partner = gebankte.find(
      (z) =>
        z.playerId === zoeId &&
        z.betrag === n.betrag &&
        n.atMs - z.atMs <= 1_000 &&
        n.atMs >= z.atMs,
    );
    if (!partner) {
      runde.probleme.push(`Nino-Bank (${n.betrag} MM @${n.atMs}) ohne Zoe-Fenster davor`);
    }
  }
  if (summe(stenId) !== 0) runde.probleme.push(`Team-Player Sten hat gebankt: ${summe(stenId)}`);
  if (summe(samiId) !== 0) {
    runde.probleme.push(`Offline-Sami wurde etwas gutgeschrieben: ${summe(samiId)} (Auto-Bank?)`);
  }
  // Durchgangs-Dramaturgie: 2 Starts + mindestens 1 Verbrennen (Rest-Pott).
  const starts = eintraege.filter((h) => h.typ === "durchgang-start").length;
  if (starts !== 2) runde.probleme.push(`Erwartet 2 Durchgang-Starts, gesehen: ${starts}`);
  if (!eintraege.some((h) => h.typ === "verbrannt")) {
    runde.probleme.push("Kein einziger Pott verbrannt — Durchgangs-Ende-Regel nicht gesehen");
  }
  // Offline-Basis-Beweis: NACH Samis Abgang wächst die Kette zu dritt weiter.
  if (samiOfflineAbMs !== null) {
    const danach = eintraege.filter((h) => h.typ === "verdoppelt" && h.atMs > samiOfflineAbMs!);
    if (danach.length === 0) {
      runde.probleme.push("Nach Samis Disconnect kein Mehrheits-Treffer mehr (Basis-Bug?)");
    } else {
      runde.log(`${danach.length} Mehrheits-Treffer NACH Samis Disconnect (Basis = 3) ✓`);
    }
  }
  runde.log(
    `Historie: ${eintraege.length} Beats — ` +
      `${eintraege.filter((h) => h.typ === "verdoppelt").length}× verdoppelt, ` +
      `${gebankte.length}× gebankt, ` +
      `${eintraege.filter((h) => h.typ === "verbrannt").length}× verbrannt`,
  );

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
