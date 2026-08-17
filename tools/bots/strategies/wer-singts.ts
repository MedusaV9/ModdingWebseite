// Bot-Lauf Wer singt's?: 4 Bots spielen EINE Platten-Runde (4 Beats, davon 2
// Song-Pack-Wünsche) in Echtzeit gegen den echten Server. Der Clou: die Bots
// erkennen den richtigen Interpreten NUR aus dem PUBLIC View (Titel auf der
// Platte) + dem geteilten Fakten-Pool — genau wie ein Musik-Kenner am Handy.
// Leakt der Server nichts, ist das die EINZIGE Gewinnstrategie.
//   · Platten-Paula (kennt jede Platte, tippt BLITZSCHNELL ⇒ voller Speed-Bonus)
//   · Vinyl-Vera    (kennt jede Platte, tippt SPÄT ⇒ kaum Speed-Bonus —
//                   Paula MUSS pro Beat mehr verdienen)
//   · Rate-Rudi     (tippt immer auf den falschen Interpreten ⇒ exakt 0)
//   · Stumm-Susi    (sagt nie etwas ⇒ exakt 0, keine Strafe)
// Der Lauf beweist: Song-Pack-Einbindung (2 Wunsch-Beats via sliceExtras),
// Leak-Wachen (Interpret/correctIndex NIE vor der Aufdeckung), Speed-Bonus-
// Staffel, Null-für-Falsch/Stumm und die Aufdeckungs-Rotation (artist im View).
//
// Aufruf: npx tsx tools/bots/strategies/wer-singts.ts [--seed 15]
import { werSingtsPlugin } from "../../../server/minigames/wer-singts/index";
import type { Question } from "../../../shared/content";
import { WS_FAKTEN_POOL, WS_WERT } from "../../../shared/minigames/wer-singts.meta";
import type { Schwierigkeit } from "../../../shared/money";
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

// 4 Beats = 4 injizierte Zähl-Fragen (contentKind "none": nur die Anzahl zählt).
const FRAGEN: Question[] = Array.from({ length: 4 }, (_, i) => ({
  id: `ws-beat-${i + 1}`,
  kind: "choice4",
  category: "musik",
  difficulty: "medium",
  text: `Beat ${i + 1}`,
  options: ["A", "B", "C", "D"],
  answer: 0,
  erklaerung: "",
}));

// Song-Pack-Wünsche (2 Stück ⇒ bei 4 Beats nimmt wsWaehleBeats BEIDE mit —
// Pack-Deckel ist ceil(4/2) = 2).
const PACK_SONGS = [
  { id: "wunsch-1", titel: "Bananen-Boogie", artist: "Die Test-Affen", jahr: 2024 },
  { id: "wunsch-2", titel: "Dschungel-Disco", artist: "MC Kokosnuss", jahr: 2023 },
];

/** Interpret zu einem Platten-Titel — Pool zuerst, dann die Pack-Wünsche
 * (EXAKT das Wissen, das auch ein Party-Gast mitbringen könnte). */
function interpretZu(titel: string): string | null {
  const pool = WS_FAKTEN_POOL.find((f) => f.titel === titel);
  if (pool !== undefined) return pool.artist;
  return PACK_SONGS.find((s) => s.titel === titel)?.artist ?? null;
}

const NAMEN = ["Platten-Paula", "Vinyl-Vera", "Rate-Rudi", "Stumm-Susi"];

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 15;
}

