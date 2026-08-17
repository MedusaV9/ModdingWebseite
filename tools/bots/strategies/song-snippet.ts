// Bot-Lauf „Der Blitz-DJ": 3 Bots spielen 3 Songs (rotierender Fixture-Pack
// via sliceExtras — genau der songs-Slice-Vertrag des Song-Pack-Loaders).
//   · Falsch-Fred  buzzert auf Stufe 1 (0,1 s) und rät FALSCH
//                  ⇒ Sperre für den Song + 50 MM Strafe ins Jackpot-Glas
//   · Blitz-Bella  buzzert auf Stufe 2 (0,2 s) und rät RICHTIG
//                  ⇒ holt den Song zum Stufe-2-Wert (Treppe bewiesen)
//   · Zoeger-Zoe   buzzert NIE ⇒ 0 MM
// Der Lauf beweist end-zu-end: Eskalation nach Falsch-Buzz, Verfalls-Treppe
// (Stufe-2-Wert < Startwert), Sperre, Strafe ins Glas — und dass Player-Views
// NIE correctIndex/Titel tragen (der Runner spickt beim GM-View, nie beim
// Spieler-View).
//
// Aufruf: npx tsx tools/bots/strategies/song-snippet.ts [--seed 7]
import { songSnippetPlugin } from "../../../server/minigames/song-snippet/index";
import type { Question } from "../../../shared/content";
import { SS_STRAFE_MM, ssStufenWert } from "../../../shared/minigames/song-snippet.meta";
import type { Schwierigkeit } from "../../../shared/money";
import { FIXTURE_SONGS } from "../../../shared/songs";
import {
  beende,
  pruefeKontoKorridor,
  sende,
  spawneRunde,
  spieleBisEnde,
  starteSyncPolling,
  starteTestServer,
} from "./_harness";

