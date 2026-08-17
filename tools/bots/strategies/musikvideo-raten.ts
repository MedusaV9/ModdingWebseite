// Bot-Lauf Stummfilm-Studio (musikvideo-raten): 3 Bots spielen die 3 Beats
// der Runde komplett durch (Song-Pack = die 3 ffmpeg-Fixture-Video-Songs,
// injiziert über den Slice — genau wie es der Song-Loader täte):
//   · Stumm-Steffi erkennt den Clip STUMM       ⇒ voller Wert W
//   · Ton-Toni     wartet auf die Rettungsstufe ⇒ W/2 (500-ms-Schnipsel)
//   · Falsch-Fritz tippt stumm DANEBEN          ⇒ 0 MM + Sperre
// Der Lauf beweist die Zwei-Stufen-Ökonomie end-zu-end (Deltas = Σ W bzw.
// Σ W/2 über alle Beats) und wacht über die Leaks: kein answer/correctIndex/
// Titel im Spieler-View vor der Aufdeckung, tonUrl erst AB der Rettungsstufe,
// introUrl NUR in der Aufdeckung. Die richtige Option kennt der Runner aus
// dem GM-Spickzettel (Server-Wahrheit) — nie aus Spieler-Views.
//
// Aufruf: npx tsx tools/bots/strategies/musikvideo-raten.ts [--seed 7]
import { musikvideoRatenPlugin } from "../../../server/minigames/musikvideo-raten/index";
import type { Question } from "../../../shared/content";
import { MV_FIXTURE_SONGS, mvRettungsWert } from "../../../shared/minigames/musikvideo-raten.meta";
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

// 3 Slot-Fragen ⇒ 3 Beats; der Beat-Wert folgt der Schwierigkeit (250/500/1000).
const FRAGEN: Question[] = (["medium", "hard", "ultrahard"] as const).map((difficulty, i) => ({
  id: `mv-slot-${i + 1}`,
  kind: "choice4",
  category: "musik",
  difficulty,
  text: "Welcher Song läuft im Stummfilm?",
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: "Der Song kommt aus dem Pack — die Slot-Frage liefert nur den Wert.",
}));

const NAMEN = ["Stumm-Steffi", "Ton-Toni", "Falsch-Fritz"];

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 7;
}

interface MvHistorieEintrag {
  songId: string;
  titel: string;
  artist: string;
  answer: number;
  wert: number;
  stummRichtig: string[];
  tonRichtig: string[];
  falsch: string[];
}

interface MvView {
  questionId?: string;
  nichtVerfuegbar?: boolean;
  phase?: "stumm" | "ton" | "aufdeckung";
  wert?: number;
  videoUrl?: string;
  tonUrl?: string | null;
  introUrl?: string | null;
  optionen?: string[];
  darfNoch?: boolean;
  finished?: boolean;
  historie?: MvHistorieEintrag[];
  aufloesung?: unknown;
  correctIndex?: unknown;
  answer?: unknown;
  titel?: unknown;
  artist?: unknown;
  antworten?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  const server = await starteTestServer({
    plugin: musikvideoRatenPlugin,
    fragen: FRAGEN,
    seed,
    // Song-Pack-Injektion — exakt der Slice-Vertrag des Song-Loaders.
    sliceExtras: () => ({ songs: [...MV_FIXTURE_SONGS] }),
  });
  const runde = await spawneRunde(server, NAMEN, "musikvideo-bots");
  const stopPolling = starteSyncPolling(runde);

  // ---------- GM-Spickzettel: richtige Option je Beat (Server-Wahrheit) ----------
  const korrektVon = new Map<string, number>();
  runde.gm.onView((view) => {
    const mg = view.minigame?.view as MvView | null;
    if (mg?.questionId && typeof mg.correctIndex === "number") {
      korrektVon.set(mg.questionId, mg.correctIndex);
    }
  });

  // ---------- Screen-Beobachter: Beat-Historie einsammeln ----------
  const historie = new Map<string, MvHistorieEintrag>();
  runde.screen.onView((view) => {
    const mg = view.minigame?.view as MvView | null;
    for (const h of mg?.historie ?? []) historie.set(h.songId, h);
    // Screen-Leak-Wache: die Lösung bleibt bis zur Aufdeckung auf dem Server.
    if (mg && mg.correctIndex !== undefined) {
      runde.probleme.push("Screen-View leakt correctIndex!");
    }
  });

