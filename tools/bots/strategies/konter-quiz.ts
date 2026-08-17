// Bot-Lauf Konter-Quiz: 4 Bots spielen EIN komplettes Duell (8 Blitz-Fragen)
// in Echtzeit gegen den echten Server.
//   · Konter-Kalle  (400 MM, Letzter ⇒ HERAUSFORDERER) — testet erst den
//                   Feiglings-Schutz (Zack ist geschützt!), fordert dann Doro
//                   (die Führende); Fragen 1–6 richtig (schnell), Frage 7
//                   FALSCH, Frage 8 STUMM (Schweigen ist gratis!)
//   · Duell-Doro    (2000 MM, die Führende) — Fragen 1–2 falsch, 3–8 richtig
//                   (immer langsamer als Kalle — kein Fotofinish)
//   · Zaungast-Zoe  (1200 MM) — versucht verbotenerweise mitzuraten
//                   (Zuschauer-Wache!) und prüft die Leak-Wachen
//   · Zaungast-Zack (800 MM, ärmster Zuschauer ⇒ Feiglings-Schutz)
// Erwartete Abrechnung (kqFrageDeltas als Single Source of Truth):
//   Kalle: 6×150 Bank − 1×150 Konter + 2×150 Gutschrift = +1050
//   Doro:  6×150 Bank − 2×150 Konter + 1×150 Gutschrift = +750
//   Zoe/Zack: ±0 — und der TRANSFER-Anteil ist EXAKT nullsummig.
// Punkte (Duell-Balken): Kalle 6 (immer schneller richtig), Doro 2 ⇒ Sieger.
//
// Aufruf: npx tsx tools/bots/strategies/konter-quiz.ts [--seed 15]
import { konterQuizPlugin } from "../../../server/minigames/konter-quiz/index";
import type { Question } from "../../../shared/content";
import { KQ_KONTER_MM, KQ_RICHTIG_MM, KQ_RUNDEN } from "../../../shared/minigames/konter-quiz.meta";
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
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  ["Wer wohnt im Dschungel?", ["Der Pinguin", "Der Affe", "Das Walross", "Der Elch"], 1],
  ["Was ist ein Konter?", ["Eine Gutschrift", "Ein Tanz", "Ein Hut", "Ein Fisch"], 0],
  ["Was kostet Schweigen?", ["Nichts", "150 MM", "Alles", "Eine Banane"], 0],
  ["Wer holt den Duell-Punkt?", ["Die schnellere richtige", "Niemand", "Beide", "Der GM"], 0],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `kq-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "easy",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Konter-Kalle", "Duell-Doro", "Zaungast-Zoe", "Zaungast-Zack"];
// Kalle ist der Letzte (Herausforderer), Doro die Führende, Zack der ärmste
// ZUSCHAUER (⇒ Feiglings-Schutz: nicht herausforderbar).
const STARTKAPITAL: Record<string, number> = {
  "Konter-Kalle": 400,
  "Duell-Doro": 2_000,
  "Zaungast-Zoe": 1_200,
  "Zaungast-Zack": 800,
};

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 15;
}

interface KqBotView {
  questionId?: string;
  frageNonce?: number;
  phase?: string;
  finished?: boolean;
  rundeNr?: number;
  herausforderer?: string;
  gegner?: string | null;
  punkte?: Record<string, number>;
  bilanz?: Record<string, number>;
  answeredCount?: number;
  options?: unknown;
  letzteRunde?: {
    transfer: Record<string, number>;
    bank: Record<string, number>;
    punktFuer: string | null;
  } | null;
  ergebnis?: {
    sieger: string | null;
    geteilt: boolean;
    vorzeitig: boolean;
    ohneTransfer: boolean;
    abgebrochen: boolean;
    punkte: Record<string, number>;
  } | null;
  duBistDuellant?: boolean;
  duBistHerausforderer?: boolean;
  waehlbareGegner?: { id: string; waehlbar: boolean }[] | null;
  correctIndex?: unknown;
  answers?: unknown;
  balances?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() für das ganze Duell — 8 Fragen injiziert.
  const server = await starteTestServer({ plugin: konterQuizPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "konter-quiz-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const kalleId = idVon.get("Konter-Kalle")!;
  const doroId = idVon.get("Duell-Doro")!;
  const zackId = idVon.get("Zaungast-Zack")!;

  // ---------- GM verteilt Startkapital in der Lobby (Zwischenstand-Basis) ----------
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
  runde.log("Startkapital: Kalle 400 (Letzter!), Doro 2000, Zoe 1200, Zack 800 MM");

  // ---------- Beobachtungs-Sammler (Beweis-Grundlage) ----------
  let feiglingsSchutzGesehen = false; // Zack war im Wahl-Grid als NICHT wählbar markiert
  let gegnerWarZack = false;
  let maxAnswered = 0;
  let transferBeatGesehen = false; // Konter-Beat mit fliegender Gutschrift
  let konterSummeVerletzt = false; // Σ Transfer eines Beats ≠ 0

  runde.screen.onView((view) => {
    const mg = view.minigame?.view as KqBotView | null;
    if (!mg?.questionId || view.phase !== "frage") return;
    if (mg.phase === "konter" && mg.letzteRunde) {
      const summe = Object.values(mg.letzteRunde.transfer).reduce((a, b) => a + b, 0);
      if (summe !== 0) konterSummeVerletzt = true;
      if (Object.values(mg.letzteRunde.transfer).some((t) => t !== 0)) transferBeatGesehen = true;
    }
  });

  // ---------- Spieler-Bots ----------
  for (const { bot, playerId, name } of runde.spieler) {
    let herausgefordert = false;
    const beantwortet = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as KqBotView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;

      // LEAK-WACHEN: Lösung, Antwort-Details und Konto-Snapshot bleiben auf
      // dem Server; Zuschauer sehen im Frage-Fenster KEINE Antwort-Buttons.
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.answers !== undefined || mg.balances !== undefined) {
        runde.probleme.push(`${name}: Server-Interna (answers/balances) leaken!`);
      }
      if (
        mg.phase === "frage" &&
        mg.duBistDuellant !== true &&
        mg.options !== null &&
        mg.options !== undefined
      ) {
        runde.probleme.push(`${name}: Zuschauer sieht Antwort-Optionen!`);
      }
      maxAnswered = Math.max(maxAnswered, mg.answeredCount ?? 0);
      if (mg.gegner === zackId) gegnerWarZack = true;
      if (mg.finished) return;

      // 1) GEGNER-WAHL (nur Kalle): erst der Feiglings-Schutz-Test (Zack,
      //    muss abprallen), dann die echte Herausforderung (Doro).
      if (mg.phase === "herausforderung" && name === "Konter-Kalle" && !herausgefordert) {
        herausgefordert = true;
        const zack = (mg.waehlbareGegner ?? []).find((k) => k.id === zackId);
        if (mg.duBistHerausforderer !== true) {
          runde.probleme.push("Kalle (Letzter) ist NICHT der Herausforderer!");
        }
        if (zack !== undefined && !zack.waehlbar) feiglingsSchutzGesehen = true;
        void (async () => {
          await delay(400);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "herausfordern",
            payload: { targetId: zackId },
            idemKey: `${playerId}-fordere-zack`,
          });
          runde.log("Kalle versucht den geschützten Zack zu fordern (muss abprallen)");
          await delay(600);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "herausfordern",
            payload: { targetId: doroId },
            idemKey: `${playerId}-fordere-doro`,
          });
          runde.log("Kalle fordert Doro (die Führende) zum Konter-Quiz! ⚔️");
        })();
      }

      // 2) SPEED-FRAGEN: Kalle 1–6 richtig (schnell), 7 falsch, 8 STUMM;
      //    Doro 1–2 falsch, 3–8 richtig (langsamer); Zoe versucht
      //    verbotenerweise mitzuraten (Zuschauer-Wache).
      const nonce = mg.frageNonce ?? 0;
      if (mg.phase === "frage" && !beantwortet.has(nonce)) {
        beantwortet.add(nonce);
        const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        const rundeNr = mg.rundeNr ?? 0;
        if (name === "Konter-Kalle") {
          if (rundeNr === KQ_RUNDEN) {
            runde.log("Kalle bleibt bei Frage 8 STUMM (Schweigen ist gratis)");
            return;
          }
          const choice = rundeNr === 7 ? (korrekt + 1) % 4 : korrekt;
          void (async () => {
            await delay(400);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice },
              idemKey: `${playerId}-n${nonce}-answer`,
            });
          })();
        } else if (name === "Duell-Doro") {
          const choice = rundeNr <= 2 ? (korrekt + 1) % 4 : korrekt;
          void (async () => {
            await delay(1_300); // deutlich langsamer — kein Fotofinish
            await sende(bot, "player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice: choice as number },
              idemKey: `${playerId}-n${nonce}-answer`,
            });
          })();
        } else if (name === "Zaungast-Zoe") {
          void (async () => {
            await delay(700);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice: korrekt },
              idemKey: `${playerId}-n${nonce}-answer`,
            });
          })();
        }
      }
    });
  }

  // Ein Duell = Wahl + Countdown + 8×(Frage/Konter) + Ergebnis.
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: EXAKTE Abrechnung + Nullsummen-Invarianten ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Duell), gesehen: ${runde.aufloesungen.length}`);
  }
  const a = runde.aufloesungen[0];
  if (a !== undefined) {
    const mg = a.mgView as KqBotView;
    const e = mg.ergebnis;
    if (e?.sieger !== kalleId || e?.geteilt !== false) {
      runde.probleme.push(`Duell-Ausgang falsch: sieger=${String(e?.sieger)}`);
    }
    // Punkte-Balken: Kalle 6 (immer schneller richtig), Doro 2 (Fragen 7+8).
    if (e?.punkte?.[kalleId] !== 6 || e?.punkte?.[doroId] !== 2) {
      runde.probleme.push(`Punkte falsch: ${JSON.stringify(e?.punkte)} (erwartet 6:2)`);
    }
    // Erwartete Deltas (kqFrageDeltas-Mathe): Kalle +1050, Doro +750, Rest 0.
    const erwartet: Record<string, number> = {
      [kalleId]: 6 * KQ_RICHTIG_MM - 1 * KQ_KONTER_MM + 2 * KQ_KONTER_MM,
      [doroId]: 6 * KQ_RICHTIG_MM - 2 * KQ_KONTER_MM + 1 * KQ_KONTER_MM,
    };
    for (const r of a.perPlayer) {
      if (r.delta !== (erwartet[r.playerId] ?? 0)) {
        runde.probleme.push(
          `Delta falsch: ${r.playerId} hat ${r.delta}, erwartet ${erwartet[r.playerId] ?? 0}`,
        );
      }
    }
    // Duell-Nullsumme: Σ aller Deltas = NUR die Bank-Prämien (12 Richtige).
    const summe = a.perPlayer.reduce((s, r) => s + r.delta, 0);
    if (summe !== 12 * KQ_RICHTIG_MM) {
      runde.probleme.push(`Σ aller Deltas ${summe} ≠ Bank-Summe ${12 * KQ_RICHTIG_MM}`);
    }
    runde.log(
      `Abrechnung exakt: Kalle +${erwartet[kalleId]} (900 Bank − 150 Konter + 300 Gutschrift), ` +
        `Doro +${erwartet[doroId]} — Transfer-Anteil nullsummig ✓`,
    );
  }
  if (!feiglingsSchutzGesehen) {
    runde.probleme.push("Feiglings-Schutz nie gesehen (Zack war im Wahl-Grid wählbar?)");
  }
  if (gegnerWarZack) {
    runde.probleme.push("Feiglings-Schutz durchbrochen: Zack wurde Duell-Partner!");
  }
  if (konterSummeVerletzt) {
    runde.probleme.push("Konter-Beat mit NICHT-nullsummigem Transfer gesehen!");
  }
  if (!transferBeatGesehen) {
    runde.probleme.push("Nie einen Konter-Beat mit fliegender Gutschrift gesehen");
  } else {
    runde.log("Konter-Gutschriften flogen sichtbar — jede Frage Σ Transfer = 0 ✓");
  }
  if (maxAnswered > 2) {
    runde.probleme.push(`Zuschauer-Wache verletzt: ${maxAnswered} Antworten (max. 2 Duellanten)`);
  } else {
    runde.log(`Zuschauer-Wache hält: Zoes Rate-Versuche wurden ignoriert (max ${maxAnswered}/2) ✓`);
  }

  stopPolling();
  pruefeKontoKorridor(runde, gmAnpassungen);
  beende(server, runde);
}

void main();
