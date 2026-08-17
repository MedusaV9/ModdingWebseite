// Bot-Lauf Taschendieb: 4 Bots spielen die 4 Fragen der ersten Playlist-Runde
// komplett durch — mit GM-Startkapital, damit es etwas zu klauen gibt.
//   · Kroesus-Kalle (2.000 MM)  richtig, aber langsam (~4 s) — das Klau-Ziel
//   · Diebin-Dana     (800 MM)  richtig nach ~800 ms — gewinnt das Klau-Recht
//   · Mittel-Mia    (1.200 MM)  richtig nach ~1,3 s (F3: Fotofinish-Duell)
//   · Pleite-Paul     (400 MM)  antwortet immer falsch — Kappen-Beweis-Opfer
// Drehbuch (nach POSITION der Frage, die Fragen-Reihenfolge wählt die Engine):
//   F1 Klau beim Reichsten (voller Betrag),
//   F2 Klau prallt am Bananentresor-Schild ab (J6-Hook, injiziert),
//   F3 Anti-Mobbing sperrt das Doppel-Opfer (Dieb muss umschwenken),
//   F4 Klau beim Ärmsten → 25-%-Kappe greift (100 statt 300 MM).
// Kontostände kommen im Plugin ÜBER ctx.match (Engine-Pfad, kein Test-Stub).
//
// Aufruf: npx tsx tools/bots/strategies/taschendieb.ts [--seed 5]
import { taschendiebPlugin } from "../../../server/minigames/taschendieb/index";
import type { Question } from "../../../shared/content";
import { FRAGE_WERTE } from "../../../shared/money";
import { TD_MITMACH_ANTEIL, tdKlauBetrag } from "../../../shared/minigames/taschendieb.meta";
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
  ["Womit bezahlt man bei MONKEY MONEY?", ["Euros", "MONKEY MONEY", "Muscheln", "Kekse"], 1],
  [
    "Wie nennt man einen Affen mit Maske?",
    ["Taschendieb-Affe", "Zahnarzt", "Astronaut", "Bäcker"],
    0,
  ],
  [
    "Was passiert beim Fotofinish?",
    ["Nichts", "Alle verlieren", "Beide gewinnen etwas", "Spiel-Ende"],
    2,
  ],
  [
    "Wieviel darf der Dieb maximal klauen?",
    ["Alles", "Die Hälfte", "25 % des Kontos", "Nur 10 MM"],
    2,
  ],
];
const FRAGEN: Question[] = THEMEN.map(([text, options, answer], i) => ({
  id: `td-bot-${i + 1}`,
  kind: "choice4",
  category: "geld",
  difficulty: "medium",
  text,
  options,
  answer,
  erklaerung: `Richtig ist: ${options[answer]}.`,
}));
const ANTWORT = new Map(FRAGEN.map((f) => [f.id, f.answer]));

const STARTKAPITAL: Record<string, number> = {
  "Kroesus-Kalle": 2_000,
  "Diebin-Dana": 800,
  "Mittel-Mia": 1_200,
  "Pleite-Paul": 400,
};

/** Antwort-Verzögerung pro Bot und Fragen-POSITION (F3: Dana+Mia zeitgleich). */
function antwortDelay(name: string, position: number): number {
  if (position === 3 && (name === "Diebin-Dana" || name === "Mittel-Mia")) return 900;
  switch (name) {
    case "Diebin-Dana":
      return 800;
    case "Mittel-Mia":
      return 1_300;
    case "Pleite-Paul":
      return 1_500;
    default:
      return 4_000; // Kroesus-Kalle
  }
}

function parseSeed(argv: string[]): number {
  const i = argv.indexOf("--seed");
  return i >= 0 ? Number(argv[i + 1]) : 5;
}

