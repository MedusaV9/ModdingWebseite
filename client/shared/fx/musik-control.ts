// Musik-Control des Screens (Musik-Welle 3): dezentes Widget unten rechts
// ÜBER der Lautstärke-Ecke — Musik-Toggle (getrennt vom SFX-Stumm!), eigener
// Musik-Volume-Regler, „Nächster Track"-Skip und der Track-Ticker
// „♪ Titel — Artist" (Credits-Pflicht der MacLeod-Betten, charmant gelöst).
// Zustand persistiert im localStorage (sound.ts, Key mm:sound:screen).
import { html, type TemplateResult } from "lit-html";
import type { SoundSystem } from "./sound";

export function musikControl(sound: SoundSystem, neuZeichnen: () => void): TemplateResult {
  const an = sound.istMusikAn();
  const matchAn = sound.istMatchMusikAn();
  const track = sound.aktuellerTrack();
  const ticker = !matchAn
    ? "Musik aus (Match-Setting)"
    : !an
      ? "Musik aus"
      : track !== null
        ? `♪ ${track.titel} — ${track.artist}`
        : "♪ …";
  return html`<div class="musik-control" data-testid="mm-musik-control">
    <span class="musik-ticker" data-testid="mm-musik-ticker" title=${ticker}>${ticker}</span>
    ${
      an && matchAn
        ? html`<input
              type="range"
              min="0"
              max="100"
              .value=${String(Math.round(sound.getMusikLautstaerke() * 100))}
              aria-label="Musik-Lautstärke"
              data-testid="mm-musik-vol"
              @input=${(e: Event) => {
                sound.setMusikLautstaerke(Number((e.target as HTMLInputElement).value) / 100);
              }}
            /><button
              aria-label="Nächster Track"
              title="Nächster Track"
              data-testid="mm-musik-skip"
              @click=${() => {
                sound.musikSkip();
                neuZeichnen();
              }}
            >
              ⏭
            </button>`
        : ""
    }
    <button
      class=${an ? "" : "musik-aus"}
      aria-label=${an ? "Musik ausschalten" : "Musik einschalten"}
      title=${an ? "Musik ausschalten" : "Musik einschalten"}
      data-testid="mm-musik-toggle"
      @click=${() => {
        sound.setMusikAn(!an);
        neuZeichnen();
      }}
    >
      🎵
    </button>
  </div>`;
}
