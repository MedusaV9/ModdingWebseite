// Storage-Interface + JSON-Atomic-Implementierung (TECH-SPEC §1.3/§5).
// Schreiben IMMER: write tmp → fsync → rename. Pfad via DATA_DIR-Env.
// Designierter Upgrade-Pfad: node:sqlite als zweiter Adapter — niemals node-gyp.
import { randomBytes } from "node:crypto";
import { promises as fs } from "node:fs";
import { dirname, join } from "node:path";

export interface Storage {
  /** JSON-Datei lesen; null wenn nicht vorhanden. */
  readJson<T>(relPath: string): Promise<T | null>;
  /** JSON-Datei atomar schreiben (tmp → fsync → rename). */
  writeJsonAtomic(relPath: string, data: unknown): Promise<void>;
  /** Zeile an JSONL-Datei anhängen (append-only Event-Log). */
  appendLine(relPath: string, line: string): Promise<void>;
  /** ADDITIV (Analytics): Textdatei komplett lesen; null wenn nicht vorhanden. */
  readText(relPath: string): Promise<string | null>;
  /** ADDITIV (Analytics): Dateinamen in einem Verzeichnis (leer wenn fehlt). */
  listeDateien(relDir: string): Promise<string[]>;
  /** ADDITIV (Autosave/Rotation): Datei löschen — fehlende Datei ist ok. */
  loesche(relPath: string): Promise<void>;
  /** Absoluten Pfad auflösen (für Diagnose/Tests). */
  resolve(relPath: string): string;
}

export function createFileStorage(dataDir: string): Storage {
  const abs = (relPath: string) => join(dataDir, relPath);

  async function ensureParent(pfad: string): Promise<void> {
    await fs.mkdir(dirname(pfad), { recursive: true });
  }

  // Eval-7-Befund (P2): Der tmp-Name war NUR pid-eindeutig — zwei parallele
  // Writes auf dieselbe Datei teilten sich dieselbe tmp-Datei, der zweite
  // rename flog mit ENOENT (live beobachtet an meta/rooms.json) und der
  // Inhalt war ein Interleaving-Roulette. Fix in zwei Schichten:
  //   1) tmp-Suffix eindeutig machen (pid + Zähler + Zufall),
  //   2) Writes pro ZIEL-Datei über eine Promise-Kette serialisieren
  //      (gleiches Muster wie der Event-Log/profile-store) — der letzte
  //      Aufrufer gewinnt, kein Write geht verloren, kein rename kollidiert.
  let tmpZaehler = 0;
  const writeKetten = new Map<string, Promise<void>>();

  async function schreibeAtomar(ziel: string, text: string): Promise<void> {
    await ensureParent(ziel);
    const eindeutig = `${process.pid}-${++tmpZaehler}-${randomBytes(3).toString("hex")}`;
    const tmp = `${ziel}.tmp-${eindeutig}`;
    const handle = await fs.open(tmp, "w");
    try {
      await handle.writeFile(text, "utf8");
      await handle.sync(); // fsync VOR dem rename — sonst ist atomar gelogen
    } finally {
      await handle.close();
    }
    await fs.rename(tmp, ziel);
  }

  return {
    resolve: abs,

    async readJson<T>(relPath: string): Promise<T | null> {
      try {
        const text = await fs.readFile(abs(relPath), "utf8");
        return JSON.parse(text) as T;
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
        throw err;
      }
    },

    writeJsonAtomic(relPath: string, data: unknown): Promise<void> {
      const ziel = abs(relPath);
      // JETZT serialisieren (nicht erst in der Kette) — der Aufrufer-Zustand
      // des Schreib-Moments gewinnt, egal wann die Kette dran ist.
      const text = JSON.stringify(data, null, 2);
      const vorgaenger = writeKetten.get(ziel) ?? Promise.resolve();
      const eigener = vorgaenger
        .catch(() => undefined) // Fehler des Vorgängers reißt NICHT die Kette
        .then(() => schreibeAtomar(ziel, text));
      writeKetten.set(ziel, eigener);
      // Kette aufräumen, sobald der letzte Write durch ist (kein Map-Leak).
      void eigener
        .catch(() => undefined)
        .then(() => {
          if (writeKetten.get(ziel) === eigener) writeKetten.delete(ziel);
        });
      return eigener;
    },

    async appendLine(relPath: string, line: string): Promise<void> {
      const ziel = abs(relPath);
      await ensureParent(ziel);
      await fs.appendFile(ziel, line.endsWith("\n") ? line : `${line}\n`, "utf8");
    },

    async readText(relPath: string): Promise<string | null> {
      try {
        return await fs.readFile(abs(relPath), "utf8");
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
        throw err;
      }
    },

    async listeDateien(relDir: string): Promise<string[]> {
      try {
        return (await fs.readdir(abs(relDir))).sort();
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
        throw err;
      }
    },

    async loesche(relPath: string): Promise<void> {
      try {
        await fs.unlink(abs(relPath));
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "ENOENT") return;
        throw err;
      }
    },
  };
}
