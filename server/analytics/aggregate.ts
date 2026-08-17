// Materialisierte Aggregate (TECH-SPEC §5.3): Event-Log-JSONL → 15 Spieler-Stats
// (GAME-DESIGN §7.2, pro PROFIL) + pro-Frage-Gesundheit (§7.6). Der Kern
// (wendeMatchAn) ist pur und aus synthetischen Logs testbar; der Job verarbeitet
// nur FERTIGE Matches (match_ended im Log) genau einmal (verarbeitet-Liste) und
// schreibt meta/stats.json atomar.
import {
  ZEIT_BUCKET_MS,
  ZEIT_BUCKETS,
  leereFrageStats,
  leereProfilStats,
  type FrageStats,
  type ProfilStats,
} from "../../shared/meta";
import { atFuerEndstand } from "../../shared/economy";
import type { Storage } from "../persistence/storage";

/** Eine Zeile des JSONL-Event-Logs (Schema TECH-SPEC §5.3). */
export interface LogZeile {
  v: number;
  ts: number;
  matchId: string;
  seq: number;
  type: string;
  actor?: string;
  questionId?: string;
  payload: Record<string, unknown>;
}

export interface FrageInfo {
  kategorie: string;
  schwierigkeit: string;
}

export interface FeedbackEintrag {
  ts: number;
  matchId: string;
  profileId: string | null;
  name: string;
  text: string;
}

export interface AggregatDaten {
  schemaVersion: 1;
  /** matchIds, deren Logs vollständig eingearbeitet sind (genau-einmal). */
  verarbeitet: string[];
  profile: Record<string, ProfilStats>;
  fragen: Record<string, FrageStats>;
  feedback: FeedbackEintrag[];
  aktualisiertTs: number;
}

export function leereAggregate(): AggregatDaten {
  return {
    schemaVersion: 1,
    verarbeitet: [],
    profile: {},
    fragen: {},
    feedback: [],
    aktualisiertTs: 0,
  };
}

export function parseZeilen(text: string): LogZeile[] {
  const zeilen: LogZeile[] = [];
  for (const roh of text.split("\n")) {
    if (roh.trim().length === 0) continue;
    try {
      const z = JSON.parse(roh) as LogZeile;
      if (typeof z.type === "string") zeilen.push(z);
    } catch {
      // Halbe Zeile (Crash mitten im append) — überspringen, Rest bleibt gültig.
    }
  }
  return zeilen;
}

/** Antwortzeit < 2,5 s zählt als Früh-Buzz (Aggressivitäts-Index, Stat 5). */
const SCHNELL_MS = 2500;

/**
 * EIN fertiges Match in die Aggregate einarbeiten (mutiert `agg`).
 * `frageInfo` liefert Kategorie/Schwierigkeit aus dem Content-Katalog —
 * unbekannte Ids (eingebaute Minigame-Pools) landen unter "unbekannt".
 */
