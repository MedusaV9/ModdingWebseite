// GLÜCKSRAD als echtes drehendes Rad (Basis: assets/img/ui/rad-basis.svg).
// Segmente werden dynamisch auf die tatsächliche Ring-Größe generiert; die
// Dreh-Animation ist DETERMINISTISCH aus ergebnisIndex + dreh.{startetAt,dauerMs}
// (Engine liefert beides) — jeder Client rechnet denselben Winkel aus serverNow.
import { html, svg, type SVGTemplateResult, type TemplateResult } from "lit-html";
import type { RadView, ScreenView } from "../../shared/views";
import { RAD_SEGMENTE } from "../../shared/wheel";
import type { FxApi } from "../shared/minigames/types";

const R = 170;
const CX = 220;
const CY = 220;

function punkt(grad: number, radius: number): [number, number] {
  const rad = (grad * Math.PI) / 180;
  return [CX + radius * Math.sin(rad), CY - radius * Math.cos(rad)];
}

function segmentPfad(vonGrad: number, bisGrad: number): string {
  const [x0, y0] = punkt(vonGrad, R);
  const [x1, y1] = punkt(bisGrad, R);
  const gross = bisGrad - vonGrad > 180 ? 1 : 0;
  return `M ${CX} ${CY} L ${x0.toFixed(1)} ${y0.toFixed(1)} A ${R} ${R} 0 ${gross} 1 ${x1.toFixed(1)} ${y1.toFixed(1)} Z`;
}

/** Kubisches Ease-out — Kasino-Rad: schnell anreißen, langsam einrasten. */
function easeOut(t: number): number {
  return 1 - Math.pow(1 - Math.max(0, Math.min(1, t)), 3);
}

/** Aktueller Drehwinkel (Grad) — deterministisch aus Server-Zeit. */
export function radWinkel(rad: RadView, serverNow: number): number {
  const n = Math.max(1, rad.segmente.length);
  const seg = 360 / n;
  const ziel = 4 * 360 + (rad.ergebnisIndex + 0.5) * seg; // 4 Ehrenrunden + Zentrum
  const t = (serverNow - rad.dreh.startetAt) / Math.max(1, rad.dreh.dauerMs);
  return easeOut(t) * ziel;
}

// Tick-Geräusch, wenn ein Segment unter dem Zeiger durchrattert (Modul-Zustand,
// weil das Rad im 120-ms-Live-Intervall neu gerendert wird).
let letzterTickIndex = -1;
let letzterDrehStart = 0;

function segmentLabel(name: string, mitteGrad: number): SVGTemplateResult {
  const worte = name.split(" ");
  const zeilen: string[] = [];
  for (const w of worte) {
    if (zeilen.length > 0 && (zeilen[zeilen.length - 1] + " " + w).length <= 11) {
      zeilen[zeilen.length - 1] += ` ${w}`;
    } else {
      zeilen.push(w);
    }
  }
  const [lx, ly] = punkt(mitteGrad, 108);
  return svg`<g transform="rotate(${mitteGrad} ${lx.toFixed(1)} ${ly.toFixed(1)})">
    ${zeilen.slice(0, 3).map(
      (z, i) =>
        svg`<text x=${lx.toFixed(1)} y=${(ly + (i - (Math.min(zeilen.length, 3) - 1) / 2) * 13).toFixed(1)}
          text-anchor="middle" dominant-baseline="middle"
          font-family="Rubik,sans-serif" font-size="12" font-weight="800"
          fill="#1A1208">${z}</text>`,
    )}
  </g>`;
}

/** Das Rad als Inline-SVG — Segmente + Lauflichter + Nabe + Zeiger.
 * Klasse „dreht" (solange kein Ergebnis) lässt die Zeiger-Zunge wippen. */
export function radSvg(rad: RadView, winkel: number): TemplateResult {
  const n = Math.max(1, rad.segmente.length);
  const seg = 360 / n;
  return html`<svg
    class="rad-svg ${rad.ergebnis ? "" : "dreht"}"
    viewBox="0 0 440 440"
    role="img"
    aria-label="Glücksrad"
  >
    <circle cx="220" cy="220" r="196" fill="#14532D" stroke="#1A1208" stroke-width="7" />
    <circle cx="220" cy="220" r="178" fill="none" stroke="#F5B301" stroke-width="12" />
    <g fill="#FFDE6B" stroke="#1A1208" stroke-width="3">
      ${Array.from({ length: 10 }, (_, i) => {
        const [bx, by] = punkt(i * 36, 194);
        return svg`<circle cx=${bx.toFixed(1)} cy=${by.toFixed(1)} r="7" />`;
      })}
    </g>
    <g
      style="transform-box:view-box;transform-origin:220px 220px;transform:rotate(${(-winkel).toFixed(2)}deg)"
    >
      ${rad.segmente.map((s, i) => {
        const farbe = s.klasse === "gold" ? "#F5B301" : s.klasse === "blau" ? "#3B82F6" : "#22A559";
        return svg`<path d=${segmentPfad(i * seg, (i + 1) * seg)} fill=${farbe}
          stroke="#1A1208" stroke-width="5" stroke-linejoin="round" />`;
      })}
      ${rad.segmente.map((s, i) => segmentLabel(s.name, (i + 0.5) * seg))}
    </g>
    <circle cx="220" cy="220" r="46" fill="#0E2A1F" stroke="#1A1208" stroke-width="6" />
    <circle cx="220" cy="220" r="38" fill="none" stroke="#F5B301" stroke-width="4" />
    <text x="220" y="232" text-anchor="middle" font-size="34">🍌</text>
    <g class="rad-zeiger">
      <path
        d="M 198 8 L 242 8 L 220 58 Z"
        fill="#FF3E8E"
        stroke="#1A1208"
        stroke-width="6"
        stroke-linejoin="round"
      />
      <circle cx="220" cy="14" r="9" fill="#FFDE6B" stroke="#1A1208" stroke-width="4" />
    </g>
  </svg>`;
}

