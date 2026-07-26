// Konfiguration: ENV > Defaults. Pure Funktion (testbar mit beliebigem env-Objekt).
// AMP "Node.js App Runner" setzt ENV am bequemsten — keine config-Datei nötig.

const int = (v, def) => {
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) && n >= 0 ? n : def;
};

export function loadConfig(env = process.env) {
  const cfg = {
    port: int(env.PORT, 8080),
    // Pflicht fürs Panel. Fehlt sie, ist /panel hart deaktiviert (503, fail-closed).
    adminPassword: env.GOOBY_ADMIN_PASSWORD || null,
    dataDir: env.DATA_DIR || env.GOOBY_DATA_DIR || './data',
    tz: env.GOOBY_TZ || 'Europe/Berlin',
    palDailyLimit: int(env.GOOBY_PAL_DAILY_LIMIT, 250),
    maxPhotoKb: int(env.GOOBY_MAX_PHOTO_KB, 512),
    heartbeatSec: int(env.GOOBY_HEARTBEAT_SEC, 20),
    boardRejoinMs: int(env.GOOBY_BOARD_REJOIN_MS, 120_000),
    // Ranch-MP (RW-6): Rejoin-Fenster analog Brettspiel; Fangen-Rundendauer;
    // Countdown zwischen MG_READY-Komplett und Startschuss (Doc §2.3: ≥ 3 s).
    rmpRejoinMs: int(env.GOOBY_RMP_REJOIN_MS, 120_000),
    rmpFangenMs: int(env.GOOBY_RMP_FANGEN_MS, 90_000),
    rmpCountdownMs: int(env.GOOBY_RMP_COUNTDOWN_MS, 4_000),
    // Limits (Doc C §7) — zentral, damit Tests sie referenzieren können.
    limits: {
      wsFrameBytes: 16 * 1024,
      roomBodyBytes: 8 * 1024,
      houseSnapshotBytes: 256 * 1024,
      analyticsBatchSessions: 200,
      nameLen: 24,
      presenceKindLen: 32,
      // Ranch-MP: Ranch-Metadaten (Ausbau/Pferde/Trophäen) + Ghost-Blob.
      ranchMetaBytes: 16 * 1024,
      ghostBytes: 32 * 1024,
      ghostsPerKurs: 64,
    },
  };
  if (!cfg.adminPassword) {
    // Lautes Warning laut Doc C §2.3 — aber kein Crash: Spiel-Features laufen ohne Panel.
    console.warn(
      '[gooby-server] WARNUNG: GOOBY_ADMIN_PASSWORD ist nicht gesetzt — ' +
        'das Webpanel (/panel) ist DEAKTIVIERT (503, fail-closed).'
    );
  }
  return cfg;
}

// dayKey in konfigurierter Zeitzone ("YYYY-MM-DD") — Basis für Pal-Tageslimit + Analytics-Tage.
export function dayKey(tsMs, tz) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(tsMs));
}

// Monats-Suffix für JSONL-Rotation ("YYYY-MM").
export function monthKey(tsMs, tz) {
  return dayKey(tsMs, tz).slice(0, 7);
}
