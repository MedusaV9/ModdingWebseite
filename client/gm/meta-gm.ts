// GM-Meta-Karte: „Bot hinzufügen" (Lobby, §Modi/AI) + Save/Load-Slots
// (3 Slots + Autosave; Laden NUR aus der Lobby — Raum läuft unter dem
// gespeicherten Code weiter). Kommandos laufen über den EINEN gm.cmd-Kanal
// (bot.add / bot.remove / save.write / save.load) — views.ts hängt nur
// die Karte ein.
import { html, type TemplateResult } from "lit-html";
import type { GmView } from "../../shared/views";
import { metaFetch } from "../shared/meta-fetch";
import { istStandalone } from "../shared/standalone-transport";

interface SlotInfo {
  slot: number;
  auto: boolean;
  savedAt: number;
  roomCode: string;
  phase: string;
  frageNr: number;
  spieler: { name: string; avatar: string }[];
}

type Sende = (cmd: string, args: Record<string, unknown>) => Promise<boolean>;

let slots: SlotInfo[] = [];
let slotsGeladen = false;

function ladeSlots(zeichne: () => void): void {
  void metaFetch("/api/meta/saves")
    .then((r) => {
      const d = r.json as { slots?: SlotInfo[] };
      slots = d.slots ?? [];
      zeichne();
    })
    .catch(() => {});
}

function slotText(info: SlotInfo | undefined): string {
  if (!info) return "leer";
  const wann = new Date(info.savedAt).toLocaleString("de-DE", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
  return `${info.roomCode} · Frage ${info.frageNr} · ${info.spieler.length} 🐒 · ${wann}`;
}

export function metaKarte(v: GmView, zeichne: () => void, sende: Sende): TemplateResult {
  if (!slotsGeladen) {
    slotsGeladen = true;
    ladeSlots(zeichne);
  }
  const inLobby = v.phase === "lobby";
  const laeuft = v.phase !== "lobby" && v.phase !== "ende";
  const proSlot = new Map(slots.map((s) => [s.slot, s]));

  return html`<div class="karte" style="display:flex;gap:10px;flex-wrap:wrap;align-items:center">
    <strong>🤖💾</strong>
    ${
      inLobby
        ? html`<button @click=${() => sende("bot.add", {})}>🤖 Bot dazu</button>
            <button @click=${() => sende("bot.remove", {})}>Bot raus</button>
            <span style="border-left:1px solid var(--muted);height:24px"></span>`
        : ""
    }
    ${[1, 2, 3].map((slot) => {
      const info = proSlot.get(slot);
      return html`<span style="display:flex;gap:4px;align-items:center">
        ${
          laeuft
            ? html`<button
                title=${slotText(info)}
                @click=${() => sende("save.write", { slot }).then(() => ladeSlots(zeichne))}
              >
                💾 Slot ${slot}
              </button>`
            : ""
        }
        ${
          inLobby && info
            ? html`<button
                  title=${slotText(info)}
                  @click=${() => sende("save.load", { slot }).then(() => ladeSlots(zeichne))}
                >
                  📂 Slot ${slot} laden
                </button>
                <span class="muted" style="font-size:0.75rem">${slotText(info)}</span>`
            : ""
        }
      </span>`;
    })}
    ${
      inLobby && proSlot.has(0)
        ? html`<button
              title=${slotText(proSlot.get(0))}
              @click=${() => sende("save.load", { slot: 0 }).then(() => ladeSlots(zeichne))}
            >
              📂 Autosave laden
            </button>
            <span class="muted" style="font-size:0.75rem">${slotText(proSlot.get(0))}</span>`
        : ""
    }
    ${
      inLobby && slots.length === 0
        ? html`<span class="muted" style="font-size:0.85rem"
            >Keine Spielstände — 💾 gibt's im laufenden Match.</span
          >`
        : ""
    }
    ${
      istStandalone()
        ? html`<span class="muted" style="font-size:0.75rem"
            >💾 Spielstände &amp; Profile liegen lokal auf dem iPad (IndexedDB).</span
          >`
        : ""
    }
  </div>`;
}
