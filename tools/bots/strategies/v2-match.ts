// v2-Match-Runner: 4 Bots spielen ein KOMPLETTES Marathon-Match mit der
// v2-Playlist (15 Runden inkl. monkey-market, bananen-boerse, bananen-bluff,
// affen-auktion, lianensteg-duell, goldener-affe + Jackpot + Finale) gegen
// einen ECHTEN Server.
// Show-Tempo-Settings für den Bot-Beweis: autoGm aus (keine +10-s-Gnaden),
// rad aus, kategorienWahl aus, kurzeShow an — sonst sprengt der Marathon
// jede Watchdog-Kappe. Die Spieler-Logik entspricht dem generischen Bot
// (tools/bots/index.ts): answer/choice, buzz, einsatz-Fenster, Schätz-Slider,
// BANK!, Sitzkreis-Fragen — die v2-Formate laufen bewusst ÜBER GENAU DIESE
// generischen Drähte (Design-Vorgabe der v2-Welle).
// Erfolgs-Kriterien: Match erreicht „ende", ALLE 4 v2-Runden wurden gespielt,
// Endstand mit endlichen Kontoständen.
//
// Aufruf: npx tsx tools/bots/strategies/v2-match.ts [--seed 42] [--url http://localhost:8231]
import { setTimeout as delay } from "node:timers/promises";
import { createRng, type Rng } from "../../../shared/rng";
import { createBotClient, sendeHello, type BotClient, type BotView } from "../client";

const V2_FORMATE = [
  "monkey-market",
  "bananen-boerse",
  "bananen-bluff",
  "affen-auktion",
  // v2-Welle 2 (Agent E): Duell-Bracket + Finale-Alternative — beide laufen
  // über die generischen Drähte (answer/choice, Schätz-Slider) plus Timeouts
  // für die Wett-/Herausforderungs-Fenster.
  "lianensteg-duell",
  "goldener-affe",
  // Buzz-Welle 3 (Agent Buzz): beide laufen über die generischen Drähte —
  // Ziel-Wahl/Herausforderung/Wetten regeln die Server-Timeouts (Default-Ziel
  // ist der sauberste Gegner, Default-Gegner der Führende, Wetten optional).
  "bananen-tortenschlacht",
  "bananen-boxkampf",
  // Duell-Welle 4: Konter-Quiz (Herausforderungs-Timeout wählt den Führenden,
  // Duellanten antworten über answer/choice) + Wer singt's? (Simultan-MC über
  // answer/choice — Optionen erscheinen erst im Rate-Fenster).
  "konter-quiz",
  "wer-singts",
  // Klassiker-Welle 4: Risiko-Leiter (Entscheidungs-Draht „entscheidung" +
  // answer/choice für Kletterer) + Einer gegen alle (Solist UND Menge
  // antworten über die generischen answer/choice-Drähte).
  "risiko-leiter",
  "einer-gegen-alle",
];
// Klassiker-Welle 4: die Playlist wuchs auf 25 Runden (+ risiko-leiter mit
// 8 Entscheidungs-/Frage-Fenstern + einer-gegen-alle) — die alte 35-min-Kappe
// riss mitten im Finale (Frage 124/128), obwohl alle Runden sauber liefen.
const MAX_MATCH_MS = 45 * 60_000;
const WATCHDOG_MS = 90_000;

interface Args {
  url: string;
  seed: number;
}

function parseArgs(argv: string[]): Args {
  const hole = (flag: string): string | undefined => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  return {
    url: hole("--url") ?? `http://localhost:${process.env.PORT ?? 8080}`,
    seed: Number(hole("--seed") ?? 42),
  };
}

