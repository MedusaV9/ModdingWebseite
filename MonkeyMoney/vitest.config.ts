// Vitest-Konfiguration: Unit-Tests liegen kolokalisiert als *.test.ts neben den Modulen.
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: [
      "server/**/*.test.ts",
      "shared/**/*.test.ts",
      "tools/**/*.test.ts",
      // Standalone-Transport (iPad-Host): reine Logik, läuft im Node-Env.
      "client/**/*.test.ts",
    ],
    environment: "node",
  },
});
