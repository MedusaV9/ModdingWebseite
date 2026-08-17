// Engine-Typen: die volle Show-Zustandsmaschine (GAME-DESIGN §1) —
// lobby → intro → [kategorie-wahl → erklaerkarte → (frage → aufloesung)×N →
// zwischenstand → rad?] → … → siegerehrung → ende.
// Der komplette State ist JSON-serialisierbar (Save/Load + Event-Log gratis).
import type { Question } from "../../shared/content";
import type { Song } from "../../shared/songs";
import type { AvatarFarbe } from "../../shared/ids";
import type { Schwierigkeit } from "../../shared/money";
import type { JokerId } from "../../shared/jokers";
import type { MatchSettings, SlotTag } from "../../shared/settings";
import type { TeamAufstellung } from "../../shared/teams";
import type { RadSegmentId } from "../../shared/wheel";
import type { EnginePhase } from "../../shared/views";
import type { ChronikEintrag, Highlight } from "./highlights";

export interface PlayerState {
  id: string;
  name: string;
  avatar: AvatarFarbe;
  connected: boolean;
  graceUntil: number | null; // gesetzt solange offline (Grace-Period 180 s)
  balance: number; // MM-Konto (Startkonto 0, Dispo-Limit −500)
  streak: number; // richtige Antworten in Folge (Multiplikator §3.1)
  maxStreak: number; // für Awards
  /** Joker-Ladungen (Consumable-Datenmodell §8.1). */
  jokers: Partial<Record<JokerId, number>>;
  /** Nach-Käufe pro Joker (max. 2 gleiche pro Spieler/Match). */
  jokerKaeufe: Partial<Record<JokerId, number>>;
  /** Bananentresor: Klau-Schutz aktiv bis inkl. Runde n (J6). */
  schildBisRunde: number | null;
  /** J6-Cooldown: nicht 2 Runden in Folge. */
  schildZuletztRunde: number | null;
  /** Clowns-Avatar bis Rundenende (Pranger). */
  clownBisRunde: number | null;
  /** Rückenwind wurde einmalig angesagt (danach dezente Windböen). */
  rueckenwindAngekuendigt: boolean;
  /** Gewonnene All-in/Sonder-Statistik: schnellste richtige Antworten (Awards). */
  richtigGesamt: number;
}

/** Ein Abschnitt des Match-Plans: normale Runde, Jackpot-Frage oder Finale. */
export interface Abschnitt {
  typ: "runde" | "jackpot" | "finale";
  nr: number; // Runden-Nr (1-basiert) bei typ=runde, sonst 0
  slot?: SlotTag;
  wunschMinigameId: string; // aus der Playlist (GAME-DESIGN §1.3)
  minigameId: string; // aufgelöst gegen die Registry (Fallback: Frage-Format)
  fragen: number;
  schwierigkeiten: Schwierigkeit[];
  kategorieWahl: "keine" | "voting" | "letzter";
  radDanach: boolean;
  kategorie: string | null; // Ergebnis der Kategorien-Wahl
}

export interface MatchPlan {
  abschnitte: Abschnitt[];
  rundenTotal: number;
  fragenTotal: number;
  ultrahardMax: number;
}

/** Laufzeit-Modifier (Glücksrad/Joker/GM) — Scope „nächste Frage" oder „Runde". */
export interface AktiverModifier {
  id: RadSegmentId | "goldene-banane" | "boost-x2";
  scope: "naechste-frage" | "runde";
  betroffen: string[]; // playerIds; leer = alle
  daten?: Record<string, unknown>; // z. B. steuerpruefung: { leaderId }
}

export interface KategorieWahlState {
  optionen: string[];
  stimmen: Record<string, string>; // playerId → Kategorie
  nurLetzter: string | null; // playerId (KONFLIKT: Letzter wählt) oder null
  endetAt: number;
}

