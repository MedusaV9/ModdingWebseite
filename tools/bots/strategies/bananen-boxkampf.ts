// Bot-Lauf Bananen-Boxkampf: 4 Bots spielen EINEN kompletten Kampf (K.O. in 4
// Schlagabtauschen mit Zuschauer-Wetten) in Echtzeit gegen den echten Server.
//   · Boxer-Bodo    (400 MM, Letzter ⇒ HERAUSFORDERER) — testet erst den
//                   Feiglings-Schutz (Wanda ist geschützt!), fordert dann
//                   Greta und antwortet IMMER richtig, IMMER schneller
//   · Gegner-Greta  (2000 MM, die Führende) — Abtausch 1 + 4 richtig (aber
//                   langsamer!), Abtausch 2 + 3 falsch
//   · Wett-Willi    (1200 MM) — wettet 50 MM auf Bodo (RICHTIG) und versucht
//                   verbotenerweise mitzuboxen (Zuschauer-Wache!)
//   · Wett-Wanda    (800 MM, ärmste Zuschauerin ⇒ Feiglings-Schutz) — wettet
//                   50 MM auf Greta (FALSCH)
// Erwarteter Verlauf (HARD = 30 Schaden): Abtausch 1 BEIDE richtig ⇒ Bodo
// schlägt ZUERST (Buzzer-Reihenfolge), Greta KONTERT (70:70). Abtausch 2+3
// nur Bodo (70:40, 70:10). Abtausch 4 BEIDE richtig ⇒ Bodos Erstschlag = K.O.
// bei 0 HP, Gretas Konter ENTFÄLLT (70:0). Der Lauf beweist: Herausforderer-
// Wahl + Feiglings-Schutz, geheime Wetten (Leak-Wache), Buzzer-Reihenfolge
// (Erstschlag/Konter/K.O. schluckt Konter), HP-Verlauf und die EXAKTE
// Abrechnung (Bodo +400 Bank, Greta zahlt NICHTS; Wett-Topf pari-mutuel:
// Willi +50, Wanda −50, Rest 0 — exakt nullsummig) und dass Zuschauer-
// Antworten serverseitig ignoriert werden.
//
// Aufruf: npx tsx tools/bots/strategies/bananen-boxkampf.ts [--seed 15]
import { boxkampfPlugin } from "../../../server/minigames/bananen-boxkampf/index";
import type { Question } from "../../../shared/content";
import {
  BX_MAX_HP,
  BX_PUNCH,
  BX_SIEG_KO_MM,
  BX_WETTE_MM,
  bxWettAbrechnung,
} from "../../../shared/minigames/bananen-boxkampf.meta";
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
  ["Was trägt ein Boxer?", ["Handschuhe", "Zylinder", "Flossen", "Schlips"], 0],
  ["Wann ist ein Kampf K.O.?", ["Bei 0 HP", "Nie", "Beim Gong", "Nach 1 Frage"], 0],
  ["Wer gewinnt nach Punkten?", ["Mehr Rest-HP", "Weniger HP", "Der Ältere", "Niemand"], 0],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `bx-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "hard",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Boxer-Bodo", "Gegner-Greta", "Wett-Willi", "Wett-Wanda"];
// Bodo ist der Letzte (Herausforderer), Greta die Führende, Wanda die ärmste
// ZUSCHAUERIN (⇒ Feiglings-Schutz: nicht herausforderbar).
const STARTKAPITAL: Record<string, number> = {
  "Boxer-Bodo": 400,
  "Gegner-Greta": 2_000,
  "Wett-Willi": 1_200,
  "Wett-Wanda": 800,
};

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 15;
}

interface BxBotView {
  questionId?: string;
  frageNonce?: number;
  phase?: string;
  finished?: boolean;
  rundeNr?: number;
  herausforderer?: string;
  gegner?: string | null;
  hp?: Record<string, number>;
  answeredCount?: number;
  wetten?: Record<string, string> | null;
  wettenAnzahl?: number;
  letzterAbtausch?: {
    schlaege: { von: string; schaden: number; konter: boolean; ko: boolean }[];
  } | null;
  ergebnis?: {
    sieger: string | null;
    verlierer: string | null;
    ko: boolean;
    geteilt: boolean;
    kampflos: boolean;
    abgebrochen: boolean;
  } | null;
  duBistHerausforderer?: boolean;
  waehlbareGegner?: { id: string; waehlbar: boolean }[] | null;
  correctIndex?: unknown;
  answers?: unknown;
  balances?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() für den ganzen Kampf — die Fragen rotieren.
  const server = await starteTestServer({ plugin: boxkampfPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "boxkampf-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const bodoId = idVon.get("Boxer-Bodo")!;
  const gretaId = idVon.get("Gegner-Greta")!;
  const williId = idVon.get("Wett-Willi")!;
  const wandaId = idVon.get("Wett-Wanda")!;

  // ---------- GM verteilt Startkapital in der Lobby (Zwischenstand-Basis) ----------
  const gmAnpassungen = new Map<string, number>();
  for (const { playerId, name } of runde.spieler) {
    const delta = STARTKAPITAL[name];
    const ack = await runde.gm.emitAck("gm.cmd", {
      cmd: "score.adjust",
      args: { playerId, delta, grund: "startkapital-botlauf", override: true },
      cmdId: `kapital-${name}`,
    });
    if (!ack.ok) throw new Error(`Startkapital für ${name} abgelehnt: ${String(ack.error)}`);
    gmAnpassungen.set(playerId, delta);
  }
  runde.log("Startkapital: Bodo 400 (Letzter!), Greta 2000, Willi 1200, Wanda 800 MM");

  // ---------- Beobachtungs-Sammler (Beweis-Grundlage) ----------
  let feiglingsSchutzGesehen = false; // Wanda war im Wahl-Grid als NICHT wählbar markiert
  let wettenGeheimGeprueft = false; // im Wett-Fenster waren die Tipps unsichtbar
  let maxAnswered = 0;
  let gegnerWarWanda = false;
  let konterGesehen = false; // Abtausch 1: Erstschlag + Konter
  let koSchlucktKonter = false; // K.O.-Abtausch: NUR 1 Schlag trotz 2 Richtiger

  runde.screen.onView((view) => {
    const mg = view.minigame?.view as BxBotView | null;
    if (!mg?.questionId || view.phase !== "frage") return;
    if (mg.phase === "schlag" && mg.letzterAbtausch) {
      const schlaege = mg.letzterAbtausch.schlaege;
      if (schlaege.length === 2 && schlaege[0].von === bodoId && schlaege[1].konter) {
        konterGesehen = true;
      }
      if (schlaege.length === 1 && schlaege[0].ko && schlaege[0].von === bodoId) {
        koSchlucktKonter = true; // Greta war auch richtig — ihr Konter entfiel
      }
    }
  });

  // ---------- Spieler-Bots ----------
  for (const { bot, playerId, name } of runde.spieler) {
    let herausgefordert = false;
    let gewettet = false;
    const beantwortet = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as BxBotView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;

      // LEAK-WACHEN: Lösung, Antwort-Details und Konto-Snapshot bleiben auf dem
      // Server; im Wett-Fenster ist nur die ANZAHL der Wetten sichtbar.
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.answers !== undefined || mg.balances !== undefined) {
        runde.probleme.push(`${name}: Server-Interna (answers/balances) leaken!`);
      }
      if (mg.phase === "wetten") {
        wettenGeheimGeprueft = true;
        if (mg.wetten !== null && mg.wetten !== undefined) {
          runde.probleme.push(`${name}: Wetten leaken VOR Wettschluss!`);
        }
      }
      maxAnswered = Math.max(maxAnswered, mg.answeredCount ?? 0);
      if (mg.gegner === wandaId) gegnerWarWanda = true;
      if (mg.finished) return;

      // 1) GEGNER-WAHL (nur Bodo): erst der Feiglings-Schutz-Test (Wanda,
      //    muss abprallen), dann die echte Herausforderung (Greta).
      if (mg.phase === "herausforderung" && name === "Boxer-Bodo" && !herausgefordert) {
        herausgefordert = true;
        const wanda = (mg.waehlbareGegner ?? []).find((k) => k.id === wandaId);
        if (mg.duBistHerausforderer !== true) {
          runde.probleme.push("Bodo (Letzter) ist NICHT der Herausforderer!");
        }
        if (wanda !== undefined && !wanda.waehlbar) feiglingsSchutzGesehen = true;
        void (async () => {
          await delay(400);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "herausfordern",
            payload: { targetId: wandaId },
            idemKey: `${playerId}-fordere-wanda`,
          });
          runde.log("Bodo versucht die geschützte Wanda zu fordern (muss abprallen)");
          await delay(600);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "herausfordern",
            payload: { targetId: gretaId },
            idemKey: `${playerId}-fordere-greta`,
          });
          runde.log("Bodo fordert Greta (die Führende) in den Ring! 🥊");
        })();
      }

      // 2) WETT-FENSTER (nur Zuschauer): Willi → Bodo (richtig), Wanda → Greta.
      if (mg.phase === "wetten" && !gewettet && (name === "Wett-Willi" || name === "Wett-Wanda")) {
        gewettet = true;
        const auf = name === "Wett-Willi" ? bodoId : gretaId;
        void (async () => {
          await delay(name === "Wett-Willi" ? 400 : 900);
          const ack = await sende(bot, "player.action", {
            minigameId,
            actionId: "wette",
            payload: { auf },
            idemKey: `${playerId}-wette`,
          });
          if (ack?.ok)
            runde.log(`${name} wettet ${BX_WETTE_MM} MM auf ${auf === bodoId ? "Bodo" : "Greta"}`);
        })();
      }

      // 3) SPEED-FRAGEN: Bodo immer richtig (schnell); Greta in Abtausch 1+4
      //    richtig (langsamer!), sonst falsch; Willi versucht verbotenerweise
      //    mitzuboxen (Zuschauer-Wache).
      const nonce = mg.frageNonce ?? 0;
      if (mg.phase === "frage" && !beantwortet.has(nonce)) {
        beantwortet.add(nonce);
        const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        const rundeNr = mg.rundeNr ?? 0;
        if (name === "Boxer-Bodo") {
          void (async () => {
            await delay(400);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice: korrekt },
              idemKey: `${playerId}-n${nonce}-answer`,
            });
          })();
        } else if (name === "Gegner-Greta") {
          const richtig = rundeNr === 1 || rundeNr === 4;
          void (async () => {
            await delay(1_300); // deutlich langsamer — kein Fotofinish
            await sende(bot, "player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice: richtig ? korrekt : (korrekt + 1) % 4 },
              idemKey: `${playerId}-n${nonce}-answer`,
            });
          })();
        } else if (name === "Wett-Willi") {
          void (async () => {
            await delay(700);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice: korrekt },
              idemKey: `${playerId}-n${nonce}-answer`,
            });
          })();
        }
      }
    });
  }

  // Ein Kampf = Wahl + Wetten + 4 Abtausche (Countdown/Frage/Schlag) + Ergebnis.
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: EXAKTE Abrechnung + Nullsummen-Invarianten ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Kampf), gesehen: ${runde.aufloesungen.length}`);
  }
  const a = runde.aufloesungen[0];
  if (a !== undefined) {
    const mg = a.mgView as BxBotView;
    const e = mg.ergebnis;
    if (e?.sieger !== bodoId || e?.verlierer !== gretaId || e?.ko !== true) {
      runde.probleme.push(`Kampf-Ausgang falsch: sieger=${String(e?.sieger)} ko=${String(e?.ko)}`);
    }
    // HP-Verlauf: Bodo kassierte GENAU einen Konter (Abtausch 1), Greta K.O.
    if (mg.hp?.[bodoId] !== BX_MAX_HP - BX_PUNCH.hard || mg.hp?.[gretaId] !== 0) {
      runde.probleme.push(`HP falsch: ${JSON.stringify(mg.hp)} (erwartet 70:0)`);
    }
    // Erwartete Deltas aus der geteilten Wett-Mathe (Single Source of Truth):
    // Topf 100, 1 Richtiger (Willi) ⇒ Anteil 100, Rest 0. Greta zahlt NICHTS.
    const wetten = { [williId]: bodoId, [wandaId]: gretaId };
    const wett = bxWettAbrechnung(wetten, bodoId);
    const erwartet: Record<string, number> = {
      [bodoId]: BX_SIEG_KO_MM + wett.restAnSieger,
      [gretaId]: 0,
      [williId]: wett.deltas[williId],
      [wandaId]: wett.deltas[wandaId],
    };
    for (const r of a.perPlayer) {
      if (r.delta !== erwartet[r.playerId]) {
        runde.probleme.push(
          `Delta falsch: ${r.playerId} hat ${r.delta}, erwartet ${erwartet[r.playerId]}`,
        );
      }
    }
    // Wett-Nullsumme: Σ Wetter-Deltas + Topf-Rest an den Sieger = 0.
    const wettSumme = wett.deltas[williId] + wett.deltas[wandaId] + wett.restAnSieger;
    if (wettSumme !== 0) runde.probleme.push(`Wett-Topf nicht nullsummig: Σ ${wettSumme}`);
    // Kampf-Nullsumme: Gesamtsumme = NUR die Bank-Prämie (400, K.O.).
    const summe = a.perPlayer.reduce((s, r) => s + r.delta, 0);
    if (summe !== BX_SIEG_KO_MM) {
      runde.probleme.push(`Σ aller Deltas ${summe} ≠ K.O.-Prämie ${BX_SIEG_KO_MM}`);
    }
    runde.log(
      `Abrechnung exakt: Bodo +${erwartet[bodoId]} (400 K.O.-Bank), Greta ±0 (zahlt nichts), ` +
        `Willi +${erwartet[williId]}, Wanda ${erwartet[wandaId]} ✓`,
    );
  }
  if (!feiglingsSchutzGesehen) {
    runde.probleme.push("Feiglings-Schutz nie gesehen (Wanda war im Wahl-Grid wählbar?)");
  }
  if (gegnerWarWanda) {
    runde.probleme.push("Feiglings-Schutz durchbrochen: Wanda wurde Gegnerin!");
  }
  if (!wettenGeheimGeprueft) {
    runde.probleme.push("Wett-Fenster nie in einem Player-View gesehen");
  }
  if (!konterGesehen) {
    runde.probleme.push("Konter nie gesehen (Abtausch 1: Erstschlag Bodo + Konter Greta)");
  } else {
    runde.log("Buzzer-Reihenfolge: Bodos Erstschlag landete VOR Gretas Konter ✓");
  }
  if (!koSchlucktKonter) {
    runde.probleme.push("K.O.-Regel nie gesehen (Abtausch 4: Erstschlag-K.O. ohne Konter)");
  } else {
    runde.log("K.O. ist K.O.: Gretas Konter im 4. Abtausch ENTFIEL ✓");
  }
  if (maxAnswered > 2) {
    runde.probleme.push(`Zuschauer-Wache verletzt: ${maxAnswered} Antworten (max. 2 Boxer)`);
  } else {
    runde.log(
      `Zuschauer-Wache hält: Willis Box-Versuche wurden ignoriert (max ${maxAnswered}/2) ✓`,
    );
  }

  stopPolling();
  pruefeKontoKorridor(runde, gmAnpassungen);
  beende(server, runde);
}

void main();
