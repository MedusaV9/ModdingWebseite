// MinigamePlugin-Interface (TECH-SPEC §2.1) — der wichtigste Vertrag des Projekts.
// Alle Hooks sind PURE: Clock/Rng NUR aus ctx, State IMMER JSON-serialisierbar.
// Minigame-State lebt IM Engine-State → Save/Load, Reconnect und Event-Log
// funktionieren automatisch. Interface-Einfrieren erst nach 4 Referenz-Minigames.
//
// ENGINE-AUSBAU (ADDITIV — bestehende Plugins bleiben gültig):
//   · Ctx.buzzer  — Buzzer-Fairness-API (Median-RTT, Sammel-Fenster, Fotofinish-Los)
//   · Ctx.match   — Read-only-Match-Infos (Kontostände, Reihenfolge, Klau-Schutz)
//   · JokerAction — Joker-Wirkungs-Hooks (nur an Plugins mit meta.jokerAktionen)
//   · outcomes()  — optionale Richtig/Falsch-Auskunft (Streak, Jackpot, Finale, Auto-GM)
//   · meta-Flags  — roundBased / streak / strafenInsGlas / jokerAktionen
import type { ContentSlice } from "../../../shared/content";
import type { PlayerId } from "../../../shared/ids";
import type { Rng } from "../../../shared/rng";
import type { SongsSlice } from "../../../shared/songs";
import type { Clock } from "../../../shared/time";
import type { BuzzErgebnis, BuzzKandidat } from "../../../shared/buzzer";

/** Buzzer-Fairness (TECH-SPEC §3.3) — die Engine liefert die Implementierung.
 * Buzz-Eingaben kommen als PlayerAction `{type:"buzz", finalAt:number}` an:
 * finalAt ist bereits Median-RTT-geclampt; das Plugin wendet nur noch
 * max(armedAt, finalAt) an und sammelt bis sammelfensterEnde(ersterBuzz). */
export interface BuzzerApi {
  /** Median-RTT des Spielers (Server-Messung, letzte 5 Proben). */
  medianRtt(p: PlayerId): number;
  sammelfensterMs: number; // 280
  fotofinishMs: number; // 40
  /** Sortierung + Fotofinish-Los (injizierter Rng der Engine). */
  ordne(kandidaten: BuzzKandidat[]): BuzzErgebnis[];
}

/** Read-only-Blick auf den Match-Zustand (für Klau-Formate, Tausch, Kappen). */
export interface MatchApi {
  balance(p: PlayerId): number;
  /** Lobby-Reihenfolge (Sitznachbarn, Stinkbananen-Kreis). */
  reihenfolge(): PlayerId[];
  /** Bananentresor-Schild aktiv? (J6 — Klau-Effekte prallen ab). */
  hatKlauSchutz(p: PlayerId): boolean;
  istVerbunden(p: PlayerId): boolean;
  /** Team-Modus „Affenbanden" (ADDITIV, optional): TeamId des Spielers —
   * null ohne Team-Modus. Klau-Formate bevorzugen damit GEGNER-Teams. */
  teamVon?(p: PlayerId): string | null;
}

export interface Ctx {
  clock: Clock;
  rng: Rng;
  /** In Engine-Läufen immer gesetzt; in isolierten Tests optional. */
  buzzer?: BuzzerApi;
  match?: MatchApi;
  /** ADDITIV (Musik-Formate): Song-Slice vom Song-Pack-Loader — Alternative
   * zum ContentSlice.songs-Transport. Fehlt beides, nutzen die Song-Plugins
   * den Fixture-Katalog (shared/songs.ts) — ein Match crasht NIE an Songs. */
  songs?: SongsSlice;
}

/** Vom Server verifizierter Spieler-Input (Zeitstempel = Server-Empfangszeit). */
export interface PlayerAction<A extends { type: string }> {
  kind: "player";
  playerId: PlayerId;
  action: A;
  atServerTime: number;
}

/** GM-Eingriffe, die JEDES Minigame verstehen muss (Zeit-Manipulation). */
export type GmAction =
  | { kind: "gm"; type: "timer.extend"; ms: number } // GM: „+15 s"
  | { kind: "gm"; type: "timer.shift"; ms: number } // Pause/Resume: Deadline verschieben
  | { kind: "gm"; type: "force.finish" }; // GM: Frage-Skip

/**
 * Joker-Wirkungs-Hooks (GAME-DESIGN §5.1) — die Engine schickt sie NUR an
 * Plugins, die die Aktion in meta.jokerAktionen deklarieren:
 *   fiftyFifty — Bananen-Split: 2 falsche Optionen für DIESEN Spieler sperren
 *   removeOne  — Schmiergeld Stufe 1: 1 falsche Option sperren (auch global via GM-Hint)
 *   secondTry  — Rückgaberecht: falsche Antwort löschen, Option sperren, Gewinn 50 %
 */
export type JokerAction =
  | { kind: "joker"; type: "fiftyFifty"; playerId: PlayerId }
  | { kind: "joker"; type: "removeOne"; playerId: PlayerId | null } // null = für alle (GM-Hint)
  | { kind: "joker"; type: "secondTry"; playerId: PlayerId };

export type Role = "screen" | "player" | "gm";

