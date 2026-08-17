// Bot-Lauf Pixel-Dschungel: 4 Bots spielen die 4 Fragen der ersten Playlist-
// Runde komplett durch (danach beendet der GM das Match — Beweis im Kasten).
//   · Blitz-Bella   buzzert auf Stufe 1  (früh = Maximum, Risiko)
//   · Zoeger-Zoe    buzzert auf Stufe 4  (Mittelfeld)
//   · Wart-Willi    buzzert auf Stufe 7  (spät = Minimum, sicher)
//   · Raterich-Rudi buzzert auf Stufe 1, aber FALSCH (0 MM + Sperre)
// Der Lauf beweist die Verfalls-Kurve end-zu-end: Deltas liegen exakt auf der
// Jackpot-Treppe der gebuzzerten Stufe, und früh > mittel > spät.
// Antworten kennt der RUNNER aus seinen eigenen Fragen (nicht aus Spieler-
// Views — der Lauf prüft im Gegenteil, dass Views NIE correctIndex leaken).
//
// Aufruf: npx tsx tools/bots/strategies/pixel-dschungel.ts [--seed 7]
import { pixelDschungelPlugin } from "../../../server/minigames/pixel-dschungel/index";
import type { Question } from "../../../shared/content";
import { PD_STUFE_MS, pdJackpotWert } from "../../../shared/minigames/pixel-dschungel.meta";
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

const FRAGEN: Question[] = [
  {
    id: "pd-bot-1",
    kind: "choice4",
    category: "tiere",
    difficulty: "medium",
    text: "Welches Tier versteckt sich im Pixel-Bild?",
    options: ["Ein Affe", "Ein Krokodil", "Ein Papagei", "Ein Faultier"],
    answer: 0,
    erklaerung: "Der Affenkopf ist das Platzhalter-Motiv Nummer eins.",
  },
  {
    id: "pd-bot-2",
    kind: "choice4",
    category: "essen",
    difficulty: "medium",
    text: "Welche Frucht wird hier enthüllt?",
    options: ["Eine Kokosnuss", "Eine Banane", "Eine Mango", "Eine Ananas"],
    answer: 1,
    erklaerung: "Die Banane — was sonst, bei MONKEY MONEY.",
  },
  {
    id: "pd-bot-3",
    kind: "choice4",
    category: "natur",
    difficulty: "hard",
    text: "Was steht am Strand im Pixel-Nebel?",
    options: ["Ein Leuchtturm", "Ein Liegestuhl", "Eine Palme", "Ein Sonnenschirm"],
    answer: 2,
    erklaerung: "Die Palme — das dritte Platzhalter-Motiv.",
  },
  {
    id: "pd-bot-4",
    kind: "choice4",
    category: "show",
    difficulty: "ultrahard",
    text: "Was zeigt das allerletzte Pixel-Bild?",
    options: ["Einen Tresor", "Ein Sofa", "Einen Kaktus", "Ein Jackpot-Glas"],
    answer: 3,
    erklaerung: "Das Jackpot-Glas — hier landet das Straf-Geld.",
  },
];
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