export interface ErklaerkarteState {
  bereit: string[];
  streik: string[];
  endetAt: number;
}

export interface RadStand {
  segmente: RadSegmentId[];
  ergebnisIndex: number;
  ergebnis: RadSegmentId;
  subphase: "dreh" | "interaktion" | "ergebnis";
  subEndetAt: number;
  drehStartetAt: number;
  drehDauerMs: number;
  /** Spieler-Eingaben der Interaktion (long/short/umarmt/ja/nein). */
  wahlen: Record<string, string>;
  /** Kompliment-Konto: ausgelostes Paar. */
  paar: { von: string; zu: string } | null;
  betroffen: string[]; // für die Ergebnis-Karte
  respins: number;
  rigged: boolean;
  /** Ergebnis-Wirkung schon angewendet (Sofort-Segmente sind nicht re-spinnbar). */
  angewendet: boolean;
}

export interface VotingState {
  frage: string;
  optionen: string[];
  stimmen: Record<string, number>; // playerId → Options-Index
  endetAt: number;
}

/** Voting-Ergebnis-Einblendung: nach Voting-Schluss ~7 s auf Screen + Handys. */
export interface VotingErgebnisState {
  frage: string;
  optionen: string[];
  stimmen: number[]; // ausgezählt je Option
  gewinnerIndex: number | null; // null = keine Stimme abgegeben
  endetAt: number;
}

export interface MoodState {
  endetAt: number;
  werte: Record<string, number>; // playerId → Emoji-Index 0–4
}

/** Bildschirm-Moment (Inszenierung) — Ring der letzten Ereignisse. */
export interface Moment {
  id: string;
  ts: number;
  art: string;
  text: string;
}

/** GM-Laufzeit-Budgets + Zähler (Fairness-Grenzen sitzen im SERVER, §3.4). */
export interface GmRuntime {
  jokerChips: number; // Vergabe-Budget (6/Session)
  verlaengerungenDieseFrage: number; // max. 2
  encoresDieseRunde: number; // max. 2
  blitzStimmungen: number; // verbleibend (3/Session)
  hintStufeDieseFrage: number; // 0–3 (sichtbarer Punktabzug −25 %/Stufe)
  boostsDieseRunde: Record<string, number>; // playerId → Anzahl (max. 1)
  fluesterDieseRunde: Record<string, number>; // playerId → Anzahl (max. 2)
  letzteBestrafung: string | null; // Anti-Mobbing: nie 2× in Folge
  vorletzteBestrafung: string | null;
  autoTimerVerlaengert: boolean; // Auto-GM: max. 1×/Frage
  stimmungsHistorie: { ts: number; werte: number[] }[];
}

/** v2 Sudden-Death: Kokosnuss-Shake bei Gleichstand an der Spitze nach dem Plan. */
export interface TiebreakerZustand {
  /** Die gleichauf liegenden Spieler (Re-Shake: nur noch die Tap-Gleichen). */
  teilnehmer: string[];
  subphase: "countdown" | "shake" | "ergebnis";
  endetAt: number;
  runde: number; // 1-basiert; bei erneutem Gleichstand Re-Shake (max. 3 Runden)
  taps: Record<string, number>; // playerId → Tap-Summe dieser Shake-Runde
  sieger: string | null; // gesetzt in "ergebnis" — holt Platz 1
  betrag: number; // der umkämpfte Kontostand (Inszenierung)
}

/** v2 Replay-Highlights: Karten-Sequenz vor der Siegerehrung. */
export interface HighlightsLauf {
  karten: Highlight[];
  index: number;
  endetAt: number; // Server-Deadline der aktuellen Karte
}

export interface SiegerehrungDaten {
  platzierungen: {
    playerId: string;
    platz: number;
    balance: number;
    at: number;
  }[];
  awards: { titel: string; playerId: string; wert: string }[];
  /** Team-Modus (ADDITIV): Team-Ranking der Siegerehrung — sonst nicht gesetzt. */
  teamPlatzierungen?: { teamId: string; platz: number; topf: number }[];
}

