// Loop-Schnitt-Wächter (Musik-Welle 3): import.mjs --bett läuft hier KOMPLETT
// gegen ein Temp-Verzeichnis (MM_MUSIK_DIR) mit einer synthetischen Quelle —
// kein Netz, kein Schreiben ins echte content/musik. Geprüft wird der ganze
// Vertrag: EIN Loop 60–90 s unter bett/<id>.ogg, −18 LUFS, nurBett-Eintrag
// OHNE Snippets, Credits-Zeile, Hook-Clamp bei zu kurzen Songs.
// Braucht ffmpeg/ffprobe (wie der Import selbst) — sonst sauberer Skip.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";

const IMPORT_MJS = join(__dirname, "import.mjs");

const ffmpegVerfuegbar = (() => {
  try {
    execFileSync("ffmpeg", ["-version"], { encoding: "utf8", stdio: "pipe" });
    execFileSync("ffprobe", ["-version"], { encoding: "utf8", stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
})();

const tmp = mkdtempSync(join(tmpdir(), "mm-bett-test-"));
afterAll(() => rmSync(tmp, { recursive: true, force: true }));

/** Synthetische Quelle: Sinus-„Song" gegebener Länge (kein Download nötig). */
function synthQuelle(name: string, sekunden: number): string {
  const datei = join(tmp, name);
  execFileSync(
    "ffmpeg",
    ["-hide_banner", "-y", "-f", "lavfi", "-i", `sine=frequency=440:duration=${sekunden}`, datei],
    { encoding: "utf8", stdio: "pipe" },
  );
  return datei;
}

function ffprobeDauer(datei: string): number {
  return Number(
    execFileSync(
      "ffprobe",
      ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", datei],
      { encoding: "utf8" },
    ).trim(),
  );
}

/** import.mjs --bett gegen ein eigenes MM_MUSIK_DIR laufen lassen. */
function importiere(musikDir: string, extraArgs: string[]): { status: number; stdout: string } {
  const r = spawnSync("node", [IMPORT_MJS, "--bett", ...extraArgs], {
    encoding: "utf8",
    env: { ...process.env, MM_MUSIK_DIR: musikDir },
  });
  return { status: r.status ?? -1, stdout: `${r.stdout}\n${r.stderr}` };
}

describe.skipIf(!ffmpegVerfuegbar)("import.mjs --bett: der 60–90-s-Loop-Schnitt", () => {
  it("schneidet EINEN Loop (−18 LUFS, Fades) + nurBett-Eintrag OHNE Snippets", () => {
    const musikDir = join(tmp, "musik-a");
    const quelle = synthQuelle("song120.wav", 120);
    const r = importiere(musikDir, [
      "--datei",
      quelle,
      "--titel",
      "Loop Test",
      "--artist",
      "Testfall",
      "--jahr",
      "2020",
      "--stimmung",
      "upbeat",
      "--hook",
      "10",
      "--laenge",
      "60",
    ]);
    expect(r.status, r.stdout).toBe(0);

    // 1) EIN Loop unter bett/<id>.ogg — Länge exakt im Fenster.
    const loop = join(musikDir, "bett", "s_bett_loop_test.ogg");
    expect(existsSync(loop)).toBe(true);
    expect(ffprobeDauer(loop)).toBeGreaterThan(58.5);
    expect(ffprobeDauer(loop)).toBeLessThan(61.5);
    // KEIN Snippet-Ordner (media/<id>/) — Bett-Songs raten nicht mit.
    expect(existsSync(join(musikDir, "media", "s_bett_loop_test"))).toBe(false);

    // 2) Loudness-Beleg aus der Beweis-Ausgabe: −18 LUFS (Hintergrund).
    const lufs = Number(r.stdout.match(/Loop-Loudness: (-?[\d.]+) LUFS/)?.[1]);
    expect(lufs).toBeGreaterThan(-21);
    expect(lufs).toBeLessThan(-15);

    // 3) songs.json: nurBett:true + stimmung + medien.bett — sonst nichts.
    const katalog = JSON.parse(readFileSync(join(musikDir, "songs.json"), "utf8")) as {
      songs: Record<string, unknown>[];
    };
    const eintrag = katalog.songs.find((s) => s.id === "s_bett_loop_test");
    expect(eintrag).toMatchObject({
      nurBett: true,
      stimmung: "upbeat",
      titel: "Loop Test",
      medien: { bett: "bett/s_bett_loop_test.ogg" },
    });
    expect((eintrag?.medien as Record<string, unknown>).intro5s).toBeUndefined();
    expect((eintrag?.medien as Record<string, unknown>).buzz).toBeUndefined();

    // 4) Credits-Zeile (Pflicht) mit Bett-Loop-Hinweis.
    const credits = readFileSync(join(musikDir, "CREDITS-SONGS.md"), "utf8");
    expect(credits).toContain("| s_bett_loop_test | Loop Test | Testfall | 2020 |");
    expect(credits).toContain("Bett-Loop 60 s (upbeat)");
  }, 120_000);

  it("Hook-Clamp: zu kurzer Song schrumpft Loop + zieht den Hook nach vorn", () => {
    const musikDir = join(tmp, "musik-b");
    const quelle = synthQuelle("song70.wav", 70);
    const r = importiere(musikDir, [
      "--datei",
      quelle,
      "--titel",
      "Kurzer Song",
      "--artist",
      "Testfall",
      "--jahr",
      "2021",
      "--hook",
      "40", // passt NICHT: 40 + 75 > 70 ⇒ Clamp auf Hook≈0, Loop≈69 s
    ]);
    expect(r.status, r.stdout).toBe(0);
    const loop = join(musikDir, "bett", "s_bett_kurzer_song.ogg");
    const dauer = ffprobeDauer(loop);
    expect(dauer).toBeGreaterThan(60); // immer noch im Bett-Fenster
    expect(dauer).toBeLessThan(70);
    expect(r.stdout).toContain("HINWEIS"); // beide Clamps melden sich
  }, 120_000);

  it("Song unter 60 s wird abgelehnt (kein Mini-Loop-Gestottere)", () => {
    const musikDir = join(tmp, "musik-c");
    const quelle = synthQuelle("song30.wav", 30);
    const r = importiere(musikDir, [
      "--datei",
      quelle,
      "--titel",
      "Zu Kurz",
      "--artist",
      "Testfall",
      "--jahr",
      "2022",
    ]);
    expect(r.status).not.toBe(0);
    expect(r.stdout).toContain("Bett-Loop braucht");
  }, 60_000);
});