interface Profil {
  name: string;
  zielStufe: number;
  richtig: boolean;
}
const PROFILE: Profil[] = [
  { name: "Blitz-Bella", zielStufe: 1, richtig: true },
  { name: "Zoeger-Zoe", zielStufe: 4, richtig: true },
  { name: "Wart-Willi", zielStufe: 7, richtig: true },
  { name: "Raterich-Rudi", zielStufe: 1, richtig: false },
];

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 7;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({ plugin: pixelDschungelPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(
    server,
    PROFILE.map((p) => p.name),
    "pixel-dschungel-bots",
  );
  const stopPolling = starteSyncPolling(runde);

  // Jeder Bot spielt sein Stufen-Profil; Leak-Check läuft in jedem View mit.
  for (let i = 0; i < PROFILE.length; i++) {
    const profil = PROFILE[i];
    const { bot, playerId } = runde.spieler[i];
    const gespielt = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        finished?: boolean;
        correctIndex?: unknown;
        aufloesung?: unknown;
      } | null;
      if (!mg?.questionId || !view.minigame) return;
      // LEAK-CHECK: Spieler-Views dürfen die Lösung erst mit der Auflösung tragen.
      if (mg.correctIndex !== undefined && !mg.aufloesung) {
        runde.probleme.push(`${profil.name}: correctIndex leakt im Spieler-View!`);
      }
      if (view.phase !== "frage" || mg.finished || gespielt.has(mg.questionId)) return;
      const questionId = mg.questionId;
      const minigameId = view.minigame.id;
      gespielt.add(questionId);
      const korrekt = ANTWORT.get(questionId) ?? 0;
      const choice = profil.richtig ? korrekt : (korrekt + 1) % 4;
      // Stufen-Mitte anpeilen (Stufe s beginnt bei s·3000 ms): Netzwerk-Jitter
      // von wenigen ms kann die 1.500-ms-Mitte nicht aus der Stufe schieben.
      const wartezeit = profil.zielStufe * PD_STUFE_MS + PD_STUFE_MS / 2;
      void (async () => {
        await delay(wartezeit);
        const antwort = await sende(bot, "player.action", {
          minigameId,
          actionId: "answer",
          payload: { choice },
          idemKey: `${playerId}-${questionId}-answer`,
        });
        if (!antwort?.ok) {
          runde.probleme.push(`${profil.name}: answer abgelehnt (${String(antwort?.error)})`);
          return;
        }
        runde.log(
          `${profil.name} buzzert ${questionId} auf Ziel-Stufe ${profil.zielStufe} ` +
            `(${profil.richtig ? "richtig" : "absichtlich falsch"})`,
        );
      })();
    });
  }

  await spieleBisEnde(runde, 60_000, { endeNachAufloesungen: FRAGEN.length });

  // ---------- Verfalls-Kurven-Beweis über die Auflösungen ----------
  if (runde.aufloesungen.length < FRAGEN.length) {
    runde.probleme.push(`Nur ${runde.aufloesungen.length}/${FRAGEN.length} Fragen aufgelöst`);
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  for (const a of runde.aufloesungen) {
    const frage = FRAGEN.find((f) => f.id === a.questionId);
    if (!frage) {
      runde.probleme.push(`Unbekannte Frage ${a.questionId} aufgelöst`);
      continue;
    }
    const deltaVon = new Map(a.perPlayer.map((r) => [r.playerId, r.delta]));
    const stufeVon = new Map(a.perPlayer.map((r) => [r.playerId, r.stufe as number | null]));
    for (const profil of PROFILE) {
      const id = idVon.get(profil.name)!;
      const delta = deltaVon.get(id) ?? NaN;
      if (!profil.richtig) {
        if (delta !== 0) {
          runde.probleme.push(`${a.questionId}: ${profil.name} falsch, aber Delta ${delta} ≠ 0`);
        }
        continue;
      }
      const stufe = stufeVon.get(id);
      if (stufe === null || stufe === undefined) {
        runde.probleme.push(`${a.questionId}: ${profil.name} ohne Stufen-Eintrag`);
        continue;
      }
      const erwartet = pdJackpotWert(frage.difficulty, stufe);
      if (delta !== erwartet) {
        runde.probleme.push(
          `${a.questionId}: ${profil.name} Delta ${delta} ≠ Treppe(${frage.difficulty}, Stufe ${stufe}) = ${erwartet}`,
        );
      }
      if (Math.abs(stufe - profil.zielStufe) > 1) {
        runde.probleme.push(
          `${a.questionId}: ${profil.name} landete auf Stufe ${stufe} (Ziel ${profil.zielStufe})`,
        );
      }
    }
    const bella = deltaVon.get(idVon.get("Blitz-Bella")!) ?? 0;
    const zoe = deltaVon.get(idVon.get("Zoeger-Zoe")!) ?? 0;
    const willi = deltaVon.get(idVon.get("Wart-Willi")!) ?? 0;
    if (!(bella > zoe && zoe > willi)) {
      runde.probleme.push(
        `${a.questionId}: Verfall verletzt — früh ${bella} > mittel ${zoe} > spät ${willi} gilt nicht`,
      );
    } else {
      runde.log(
        `${a.questionId} (${frage.difficulty}): Verfall bewiesen — ${bella} > ${zoe} > ${willi} MM ✓`,
      );
    }
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
