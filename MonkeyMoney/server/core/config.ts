// Env-Konfiguration — AMP-Realität: PORT und DATA_DIR kommen strikt aus der Env.
export interface Config {
  port: number;
  dataDir: string;
  maxRooms: number;
  tickMs: number;
  fragenProMatch: number;
  /** META: Admin-Dashboard-PIN — ohne Env-Wert ist /admin deaktiviert. */
  adminPin: string | null;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  return {
    port: Number(env.PORT ?? 8080),
    dataDir: env.DATA_DIR ?? "data",
    maxRooms: Number(env.MAX_ROOMS ?? 20),
    tickMs: Number(env.TICK_MS ?? 250),
    fragenProMatch: Number(env.FRAGEN_PRO_MATCH ?? 3),
    adminPin: env.ADMIN_PIN && env.ADMIN_PIN.length > 0 ? env.ADMIN_PIN : null,
  };
}
