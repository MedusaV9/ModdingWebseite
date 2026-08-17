// „Rückwärts-Banane" (song-rueckwaerts) — beidseitige Meta + Action-Typen.
//
// DESIGN-KERN: Der Screen spielt rueckwaerts5s (das Intro RÜCKWÄRTS) — alle
// Affen raten GLEICHZEITIG aus 4 Optionen (Titel — Artist, kein Buzzer, jeder
// darf). Der Abspielplan liegt im Server-State: Erst-Abspielung + eine
// Auto-Wiederholung sind vorgeplant, GM „+15 s" (timer.extend) hängt eine
// dritte Abspielung an (max. RB_MAX_ABSPIELUNGEN — „2× wiederholbar per
// GM/Auto"). Die AUFLÖSUNG spielt das Intro VORWÄRTS — der Aha-Moment!
// SCORING wie MC-Standard (§3.1): Grundwert der Song-Schwierigkeit +
// Speed-Bonus (shared/money.fragenGewinn); Streak zählt (faires
// Alle-antworten-Format, explizit — contentKind "songs" hat keinen Default).
export const SONG_RUECKWAERTS_ID = "song-rueckwaerts";

export const SONG_RUECKWAERTS_META = {
  id: SONG_RUECKWAERTS_ID,
  name: "Rückwärts-Banane",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  contentKind: "songs" as const,
  needsScreen: true, // das Rückwärts-Audio läuft über den SCREEN
  streak: true,
};

/** Spieler-Aktionen: Simultan-MC — die ERSTE Antwort zählt (Lock). */
export type SongRueckwaertsAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing ----------
/** Antwort-Fenster: 5 s Clip + Denkpause + Auto-Replay + Rest-Raten. */
export const RB_TIMER_MS = 24_000;
/** Vorlauf bis zur Erst-Abspielung („Ohren auf!"-Beat). */
export const RB_VORLAUF_MS = 1_000;
/** Pause zwischen Clip-Ende und Auto-Wiederholung. */
export const RB_REPLAY_PAUSE_MS = 2_500;
/** Clip-Länge (rueckwaerts5s — Format-Vertrag der Pipeline). */
export const RB_CLIP_MS = 5_000;
/** Max. Abspielungen: Erst-Abspielung + 2 Wiederholungen (GM/Auto). */
export const RB_MAX_ABSPIELUNGEN = 3;
/** GM-Bonus-Replay startet so viel nach dem timer.extend. */
export const RB_GM_REPLAY_VORLAUF_MS = 800;

/** Auto-Abspielplan ab Frage-Start (Server-Zeiten): Erst-Play + 1 Replay. */
export function rbAutoAbspielplan(startedAt: number): number[] {
  const erste = startedAt + RB_VORLAUF_MS;
  return [erste, erste + RB_CLIP_MS + RB_REPLAY_PAUSE_MS];
}