/** Richtig/Falsch-Auskunft pro Spieler: correct=null ⇒ (noch) keine Antwort. */
export interface PlayerOutcome {
  correct: boolean | null;
  /** Antwortzeit nach Frage-Start in ms (für Pott-Vergabe/Jackpot-Glas-Splits). */
  nachMs?: number;
  /** Rückgaberecht eingelöst — Jackpot-Frage zahlt dann nur den HALBEN Jackpot
   * (2.000er-Festwert UND Glas-Anteil halbiert; Rest bleibt im Glas). */
  zweitversuch?: boolean;
}

export interface MinigamePlugin<S, A extends { type: string }> {
  meta: {
    id: string;
    name: string;
    minPlayers: number;
    maxPlayers: number;
    formats: readonly (
      "buttons" | "slider" | "dragList" | "hold" | "tapFrenzy" | "buzzer" | "text"
    )[];
    /** ADDITIV "songs": Format spielt Song-Packs (content/musik/songs.json)
     * statt Fragen — ohne geladene Songs meldet die Registry das Format als
     * nicht verfügbar (allePluginsFuer), die Playlist fällt aufs Frage-Format
     * zurück. Streak-Default bleibt an contentKind === "quiz" gekoppelt. */
    contentKind: "quiz" | "estimate" | "sort" | "media" | "none" | "songs";
    requiresSecureContext?: boolean; // Mikro/Kipp-Spiele → im HTTP-Pfad ausgeblendet
    needsScreen?: boolean;
    supportsGamepad?: boolean;
    // ---------- Engine-Ausbau (ADDITIV, alle optional) ----------
    /** true: EIN init() pro RUNDE (bekommt alle Fragen der Runde, z. B. Affenbank).
     *  false/fehlend: ein init() pro FRAGE (Standard, z. B. vier-lianen). */
    roundBased?: boolean;
    /** Streak-Kette zählt in diesem Format (Default: contentKind === "quiz"). */
    streak?: boolean;
    /** Negative scores() fließen ins Jackpot-Glas (z. B. Stinkbananen-Explosion). */
    strafenInsGlas?: boolean;
    /** Unterstützte Joker-Wirkungs-Hooks (siehe JokerAction). */
    jokerAktionen?: readonly ("fiftyFifty" | "removeOne" | "secondTry")[];
    /** Plugin konsumiert mods.fragenProSpieler (Maßanzug/Portfolio) einheitlich:
     *  eigene Frage pro zugewiesenem Spieler. Fehlt das Flag, lässt die Engine
     *  Zuweisungen für dieses Format UNANGETASTET (GM-Cockpit zeigt das ehrlich). */
    perSpielerFragen?: boolean;
    /** ADDITIV (Musik): Format WÜNSCHT den Song-Pool zusätzlich zum eigenen
     *  contentKind (z. B. Telegramm, contentKind "none": Song-Titel wandern in
     *  den Begriffs-Topf). flow.starteFrage hängt dann den KOMPLETTEN Pool
     *  READ-ONLY an ContentSlice.songs — OHNE usedSongIds-Verbrauch: die
     *  No-Repeat-Sperre bleibt den echten Song-Formaten (waehleSongSlice)
     *  vorbehalten, reine Titel-Nutzer verbrennen kein Blitz-DJ-Kontingent. */
    wuenschtSongs?: boolean;
    /** ADDITIV (Musik): Mindestzahl an Songs MIT medien.video3s, damit sich
     *  dieses Format verfügbar meldet (registry.allePluginsFuer). Fehlt das
     *  Feld ⇒ keine Video-Anforderung. Stummfilm-Studio setzt 3 — mit dem
     *  1-Video-Starter-Pack bleibt es aus der Playlist (plan.aufloesen). */
    minVideoSongs?: number;
    /** Auto-GM-+10s-Heuristik (engine.tick: <50 % geantwortet + <4 s übrig ⇒
     *  einmalig verlängern) EXPLIZIT abschalten. Default: erlaubt, sofern der
     *  Screen-View endsAt+answeredCount exponiert. `false` setzen, wenn
     *  answeredCount KEINE klassischen Antworten zählt (Blitz-DJ-Falle:
     *  Buzzes sind keine Antworten — Schweigen ist dort Spielverlauf). */
    autoVerlaengerung?: boolean;
  };
  // Lifecycle-Hooks — ALLE pure:
  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): S;
  reduce(state: S, action: PlayerAction<A> | GmAction | JokerAction, ctx: Ctx): S;
  tick(state: S, ctx: Ctx): S; // Server-Timer-Fortschritt (Phasen, Stufen)
  onDisconnect(state: S, p: PlayerId, ctx: Ctx): S; // AFK-Regel des Spiels (Default: no-op)
  onReconnect(state: S, p: PlayerId, ctx: Ctx): S;
  viewFor(state: S, role: Role, player?: PlayerId): unknown; // Geheimnis-Filterung SERVERSEITIG
  isFinished(state: S): boolean;
  scores(state: S): Record<PlayerId, number>; // Engine bucht aufs MM-Konto
  /** OPTIONAL: Richtig/Falsch pro Spieler — Grundlage für Streak-Kette,
   * Jackpot-Frage, Finale-Formel, Applaus-Almosen und Auto-GM-Heuristiken.
   * Fehlt der Hook, nimmt die Engine delta > 0 als „richtig". */
  outcomes?(state: S): Record<PlayerId, PlayerOutcome>;
}
