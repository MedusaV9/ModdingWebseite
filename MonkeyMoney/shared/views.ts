// Rollen-gefilterte View-Typen — der Server rendert diese, Clients zeigen sie nur an.
// Geheimnis-Filterung (z. B. correctIndex) passiert SERVERSEITIG in viewFor.
import type { AvatarFarbe } from "./ids";
import type { MatchSettings } from "./settings";

/**
 * Engine-Phasen (GAME-DESIGN §1.1):
 * lobby → intro (Opening) → [pro Abschnitt: kategorie-wahl? → erklaerkarte →
 * (frage → aufloesung)×N → zwischenstand → rad?] → … → siegerehrung → ende (Abspann).
 * Jackpot-Frage und Finale laufen als eigene Abschnitte durch dieselben
 * frage/aufloesung-Phasen (siehe ViewBase.abschnitt.typ).
 */
export type EnginePhase =
  | "lobby"
  | "intro"
  | "kategorie-wahl"
  | "erklaerkarte"
  | "frage"
  | "aufloesung"
  | "zwischenstand"
  | "rad"
  // v2: Sudden-Death-Tiebreaker (Kokosnuss-Shake) bei Gleichstand nach dem Plan
  | "tiebreaker"
  // v2: „Die Highlights des Abends" — Replay-Sequenz VOR der Siegerehrung
  | "highlights"
  | "siegerehrung"
  | "ende";

export interface SpielerPublic {
  id: string;
  name: string;
  avatar: AvatarFarbe;
  connected: boolean;
  graceUntil?: number; // gesetzt solange offline (→ „offline"-Badge)
  balance: number;
  streak: number;
  /** Rückenwind aktiv (×1,25 / ×1,5) — transparent, nie heimlich (§3.4). */
  rueckenwind?: number;
  /** Bananentresor-Schild aktiv (Klau-Schutz, J6). */
  schild?: boolean;
  /** Clowns-Avatar bis Rundenende (Pranger-Strafe). */
  clown?: boolean;
}

export interface PauseInfo {
  text: string;
  seit: number;
  /** Timeout-Screen: Countdown-Ende auf allen Geräten (Bananen-Pause §4.2/11). */
  bis?: number;
}

/** Wo im Match-Plan stehen wir? (Runde/Jackpot/Finale + Frage-Zähler) */
export interface AbschnittInfo {
  typ: "runde" | "jackpot" | "finale";
  rundeNr: number; // 1-basiert (jackpot/finale: 0)
  rundenTotal: number;
  slot?: string; // opener/aufbau/geld/konflikt/risiko
  minigameId: string;
  minigameName: string;
  kategorie: string | null;
  frageInRunde: number; // 1-basiert
  fragenInRunde: number;
  /** Nur Finale: der angesagte W_final-Wert („Jede Frage ist heute X wert!"). */
  wFinal?: number;
}

export interface KategorieWahlView {
  optionen: string[];
  stimmen: number[]; // Stimmen-Zähler je Option (live)
  /** Comeback-Regel: nur die Stimme des Letzten zählt (KONFLIKT-Runde). */
  nurLetzterWaehlt: boolean;
  waehlerName?: string; // wer wählt (bei nurLetzterWaehlt)
  endetAt: number;
  /** Nur PlayerView: eigene abgegebene Stimme. */
  deineStimme?: number | null;
}

export interface ErklaerkarteView {
  minigameId: string;
  minigameName: string;
  slot?: string;
  text: string; // 1 Satz Regel-Erklärung
  kategorie: string | null;
  schwierigkeiten: string[];
  bereit: string[]; // playerIds, die „Bereit" gedrückt haben
  streik: string[]; // playerIds mit Streik-Stimme (Mehrheit = Minispiel-Skip)
  endetAt: number;
  wFinal?: number; // Finale-Ansage
  /** Tutorial-Video (nur wenn Setting tutorialVideos AN + Format hat eins) —
   * der Screen zeigt dann einen „Video ansehen"-Knopf; Skip bleibt wie gehabt. */
  videoUrl?: string;
}

export interface RadSegmentView {
  id: string;
  name: string;
  klasse: string; // gruen/blau/gold
}