export function wendeMatchAn(
  agg: AggregatDaten,
  zeilen: LogZeile[],
  frageInfo: (questionId: string) => FrageInfo | null,
): void {
  const matchId = zeilen[0]?.matchId ?? "?";
  if (agg.verarbeitet.includes(matchId)) return;

  const bindung = new Map<string, string>(); // playerId → profileId
  const namen = new Map<string, string>();
  const balances = new Map<string, number>();
  let modus = "?";
  let slot: string | undefined;
  let rundenMinigame = "?";
  let aktuelleFrage: string | null = null;
  let frageStartTs = 0;
  const antwortZeit = new Map<string, number>(); // playerId → ms (erste Abgabe dieser Frage)
  const jokerDieseFrage = new Set<string>();
  let finaleSnapshot: Map<string, number> | null = null;

  const ps = (profileId: string): ProfilStats => {
    agg.profile[profileId] ??= leereProfilStats();
    return agg.profile[profileId];
  };
  const fs = (questionId: string): FrageStats => {
    agg.fragen[questionId] ??= leereFrageStats();
    return agg.fragen[questionId];
  };

  for (const z of zeilen) {
    switch (z.type) {
      case "player_joined": {
        if (z.actor) namen.set(z.actor, String(z.payload.name ?? z.actor));
        break;
      }
      case "profile_bound": {
        if (z.actor && typeof z.payload.profileId === "string") {
          bindung.set(z.actor, z.payload.profileId);
        }
        break;
      }
      case "match_started": {
        modus = String(z.payload.modus ?? "?");
        break;
      }
      case "runde_gestartet": {
        slot = typeof z.payload.slot === "string" ? z.payload.slot : undefined;
        rundenMinigame = String(z.payload.minigameId ?? "?");
        break;
      }
      case "question_shown": {
        if (!z.questionId) break;
        aktuelleFrage = z.questionId;
        frageStartTs = z.ts;
        antwortZeit.clear();
        jokerDieseFrage.clear();
        const f = fs(z.questionId);
        f.ausspielungen += 1;
        f.gespieltTs = [...f.gespieltTs, z.ts].slice(-200);
        break;
      }
      case "answer_submitted": {
        if (z.actor && !antwortZeit.has(z.actor)) {
          antwortZeit.set(z.actor, Math.max(0, z.ts - frageStartTs));
        }
        break;
      }
      case "joker_used": {
        if (z.actor) jokerDieseFrage.add(z.actor);
        if (z.payload.jokerId === "schmiergeld" && aktuelleFrage) {
          fs(aktuelleFrage).tippKaeufe += 1;
        }
        break;
      }
      case "hint_given": {
        if (z.payload.art === "global" && aktuelleFrage) fs(aktuelleFrage).tippKaeufe += 1;
        break;
      }
      case "answer_judged": {
        const correct = z.payload.correct === true;
        const zeit = z.actor !== undefined ? antwortZeit.get(z.actor) : undefined;
        if (z.questionId) {
          const f = fs(z.questionId);
          f.antworten += 1;
          if (correct) f.richtig += 1;
          if (zeit !== undefined) {
            f.zeitSummeMs += zeit;
            f.zeitN += 1;
          }
          f.proModus[modus] ??= { n: 0, richtig: 0 };
          f.proModus[modus].n += 1;
          if (correct) f.proModus[modus].richtig += 1;
        }
        const profileId = z.actor !== undefined ? bindung.get(z.actor) : undefined;
        if (profileId !== undefined) {
          const p = ps(profileId);
          p.beantwortet += 1;
          if (correct) p.richtig += 1;
          const info = z.questionId ? frageInfo(z.questionId) : null;
          const key = `${info?.kategorie ?? "unbekannt"}|${info?.schwierigkeit ?? "unbekannt"}`;
          p.matrix[key] ??= { n: 0, richtig: 0 };
          p.matrix[key].n += 1;
          if (correct) p.matrix[key].richtig += 1;
          if (zeit !== undefined) {
            const bucket = Math.min(ZEIT_BUCKETS - 1, Math.floor(zeit / ZEIT_BUCKET_MS));
            p.zeitBuckets[bucket] += 1;
            if (zeit < SCHNELL_MS) {
              p.schnelleAntworten += 1;
              if (!correct) p.schnelleFalsch += 1;
            }
            if (correct && (p.schnellsteAntwortMs === null || zeit < p.schnellsteAntwortMs)) {
              p.schnellsteAntwortMs = zeit;
            }
          }
          // Serien (Stat 9, matchübergreifend — Zähler lebt im Aggregat).
          p.aktuelleSerie = correct ? p.aktuelleSerie + 1 : 0;
          p.laengsteSerie = Math.max(p.laengsteSerie, p.aktuelleSerie);
          // Joker-Effizienz (Stat 11).
          const zelle =
            z.actor !== undefined && jokerDieseFrage.has(z.actor) ? p.mitJoker : p.ohneJoker;
          zelle.n += 1;
          if (correct) zelle.richtig += 1;
          // Wett-Bilanz (Stat 12): RISIKO-Slot = Einsatz-Runden (Alles oder Banane).
          if (slot === "risiko") {
            if (correct) p.wettenGewonnen += 1;
            else p.wettenVerloren += 1;
            const delta = typeof z.payload.delta === "number" ? z.payload.delta : 0;
            if (delta > 0) p.groessterWettgewinn = Math.max(p.groessterWettgewinn, delta);
          }
        }
        break;
      }
      case "money_changed": {
        const delta = typeof z.payload.delta === "number" ? z.payload.delta : 0;
        const balance = typeof z.payload.balance === "number" ? z.payload.balance : 0;
        if (z.actor) balances.set(z.actor, balance);
        // Finale-Marker: Mitleids-Banane wird EXAKT beim Finale-Start gebucht.
        if (z.payload.grund === "mitleids-banane") finaleSnapshot = new Map(balances);
        // Klau-Bilanz (Stat 13): Geld-Deltas in Taschendieb-Runden.
        const profileId = z.actor !== undefined ? bindung.get(z.actor) : undefined;
        if (profileId !== undefined && rundenMinigame === "taschendieb") {
          if (delta > 0) ps(profileId).gestohlen += delta;
          if (delta < 0) ps(profileId).bestohlen += -delta;
        }
        break;
      }
      case "question_flagged": {
        if (z.questionId) {
          fs(z.questionId).flags = [
            ...fs(z.questionId).flags,
            { grund: String(z.payload.grund ?? "?"), ts: z.ts, matchId },
          ].slice(-20);
        }
        break;
      }
      case "feedback_given": {
        if (typeof z.payload.text === "string" && z.payload.text.length > 0) {
          agg.feedback = [
            ...agg.feedback,
            {
              ts: z.ts,
              matchId,
              profileId: z.actor !== undefined ? (bindung.get(z.actor) ?? null) : null,
              name: z.actor !== undefined ? (namen.get(z.actor) ?? z.actor) : "?",
              text: z.payload.text,
            },
          ].slice(-200);
        }
        break;
      }
      case "match_ended": {
        const standings = Array.isArray(z.payload.standings)
          ? (z.payload.standings as { playerId: string; balance: number }[])
          : [];
        const siegerId = standings[0]?.playerId;
        let finaleLeader: string | null = null;
        if (finaleSnapshot !== null && finaleSnapshot.size > 0) {
          finaleLeader = [...finaleSnapshot.entries()].sort((a, b) => b[1] - a[1])[0][0];
        }
        for (const s of standings) {
          const profileId = bindung.get(s.playerId);
          if (profileId === undefined) continue;
          const p = ps(profileId);
          p.matches += 1;
          const sieg = s.playerId === siegerId;
          if (sieg) p.siege += 1;
          p.atLifetime += atFuerEndstand(s.balance, sieg);
          p.besterEndstand = Math.max(p.besterEndstand, s.balance);
          p.aktuelleSiegesserie = sieg ? p.aktuelleSiegesserie + 1 : 0;
          p.laengsteSiegesserie = Math.max(p.laengsteSiegesserie, p.aktuelleSiegesserie);
          // Comeback (Stat 14): vor dem Finale NICHT Platz 1 — trotzdem gewonnen?
          if (finaleLeader !== null && s.playerId !== finaleLeader) {
            p.comebackMatches += 1;
            if (sieg) p.comebackSiege += 1;
          }
        }
        break;
      }
      default:
        break;
    }
  }

  agg.verarbeitet = [...agg.verarbeitet, matchId].slice(-500);
}

