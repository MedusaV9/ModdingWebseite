// Team-Modus v1 „Affenbanden" (GAME-DESIGN §1.4 + docs/ideen/06 Idee 1/7):
// feste Zweierteams mit Auto-Namen aus dem Money-Affen-Wortschatz, Team-Farbe,
// ausbalancierter Auto-Verteilung (Stärke-Snake) und der Doppel-Affe-Regel bei
// ungeraden Spielerzahlen (ein Spieler zählt im Team-Topf doppelt, erhält aber
// nur den Einzelanteil). Individuelles Money BLEIBT — der TEAM-TOPF ist die
// Summe der Mitglieds-Konten (Doppel-Affe ×2), Sieger = Team mit höchstem Topf.
// Pure Daten + pure Helfer, beidseitig importierbar; Zufall IMMER injiziert.
import type { Rng } from "./rng";

/** Match-Setting `teams` (additiv in MatchSettings, Default "aus"). */
export type TeamModusSetting = "aus" | "2er" | "2v2v2v2" | "frei";
/** Aktiver Team-Modus (ohne "aus"). */
export type TeamModus = Exclude<TeamModusSetting, "aus">;

export type TeamId = "banane" | "kokos" | "liane" | "orchidee";

/** Team-Modus verfügbar ab 4 Spielern (GAME-DESIGN §1.4: bei 2–3 ausgeblendet). */
export const TEAM_MIN_SPIELER = 4;
export const MAX_TEAMS = 4;

export interface TeamDef {
  id: TeamId;
  /** Team-Farbe (CSS) — Rahmen/Banner auf Screen + Handy-Header. */
  farbe: string;
  emoji: string;
}

export const TEAM_REIHENFOLGE: readonly TeamId[] = ["banane", "kokos", "liane", "orchidee"];

export const TEAM_DEFS: Record<TeamId, TeamDef> = {
  banane: { id: "banane", farbe: "#FFC93C", emoji: "🍌" },
  kokos: { id: "kokos", farbe: "#B4693C", emoji: "🥥" },
  liane: { id: "liane", farbe: "#2FBF71", emoji: "🌿" },
  orchidee: { id: "orchidee", farbe: "#B278E8", emoji: "🌺" },
};

/** Auto-Team-Namen aus dem Money-Affen-Wortschatz (Design: „Die Bananen-Barone"). */
export const TEAM_NAMEN_POOL: Record<TeamId, readonly string[]> = {
  banane: ["Die Bananen-Barone", "Team Banane", "Die Gold-Gibbons", "Bananen-Bande AG"],
  kokos: ["Die Krypto-Kapuziner", "Team Kokos", "Der Kokos-Konzern", "Kokosnuss-Kartell"],
  liane: ["Die Lianen-Liga", "Team Liane", "Die Dschungel-Dukaten", "Lianen-Lobby GmbH"],
  orchidee: ["Die Orchideen-Oligarchen", "Team Orchidee", "Die Prima-Primaten", "Orchideen-Orden"],
};

/** Deterministischer Team-Name aus dem Pool (Rng injiziert — Save/Replay-fest). */
export function teamName(id: TeamId, rng: Rng): string {
  const pool = TEAM_NAMEN_POOL[id];
  return pool[rng.int(pool.length)];
}

/** Neutraler Anzeige-Name VOR der Team-Bildung (Lobby-Wahl-Buttons/Spalten). */
export function teamAnzeigeName(id: TeamId): string {
  return `Team ${id.charAt(0).toUpperCase()}${id.slice(1)}`;
}

export interface TeamInfo {
  id: TeamId;
  name: string;
  farbe: string;
  emoji: string;
}

/** Team-Aufstellung eines Matches — lebt (JSON-serialisierbar) im Engine-State. */
export interface TeamAufstellung {
  modus: TeamModus;
  teams: TeamInfo[];
  /** playerId → TeamId. */
  zuordnung: Record<string, TeamId>;
  /** Doppel-Affe-Regel (ungerade Zahl im 2er-Modus): zählt im Topf doppelt. */
  doppelAffe: string | null;
}

