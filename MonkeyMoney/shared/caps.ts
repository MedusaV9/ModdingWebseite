// Capability-Schicht (TECH-SPEC §4): einmal beim Start prüfen, Flags liefern.
// Nichts Secure-Context-Abhängiges wird je hart vorausgesetzt — UI passt sich an.
export interface Caps {
  secureContext: boolean; // http://<lan-ip> = false → „LAN-Modus"-Badge
  wakeLock: boolean;
  clipboard: boolean;
  vibrate: boolean;
  share: boolean;
  touch: boolean;
  /** <video>-Wiedergabe möglich (Stinger/Tutorials) — HTTP-Autoplay bleibt
   * trotzdem best-effort: Aufrufer brauchen einen Nicht-Video-Fallback. */
  video: boolean;
}

export function detectCaps(): Caps {
  const nav = typeof navigator !== "undefined" ? navigator : undefined;
  const secure = typeof window !== "undefined" && window.isSecureContext === true;
  return {
    secureContext: secure,
    wakeLock: secure && !!nav && "wakeLock" in nav,
    clipboard: secure && !!nav && "clipboard" in nav,
    vibrate: !!nav && "vibrate" in nav,
    share: !!nav && "share" in nav,
    touch: !!nav && (nav.maxTouchPoints ?? 0) > 0,
    video: kannVideo(),
  };
}

/** MP4 (H.264) ODER WebM (VP9) abspielbar? — SSR-/Test-sicher (false ohne DOM). */
function kannVideo(): boolean {
  if (typeof document === "undefined") return false;
  try {
    const v = document.createElement("video");
    if (typeof v.canPlayType !== "function") return false;
    return (
      v.canPlayType('video/mp4; codecs="avc1.42E01E"') !== "" ||
      v.canPlayType('video/webm; codecs="vp9"') !== ""
    );
  } catch {
    return false;
  }
}

/** Geräte-Klasse für die Landing-Heuristik (TECH-SPEC §7.1). */
export type Geraet = "phone" | "ipad" | "desktop";

export function detectGeraet(): Geraet {
  if (typeof navigator === "undefined") return "desktop";
  const touchPoints = navigator.maxTouchPoints ?? 0;
  // iPad-Falle: iPadOS meldet macOS → MacIntel + Multi-Touch ⇒ iPad.
  if (navigator.platform === "MacIntel" && touchPoints > 1) return "ipad";
  if (/iPad/i.test(navigator.userAgent)) return "ipad";
  if (touchPoints > 0 && Math.min(screen.width, screen.height) < 500) return "phone";
  if (/iPhone|Android.*Mobile/i.test(navigator.userAgent)) return "phone";
  return "desktop";
}