/** Rad-Phase auf dem Screen: Dreh → Einschlag → Ergebnis-Karte. */
export function radPhase(view: ScreenView, serverNow: number, fx: FxApi): TemplateResult {
  const rad = view.rad;
  if (!rad) return html`<div class="zentriert"><h1>🎡 Glücksrad!</h1></div>`;
  if (rad.interaktion) return radInteraktion(view, rad);

  const winkel = radWinkel(rad, serverNow);
  const n = Math.max(1, rad.segmente.length);
  const seg = 360 / n;

  // Ticker: Segment-Wechsel unter dem Zeiger (deterministisch, kein Zufall).
  if (rad.dreh.startetAt !== letzterDrehStart) {
    letzterDrehStart = rad.dreh.startetAt;
    letzterTickIndex = -1;
  }
  if (!rad.ergebnis) {
    const tickIndex = Math.floor((((winkel % 360) + 360) % 360) / seg);
    if (tickIndex !== letzterTickIndex) {
      letzterTickIndex = tickIndex;
      fx.sound("rad-tick");
    }
  }

  const ergebnis = rad.ergebnis;
  return html`<div class="rad-buehne">
    ${radSvg(rad, winkel)}
    ${
      ergebnis
        ? html`<div class="rad-ergebnis-karte runden-karte" style="margin:0">
            <span class="slot-tag"
              >${ergebnis.klasse === "gold" ? "✨ GOLD" : ergebnis.klasse === "blau" ? "🌀 AKTION" : "🎡 EFFEKT"}</span
            >
            <h1 style="font-size:var(--mm-display-m)">${ergebnis.name}</h1>
            <p class="regel">${ergebnis.wirkung}</p>
            ${betroffenZeile(view, ergebnis.betroffen)}
          </div>`
        : radVorschau(rad, winkel)
    }
  </div>`;
}

/** Live-Vorschau während des Drehs: das gerade anvisierte Segment GROSS +
 * 1-Zeiler-Wirkung — die mitrotierten Rad-Labels sind aus Sofadistanz
 * unlesbar (Playtest 3), das Panel rechts übernimmt die Lesbarkeit. */
function radVorschau(rad: RadView, winkel: number): TemplateResult {
  const n = Math.max(1, rad.segmente.length);
  const seg = 360 / n;
  const index = Math.floor((((winkel % 360) + 360) % 360) / seg) % n;
  const aktuell = rad.segmente[index];
  const wirkung = RAD_SEGMENTE.find((s) => s.id === aktuell?.id)?.wirkung ?? "";
  const farbe =
    aktuell?.klasse === "gold" ? "#F5B301" : aktuell?.klasse === "blau" ? "#3B82F6" : "#22A559";
  return html`<div class="rad-vorschau" data-testid="rad-vorschau">
    <h2 class="rad-vorschau-titel">Das Rad dreht … 🎯</h2>
    <div class="rad-vorschau-segment" style="--segment-farbe:${farbe}">${aktuell?.name ?? "?"}</div>
    <p class="rad-vorschau-wirkung">${wirkung}</p>
  </div>`;
}

function betroffenZeile(view: ScreenView, ids: string[]): TemplateResult {
  if (ids.length === 0) return html``;
  const namen = ids.map((id) => view.players.find((p) => p.id === id)?.name ?? "?").join(", ");
  return html`<p style="font-weight:700">Betroffen: ${namen}</p>`;
}

function radInteraktion(view: ScreenView, rad: RadView): TemplateResult {
  const ia = rad.interaktion!;
  if (ia.typ === "long-short") {
    return html`<div class="zentriert" style="gap:10px">
      <h1>🎰 Börsen-Roulette</h1>
      <p style="font-size:1.4rem">
        LONG oder SHORT auf die eigene nächste Antwort — wählt am Handy!
      </p>
    </div>`;
  }
  if (ia.typ === "umarmt") {
    return html`<div class="zentriert" style="gap:10px">
      <h1>🤗 Umarmungs-Bonus!</h1>
      <p style="font-size:1.4rem">Umarmt euch! Wer drückt, kassiert Bonus-MM.</p>
    </div>`;
  }
  const von = view.players.find((p) => p.id === ia.paar?.von)?.name ?? "?";
  const zu = view.players.find((p) => p.id === ia.paar?.zu)?.name ?? "?";
  return html`<div class="zentriert" style="gap:10px">
    <h1>💬 Kompliment-Konto</h1>
    <p style="font-size:1.5rem">
      <strong>${von}</strong> macht <strong>${zu}</strong> JETZT ein Kompliment!
    </p>
    <p class="muted">Alle stimmen am Handy ab: War's ein gutes Kompliment?</p>
  </div>`;
}
