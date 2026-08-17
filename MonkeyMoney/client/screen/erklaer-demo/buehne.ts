// Demo-Bühne: montiert eine Choreo in die Erklärkarte und spielt sie im
// rAF-Takt ab. DOM wird NUR an Beat-Grenzen angefasst (alle ~2 s) — dazwischen
// tragen CSS-Transitions/-Animationen die Bewegung (nur transform/opacity,
// kein Layout-Thrash). Skip/Phasenwechsel regelt die Engine wie gehabt: fällt
// der Host aus dem DOM, räumt der nächste Frame Loop + Controller ab.
import { html, render, type TemplateResult } from "lit-html";
import { fuellePuppen } from "../../shared/fx/affe";
import type { DemoAkteur, DemoChoreo, DemoOrt, DemoSzene } from "../../shared/minigames/demo-typen";
import type { FxApi } from "../../shared/minigames/types";
import { createDemoSpieler, type DemoTakt } from "./choreo";
import { kernregelFuer } from "./kernregeln";
import { requisitTpl } from "./requisiten";
import "./erklaer-demo.css";

/** Die zwei Beispiel-Affen der Demos (Puppen aus assets/img/monkeys/). */
export const DEMO_AKTEURE: Record<DemoAkteur, { name: string; puppe: string; farbe: string }> = {
  a: { name: "Mia", puppe: "kiki-krawall", farbe: "rot" },
  b: { name: "Bo", puppe: "pumper-paule", farbe: "tuerkis" },
};

/** Ort → horizontale Bühnen-Position (Prozent) für Banane/Geld-Flüge. */
const ORT_X: Record<DemoOrt, number> = { a: 15, mitte: 50, b: 85 };

interface AktiveDemo {
  key: string;
  host: HTMLElement;
  raf: number;
  stop: () => void;
}

let aktiv: AktiveDemo | null = null;

function stoppeAktive(): void {
  if (!aktiv) return;
  cancelAnimationFrame(aktiv.raf);
  aktiv.stop();
  aktiv = null;
}

function akteurTpl(id: DemoAkteur): TemplateResult {
  const a = DEMO_AKTEURE[id];
  return html`<div class="ed-akteur ed-akteur-${id}">
    <div class="ed-blase"></div>
    <div class="ed-stempel"></div>
    <div
      class="ed-puppe mm-affe mm-affe-idle"
      data-puppe=${a.puppe}
      data-farbe=${a.farbe}
      style="--idle-versatz:${id === "a" ? 0 : 0.7}s"
    ></div>
    <span class="ed-name von-${id}">${a.name}</span>
  </div>`;
}

/** Bühnen-Skelett — mit prominentem 1-Satz-Kernregel-Banner ÜBER der Bühne
 * (W4, Eval-6): der Merksatz steht die ganze Demo über, die Beats zeigen ihn. */
function skelettTpl(kernregel: string | null): TemplateResult {
  return html`${
      kernregel !== null
        ? html`<div class="ed-kernregel" data-testid="demo-kernregel">
            <span class="ed-kernregel-pin">📌</span>${kernregel}
          </div>`
        : ""
    }
    <div class="ed-buehne">
      ${akteurTpl("a")}
      <div class="ed-mitte"></div>
      ${akteurTpl("b")}
      <div class="ed-fx"></div>
    </div>`;
}

/** ✓/✗-Stempel des Beats: aufgelöste Frage-Requisite ⇒ Tipp je Akteur werten. */
function stempelFuer(szene: DemoSzene, id: DemoAkteur): "haken" | "kreuz" | null {
  const frage = szene.requisiten.find((r) => r.art === "frage");
  if (frage === undefined || frage.art !== "frage" || frage.richtig == null) return null;
  const tipp = id === "a" ? frage.tippA : frage.tippB;
  if (tipp == null) return null;
  return tipp === frage.richtig ? "haken" : "kreuz";
}