const STATS_DATEI = "meta/stats.json";

export interface Aggregator {
  /** Neue fertige Match-Logs einarbeiten; liefert die frischen Aggregate. */
  aktualisiere(): Promise<AggregatDaten>;
  /** Letzter bekannter Stand ohne Neuberechnung (Boards/Karten-Reads). */
  lese(): Promise<AggregatDaten>;
}

export function createAggregator(
  storage: Storage,
  frageInfo: (questionId: string) => FrageInfo | null,
  now: () => number,
  ruheMs = 0,
): Aggregator {
  let laufend: Promise<AggregatDaten> | null = null;

  async function lauf(): Promise<AggregatDaten> {
    const agg = (await storage.readJson<AggregatDaten>(STATS_DATEI)) ?? leereAggregate();
    const dateien = await storage.listeDateien("events");
    let geaendert = false;
    for (const datei of dateien) {
      if (!datei.endsWith(".jsonl")) continue;
      const matchId = datei.slice(0, -".jsonl".length);
      if (agg.verarbeitet.includes(matchId)) continue;
      const text = await storage.readText(`events/${datei}`);
      if (text === null) continue;
      const zeilen = parseZeilen(text);
      // Nur FERTIGE Matches einarbeiten (genau-einmal-Garantie ohne Zeilen-Cursor).
      const ende = zeilen.find((z) => z.type === "match_ended");
      if (ende === undefined) continue;
      // Abspann-Feedback trudelt NACH match_ended ein — erst einarbeiten, wenn
      // das Ruhefenster ab MATCH-ENDE abgelaufen ist. Anker ist bewusst der
      // match_ended-Zeitstempel, NICHT die letzte Log-Zeile: presence-Events
      // (Disconnects/Reconnects nach Match-Ende) würden das Fenster sonst
      // endlos verschieben und die Stats blieben auf 0 (Eval-4-Bug).
      if (ruheMs > 0 && now() - ende.ts < ruheMs) continue;
      wendeMatchAn(agg, zeilen, frageInfo);
      geaendert = true;
    }
    if (geaendert) {
      agg.aktualisiertTs = now();
      await storage.writeJsonAtomic(STATS_DATEI, agg);
    }
    return agg;
  }

  return {
    aktualisiere(): Promise<AggregatDaten> {
      // Nie zwei Läufe parallel (Job-Timer + Admin-Refresh können kollidieren).
      laufend ??= lauf().finally(() => {
        laufend = null;
      });
      return laufend;
    },
    async lese(): Promise<AggregatDaten> {
      return (await storage.readJson<AggregatDaten>(STATS_DATEI)) ?? leereAggregate();
    },
  };
}
