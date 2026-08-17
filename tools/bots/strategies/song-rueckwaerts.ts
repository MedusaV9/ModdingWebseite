// Bot-Lauf „Rückwärts-Banane": 3 Bots raten 3 rückwärts gespielte Songs
// GLEICHZEITIG (kein Buzzer — Simultan-MC mit Speed-Bonus); der Song kommt
// pro Frage aus einem rotierenden Fixture-Pack (songs-Slice-Vertrag).
//   · Speedy-Sina  antwortet SOFORT richtig  ⇒ Grundwert + voller Speed-Bonus
//   · Bummel-Ben   antwortet nach ~9 s richtig ⇒ Grundwert + kleinerer Bonus
//   · Falsch-Frida antwortet sofort FALSCH   ⇒ 0 MM
// Der Lauf beweist end-zu-end: Simultan-Antworten, Speed-Bonus-Ordnung
// (Sina > Ben > Grundwert), falsch = 0, Abspielplan (Erst-Play + Auto-Replay)
// und den Aha-Moment (Vorwärts-Intro-URL erscheint ERST mit der Auflösung).
//
// Aufruf: npx tsx tools/bots/strategies/song-rueckwaerts.ts [--seed 7]
import { songRueckwaertsPlugin } from "../../../server/minigames/song-rueckwaerts/index";
import type { Question } from "../../../shared/content";
import { RB_TIMER_MS } from "../../../shared/minigames/song-rueckwaerts.meta";
import { FRAGE_WERTE, fragenGewinn, type Schwierigkeit } from "../../../shared/money";
import { FIXTURE_SONGS } from "../../../shared/songs";
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

