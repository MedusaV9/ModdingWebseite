// Wächter: pageerror-Telemetrie (Client-Seite) — Meldungs-Bau (Kürzung +
// Kontext aus Snapshots) und die Flut-Kappe (10/Seiten-Lauf + Dedupe).
// Reine Logik, läuft im Node-Env (installiereFehlerTelemetrie ist dort no-op).
import { beforeEach, describe, expect, it } from "vitest";
import {
  FEHLER_MAX_MELDUNGEN,
  FEHLER_MSG_MAX,
  FEHLER_STACK_MAX,
  baueFehlerMeldung,
  darfSenden,
  installiereFehlerTelemetrie,
  merkeFehlerKontext,
  resetFehlerTelemetrie,
} from "./fehler-telemetrie";

describe("fehler-telemetrie (Client)", () => {
  beforeEach(() => resetFehlerTelemetrie());

  it("baut die Meldung mit gekürztem msg/stack und Snapshot-Kontext", () => {
    merkeFehlerKontext({ phase: "frage", abschnitt: { minigameId: "vier-lianen" } });
    const m = baueFehlerMeldung("x".repeat(1_000), "s".repeat(5_000), {
      url: "/j/AFFE?standalone=1",
      ts: 123,
    });
    expect(m.msg).toHaveLength(FEHLER_MSG_MAX);
    expect(m.stack).toHaveLength(FEHLER_STACK_MAX);
    expect(m.phase).toBe("frage");
    expect(m.minigameId).toBe("vier-lianen");
    expect(m.url).toBe("/j/AFFE?standalone=1");
    expect(m.ts).toBe(123);
  });

  it("übersteht kaputte Views/Fehler-Objekte (Kontext defensiv, msg-Fallback)", () => {
    merkeFehlerKontext(null);
    merkeFehlerKontext({ phase: 7, abschnitt: "quatsch" });
    const m = baueFehlerMeldung(undefined, 42, { url: "/", ts: 1 });
    expect(m.msg).toBe("unbekannter-fehler");
    expect(m.stack).toBeNull();
    expect(m.phase).toBeNull();
    expect(m.minigameId).toBeNull();
  });

  it("Flut-Kappe: identische Folge-Meldung dedupet, max. 10 pro Seiten-Lauf", () => {
    expect(darfSenden("boom")).toBe(true);
    expect(darfSenden("boom")).toBe(false); // Render-Loop-Dedupe
    expect(darfSenden("anders")).toBe(true);
    let gesendet = 2;
    for (let i = 0; i < 30; i++) {
      if (darfSenden(`fehler-${i}`)) gesendet += 1;
    }
    expect(gesendet).toBe(FEHLER_MAX_MELDUNGEN);
    expect(darfSenden("noch-einer")).toBe(false);
  });

  it("installieren ist außerhalb des Browsers ein no-op (kein Crash im Node-Env)", () => {
    expect(() => installiereFehlerTelemetrie(() => undefined)).not.toThrow();
  });
});