async function main(): Promise<void> {
  const seed = parseSeed(process.argv);

  // Runner-seitige Klau-Historie → wandert als letzteOpfer in den nächsten init()
  // (die Engine führt noch keine Klau-Historie über Fragen hinweg — TODO im Plugin).
  const opferHistorie: string[] = [];
  let kalleId = ""; // nach spawn gesetzt (F2: Klau-Schutz-Schild für Kalle)
  let initZaehler = 0;
  const kontoBeiInit: Record<string, number>[] = [];

  const server = await starteTestServer({
    plugin: taschendiebPlugin,
    fragen: FRAGEN,
    seed,
    sliceExtras: (raum) => {
      initZaehler += 1;
      // Kontostands-SNAPSHOT nur für die Runner-Assertions (Kappen-Formel) —
      // das Plugin selbst liest die Stände über ctx.match (Engine-Pfad!).
      const state = raum.state as unknown as {
        order: string[];
        players: Record<string, { balance: number }>;
      };
      kontoBeiInit.push(
        Object.fromEntries(state.order.map((id) => [id, state.players[id].balance])),
      );
      return {
        letzteOpfer: [...opferHistorie],
        // F2: Bananentresor-Schild (J6) auf dem Reichsten — der Klau muss abprallen.
        klauSchutz: initZaehler === 2 ? [kalleId] : [],
      };
    },
  });
  const runde = await spawneRunde(server, Object.keys(STARTKAPITAL), "taschendieb-bots");
  const stopPolling = starteSyncPolling(runde);
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  kalleId = idVon.get("Kroesus-Kalle")!;
  const paulId = idVon.get("Pleite-Paul")!;

  // ---------- GM verteilt Startkapital in der Lobby ----------
  const gmAnpassungen = new Map<string, number>();
  for (const { playerId, name } of runde.spieler) {
    const delta = STARTKAPITAL[name];
    // override: bewusste GM-Entscheidung über dem Soft-Cap (±400) — mit Grund.
    const ack = await runde.gm.emitAck("gm.cmd", {
      cmd: "score.adjust",
      args: { playerId, delta, grund: "startkapital-botlauf", override: true },
      cmdId: `kapital-${name}`,
    });
    if (!ack.ok) throw new Error(`Startkapital für ${name} abgelehnt: ${String(ack.error)}`);
    gmAnpassungen.set(playerId, delta);
  }
  runde.log("Startkapital verteilt: Kalle 2000, Mia 1200, Dana 800, Paul 400 MM");

  // ---------- Spieler-Bots: antworten + (als Dieb) Opfer wählen ----------
  const zieleGesehen: Record<
    number,
    { id: string; waehlbar: boolean; kontostand: number | null }[]
  > = {};
  for (const { bot, playerId, name } of runde.spieler) {
    const beantwortet = new Set<string>();
    const geklaut = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as {
        questionId?: string;
        phase?: string;
        istDieb?: boolean;
        ziele?: { id: string; waehlbar: boolean; kontostand: number | null }[] | null;
        finished?: boolean;
        correctIndex?: unknown;
        aufloesung?: unknown;
      } | null;
      if (!mg?.questionId || view.phase !== "frage" || !view.minigame) return;
      const questionId = mg.questionId;
      const minigameId = view.minigame.id;
      const position = initZaehler; // Frage k läuft nach dem k-ten init()
      // LEAK-CHECKS: Lösung nie vor der Auflösung; das Ziel-Grid NUR beim Dieb.
      if (mg.correctIndex !== undefined && !mg.aufloesung) {
        runde.probleme.push(`${name}: correctIndex leakt im Spieler-View!`);
      }
      if (mg.phase === "opferwahl" && !mg.istDieb && mg.ziele) {
        runde.probleme.push(`${name}: Nicht-Dieb sieht das Ziel-Grid!`);
      }

      // Phase „frage": genau EINE Antwort (richtig/falsch nach Drehbuch).
      if (mg.phase === "frage" && !mg.finished && !beantwortet.has(questionId)) {
        beantwortet.add(questionId);
        const korrekt = ANTWORT.get(questionId) ?? 0;
        const choice = name === "Pleite-Paul" ? (korrekt + 1) % 4 : korrekt;
        void (async () => {
          await delay(antwortDelay(name, position));
          await sende(bot, "player.action", {
            minigameId,
            actionId: "answer",
            payload: { choice },
            idemKey: `${playerId}-${questionId}-answer`,
          });
        })();
      }

      // Phase „opferwahl": der Dieb greift zu — F1–F3 beim Reichsten (gierig,
      // auch wenn das Schild sichtbar ist), F4 beim Ärmsten (Kappen-Beweis).
      if (mg.phase === "opferwahl" && mg.istDieb && mg.ziele && !geklaut.has(questionId)) {
        geklaut.add(questionId);
        zieleGesehen[position] = mg.ziele;
        const waehlbare = mg.ziele.filter((z) => z.waehlbar);
        const sortiert = [...waehlbare].sort((a, b) => (b.kontostand ?? 0) - (a.kontostand ?? 0));
        const ziel = position === 4 ? sortiert[sortiert.length - 1] : sortiert[0];
        if (!ziel) return;
        void (async () => {
          await delay(600);
          await sende(bot, "player.action", {
            minigameId,
            actionId: "steal",
            payload: { targetId: ziel.id },
            idemKey: `${playerId}-${questionId}-steal`,
          });
          runde.log(`${name} ist der Dieb (F${position}) und klaut bei ${ziel.id}`);
        })();
      }
    });
  }

  // Klau-Historie fürs nächste init() aus den Auflösungen speisen.
  runde.screen.onView((view) => {
    const mg = view.minigame?.view as {
      aufloesung?: { klau?: { von?: string | null } | null } | null;
    } | null;
    if (view.phase !== "aufloesung" || !mg?.aufloesung?.klau?.von) return;
    // Pro Frage genau einmal anhängen (die Auflösung wird mehrfach gesnapshottet).
    if (runde.aufloesungen.length > opferHistorie.length) {
      opferHistorie.push(mg.aufloesung.klau.von);
    }
  });

  await spieleBisEnde(runde, 60_000, { endeNachAufloesungen: FRAGEN.length });

  // ---------- Drehbuch-Beweise über die Auflösungen (nach Position) ----------
  if (runde.aufloesungen.length < FRAGEN.length) {
    runde.probleme.push(`Nur ${runde.aufloesungen.length}/${FRAGEN.length} Fragen aufgelöst`);
  }
  runde.aufloesungen.forEach((a, index) => {
    const position = index + 1;
    const frage = FRAGEN.find((f) => f.id === a.questionId);
    if (!frage) {
      runde.probleme.push(`F${position}: unbekannte Frage ${a.questionId}`);
      return;
    }
    const klau = (
      a.mgView.aufloesung as {
        klau: { von: string; zu: string; betrag: number; abgeprallt: boolean } | null;
      }
    ).klau;
    const fotofinish = (a.mgView.fotofinish as string[]) ?? [];
    const dieb = a.mgView.dieb as string | null;
    if (!klau || dieb === null) {
      runde.probleme.push(`F${position}: kein Klau protokolliert (dieb=${String(dieb)})`);
      return;
    }

    // Erwartete Deltas: Mitmach-Geld + Klau-Nullsumme (Dieb ↔ Opfer).
    const grundwert = FRAGE_WERTE[frage.difficulty];
    for (const r of a.perPlayer) {
      let erwartet = 0;
      if (r.correct === true && r.playerId !== dieb) {
        erwartet = fotofinish.includes(r.playerId)
          ? grundwert
          : Math.round(grundwert * TD_MITMACH_ANTEIL);
      }
      if (r.playerId === dieb) erwartet += klau.betrag;
      if (r.playerId === klau.von) erwartet -= klau.betrag;
      if (r.delta !== erwartet) {
        runde.probleme.push(`F${position}: ${r.playerId} Delta ${r.delta} ≠ erwartet ${erwartet}`);
      }
    }

    // Klau-Betrag gegen Kappe (Kontostand aus dem init-Snapshot dieser Frage).
    const konto = kontoBeiInit[index]?.[klau.von] ?? null;
    const erwarteterBetrag = klau.abgeprallt ? 0 : tdKlauBetrag(frage.difficulty, konto);
    if (klau.betrag !== erwarteterBetrag) {
      runde.probleme.push(
        `F${position}: Klau-Betrag ${klau.betrag} ≠ erwartet ${erwarteterBetrag} (Konto ${String(konto)})`,
      );
    }

    if (position === 1) {
      if (klau.von !== kalleId) {
        runde.probleme.push(`F1: Opfer ${klau.von} ≠ Kroesus-Kalle (Reichster)`);
      } else {
        runde.log(`F1: Klau beim Reichsten — ${klau.betrag} MM von Kalle ✓`);
      }
    }
    if (position === 2) {
      if (!klau.abgeprallt || klau.betrag !== 0) {
        runde.probleme.push(`F2: Klau-Schutz griff nicht (abgeprallt=${String(klau.abgeprallt)})`);
      } else {
        runde.log("F2: Bananentresor-Schild — Klau prallt ab (0 MM) ✓");
      }
    }
    if (position === 3) {
      const kalleZiel = zieleGesehen[3]?.find((z) => z.id === kalleId);
      if (kalleZiel && kalleZiel.waehlbar) {
        runde.probleme.push("F3: Anti-Mobbing — Kalle müsste gesperrt sein (waehlbar=false)");
      }
      if (klau.von === kalleId) {
        runde.probleme.push("F3: Anti-Mobbing verletzt — Kalle wurde zum 3. Mal Opfer");
      } else {
        runde.log(`F3: Anti-Mobbing — Dieb musste umschwenken (Opfer ${klau.von}) ✓`);
      }
      runde.log(
        fotofinish.length > 0
          ? `F3: FOTOFINISH ausgelöst — ${fotofinish.join(",")} bekommt vollen Grundwert ✓`
          : "F3: kein Fotofinish (Timing-Jitter > 50 ms) — Regel bleibt unit-getestet",
      );
    }
    if (position === 4) {
      if (klau.von !== paulId) {
        runde.probleme.push(`F4: Opfer ${klau.von} ≠ Pleite-Paul (Ärmster)`);
      } else if (klau.betrag >= 300) {
        runde.probleme.push(`F4: Kappe griff nicht — Betrag ${klau.betrag}`);
      } else {
        runde.log(
          `F4: 25-%-Kappe — statt 300 nur ${klau.betrag} MM von Paul (Konto ${String(kontoBeiInit[index]?.[paulId])}) ✓`,
        );
      }
    }
  });

  stopPolling();
  pruefeKontoKorridor(runde, gmAnpassungen);
  beende(server, runde);
}

void main();
