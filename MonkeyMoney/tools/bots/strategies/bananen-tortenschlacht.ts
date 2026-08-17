// Bot-Lauf Bananen-Tortenschlacht: 4 Bots spielen EINE komplette Schlacht in
// Echtzeit gegen den echten Server.
//   · Torten-Tina  — antwortet IMMER richtig (schnell) und tortet gezielt:
//                    erst Susi, dann Bernd (Ziel = erster Nicht-Rausgeflogene)
//   · Werfer-Willi — antwortet richtig, solange >2 Affen aktiv sind (wirft mit),
//                    ab dem 2-Aktive-Endspiel IMMER falsch (kassiert den Autowurf)
//   · Sahne-Susi   — antwortet immer falsch UND versucht nach ihrem Rauswurf
//                    verbotenerweise weiter mitzuantworten (Raus-Wache!)
//   · Blick-Bernd  — antwortet immer falsch (zweites Opfer)
// Erwarteter Verlauf (deterministisch): R1 Susi 0→2 Schichten (Tina+Willi),
// R2 Susi 3.+4. Torte (RAUS als 1. — die 4. landet, geworfen ist geworfen!),
// R3 Bernd 0→2, R4 Bernd RAUS als 2., R5–R7 nur noch 2 Aktive ⇒ Ziel-Wahl
// übersprungen (AUTOWURF), Tina tortet Willi als 3. raus und bleibt selbst
// SAUBER ⇒ Sieg „letzter-sauberer“.
// Der Lauf beweist: Werfer-Kür (nur Richtige werfen), GEHEIME Ziel-Wahl
// (Salve unsichtbar bis zum Wurf-Beat), Sahne-Schichten + Rauswurf-Reihenfolge,
// Raus-Wache (Antworten Rausgeflogener verpuffen), den 2-Aktive-Autowurf und
// die EXAKTE Abrechnung (Topf 1.500 an Tina; Trost-Staffel 100/200/300 nach
// Überlebensdauer — Σ Deltas = Topf + Σ Trost).
//
// Aufruf: npx tsx tools/bots/strategies/bananen-tortenschlacht.ts [--seed 15]
import { tortenschlachtPlugin } from "../../../server/minigames/bananen-tortenschlacht/index";
import type { Question } from "../../../shared/content";
import { TS_TOPF_MM, tsTrost } from "../../../shared/minigames/bananen-tortenschlacht.meta";
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
  ["Woraus besteht eine Sahnetorte?", ["Aus Sahne", "Aus Beton", "Aus Sand", "Aus Glas"], 0],
  ["Wie viele Torten bis zum Raus?", ["Eine", "Zwei", "Drei", "Zehn"], 2],
  ["Was macht ein sauberer Affe?", ["Er gewinnt", "Er weint", "Er schläft", "Er kocht"], 0],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `ts-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "hard",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Torten-Tina", "Werfer-Willi", "Sahne-Susi", "Blick-Bernd"];

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 15;
}

interface TsBotView {
  questionId?: string;
  frageNonce?: number;
  phase?: string;
  finished?: boolean;
  raus?: string[];
  torten?: Record<string, number>;
  aktiveAnzahl?: number;
  answeredCount?: number;
  werfer?: string[];
  wuerfe?: { von: string; zu: string; schicht: number; raus: boolean }[];
  sieger?: string[];
  siegerGrund?: string | null;
  duBistRaus?: boolean;
  istWerfer?: boolean;
  deinZielGewaehlt?: boolean;
  ziele?: { id: string }[] | null;
  options?: string[] | null;
  correctIndex?: unknown;
  zielWahl?: unknown;
  answers?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() für die ganze Schlacht — 8 Fragen Vorrat.
  // sliceExtras: die Playlist-Position des Laufs sliced nur 4 Fragen — die
  // Schlacht braucht 7 (in der echten Marathon-Playlist stehen 8 im Plan).
  const server = await starteTestServer({
    plugin: tortenschlachtPlugin,
    fragen: FRAGEN,
    seed,
    sliceExtras: () => ({ questions: FRAGEN }),
  });
  const runde = await spawneRunde(server, NAMEN, "tortenschlacht-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const tinaId = idVon.get("Torten-Tina")!;
  const williId = idVon.get("Werfer-Willi")!;
  const susiId = idVon.get("Sahne-Susi")!;
  const berndId = idVon.get("Blick-Bernd")!;
  const nameVon = new Map(runde.spieler.map((s) => [s.playerId, s.name]));

  // ---------- Beobachtungs-Sammler (Beweis-Grundlage) ----------
  let zielwahlGeheimGeprueft = false; // in der Ziel-Wahl war die Salve unsichtbar
  const zielwahlNonces = new Set<number>(); // Nonces MIT Ziel-Wahl-Phase
  const wurfNonces = new Map<number, number>(); // Nonce → Torten der Salve
  let autowurfGesehen = false; // Wurf-Beat OHNE vorherige Ziel-Wahl (2 Aktive)
  let susiRausGesehen = false; // Susi trug die Raus-Markierung im eigenen View
  let maxAnsweredNachRaus = 0; // Antwort-Zähler, NACHDEM Susi raus war

  runde.screen.onView((view) => {
    const mg = view.minigame?.view as TsBotView | null;
    if (!mg?.questionId || view.phase !== "frage") return;
    const nonce = mg.frageNonce ?? 0;
    if (mg.phase === "zielwahl") zielwahlNonces.add(nonce);
    if (mg.phase === "wurf") {
      wurfNonces.set(nonce, (mg.wuerfe ?? []).length);
      // 2-Aktive-Endspiel: Einzel-Torte OHNE vorherige Ziel-Wahl-Phase.
      if (!zielwahlNonces.has(nonce) && (mg.wuerfe ?? []).length === 1 && mg.aktiveAnzahl === 2) {
        autowurfGesehen = true; // Ziel-Wahl übersprungen — Torte flog automatisch
      }
    }
    if (mg.phase === "frage" && (mg.raus ?? []).includes(susiId)) {
      maxAnsweredNachRaus = Math.max(maxAnsweredNachRaus, mg.answeredCount ?? 0);
    }
  });

  // ---------- Spieler-Bots ----------
  for (const { bot, playerId, name } of runde.spieler) {
    const beantwortet = new Set<number>();
    const geworfen = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as TsBotView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;
      const nonce = mg.frageNonce ?? 0;

      // LEAK-WACHEN: Lösung, geheime Ziel-Wahl und Server-Antworten bleiben
      // auf dem Server; die Salve ist VOR dem Wurf-Beat unsichtbar.
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.zielWahl !== undefined || mg.answers !== undefined) {
        runde.probleme.push(`${name}: Server-Interna (zielWahl/answers) leaken!`);
      }
      if (mg.phase === "zielwahl") {
        zielwahlGeheimGeprueft = true;
        if ((mg.wuerfe ?? []).length > 0) {
          runde.probleme.push(`${name}: Salve leakt VOR dem Wurf-Beat!`);
        }
      }
      if (mg.duBistRaus === true) {
        if (name === "Sahne-Susi") susiRausGesehen = true;
        if (mg.options !== null && mg.options !== undefined) {
          runde.probleme.push(`${name}: Raus-Affe sieht noch Antwort-Optionen!`);
        }
      }
      if (mg.finished) return;

      // 1) ANTWORTEN: Tina immer richtig; Willi richtig bis zum 2-Aktive-
      //    Endspiel; Susi/Bernd immer falsch. Susi feuert auch NACH ihrem
      //    Rauswurf (die Raus-Wache muss das serverseitig schlucken).
      if (mg.phase === "frage" && !beantwortet.has(nonce)) {
        beantwortet.add(nonce);
        const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        const richtig =
          name === "Torten-Tina" || (name === "Werfer-Willi" && (mg.aktiveAnzahl ?? 4) > 2);
        const choice = richtig ? korrekt : (korrekt + 1) % 4;
        const verzoegerung = name === "Torten-Tina" ? 350 : name === "Werfer-Willi" ? 800 : 550;
        void (async () => {
          await delay(verzoegerung);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-n${nonce}-answer`,
          });
        })();
      }

      // 2) GEHEIME ZIEL-WAHL (nur Werfer): erst Susi torten, dann Bernd.
      if (mg.phase === "zielwahl" && mg.istWerfer === true && !geworfen.has(nonce)) {
        geworfen.add(nonce);
        const raus = mg.raus ?? [];
        const ziel = [susiId, berndId].find((z) => !raus.includes(z) && z !== playerId);
        if (ziel === undefined) return;
        void (async () => {
          await delay(300);
          const ack = await sende(bot, "player.action", {
            minigameId,
            actionId: "wurf",
            payload: { targetId: ziel },
            idemKey: `${playerId}-n${nonce}-wurf`,
          });
          if (ack?.ok) runde.log(`${name} zielt GEHEIM auf ${nameVon.get(ziel) ?? ziel} 🥧`);
        })();
      }
    });
  }

  // 7 Fragen à ~7 s (Frage + Ziel-Wahl + Wurf-Beat) + Ergebnis-Beat.
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: EXAKTE Abrechnung + Verlaufs-Beweise ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (roundBased), gesehen: ${runde.aufloesungen.length}`);
  }
  const a = runde.aufloesungen[0];
  if (a !== undefined) {
    const mg = a.mgView as TsBotView;
    if (mg.siegerGrund !== "letzter-sauberer" || !(mg.sieger ?? []).includes(tinaId)) {
      runde.probleme.push(
        `Ausgang falsch: sieger=${JSON.stringify(mg.sieger)} grund=${String(mg.siegerGrund)}`,
      );
    }
    // Rauswurf-Reihenfolge: Susi als 1., Bernd als 2., Willi als 3.
    if (JSON.stringify(mg.raus) !== JSON.stringify([susiId, berndId, williId])) {
      runde.probleme.push(`Rauswurf-Reihenfolge falsch: ${JSON.stringify(mg.raus)}`);
    }
    // EXAKTE Deltas: Topf an Tina, Trost-Staffel nach Überlebensdauer.
    const erwartet: Record<string, number> = {
      [tinaId]: TS_TOPF_MM,
      [susiId]: tsTrost(1),
      [berndId]: tsTrost(2),
      [williId]: tsTrost(3),
    };
    for (const r of a.perPlayer) {
      if (r.delta !== erwartet[r.playerId]) {
        runde.probleme.push(
          `Delta falsch: ${nameVon.get(r.playerId) ?? r.playerId} hat ${r.delta}, ` +
            `erwartet ${erwartet[r.playerId]}`,
        );
      }
    }
    const summe = a.perPlayer.reduce((s, r) => s + r.delta, 0);
    if (summe !== TS_TOPF_MM + tsTrost(1) + tsTrost(2) + tsTrost(3)) {
      runde.probleme.push(`Σ aller Deltas ${summe} ≠ Topf + Trost-Staffel`);
    }
    runde.log(
      `Abrechnung exakt: Tina +${TS_TOPF_MM} (Topf), Willi +${tsTrost(3)}, ` +
        `Bernd +${tsTrost(2)}, Susi +${tsTrost(1)} (Trost nach Überlebensdauer) ✓`,
    );
  }
  if (!zielwahlGeheimGeprueft) {
    runde.probleme.push("Ziel-Wahl-Phase nie in einem Player-View gesehen");
  }
  if (!autowurfGesehen) {
    runde.probleme.push("2-Aktive-Autowurf nie gesehen (Ziel-Wahl wurde nicht übersprungen?)");
  } else {
    runde.log("2-Aktive-Endspiel: Ziel-Wahl übersprungen, Torte flog automatisch ✓");
  }
  if (!susiRausGesehen) {
    runde.probleme.push("Susi sah ihre Ehrentribüne nie (duBistRaus fehlte)");
  }
  if (maxAnsweredNachRaus > 3) {
    runde.probleme.push(
      `Raus-Wache verletzt: ${maxAnsweredNachRaus} Antworten mit Susi draußen (max. 3 Aktive)`,
    );
  } else {
    runde.log(`Raus-Wache hält: Susis Antworten nach dem Rauswurf verpufften ✓`);
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