/** Team-Modus „Affenbanden" (ADDITIV, GAME-DESIGN §1.4): Aufstellung + Laufzeit.
 * Die Aufstellung entsteht beim Match-Start aus den Lobby-Wünschen; der
 * Buzz-Vergabe-Zustand lebt PRO FRAGE (Buzzer-Regel: 1 Buzz pro Team). */
export interface TeamsState extends TeamAufstellung {
  /** Diese Frage: teamId → playerId des Team-Buzzers (weitere werden abgelehnt). */
  buzzVonTeam: Record<string, string>;
}

export interface EngineState {
  phase: EnginePhase;
  matchId: string | null;
  settings: MatchSettings;
  players: Record<string, PlayerState>;
  order: string[]; // Join-Reihenfolge (stabile Anzeige, Sitznachbarn)
  // ---------- Match-Plan + Fragen ----------
  plan: MatchPlan | null;
  abschnittIndex: number; // -1 = vor dem ersten Abschnitt
  frageInAbschnitt: number; // 0-basiert; -1 = noch keine gestartet
  fragenPool: Question[]; // beim Start geladener Vorrat (Content-Loader)
  usedQuestionIds: string[];
  // ADDITIV (Musik): Song-Vorrat für contentKind-"songs"-Formate — optional,
  // damit alte Saves gültig bleiben (fehlend ⇒ wie leer).
  songsPool?: Song[];
  usedSongIds?: string[];
  ultrahardGestellt: number;
  fragenZaehler: number; // global gestellte Fragen (Anzeige)
  naechsteFrageId: string | null; // GM-Pick (Fragen-Regal)
  zuweisungen: Record<string, string>; // Maßanzug: playerId → questionId
  regalFilter: { kategorie: string | null; schwierigkeit: Schwierigkeit | null };
  // ---------- Aktive Frage / Minigame ----------
  minigameId: string | null;
  minigameState: unknown; // Plugin-State — lebt IM Engine-State (TECH-SPEC §2.1)
  aktuelleFragen: Question[]; // Fragen des laufenden Plugin-init (1 oder Runde)
  phaseEndsAt: number | null; // Server-Deadline der Nicht-Frage-Phasen
  paused: { text: string; seit: number; bis: number | null } | null;
  // ---------- Ökonomie ----------
  jackpotGlas: number;
  pott: number; // Fragen-Pott (Steuerprüfung / Affe würfelt)
  modifiers: AktiverModifier[];
  // ---------- Joker ----------
  infoJokerFrage: string[]; // playerIds mit J1/J4 in DIESER Frage (max. 1)
  jokerFrageZaehler: Record<string, number>; // `${jokerId}:${playerId}` → Anzahl diese Frage
  // ---------- Phasen-Zustände ----------
  kategorieWahl: KategorieWahlState | null;
  erklaerkarte: ErklaerkarteState | null;
  rad: RadStand | null;
  radHistorie: { letztesSegment: RadSegmentId | null; drehsOhneGold: number };
  voting: VotingState | null;
  /** Ergebnis-Einblendung nach Voting-Schluss (Balken + Sieger-Option, ~7 s). */
  votingErgebnis: VotingErgebnisState | null;
  mood: MoodState | null;
  fluesterTipp: Record<string, string>; // playerId → aktiver Tipp (nur Ziel-Handy)
  hinweis: Record<string, string>; // playerId → Schmiergeld-Stufe-2-Text
  /** Tipp-Kanone (ADDITIV, Eval 5): die für DIESE Frage bereits enthüllten
   * Autoren-Tipps (öffentlich) — Reset in starteFrage; optional, damit alte
   * Saves gültig bleiben (fehlend ⇒ wie leer). */
  gezeigteTipps?: string[];
  momente: Moment[];
  momentZaehler: number;
  gm: GmRuntime;
  feedbackAngefragt: boolean;
  feedback: { playerId: string; text: string }[];
  finaleWert: number | null; // W_final (§3.5), vor dem Finale berechnet
  siegerehrung: SiegerehrungDaten | null;
  /** Deltas der letzten Fragen-Buchung — Grundlage für markBroken-Rückabwicklung. */
  letzteBuchung: { questionId: string; deltas: Record<string, number> } | null;
  // ---------- v2-Features (ADDITIV) ----------
  /** Match-Chronik für die Replay-Highlights (in schliesseFrageAb gesammelt). */
  chronik: ChronikEintrag[];
  /** Sudden-Death-Kokosnuss-Shake (Phase "tiebreaker") — sonst null. */
  tiebreaker: TiebreakerZustand | null;
  /** Replay-Highlights-Sequenz (Phase "highlights") — sonst null. */
  highlights: HighlightsLauf | null;
  // ---------- Team-Modus „Affenbanden" (ADDITIV) ----------
  /** Lobby: Team-Wünsche (Spieler-Wahl/GM-Zuweisung) — playerId → TeamId. */
  teamWuensche: Record<string, string>;
  /** Aktive Team-Aufstellung des Matches — null bei teams=aus/zu wenigen Spielern. */
  teams: TeamsState | null;
  // ---------- Musik-Rotation (ADDITIV, Musik-Welle 3) ----------
  /** GM-„Nächster Track"-Zähler: der Screen skippt die Bett-Rotation bei jeder
   * Erhöhung (optional — alte Saves ohne Feld zählen als 0). */
  musikSkips?: number;
}

