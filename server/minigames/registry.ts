// Server-seitige Plugin-Registry: 1 Ordner = 1 Plugin. Neue Minigames docken hier an.
import type { MinigamePlugin } from "./_api/plugin";
import { affenAuktionPlugin } from "./affen-auktion/index";
import { affenbankPlugin } from "./affenbank/index";
import { affenleiterPlugin } from "./affenleiter/index";
import { allesOderBananePlugin } from "./alles-oder-banane/index";
import { bananenBasicsPlugin } from "./bananen-basics/index";
import { bananenBluffPlugin } from "./bananen-bluff/index";
import { bananenBoersePlugin } from "./bananen-boerse/index";
import { boxkampfPlugin } from "./bananen-boxkampf/index";
import { bananenTresorPlugin } from "./bananen-tresor/index";
import { tortenschlachtPlugin } from "./bananen-tortenschlacht/index";
import { buchstabenTelegrammPlugin } from "./buchstaben-telegramm/index";
import { einerGegenAllePlugin } from "./einer-gegen-alle/index";
import { goldenerAffePlugin } from "./goldener-affe/index";
import { kokosnussUhrPlugin } from "./kokosnuss-uhr/index";
import { konterQuizPlugin } from "./konter-quiz/index";
import { lianenFinalePlugin } from "./lianen-finale/index";
import { lianenstegDuellPlugin } from "./lianensteg-duell/index";
import { monkeyMarketPlugin } from "./monkey-market/index";
import { musikvideoRatenPlugin } from "./musikvideo-raten/index";
import { pixelDschungelPlugin } from "./pixel-dschungel/index";
import { risikoLeiterPlugin } from "./risiko-leiter/index";
import { songRueckwaertsPlugin } from "./song-rueckwaerts/index";
import { songSnippetPlugin } from "./song-snippet/index";
import { stinkbananePlugin } from "./stinkbanane/index";
import { taschendiebPlugin } from "./taschendieb/index";
import { vierLianenPlugin } from "./vier-lianen/index";
import { werSingtsPlugin } from "./wer-singts/index";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const plugins: Record<string, MinigamePlugin<any, any>> = {
  [vierLianenPlugin.meta.id]: vierLianenPlugin,
  [kokosnussUhrPlugin.meta.id]: kokosnussUhrPlugin,
  [bananenTresorPlugin.meta.id]: bananenTresorPlugin,
  [affenleiterPlugin.meta.id]: affenleiterPlugin,
  [pixelDschungelPlugin.meta.id]: pixelDschungelPlugin,
  [stinkbananePlugin.meta.id]: stinkbananePlugin,
  [taschendiebPlugin.meta.id]: taschendiebPlugin,
  [bananenBasicsPlugin.meta.id]: bananenBasicsPlugin,
  [affenbankPlugin.meta.id]: affenbankPlugin,
  [allesOderBananePlugin.meta.id]: allesOderBananePlugin,
  [lianenFinalePlugin.meta.id]: lianenFinalePlugin,
  // v2-Welle (Agent D): Handel, Bluff, Börse, Auktion.
  [monkeyMarketPlugin.meta.id]: monkeyMarketPlugin,
  [bananenBluffPlugin.meta.id]: bananenBluffPlugin,
  [bananenBoersePlugin.meta.id]: bananenBoersePlugin,
  [affenAuktionPlugin.meta.id]: affenAuktionPlugin,
  // v2-Welle 2 (Agent E): Duell-Bracket + Finale-Alternative.
  [lianenstegDuellPlugin.meta.id]: lianenstegDuellPlugin,
  [goldenerAffePlugin.meta.id]: goldenerAffePlugin,
  // Musik-Welle (Agent B): Paar-Telegramm (immer spielbar, eingebauter
  // Begriffs-Pool) + Stummfilm-Studio (meldet sich ohne video3s-Songs
  // nicht-verfügbar — Playlist-Aufnahme erst, wenn der Song-Loader
  // songs.json in den ContentSlice injiziert).
  [buchstabenTelegrammPlugin.meta.id]: buchstabenTelegrammPlugin,
  [musikvideoRatenPlugin.meta.id]: musikvideoRatenPlugin,
  // Musik-Welle (Agent A): Blitz-DJ (Eskalations-Buzzer) + Rückwärts-Banane
  // (Simultan-MC mit Vorwärts-Aha) — Song-Pack-Formate (contentKind "songs").
  [songSnippetPlugin.meta.id]: songSnippetPlugin,
  [songRueckwaertsPlugin.meta.id]: songRueckwaertsPlugin,
  // Buzz-Welle 3 (Agent Buzz): Tortenschlacht (Rauswurf-Sitzkreis) +
  // Boxkampf (1v1-HP-Duell mit Buzzer-Reihenfolge + Zuschauer-Wetten).
  [tortenschlachtPlugin.meta.id]: tortenschlachtPlugin,
  [boxkampfPlugin.meta.id]: boxkampfPlugin,
  // Duell-Welle 4: Konter-Quiz (freundliches 1v1 mit nullsummigem
  // Konter-Transfer) + Wer singt's? (Musik-Wissens-Quiz, eingebauter
  // Fakten-Pool + Song-Pack-Zusatzfragen — immer spielbar, contentKind none).
  [konterQuizPlugin.meta.id]: konterQuizPlugin,
  [werSingtsPlugin.meta.id]: werSingtsPlugin,
  // Klassiker-Welle 4: Risiko-Leiter (Gewinnleiter mit Sicherheitsstufe 3 =
  // 400 MM + Gipfel-Jackpot) + Einer gegen alle (der Führende gegen die
  // Mengen-Mehrheit, minPlayers 3).
  [risikoLeiterPlugin.meta.id]: risikoLeiterPlugin,
  [einerGegenAllePlugin.meta.id]: einerGegenAllePlugin,
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function getPlugin(id: string): MinigamePlugin<any, any> {
  const plugin = plugins[id];
  if (!plugin) throw new Error(`Minigame-Plugin unbekannt: ${id}`);
  return plugin;
}

export function allePlugins(): string[] {
  return Object.keys(plugins);
}

/**
 * ADDITIV (Musik-Welle): verfügbare Plugin-Ids unter Berücksichtigung des
 * Song-Pack-Zustands — ohne geladene songs.json melden sich die
 * contentKind-"songs"-Formate NICHT verfügbar, und die Playlist fällt über
 * plan.aufloesen() aufs Frage-Format zurück (Mechanismus existiert, Wächter:
 * server/engine/song-verfuegbarkeit.test.ts).
 * `videoSongs` (Anzahl Songs MIT medien.video3s, shared/songs.ts
 * zaehleVideoSongs) gated Formate mit meta.minVideoSongs (Stummfilm-Studio:
 * ≥ 3) — Aufrufer ohne den Zähler (Alt-Signatur) lassen Video-Formate
 * konservativ draußen.
 * room.startMatch reicht diese Funktion statt plugins.alle() mit
 * `songsVerfuegbar: songs.length > 0` + `videoSongs`.
 */
export function allePluginsFuer(opts: { songsVerfuegbar: boolean; videoSongs?: number }): string[] {
  return Object.values(plugins)
    .filter((p) => opts.songsVerfuegbar || p.meta.contentKind !== "songs")
    .filter((p) => (p.meta.minVideoSongs ?? 0) <= (opts.videoSongs ?? 0))
    .map((p) => p.meta.id);
}
