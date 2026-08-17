// Bot-Lauf „Einer gegen alle": 5 Bots spielen EINE komplette Runde (6 Fragen)
// in Echtzeit gegen den echten Server. Solo-Sofia bekommt vom GM das größte
// Startkapital ⇒ sie ist die FÜHRENDE und muss aufs Solisten-Podest.
// Drehbuch (Menge = Carl, Clara, Chris, Micha):
//   F1: Sofia richtig, Menge 3:1 falsch      ⇒ SOLO-COUP: Sofia +400
//   F2: beide richtig (Menge 3:1 richtig)    ⇒ ALLE +150
//   F3: Sofia falsch, Menge 3:1 richtig      ⇒ Menge je +200
//   F4: GLEICHSTAND 2:2 (richtig vs. falsch) ⇒ Los via ctx.rng entscheidet —
//       Sofia richtig: fällt das Los auf richtig, +150 für alle, sonst
//       Solo-Coup +400 (der Lauf liest den Los-Ausgang aus dem Beat)
//   F5: beide falsch                         ⇒ nichts
//   F6: Menge KOMPLETT STUMM (= falsch), Sofia richtig ⇒ Solo-Coup +400
// Leak-Wachen im Lauf: der Solist sieht die Mengen-Verteilung NIE vor der
// Enthüllung (nur die Stimm-ANZAHL reist live), kein correctIndex im
// Player-View, letzteFrage bleibt bis zur Enthüllung null.
//
// Aufruf: npx tsx tools/bots/strategies/einer-gegen-alle.ts [--seed 15]
import { einerGegenAllePlugin } from "../../../server/minigames/einer-gegen-alle/index";
import type { Question } from "../../../shared/content";
import {
  EGA_BEIDE_MM,
  EGA_SOLO_MM,
  EGA_TEAM_MM,
} from "../../../shared/minigames/einer-gegen-alle.meta";
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
  ["Wer tritt allein an?", ["Der Letzte", "Der Führende", "Der GM", "Niemand"], 1],
  ["Was zählt für die Menge?", ["Die Mehrheit", "Der Lauteste", "Das Los", "Nichts"], 0],
  ["Was bringt der Solo-Coup?", ["100", "150", "400", "Nichts"], 2],
  ["Wann fällt das Los?", ["Bei Gleichstand", "Immer", "Nie", "Montags"], 0],
  ["Was sieht der Solist vorab?", ["Alles", "Die Verteilung", "Nichts", "Die Namen"], 2],
  ["Was kostet Schweigen der Menge?", ["Nichts", "Die Frage (= falsch)", "500", "Applaus"], 1],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `ega-bot-${i + 1}`,
  kind: "choice4",
  category: "affen",
  difficulty: "medium",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const NAMEN = ["Solo-Sofia", "Chor-Carl", "Chor-Clara", "Chor-Chris", "Mecker-Micha"];
// Sofia führt den Zwischenstand an ⇒ das Plugin setzt SIE aufs Podest.
const STARTKAPITAL: Record<string, number> = {
  "Solo-Sofia": 2_500,
  "Chor-Carl": 900,
  "Chor-Clara": 800,
  "Chor-Chris": 700,
  "Mecker-Micha": 600,
};

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 15;
}

