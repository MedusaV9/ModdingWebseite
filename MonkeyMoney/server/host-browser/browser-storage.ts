// Browser-Persistenz für den Standalone-Modus: implementiert das Storage-
// Interface aus persistence/storage.ts auf IndexedDB — Room-Event-Log,
// meta/rooms.json und künftige Save-Slots/Profile landen damit auf dem iPad
// selbst (überleben App-Neustarts, solange iOS den WKWebView-Datastore behält).
//
// Abbildung Dateisystem → IndexedDB:
//   writeJsonAtomic/readJson → Objekt-Store "json" (key = relPath). IndexedDB-
//     Transaktionen sind atomar — das tmp→fsync→rename-Ballett entfällt.
//   appendLine/readText      → Objekt-Store "zeilen" (key = relPath, value =
//     string[]). Append-only-Logs (JSONL) laufen als RING-PUFFER: ab
//     maxLogZeilen fliegen die ältesten Zeilen raus (iPad-Speicher ist endlich,
//     und Analytics braucht ohnehin nur die jüngere Historie).
//   listeDateien             → Key-Scan mit Verzeichnis-Präfix.
//
// KEIN localStorage als Primärpfad (5-MB-Limit, synchron, iOS räumt es
// aggressiver) — aber createMemoryStorage() unten dient als Fallback, falls
// IndexedDB nicht öffnet (Lockdown-Mode o. Ä.): das Match läuft dann trotzdem,
// nur ohne Neustart-Persistenz.
import type { Storage } from "../persistence/storage";

const JSON_STORE = "json";
const ZEILEN_STORE = "zeilen";

export interface BrowserStorageOptions {
  dbName?: string;
  /** Ring-Puffer-Obergrenze pro Log-Datei (älteste Zeilen fliegen zuerst). */
  maxLogZeilen?: number;
}

/** IDBRequest → Promise (IndexedDB ist Callback-Steinzeit). */
function warteAuf<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("IndexedDB-Fehler"));
  });
}

function oeffneDb(dbName: string): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(JSON_STORE)) db.createObjectStore(JSON_STORE);
      if (!db.objectStoreNames.contains(ZEILEN_STORE)) db.createObjectStore(ZEILEN_STORE);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("IndexedDB öffnet nicht"));
  });
}

/** Direkte Kinder (Datei-Namen) eines "Verzeichnisses" aus einer Key-Liste. */
export function direkteKinder(keys: string[], relDir: string): string[] {
  const praefix = relDir.endsWith("/") ? relDir : `${relDir}/`;
  const kinder = new Set<string>();
  for (const key of keys) {
    if (!key.startsWith(praefix)) continue;
    const rest = key.slice(praefix.length);
    // Nur direkte Kinder — wie fs.readdir ohne recursive. Tiefere Pfade
    // erscheinen als ihr erstes Segment (Verzeichnis-Name), einmalig.
    kinder.add(rest.includes("/") ? rest.slice(0, rest.indexOf("/")) : rest);
  }
  return [...kinder].sort();
}

