// Bot-Lauf Risiko-Leiter: 4 Bots mit RISIKO-PERSÖNLICHKEITEN klettern EINE
// komplette 8-Stufen-Money-Leiter in Echtzeit gegen den echten Server.
//   · Gipfel-Greta (volles Risiko): IMMER weiterklettern, alle 8 Fragen
//                   richtig ⇒ Gipfel = 3.000 + 500 Jackpot-Bonus = +3.500
//   · Kasse-Kurt   (der Vorsichtige): klettert 4 Stufen richtig mit, macht
//                   im 5. Entscheidungs-Fenster KASSE ⇒ +700
//   · Zocker-Zorro (der Zocker): klettert 5 Stufen, verzockt sich auf
//                   Stufe 6 ⇒ Absturz auf die SICHERHEITSSTUFE 3 = +400
//   · Blitz-Bruno  (der Übermütige): patzt schon bei Stufe 1 ⇒ Absturz
//                   UNTER der Sicherheitsstufe = +0 — und testet danach als
//                   Zuschauer die Wachen (Antworten müssen abprallen)
// Erwartete Abrechnung (rlLeiterWert/rlAbsturzWert als Single Source of
// Truth): Greta +3500 · Kurt +700 · Zorro +400 · Bruno +0.
// Leak-Wachen im Lauf: KEIN Frage-Text im Entscheidungs-Fenster (der
// Guck-Exploit „erst Frage sehen, dann absichern" existiert nicht), KEIN
// correctIndex im Player-View, Zuschauer ohne Antwort-Draht.
//
// Aufruf: npx tsx tools/bots/strategies/risiko-leiter.ts [--seed 15]
import { risikoLeiterPlugin } from "../../../server/minigames/risiko-leiter/index";
import type { Question } from "../../../shared/content";
import {
  RL_JACKPOT_BONUS,
  RL_SICHERHEITSSTUFE,
  RL_STUFEN,
  rlLeiterWert,
} from "../../../shared/minigames/risiko-leiter.meta";
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