interface EgaBotView {
  questionId?: string;
  frageNonce?: number;
  phase?: string;
  finished?: boolean;
  frageNr?: number;
  solist?: string;
  duBistSolist?: boolean;
  stimmenAbgegeben?: number;
  mengeGroesse?: number;
  letzteFrage?: {
    solistRichtig: boolean;
    mengeChoice: number | null;
    mengeRichtig: boolean;
    gleichstand: boolean;
    verteilung: number[];
    deltas: Record<string, number>;
  } | null;
  ergebnis?: {
    neutral: boolean;
    abgebrochen: boolean;
    soloPunkte: number;
    teamPunkte: number;
    sieger: string | null;
  } | null;
  correctIndex?: unknown;
  answers?: unknown;
  antworten?: unknown;
  verteilung?: unknown;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);
  // meta.roundBased: EIN init() für die ganze Runde — 6 Duell-Fragen injiziert.
  const server = await starteTestServer({ plugin: einerGegenAllePlugin, fragen: FRAGEN, seed });
  const runde = await spawneRunde(server, NAMEN, "einer-gegen-alle-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  const sofiaId = idVon.get("Solo-Sofia")!;

  // ---------- GM verteilt Startkapital (Zwischenstand-Basis) ----------
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
  runde.log("Startkapital: Sofia 2500 (die Führende!), Menge 600–900 MM");

  // ---------- Beobachtungs-Sammler (Beweis-Grundlage) ----------
  let losF4RichtigGezogen: boolean | null = null; // Los-Ausgang der Gleichstands-Frage
  let gleichstandGesehen = false;
  let stummeMengeFalsch = false; // F6: keine Stimmen ⇒ Menge falsch

  runde.screen.onView((view) => {
    const mg = view.minigame?.view as EgaBotView | null;
    if (!mg?.questionId || view.phase !== "frage") return;
    if (mg.phase === "enthuellung" && mg.letzteFrage) {
      const f = mg.letzteFrage;
      if ((mg.frageNr ?? 0) === 4 && f.gleichstand) {
        gleichstandGesehen = true;
        losF4RichtigGezogen = f.mengeRichtig;
      }
      if ((mg.frageNr ?? 0) === 6 && f.mengeChoice === null && !f.mengeRichtig) {
        stummeMengeFalsch = true;
      }
    }
  });

  // ---------- Spieler-Bots (Drehbuch über frageNr) ----------
  for (const { bot, playerId, name } of runde.spieler) {
    const beantwortet = new Set<number>();
    bot.onView((view) => {
      const mg = view.minigame?.view as EgaBotView | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const minigameId = view.minigame.id;
      const istSolist = mg.duBistSolist === true;

      // LEAK-WACHEN: die Mengen-Verteilung existiert im Frage-Fenster in
      // KEINEM View (erst der Enthüllungs-Beat trägt sie), correctIndex und
      // Server-Antworten bleiben auf dem Server.
      if (mg.correctIndex !== undefined) {
        runde.probleme.push(`${name}: correctIndex leakt im Player-View!`);
      }
      if (mg.answers !== undefined || mg.antworten !== undefined) {
        runde.probleme.push(`${name}: Server-Interna (answers) leaken!`);
      }
      if (mg.verteilung !== undefined) {
        runde.probleme.push(`${name}: Stimm-Verteilung leakt außerhalb des Beats!`);
      }
      if (istSolist && mg.phase === "frage" && mg.letzteFrage != null) {
        runde.probleme.push("Sofia sieht den Beat (Verteilung) schon im Frage-Fenster!");
      }
      if (mg.finished) return;

      // Antworten nach Drehbuch (frageNr 1–6).
      const nonce = mg.frageNonce ?? 0;
      const frageNr = mg.frageNr ?? 0;
      if (mg.phase !== "frage" || beantwortet.has(nonce) || frageNr < 1) return;
      beantwortet.add(nonce);
      const korrekt = ANTWORT.get((mg.questionId ?? "").split("~")[0]) ?? 0;
      const falschWahl = (korrekt + 1) % 4;
      const zweiteFalsch = (korrekt + 2) % 4;

      let choice: number | null;
      if (istSolist) {
        // Sofia: F3 + F5 falsch, sonst richtig.
        choice = frageNr === 3 || frageNr === 5 ? falschWahl : korrekt;
      } else {
        const istVierterChor = name === "Mecker-Micha";
        const istDritterChor = name === "Chor-Chris";
        switch (frageNr) {
          case 1: // Menge 3:1 falsch (nur Carl trifft).
            choice = name === "Chor-Carl" ? korrekt : falschWahl;
            break;
          case 2: // Menge 3:1 richtig (nur Micha meckert daneben).
            choice = istVierterChor ? falschWahl : korrekt;
            break;
          case 3: // Menge 3:1 richtig.
            choice = istVierterChor ? falschWahl : korrekt;
            break;
          case 4: // GLEICHSTAND 2:2: Carl+Clara richtig, Chris+Micha falsch.
            choice = istDritterChor || istVierterChor ? falschWahl : korrekt;
            break;
          case 5: // Menge geschlossen falsch (zweite falsche Option).
            choice = zweiteFalsch;
            break;
          default: // F6: die Menge bleibt KOMPLETT STUMM (= falsch).
            choice = null;
        }
      }
      if (choice === null) return;
      const wahl = choice;
      void (async () => {
        await delay(300 + (NAMEN.indexOf(name) + 1) * 130);
        await sende(bot, "player.action", {
          minigameId,
          actionId: "answer",
          payload: { choice: wahl },
          idemKey: `${playerId}-n${nonce}-answer`,
        });
      })();
    });
  }

  // Eine Runde = Vorstellung + 6×(Frage/Enthüllung) + Ergebnis. F6 wartet
  // das volle Stimm-Fenster ab (12 s Stille der Menge).
  await spieleBisEnde(runde, 240_000, { endeNachAufloesungen: 1 });

  // ---------- Auswertung: EXAKTE Abrechnung (inkl. Los-Ausgang F4) ----------
  if (runde.aufloesungen.length !== 1) {
    runde.probleme.push(`Erwartet 1 Auflösung (1 Runde), gesehen: ${runde.aufloesungen.length}`);
  }
  if (!gleichstandGesehen) {
    runde.probleme.push("F4-Gleichstand (2:2) nie im Enthüllungs-Beat gesehen");
  }
  if (!stummeMengeFalsch) {
    runde.probleme.push("F6 (stumme Menge = falsch) nie im Enthüllungs-Beat gesehen");
  }
  const a = runde.aufloesungen[0];
  if (a !== undefined && losF4RichtigGezogen !== null) {
    const mg = a.mgView as EgaBotView;
    const e = mg.ergebnis;
    // F4-Los: richtig gezogen ⇒ beide richtig (alle +150); falsch ⇒ Solo-Coup.
    const sofiaF4 = losF4RichtigGezogen ? EGA_BEIDE_MM : EGA_SOLO_MM;
    const chorF4 = losF4RichtigGezogen ? EGA_BEIDE_MM : 0;
    const erwartetSofia = EGA_SOLO_MM + EGA_BEIDE_MM + sofiaF4 + EGA_SOLO_MM; // F1+F2+F4+F6
    const erwartetChor = EGA_BEIDE_MM + EGA_TEAM_MM + chorF4; // F2+F3+F4
    const erwartetSolo = losF4RichtigGezogen ? 2 : 3;
    if (e?.sieger !== "solist" || e.soloPunkte !== erwartetSolo || e.teamPunkte !== 1) {
      runde.probleme.push(
        `Ausgang falsch: ${JSON.stringify(e)} (erwartet Solist ${erwartetSolo}:1)`,
      );
    }
    for (const r of a.perPlayer) {
      const erwartet = r.playerId === sofiaId ? erwartetSofia : erwartetChor;
      if (r.delta !== erwartet) {
        runde.probleme.push(`Delta falsch: ${r.playerId} hat ${r.delta}, erwartet ${erwartet}`);
      }
    }
    runde.log(
      `Abrechnung exakt (F4-Los zog ${losF4RichtigGezogen ? "RICHTIG → alle +150" : "FALSCH → Solo-Coup"}): ` +
        `Sofia +${erwartetSofia} · Menge je +${erwartetChor} — Sieger: Solist ${erwartetSolo}:1 ✓`,
    );
  }

  stopPolling();
  pruefeKontoKorridor(runde, gmAnpassungen);
  beende(server, runde);
}

void main();
