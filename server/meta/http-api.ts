// Meta-HTTP-API (JSON): Profile, Shop, Bestenlisten, Übungsmodus, Save-Slots
// + Admin-Dashboard (/admin, PIN aus der Env). Wird von core/http.ts mit EINER
// Zeile eingehängt. Die /api/meta-Routen-LOGIK lebt seit dem Standalone-Meta-
// Wiring (W4) transport-neutral in wire-api.ts — Express ist hier nur noch
// der dünne Adapter (Body-Parsing + Status/JSON), damit der iPad-Standalone
// EXAKT dieselben Routen über das Relay-Wire-Event "meta.http" bekommt.
import express, { type Express, type Request, type Response } from "express";
import type { MetaService } from "./index";
import { bearbeiteMetaRequest } from "./wire-api";
import { adminHtml } from "./admin-ui";

export interface MetaApiOptions {
  /** Admin-PIN aus der Env — ohne PIN ist /admin deaktiviert (503). */
  adminPin: string | null;
}

export function registriereMetaApi(app: Express, meta: MetaService, opts: MetaApiOptions): void {
  app.use(["/api/meta", "/api/admin"], express.json({ limit: "64kb" }));

  // ---------- /api/meta/* — EINE Routen-Logik für HTTP UND Relay-Wire ----------

  app.use("/api/meta", (req, res) => {
    // originalUrl trägt den vollen Pfad inkl. Query — wire-api schneidet das
    // /api/meta-Präfix selbst ab (der Wire-Pfad der Telefone kommt genauso an).
    void bearbeiteMetaRequest(meta, {
      method: req.method,
      pfad: req.originalUrl,
      body: req.body,
    })
      .then((antwort) => res.status(antwort.status).json(antwort.body))
      .catch(() => res.status(500).json({ error: "meta-fehler" }));
  });

  // ---------- Admin-Dashboard (§7.6 — PIN aus der Env, Node-only) ----------

  app.get("/admin", (_req, res) => {
    if (opts.adminPin === null) {
      return void res
        .status(503)
        .type("text/plain")
        .send("Admin deaktiviert — ADMIN_PIN in der Env setzen.");
    }
    res.type("text/html").send(adminHtml());
  });

  /** PIN-Gate für alle /api/admin-Routen — true = weitermachen. */
  function adminOk(req: Request, res: Response): boolean {
    if (opts.adminPin === null) {
      res.status(503).json({ error: "admin-deaktiviert" });
      return false;
    }
    const pin = req.header("x-admin-pin") ?? String(req.query.pin ?? "");
    if (pin !== opts.adminPin) {
      res.status(403).json({ error: "pin-falsch" });
      return false;
    }
    return true;
  }

  app.get("/api/admin/reports", (req, res) => {
    if (!adminOk(req, res)) return;
    void meta
      .reports(req.query.refresh !== "0")
      .then((reports) => res.json({ reports }))
      .catch((err) => {
        console.error("Admin-Reports fehlgeschlagen:", err);
        res.status(500).json({ error: "report-fehler" });
      });
  });

  // ---------- Admin-Aktionen der Fehlerhaft-Queue (ADDITIV, W20) ----------
  // Quarantäne = Frage wirklich aus der Match-Rotation (pickQuestions-Sperre),
  // Entkräften = bisherige Flags ausblenden, Geprüft = Sichtvermerk mit Datum.

  app.post("/api/admin/frage/:id/quarantaene", (req, res) => {
    if (!adminOk(req, res)) return;
    const an = (req.body as Record<string, unknown>)?.an !== false;
    void meta.moderation
      .setzeQuarantaene(req.params.id, an)
      .then((eintrag) => res.json({ eintrag }))
      .catch(() => res.status(500).json({ error: "moderation-fehler" }));
  });

  app.post("/api/admin/frage/:id/entkraeften", (req, res) => {
    if (!adminOk(req, res)) return;
    void meta.moderation
      .entkraefte(req.params.id)
      .then((eintrag) => res.json({ eintrag }))
      .catch(() => res.status(500).json({ error: "moderation-fehler" }));
  });

  app.post("/api/admin/frage/:id/geprueft", (req, res) => {
    if (!adminOk(req, res)) return;
    const an = (req.body as Record<string, unknown>)?.an !== false;
    void meta.moderation
      .setzeGeprueft(req.params.id, an)
      .then((eintrag) => res.json({ eintrag }))
      .catch(() => res.status(500).json({ error: "moderation-fehler" }));
  });
}