export interface RadView {
  segmente: RadSegmentView[];
  /** Index des Ergebnisses im Ring — Client animiert deterministisch dorthin. */
  ergebnisIndex: number;
  dreh: { startetAt: number; dauerMs: number };
  /** Gesetzt sobald der Dreh vorbei ist (Einschlag + Erklärkarte). */
  ergebnis: {
    id: string;
    name: string;
    klasse: string;
    wirkung: string;
    betroffen: string[];
  } | null;
  /** Aktive Spieler-Interaktion (Börsen-Roulette/Umarmung/Kompliment). */
  interaktion: {
    typ: "long-short" | "umarmt" | "kompliment";
    endetAt: number;
    /** Kompliment: wer macht wem ein Kompliment. */
    paar?: { von: string; zu: string };
    /** Nur PlayerView: eigene Wahl (long/short/umarmt/ja/nein). */
    deineWahl?: string | null;
  } | null;
}

/** Aktiver Modifier (Rad/Joker) für die Icon-Leiste am Bildschirmrand. */
export interface ModifierView {
  id: string;
  name: string;
  scope: string; // naechste-frage | runde
  betroffen?: string[]; // playerIds (leer = alle)
}

/** Bildschirm-Moment (Inszenierungs-Event): Banner auf Screen + Handys. */
export interface MomentView {
  id: string;
  ts: number;
  art: string; // joker | boost | rad | strafe | underdog | info | sound
  text: string;
}

export interface VotingView {
  frage: string;
  optionen: string[];
  stimmen: number[];
  endetAt: number;
  deineStimme?: number | null; // nur PlayerView
}

/** Ergebnis-Einblendung nach Voting-Schluss: Balken + Sieger-Option (~7 s). */
export interface VotingErgebnisView {
  frage: string;
  optionen: string[];
  stimmen: number[];
  gewinnerIndex: number | null; // null = keine Stimme abgegeben
  endetAt: number;
}

export interface SiegerehrungView {
  platzierungen: {
    playerId: string;
    name: string;
    avatar: AvatarFarbe;
    platz: number;
    balance: number;
    at: number; // All-Time-Umrechnung (§3.6)
  }[];
  awards: { titel: string; playerId: string; name: string; wert: string }[];
  /** Team-Modus (ADDITIV): Team-Podest der Siegerehrung — sonst nicht gesetzt.
   * Reihenfolge = Endstand (Shake-Sieger-Team bricht Topf-Gleichstände). */
  teams?: {
    teamId: string;
    name: string;
    farbe: string;
    emoji: string;
    platz: number;
    topf: number;
  }[];
}

// ---------- v2: Replay-Highlights / Sudden-Death / Jubiläum (ADDITIV) ----------

/** Eine Highlight-Karte der „Highlights des Abends"-Sequenz (v2, E-01). */
export interface HighlightKarteView {
  id: string;
  /** groesster-klau | knappster-buzzer | teuerste-falschantwort | bank-verrat |
   * comeback | jackpot — Heuristik-Art (Client wählt Farbe/Icon danach). */
  art: string;
  titel: string;
  text: string; // dramatischer Satz MIT Namen + Zahlen
  playerId: string; // Haupt-Akteur → Handy zeigt „DU warst das!"
  playerName: string;
  avatar: AvatarFarbe;
  gegnerId?: string;
  gegnerName?: string;
  betrag?: number;
  frageNr: number;
}

/** Replay-Sequenz vor der Siegerehrung: eine Karte je Highlight (~4,5 s). */
export interface HighlightsView {
  karten: HighlightKarteView[];
  index: number; // aktuell gezeigte Karte
  endetAt: number; // Server-Deadline der aktuellen Karte
  karteMs: number; // Anzeigedauer je Karte (Fortschrittsbalken)
}

/** Sudden-Death (v2, C-03): Kokosnuss-Shake bei Gleichstand nach dem Finale. */
export interface TiebreakerView {
  subphase: "countdown" | "shake" | "ergebnis";
  endetAt: number;
  runde: number; // 1-basiert — Re-Shake bei erneutem Gleichstand
  betrag: number; // der umkämpfte Kontostand
  teilnehmer: { playerId: string; name: string; avatar: AvatarFarbe; taps: number }[];
  siegerId: string | null; // gesetzt in subphase "ergebnis"
}

/** Jubiläums-Erkennung (v2, C-05): Gruppen-Meilenstein wird im Opening gefeiert. */
export interface JubilaeumsView {
  titel: string; // z. B. „🎉 Euer 10. Abend!"
  text: string;
  matchNr: number; // das JETZT laufende Match der Gruppe
  gesamtMoney: number; // Lifetime-Money der Gruppe (alle bisherigen Endstände)
  rekord: { name: string; endstand: number } | null; // ewiger Einzel-Match-Rekord
  meilensteine: string[]; // z. B. ["match-10"], ["money-100k"]
}

