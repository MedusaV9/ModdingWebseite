// Session-Token im localStorage unter mm:<roomCode> (TECH-SPEC §3.1, welcome).
export function speichereToken(roomCode: string, token: string): void {
  try {
    localStorage.setItem(`mm:${roomCode}`, token);
  } catch {
    /* Private-Mode-Safari o. Ä. — Reconnect klappt dann nur per Neu-Join */
  }
}

export function ladeToken(roomCode: string): string | null {
  try {
    return localStorage.getItem(`mm:${roomCode}`);
  } catch {
    return null;
  }
}

export function loescheToken(roomCode: string): void {
  try {
    localStorage.removeItem(`mm:${roomCode}`);
  } catch {
    /* egal */
  }
}

/** Raum-Code aus URL ziehen: /j/AFFE, /join/AFFE oder ?code=AFFE. */
export function codeAusUrl(): string | null {
  const pfad = window.location.pathname.match(/^\/(?:j|join)\/([A-Za-z]{4})$/);
  if (pfad) return pfad[1].toUpperCase();
  const query = new URLSearchParams(window.location.search).get("code");
  return query ? query.toUpperCase() : null;
}