/** Generische Spieler-Logik (Spiegel von tools/bots/index.ts, ohne Chaos). */
function spielerBot(bot: BotClient, meineId: string, rng: Rng, log: (t: string) => void): void {
  const beantwortet = new Set<string>();
  const eingesetzt = new Set<string>();
  const gebanktBei = new Set<string>();
  const bereitGemeldet = new Set<number>();
  const gevotet = new Set<number>();
  let aktionNr = 0;

  const idem = (): string => `v2-${meineId}-${aktionNr++}`;
  const wartezeit = (): number => 500 + rng.int(900);
  const sende = (event: string, payload: Record<string, unknown>, was: string): void => {
    void delay(wartezeit()).then(async () => {
      try {
        await bot.emitAck(event, { ...payload, idemKey: idem() });
      } catch {
        // ACK-Timeout im Phasen-Race — kein Invarianten-Bruch.
      }
      log(`${bot.name} ${was}`);
    });
  };

  bot.onView((view: BotView) => {
    if (view.phase === "erklaerkarte" && view.erklaerkarte) {
      const ek = view.erklaerkarte;
      if (!bereitGemeldet.has(ek.endetAt) && !ek.bereit.includes(meineId)) {
        bereitGemeldet.add(ek.endetAt);
        sende("phase.ready", { was: "bereit" }, "ist bereit");
      }
    }

    if (view.phase === "frage" && view.minigame) {
      const mg = view.minigame.view as {
        questionId?: string;
        frageNonce?: number;
        finished?: boolean;
        options?: unknown[] | null;
        frage?: { options?: unknown[] } | null;
        endsAt?: number;
        buzzAktiv?: boolean;
        phase?: string;
        einsatzMax?: number;
        yourEinsatz?: unknown;
        pott?: number;
        eingabeMin?: number;
        eingabeMax?: number;
        yourTipp?: unknown;
        stufeNr?: number;
        duKletterst?: boolean;
        deineWahl?: unknown;
      };
      const key = `${view.frageNr}:${mg.questionId ?? "x"}:${mg.frageNonce ?? 0}:${mg.endsAt ?? 0}`;
      // Risiko-Leiter-Entscheidungs-Fenster: Bot-Persönlichkeit „mutig bis
      // Stufe 5, danach Kasse" — hält das Show-Tempo hoch (Timeout wäre
      // ohnehin WEITER, aber der frühe Klick schließt das Fenster sofort).
      if (
        mg.phase === "entscheidung" &&
        mg.duKletterst === true &&
        (mg.deineWahl === null || mg.deineWahl === undefined) &&
        !eingesetzt.has(`rl-${key}`)
      ) {
        eingesetzt.add(`rl-${key}`);
        const wahl = (mg.stufeNr ?? 1) <= 4 + rng.int(3) ? "weiter" : "absichern";
        sende(
          "player.action",
          { minigameId: view.minigame.id, actionId: "entscheidung", payload: { wahl } },
          wahl === "weiter" ? "klettert weiter 🧗" : "macht Kasse 💰",
        );
      }
      // Setz-/Bieter-Fenster (alles-oder-banane UND affen-auktion — dieselbe
      // Setz-Konvention: einsatzMax + yourEinsatz + actionId "einsatz").
      if (
        mg.phase === "setzen" &&
        typeof mg.einsatzMax === "number" &&
        (mg.yourEinsatz === null || mg.yourEinsatz === undefined) &&
        !eingesetzt.has(key)
      ) {
        eingesetzt.add(key);
        const betrag = Math.max(100, Math.round((mg.einsatzMax * 0.6) / 50) * 50);
        sende(
          "player.action",
          { minigameId: view.minigame.id, actionId: "einsatz", payload: { betrag } },
          `setzt/bietet ${betrag} MM`,
        );
      }
      // Schätz-Slider (bananen-tresor).
      if (
        typeof mg.eingabeMin === "number" &&
        typeof mg.eingabeMax === "number" &&
        (mg.yourTipp === null || mg.yourTipp === undefined) &&
        !mg.finished &&
        !beantwortet.has(key)
      ) {
        beantwortet.add(key);
        const spanne = Math.max(0, mg.eingabeMax - mg.eingabeMin);
        sende(
          "player.action",
          {
            minigameId: view.minigame.id,
            actionId: "einloggen",
            payload: { wert: mg.eingabeMin + rng.int(spanne + 1) },
          },
          "loggt eine Schätzung ein",
        );
      }
      // Antworten: choice-Formate (inkl. Sitzkreis-Nested) oder Buzzer.
      const optionen = Array.isArray(mg.options)
        ? mg.options
        : Array.isArray(mg.frage?.options)
          ? mg.frage.options
          : null;
      const optionenDa = optionen !== null && optionen.length > 0;
      if (mg.questionId && !mg.finished && !beantwortet.has(key) && (mg.buzzAktiv || optionenDa)) {
        beantwortet.add(key);
        if (mg.buzzAktiv) {
          sende("buzz", { minigameId: view.minigame.id, pressedAtServerEst: Date.now() }, "buzzt");
        } else {
          const wahl = rng.int(Math.max(1, optionen?.length ?? 4));
          sende(
            "player.action",
            { minigameId: view.minigame.id, actionId: "answer", payload: { choice: wahl } },
            `antwortet ${["A", "B", "C", "D"][wahl] ?? wahl}`,
          );
        }
      }
      // Affenbank: gelegentlich BANK!
      if (typeof mg.pott === "number" && mg.pott > 0 && !gebanktBei.has(key) && rng.int(100) < 15) {
        gebanktBei.add(key);
        sende(
          "player.action",
          { minigameId: view.minigame.id, actionId: "bank", payload: {} },
          `drückt BANK! (${mg.pott} MM)`,
        );
      }
    }

    if (view.voting && !gevotet.has(view.voting.endetAt)) {
      gevotet.add(view.voting.endetAt);
      sende(
        "vote.cast",
        { option: rng.int(Math.max(1, view.voting.optionen.length)) },
        "stimmt ab",
      );
    }
  });
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const rng = createRng(args.seed);
  const log = (text: string) => console.log(`[v2-match] ${text}`);
  log(`Marathon mit v2-Playlist gegen ${args.url} (Seed ${args.seed}, Show-Tempo-Settings)`);

  const alle: BotClient[] = [];
  const probleme: string[] = [];
  const phasenGesehen = new Set<string>();
  const rundenGesehen = new Map<string, number>(); // minigameId → rundeNr

  const screen = createBotClient(args.url, "Screen");
  alle.push(screen);
  const raum = await screen.emitAck("room.create", { role: "screen", origin: args.url });
  if (!raum.ok) throw new Error(`room.create fehlgeschlagen: ${String(raum.error)}`);
  const code = raum.code as string;
  const gmPin = raum.gmPin as string;
  await sendeHello(screen, { roomCode: code, role: "screen", origin: args.url });
  log(`Raum ${code} eröffnet`);

  screen.onView((view) => {
    phasenGesehen.add(view.phase);
    const a = view.abschnitt;
    if (a?.typ === "runde" && !rundenGesehen.has(a.minigameId)) {
      rundenGesehen.set(a.minigameId, a.rundeNr);
    }
  });

  const farben = ["gelb", "rot", "gruen", "blau"];
  for (let i = 1; i <= 4; i++) {
    const bot = createBotClient(args.url, `Bot-${i}`);
    alle.push(bot);
    const welcome = await sendeHello(bot, {
      roomCode: code,
      role: "player",
      name: `Bot-${i}`,
      avatar: farben[i - 1],
    });
    spielerBot(bot, welcome.playerId as string, rng, log);
  }
  log("4 Bots in der Lobby");

  const gm = createBotClient(args.url, "GM");
  alle.push(gm);
  await sendeHello(gm, { roomCode: code, role: "gm", gmPin });
  const settings = await gm.emitAck("gm.cmd", {
    cmd: "settings.set",
    args: {
      modus: "marathon",
      jokerAn: false, // Tempo: keine Joker-Show-Momente im Bot-Beweis
      v2Formate: true, // die v2-Welle EXPLIZIT an (Default wäre ohnehin an)
      autoGm: false,
      rad: "aus",
      kategorienWahl: "aus",
      kurzeShow: true,
    },
    cmdId: "settings-v2",
  });
  if (!settings.ok) throw new Error(`settings.set fehlgeschlagen: ${String(settings.error)}`);
  const start = await gm.emitAck("gm.cmd", { cmd: "flow.next", args: {}, cmdId: "start-1" });
  if (!start.ok) throw new Error(`Match-Start fehlgeschlagen: ${String(start.error)}`);
  log("GM startet den Marathon (v2Formate an, Show-Tempo)");

  // Bis „ende" laufen lassen — Fortschritts-Watchdog wie im generischen Runner.
  let letztePhase = "";
  let letzteSignatur = "";
  let letzterWechsel = performance.now();
  const startZeit = performance.now();
  for (;;) {
    const phase = screen.view?.phase ?? "?";
    if (phase !== letztePhase) {
      letztePhase = phase;
      const a = screen.view?.abschnitt;
      log(
        `Phase: ${phase}` +
          (a ? ` (${a.typ}${a.typ === "runde" ? ` R${a.rundeNr}` : ""} · ${a.minigameId})` : "") +
          (phase === "frage" ? ` — Frage ${screen.view?.frageNr}/${screen.view?.frageTotal}` : ""),
      );
    }
    const signatur = `${phase}|${screen.view?.frageNr ?? 0}|${JSON.stringify(screen.view?.minigame?.view ?? null)}`;
    if (signatur !== letzteSignatur) {
      letzteSignatur = signatur;
      letzterWechsel = performance.now();
    }
    if (phase === "ende") break;
    if (performance.now() - letzterWechsel > WATCHDOG_MS) {
      probleme.push(`Hängender Fortschritt: Phase ${phase} > ${WATCHDOG_MS} ms`);
      break;
    }
    if (performance.now() - startZeit > MAX_MATCH_MS) {
      probleme.push(`Match nicht in ${MAX_MATCH_MS / 60_000} min beendet`);
      break;
    }
    await delay(200);
  }
  const dauerMin = ((performance.now() - startZeit) / 60_000).toFixed(1);

  // ---------- Auswertung: v2-Runden gespielt + Match komplett ----------
  for (const p of ["frage", "aufloesung", "siegerehrung", "ende"]) {
    if (!phasenGesehen.has(p)) probleme.push(`Phase nie gesehen: ${p}`);
  }
  for (const id of V2_FORMATE) {
    if (!rundenGesehen.has(id)) probleme.push(`v2-Runde nie gespielt: ${id}`);
  }
  const standings = screen.view?.standings ?? [];
  if (standings.length !== 4) probleme.push(`Endstand hat ${standings.length} statt 4 Spieler`);
  log(`— Endstand (nach ${dauerMin} min, ${screen.view?.frageTotal ?? "?"} Fragen) —`);
  for (const [i, s] of standings.entries()) {
    log(`  ${i + 1}. ${s.name}: ${s.balance} MM`);
    if (!Number.isFinite(s.balance)) probleme.push(`Kontostand kaputt: ${s.name} = ${s.balance}`);
  }
  const reihenfolge = [...rundenGesehen.entries()].sort((a, b) => a[1] - b[1]);
  log(`Runden: ${reihenfolge.map(([id, nr]) => `R${nr} ${id}`).join(" · ")}`);

  for (const bot of alle) probleme.push(...bot.fehler);
  for (const bot of alle) bot.close();
  if (probleme.length > 0) {
    console.error("[v2-match] FEHLGESCHLAGEN:");
    for (const p of probleme) console.error(`  ✗ ${p}`);
    process.exit(1);
  }
  log(
    `OK: Marathon MIT v2-Welle komplett durchgespielt (alle ${V2_FORMATE.length} v2-Runden dabei). ✓`,
  );
  process.exit(0);
}

main().catch((err) => {
  console.error("[v2-match] Abbruch:", err);
  process.exit(1);
});
