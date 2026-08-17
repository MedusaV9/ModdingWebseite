// Session-Restore: Token ↔ Slot — der Kern des fachlichen Reconnects.
import { describe, expect, it } from "vitest";
import { createSessionStore } from "./sessions";

describe("rooms: Sessions", () => {
  it("stellt Rolle + Spieler-Slot über den Token wieder her", () => {
    const store = createSessionStore();
    const session = store.erstelle("player", "p_1234");
    const restored = store.restore(session.token);
    expect(restored).not.toBeNull();
    expect(restored!.role).toBe("player");
    expect(restored!.playerId).toBe("p_1234");
  });

  it("liefert null für unbekannte Tokens", () => {
    const store = createSessionStore();
    store.erstelle("player", "p_1234");
    expect(store.restore("gibts-nicht")).toBeNull();
  });

  it("unterscheidet GM-Sessions (ohne Spieler-Slot)", () => {
    const store = createSessionStore();
    const gm = store.erstelle("gm", null);
    expect(store.restore(gm.token)!.role).toBe("gm");
    expect(store.restore(gm.token)!.playerId).toBeNull();
  });

  it("vergibt eindeutige Tokens (injizierbare Factory)", () => {
    let n = 0;
    const store = createSessionStore(() => `tok-${n++}`);
    const a = store.erstelle("player", "p_a");
    const b = store.erstelle("player", "p_b");
    expect(a.token).not.toBe(b.token);
    expect(store.restore("tok-1")!.playerId).toBe("p_b");
  });
});