// 8 Stufen-Fragen mit steigender Schwierigkeit (init sortiert easy →
// ultrahard — die injizierte Reihenfolge IST bereits die Leiter-Reihenfolge).
const THEMEN: [string, string[], number, Question["difficulty"]][] = [
  ["Welche Farbe hat eine Banane?", ["Gelb", "Blau", "Karo", "Lila"], 0, "easy"],
  ["Wo klettern Affen?", ["Im Keller", "Auf Bäume", "Unter Wasser", "Im Büro"], 1, "easy"],
  ["Was ist die Sicherheitsstufe?", ["Stufe 3", "Stufe 8", "Stufe 1", "Keine"], 0, "medium"],
  ["Was bringt Absichern?", ["Nichts", "Eine Banane", "Den Leiter-Stand", "Ärger"], 2, "medium"],
  [
    "Was kostet Zögern?",
    ["Alles", "Nichts — wer zögert, klettert", "500", "Eine Runde"],
    1,
    "medium",
  ],
  ["Was passiert bei falsch?", ["Absturz", "Applaus", "Bonus", "Nichts"], 0, "hard"],
  ["Wie viele Stufen hat die Leiter?", ["Sechs", "Sieben", "Neun", "Acht"], 3, "hard"],
  [
    "Was wartet auf dem Gipfel?",
    ["Nebel", "3000 + Jackpot-Bonus", "Ein Krokodil", "Regen"],
    1,
    "ultrahard",
  ],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer, difficulty], i) => ({
  id: `rl-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty,
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Gipfel-Greta", "Kasse-Kurt", "Zocker-Zorro", "Blitz-Bruno"];

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 15;
}

interface RlBotView {
  questionId?: string;
  frageNonce?: number;
  phase?: string;
  finished?: boolean;
  stufeNr?: number;
  text?: unknown;
  options?: unknown;
  zuschauerOptionen?: unknown;
  answeredCount?: number;
  klettererCount?: number;
  leitern?: Record<
    string,
    { stufe: number; status: string; gutschrift: number | null; verbunden: boolean }
  >;
  duKletterst?: boolean;
  deineWahl?: string | null;
  ergebnis?: { uebersprungen: boolean; gipfelstuermer: string[] } | null;
  correctIndex?: unknown;
  answers?: unknown;
  antworten?: unknown;
  entscheidungen?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() für die ganze Leiter — 8 Stufen-Fragen injiziert.
  const server = await starteTestServer({ plugin: risikoLeiterPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "risiko-leiter-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const gretaId = idVon.get("Gipfel-Greta")!;
  const kurtId = idVon.get("Kasse-Kurt")!;
  const zorroId = idVon.get("Zocker-Zorro")!;
  const brunoId = idVon.get("Blitz-Bruno")!;

  // ---------- Beobachtungs-Sammler (Beweis-Grundlage) ----------
  let kurtKasseGesehen = false; // Kurts Absicherung sofort public (700 MM)
  let zorroAbsturzGesehen = false; // Zorro fällt auf die Sicherheitsstufe (400)
  let maxAnswered = 0;
  let maxKletterer = 0;

  runde.screen.onView((view) => {
    const mg = view.minigame?.view as RlBotView | null;
    if (!mg?.questionId || view.phase !== "frage") return;
    const kurt = mg.leitern?.[kurtId];
    if (kurt?.status === "abgesichert" && kurt.gutschrift === rlLeiterWert(4)) {
      kurtKasseGesehen = true;
    }
    const zorro = mg.leitern?.[zorroId];
    if (zorro?.status === "abgestuerzt" && zorro.gutschrift === rlLeiterWert(RL_SICHERHEITSSTUFE)) {
      zorroAbsturzGesehen = true;
    }
    maxAnswered = Math.max(maxAnswered, mg.answeredCount ?? 0);
    maxKletterer = Math.max(maxKletterer, mg.klettererCount ?? 0);
  });

  // ---------- Spieler-Bots (die Risiko-Persönlichkeiten) ----------
  for (const { bot, playerId, name } of runde.spieler) {
    const entschieden = new Set<string>();
    const beantwortet = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as RlBotView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;

      // LEAK-WACHEN: Lösung/Server-Interna bleiben auf dem Server; im
      // Entscheidungs-Fenster reist KEIN Frage-Text (Guck-Exploit-Wache).
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.answers !== undefined || mg.antworten !== undefined) {
        runde.probleme.push(`${name}: Server-Interna (answers) leaken!`);
      }
      if (mg.entscheidungen !== undefined) {
        runde.probleme.push(`${name}: fremde Entscheidungen leaken!`);
      }
      if (mg.phase === "entscheidung" && (mg.text !== null || mg.options !== null)) {
        runde.probleme.push(`${name}: Frage leakt VOR der Entscheidung (Guck-Exploit)!`);
      }
      if (mg.phase === "frage" && mg.duKletterst !== true && mg.options !== null) {
        runde.probleme.push(`${name}: Zuschauer hat Antwort-Draht (options)!`);
      }
      if (mg.finished) return;

      const stufe = mg.stufeNr ?? 0;

      // 1) ENTSCHEIDUNGS-FENSTER: die Persönlichkeiten wählen.
      if (mg.phase === "entscheidung" && mg.duKletterst === true && mg.deineWahl === null) {
        const key = `s${stufe}`;
        if (entschieden.has(key)) return;
        entschieden.add(key);
        // Kurt macht im 5. Fenster Kasse, alle anderen klettern immer weiter.
        const wahl = name === "Kasse-Kurt" && stufe === 5 ? "absichern" : "weiter";
        void (async () => {
          await delay(300);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "entscheidung",
            payload: { wahl },
            idemKey: `${playerId}-s${stufe}-entscheidung`,
          });
          if (wahl === "absichern") runde.log(`Kurt macht KASSE auf Stufe 4 (700 MM) 💰`);
        })();
        return;
      }

      // 2) STUFEN-FRAGE: richtig/falsch nach Drehbuch der Persönlichkeit.
      const nonce = mg.frageNonce ?? 0;
      if (mg.phase === "frage" && !beantwortet.has(nonce)) {
        beantwortet.add(nonce);
        const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        // Bruno (Zuschauer ab Stufe 2) testet die Zuschauer-Wache: sein
        // Rate-Versuch über den Draht MUSS abprallen.
        if (mg.duKletterst !== true) {
          if (name === "Blitz-Bruno") {
            void (async () => {
              await delay(400);
              await sende(bot, "player.action", {
                minigameId,
                actionId: "answer",
                payload: { choice: korrekt },
                idemKey: `${playerId}-n${nonce}-zuschauer`,
              });
            })();
          }
          return;
        }
        const falsch =
          (name === "Blitz-Bruno" && stufe === 1) || (name === "Zocker-Zorro" && stufe === 6);
        const choice = falsch ? (korrekt + 1) % 4 : korrekt;
        void (async () => {
          await delay(400 + (NAMEN.indexOf(name) + 1) * 150);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-n${nonce}-answer`,
          });
          if (falsch) runde.log(`${name} verzockt sich auf Stufe ${stufe} 🪂`);
        })();
      }
    });
  }

  // Eine Leiter = 8×(Entscheidung/Frage/Aufstieg) + Ergebnis.
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: EXAKTE Leiter-Abrechnung ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Leiter), gesehen: ${runde.aufloesungen.length}`);
  }
  const a = runde.aufloesungen[0];
  if (a !== undefined) {
    const mg = a.mgView as RlBotView;
    if (!(mg.ergebnis?.gipfelstuermer ?? []).includes(gretaId)) {
      runde.probleme.push("Greta fehlt unter den Gipfelstürmern!");
    }
    // Erwartete Deltas (rlLeiterWert/rlAbsturzWert-Mathe).
    const erwartet: Record<string, number> = {
      [gretaId]: rlLeiterWert(RL_STUFEN) + RL_JACKPOT_BONUS, // 3500
      [kurtId]: rlLeiterWert(4), // 700
      [zorroId]: rlLeiterWert(RL_SICHERHEITSSTUFE), // 400
      [brunoId]: 0,
    };
    for (const r of a.perPlayer) {
      if (r.delta !== (erwartet[r.playerId] ?? 0)) {
        runde.probleme.push(
          `Delta falsch: ${r.playerId} hat ${r.delta}, erwartet ${erwartet[r.playerId] ?? 0}`,
        );
      }
    }
    runde.log(
      `Abrechnung exakt: Greta +${erwartet[gretaId]} (Gipfel + Bonus) · Kurt +${erwartet[kurtId]} ` +
        `(Kasse Stufe 4) · Zorro +${erwartet[zorroId]} (Sicherheitsstufe) · Bruno +0 ✓`,
    );
  }
  if (!kurtKasseGesehen) {
    runde.probleme.push("Kurts Absicherung (700 MM) war nie public sichtbar");
  } else {
    runde.log("Kurts Kasse-Moment war sofort public auf den Leitern sichtbar ✓");
  }
  if (!zorroAbsturzGesehen) {
    runde.probleme.push("Zorros Absturz auf die Sicherheitsstufe war nie sichtbar");
  } else {
    runde.log("Zorros Absturz auf Stufe 3 (400 MM) war public sichtbar ✓");
  }
  if (maxAnswered > maxKletterer) {
    runde.probleme.push(
      `Zuschauer-Wache verletzt: ${maxAnswered} Antworten bei max. ${maxKletterer} Kletterern`,
    );
  } else {
    runde.log(`Zuschauer-Wache hält: Brunos Rate-Versuche prallten ab (${maxAnswered} max) ✓`);
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
