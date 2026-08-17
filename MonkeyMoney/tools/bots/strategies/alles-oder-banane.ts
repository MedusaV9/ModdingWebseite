// Bot-Lauf Alles oder Banane: 4 Bots spielen die Wettrunde (4 Fragen à
// Setzen → Reveal → Frage) komplett in Echtzeit durch.
//   · Mutige-Mia      setzt IMMER „alles" (999.999 ⇒ Server klemmt), richtig
//   · Vorsichtige-Vera setzt das Minimum, richtig — DISCONNECTET in Frage 3
//     nach dem Einsatz (Erstattungs-Beweis) und kommt für Frage 4 zurück
//   · Zocker-Zoe      setzt hoch und tippt IMMER falsch (−Einsatz an die Bank)
//   · Sparsame-Selin  setzt NIE selbst (Auto-Minimum-Beweis), richtig
// Alle starten mit 0 MM ⇒ Frage 1 ist der Gratis-Einsatz-Beweis (Kredit der
// Affenbank: falsch kostet NICHTS, richtig zahlt +100). Der Lauf beweist die
// exakte ±Einsatz-Mathe, die Server-Klemme (50er-Raster, Kappe), Auto-Minimum,
// Erstattung bei Disconnect. Leak-Checks: Einsätze sind im Setz-Fenster GEHEIM,
// Frage-Text/-Optionen erscheinen erst im Frage-Fenster.
//
// Aufruf: npx tsx tools/bots/strategies/alles-oder-banane.ts [--seed 23]
import { allesOderBananePlugin } from "../../../server/minigames/alles-oder-banane/index";
import type { Question } from "../../../shared/content";
import { AOB_SCHRITT } from "../../../shared/minigames/alles-oder-banane.meta";
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
  ["Was liegt im Jackpot-Glas?", ["Sand", "Wasser", "Kekse", "MONKEY MONEY"], 3],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
  ["Wer wohnt im Dschungel?", ["Der Pinguin", "Der Affe", "Das Walross", "Der Elch"], 1],
  ["Wie viele Beine hat eine Spinne?", ["Sechs", "Acht", "Zehn", "Vier"], 1],
  ["Womit klettert der Affe?", ["Mit Lianen", "Leitern", "Aufzügen", "Raketen"], 0],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `aob-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "hard",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

interface Profil {
  name: string;
  /** null = nie selbst setzen (Auto-Minimum-Beweis). */
  einsatzWunsch: number | null;
  richtig: boolean;
}
const PROFILE: Profil[] = [
  { name: "Mutige-Mia", einsatzWunsch: 999_999, richtig: true },
  { name: "Vorsichtige-Vera", einsatzWunsch: 100, richtig: true },
  { name: "Zocker-Zoe", einsatzWunsch: 730, richtig: false }, // 730 ⇒ Raster-Klemme
  { name: "Sparsame-Selin", einsatzWunsch: null, richtig: true },
];
const FRAGEN_ZIEL = 4;
const VERA_DISCONNECT_BEI_FRAGE = 3; // 1-basiert: nach dem Einsatz von Frage 3

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 23;
}

interface AobBotView {
  questionId?: string;
  phase?: string;
  finished?: boolean;
  text?: string | null;
  options?: string[] | null;
  einsaetze?: unknown;
  yourEinsatz?: { betrag: number; gratis: boolean } | null;
  einsatzMax?: number;
  correctIndex?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({ plugin: allesOderBananePlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(
    server,
    PROFILE.map((p) => p.name),
    "aob-bots",
  );
  const stopPolling = starteSyncPolling(runde);

  const veraQuestionIds: string[] = []; // Frage-Reihenfolge aus Veras Sicht
  let veraOffline = false;

  // ---------- Spieler-Bots: setzen im Setz-Fenster, antworten im Frage-Fenster ----------
  for (let i = 0; i < PROFILE.length; i++) {
    const profil = PROFILE[i];
    const { bot, playerId } = runde.spieler[i];
    const gesetzt = new Set<string>();
    const beantwortet = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as AobBotView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const questionId = mg.questionId;
      // Plan-Position ≠ Plugin-Id im Injektions-Harness: die Id kommt aus dem View.
      const minigameId = view.minigame.id;

      // LEAK-CHECKS (§2.9): im Setz-Fenster sind Einsätze GEHEIM und die Frage
      // (Text + Optionen) noch auf dem Server; die Lösung sowieso.
      if (mg.phase === "setzen" || mg.phase === "reveal") {
        if (mg.phase === "setzen" && mg.einsaetze !== null && mg.einsaetze !== undefined) {
          runde.probleme.push(`${profil.name}: Einsätze leaken im Setz-Fenster!`);
        }
        if (typeof mg.text === "string" || Array.isArray(mg.options)) {
          runde.probleme.push(`${profil.name}: Frage leakt vor dem Frage-Fenster!`);
        }
      }
      if (!mg.finished && mg.correctIndex !== undefined) {
        runde.probleme.push(`${profil.name}: correctIndex leakt im Player-View!`);
      }
      if (mg.finished) return;

      // Frage-Reihenfolge für den Vera-Disconnect-Plan mitschreiben.
      if (i === 1 && !veraQuestionIds.includes(questionId)) veraQuestionIds.push(questionId);

      // 1) Setz-Fenster: Einsatz einloggen (außer Selin — Auto-Minimum-Beweis).
      if (
        mg.phase === "setzen" &&
        profil.einsatzWunsch !== null &&
        mg.yourEinsatz === null &&
        !gesetzt.has(questionId)
      ) {
        gesetzt.add(questionId);
        const betrag = profil.einsatzWunsch;
        void (async () => {
          await delay(400 + i * 200);
          const antwort = await sende(bot, "player.action", {
            minigameId,
            actionId: "einsatz",
            payload: { betrag },
            idemKey: `${playerId}-${questionId}-einsatz`,
          });
          if (antwort?.ok) runde.log(`${profil.name} setzt (Wunsch ${betrag} MM)`);
          // Vera-Drama: nach dem Einsatz von Frage 3 bricht die Verbindung ab.
          if (
            i === 1 &&
            veraQuestionIds.indexOf(questionId) === VERA_DISCONNECT_BEI_FRAGE - 1 &&
            !veraOffline
          ) {
            veraOffline = true;
            bot.socket.disconnect();
            runde.log("Vorsichtige-Vera verliert die Verbindung (geplant, nach Einsatz F3)");
          }
        })();
      }

      // 2) Frage-Fenster: antworten (Profil-Treffsicherheit).
      if (mg.phase === "frage" && Array.isArray(mg.options) && !beantwortet.has(questionId)) {
        beantwortet.add(questionId);
        const korrekt = ANTWORT.get(questionId.split("~")[0]) ?? 0;
        const choice = profil.richtig ? korrekt : (korrekt + 1) % 4;
        void (async () => {
          await delay(800 + i * 300);
          const antwort = await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-${questionId}-answer`,
          });
          if (antwort?.ok) {
            runde.log(`${profil.name} tippt ${profil.richtig ? "richtig" : "FALSCH"}`);
          }
        })();
      }
    });
  }

  // Vera-Reconnect: sobald Frage 3 aufgelöst ist, kommt sie für Frage 4 zurück.
  void (async () => {
    for (;;) {
      await delay(500);
      if (veraOffline && runde.aufloesungen.length >= VERA_DISCONNECT_BEI_FRAGE) {
        await runde.spieler[1].bot.wiederVerbinden();
        runde.log("Vorsichtige-Vera ist wieder da (Slot-Restore via Token)");
        return;
      }
      if (runde.aufloesungen.length >= FRAGEN_ZIEL) return;
    }
  })();

  await spieleBisEnde(runde, 90_000, { endeNachAufloesungen: FRAGEN_ZIEL });

  // ---------- Auswertung: exakte ±Einsatz-Mathe auf JEDER Auflösung ----------
  if (runde.aufloesungen.length < FRAGEN_ZIEL) {
    runde.probleme.push(
      `Erwartet ≥ ${FRAGEN_ZIEL} Auflösungen, gesehen: ${runde.aufloesungen.length}`,
    );
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const veraId = idVon.get("Vorsichtige-Vera") ?? "";
  for (const [nr, a] of runde.aufloesungen.entries()) {
    for (const r of a.perPlayer) {
      const einsatz = r.einsatz as number | null;
      const gratis = r.gratis === true;
      if (einsatz === null || einsatz === undefined) {
        runde.probleme.push(`${r.playerId}: Auflösung ohne Einsatz (Auto-Minimum-Bug?)`);
        continue;
      }
      // Server-Klemme: 50er-Raster, 100–1.000 (Mia „alles" ⇒ gekappt).
      if (einsatz % AOB_SCHRITT !== 0 || einsatz < 100 || einsatz > 1_000) {
        runde.probleme.push(`${r.playerId}: Einsatz ${einsatz} verletzt Raster/Grenzen`);
      }
      const erwartet =
        r.correct === true ? einsatz : r.correct === false ? (gratis ? 0 : -einsatz) : 0; // keine Antwort: hier nur via Disconnect/GM — erstattet ⇒ 0
      // Vera in Frage 3: KEINE Antwort (choice null), aber erstattet ⇒ Delta 0.
      if (r.playerId === veraId && nr === VERA_DISCONNECT_BEI_FRAGE - 1) {
        if (r.choice !== null || r.delta !== 0) {
          runde.probleme.push(
            `Erstattung verletzt: Vera F3 choice=${String(r.choice)} delta=${r.delta}`,
          );
        }
        continue;
      }
      if (r.delta !== erwartet) {
        runde.probleme.push(
          `${r.playerId} (F${nr + 1}): Delta ${r.delta} ≠ ${erwartet} ` +
            `(correct=${String(r.correct)}, einsatz=${einsatz}, gratis=${String(gratis)})`,
        );
      }
    }
  }
  // Gratis-Einsatz-Beweis: in Frage 1 (alle Konten 0) ist JEDER Einsatz ein Bank-Kredit.
  const f1 = runde.aufloesungen[0];
  if (f1 && !f1.perPlayer.every((r) => r.gratis === true)) {
    runde.probleme.push("Frage 1: nicht alle Einsätze gratis (Konto-Snapshot-Bug?)");
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
