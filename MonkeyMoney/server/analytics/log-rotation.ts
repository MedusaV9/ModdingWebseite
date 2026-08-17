// Event-Log-Rotation light (Eval-7): data/events wächst sonst unbegrenzt.
// Beim Server-Boot fliegen Logs, die älter als 30 Tage sind — und wenn danach
// immer noch mehr als 500 Dateien liegen, zusätzlich die ältesten darüber.
// Node-only (fs/stat): wird NUR von server/core/index.ts importiert — der
// Browser-Host-Pfad (room.ts → event-log.ts) bleibt fs-frei.
import { promises as fs } from "node:fs";
import { join } from "node:path";

export interface LogRotationErgebnis {
  geloescht: number;
  behalten: number;
}

export const LOG_MAX_ALTER_MS = 30 * 24 * 60 * 60_000; // 30 Tage
export const LOG_MAX_DATEIEN = 500;

export async function raeumeEventLogsAuf(
  eventsDir: string,
  nowMs: number,
  opts: { maxAlterMs?: number; maxDateien?: number } = {},
): Promise<LogRotationErgebnis> {
  const maxAlterMs = opts.maxAlterMs ?? LOG_MAX_ALTER_MS;
  const maxDateien = opts.maxDateien ?? LOG_MAX_DATEIEN;
  let namen: string[];
  try {
    namen = await fs.readdir(eventsDir);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return { geloescht: 0, behalten: 0 };
    throw err;
  }
  const dateien: { name: string; mtime: number }[] = [];
  for (const name of namen) {
    if (!name.endsWith(".jsonl")) continue;
    try {
      const st = await fs.stat(join(eventsDir, name));
      if (st.isFile()) dateien.push({ name, mtime: st.mtimeMs });
    } catch {
      // Rennen mit parallelem Löschen — dann ist die Datei eben schon weg.
    }
  }
  dateien.sort((a, b) => a.mtime - b.mtime); // älteste zuerst
  const zuLoeschen = new Set<string>();
  for (const d of dateien) {
    if (nowMs - d.mtime > maxAlterMs) zuLoeschen.add(d.name);
  }
  const verbleibend = dateien.filter((d) => !zuLoeschen.has(d.name));
  for (let i = 0; i < verbleibend.length - maxDateien; i++) zuLoeschen.add(verbleibend[i].name);
  for (const name of zuLoeschen) {
    try {
      await fs.unlink(join(eventsDir, name));
    } catch {
      // idempotent: fehlende Datei ist ok
    }
  }
  return { geloescht: zuLoeschen.size, behalten: dateien.length - zuLoeschen.size };
}
