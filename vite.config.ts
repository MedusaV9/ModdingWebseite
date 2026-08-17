// Vite-Multi-Page-Build: fünf Entries (Landing, Screen, Player, GM, Host) → client/dist/.
// Der Express-Server liefert client/dist/ statisch aus — AMP sieht nie einen Build.
// Host = Standalone-Modus (iPad ist der Server): die Seite bündelt den kompletten
// Spiel-Server (server/host-browser/) und braucht dafür zwei Zusätze unten:
// den node:crypto-Alias und das Content-Bundle-Plugin.
import { resolve } from "node:path";
import { defineConfig, type Plugin } from "vite";
import { createContentLoader } from "./server/content-loader/index";

const root = resolve(import.meta.dirname, "client");

/**
 * Backt die Fragen-Packs als STATISCHES JSON in den Build (host-content.json):
 * gleiche Quelle wie der Node-Server (createContentLoader läuft hier zur
 * BUILD-Zeit in Node und liefert den validierten choice4-Katalog inkl.
 * /media-URLs). Im Dev-Server kommt dieselbe Datei aus einer Middleware.
 */
function mmHostContentBundle(): Plugin {
  async function baueBundle(): Promise<string> {
    const loader = createContentLoader();
    await loader.loadPacks();
    return JSON.stringify({
      schemaVersion: 1,
      quelle: "content/packs (Build-Zeit, createContentLoader.alleFragen)",
      fragen: loader.alleFragen(),
    });
  }
  return {
    name: "mm-host-content-bundle",
    async generateBundle() {
      this.emitFile({ type: "asset", fileName: "host-content.json", source: await baueBundle() });
    },
    configureServer(server) {
      server.middlewares.use("/host-content.json", (_req, res) => {
        void baueBundle().then((json) => {
          res.setHeader("content-type", "application/json");
          res.end(json);
        });
      });
    },
  };
}

export default defineConfig({
  root,
  plugins: [mmHostContentBundle()],
  resolve: {
    alias: {
      // NUR für den Host-Entry relevant: rooms/sessions/sockets ziehen
      // randomUUID aus node:crypto, meta/profile-store zusätzlich createHash —
      // im Browser kommt WebCrypto + Pure-TS-SHA-256 (Shim). Die anderen
      // Entries importieren nie node:crypto (Alias ist inert).
      "node:crypto": resolve(root, "host/node-crypto-shim.ts"),
      // Meta-Wiring (W4): analytics/reports.ts (Admin-Lücken-Report) zieht
      // node:fs/path/url — im Standalone unerreichbar, aber bündelbar nötig.
      "node:fs": resolve(root, "host/node-stubs-shim.ts"),
      "node:path": resolve(root, "host/node-stubs-shim.ts"),
      "node:url": resolve(root, "host/node-stubs-shim.ts"),
    },
  },
  build: {
    outDir: "dist", // relativ zu root → client/dist
    emptyOutDir: true,
    rollupOptions: {
      input: {
        landing: resolve(root, "index.html"),
        screen: resolve(root, "screen.html"),
        player: resolve(root, "player.html"),
        gm: resolve(root, "gm.html"),
        host: resolve(root, "host.html"),
      },
      output: {
        // Eval-7 P2 (Erstladung): Vendor-Deps (lit-html, socket.io-client, zod)
        // in EINEN stabilen Chunk — App-Updates invalidieren den Browser-Cache
        // der Deps nicht mehr. Die Minigame-Renderer splitten sich seit dem
        // lazy import.meta.glob in der Registry ohnehin pro Format.
        manualChunks(id: string): string | undefined {
          return id.includes("node_modules") ? "vendor" : undefined;
        },
      },
    },
  },
  server: {
    // Dev-Komfort: Vite-Dev-Server proxied Socket-Traffic an den lokalen Node-Server.
    proxy: {
      "/socket.io": { target: "http://localhost:8080", ws: true },
      "/api": { target: "http://localhost:8080" },
      // Laufzeit-Medien (Fragen-Bilder, Videos) liefert der Node-Server aus.
      "/media": { target: "http://localhost:8080" },
      // Song-Snippets (content/musik/media) — explizit, auch wenn der
      // /media-Präfix-Match sie schon erwischen würde.
      "/media-musik": { target: "http://localhost:8080" },
    },
  },
});
