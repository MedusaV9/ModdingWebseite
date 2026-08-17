// Asset-Gate (ART-PLAN §4.4-Idee als Unit-Test): jedes Event-Mapping zeigt auf
// eine existierende Datei unter client/public/audio/**, die Standard-Buzzer-
// Familie ist vollständig und kollisionsfrei. Die tiefe Prüfung (ffprobe,
// Loudness) macht tools/audio/probe.mjs — hier nur das schnelle CI-Netz
// (plus Crowd-Dauer-Wächter: der braucht ffprobe, ubuntu-Runner haben es).
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MUSIK, SFX, STANDARD_BUZZER, standardBuzzer } from "../../client/shared/fx/sound-map";
import { SHOP_ITEMS } from "../../shared/meta";

const PUBLIC_AUDIO = join(__dirname, "..", "..", "client", "public", "audio");
const fsPfad = (webPfad: string): string => join(PUBLIC_AUDIO, webPfad.replace(/^\/audio\//, ""));

// GitHub-Runner haben ffprobe NICHT vorinstalliert (CI installiert ffmpeg im
// test-Job; falls das je fehlt, überspringen die Dauer-Wächter statt rot zu
// werden — die Existenz-/Familien-Gates oben laufen überall).
const ffprobeVerfuegbar = (() => {
  try {
    execFileSync("ffprobe", ["-version"], { encoding: "utf8", stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
})();

describe("sound-map: Dateien existieren", () => {
  it("jede SFX-Datei liegt unter client/public/audio", () => {
    const fehlend: string[] = [];
    for (const def of Object.values(SFX)) {
      for (const d of def.dateien) if (!existsSync(fsPfad(d))) fehlend.push(d);
    }
    expect(fehlend).toEqual([]);
  });

  it("jede Musik-Ebene liegt unter client/public/audio", () => {
    for (const d of Object.values(MUSIK)) expect(existsSync(fsPfad(d)), d).toBe(true);
  });
});

describe("Crowd-Dauern (Eval 3, Applaus-Stapel)", () => {
  // Die ausgelieferten Applaus-Dateien sind auf Show-Längen geschnitten
  // (kurz 4 s / mittel 7 s / groß 10 s / anlaufend 12 s, jeweils Fade-out —
  // die 17-/25-s-Originale bleiben in assets/audio/crowd). Zusammen mit der
  // Anti-Stapel-Regel in fx/sound.ts kann sich kein Applaus-Teppich mehr bis
  // zum 8-Stimmen-Deckel auftürmen.
  it.skipIf(!ffprobeVerfuegbar)(
    "keine Datei unter client/public/audio/crowd länger als 12,5 s",
    () => {
      const crowdDir = join(PUBLIC_AUDIO, "crowd");
      const dateien = readdirSync(crowdDir).filter((f) => f.endsWith(".ogg"));
      expect(dateien.length).toBeGreaterThanOrEqual(5);
      for (const f of dateien) {
        const dauer = Number(
          execFileSync(
            "ffprobe",
            [
              "-v",
              "error",
              "-show_entries",
              "format=duration",
              "-of",
              "csv=p=0",
              join(crowdDir, f),
            ],
            { encoding: "utf8" },
          ).trim(),
        );
        expect(dauer, f).toBeGreaterThan(0);
        expect(dauer, f).toBeLessThanOrEqual(12.5);
      }
    },
  );

  it.skipIf(!ffprobeVerfuegbar)(
    "applaus-kurz ist wirklich kurz (≤ 4,5 s — lief vorher 17 s!)",
    () => {
      const datei = SFX["applaus-kurz"].dateien[0];
      const dauer = Number(
        execFileSync(
          "ffprobe",
          ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", fsPfad(datei)],
          { encoding: "utf8" },
        ).trim(),
      );
      expect(dauer).toBeLessThanOrEqual(4.5);
    },
  );
});

describe("Standard-Buzzer-Familie (Plan §4.3 Lücke 3)", () => {
  it("8 unterscheidbare Buzzer, alle als SFX registriert", () => {
    expect(STANDARD_BUZZER).toHaveLength(8);
    expect(new Set(STANDARD_BUZZER).size).toBe(8);
    for (const id of STANDARD_BUZZER) {
      expect(SFX[id], id).toBeDefined();
      expect(SFX[id].dateien).toHaveLength(1);
    }
    // Jeder Standard-Buzzer nutzt eine ANDERE Datei (Timbre-Trennung).
    const dateien = STANDARD_BUZZER.map((id) => SFX[id].dateien[0]);
    expect(new Set(dateien).size).toBe(8);
  });

  it("Familie = kaufbare Shop-Items (wählbar) mit Datei", () => {
    for (const id of STANDARD_BUZZER) {
      const item = SHOP_ITEMS.find((i) => i.id === id);
      expect(item?.slot, id).toBe("buzzer");
      expect(item?.datei, id).toBeTruthy();
    }
  });

  it("Slot-Zuordnung: 8 Slots → 8 VERSCHIEDENE Buzzer, dann Rundlauf", () => {
    const erste8 = Array.from({ length: 8 }, (_, i) => standardBuzzer(i));
    expect(new Set(erste8).size).toBe(8);
    expect(standardBuzzer(8)).toBe(standardBuzzer(0));
    expect(standardBuzzer(-1)).toBe(standardBuzzer(7)); // defensiver Modulo
  });
});