/** Domänen-Events: gehen ins JSONL-Event-Log UND steuern Broadcast-Entscheidungen. */
export type EngineEvent =
  | { type: "player_joined"; playerId: string; name: string }
  | { type: "presence"; playerId: string; connected: boolean; graceUntil?: number }
  | { type: "match_started"; matchId: string; playerIds: string[]; modus: string }
  | { type: "phase_changed"; phase: EnginePhase }
  | { type: "runde_gestartet"; nr: number; minigameId: string; slot?: string; kategorie?: string }
  | { type: "runde_beendet"; nr: number }
  | { type: "kategorie_gewaehlt"; kategorie: string; art: "voting" | "letzter" | "gm" | "auto" }
  | { type: "question_shown"; questionId: string; index: number }
  | { type: "answer_submitted"; playerId: string; questionId: string }
  | { type: "answer_judged"; playerId: string; questionId: string; correct: boolean; delta: number }
  | { type: "money_changed"; playerId: string; delta: number; balance: number; grund: string }
  | { type: "timer_extended"; ms: number }
  | { type: "joker_used"; playerId: string; jokerId: string; preis: number }
  | { type: "joker_granted"; playerId: string; jokerId: string; quelle: string }
  | { type: "rad_gestartet"; segmente: string[]; ergebnis: string; rigged: boolean }
  | { type: "rad_ergebnis"; segment: string; betroffen: string[] }
  | { type: "hint_given"; art: "global" | "whisper"; playerId?: string; stufe?: number }
  | { type: "boost"; playerId: string; art: string; grund: string }
  | { type: "punished"; playerId: string; strafe: string }
  | { type: "question_flagged"; questionId: string; grund: string; refund: string }
  | { type: "game_flagged"; minigameId: string; grund: string }
  | { type: "vote_result"; frage: string; stimmen: number[] }
  | { type: "vote_ergebnis_ende" } // Ergebnis-Einblendung vorbei → Snapshot-Trigger
  | { type: "mood_result"; werte: number[] }
  | { type: "feedback_given"; playerId: string; text?: string }
  | { type: "sound_play"; sfxId: string }
  | { type: "moment"; art: string; text: string }
  | { type: "gm_command"; cmd: string; args: Record<string, unknown> }
  // Leichte Interaktions-Events: Log-Zeile + Snapshot-Trigger (Stimmen-Zähler live).
  | { type: "kategorie_vote"; playerId: string; kategorie: string }
  | { type: "phase_ready"; playerId: string; was: "bereit" | "streik" }
  | { type: "rad_wahl"; playerId: string; wahl: string }
  | { type: "vote_cast"; playerId: string }
  | { type: "mood_vote"; playerId: string }
  | { type: "settings_changed"; patch: Record<string, unknown> }
  | { type: "frage_annulliert"; questionId: string }
  | { type: "match_ended"; standings: { playerId: string; balance: number }[] }
  // ---------- v2: Sudden-Death + Replay-Highlights ----------
  | { type: "tiebreaker_gestartet"; teilnehmer: string[]; betrag: number }
  // Leichtes Live-Event: neuer Tap-Gesamtstand EINES Shakers (Wire-Delta).
  | { type: "shake_tap"; playerId: string; taps: number }
  | { type: "tiebreaker_ergebnis"; sieger: string; taps: Record<string, number>; runde: number }
  | { type: "highlights_gestartet"; anzahl: number }
  | { type: "highlight_gezeigt"; highlightId: string; art: string }
  // ---------- Team-Modus „Affenbanden" (ADDITIV) ----------
  | { type: "team_wahl"; playerId: string; team: string }
  | {
      type: "teams_gebildet";
      modus: string;
      teams: { id: string; name: string }[];
      zuordnung: Record<string, string>;
      doppelAffe: string | null;
    }
  | { type: "team_ergebnis"; platzierungen: { teamId: string; platz: number; topf: number }[] };

