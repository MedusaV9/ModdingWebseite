// Bot-Lauf Das große Lianen-Finale: 4 Bots hängen 3 Finalfragen lang über dem
// Krokodil-Fluss (12 s MC-4, alle gleichzeitig) — in Echtzeit.
//   · Kletter-Karla  antwortet nach ~800 ms, immer richtig  (+W)
//   · Mutige-Mia     antwortet nach ~9 s, immer richtig      (+W — KEIN Speed!)
//   · Wackel-Willi   antwortet flott, immer falsch           (−W/2, der Riss)
//   · Schnarch-Sami  antwortet NIE                            (0, Liane hält)
// Isolierte Läufe haben kein mods.wFinal ⇒ das Formel-Minimum W = 500 greift
// (§3.5). Der Lauf beweist die exakten Finale-Deltas (+500 / −250 / 0), dass
// früh und spät richtig DASSELBE zahlen (kein Speed-Bonus), und die Lianen-
// Normierung (Führender 100 %, Anzeige-Minimum 25 %). Leak-Check: correctIndex
// erscheint NIE vor der Auflösung.
//
// Aufruf: npx tsx tools/bots/strategies/lianen-finale.ts [--seed 31]
import { lianenFinalePlugin } from "../../../server/minigames/lianen-finale/index";
import type { Question } from "../../../shared/content";
import { LF_ANZEIGE_MIN, LF_FALLBACK_W } from "../../../shared/minigames/lianen-finale.meta";
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
  ["Was frisst ein Krokodil NICHT?", ["Fische", "Vögel", "Lianen", "Fleisch"], 2],
  ["Wo hängt der Finalist?", ["An der Liane", "Am Kran", "Im Netz", "Am Ast"], 0],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  ["Wer wohnt im Dschungel?", ["Der Pinguin", "Der Affe", "Das Walross", "Der Elch"], 1],
  ["Was liegt im Jackpot-Glas?", ["Sand", "Wasser", "Kekse", "MONKEY MONEY"], 3],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `lf-bot-${i + 1}`,
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
  antwortNachMs: number | null; // null = antwortet nie
  richtig: boolean;
}
const PROFILE: Profil[] = [
  { name: "Kletter-Karla", antwortNachMs: 800, richtig: true },
  { name: "Mutige-Mia", antwortNachMs: 9_000, richtig: true },
  { name: "Wackel-Willi", antwortNachMs: 1_500, richtig: false },
  { name: "Schnarch-Sami", antwortNachMs: null, richtig: true },
];
const FRAGEN_ZIEL = 3;

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 31;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({ plugin: lianenFinalePlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(
    server,
    PROFILE.map((p) => p.name),
    "lianen-finale-bots",
  );
  const stopPolling = starteSyncPolling(runde);

  // ---------- Spieler-Bots: 4 Buttons, Profil-Tempo — Sami schnarcht ----------
  for (let i = 0; i < PROFILE.length; i++) {
    const profil = PROFILE[i];
    const { bot, playerId } = runde.spieler[i];
    const beantwortet = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        finished?: boolean;
        correctIndex?: unknown;
        deineLiane?: number;
        lianen?: { laenge: number }[];
      } | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      // LEAK-CHECK: die Lösung bleibt bis zur Auflösung auf dem Server.
      if (!mg.finished && mg.correctIndex !== undefined) {
        runde.probleme.push(`${profil.name}: correctIndex leakt im Player-View!`);
      }
      // Lianen-Normierung live prüfen (Führender 100 %, Minimum 25 %).
      for (const l of mg.lianen ?? []) {
        if (l.laenge < LF_ANZEIGE_MIN || l.laenge > 1) {
          runde.probleme.push(`${profil.name}: Lianenlänge ${l.laenge} ∉ [0,25, 1]`);
        }
      }
      if (mg.finished || profil.antwortNachMs === null) return;
      const questionId = mg.questionId;
      if (beantwortet.has(questionId)) return;
      beantwortet.add(questionId);
      // Plan-Position ≠ Plugin-Id im Injektions-Harness: die Id kommt aus dem View.
      const minigameId = view.minigame.id;
      const korrekt = ANTWORT.get(questionId.split("~")[0]) ?? 0;
      const choice = profil.richtig ? korrekt : (korrekt + 1) % 4;
      void (async () => {
        await delay(profil.antwortNachMs!);
        const antwort = await sende(bot, "player.action", {
          minigameId,
          actionId: "answer",
          payload: { choice },
          idemKey: `${playerId}-${questionId}-answer`,
        });
        if (antwort?.ok) {
          runde.log(
            `${profil.name} tippt ${profil.richtig ? "richtig" : "FALSCH"} (${questionId})`,
          );
        }
      })();
    });
  }

  // Sami antwortet nie ⇒ jede Frage läuft die vollen 12 s (Timer-Pfad).
  await spieleBisEnde(runde, 60_000, { endeNachAufloesungen: FRAGEN_ZIEL });

  // ---------- Auswertung: exakte §3.5-Deltas + kein Speed-Bonus ----------
  if (runde.aufloesungen.length < FRAGEN_ZIEL) {
    runde.probleme.push(
      `Erwartet ≥ ${FRAGEN_ZIEL} Auflösungen, gesehen: ${runde.aufloesungen.length}`,
    );
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const erwartetFuer = new Map<string, number>([
    [idVon.get("Kletter-Karla") ?? "", LF_FALLBACK_W],
    [idVon.get("Mutige-Mia") ?? "", LF_FALLBACK_W],
    [idVon.get("Wackel-Willi") ?? "", -LF_FALLBACK_W / 2],
    [idVon.get("Schnarch-Sami") ?? "", 0],
  ]);
  for (const a of runde.aufloesungen) {
    if ((a.mgView.wFinal as number) !== LF_FALLBACK_W) {
      runde.probleme.push(`wFinal ${String(a.mgView.wFinal)} ≠ Formel-Minimum ${LF_FALLBACK_W}`);
    }
    for (const r of a.perPlayer) {
      const erwartet = erwartetFuer.get(r.playerId);
      if (erwartet !== undefined && r.delta !== erwartet) {
        runde.probleme.push(
          `${r.playerId} (${a.questionId}): Delta ${r.delta} ≠ ${erwartet} (§3.5)`,
        );
      }
      const nachher = r.lianeNachher as number | undefined;
      if (nachher !== undefined && (nachher < LF_ANZEIGE_MIN || nachher > 1)) {
        runde.probleme.push(`${r.playerId}: lianeNachher ${nachher} ∉ [0,25, 1]`);
      }
    }
    // Kein Speed-Bonus: Karla (~0,8 s) und Mia (~9 s) kriegen DENSELBEN Betrag.
    const karla = a.perPlayer.find((r) => r.playerId === idVon.get("Kletter-Karla"));
    const mia = a.perPlayer.find((r) => r.playerId === idVon.get("Mutige-Mia"));
    if (karla && mia && karla.delta !== mia.delta) {
      runde.probleme.push(
        `Speed-Bonus im Finale?! Karla ${karla.delta} ≠ Mia ${mia.delta} (${a.questionId})`,
      );
    }
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