  // ---------- Spieler-Bots (Profil siehe Kopf) ----------
  for (let i = 0; i < NAMEN.length; i++) {
    const name = NAMEN[i];
    const { bot, playerId } = runde.spieler[i];
    const gespielt = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as MvView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      // LEAK-CHECKS in JEDEM Spieler-View:
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Spieler-View!`);
      }
      if (mg.answer !== undefined || mg.antworten !== undefined) {
        runde.probleme.push(`${name}: answer/antworten leakt im Spieler-View!`);
      }
      if (mg.phase !== "aufdeckung" && (mg.titel !== undefined || mg.artist !== undefined)) {
        runde.probleme.push(`${name}: Titel/Artist leakt VOR der Aufdeckung!`);
      }
      if (mg.phase === "stumm" && mg.tonUrl != null) {
        runde.probleme.push(`${name}: tonUrl leakt schon im Stumm-Durchlauf!`);
      }
      if (mg.phase !== "aufdeckung" && mg.introUrl != null) {
        runde.probleme.push(`${name}: introUrl leakt vor der Aufdeckung!`);
      }
      if (mg.finished || mg.phase === "aufdeckung" || gespielt.has(mg.questionId)) return;

      // Profil-Timing: Steffi + Fritz tippen stumm, Toni erst in der Rettungsstufe.
      const willJetzt = name === "Ton-Toni" ? mg.phase === "ton" : mg.phase === "stumm";
      if (!willJetzt || mg.darfNoch !== true) return;
      const korrekt = korrektVon.get(mg.questionId);
      if (korrekt === undefined) return; // GM-Spickzettel noch nicht da — nächster Poll
      const questionId = mg.questionId;
      const minigameId = view.minigame.id;
      gespielt.add(questionId);
      const choice = name === "Falsch-Fritz" ? (korrekt + 1) % 4 : korrekt;
      void (async () => {
        await delay(400 + i * 200);
        const antwort = await sende(bot, "player.action", {
          minigameId,
          actionId: "answer",
          payload: { choice },
          idemKey: `${playerId}-${questionId}-answer`,
        });
        if (!antwort?.ok) {
          runde.probleme.push(`${name}: answer abgelehnt (${String(antwort?.error)})`);
          return;
        }
        runde.log(
          `${name} tippt ${questionId} im ${mg.phase === "ton" ? "TON" : "STUMM"}-Durchlauf ` +
            `(${name === "Falsch-Fritz" ? "absichtlich falsch" : "richtig"})`,
        );
      })();
    });
  }

  // roundBased: EINE Auflösung fürs ganze Studio; Phase „frage" steht ~70 s.
  await spieleBisEnde(runde, 150_000, { endeNachAufloesungen: 1 });

  // ---------- Zwei-Stufen-Beweis über die Beat-Historie ----------
  const beats = [...historie.values()];
  if (beats.length !== FRAGEN.length) {
    runde.probleme.push(
      `Erwartet ${FRAGEN.length} Beats in der Historie, gesehen: ${beats.length}`,
    );
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const steffiId = idVon.get("Stumm-Steffi") ?? "";
  const toniId = idVon.get("Ton-Toni") ?? "";
  const fritzId = idVon.get("Falsch-Fritz") ?? "";
  let steffiSoll = 0;
  let toniSoll = 0;
  for (const b of beats) {
    if (!b.stummRichtig.includes(steffiId)) {
      runde.probleme.push(`${b.songId}: Steffi fehlt bei „stumm richtig" (${b.stummRichtig})`);
    }
    if (!b.tonRichtig.includes(toniId)) {
      runde.probleme.push(`${b.songId}: Toni fehlt bei „mit Ton gerettet" (${b.tonRichtig})`);
    }
    if (!b.falsch.includes(fritzId)) {
      runde.probleme.push(`${b.songId}: Fritz fehlt bei „daneben" (${b.falsch})`);
    }
    steffiSoll += b.wert;
    toniSoll += mvRettungsWert(b.wert);
    runde.log(
      `${b.songId} („${b.titel}", W=${b.wert}): Steffi stumm +${b.wert}, ` +
        `Toni Ton +${mvRettungsWert(b.wert)}, Fritz 0 ✓`,
    );
  }
  for (const a of runde.aufloesungen) {
    const deltaVon = new Map(a.perPlayer.map((r) => [r.playerId, r.delta]));
    if (deltaVon.get(steffiId) !== steffiSoll) {
      runde.probleme.push(`Steffi-Delta ${deltaVon.get(steffiId)} ≠ Σ W = ${steffiSoll}`);
    }
    if (deltaVon.get(toniId) !== toniSoll) {
      runde.probleme.push(`Toni-Delta ${deltaVon.get(toniId)} ≠ Σ W/2 = ${toniSoll}`);
    }
    if (deltaVon.get(fritzId) !== 0) {
      runde.probleme.push(`Fritz-Delta ${deltaVon.get(fritzId)} ≠ 0 (falsch zahlt nichts)`);
    }
  }
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Runden-Auflösung, gesehen: ${runde.aufloesungen.length}`);
  } else {
    runde.log(
      `Zwei-Stufen-Ökonomie bewiesen: Steffi ${steffiSoll} MM (voll) > Toni ${toniSoll} MM (halb) > Fritz 0 MM ✓`,
    );
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