// ---------- Team-Modus „Affenbanden" (ADDITIV, GAME-DESIGN §1.4) ----------

/** Ein Team im Wire-Format: Name/Farbe + Topf + Mitglieder MIT Einzel-Konten. */
export interface TeamEintragView {
  id: string;
  name: string;
  farbe: string; // CSS-Farbe für Rahmen/Banner/Spalten
  emoji: string;
  /** TEAM-TOPF = Summe der Mitglieds-Konten (Doppel-Affe ×2). */
  topf: number;
  /** 1-basiert im Team-Ranking; 0 in der Lobby (noch kein Stand). */
  platz: number;
  mitglieder: {
    playerId: string;
    name: string;
    avatar: AvatarFarbe;
    balance: number;
    /** Doppel-Affe-Regel: zählt im Topf doppelt (ungerade Zahl, 2er-Modus). */
    doppelAffe: boolean;
  }[];
}

/** Team-Block in allen Views — null wenn Team-Modus aus/nicht aktiv. */
export interface TeamsView {
  modus: string; // 2er | 2v2v2v2 | frei
  /** Lobby-Phase: Spieler dürfen ihren Team-Wunsch (um)wählen. */
  wahlOffen: boolean;
  /** Team-Modus greift erst ab so vielen Spielern (Screen-Hinweis). */
  minSpieler: number;
  teams: TeamEintragView[];
  /** Nur PlayerView: eigenes Team (bzw. eigener Lobby-Wunsch). */
  deinTeam?: string | null;
}

/** PlayerView: eigene Joker-Leiste (Besitz + Kaufpreis + Einsatzfenster-Status). */
export interface JokerLeisteEintrag {
  id: string;
  name: string;
  emoji: string;
  beschreibung: string;
  ladungen: number;
  /** Kaufpreis JETZT (inkl. Sozialrabatt) — null = nicht (nach)kaufbar. */
  preis: number | null;
  /** Jetzt zündbar (Einsatzfenster + Format-Unterstützung + Regeln). */
  nutzbar: boolean;
}

/** Gemeinsamer View-Rumpf aller Rollen. */
export interface ViewBase {
  phase: EnginePhase;
  roomCode: string;
  players: SpielerPublic[];
  paused: PauseInfo | null;
  serverTime: number;
  frageNr: number; // 1-basiert über das ganze Match, 0 = noch keine
  frageTotal: number;
  /** Rollen-spezifischer Minigame-View (plugin.viewFor) — null außerhalb frage/aufloesung. */
  minigame: { id: string; view: unknown } | null;
  // ---------- Engine-Ausbau (ADDITIV) ----------
  abschnitt: AbschnittInfo | null;
  jackpotGlas: number;
  /** Fragen-Pott (Steuerprüfung/Affe würfelt) — kassiert der nächste Fragen-Gewinner. */
  pott: number;
  modifiers: ModifierView[];
  momente: MomentView[];
  kategorieWahl: KategorieWahlView | null;
  erklaerkarte: ErklaerkarteView | null;
  rad: RadView | null;
  voting: VotingView | null;
  /** Nach Voting-Schluss: Ergebnis-Einblendung (Screen + Handys, ~7 s). */
  votingErgebnis: VotingErgebnisView | null;
  siegerehrung: SiegerehrungView | null;
  /** Abspann/GM-Trigger: Handys zeigen Freitext-Feedback-Formular. */
  feedbackAngefragt: boolean;
  /** META (§7.4): Shop-Kosmetik (Avatar-Extras) im Match rendern ja/nein. */
  alltimeItems: boolean;
  // ---------- v2-Features (ADDITIV) ----------
  /** Replay-Highlights (Phase "highlights") — sonst null. */
  highlights: HighlightsView | null;
  /** Sudden-Death-Kokosnuss-Shake (Phase "tiebreaker") — sonst null. */
  tiebreaker: TiebreakerView | null;
  /** Gruppen-Jubiläum dieses Matches (Opening-Feier) — sonst null. */
  jubilaeum: JubilaeumsView | null;
  /** Team-Modus „Affenbanden" (ADDITIV) — null wenn aus/nicht aktiv. */
  teams: TeamsView | null;
  // ---------- Tipps + Kontext-Anker (ADDITIV, Eval 5) ----------
  /** Tipp-Kanone: die für DIESE Frage bereits enthüllten Autoren-Tipps
   * (öffentlich — Screen zeigt sie unter der Frage, Handys als Banner). */
  tipps: string[];
  /** Kategorie-Badge der laufenden Frage („Gaming · Minecraft") — nur in
   * frage/aufloesung bei Frage-Formaten (quiz/estimate/sort/media). */
  frageKategorie: string | null;
  // ---------- Musik-Rotation (ADDITIV, Musik-Welle 3) ----------
  /** Match-Setting musik: an/aus — der Screen pausiert das Bett bei aus. */
  musikAn: boolean;
  /** Show-weite Musik-Lautstärke 0–1 (GM-Regler, multipliziert lokal). */
  musikVolume: number;
  /** GM-„Nächster Track"-Zähler: jede Erhöhung = 1 Skip der Bett-Rotation
   * (der Screen reagiert auf die Änderung — deterministisch, kein Event-Spam). */
  musikSkips: number;
}