/** Eingaben in den Reducer — alles läuft durch reduce/tick (Server = einzige Wahrheit). */
export type EngineAction =
  | { type: "join"; playerId: string; name: string; avatar: AvatarFarbe }
  | { type: "presence"; playerId: string; connected: boolean; graceUntil: number | null }
  | {
      type: "start";
      matchId: string;
      fragenPool: Question[];
      verfuegbareMinigames: string[];
      /** Team-Auto-Balance (ADDITIV): Stärke pro Spieler (AT-Stats bei Profilen). */
      staerke?: Record<string, number>;
      /** ADDITIV (Musik): Song-Vorrat (Content-Loader pickSongs) — fehlt/leer
       * ⇒ die Song-Formate sind schon aus verfuegbareMinigames gefiltert. */
      songsPool?: Song[];
    }
  | {
      type: "playerAction";
      playerId: string;
      minigameId: string;
      action: { type: string; [k: string]: unknown };
      atServerTime: number;
    }
  | { type: "playerReady"; playerId: string }
  | { type: "playerStreik"; playerId: string }
  | { type: "kategorieVote"; playerId: string; kategorie: string }
  | { type: "voteCast"; playerId: string; option: number }
  | { type: "radAktion"; playerId: string; wahl: string }
  | { type: "jokerUse"; playerId: string; jokerId: string; stufe?: number }
  | { type: "jokerBuy"; playerId: string; jokerId: string }
  | { type: "feedbackText"; playerId: string; text: string }
  // v2 Sudden-Death: Tap-Batch eines Kokosnuss-Shakers (Server kappt pro Batch).
  | { type: "shakeTap"; playerId: string; taps: number }
  // Team-Modus: Team-Wunsch in der Lobby (Spieler-Wahl, GAME-DESIGN §1.4).
  | { type: "teamWahl"; playerId: string; team: string }
  // ---------- GM-Kommandos (EIN Kanal, §4.1) ----------
  | { type: "gm.scoreAdjust"; playerId: string; delta: number; grund: string; override?: boolean }
  | { type: "gm.timerExtend"; ms: number }
  | { type: "gm.pause"; text: string; dauerMs?: number }
  | { type: "gm.resume" }
  | { type: "gm.next" }
  | { type: "gm.settings"; patch: Record<string, unknown> }
  | { type: "gm.kategoriePick"; kategorie: string }
  | { type: "gm.questionPick"; questionId: string }
  | { type: "gm.questionAssign"; playerId: string; questionId: string | null }
  | { type: "gm.regalFilter"; kategorie?: string | null; schwierigkeit?: string | null }
  | { type: "gm.hintGlobal" }
  | { type: "gm.hintWhisper"; playerId: string; text: string }
  | { type: "gm.voteStart"; frage: string; optionen: string[]; dauerMs?: number }
  | { type: "gm.markBroken"; grund: string; refund: "annul" | "grantAll" }
  | { type: "gm.gameSkip"; keepPoints: boolean }
  | { type: "gm.flagBuggy"; grund: string }
  | { type: "gm.punish"; playerId: string; strafe: string }
  | { type: "gm.boost"; playerId: string; art: "x2" | "plus300" | "joker"; grund: string }
  | { type: "gm.jokerGrant"; ziel: string; jokerId: string }
  | { type: "gm.wheelSpin"; rigTarget?: string }
  | { type: "gm.moodPoll" }
  | { type: "gm.feedbackCollect" }
  | { type: "gm.encore" }
  | { type: "gm.sound"; sfxId: string }
  // Musik-Rotation (ADDITIV): „Nächster Track" fürs Show-Bett (Screen skippt).
  | { type: "gm.musikSkip" }
  | { type: "gm.autoGm"; enabled: boolean }
  // Team-Modus: GM-Zuweisung in der Lobby (team=null löscht den Wunsch).
  | { type: "gm.teamAssign"; playerId: string; team: string | null }
  | { type: "gm.ende" }
  // GM-Wechsel (Raum-Ebene: EIN aktives Cockpit) — Moment fürs Screen-Toast + Log.
  | { type: "gm.wechsel"; grund: "takeover" | "nachrueckt" };

