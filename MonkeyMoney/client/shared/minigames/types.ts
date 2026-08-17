// Client-Renderer-Interface für Minigames (TECH-SPEC §2.1, Client-Seite).
// Ein Minigame hat exakt drei Heimaten: shared-Meta, Server-Plugin, Client-Renderer.
import type { TemplateResult } from "lit-html";

/**
 * Partikel/Sound/Zeit-Sync für Renderer.
 * - serverNow(): geschätzte Server-Zeit (Offset aus time.ping/pong) — steht
 *   jetzt AUCH renderPlayer zur Verfügung (dokumentierter Minispiel-Wunsch:
 *   die Kokosnuss-Sack-Anzeige tickt damit exakt auf Server-Takt).
 * - sound(): Event-Sound nach ART-PLAN §4.1 (client/shared/fx/sound-map.ts) —
 *   no-op vor dem Audio-Unlock bzw. bei stummgeschalteter Rolle.
 * - partikel(): Salve auf dem Overlay-Canvas (nur Screen; Handy: no-op).
 * - spieler(): Anzeige-Infos (Name + Avatar "affe.farbe") zu einer playerId —
 *   ADDITIV am Vertrag: Plugins liefern nur Ids, die App löst sie auf
 *   (Stinkbananen-Sitzkreis, Taschendieb-Ziel-Grid zeigen echte Affen + Namen).
 */
export interface SpielerAnzeige {
  name: string;
  /** Wire-Format "affe.farbe" (oder Alt-Format nur Farbe) — parseAvatar-tauglich. */
  avatar: string;
}

export interface FxApi {
  serverNow(): number;
  sound(sfxId: string): void;
  partikel?(
    art: "konfetti" | "money-regen" | "scheine",
    opts?: {
      x?: number;
      y?: number;
      anzahl?: number;
      farbe?: string;
      /** Gekaufter Konfetti-Stil (§7.4) — Standard: klassisch. */
      stil?: "klassisch" | "bananen" | "8bit";
    },
  ): void;
  spieler?(playerId: string): SpielerAnzeige | null;
}

export type SendAction = (actionId: string, payload: unknown) => Promise<unknown>;

export interface GmApi {
  sendCmd(cmd: string, args: Record<string, unknown>): Promise<{ ok: boolean; error?: string }>;
  serverNow(): number;
}

export interface MinigameClientModule {
  id: string;
  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void;
  /** fx ist ADDITIV (Engine-Wunsch b): alte Renderer ohne 4. Parameter laufen weiter. */
  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void;
  renderGm?(view: unknown, host: HTMLElement, gm: GmApi): void; // Default: Status-Panel
  explainCard: { text: string; animation: TemplateResult };
  /** ADDITIV: Format spielt seine Auflösung selbst (richtig/zeit-um + Song-Intro
   * sofort bei finished, z. B. Blitz-DJ/Rückwärts-Banane) — die zentrale Regie
   * lässt dann Dreiklang (Riser→Stille→Fanfare) UND den verzögerten visuellen
   * Aufdeck-Flip aus (Screen deckt sofort auf, das Format dirigiert selbst). */
  eigeneAufloesungsRegie?: boolean;
}

/** ADDITIV am Screen-Renderer-Vertrag (P1 „Auflösungs-Spoiler"): Die Screen-App
 * injiziert in der Auflösungs-Phase ein `aufgedeckt`-Flag in den Minigame-View.
 * Solange es false ist (Spannungs-Fenster bis zur Fanfare, AUFLOESUNG_AUFDECK_MS)
 * ist ZUSÄTZLICH `aufloesung` bereits zentral auf null maskiert — Renderer
 * zeigen also automatisch den neutralen Frage-Zustand. Formate, die Reveal-Infos
 * außerhalb von `aufloesung` tragen, können das Flag direkt auswerten. */
export interface AufdeckBlick {
  aufgedeckt?: boolean;
}