interface WsBotView {
  questionId?: string;
  beatNr?: number;
  beatTotal?: number;
  phase?: string;
  finished?: boolean;
  titel?: string;
  jahr?: number | null;
  schwierigkeit?: Schwierigkeit;
  wert?: number;
  ausSongPack?: boolean;
  options?: string[] | null;
  artist?: string | null;
  answeredCount?: number;
  beat?: { artist: string; richtige: string[]; wert: number } | null;
  deltas?: Record<string, number>;
  correctIndex?: unknown;
  antworten?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased + wuenschtSongs: das Song-Pack kommt über sliceExtras
  // (der Produktions-Draht flow.starteFrage hängt songs READ-ONLY an).
  const server = await starteTestServer({
    plugin: werSingtsPlugin,
    fragen: FRAGEN,
    seed,
    sliceExtras: () => ({ songs: PACK_SONGS }),
  });
  const runde = await spawneRunde(server, NAMEN, "wer-singts-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const paulaId = idVon.get("Platten-Paula")!;
  const veraId = idVon.get("Vinyl-Vera")!;
  const rudiId = idVon.get("Rate-Rudi")!;
  const susiId = idVon.get("Stumm-Susi")!;
  const gmAnpassungen = new Map<string, number>();

  // ---------- Beobachtungs-Sammler (Beweis-Grundlage) ----------
  const packBeatsGesehen = new Set<string>(); // Song-Wunsch-Titel auf der Bühne
  const beatWerte: { titel: string; wert: number; schwierigkeit: string }[] = [];
  let aufdeckungMitArtist = false; // die Platte drehte sich zum Interpreten
  let letzterBeatKey = "";

  runde.screen.onView((view) => {
    const mg = view.minigame?.view as WsBotView | null;
    if (!mg?.questionId || view.phase !== "frage") return;
    if (mg.ausSongPack === true && mg.titel !== undefined) packBeatsGesehen.add(mg.titel);
    const key = `${mg.beatNr ?? 0}`;
    if (mg.phase === "raten" && key !== letzterBeatKey && mg.titel !== undefined) {
      letzterBeatKey = key;
      beatWerte.push({
        titel: mg.titel,
        wert: mg.wert ?? 0,
        schwierigkeit: mg.schwierigkeit ?? "?",
      });
      runde.log(
        `Platte ${mg.beatNr}/${mg.beatTotal}: „${mg.titel}" (${String(mg.jahr)}, ` +
          `${mg.schwierigkeit}, ${mg.wert} MM${mg.ausSongPack === true ? ", Song-Wunsch" : ""})`,
      );
    }
    if (mg.phase === "aufdeckung" && typeof mg.artist === "string" && mg.artist.length > 0) {
      aufdeckungMitArtist = true;
    }
  });

  // ---------- Spieler-Bots ----------
  for (const { bot, playerId, name } of runde.spieler) {
    const getippt = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as WsBotView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;

      // LEAK-WACHEN: vor der Aufdeckung darf NIEMAND den Interpreten oder den
      // richtigen Index sehen — sonst wäre die Pool-Strategie witzlos.
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.antworten !== undefined) {
        runde.probleme.push(`${name}: Antwort-Details (antworten) leaken!`);
      }
      if (mg.phase !== "aufdeckung" && mg.artist !== null && mg.artist !== undefined) {
        runde.probleme.push(`${name}: Interpret leakt VOR der Aufdeckung (${String(mg.artist)})!`);
      }
      if (mg.phase === "auflegen" && mg.options != null) {
        runde.probleme.push(`${name}: Optionen leaken schon in der Auflegen-Phase!`);
      }
      if (mg.finished || name === "Stumm-Susi") return;

      // RATEN: Interpret NUR über Titel + geteilten Pool erkennen.
      const beatNr = mg.beatNr ?? 0;
      if (mg.phase === "raten" && Array.isArray(mg.options) && !getippt.has(beatNr)) {
        getippt.add(beatNr);
        const artist = interpretZu(mg.titel ?? "");
        const richtig = artist === null ? -1 : mg.options.indexOf(artist);
        if (richtig < 0) {
          runde.probleme.push(`${name}: Interpret zu „${String(mg.titel)}" nicht in den Optionen!`);
          return;
        }
        const choice = name === "Rate-Rudi" ? (richtig + 1) % mg.options.length : richtig;
        const wartezeit = name === "Platten-Paula" ? 600 : name === "Vinyl-Vera" ? 9_000 : 2_000;
        void (async () => {
          await delay(wartezeit);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-b${beatNr}-answer`,
          });
        })();
      }
    });
  }

  // Eine Runde = 4×(Auflegen/Raten/Aufdeckung) — Susi schweigt, also läuft
  // jedes Rate-Fenster die vollen 12 s.
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: Wertung + Song-Pack + Leak-Beweis ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Runde), gesehen: ${runde.aufloesungen.length}`);
  }
  const a = runde.aufloesungen[0];
  if (a !== undefined) {
    const deltas = new Map(a.perPlayer.map((r) => [r.playerId, r.delta]));
    const paula = deltas.get(paulaId) ?? 0;
    const vera = deltas.get(veraId) ?? 0;
    // Grundwert-Summe der 4 gespielten Platten; Speed-Bonus-Deckel je Beat =
    // round(wert × 0,5 / 10) × 10 (die 10er-Rundung von shared/money.ts!).
    const basis = beatWerte.reduce((s, b) => s + b.wert, 0);
    const maxBonus = beatWerte.reduce((s, b) => s + Math.round((b.wert * 0.5) / 10) * 10, 0);
    if (paula < basis || paula > basis + maxBonus) {
      runde.probleme.push(`Paula: ${paula} MM außerhalb [${basis}, ${basis + maxBonus}]`);
    }
    if (vera < basis) {
      runde.probleme.push(`Vera: ${vera} MM unter der Grundwert-Summe ${basis}`);
    }
    if (paula <= vera) {
      runde.probleme.push(`Speed-Bonus wirkungslos: Paula ${paula} ≤ Vera ${vera}`);
    }
    if ((deltas.get(rudiId) ?? -1) !== 0) {
      runde.probleme.push(`Rudi (immer falsch) hat ${deltas.get(rudiId)} statt 0`);
    }
    if ((deltas.get(susiId) ?? -1) !== 0) {
      runde.probleme.push(`Susi (stumm) hat ${deltas.get(susiId)} statt 0`);
    }
    runde.log(
      `Wertung: Paula +${paula} (Basis ${basis} + Speed), Vera +${vera} (langsamer!), ` +
        `Rudi ±0 (falsch kostet nichts), Susi ±0 (stumm) ✓`,
    );
  }
  if (packBeatsGesehen.size !== PACK_SONGS.length) {
    runde.probleme.push(
      `Song-Pack-Beats fehlen: ${packBeatsGesehen.size}/${PACK_SONGS.length} ` +
        `(gesehen: ${[...packBeatsGesehen].join(", ")})`,
    );
  } else {
    runde.log(
      `Beide Song-Wünsche liefen als Zusatz-Platten: ${[...packBeatsGesehen].join(" · ")} ✓`,
    );
  }
  if (!aufdeckungMitArtist) {
    runde.probleme.push("Aufdeckung nie gesehen (artist blieb im Screen-View leer)");
  } else {
    runde.log("Die Platte drehte sich: Interpret erschien ERST in der Aufdeckung ✓");
  }
  const werte = new Set(Object.values(WS_WERT));
  for (const b of beatWerte) {
    if (!werte.has(b.wert)) {
      runde.probleme.push(`Beat „${b.titel}": Wert ${b.wert} passt zu keiner Bekanntheits-Stufe`);
    }
  }

  stopPolling();
  pruefeKontoKorridor(runde, gmAnpassungen);
  beende(server, runde);
}

void main();
