// Bot-Framework v1: N headless Bots spielen ein KOMPLETTES Match durch — alle
// Engine-Phasen generisch (Kategorien-Voting, Bereit-Meldungen, Antworten,
// Buzzer, Rad-Interaktionen, Votings, Joker-Zufallsnutzung, Feedback).
// Personas (Skill ⇒ Antwort-Tempo, Joker-Lust) + CHAOS-Modus (Random-
// Disconnects/Reconnects mit Session-Token) — Basis für die Test-Wellen.
//
//   npm run bots -- --players 3 --seed 42 --modus quick --joker an [--chaos]
//
// Exit-Code ≠ 0 bei Invarianten-Verletzung (Phasen fehlen, seq rückwärts,
// NaN-Kontostände, hängende Phase > 90 s).
import { setTimeout as delay } from "node:timers/promises";
import { createRng, type Rng } from "../../shared/rng";
import { createBotClient, sendeHello, type BotClient, type BotView } from "./client";

interface Args {
  players: number;
  url: string;
  seed: number;
  modus: "quick" | "klassik" | "marathon";
  joker: boolean;
  chaos: boolean;
  /** Team-Modus „Affenbanden" (ADDITIV): aus | 2er | 2v2v2v2 | frei. */
  teams: "aus" | "2er" | "2v2v2v2" | "frei";
  /** Deterministischer Rad-Test: `--rigRad <segment>:<nachRunde>` — der GM
   * riggt den Dreh im Zwischenstand nach Runde N (z. B. `blackout:2` prüft
   * das Sendeausfall-Szenario direkt vor der Affenbank-Runde im quick-Plan). */
  rigRad: { segment: string; nachRunde: number } | null;
}

/** Persona: Skill steuert das Antwort-Tempo (Speed-Bonus-Pfad), Joker-Lust die Zünd-Rate. */
interface Persona {
  skill: number; // 0..1 — hoch = schnell
  delayMinMs: number;
  delayMaxMs: number;
  jokerLust: number; // Wahrscheinlichkeit pro Frage, einen nutzbaren Joker zu zünden
  chaot: boolean; // Chaos-Modus: zufällige Disconnects/Reconnects
}

function parseArgs(argv: string[]): Args {
  const hole = (flag: string): string | undefined => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  const modus = hole("--modus");
  const teamsFlag = hole("--teams");
  const teams =
    teamsFlag === "2er" || teamsFlag === "2v2v2v2" || teamsFlag === "frei" ? teamsFlag : "aus";
  const rigFlag = hole("--rigRad");
  const rigTeile = rigFlag?.split(":") ?? [];
  const rigRad =
    rigTeile.length === 2 && rigTeile[0].length > 0 && Number.isInteger(Number(rigTeile[1]))
      ? { segment: rigTeile[0], nachRunde: Number(rigTeile[1]) }
      : null;
  return {
    // Team-Modus greift erst ab 4 Spielern ⇒ Default hebt sich passend an.
    players: Number(hole("--players") ?? (teams === "aus" ? 3 : 4)),
    url: hole("--url") ?? `http://localhost:${process.env.PORT ?? 8080}`,
    seed: Number(hole("--seed") ?? 42),
    modus: modus === "klassik" || modus === "marathon" ? modus : "quick",
    joker: hole("--joker") !== "aus",
    chaos: argv.includes("--chaos"),
    teams,
    rigRad,
  };
}

function persona(rng: Rng, index: number, chaos: boolean): Persona {
  const skill = 0.3 + rng.int(65) / 100; // 0,30 … 0,94
  const delayMinMs = 400 + Math.round((1 - skill) * 1800);
  return {
    skill,
    delayMinMs,
    delayMaxMs: delayMinMs + 600 + Math.round((1 - skill) * 2500),
    jokerLust: 0.35,
    chaot: chaos && index >= 2, // Bot-1 bleibt stabil (sonst fehlt ggf. der Quorum-Anker)
  };
}