/**
 * Wie viele Teams bietet der Modus bei n Spielern an?
 * · 2er: Zweierteams — ceil(n/2), gekappt auf 4 (Design: 2v2, 2v2v2, 2v2v2v2;
 *   bei 5/7 bekommt das letzte Team den Doppel-Affen statt eines 2. Spielers).
 * · 2v2v2v2: fest 4 Lager (Spieler gleichmäßig verteilt).
 * · frei: 4 Farben angeboten, Spieler wählen — leere Teams fallen beim Start weg.
 */
export function teamAnzahl(modus: TeamModus, spielerzahl: number): number {
  if (modus === "2er") return Math.min(MAX_TEAMS, Math.max(2, Math.ceil(spielerzahl / 2)));
  return MAX_TEAMS;
}

/** Die im Lobby-Wahl-Screen angebotenen Teams (Reihenfolge = Farb-Ring). */
export function angeboteneTeams(modus: TeamModus, spielerzahl: number): TeamId[] {
  return TEAM_REIHENFOLGE.slice(0, teamAnzahl(modus, spielerzahl)) as TeamId[];
}

/** Kapazität eines Team-Slots (Index) — Infinity im frei-Modus. */
function kapazitaeten(modus: TeamModus, spielerzahl: number, anzahl: number): number[] {
  if (modus === "frei") return Array.from({ length: anzahl }, () => spielerzahl);
  if (modus === "2er") {
    // Zweierteams; bei ungerader Zahl hat das LETZTE Team nur 1 Platz (Doppel-Affe).
    const caps = Array.from({ length: anzahl }, () => 2);
    if (spielerzahl % 2 === 1 && spielerzahl < anzahl * 2) caps[anzahl - 1] = 1;
    return caps;
  }
  // 2v2v2v2: gleichmäßig — die ersten (n mod 4) Teams bekommen einen Platz mehr.
  const basis = Math.floor(spielerzahl / anzahl);
  const rest = spielerzahl % anzahl;
  return Array.from({ length: anzahl }, (_, i) => basis + (i < rest ? 1 : 0));
}

export interface BildeTeamsOptionen {
  modus: TeamModus;
  /** Spieler in Join-Reihenfolge. */
  spieler: string[];
  /** Lobby-Wünsche (Spieler-Wahl ODER GM-Zuweisung) — playerId → TeamId. */
  wuensche?: Record<string, string>;
  /** Stärke-Wert pro Spieler (AT-Stats bei Profilen; fehlend = 0) für die Balance. */
  staerke?: Record<string, number>;
  rng: Rng;
}

/**
 * Team-Bildung beim Match-Start: Wünsche werden in Join-Reihenfolge erfüllt,
 * solange Kapazität da ist; der Rest wird ausbalanciert verteilt (stärkste
 * zuerst, immer ins Team mit der niedrigsten Stärke-Summe — Idee 7 „Fairer
 * Draft"). Ungerade Zahl im 2er-Modus ⇒ der Solo-Spieler wird Doppel-Affe.
 * Der Greedy-Draft setzt dabei einen Spieler aus der STÄRKE-MITTE solo —
 * mit der ×2-Topf-Regel ist genau das die fairste Aufstellung (der mittlere
 * Wert ×2 ≈ Summe eines Zweier-Teams; der Schwächste solo wäre chancenlos).
 */