// Die Fragen liefern nur questionIds/Timer-Rahmen — der SONG kommt aus dem
// songs-Slice (sliceExtras unten), genau wie später vom Song-Pack-Loader.
const FRAGEN: Question[] = [1, 2, 3].map((n) => ({
  id: `ss-bot-${n}`,
  kind: "choice4",
  category: "musik",
  difficulty: "medium",
  text: `Song ${n}: Wer erkennt ihn zuerst?`,
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: "Der Song-Slice entscheidet — nicht diese Platzhalter-Frage.",
}));

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 7;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // Rotierender Song-Slice: jede Frage bekommt einen ANDEREN Ziel-Song
  // (songs[0] = Ziel, Rest = Distraktoren — der Slice-Vertrag der Pipeline).
  let initNr = 0;
  const server = await starteTestServer({
    plugin: songSnippetPlugin,
    fragen: FRAGEN,
    seed,
    sliceExtras: () => {
      const start = initNr++ % FIXTURE_SONGS.length;
      return { songs: [...FIXTURE_SONGS.slice(start), ...FIXTURE_SONGS.slice(0, start)] };
    },
  });
  const runde = await spawneRunde(server, ["Falsch-Fred", "Blitz-Bella", "Zoeger-Zoe"], "blitz-dj");
  const stopPolling = starteSyncPolling(runde);

  // GM-Spickzettel des RUNNERS: correctIndex pro Frage (Spieler-Views tragen
  // die Lösung NIE — genau das prüft der Leak-Check unten mit).
  const korrekt = new Map<string, number>();
  runde.gm.onView((view) => {
    const mg = view.minigame?.view as { questionId?: string; correctIndex?: number } | null;
    if (mg?.questionId !== undefined && mg.correctIndex !== undefined) {
      korrekt.set(mg.questionId, mg.correctIndex);
    }
  });

  interface SsBotView {
    questionId?: string;
    phase?: string;
    stufe?: number;
    finished?: boolean;
    buzzAktiv?: boolean;
    duBistRater?: boolean;
    options?: string[];
    correctIndex?: unknown;
    titel?: unknown;
    aufloesung?: unknown;
  }

  // Profil: zielStufe = Stufe, auf der gebuzzert wird (1-basiert im Log).
  const profile = [
    { name: "Falsch-Fred", buzzStufe: 0, richtig: false },
    { name: "Blitz-Bella", buzzStufe: 1, richtig: true },
    { name: "Zoeger-Zoe", buzzStufe: null as number | null, richtig: true },
  ];

  for (let i = 0; i < profile.length; i++) {
    const profil = profile[i];
    const { bot, playerId } = runde.spieler[i];
    const gebuzzt = new Set<string>();
    const geraten = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as SsBotView | null;
      if (!mg?.questionId || !view.minigame) return;
      // LEAK-CHECK: Titel/Lösung dürfen vor der Auflösung NIE im Spieler-View stehen.
      if (!mg.aufloesung && (mg.correctIndex !== undefined || mg.titel !== undefined)) {
        runde.probleme.push(`${profil.name}: Lösung leakt im Spieler-View!`);
      }
      if (view.phase !== "frage" || mg.finished) return;
      const qid = mg.questionId;

      // Buzzen: über das ECHTE buzz-Event (Median-RTT-Pfad der Räume).
      if (
        profil.buzzStufe !== null &&
        mg.phase === "lauschen" &&
        mg.stufe === profil.buzzStufe &&
        mg.buzzAktiv === true &&
        !gebuzzt.has(qid)
      ) {
        gebuzzt.add(qid);
        void sende(bot, "buzz", {
          minigameId: view.minigame.id,
          pressedAtServerEst: Date.now(),
          idemKey: `${playerId}-${qid}-buzz`,
        }).then((antwort) => {
          if (!antwort?.ok) {
            runde.probleme.push(`${profil.name}: buzz abgelehnt (${String(antwort?.error)})`);
          } else {
            runde.log(`${profil.name} buzzert ${qid} auf Stufe ${(profil.buzzStufe ?? 0) + 1}`);
          }
        });
      }

      // Raten (nur als Buzz-Sieger): Lösung aus dem GM-Spickzettel des Runners.
      if (mg.phase === "raten" && mg.duBistRater === true && mg.options && !geraten.has(qid)) {
        geraten.add(qid);
        const richtig = korrekt.get(qid) ?? 0;
        const choice = profil.richtig ? richtig : (richtig + 1) % 4;
        void sende(bot, "player.action", {
          minigameId: view.minigame.id,
          actionId: "answer",
          payload: { choice },
          idemKey: `${playerId}-${qid}-answer`,
        }).then((antwort) => {
          if (!antwort?.ok) {
            runde.probleme.push(`${profil.name}: answer abgelehnt (${String(antwort?.error)})`);
          } else {
            runde.log(`${profil.name} rät ${profil.richtig ? "RICHTIG" : "absichtlich FALSCH"}`);
          }
        });
      }
    });
  }

  await spieleBisEnde(runde, 90_000, { endeNachAufloesungen: FRAGEN.length });

  // ---------- Beweis: Eskalation + Verfalls-Treppe + Sperre + Strafe ----------
  if (runde.aufloesungen.length < FRAGEN.length) {
    runde.probleme.push(`Nur ${runde.aufloesungen.length}/${FRAGEN.length} Songs aufgelöst`);
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  for (const a of runde.aufloesungen) {
    const mg = a.mgView as unknown as {
      schwierigkeit: Schwierigkeit;
      aufloesung: { gewinnerId: string | null; gewinnerStufe: number | null; titel: string };
    };
    const deltaVon = new Map(a.perPlayer.map((r) => [r.playerId, r.delta]));
    const fred = deltaVon.get(idVon.get("Falsch-Fred")!) ?? NaN;
    const bella = deltaVon.get(idVon.get("Blitz-Bella")!) ?? NaN;
    const zoe = deltaVon.get(idVon.get("Zoeger-Zoe")!) ?? NaN;
    const s = mg.schwierigkeit;
    const erwartet = ssStufenWert(s, 1);

    if (mg.aufloesung.gewinnerId !== idVon.get("Blitz-Bella")) {
      runde.probleme.push(`${a.questionId}: Gewinner ist nicht Bella`);
    }
    if (mg.aufloesung.gewinnerStufe !== 1) {
      runde.probleme.push(`${a.questionId}: Sieg-Stufe ${mg.aufloesung.gewinnerStufe} ≠ 1`);
    }
    if (bella !== erwartet) {
      runde.probleme.push(`${a.questionId}: Bella ${bella} ≠ Treppe(${s}, Stufe 2) = ${erwartet}`);
    }
    if (fred !== -SS_STRAFE_MM) {
      runde.probleme.push(`${a.questionId}: Fred ${fred} ≠ −${SS_STRAFE_MM} (Falsch-Buzz-Strafe)`);
    }
    if (zoe !== 0) {
      runde.probleme.push(`${a.questionId}: Zoe ${zoe} ≠ 0 (nie gebuzzert)`);
    }
    if (!(erwartet < ssStufenWert(s, 0))) {
      runde.probleme.push(`${a.questionId}: Treppe fällt nicht (${erwartet} ≥ Stufe-1-Wert)`);
    }
    if (runde.probleme.length === 0) {
      runde.log(
        `${a.questionId} („${mg.aufloesung.titel}", ${s}): Fred −${SS_STRAFE_MM} (Sperre) → ` +
          `Bella +${bella} auf Stufe 2 (statt ${ssStufenWert(s, 0)} auf Stufe 1) — Verfall bewiesen ✓`,
      );
    }
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