/** Szene auf die Bühne anwenden — läuft NUR beim Beat-Wechsel. */
function wendeSzeneAn(host: HTMLElement, takt: DemoTakt, fx: FxApi): void {
  const szene: DemoSzene = takt.szene;
  const buehne = host.querySelector<HTMLElement>(".ed-buehne");
  if (!buehne) return;

  for (const id of ["a", "b"] as const) {
    const akteur = buehne.querySelector<HTMLElement>(`.ed-akteur-${id}`);
    if (!akteur) continue;
    const puppe = akteur.querySelector<HTMLElement>(".ed-puppe");
    if (puppe) {
      puppe.className = `ed-puppe mm-affe mm-affe-idle ed-pose-${szene.pose[id]}`;
      const gesicht = szene.gesicht[id];
      puppe.dataset.gesicht = gesicht;
      const svg = puppe.querySelector("svg");
      if (svg) {
        if (gesicht !== "neutral") svg.dataset.gesicht = gesicht;
        else delete svg.dataset.gesicht;
      }
    }
    const blase = akteur.querySelector<HTMLElement>(".ed-blase");
    if (blase) {
      if (szene.blase && szene.blase.wer === id) {
        // Frisches Kind-Element ⇒ Pop-Animation startet ohne Reflow-Trick neu.
        const inhalt = document.createElement("span");
        inhalt.className = "ed-blase-inhalt";
        inhalt.textContent = szene.blase.text;
        blase.replaceChildren(inhalt);
        blase.classList.add("sichtbar");
      } else {
        blase.classList.remove("sichtbar");
      }
    }
    // ✓/✗-Stempel (W4): am Auflösungs-Beat knallt das Urteil auf die Puppe.
    const stempelHost = akteur.querySelector<HTMLElement>(".ed-stempel");
    if (stempelHost) {
      const urteil = stempelFuer(szene, id);
      if (urteil !== null) {
        const s = document.createElement("span");
        s.className = `ed-stempel-mal ${urteil}`;
        s.textContent = urteil === "haken" ? "✓" : "✗";
        stempelHost.replaceChildren(s);
      } else {
        stempelHost.replaceChildren();
      }
    }
  }

  const mitte = buehne.querySelector<HTMLElement>(".ed-mitte");
  if (mitte) render(html`${szene.requisiten.map(requisitTpl)}`, mitte);

  const fxLayer = buehne.querySelector<HTMLElement>(".ed-fx");
  if (fxLayer) {
    const kinder: HTMLElement[] = [];
    if (szene.effekt === "konfetti") {
      for (let i = 0; i < 12; i++) {
        const k = document.createElement("span");
        k.className = "ed-konfetti";
        k.style.setProperty("--i", String(i));
        kinder.push(k);
      }
    } else if (szene.effekt === "explosion") {
      const e = document.createElement("span");
      e.className = "ed-explosion";
      e.textContent = "💥";
      kinder.push(e);
    }
    if (szene.geldflug) {
      const vonX = ORT_X[szene.geldflug.von];
      const zuX = ORT_X[szene.geldflug.zu];
      // Geld-Fluss-Pfeil (W4): gezeichnete Flugbahn unter den Scheinen —
      // macht die Transfer-Richtung („wessen Geld wandert wohin?") explizit.
      const pfeil = document.createElement("span");
      pfeil.className = `ed-geldpfeil ${zuX < vonX ? "nach-links" : ""}`;
      pfeil.style.setProperty("--von-x", `${Math.min(vonX, zuX)}%`);
      pfeil.style.setProperty("--breite", `${Math.abs(zuX - vonX)}%`);
      kinder.push(pfeil);
      for (let i = 0; i < 3; i++) {
        const s = document.createElement("span");
        s.className = "ed-schein";
        s.textContent = "💵";
        s.style.setProperty("--von-x", `${vonX}%`);
        s.style.setProperty("--zu-x", `${zuX}%`);
        s.style.setProperty("--i", String(i));
        kinder.push(s);
      }
    }
    fxLayer.replaceChildren(...kinder);
    buehne.classList.toggle("wackelt", szene.effekt === "explosion");
  }

  if (takt.sound) fx.sound(takt.sound);
}

function montiere(host: HTMLElement, key: string, choreo: DemoChoreo, fx: FxApi): void {
  // key = "<minigameId>:<endetAt>" (cutscenes.ts) — Kernregel per Format.
  render(skelettTpl(kernregelFuer(key.split(":")[0])), host);
  fuellePuppen(host);
  const spieler = createDemoSpieler(choreo);
  let start: number | null = null;
  const schritt = (ts: number): void => {
    if (!host.isConnected || aktiv?.key !== key) {
      // Karte weg (Skip/Phasenwechsel/Tutorial-Video) ⇒ komplett abräumen.
      if (aktiv?.key === key) stoppeAktive();
      else spieler.stop();
      return;
    }
    if (start === null) start = ts;
    const takt = spieler.tick(ts - start);
    if (takt?.neuerBeat) wendeSzeneAn(host, takt, fx);
    aktiv.raf = requestAnimationFrame(schritt);
  };
  aktiv = { key, host, raf: requestAnimationFrame(schritt), stop: () => spieler.stop() };
}

function sorgeFuerDemo(key: string, choreo: DemoChoreo, fx: FxApi): void {
  const host = document.querySelector<HTMLElement>(`[data-demo-key="${key}"]`);
  if (!host) return; // Karte schon wieder weg — nichts zu montieren
  if (aktiv && aktiv.key === key && aktiv.host === host) return; // läuft schon
  stoppeAktive();
  montiere(host, key, choreo, fx);
}

/**
 * Demo-Slot für die Erklärkarte: liefert den (über Re-Renders persistenten)
 * Host und sorgt nach dem Render fürs Montieren/Weiterlaufen — idempotent,
 * die App darf beliebig oft neu zeichnen (120-ms-Live-Tick).
 */
export function demoBuehne(key: string, choreo: DemoChoreo, fx: FxApi): TemplateResult {
  queueMicrotask(() => sorgeFuerDemo(key, choreo, fx));
  return html`<div class="ed-slot" data-demo-key=${key}></div>`;
}
