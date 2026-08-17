// pageerror-Telemetrie (Playtest-Wunsch): window.onerror + unhandledrejection
// → POST /api/fehler mit {msg, stack (gekürzt), phase, minigameId, url, ts}.
// Serverseite: server/core/fehler-telemetrie.ts (JSONL data/fehler.log,
// Rate-Limit 10/min/IP); die Admin-Seite (/admin) zeigt die letzten 20.
//
// Grundsätze: Telemetrie darf NIE selbst crashen und NIE fluten — deshalb
// (1) alles abwehrend gekapselt, (2) Client-Kappe MAX_MELDUNGEN pro
// Seiten-Lauf + Dedupe identischer Folge-Meldungen, (3) fetch-Fehler werden
// verschluckt (Standalone-Relay kennt den Endpoint nicht — egal).
// Verkabelung: socket.ts installiert das Modul beim Import und füttert den
// Match-Kontext (phase/minigameId) aus jedem Snapshot — Fehler-Reports sind
// damit der Spiel-Situation zuordenbar.

/** Wire-Format einer Fehler-Meldung (Server validiert nochmal strikt). */
export interface FehlerMeldung {
  msg: string;
  stack: string | null;
  phase: string | null;
  minigameId: string | null;
  url: string;
  ts: number;
}

export const FEHLER_MSG_MAX = 300;
export const FEHLER_STACK_MAX = 1_200;
/** Client-Kappe: mehr Meldungen pro Seiten-Lauf wären ein Fehler-Sturm. */
export const FEHLER_MAX_MELDUNGEN = 10;

let kontext: { phase: string | null; minigameId: string | null } = {
  phase: null,
  minigameId: null,
};
let installiert = false;
let gesendet = 0;
let letzteMsg = "";

/** Match-Kontext aus einem Server-View ziehen (defensiv — jede Rolle passt:
 * ViewBase trägt phase + abschnitt.minigameId, alles andere bleibt null). */
export function merkeFehlerKontext(view: unknown): void {
  const v = view as {
    phase?: unknown;
    abschnitt?: { minigameId?: unknown } | null;
  } | null;
  kontext = {
    phase: typeof v?.phase === "string" ? v.phase : null,
    minigameId: typeof v?.abschnitt?.minigameId === "string" ? v.abschnitt.minigameId : null,
  };
}

/** Meldung bauen: Längen kappen (Wire-Hygiene) + Kontext anreichern. Pure —
 * der vitest-Wächter läuft damit ohne DOM. */
export function baueFehlerMeldung(
  msg: unknown,
  stack: unknown,
  opts: { url: string; ts: number },
): FehlerMeldung {
  return {
    msg: String(msg ?? "unbekannter-fehler").slice(0, FEHLER_MSG_MAX),
    stack: typeof stack === "string" && stack.length > 0 ? stack.slice(0, FEHLER_STACK_MAX) : null,
    phase: kontext.phase,
    minigameId: kontext.minigameId,
    url: opts.url,
    ts: opts.ts,
  };
}

/** Kappe + Dedupe: senden wir diese Meldung noch? (mutiert die Zähler) */
export function darfSenden(msg: string): boolean {
  if (gesendet >= FEHLER_MAX_MELDUNGEN) return false;
  if (msg === letzteMsg) return false; // identische Folge-Meldung (Render-Loop)
  gesendet += 1;
  letzteMsg = msg;
  return true;
}

/** Nur für Tests: Zähler/Kontext auf den Frisch-Zustand zurücksetzen. */
export function resetFehlerTelemetrie(): void {
  kontext = { phase: null, minigameId: null };
  gesendet = 0;
  letzteMsg = "";
}

function sendeStandard(meldung: FehlerMeldung): void {
  try {
    void fetch("/api/fehler", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(meldung),
      // keepalive: Meldung überlebt auch ein sofortiges Navigieren/Schließen.
      keepalive: true,
    }).catch(() => undefined);
  } catch {
    /* Telemetrie crasht nie — auch nicht ohne fetch (Uralt-Browser) */
  }
}

/** window-Listener anhängen (idempotent; no-op außerhalb des Browsers). */
export function installiereFehlerTelemetrie(
  sende: (meldung: FehlerMeldung) => void = sendeStandard,
): void {
  if (installiert || typeof window === "undefined") return;
  installiert = true;

  const melde = (msg: unknown, stack: unknown): void => {
    try {
      const meldung = baueFehlerMeldung(msg, stack, {
        url: window.location.pathname + window.location.search,
        // Zeitstempel ist Telemetrie-Infrastruktur, kein Spiel-Determinismus.
        // eslint-disable-next-line no-restricted-properties
        ts: Date.now(),
      });
      if (darfSenden(meldung.msg)) sende(meldung);
    } catch {
      /* nie crashen */
    }
  };

  window.addEventListener("error", (event) => {
    melde(event.message, (event.error as { stack?: unknown } | null)?.stack);
  });
  window.addEventListener("unhandledrejection", (event) => {
    const grund = event.reason as { message?: unknown; stack?: unknown } | null;
    melde(grund?.message ?? grund, grund?.stack);
  });
}
