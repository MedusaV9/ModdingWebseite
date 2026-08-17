// ESLint Flat Config — zementiert die Abhängigkeitsregeln aus TECH-SPEC §2:
//   shared ← alle · engine importiert nur shared + minigames/_api ·
//   minigames/* nur shared + _api · client/* nur shared + client/shared ·
//   Clock/Rng-Disziplin: Date.now()/Math.random() nur in server/core + tools/tests.
import eslint from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";

// Verbot der OS-Uhr/des globalen Zufalls in Spiellogik (Determinismus, TECH-SPEC Leitprinzip 3).
const clockRngBan = {
  "no-restricted-properties": [
    "error",
    { object: "Date", property: "now", message: "Clock injizieren (shared/time.ts)." },
    { object: "Math", property: "random", message: "Rng injizieren (shared/rng.ts)." },
  ],
};

export default tseslint.config(
  {
    ignores: [
      "node_modules/**",
      "client/dist/**",
      "server/dist/**",
      "data/**",
      "assets/**",
      "remotion/**",
    ],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    },
  },
  // Playwright-Screenshot-Tour (.mjs): Node-Umgebung plus Browser-Globals
  // (page.evaluate-Callbacks laufen im Browser-Kontext).
  {
    files: ["tools/screenshots/**/*.mjs"],
    languageOptions: { globals: { ...globals.node, ...globals.browser } },
  },
  // Audio-Probe (.mjs): reines Node-Skript (ffprobe/loudnorm-Report).
  {
    files: ["tools/audio/**/*.mjs"],
    languageOptions: { globals: { ...globals.node } },
  },
  // Musik-Pipeline (.mjs): Node-Skripte (yt-dlp/ffmpeg-Import + Validator).
  {
    files: ["tools/musik/**/*.mjs"],
    languageOptions: { globals: { ...globals.node } },
  },
  // iPad-Standalone-Tooling (.mjs): Relay-Sim (Node) + Playwright-Beweis
  // (page.evaluate-Callbacks laufen im Browser-Kontext).
  {
    files: ["tools/ipad-host/**/*.mjs"],
    languageOptions: { globals: { ...globals.node, ...globals.browser } },
  },
  // Clock/Rng-Disziplin überall außer core/tools/tests (dort entsteht die echte Clock).
  {
    files: ["server/**/*.ts", "shared/**/*.ts", "client/**/*.ts"],
    ignores: ["server/core/**", "**/*.test.ts"],
    rules: clockRngBan,
  },
  // Engine: nur shared + minigames/_api.
  {
    files: ["server/engine/**/*.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["**/core/*", "**/rooms/*", "**/persistence/*", "**/content-loader/*"],
              message: "Engine importiert nur shared + minigames/_api (TECH-SPEC §2).",
            },
          ],
        },
      ],
    },
  },
  // Minigames: nur shared + _api.
  {
    files: ["server/minigames/**/*.ts"],
    ignores: ["server/minigames/registry.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["**/engine/*", "**/core/*", "**/rooms/*", "**/persistence/*"],
              message: "Minigames importieren nur shared + minigames/_api (TECH-SPEC §2).",
            },
          ],
        },
      ],
    },
  },
  // Clients: nie Server-Code importieren.
  {
    files: ["client/**/*.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["**/server/**"],
              message: "Clients importieren nur shared + client/shared (TECH-SPEC §2).",
            },
          ],
        },
      ],
    },
  },
  // AUSNAHME Standalone-Host (client/host/): diese Seite IST der Server im
  // Browser (iPad-Standalone-Modus) — sie darf GENAU server/host-browser
  // bündeln; der Rest des Server-Baums bleibt tabu.
  {
    files: ["client/host/**/*.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              // gitignore-Semantik: das Verzeichnis selbst UND sein Inhalt
              // müssen re-inkludiert werden, sonst greift die Negation nicht.
              group: ["**/server/**", "!**/server/host-browser", "!**/server/host-browser/**"],
              message: "Host-Seite importiert Server-Code NUR über server/host-browser.",
            },
          ],
        },
      ],
    },
  },
);