/** Ein Spieler-Bot: reagiert generisch auf JEDE Phase des PlayerViews. */
function spielerBot(
  bot: BotClient,
  meineId: string,
  p: Persona,
  rng: Rng,
  log: (t: string) => void,
): void {
  const beantwortet = new Set<string>();
  const eingesetzt = new Set<string>();
  const gebanktBei = new Set<string>();
  let teamGewuenscht = false;
  const bereitGemeldet = new Set<number>();
  const kategorieGewaehlt = new Set<number>();
  const radGewaehlt = new Set<number>();
  const gevotet = new Set<number>();
  const jokerGezuendet = new Set<number>();
  let feedbackGesendet = false;
  let aktionNr = 0;

  const idem = (): string => `bot-${meineId}-${aktionNr++}`;
  const wartezeit = (): number => p.delayMinMs + rng.int(p.delayMaxMs - p.delayMinMs);
  const sende = (event: string, payload: Record<string, unknown>, was: string): void => {
    void delay(wartezeit()).then(async () => {
      try {
        await bot.emitAck(event, { ...payload, idemKey: idem() });
      } catch {
        // Timeout/Netz während Chaos — kein Invarianten-Bruch.
      }
      log(`${bot.name} ${was}`);
    });
  };

  bot.onView((view: BotView) => {
    // 0) Team-Modus: in der Lobby einmal ein Wunsch-Team äußern (§1.4) —
    // die Engine erfüllt Wünsche nach Kapazität und balanciert den Rest.
    if (view.phase === "lobby" && view.teams?.wahlOffen && !teamGewuenscht) {
      const angebot = view.teams.teams;
      if (angebot.length > 0 && (view.teams.deinTeam ?? null) === null) {
        teamGewuenscht = true;
        const team = angebot[rng.int(angebot.length)];
        sende("team.wahl", { team: team.id }, `wünscht sich ${team.name}`);
      }
    }

    // 1) Kategorien-Voting: einmal pro Wahl-Fenster zufällig abstimmen.
    if (view.phase === "kategorie-wahl" && view.kategorieWahl) {
      const kw = view.kategorieWahl;
      if (!kategorieGewaehlt.has(kw.endetAt) && kw.optionen.length > 0) {
        kategorieGewaehlt.add(kw.endetAt);
        const wahl = kw.optionen[rng.int(kw.optionen.length)];
        sende("kategorie.vote", { kategorie: wahl }, `wählt Kategorie „${wahl}“`);
      }
    }

    // 2) Erklärkarte: Bereit-Meldung (alle bereit ⇒ Phase endet früher).
    if (view.phase === "erklaerkarte" && view.erklaerkarte) {
      const ek = view.erklaerkarte;
      if (!bereitGemeldet.has(ek.endetAt) && !ek.bereit.includes(meineId)) {
        bereitGemeldet.add(ek.endetAt);
        sende("phase.ready", { was: "bereit" }, "ist bereit");
      }
    }

    // 3) Frage: generisch antworten (choice-Formate) oder buzzen; ab und zu Joker.
    if (view.phase === "frage" && view.minigame) {
      const mg = view.minigame.view as {
        questionId?: string;
        /** Affenbank: monotoner Zähler — zyklisch rotierte Fragen NEU beantworten. */
        frageNonce?: number;
        finished?: boolean;
        options?: unknown[] | null;
        /** Sitzkreis-Formate (Stinkbanane): Frage nur beim Halter, verschachtelt. */
        frage?: { options?: unknown[] } | null;
        endsAt?: number;
        buzzAktiv?: boolean;
        phase?: string;
        // Wettrunde (alles-oder-banane): Setz-Fenster-Felder im Player-View.
        einsatzMax?: number;
        yourEinsatz?: unknown;
        // Affenbank: aktueller Team-Pott (BANK! sichert ihn persönlich).
        pott?: number;
        // Slider-Formate (bananen-tresor): Schätz-Range im Player-View.
        eingabeMin?: number;
        eingabeMax?: number;
        yourTipp?: unknown;
      };
      // endsAt im Key: Halte-Wechsel (Stinkbanane) und Fenster-Wechsel zählen
      // als NEUE Antwort-Gelegenheit (Locks machen Doppel-Versuche zum No-op).
      const key = `${view.frageNr}:${mg.questionId ?? "x"}:${mg.frageNonce ?? 0}:${mg.endsAt ?? 0}`;
      // Wettrunde: im Setz-Fenster den Einsatz einloggen (50er-Raster, Persona-Mut).
      if (
        mg.phase === "setzen" &&
        typeof mg.einsatzMax === "number" &&
        (mg.yourEinsatz === null || mg.yourEinsatz === undefined) &&
        !eingesetzt.has(key)
      ) {
        eingesetzt.add(key);
        const mut = 0.25 + p.skill * 0.75; // Könner setzen höher
        const betrag = Math.max(100, Math.round((mg.einsatzMax * mut) / 50) * 50);
        void delay(wartezeit()).then(async () => {
          try {
            await bot.emitAck("player.action", {
              minigameId: view.minigame!.id,
              actionId: "einsatz",
              payload: { betrag },
              idemKey: idem(),
            });
            log(`${bot.name} setzt ${betrag} MM`);
          } catch {
            /* Netz-Race — ok */
          }
        });
      }
      // Slider-Formate (Schätzen): zufälligen Wert in der Range einloggen.
      if (
        typeof mg.eingabeMin === "number" &&
        typeof mg.eingabeMax === "number" &&
        (mg.yourTipp === null || mg.yourTipp === undefined) &&
        !mg.finished &&
        !beantwortet.has(key)
      ) {
        beantwortet.add(key);
        const spanne = Math.max(0, mg.eingabeMax - mg.eingabeMin);
        const wert = mg.eingabeMin + rng.int(spanne + 1);
        void delay(wartezeit()).then(async () => {
          try {
            await bot.emitAck("player.action", {
              minigameId: view.minigame!.id,
              actionId: "einloggen",
              payload: { wert },
              idemKey: idem(),
            });
            log(`${bot.name} loggt Schätzung ${wert} ein`);
          } catch {
            /* Netz-Race — ok */
          }
        });
      }

      // Antworten NUR, wenn das Frage-Fenster offen ist (Optionen sichtbar) —
      // sonst würde der Antwort-Key in Setz-/Pause-Phasen verpuffen. Sitzkreis-
      // Formate liefern die Optionen verschachtelt (mg.frage, nur beim Halter).
      const optionen = Array.isArray(mg.options)
        ? mg.options
        : Array.isArray(mg.frage?.options)
          ? mg.frage.options
          : null;
      const optionenDa = optionen !== null && optionen.length > 0;
      if (mg.questionId && !mg.finished && !beantwortet.has(key) && (mg.buzzAktiv || optionenDa)) {
        beantwortet.add(key);
        if (mg.buzzAktiv) {
          // Buzzer-Format: buzz statt answer (Server clampt via Median-RTT).
          sende("buzz", { minigameId: view.minigame.id, pressedAtServerEst: Date.now() }, "buzzt");
        } else {
          const anzahl = optionen?.length ?? 4;
          const wahl = rng.int(Math.max(1, anzahl));
          void delay(wartezeit()).then(async () => {
            try {
              const antwort = await bot.emitAck("player.action", {
                minigameId: view.minigame!.id,
                actionId: "answer",
                payload: { choice: wahl },
                idemKey: idem(),
              });
              log(
                `${bot.name} antwortet ${["A", "B", "C", "D"][wahl] ?? wahl}` +
                  (antwort.ok ? "" : ` (abgelehnt: ${String(antwort.error)})`),
              );
            } catch {
              /* Netz-Race — ok */
            }
          });
        }
      }
      // Affenbank: der Verrats-Moment — ab und zu BANK! drücken, wenn Pott da ist.
      if (
        typeof mg.pott === "number" &&
        mg.pott > 0 &&
        !gebanktBei.has(key) &&
        rng.int(100) < 12 + Math.round(p.skill * 10)
      ) {
        gebanktBei.add(key);
        sende(
          "player.action",
          { minigameId: view.minigame.id, actionId: "bank", payload: {} },
          `drückt BANK! (${mg.pott} MM)`,
        );
      }
      // Joker-Zufallsnutzung (einmal pro Frage, mit Persona-Lust).
      if (view.jokers && !jokerGezuendet.has(view.frageNr) && rng.int(100) < p.jokerLust * 100) {
        const nutzbare = view.jokers.filter((j) => j.nutzbar);
        if (nutzbare.length > 0) {
          jokerGezuendet.add(view.frageNr);
          const j = nutzbare[rng.int(nutzbare.length)];
          sende(
            "joker.use",
            { jokerId: j.id, ...(j.id === "schmiergeld" ? { stufe: 1 } : {}) },
            `zündet Joker ${j.id}`,
          );
        }
      }
    }

    // 4) Rad-Interaktionen: gültige Wahl je Typ (long/short, umarmt, ja/nein).
    if (view.phase === "rad" && view.rad?.interaktion) {
      const ia = view.rad.interaktion;
      if (!radGewaehlt.has(ia.endetAt) && (ia.deineWahl === null || ia.deineWahl === undefined)) {
        radGewaehlt.add(ia.endetAt);
        const wahl =
          ia.typ === "long-short"
            ? rng.int(2) === 0
              ? "long"
              : "short"
            : ia.typ === "umarmt"
              ? "umarmt"
              : rng.int(3) > 0
                ? "ja"
                : "nein";
        sende("rad.aktion", { wahl }, `Rad-Aktion: ${wahl}`);
      }
    }

    // 5) GM-Votings/Blitz-Stimmung: zufällige Option.
    if (view.voting && !gevotet.has(view.voting.endetAt)) {
      gevotet.add(view.voting.endetAt);
      const option = rng.int(Math.max(1, view.voting.optionen.length));
      sende("vote.cast", { option }, `stimmt ab (Option ${option})`);
    }

    // 6) Feedback-Freitext (Abspann / GM-Trigger).
    if (view.feedbackAngefragt && !feedbackGesendet) {
      feedbackGesendet = true;
      sende(
        "feedback.text",
        { text: `Banane! ${p.skill > 0.6 ? "Mehr ULTRAHARD bitte." : "War cool."}` },
        "schickt Feedback",
      );
    }
  });
}