export function bildeTeams(opts: BildeTeamsOptionen): TeamAufstellung {
  const { modus, spieler, rng } = opts;
  const wuensche = opts.wuensche ?? {};
  const staerke = opts.staerke ?? {};
  const anzahl = teamAnzahl(modus, spieler.length);
  const ids = angeboteneTeams(modus, spieler.length);
  const caps = kapazitaeten(modus, spieler.length, anzahl);

  const mitglieder: Record<TeamId, string[]> = {
    banane: [],
    kokos: [],
    liane: [],
    orchidee: [],
  };
  const zuordnung: Record<string, TeamId> = {};
  const frei = (teamIdx: number): number => caps[teamIdx] - mitglieder[ids[teamIdx]].length;

  // 1) Wünsche in Join-Reihenfolge erfüllen (Kapazitäts-Grenze respektieren).
  const offen: string[] = [];
  for (const pid of spieler) {
    const wunsch = wuensche[pid];
    const idx = ids.indexOf(wunsch as TeamId);
    if (idx >= 0 && frei(idx) > 0) {
      mitglieder[ids[idx]].push(pid);
      zuordnung[pid] = ids[idx];
    } else {
      offen.push(pid);
    }
  }

  // 2) Rest ausbalanciert: stärkste zuerst, ins Team mit der kleinsten
  //    Stärke-Summe (Gleichstand: weniger Mitglieder, dann Farb-Reihenfolge).
  const sortiert = [...offen].sort((a, b) => (staerke[b] ?? 0) - (staerke[a] ?? 0));
  const teamStaerke = (teamId: TeamId): number =>
    mitglieder[teamId].reduce((sum, p) => sum + (staerke[p] ?? 0), 0);
  for (const pid of sortiert) {
    let ziel = -1;
    for (let i = 0; i < ids.length; i++) {
      if (frei(i) <= 0) continue;
      if (
        ziel === -1 ||
        teamStaerke(ids[i]) < teamStaerke(ids[ziel]) ||
        (teamStaerke(ids[i]) === teamStaerke(ids[ziel]) &&
          mitglieder[ids[i]].length < mitglieder[ids[ziel]].length)
      ) {
        ziel = i;
      }
    }
    if (ziel === -1) ziel = 0; // frei-Modus ohne Kappe erreicht das nie
    mitglieder[ids[ziel]].push(pid);
    zuordnung[pid] = ids[ziel];
  }

  // 3) frei-Modus: leere Teams fallen weg; landet ALLES in einem Team,
  //    wird zwangs-halbiert (ein Team wäre kein Wettkampf).
  let aktive = ids.filter((id) => mitglieder[id].length > 0);
  if (modus === "frei" && aktive.length < 2) {
    const alle = aktive.length === 1 ? [...mitglieder[aktive[0]]] : [...spieler];
    const zweitesTeam = ids.find((id) => id !== aktive[0]) ?? ids[1];
    const haelfte = Math.ceil(alle.length / 2);
    mitglieder[aktive[0] ?? ids[0]] = alle.slice(0, haelfte);
    mitglieder[zweitesTeam] = alle.slice(haelfte);
    for (const pid of alle.slice(0, haelfte)) zuordnung[pid] = aktive[0] ?? ids[0];
    for (const pid of alle.slice(haelfte)) zuordnung[pid] = zweitesTeam;
    aktive = [aktive[0] ?? ids[0], zweitesTeam];
  }

  // 4) Doppel-Affe (nur 2er-Modus, ungerade Zahl): der Spieler im Solo-Team.
  let doppelAffe: string | null = null;
  if (modus === "2er" && spieler.length % 2 === 1) {
    const solo = aktive.find((id) => mitglieder[id].length === 1);
    if (solo !== undefined) doppelAffe = mitglieder[solo][0];
  }

  const teams: TeamInfo[] = aktive.map((id) => ({
    id,
    name: teamName(id, rng),
    farbe: TEAM_DEFS[id].farbe,
    emoji: TEAM_DEFS[id].emoji,
  }));
  return { modus, teams, zuordnung, doppelAffe };
}

// ---------- Team-Ökonomie: Topf = Summe (Doppel-Affe ×2) ----------