export interface ScreenView extends ViewBase {
  role: "screen";
  joinUrl: string;
  qrPath: string; // Server-generierter QR (GET /api/qr?code=…)
  gmPin: string; // wird in der Lobby klein angezeigt (TECH-SPEC §3.1)
  standings: { id: string; name: string; avatar: AvatarFarbe; balance: number }[];
  /** LOBBY (ADDITIV): Anzeige-Name + Sichtbarkeit im öffentlichen Lobby-Browser. */
  lobbyName: string;
  oeffentlich: boolean;
}

export interface PlayerView extends ViewBase {
  role: "player";
  you: SpielerPublic;
  standings: { id: string; name: string; avatar: AvatarFarbe; balance: number }[];
  /** Joker-Leiste (leer bei jokerAn=aus oder im Finale). */
  jokers: JokerLeisteEintrag[];
  /** Flüster-Tipp vom GM — erscheint NUR auf diesem Handy. */
  fluesterTipp: string | null;
  /** Schmiergeld-Stufe-2-Hinweis (Anfangsbuchstabe) — nur eigenes Handy. */
  hinweis: string | null;
  /** Blitz-Stimmung (GM-Werkzeug 14): 5-Emoji-Poll, Antwort via vote.cast 0–4. */
  mood: { endetAt: number; deineWahl: number | null } | null;
}

export interface GmView extends ViewBase {
  role: "gm";
  joinUrl: string;
  standings: { id: string; name: string; avatar: AvatarFarbe; balance: number }[];
  log: { id: string; ts: number; cmd: string; text: string }[]; // letzte Kommando-Log-Einträge
  // ---------- Cockpit-Ausbau (ADDITIV) ----------
  settings: MatchSettings;
  autoGm: boolean;
  /** Fragen-Regal: die nächsten Kandidaten (GEHEIM: inkl. Antwort). */
  regal: { id: string; kategorie: string; schwierigkeit: string; text: string; antwort: string }[];
  /** Maßanzug-Zuweisungen für die nächste Frage (playerId → questionId). */
  zuweisungen: Record<string, string>;
  /** Maßanzug-Ziel: Format der nächsten Frage + ob es per-Spieler-Fragen kann.
   * verfuegbar=false ⇒ Cockpit sagt ehrlich „bei diesem Format nicht verfügbar". */
  zuweisungsZiel: { minigameId: string; minigameName: string; verfuegbar: boolean } | null;
  dramaMeter: { score: number; empfehlung: string | null };
  budgets: {
    jokerChips: number; // GM-Vergabe-Budget (6/Session)
    verlaengerungenDieseFrage: number; // max. 2
    encoresDieseRunde: number; // max. 2
    blitzStimmungen: number; // max. 3/Session
    hintStufe: number; // globale Hint-Stufe dieser Frage (0–3)
  };
  /** Eingesammeltes Feedback (Werkzeug 14 / Abspann). */
  feedback: { playerId: string; name: string; text: string }[];
  /** Blitz-Stimmungs-Ergebnisse (nur Cockpit). */
  stimmung: { ts: number; werte: number[] }[];
  /** Spickzettel: die 3 Autoren-Tipps der laufenden Frage (GEHEIM bis zum
   * Senden) — Knöpfe „Tipp 1/2/3 senden" feuern gm.hintGlobal (Stufe zählt
   * hoch, budgets.hintStufe = schon gesendet). Leer = Frage ohne Tipps. */
  spickzettelTipps: string[];
}

export type AnyView = ScreenView | PlayerView | GmView;
