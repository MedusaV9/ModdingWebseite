// Bot-Lauf Bananen-Bluff: 4 Bots spielen EINE komplette Bluff-Runde (4 Fragen,
// Verkünder-Rotation) in Echtzeit durch.
//   · Bluff-Bruno   verkündet als Verkünder einen BLUFF; als Rater glaubt er (WAHR)
//   · Ehrliche-Elif verkündet die WAHRHEIT; als Rater glaubt sie (WAHR)
//   · Glaubens-Lena verkündet die WAHRHEIT; als Rater glaubt sie IMMER (WAHR)
//   · Detektiv-Dodo verkündet einen BLUFF; als Rater ruft er IMMER GELOGEN
// Der Lauf beweist die Verkünder-Rotation (4 verschiedene Verkünder), die
// EXAKTEN Payoffs (aus der Aufdeckungs-Historie nachgerechnet: Transfers
// nullsummig, Prämien aus der Bank), mindestens 1 Ehrlichkeits-Prämie und
// 1 erfolgreichen Bluff. Leak-Wachen: die Wahrheit (correctIndex) sieht NUR
// der Verkünder im Verkünden-Fenster, Rater nie.
//
// Aufruf: npx tsx tools/bots/strategies/bananen-bluff.ts [--seed 11]
import {
  bananenBluffPlugin,
  type BbHistorieEintrag,
} from "../../../server/minigames/bananen-bluff/index";
import type { Question } from "../../../shared/content";
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
  id: `bbf-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "hard", // W = 500 ⇒ Prämie/Transfer 250
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));

interface Profil {
  name: string;
  /** Als Verkünder: die Wahrheit ansagen oder bluffen? */
  ehrlich: boolean;
  /** Als Rater: 0 = WAHR (glauben), 1 = GELOGEN (misstrauen). */
  urteil: 0 | 1;
}
const PROFILE: Profil[] = [
  { name: "Bluff-Bruno", ehrlich: false, urteil: 0 },
  { name: "Ehrliche-Elif", ehrlich: true, urteil: 0 },
  { name: "Glaubens-Lena", ehrlich: true, urteil: 0 },
  { name: "Detektiv-Dodo", ehrlich: false, urteil: 1 },
];

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 11;
}

interface BbfView {
  questionId?: string;
  phase?: string;
  finished?: boolean;
  duBistVerkuender?: boolean;
  options?: string[] | null;
  correctIndex?: number | null;
  yourChoice?: number | null;
  historie?: BbHistorieEintrag[];
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() für die ganze Runde — die Rotation braucht alle Fragen.
  const server = await starteTestServer({ plugin: bananenBluffPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(
    server,
    PROFILE.map((p) => p.name),
    "bbf-bots",
  );
  const stopPolling = starteSyncPolling(runde);

  // ---------- Screen-Beobachter: die volle Aufdeckungs-Historie einsammeln ----------
  const historie = new Map<string, BbHistorieEintrag>();
  runde.screen.onView((view) => {
    const mg = view.minigame?.view as BbfView | null;
    for (const h of mg?.historie ?? []) historie.set(h.questionId, h);
  });

  // ---------- Spieler-Bots: Verkünden (Profil) + Raten (Profil) ----------
  for (let i = 0; i < PROFILE.length; i++) {
    const profil = PROFILE[i];
    const { bot, playerId } = runde.spieler[i];
    const verkuendet = new Set<string>();
    const geraten = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as BbfView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const questionId = mg.questionId;
      const minigameId = view.minigame.id;

      // LEAK-WACHE: die Wahrheit sieht NUR der Verkünder im Verkünden-Fenster.
      if (mg.duBistVerkuender !== true && typeof mg.correctIndex === "number") {
        runde.probleme.push(`${profil.name}: correctIndex leakt an einen Rater!`);
      }
      if (mg.finished) return;

      // 1) VERKÜNDEN: Wahrheit oder Bluff je Profil (nur der Verkünder sieht options).
      if (
        mg.phase === "verkuenden" &&
        mg.duBistVerkuender === true &&
        Array.isArray(mg.options) &&
        typeof mg.correctIndex === "number" &&
        !verkuendet.has(questionId)
      ) {
        verkuendet.add(questionId);
        const wahrheit = mg.correctIndex;
        const choice = profil.ehrlich ? wahrheit : (wahrheit + 1) % 4;
        void (async () => {
          await delay(500);
          const antwort = await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-${questionId}-ansage`,
          });
          if (antwort?.ok) {
            runde.log(
              `${profil.name} verkündet ${profil.ehrlich ? "die WAHRHEIT" : "einen BLUFF"}`,
            );
          }
        })();
      }

      // 2) RATEN: WAHR/GELOGEN je Profil (Rater sehen die 2 Urteils-Optionen).
      if (
        mg.phase === "raten" &&
        mg.duBistVerkuender !== true &&
        Array.isArray(mg.options) &&
        mg.yourChoice === null &&
        !geraten.has(questionId)
      ) {
        geraten.add(questionId);
        void (async () => {
          await delay(600 + i * 200);
          const antwort = await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice: profil.urteil },
            idemKey: `${playerId}-${questionId}-urteil`,
          });
          if (antwort?.ok) {
            runde.log(`${profil.name} urteilt: ${profil.urteil === 0 ? "WAHR" : "GELOGEN"}`);
          }
        })();
      }
    });
  }

  // roundBased ⇒ EINE Auflösung am Runden-Ende (4 Fragen à 3 Beats).
  await spieleBisEnde(runde, 120_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: Payoffs aus der Historie EXAKT nachrechnen ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Runde), gesehen: ${runde.aufloesungen.length}`);
  }
  const beats = [...historie.values()];
  if (beats.length !== FRAGEN.length) {
    runde.probleme.push(`Erwartet ${FRAGEN.length} Aufdeckungs-Beats, gesehen: ${beats.length}`);
  }
  // Rotation: 4 Fragen ⇒ 4 VERSCHIEDENE Verkünder.
  const verkuenderIds = new Set(beats.map((b) => b.verkuender));
  if (verkuenderIds.size !== PROFILE.length) {
    runde.probleme.push(`Rotation verletzt: nur ${verkuenderIds.size} verschiedene Verkünder`);
  }
  // Exakte Payoff-Nachrechnung: Transfers (nullsummig) + Bank-Prämien.
  const erwartet = new Map<string, number>();
  let bankPraemien = 0;
  const plus = (p: string, betrag: number) => erwartet.set(p, (erwartet.get(p) ?? 0) + betrag);
  for (const b of beats) {
    for (const p of [...b.durchschaut, ...b.glaeubige]) {
      plus(p, b.praemie);
      bankPraemien += b.praemie;
    }
    for (const p of b.reingefallen) {
      plus(p, -b.praemie);
      plus(b.verkuender, b.praemie); // Nullsummen-Transfer an den Lügner
    }
    if (b.ehrlichkeitsPraemie) {
      plus(b.verkuender, b.praemie);
      bankPraemien += b.praemie;
    }
  }
  const a = runde.aufloesungen[0];
  let summe = 0;
  for (const r of a?.perPlayer ?? []) {
    summe += r.delta;
    const soll = erwartet.get(r.playerId) ?? 0;
    if (r.delta !== soll) {
      runde.probleme.push(`${r.playerId}: Delta ${r.delta} ≠ nachgerechnet ${soll}`);
    }
  }
  // Invariante: Σ Deltas === Σ Bank-Prämien (alle Transfers heben sich auf).
  if (summe !== bankPraemien) {
    runde.probleme.push(
      `Nullsummen-Invariante verletzt: Σ ${summe} ≠ Bank-Prämien ${bankPraemien}`,
    );
  }
  // Dramaturgie-Beweise: mind. 1 Ehrlichkeits-Prämie + 1 erfolgreicher Bluff.
  if (!beats.some((b) => b.ehrlichkeitsPraemie)) {
    runde.probleme.push("Keine Ehrlichkeits-Prämie gesehen (Mehrheits-Glaube-Pfad fehlt)");
  }
  if (!beats.some((b) => !b.wahrheit && b.reingefallen.length > 0)) {
    runde.probleme.push("Kein erfolgreicher Bluff gesehen (Transfer-Pfad fehlt)");
  }
  runde.log(
    `Historie: ${beats.length} Beats — ` +
      `${beats.filter((b) => b.wahrheit).length}× Wahrheit, ` +
      `${beats.filter((b) => !b.wahrheit).length}× Bluff, ` +
      `Σ Deltas ${summe} = Bank-Prämien ${bankPraemien} ✓`,
  );

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
