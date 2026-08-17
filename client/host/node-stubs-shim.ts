// Browser-Stubs für node:fs / node:path / node:url (vite.config-Aliase, NUR
// im Client-Build aktiv): Das Meta-Wiring (W4) bündelt server/meta/index.ts,
// das über analytics/reports.ts node:fs zieht — aber AUSSCHLIESSLICH für den
// Kategorie-Lücken-Report des Admin-Dashboards (zaehlePacks liest content/
// vom Datenträger). Im Standalone gibt es kein /admin und niemand ruft
// meta.reports() auf; existsSync → false lässt findeContentDir sauber null
// liefern, falls es doch je läuft (Lücken-Report dann leer statt Crash).
// Alles andere wirft laut — ein STILLER Fake wäre eine Falle.

const nieImBrowser = (name: string) => (): never => {
  throw new Error(`node-stubs-shim: ${name} gibt es im Browser-Server nicht`);
};

// ---------- node:fs (analytics/reports.ts) ----------
export const existsSync = (): boolean => false;
export const readdirSync = nieImBrowser("fs.readdirSync");
export const readFileSync = nieImBrowser("fs.readFileSync");
export const statSync = nieImBrowser("fs.statSync");

// ---------- node:path (analytics/reports.ts) ----------
export const join = (...teile: string[]): string => teile.join("/");
export const resolve = (...teile: string[]): string => teile.join("/");
export const dirname = (pfad: string): string => pfad.slice(0, pfad.lastIndexOf("/")) || "/";

// ---------- node:url (analytics/reports.ts) ----------
export const fileURLToPath = (url: string | URL): string => String(url);