export interface EngineResult {
  state: EngineState;
  events: EngineEvent[];
  /** Gesetzt, wenn die Aktion abgelehnt wurde (für ACKs) — State bleibt unverändert. */
  error?: string;
}

// Anzeige-Dauern der Server-getakteten Phasen (Timer laufen NUR auf dem Server).
export const INTRO_MS = 6_000;
export const KATEGORIE_WAHL_MS = 12_000;
export const ERKLAERKARTE_MS = 12_000;
export const ERKLAERKARTE_KURZ_MS = 7_000;
export const AUFLOESUNG_MS = 6_000;
// Playtest 3: 7 s statischer Zwischenstand fühlte sich nach Wartezimmer an —
// 5 s + EINE animierte Stand-Story (Screen) halten den News-Beat knackig.
export const ZWISCHENSTAND_MS = 5_000;
// Playtest 3: nach Fanfare + Podest + Awards standen 20 s Nachlauf — 12 s
// halten den Peak (Awards laufen jetzt als Beats nacheinander, siehe Screen).
export const SIEGEREHRUNG_MS = 12_000;
export const MOOD_POLL_MS = 4_000;
export const VOTING_MS = 15_000;
export const VOTING_ERGEBNIS_MS = 7_000;
// ---------- v2: Sudden-Death (Kokosnuss-Shake) + Replay-Highlights ----------
export const TIEBREAKER_COUNTDOWN_MS = 3_000;
export const TIEBREAKER_SHAKE_MS = 10_000;
export const TIEBREAKER_ERGEBNIS_MS = 5_000;
/** Nach 3 Shake-Runden mit Tap-Gleichstand entscheidet das Los (Rng). */
export const TIEBREAKER_MAX_RUNDEN = 3;
/** Anzeigedauer einer Highlight-Karte (4–5 s, skippable via gm.next). */
export const HIGHLIGHT_KARTE_MS = 4_500;