/** Mitglieder eines Teams in Spieler-Reihenfolge. */
export function teamMitglieder(
  aufstellung: Pick<TeamAufstellung, "zuordnung">,
  teamId: TeamId,
  spieler: string[],
): string[] {
  return spieler.filter((pid) => aufstellung.zuordnung[pid] === teamId);
}

/** TEAM-TOPF: Summe der Mitglieds-Konten; der Doppel-Affe zählt doppelt. */
export function teamTopf(
  aufstellung: Pick<TeamAufstellung, "zuordnung" | "doppelAffe">,
  teamId: TeamId,
  balances: Record<string, number>,
): number {
  let summe = 0;
  for (const [pid, tid] of Object.entries(aufstellung.zuordnung)) {
    if (tid !== teamId) continue;
    const faktor = aufstellung.doppelAffe === pid ? 2 : 1;
    summe += (balances[pid] ?? 0) * faktor;
  }
  return summe;
}

export interface TeamStand {
  teamId: TeamId;
  topf: number;
  platz: number; // 1-basiert
}

/**
 * Team-Ranking nach Topf (absteigend). Gleichstand: das Sudden-Death-Sieger-
 * Team gewinnt (falls übergeben), sonst stabile Farb-Reihenfolge.
 */
export function teamStaende(
  aufstellung: TeamAufstellung,
  balances: Record<string, number>,
  siegerTeamId?: TeamId | null,
): TeamStand[] {
  const sortiert = [...aufstellung.teams].sort((a, b) => {
    const diff = teamTopf(aufstellung, b.id, balances) - teamTopf(aufstellung, a.id, balances);
    if (diff !== 0) return diff;
    if (siegerTeamId === a.id) return -1;
    if (siegerTeamId === b.id) return 1;
    return TEAM_REIHENFOLGE.indexOf(a.id) - TEAM_REIHENFOLGE.indexOf(b.id);
  });
  return sortiert.map((t, i) => ({
    teamId: t.id,
    topf: teamTopf(aufstellung, t.id, balances),
    platz: i + 1,
  }));
}

/** Basis-Werte für den TEAM-bezogenen Rückenwind (§3.4 wirkt auf Team-Töpfe). */
export interface RueckenwindBasis {
  eigenerStand: number;
  fuehrenderStand: number;
  vordermannStand: number;
}

/**
 * Underdog-Mechanik team-bezogen: Rückenwind + Überhol-Kappe rechnen mit dem
 * EIGENEN Team-Topf gegen den führenden bzw. den Vordermann-Team-Topf —
 * pro Spieler aufgelöst (die Buchungs-Pipeline bleibt spieler-basiert).
 */
export function teamRueckenwindBasis(
  aufstellung: TeamAufstellung,
  balances: Record<string, number>,
): Record<string, RueckenwindBasis> {
  const staende = teamStaende(aufstellung, balances);
  const topfVon = new Map(staende.map((s) => [s.teamId, s.topf]));
  const fuehrender = staende[0]?.topf ?? 0;
  const vordermann = new Map<TeamId, number>();
  for (let i = 0; i < staende.length; i++) {
    vordermann.set(staende[i].teamId, i === 0 ? staende[0].topf : staende[i - 1].topf);
  }
  const basis: Record<string, RueckenwindBasis> = {};
  for (const [pid, teamId] of Object.entries(aufstellung.zuordnung)) {
    basis[pid] = {
      eigenerStand: topfVon.get(teamId) ?? 0,
      fuehrenderStand: fuehrender,
      vordermannStand: vordermann.get(teamId) ?? fuehrender,
    };
  }
  return basis;
}

/** Das LETZTE Team (kleinster Topf) — Basis der team-bezogenen Underdog-Regeln. */
export function letztesTeam(
  aufstellung: TeamAufstellung,
  balances: Record<string, number>,
): TeamId | null {
  const staende = teamStaende(aufstellung, balances);
  return staende[staende.length - 1]?.teamId ?? null;
}
