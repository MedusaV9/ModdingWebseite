// Bot-Lauf Duell am Lianensteg: 4 Bots spielen EIN komplettes Duell (Best-of-5
// mit Zuschauer-Wetten) in Echtzeit gegen den echten Server.
//   · Held-Hugo     (400 MM, Letzter ⇒ HERAUSFORDERER) — testet erst den
//                   Feiglings-Schutz (Wanda ist geschützt!), fordert dann
//                   Greta heraus und antwortet IMMER richtig (3:0-Sweep)
//   · Gegner-Greta  (2000 MM, die Führende) — antwortet immer FALSCH
//   · Wett-Willi    (1200 MM) — wettet 50 MM auf Hugo (RICHTIG) und versucht
//                   verbotenerweise mitzuantworten (Zuschauer-Wache!)
//   · Wett-Wanda    (800 MM, ärmste Zuschauerin ⇒ Feiglings-Schutz) — wettet
//                   50 MM auf Greta (FALSCH)
// Der Lauf beweist: Herausforderer-Wahl (der Letzte fordert), Feiglings-Schutz
// (geschützter Gegner nicht wählbar), geheime Wetten (View-Leak-Wache), den
// 3:0-Duellverlauf, die EXAKTE Abrechnung (Sieger +300 Bank + 100 Transfer vom
// Verlierer; pari-mutuel Wett-Topf: Willi +50, Wanda −50, Rest 0 — exakt
// nullsummig) und dass Zuschauer-Antworten serverseitig ignoriert werden.
//
// Aufruf: npx tsx tools/bots/strategies/lianensteg-duell.ts [--seed 15]
import { lianenstegDuellPlugin } from "../../../server/minigames/lianensteg-duell/index";
import type { Question } from "../../../shared/content";
import {
  LD_SIEG_BANK_MM,
  LD_SIEG_TRANSFER_MM,
  LD_WETTE_MM,
  ldWettAbrechnung,
} from "../../../shared/minigames/lianensteg-duell.meta";
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
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `ld-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "hard",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Held-Hugo", "Gegner-Greta", "Wett-Willi", "Wett-Wanda"];
// Hugo ist der Letzte (Herausforderer), Greta die Führende, Wanda die ärmste
// ZUSCHAUERIN (⇒ Feiglings-Schutz: nicht herausforderbar).
const STARTKAPITAL: Record<string, number> = {
  "Held-Hugo": 400,
  "Gegner-Greta": 2_000,
  "Wett-Willi": 1_200,
  "Wett-Wanda": 800,
};

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 15;
}

interface LdBotView {
  questionId?: string;
  frageNonce?: number;
  phase?: string;
  finished?: boolean;
  herausforderer?: string;
  gegner?: string | null;
  text?: string | null;
  options?: string[] | null;
  answeredCount?: number;
  wetten?: Record<string, string> | null;
  wettenAnzahl?: number;
  letzteTeilfrage?: { gewinner: string | null } | null;
  siege?: Record<string, number>;
  ergebnis?: {
    sieger: string | null;
    verlierer: string | null;
    geteilt: boolean;
    kampflos: boolean;
    abgebrochen: boolean;
    praemie: number;
    transfer: number;
    restAnSieger: number;
  } | null;
  duBistHerausforderer?: boolean;
  waehlbareGegner?: { id: string; waehlbar: boolean }[] | null;
  correctIndex?: unknown;
  answers?: unknown;
  balances?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() für die ganze Serie — die Fragen rotieren.
  const server = await starteTestServer({ plugin: lianenstegDuellPlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "lianensteg-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const hugoId = idVon.get("Held-Hugo")!;
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
  runde.log("Startkapital: Hugo 400 (Letzter!), Greta 2000, Willi 1200, Wanda 800 MM");

  // ---------- Beobachtungs-Sammler (Beweis-Grundlage) ----------
  let feiglingsSchutzGesehen = false; // Wanda war im Wahl-Grid als NICHT wählbar markiert
  let wettenGeheimGeprueft = false; // im Wett-Fenster waren die Tipps unsichtbar
  let maxAnswered = 0;
  let gegnerWarWanda = false;

  // ---------- Spieler-Bots ----------
  for (let i = 0; i < NAMEN.length; i++) {
    const name = NAMEN[i];
    const { bot, playerId } = runde.spieler[i];
    let herausgefordert = false;
    let gewettet = false;
    const beantwortet = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as LdBotView | null;
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

      // 1) GEGNER-WAHL (nur Hugo): erst der Feiglings-Schutz-Test (Wanda,
      //    muss abprallen), dann die echte Herausforderung (Greta).
      if (mg.phase === "herausforderung" && name === "Held-Hugo" && !herausgefordert) {
        herausgefordert = true;
        const wanda = (mg.waehlbareGegner ?? []).find((k) => k.id === wandaId);
        if (mg.duBistHerausforderer !== true) {
          runde.probleme.push("Hugo (Letzter) ist NICHT der Herausforderer!");
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
          runde.log("Hugo versucht die geschützte Wanda zu fordern (muss abprallen)");
          await delay(600);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "herausfordern",
            payload: { targetId: gretaId },
            idemKey: `${playerId}-fordere-greta`,
          });
          runde.log("Hugo fordert Greta (die Führende) aufs Seil!");
        })();
      }

      // 2) WETT-FENSTER (nur Zuschauer): Willi → Hugo (richtig), Wanda → Greta.
      if (mg.phase === "wetten" && !gewettet && (name === "Wett-Willi" || name === "Wett-Wanda")) {
        gewettet = true;
        const auf = name === "Wett-Willi" ? hugoId : gretaId;
        void (async () => {
          await delay(name === "Wett-Willi" ? 400 : 900);
          const ack = await sende(bot, "player.action", {
            minigameId,
            actionId: "wette",
            payload: { auf },
            idemKey: `${playerId}-wette`,
          });
          if (ack?.ok)
            runde.log(`${name} wettet ${LD_WETTE_MM} MM auf ${auf === hugoId ? "Hugo" : "Greta"}`);
        })();
      }

      // 3) SPEED-FRAGEN: Hugo richtig (schnell), Greta falsch (langsamer),
      //    Willi versucht verbotenerweise mitzuantworten (Zuschauer-Wache).
      const nonce = mg.frageNonce ?? 0;
      if (mg.phase === "frage" && !beantwortet.has(nonce)) {
        beantwortet.add(nonce);
        const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
        if (name === "Held-Hugo") {
          void (async () => {
            await delay(500);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice: korrekt },
              idemKey: `${playerId}-n${nonce}-answer`,
            });
          })();
        } else if (name === "Gegner-Greta") {
          void (async () => {
            await delay(1_100);
            await sende(bot, "player.action", {
              minigameId,
              actionId: "answer",
              payload: { choice: (korrekt + 1) % 4 },
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

  // Ein Duell = Wahl + Wetten + 3 Teilfragen + Ergebnis (~40 s Echtzeit) —
  // die Engine-Phase „frage" steht dabei durchgehend.
  await spieleBisEnde(runde, 180_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: EXAKTE Abrechnung + Nullsummen-Invarianten ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Duell), gesehen: ${runde.aufloesungen.length}`);
  }
  const a = runde.aufloesungen[0];
  if (a !== undefined) {
    const mg = a.mgView as LdBotView;
    const e = mg.ergebnis;
    if (e?.sieger !== hugoId || e?.verlierer !== gretaId) {
      runde.probleme.push(
        `Duell-Ausgang falsch: sieger=${String(e?.sieger)} verlierer=${String(e?.verlierer)}`,
      );
    }
    if (e?.geteilt === true || e?.kampflos === true || e?.abgebrochen === true) {
      runde.probleme.push("Duell endete geteilt/kampflos/abgebrochen statt regulär 3:0");
    }
    // Erwartete Deltas aus der geteilten Wett-Mathe (Single Source of Truth):
    // Topf 100, 1 Richtiger (Willi) ⇒ Anteil 100, Rest 0.
    const wetten = { [williId]: hugoId, [wandaId]: gretaId };
    const wett = ldWettAbrechnung(wetten, hugoId);
    const erwartet: Record<string, number> = {
      [hugoId]: LD_SIEG_BANK_MM + LD_SIEG_TRANSFER_MM + wett.restAnSieger,
      [gretaId]: -LD_SIEG_TRANSFER_MM,
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
    // Duell-Transfer-Nullsumme: Gesamtsumme = NUR die Bank-Prämie (300).
    const summe = a.perPlayer.reduce((s, r) => s + r.delta, 0);
    if (summe !== LD_SIEG_BANK_MM) {
      runde.probleme.push(`Σ aller Deltas ${summe} ≠ Bank-Prämie ${LD_SIEG_BANK_MM}`);
    }
    runde.log(
      `Abrechnung exakt: Hugo +${erwartet[hugoId]} (300 Bank + 100 Transfer), ` +
        `Greta ${erwartet[gretaId]}, Willi +${erwartet[williId]}, Wanda ${erwartet[wandaId]} ✓`,
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
  if (maxAnswered > 2) {
    runde.probleme.push(`Zuschauer-Wache verletzt: ${maxAnswered} Antworten (max. 2 Duellanten)`);
  } else {
    runde.log(
      `Zuschauer-Wache hält: Willis Antwort-Versuche wurden ignoriert (max ${maxAnswered}/2) ✓`,
    );
  }

  stopPolling();
  pruefeKontoKorridor(runde, gmAnpassungen);
  beende(server, runde);
}

void main();
