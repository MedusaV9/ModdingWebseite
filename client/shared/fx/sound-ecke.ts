// Lautstärke-Ecke (Screen) + Kopfzeilen-Sound-Control (Player).
// Screen ist default laut, Handys default stumm (Opt-in per Tap — genau die
// Geste, die gleichzeitig den Audio-Unlock auslöst).
// Playtest 3: der floating Eck-Knopf überdeckte am Handy Antwort D und das
// Feedback-Feld — der Player bekommt darum ein RESERVIERTES Element in der
// Spieler-Kopfzeile (soundKopf) statt eines Overlays über Interaktivem.
import { html, type TemplateResult } from "lit-html";
import type { SoundSystem } from "./sound";

export function soundEcke(sound: SoundSystem, neuZeichnen: () => void): TemplateResult {
  const stumm = sound.istStumm();
  return html`<div class="sound-ecke">
    ${
      stumm
        ? ""
        : html`<input
            type="range"
            min="0"
            max="100"
            .value=${String(Math.round(sound.getLautstaerke() * 100))}
            aria-label="Lautstärke"
            @input=${(e: Event) => {
              sound.setLautstaerke(Number((e.target as HTMLInputElement).value) / 100);
            }}
          />`
    }
    <button
      aria-label=${stumm ? "Ton einschalten" : "Ton ausschalten"}
      title=${stumm ? "Ton einschalten" : "Ton ausschalten"}
      @click=${() => {
        sound.setStumm(!stumm);
        if (stumm) sound.sound("bestaetigen");
        neuZeichnen();
      }}
    >
      ${stumm ? "🔇" : "🔊"}
    </button>
  </div>`;
}

// Lautstärke-Sheet offen? (Modul-Zustand — 1 Player-App pro Seite.)
let sheetOffen = false;

/** Sound-Control für die Spieler-Kopfzeile: Stumm-Toggle als reserviertes
 * Element (kein Overlay über Eingaben), Lautstärke im aufklappbaren Mini-Sheet. */
export function soundKopf(sound: SoundSystem, neuZeichnen: () => void): TemplateResult {
  const stumm = sound.istStumm();
  if (stumm) sheetOffen = false;
  return html`<div class="sound-kopf">
    <button
      class="sound-kopf-knopf"
      aria-label=${stumm ? "Ton einschalten" : "Ton ausschalten"}
      title=${stumm ? "Ton einschalten" : "Ton ausschalten"}
      @click=${() => {
        sound.setStumm(!stumm);
        if (stumm) sound.sound("bestaetigen");
        neuZeichnen();
      }}
    >
      ${stumm ? "🔇" : "🔊"}
    </button>
    ${
      stumm
        ? ""
        : html`<button
            class="sound-kopf-knopf ${sheetOffen ? "aktiv" : ""}"
            aria-label="Lautstärke einstellen"
            title="Lautstärke"
            @click=${() => {
              sheetOffen = !sheetOffen;
              neuZeichnen();
            }}
          >
            🎚
          </button>`
    }
    ${
      sheetOffen && !stumm
        ? html`<div class="sound-sheet">
            <span class="muted" style="font-size:0.85rem">Lautstärke</span>
            <input
              type="range"
              min="0"
              max="100"
              .value=${String(Math.round(sound.getLautstaerke() * 100))}
              aria-label="Lautstärke"
              @input=${(e: Event) => {
                sound.setLautstaerke(Number((e.target as HTMLInputElement).value) / 100);
              }}
            />
          </div>`
        : ""
    }
  </div>`;
}