const FRAGEN: Question[] = [1, 2, 3].map((n) => ({
  id: `rb-bot-${n}`,
  kind: "choice4",
  category: "musik",
  difficulty: "medium",
  text: `Rückwärts-Song ${n}: Was läuft da?`,
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
  let initNr = 0;
  const server = await starteTestServer({
    plugin: songRueckwaertsPlugin,
    fragen: FRAGEN,
    seed,
    sliceExtras: () => {
      const start = initNr++ % FIXTURE_SONGS.length;
      return { songs: [...FIXTURE_SONGS.slice(start), ...FIXTURE_SONGS.slice(0, start)] };
    },
  });
  const runde = await spawneRunde(
    server,
    ["Speedy-Sina", "Bummel-Ben", "Falsch-Frida"],
    "rueckwaerts-banane",
  );
  const stopPolling = starteSyncPolling(runde);

  // GM-Spickzettel des RUNNERS (Spieler-Views tragen die Lösung nie).
  const korrekt = new Map<string, number>();
  runde.gm.onView((view) => {
    const mg = view.minigame?.view as { questionId?: string; correctIndex?: number } | null;
    if (mg?.questionId !== undefined && mg.correctIndex !== undefined) {
      korrekt.set(mg.questionId, mg.correctIndex);
    }
  });

  interface RbBotView {
    questionId?: string;
    finished?: boolean;
    correctIndex?: unknown;
    titel?: unknown;
    aufloesung?: unknown;
  }

  const profile = [
    { name: "Speedy-Sina", wartezeitMs: 0, richtig: true },
    { name: "Bummel-Ben", wartezeitMs: 9_000, richtig: true },
    { name: "Falsch-Frida", wartezeitMs: 0, richtig: false },
  ];

  for (let i = 0; i < profile.length; i++) {
    const profil = profile[i];
    const { bot, playerId } = runde.spieler[i];
    const gespielt = new Set<string>();
    bot.onView((view) => {
      const mg = view.minigame?.view as RbBotView | null;
      if (!mg?.questionId || !view.minigame) return;
      // LEAK-CHECK: Titel/Lösung dürfen vor der Auflösung NIE im Spieler-View stehen.
      if (!mg.aufloesung && (mg.correctIndex !== undefined || mg.titel !== undefined)) {
        runde.probleme.push(`${profil.name}: Lösung leakt im Spieler-View!`);
      }
      if (view.phase !== "frage" || mg.finished || gespielt.has(mg.questionId)) return;
      const qid = mg.questionId;
      const minigameId = view.minigame.id;
      gespielt.add(qid);
      void (async () => {
        if (profil.wartezeitMs > 0) await delay(profil.wartezeitMs);
        // Auf den GM-Spickzettel warten (View-Race bei Sofort-Antworten):
        // der Runner kennt die Lösung NUR aus dem GM-View, nie vom Spieler.
        for (let warte = 0; warte < 40 && !korrekt.has(qid); warte++) await delay(100);
        const richtig = korrekt.get(qid) ?? 0;
        const choice = profil.richtig ? richtig : (richtig + 1) % 4;
        const antwort = await sende(bot, "player.action", {
          minigameId,
          actionId: "answer",
          payload: { choice },
          idemKey: `${playerId}-${qid}-answer`,
        });
        if (!antwort?.ok) {
          runde.probleme.push(`${profil.name}: answer abgelehnt (${String(antwort?.error)})`);
          return;
        }
        runde.log(
          `${profil.name} tippt ${qid} nach ~${profil.wartezeitMs} ms ` +
            `(${profil.richtig ? "richtig" : "absichtlich falsch"})`,
        );
      })();
    });
  }

  await spieleBisEnde(runde, 90_000, { endeNachAufloesungen: FRAGEN.length });

  // ---------- Beweis: Speed-Bonus-Ordnung + Abspielplan + Aha-Moment ----------
  if (runde.aufloesungen.length < FRAGEN.length) {
    runde.probleme.push(`Nur ${runde.aufloesungen.length}/${FRAGEN.length} Songs aufgelöst`);
  }
  const idVon = new Map(runde.spieler.map((s) => [s.name, s.playerId]));
  for (const a of runde.aufloesungen) {
    const mg = a.mgView as unknown as {
      schwierigkeit: Schwierigkeit;
      abspielplan: number[];
      medien?: { rueckwaertsUrl?: string; introUrl?: string | null };
      aufloesung: { titel: string };
    };
    const deltaVon = new Map(a.perPlayer.map((r) => [r.playerId, r.delta]));
    const sina = deltaVon.get(idVon.get("Speedy-Sina")!) ?? NaN;
    const ben = deltaVon.get(idVon.get("Bummel-Ben")!) ?? NaN;
    const frida = deltaVon.get(idVon.get("Falsch-Frida")!) ?? NaN;
    const grundwert = FRAGE_WERTE[mg.schwierigkeit];

    if (!(sina > ben)) {
      runde.probleme.push(`${a.questionId}: Speed-Bonus verletzt — Sina ${sina} ≤ Ben ${ben}`);
    }
    if (!(ben >= grundwert)) {
      runde.probleme.push(`${a.questionId}: Ben ${ben} < Grundwert ${grundwert}`);
    }
    // Deckel = Sofort-Antwort-Maximum (Grundwert + voller Bonus, 10er-gerundet).
    if (!(sina <= fragenGewinn(mg.schwierigkeit, 0, RB_TIMER_MS))) {
      runde.probleme.push(`${a.questionId}: Sina ${sina} > Grundwert + max. Bonus`);
    }
    if (frida !== 0) {
      runde.probleme.push(`${a.questionId}: Frida ${frida} ≠ 0 (falsch getippt)`);
    }
    if (mg.abspielplan.length < 2) {
      runde.probleme.push(`${a.questionId}: Abspielplan hat nur ${mg.abspielplan.length} Slots`);
    }
    if (!mg.medien?.rueckwaertsUrl?.includes("rueckwaerts5s")) {
      runde.probleme.push(`${a.questionId}: Screen-View ohne rueckwaerts5s-URL`);
    }
    if (typeof mg.medien?.introUrl !== "string") {
      runde.probleme.push(`${a.questionId}: Aha-Moment fehlt — introUrl nicht gesetzt`);
    }
    if (runde.probleme.length === 0) {
      runde.log(
        `${a.questionId} („${mg.aufloesung.titel}", ${mg.schwierigkeit}): ` +
          `Sina +${sina} > Ben +${ben} > Frida ${frida} — Speed-Bonus + Aha-Intro bewiesen ✓`,
      );
    }
  }

  stopPolling();
  pruefeKontoKorridor(runde, new Map());
  beende(server, runde);
}

void main();
