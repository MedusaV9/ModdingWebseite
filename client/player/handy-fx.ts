// Handy-FX-Schicht (NUR Player): Count-up-Zähler für Money-Momente, zufällige
// Idle-Einlagen des eigenen Mini-Affen in Warte-Screens und Slider-Feedback
// (Haptik-Ticks + magnetische Snap-Punkte des Wett-Sliders).
// Die reinen Rechenhelfer (zaehlerWert, snapWert) sind bewusst DOM-frei und
// werden in handy-fx.test.ts abgedeckt. Zufall ist rein kosmetisch und kommt
// wie beim Affentheater (alles-oder-banane) aus Web-Crypto, nicht Math.random.
import { formatMM } from "../../shared/money";

/** prefers-reduced-motion: alle FX degradieren zu Sofort-Endzustand. */
export function reduzierteBewegung(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** Kosmetischer Zufall 0..1 (Rng-Regel: Web-Crypto statt Math.random). */
function zufall01(): number {
  return crypto.getRandomValues(new Uint32Array(1))[0] / 0xffffffff;
}

// ---------- Count-up: Money-Zahlen zählen HOCH statt hart zu erscheinen ----------

/** Zwischenwert eines Count-ups bei Fortschritt 0..1 (ease-out, Integer-MM). */
export function zaehlerWert(fortschritt: number, von: number, ziel: number): number {
  const t = Math.min(1, Math.max(0, fortschritt));
  const eased = 1 - (1 - t) * (1 - t) * (1 - t); // cubic ease-out: schnell los, weich rein
  return Math.round(von + (ziel - von) * eased);
}

const ZAEHL_DAUER_MS = 600;

/**
 * Alle [data-zaehl-ziel]-Spans unter root befüllen und einmalig hochzählen.
 * lit-html bindet nur die Attribute (kein Text-Binding!) — der Textinhalt
 * gehört dieser Funktion, damit kein lit-Text-Node zerstört wird.
 * data-zaehl-key verhindert Restarts bei Re-Renders derselben Auflösung.
 */
export function fuelleZaehler(root: ParentNode): void {
  for (const el of root.querySelectorAll<HTMLElement>("[data-zaehl-ziel]")) {
    const ziel = Number(el.dataset.zaehlZiel ?? "0");
    const key = el.dataset.zaehlKey ?? String(ziel);
    if (el.dataset.zaehlAktiv === key) continue;
    el.dataset.zaehlAktiv = key;
    const vorzeichen = ziel >= 0 ? "+" : "";
    if (reduzierteBewegung()) {
      el.textContent = `${vorzeichen}${formatMM(ziel)}`;
      continue;
    }
    el.textContent = `${vorzeichen}${formatMM(0)}`;
    const start = performance.now();
    const tick = (jetzt: number): void => {
      if (el.dataset.zaehlAktiv !== key) return; // neue Auflösung übernimmt
      const t = (jetzt - start) / ZAEHL_DAUER_MS;
      el.textContent = `${vorzeichen}${formatMM(zaehlerWert(t, 0, ziel))}`;
      if (t < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }
}

/**
 * Kopfzeilen-Konto: [data-konto-ziel] tick-animiert von zuletzt gezeigtem Wert
 * zum neuen Stand (600 ms) + Flash-Klasse (hoch = gold, runter = rot).
 */
export function fuelleKonto(root: ParentNode): void {
  for (const el of root.querySelectorAll<HTMLElement>("[data-konto-ziel]")) {
    const ziel = Number(el.dataset.kontoZiel ?? "0");
    const gezeigt = el.dataset.kontoStand;
    if (gezeigt === undefined || reduzierteBewegung()) {
      // Erstes Rendern (oder Reduced Motion): sofort setzen, kein Ticken.
      el.dataset.kontoStand = String(ziel);
      el.textContent = formatMM(ziel);
      continue;
    }
    const von = Number(gezeigt);
    if (von === ziel) {
      // Idempotent: Text sicherstellen (z. B. nach Element-Recycling).
      if (el.textContent === "") el.textContent = formatMM(ziel);
      continue;
    }
    el.dataset.kontoStand = String(ziel);
    el.classList.remove("tickt-hoch", "tickt-runter");
    // Reflow erzwingen, damit die Flash-Animation neu startet.
    void el.offsetWidth;
    el.classList.add(ziel > von ? "tickt-hoch" : "tickt-runter");
    const start = performance.now();
    const tick = (jetzt: number): void => {
      if (el.dataset.kontoStand !== String(ziel)) return;
      const t = (jetzt - start) / ZAEHL_DAUER_MS;
      el.textContent = formatMM(zaehlerWert(t, von, ziel));
      if (t < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }
}

// ---------- Idle-Einlagen: der eigene Affe gähnt / wippt / schaut sich um ----------

const IDLE_EINLAGEN = ["gaehnt", "wippt", "schaut"] as const;
const EINLAGE_MS = 1700;
let idleLaeuft = false;

/**
 * Startet die Idle-Choreo (einmalig): alle 4–8 s bekommt der eigene Mini-Affe
 * in Warte-Screens (.eigene-puppe) eine zufällige One-Shot-Einlage.
 * Gähnen wechselt kurz das Gesicht (Augen zu) über slot.dataset.gesicht —
 * fuellePuppen() überträgt das auf das SVG, danach wird restauriert.
 */
export function starteIdleChoreo(root: HTMLElement, neuFuellen: () => void): void {
  if (idleLaeuft) return;
  idleLaeuft = true;
  const naechste = (): void => {
    window.setTimeout(
      () => {
        const puppe = root.querySelector<HTMLElement>(".eigene-puppe");
        if (puppe && !reduzierteBewegung()) {
          const art = IDLE_EINLAGEN[Math.floor(zufall01() * IDLE_EINLAGEN.length)];
          puppe.classList.add(`idle-${art}`);
          const gesichtVorher = puppe.dataset.gesicht;
          if (art === "gaehnt") {
            // „Augen zu"-Gesicht ≈ herzhaftes Gähnen (frust hat zugekniffene Augen).
            puppe.dataset.gesicht = "frust";
            neuFuellen();
          }
          window.setTimeout(() => {
            puppe.classList.remove(`idle-${art}`);
            if (art === "gaehnt" && puppe.isConnected) {
              if (gesichtVorher === undefined) delete puppe.dataset.gesicht;
              else puppe.dataset.gesicht = gesichtVorher;
              neuFuellen();
            }
          }, EINLAGE_MS);
        }
        naechste();
      },
      4000 + zufall01() * 4000,
    );
  };
  naechste();
}

// ---------- Slider-Feedback: Haptik-Ticks + Snap-Punkte (Wett-Slider) ----------

/**
 * Magnetischer Snap auf Viertel-Punkte (min / 25 % / 50 % / 75 % / max):
 * liegt wert näher als toleranz am NÄCHSTEN Punkt, rastet er dort ein (auf
 * step gerundet). Toleranz > step, damit auch Nachbar-Schritte angezogen
 * werden (sonst wäre der Magnet wirkungslos, weil Werte eh nur auf Steps
 * landen); „nächster Punkt gewinnt" hält Mini-Ranges stabil, wo sich die
 * Toleranzen der Viertel überlappen. Pure Funktion — testbar ohne DOM.
 */
export function snapWert(wert: number, min: number, max: number, step: number): number {
  const spanne = max - min;
  if (spanne <= 0 || step <= 0) return wert;
  const toleranz = Math.max(step * 1.2, spanne * 0.02);
  let bester = wert;
  let besteDistanz = Infinity;
  for (const anteil of [0, 0.25, 0.5, 0.75, 1]) {
    const roh = min + spanne * anteil;
    const punkt = Math.min(max, min + Math.round((roh - min) / step) * step);
    const distanz = Math.abs(wert - punkt);
    if (distanz <= toleranz && distanz < besteDistanz) {
      bester = punkt;
      besteDistanz = distanz;
    }
  }
  return bester;
}

let sliderFeedbackDran = false;
const sliderLetzterWert = new WeakMap<HTMLInputElement, number>();

/** Gold-Füllstand des Custom-Tracks (CSS-Var, s. alles-oder-banane.css). */
function setzeSliderFuellung(el: HTMLInputElement): void {
  const min = Number(el.min || 0);
  const max = Number(el.max || 100);
  const anteil = max > min ? ((Number(el.value) - min) / (max - min)) * 100 : 0;
  el.style.setProperty("--aob-fuellung", `${anteil}%`);
}

/**
 * Delegierter Capture-Listener (einmalig): jeder Range-Slider im Player tickt
 * haptisch (5 ms Vibration pro Wert-Schritt, wo Caps es erlauben); der
 * Wett-Slider (.aob-slider) bekommt zusätzlich magnetische Snap-Punkte —
 * aber NUR beim Finger-Ziehen (Pointer aktiv): Pfeiltasten bleiben präzise
 * schrittgenau (Tastatur-Zugänglichkeit). Capture-Phase ⇒ der Snap greift,
 * BEVOR der lit-Handler des Minigames den Wert liest — kein Eingriff in
 * Minigame-Code nötig.
 */
export function installiereSliderFeedback(root: HTMLElement, vibriere: (ms: number) => void): void {
  if (sliderFeedbackDran) return;
  sliderFeedbackDran = true;
  let zieht = false;
  const istSlider = (t: EventTarget | null): t is HTMLInputElement =>
    t instanceof HTMLInputElement && t.type === "range";
  root.addEventListener(
    "pointerdown",
    (e) => {
      if (istSlider(e.target)) zieht = true;
    },
    { capture: true },
  );
  for (const ende of ["pointerup", "pointercancel"] as const) {
    root.addEventListener(ende, () => (zieht = false), { capture: true });
  }
  root.addEventListener(
    "input",
    (e: Event) => {
      const el = e.target;
      if (!istSlider(el)) return;
      if (zieht && el.classList.contains("aob-slider")) {
        const gesnappt = snapWert(
          Number(el.value),
          Number(el.min || 0),
          Number(el.max || 100),
          Number(el.step || 1),
        );
        if (gesnappt !== Number(el.value)) el.value = String(gesnappt);
      }
      if (el.classList.contains("aob-slider")) setzeSliderFuellung(el);
      const wert = Number(el.value);
      const vorher = sliderLetzterWert.get(el);
      if (vorher !== undefined && wert !== vorher) vibriere(5);
      sliderLetzterWert.set(el, wert);
    },
    { capture: true },
  );
}
