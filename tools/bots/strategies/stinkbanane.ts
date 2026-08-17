// Bot-Lauf Stinkbanane: 4 Bots spielen EIN komplettes Spiel (2 Durchgänge,
// verdeckte Zündschnur 45–75 s) in Echtzeit durch.
//   · Flinke-Fritzi  antwortet nach ~600 ms, immer richtig
//   · Sichere-Susi   antwortet nach ~900 ms, immer richtig
//   · Wackel-Willi   antwortet nach ~1,2 s, nur zu 60 % richtig (seeded Rng)
//   · Schnarch-Sami  antwortet nach ~5,5 s — und DISCONNECTET bei t=40 s
// Der Lauf beweist: Banane wandert bei richtig, bleibt bei falsch, explodiert
// beim Halter (−500 ins Glas), und Offline-Spieler werden ÜBERSPRUNGEN.
// Leak-Checks: Nicht-Halter sehen NIE die Frage, niemand sieht die Zündschnur.
//
// Aufruf: npx tsx tools/bots/strategies/stinkbanane.ts [--seed 11]
import { stinkbananePlugin } from "../../../server/minigames/stinkbanane/index";
import type { Question } from "../../../shared/content";
import {
  SB_DURCHGAENGE,
  SB_EXPLOSION_MM,
  SB_WEITERGABE_MM,
} from "../../../shared/minigames/stinkbanane.meta";
import { createRng } from "../../../shared/rng";
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
  ["Was frisst ein Affe am liebsten?", ["Bananen", "Steine", "Autos", "Wolken"], 0],
  ["Wie viele Beine hat eine Spinne?", ["Sechs", "Acht", "Zehn", "Vier"], 1],
  ["Welche Farbe hat eine reife Banane?", ["Blau", "Rot", "Gelb", "Lila"], 2],
  ["Was macht eine Stinkbanane?", ["Singen", "Schlafen", "Rechnen", "Stinken"], 3],
  ["Wo wachsen Kokosnüsse?", ["An Palmen", "Im Keller", "Am Nordpol", "Unter Wasser"], 0],
  ["Wie nennt man ein Affen-Baby?", ["Fohlen", "Jungtier", "Kalb", "Welpe"], 1],
  ["Was ist MONKEY MONEY?", ["Ein Auto", "Ein Gewürz", "Eine Spielshow", "Ein Planet"], 2],
  [
    "Womit trommelt der Gorilla?",
    ["Mit Stöcken", "Mit Töpfen", "Mit Bananen", "Mit den Fäusten"],
    3,
  ],
  ["Welches Tier klettert am besten?", ["Der Affe", "Das Nilpferd", "Die Kuh", "Der Pinguin"], 0],
  ["Was liegt im Jackpot-Glas?", ["Wasser", "MONKEY MONEY", "Sand", "Kekse"], 1],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `sb-bot-${i + 1}`,
  kind: "choice4",
  category: "dschungel",
  difficulty: "medium",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