/** Chaos-Loop: zufällige Disconnects (2–5 s), dann Reconnect mit Session-Token. */
function chaosLoop(
  bot: BotClient,
  rng: Rng,
  log: (t: string) => void,
  laeuftNoch: () => boolean,
): void {
  void (async () => {
    while (laeuftNoch()) {
      await delay(6000 + rng.int(6000));
      if (!laeuftNoch()) return;
      if (rng.int(100) < 35 && bot.verbunden) {
        log(`💥 ${bot.name} verliert die Verbindung (Chaos)`);
        bot.trenne();
        await delay(2000 + rng.int(3000));
        if (!laeuftNoch()) return;
        await bot.wiederVerbinden();
        log(`🔌 ${bot.name} ist wieder da (Slot-Restore via Token)`);
      }
    }
  })();
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const rng = createRng(args.seed);
  const log = (text: string) => console.log(`[bots] ${text}`);
  log(
    `Starte: ${args.players} Bots gegen ${args.url} (Seed ${args.seed}, Modus ${args.modus}, ` +
      `Joker ${args.joker ? "an" : "aus"}, Chaos ${args.chaos ? "AN" : "aus"}, ` +
      `Teams ${args.teams})`,
  );

  const alle: BotClient[] = [];
  const probleme: string[] = [];
  const phasenGesehen = new Set<string>();
  const momenteGesehen = new Set<string>();
  let fertig = false;

  // 1) Screen-Bot eröffnet den Raum (room.create → hello screen).
  const screen = createBotClient(args.url, "Screen");
  alle.push(screen);
  const raum = await screen.emitAck("room.create", { role: "screen", origin: args.url });
  if (!raum.ok) throw new Error(`room.create fehlgeschlagen: ${raum.error}`);
  const code = raum.code as string;
  const gmPin = raum.gmPin as string;
  await sendeHello(screen, { roomCode: code, role: "screen", origin: args.url });
  log(`Raum ${code} eröffnet (GM-PIN ${gmPin})`);

  // Screen-Bot protokolliert Momente (Joker/Rad/Boost-Inszenierungen) fürs Log.
  let siegerehrungSnapshot: unknown = null;
  screen.onView((view) => {
    phasenGesehen.add(view.phase);
    const momente = (view as { momente?: { id: string; text: string }[] }).momente ?? [];
    for (const m of momente) {
      if (momenteGesehen.has(m.id)) continue;
      momenteGesehen.add(m.id);
      log(`📺 Moment: ${m.text}`);
    }
    const sg = (view as { siegerehrung?: unknown }).siegerehrung;
    if (sg) siegerehrungSnapshot = sg;
    const rad = view.rad as { ergebnis?: { id: string } | null } | null | undefined;
    if (rad?.ergebnis) phasenGesehen.add(`rad:${rad.ergebnis.id}`);
  });

  // 2) Spieler-Bots joinen (Name + Avatar + Persona).
  const farben = ["gelb", "rot", "gruen", "blau", "lila", "orange", "tuerkis", "pink"];
  for (let i = 1; i <= args.players; i++) {
    const p = persona(rng, i, args.chaos);
    const bot = createBotClient(args.url, `Bot-${i}`);
    alle.push(bot);
    const welcome = await sendeHello(bot, {
      roomCode: code,
      role: "player",
      name: `Bot-${i}`,
      avatar: farben[(i - 1) % farben.length],
    });
    const meineId = welcome.playerId as string;
    spielerBot(bot, meineId, p, rng, log);
    if (p.chaot) chaosLoop(bot, rng, log, () => !fertig);
    log(
      `Bot-${i} in der Lobby (Skill ${p.skill.toFixed(2)}, Delay ${p.delayMinMs}–${p.delayMaxMs} ms` +
        `${p.chaot ? ", CHAOT" : ""})`,
    );
  }

  // 3) GM-Bot: Settings (Modus/Joker) setzen, dann Match starten.
  const gm = createBotClient(args.url, "GM");
  alle.push(gm);
  await sendeHello(gm, { roomCode: code, role: "gm", gmPin });
  const settings = await gm.emitAck("gm.cmd", {
    cmd: "settings.set",
    args: { modus: args.modus, jokerAn: args.joker, teams: args.teams },
    cmdId: "settings-1",
  });
  if (!settings.ok) throw new Error(`settings.set fehlgeschlagen: ${settings.error}`);
  // Team-Modus: den Bots kurz Zeit für ihre Lobby-Team-Wünsche lassen.
  if (args.teams !== "aus") await delay(3500);
  const start = await gm.emitAck("gm.cmd", { cmd: "flow.next", args: {}, cmdId: "start-1" });
  if (!start.ok) throw new Error(`Match-Start fehlgeschlagen: ${start.error}`);
  log(
    `GM hat das Match gestartet (${args.modus}, Joker ${args.joker ? "an" : "aus"}, ` +
      `Teams ${args.teams})`,
  );

  // 4) Warten bis „ende" — Watchdog: KEIN sichtbarer Fortschritt > 90 s = Fehler.
  // Fortschritt = jede sichtbare Minigame-View-Änderung (nicht nur Engine-Phasen):
  // Runden-basierte Formate (Affenbank 2×90 s Kette, Stinkbanane 45–75 s Zündschnur)
  // stehen minutenlang in Phase „frage", machen aber laufend View-Fortschritt
  // (frageNonce/Pott/Halter). Die 20-min-Gesamtkappe bleibt das harte Limit.
  let letztePhase = "";
  let letzteSignatur = "";
  let letzterWechsel = performance.now();
  let radGerigt = false;
  const startZeit = performance.now();
  while (true) {
    const phase = screen.view?.phase ?? "?";
    // --rigRad: EIN gerigter GM-Dreh im Zwischenstand nach der Wunsch-Runde.
    if (
      args.rigRad !== null &&
      !radGerigt &&
      phase === "zwischenstand" &&
      screen.view?.abschnitt?.rundeNr === args.rigRad.nachRunde
    ) {
      radGerigt = true;
      const rig = args.rigRad;
      const antwort = await gm.emitAck("gm.cmd", {
        cmd: "wheel.spin",
        args: { rigTarget: rig.segment },
        cmdId: "rig-1",
      });
      log(
        `GM riggt das Rad auf „${rig.segment}“ nach R${rig.nachRunde} ` +
          `(${antwort.ok ? "ok" : `abgelehnt: ${String(antwort.error)}`})`,
      );
    }
    if (phase !== letztePhase) {
      letztePhase = phase;
      const a = screen.view?.abschnitt;
      log(
        `Phase: ${phase}` +
          (a ? ` (${a.typ}${a.typ === "runde" ? ` R${a.rundeNr}` : ""} · ${a.minigameId})` : "") +
          (phase === "frage" ? ` — Frage ${screen.view?.frageNr}/${screen.view?.frageTotal}` : ""),
      );
    }
    // Fortschritt = Screen ODER Handys: Blackout (Rad §5.3/11) friert die
    // Screen-Minigame-View als statisches „Sendeausfall" ein — bei roundBasierten
    // Formaten (Affenbank: 2×90 s Kette = EINE „Frage") minutenlang. Die
    // Spieler-Views rotieren weiter und zählen deshalb als Lebenszeichen.
    const sichten = alle.map((b) => JSON.stringify(b.view?.minigame?.view ?? null)).join("~");
    const signatur = `${phase}|${screen.view?.frageNr ?? 0}|${sichten}`;
    if (signatur !== letzteSignatur) {
      letzteSignatur = signatur;
      letzterWechsel = performance.now();
    }
    if (phase === "ende") {
      await delay(4000); // Gnadenfrist: Feedback-Texte der Bots noch durchlassen
      break;
    }
    if (performance.now() - letzterWechsel > 90_000) {
      probleme.push(`Hängender Fortschritt: Phase ${phase} > 90 s ohne View-Änderung`);
      break;
    }
    if (performance.now() - startZeit > 20 * 60_000) {
      probleme.push("Match nicht in 20 min beendet");
      break;
    }
    await delay(200);
  }
  fertig = true;

  // 5) Invarianten prüfen + Endstand ausgeben.
  const pflichtPhasen = [
    "intro",
    "kategorie-wahl", // ab R2 in jedem Modus (Voting)
    "erklaerkarte",
    "frage",
    "aufloesung",
    "zwischenstand",
    "rad", // jeder Modus hat ≥ 1 garantierten Dreh
    "siegerehrung",
    "ende",
  ];
  for (const p of pflichtPhasen) {
    if (!phasenGesehen.has(p)) probleme.push(`Phase nie gesehen: ${p}`);
  }

  const standings = screen.view?.standings ?? [];
  if (standings.length !== args.players) {
    probleme.push(`Endstand hat ${standings.length} statt ${args.players} Spieler`);
  }
  log("— Endstand —");
  for (const [i, s] of standings.entries()) {
    log(`  ${i + 1}. ${s.name}: ${s.balance} MM`);
    if (!Number.isFinite(s.balance)) probleme.push(`Kontostand kaputt: ${s.name} = ${s.balance}`);
  }
  const sg = siegerehrungSnapshot as {
    awards?: { titel: string; name: string; wert: string }[];
    teams?: { teamId: string; name: string; platz: number; topf: number }[];
  } | null;
  for (const a of sg?.awards ?? []) log(`  🏅 ${a.titel}: ${a.name} (${a.wert})`);

  // Team-Modus: Team-Endstand ausgeben + Invarianten (Topf = Summe, Doppel-Affe ×2).
  if (args.teams !== "aus" && args.players >= 4) {
    const tv = screen.view?.teams;
    if (!tv || tv.teams.length < 2) {
      probleme.push("Team-Modus aktiv, aber kein Team-Endstand in der Screen-View");
    } else {
      log("— Team-Endstand —");
      for (const t of tv.teams) {
        const summe = t.mitglieder.reduce((s, m) => s + m.balance * (m.doppelAffe ? 2 : 1), 0);
        log(
          `  ${t.platz}. ${t.name}: ${t.topf} MM im Topf (` +
            t.mitglieder
              .map((m) => `${m.name} ${m.balance}${m.doppelAffe ? " ×2 🐵🐵" : ""}`)
              .join(", ") +
            ")",
        );
        if (summe !== t.topf) {
          probleme.push(`Team-Topf falsch: ${t.name} ${t.topf} ≠ Mitglieder-Summe ${summe}`);
        }
      }
      if (!sg?.teams || sg.teams.length === 0) {
        probleme.push("Siegerehrung ohne Team-Podest (siegerehrung.teams fehlt)");
      } else {
        const erster = sg.teams.find((t) => t.platz === 1);
        log(`  🏆 Team-Sieger: ${erster?.name ?? "?"} (${erster?.topf ?? "?"} MM)`);
      }
    }
  }
  log(`Phasen gesehen: ${[...phasenGesehen].join(", ")}`);

  for (const bot of alle) probleme.push(...bot.fehler);
  for (const bot of alle) bot.close();

  if (probleme.length > 0) {
    console.error("[bots] FEHLGESCHLAGEN:");
    for (const p of probleme) console.error(`  ✗ ${p}`);
    process.exit(1);
  }
  log(
    `OK: Komplettes ${args.modus}-Match mit ${args.players} Bots durchgespielt ` +
      `(${screen.view?.frageTotal ?? "?"} Fragen, alle Phasen` +
      `${args.teams !== "aus" ? `, Team-Modus ${args.teams}` : ""}). ✓`,
  );
  process.exit(0);
}

main().catch((err) => {
  console.error("[bots] Abbruch:", err);
  process.exit(1);
});