export async function createBrowserStorage(opts: BrowserStorageOptions = {}): Promise<Storage> {
  const dbName = opts.dbName ?? "monkey-money-standalone";
  const maxLogZeilen = opts.maxLogZeilen ?? 5000;
  const db = await oeffneDb(dbName);

  function store(name: string, modus: IDBTransactionMode): IDBObjectStore {
    return db.transaction(name, modus).objectStore(name);
  }

  return {
    resolve: (relPath: string) => `idb://${dbName}/${relPath}`,

    async readJson<T>(relPath: string): Promise<T | null> {
      const wert = await warteAuf(store(JSON_STORE, "readonly").get(relPath));
      return wert === undefined ? null : (wert as T);
    },

    async writeJsonAtomic(relPath: string, data: unknown): Promise<void> {
      // JSON-Roundtrip statt Rohobjekt: exakt die Datei-Semantik (keine Maps,
      // keine Funktionen, keine geteilten Referenzen mit dem Aufrufer).
      const kopie = JSON.parse(JSON.stringify(data ?? null)) as unknown;
      await warteAuf(store(JSON_STORE, "readwrite").put(kopie, relPath));
    },

    async appendLine(relPath: string, line: string): Promise<void> {
      // Read-Modify-Write in EINER Transaktion (atomar; parallele Appends
      // serialisiert IndexedDB über die Transaktions-Queue).
      const tx = db.transaction(ZEILEN_STORE, "readwrite");
      const s = tx.objectStore(ZEILEN_STORE);
      const vorhanden = ((await warteAuf(s.get(relPath))) as string[] | undefined) ?? [];
      vorhanden.push(line.endsWith("\n") ? line.slice(0, -1) : line);
      // Ring-Puffer: die ältesten Zeilen fliegen, sobald das Limit reißt.
      const geschnitten =
        vorhanden.length > maxLogZeilen
          ? vorhanden.slice(vorhanden.length - maxLogZeilen)
          : vorhanden;
      await warteAuf(s.put(geschnitten, relPath));
    },

    async readText(relPath: string): Promise<string | null> {
      const zeilen = (await warteAuf(store(ZEILEN_STORE, "readonly").get(relPath))) as
        string[] | undefined;
      if (zeilen !== undefined) return zeilen.map((z) => `${z}\n`).join("");
      // Fallback: JSON-Dokumente sind auch als Text lesbar (Datei-Semantik).
      const json = await warteAuf(store(JSON_STORE, "readonly").get(relPath));
      return json === undefined ? null : JSON.stringify(json, null, 2);
    },

    async listeDateien(relDir: string): Promise<string[]> {
      const jsonKeys = (await warteAuf(store(JSON_STORE, "readonly").getAllKeys())) as string[];
      const zeilenKeys = (await warteAuf(store(ZEILEN_STORE, "readonly").getAllKeys())) as string[];
      return direkteKinder([...jsonKeys, ...zeilenKeys], relDir);
    },

    async loesche(relPath: string): Promise<void> {
      await warteAuf(store(JSON_STORE, "readwrite").delete(relPath));
      await warteAuf(store(ZEILEN_STORE, "readwrite").delete(relPath));
    },
  };
}

/** In-Memory-Fallback (IndexedDB kaputt/gesperrt): Match läuft, nichts überlebt. */
export function createMemoryStorage(opts: { maxLogZeilen?: number } = {}): Storage {
  const maxLogZeilen = opts.maxLogZeilen ?? 5000;
  const json = new Map<string, unknown>();
  const zeilen = new Map<string, string[]>();
  return {
    resolve: (relPath: string) => `memory://${relPath}`,
    async readJson<T>(relPath: string): Promise<T | null> {
      return json.has(relPath) ? (json.get(relPath) as T) : null;
    },
    async writeJsonAtomic(relPath: string, data: unknown): Promise<void> {
      json.set(relPath, JSON.parse(JSON.stringify(data ?? null)));
    },
    async appendLine(relPath: string, line: string): Promise<void> {
      const liste = zeilen.get(relPath) ?? [];
      liste.push(line.endsWith("\n") ? line.slice(0, -1) : line);
      if (liste.length > maxLogZeilen) liste.splice(0, liste.length - maxLogZeilen);
      zeilen.set(relPath, liste);
    },
    async readText(relPath: string): Promise<string | null> {
      const liste = zeilen.get(relPath);
      if (liste !== undefined) return liste.map((z) => `${z}\n`).join("");
      return json.has(relPath) ? JSON.stringify(json.get(relPath), null, 2) : null;
    },
    async listeDateien(relDir: string): Promise<string[]> {
      return direkteKinder([...json.keys(), ...zeilen.keys()], relDir);
    },
    async loesche(relPath: string): Promise<void> {
      json.delete(relPath);
      zeilen.delete(relPath);
    },
  };
}