interface Profil {
  name: string;
  antwortNachMs: number;
  trefferquote: number; // 0–1
}
const PROFILE: Profil[] = [
  { name: "Flinke-Fritzi", antwortNachMs: 600, trefferquote: 1 },
  { name: "Sichere-Susi", antwortNachMs: 900, trefferquote: 1 },
  { name: "Wackel-Willi", antwortNachMs: 1_200, trefferquote: 0.6 },
  { name: "Schnarch-Sami", antwortNachMs: 5_500, trefferquote: 1 },
];
const SAMI_DISCONNECT_NACH_MS = 40_000;

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 11;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased=true: die Engine gibt dem EINEN init() alle Runden-Fragen —
  // 1 Runde = 1 komplettes Stinkbananen-Spiel (2 Durchgänge), dann GM-Ende.
  const server = await starteTestServer({ plugin: stinkbananePlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(
    server,
    PROFILE.map((p) => p.name),
    "stinkbanane-bots",
  );
  const stopPolling = starteSyncPolling(runde);
  const botRng = createRng(seed * 1_000 + 1);

  // ---------- Screen-Beobachter: Halter-Timeline für den Offline-Skip-Beweis ----------
  const samiId = runde.spieler[3].playerId;
  let samiOfflineSeit: number | null = null;
  runde.screen.onView((view) => {
    const mg = view.minigame?.view as { holder?: string | null; phase?: string } | null;
    if (!mg || view.phase !== "frage") return;
    if (
      samiOfflineSeit !== null &&
      performance.now() - samiOfflineSeit > 1_000 && // Snapshot-Latenz-Gnade
      mg.holder === samiId
    ) {
      runde.probleme.push("Offline-Skip verletzt: Schnarch-Sami hält die Banane offline!");
    }
  });

  // ---------- Spieler-Bots: Halter antwortet, Rest trommelt ----------
  for (let i = 0; i < PROFILE.length; i++) {
    const profil = PROFILE[i];
    const { bot, playerId } = runde.spieler[i];
    const beantwortet = new Set<string>(); // Halte-Schlüssel questionId:frageEndsAt
    let trommelZaehler = 0;
    let letzteTrommel = 0;
    bot.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        phase?: string;
        istHalter?: boolean;
        frage?: { options: string[] } | null;
        frageEndsAt?: number;
        endsAt?: number;
        finished?: boolean;
        zuendschnurEndetAt?: unknown;
        correctIndex?: unknown;
      } | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;
      // LEAK-CHECKS: Zündschnur und Lösung dürfen NIE im Spieler-View stehen;
      // die Frage sieht ausschließlich der aktuelle Halter.
      if (mg.zuendschnurEndetAt !== undefined) {
        runde.probleme.push(`${profil.name}: zuendschnurEndetAt leakt im Spieler-View!`);
      }
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${profil.name}: correctIndex leakt im Spieler-View!`);
      }
      if (!mg.istHalter && mg.frage) {
        runde.probleme.push(`${profil.name}: Nicht-Halter sieht die Frage!`);
      }
      if (mg.finished || mg.phase !== "ticken") return;

      if (!mg.istHalter || !mg.frage) {
        // Kosmetik: alle ~3 s trommeln (ANFEUERN ist erlaubt und folgenlos).
        if (performance.now() - letzteTrommel > 3_000) {
          letzteTrommel = performance.now();
          void sende(bot, "player.action", {
            minigameId,
            actionId: "anfeuern",
            payload: {},
            idemKey: `${playerId}-trommel-${trommelZaehler++}`,
          });
        }
        return;
      }

      const halteKey = `${mg.questionId}:${mg.endsAt ?? 0}`;
      if (beantwortet.has(halteKey)) return;
      beantwortet.add(halteKey);
      const korrekt = ANTWORT.get(mg.questionId) ?? 0;
      const richtig = botRng.next() < profil.trefferquote;
      const choice = richtig ? korrekt : (korrekt + 1) % 4;
      void (async () => {
        await delay(profil.antwortNachMs);
        const antwort = await sende(bot, "player.action", {
          minigameId,
          actionId: "answer",
          payload: { choice },
          idemKey: `${playerId}-${halteKey}-answer`,
        });
        // Ablehnung/Timeout ist hier KEIN Fehler: Explosion oder der geplante
        // Disconnect kann der Antwort zuvorkommen (Plugin ignoriert per Design).
        if (antwort?.ok) {
          runde.log(
            `${profil.name} hält die Banane und tippt ${richtig ? "richtig" : "FALSCH"} (${mg.questionId})`,
          );
        }
      })();
    });
  }

  // Sami-Disconnect nach 40 s (parallel zum Watchdog) — beweist den Skip.
  const samiTimer = setTimeout(() => {
    samiOfflineSeit = performance.now();
    runde.spieler[3].bot.socket.disconnect();
    runde.log("Schnarch-Sami hat die Verbindung verloren (geplant, t=40 s)");
  }, SAMI_DISCONNECT_NACH_MS);

  // Ein Spiel dauert 2 Zündschnüre à 45–75 s — die Phase „frage" steht so lange.
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });
  clearTimeout(samiTimer);

  // ---------- Auswertung: Explosions-Ökonomie + Weitergabe-Mathe ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Spiel), gesehen: ${runde.aufloesungen.length}`);
  }
  for (const a of runde.aufloesungen) {
    let explosionen = 0;
    for (const r of a.perPlayer) {
      const weiter = (r.weitergaben as number) ?? 0;
      const expl = (r.explodiert as number) ?? 0;
      explosionen += expl;
      const erwartet = weiter * SB_WEITERGABE_MM - expl * SB_EXPLOSION_MM;
      if (r.delta !== erwartet) {
        runde.probleme.push(
          `${r.playerId}: Delta ${r.delta} ≠ ${weiter}×${SB_WEITERGABE_MM} − ${expl}×${SB_EXPLOSION_MM} = ${erwartet}`,
        );
      }
    }
    if (explosionen > SB_DURCHGAENGE || explosionen === 0) {
      runde.probleme.push(`Explosions-Zahl ${explosionen} außerhalb [1, ${SB_DURCHGAENGE}]`);
    }
    const glas = a.mgView.jackpotGlas as number;
    if (glas !== explosionen * SB_EXPLOSION_MM) {
      runde.probleme.push(`Jackpot-Glas ${glas} ≠ ${explosionen}×${SB_EXPLOSION_MM}`);
    } else {
      runde.log(`${explosionen} Explosion(en), ${glas} MM im Jackpot-Glas ✓`);
    }
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
