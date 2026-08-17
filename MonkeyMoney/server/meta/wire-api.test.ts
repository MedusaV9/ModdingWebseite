// wire-api = die EINE Meta-Routen-Logik für beide Transporte (Express im
// Node-Pfad, "meta.http"-Wire-Event im Standalone). Hier testen wir sie
// transport-frei: Requests wie sie das Telefon schickt (Pfad MIT
// /api/meta-Präfix + Query-String), Antworten als {status, body}-Umschlag.
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Question } from "../../shared/content";
import { createStatefulRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader, KatalogFrage } from "../content-loader/index";
import { createFileStorage } from "../persistence/storage";
import { createMetaService, type MetaService } from "./index";
import { bearbeiteMetaRequest } from "./wire-api";

function fakeLoader(): ContentLoader {
  const pool: Question[] = Array.from({ length: 10 }, (_, i) => ({
    id: `q${i}`,
    kind: "choice4",
    category: "affen",
    difficulty: "easy",
    text: `Frage ${i}?`,
    options: ["A", "B", "C", "D"],
    answer: 0,
    erklaerung: "Weil.",
  }));
  const katalog: KatalogFrage[] = pool.map((f) => ({
    frage: f,
    oberkategorie: "wissen",
    planTyp: "mc4",
    region: "global",
  }));
  return {
    async loadPacks() {},
    pickQuestions: ({ anzahl }) => pool.slice(0, anzahl).map((f) => ({ ...f })),
    alleFragen: () => katalog,
  };
}

let dir: string;
let meta: MetaService;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-wireapi-"));
  meta = createMetaService({
    storage: createFileStorage(dir),
    clock: createTestClock(1_000_000),
    rng: createStatefulRng(7),
    contentLoader: fakeLoader(),
  });
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

const req = (
  method: string,
  pfad: string,
  body?: unknown,
): ReturnType<typeof bearbeiteMetaRequest> => bearbeiteMetaRequest(meta, { method, pfad, body });

describe("bearbeiteMetaRequest (Meta über HTTP UND Wire)", () => {
  it("POST /profile legt an — Antwort OHNE pinHash/deviceTokens (nie herausgeben)", async () => {
    const antwort = await req("POST", "/api/meta/profile", {
      name: "Coco",
      avatar: "gelb",
      pin: "4711",
      deviceToken: "d_1",
    });
    expect(antwort.status).toBe(200);
    const profil = (antwort.body as { profil: Record<string, unknown> }).profil;
    expect(profil.name).toBe("Coco");
    expect(profil.gesperrt).toBe(true);
    expect(profil).not.toHaveProperty("pinHash");
    expect(profil).not.toHaveProperty("deviceTokens");
  });

  it("POST /profile ohne Namen ⇒ 400 name-fehlt (Wire ist Systemgrenze)", async () => {
    expect(await req("POST", "/api/meta/profile", {})).toEqual({
      status: 400,
      body: { error: "name-fehlt" },
    });
  });

  it("GET /profile?device=… filtert per Query-String aufs eigene Gerät", async () => {
    await req("POST", "/api/meta/profile", { name: "Coco", deviceToken: "d_ipad" });
    await req("POST", "/api/meta/profile", { name: "Fremd", deviceToken: "d_anders" });
    const antwort = await req("GET", "/api/meta/profile?device=d_ipad");
    const profile = (antwort.body as { profile: { name: string }[] }).profile;
    expect(profile.map((p) => p.name)).toEqual(["Coco"]);
  });

  it("POST /profile/laden: unbekannter Name ⇒ 404, falsche PIN ⇒ 403", async () => {
    await req("POST", "/api/meta/profile", { name: "Zoe", pin: "4711" });
    expect((await req("POST", "/api/meta/profile/laden", { name: "Niemand" })).status).toBe(404);
    const falschePi = await req("POST", "/api/meta/profile/laden", { name: "Zoe", pin: "0000" });
    expect(falschePi).toEqual({ status: 403, body: { error: "pin-falsch" } });
    const richtig = await req("POST", "/api/meta/profile/laden", { name: "Zoe", pin: "4711" });
    expect(richtig.status).toBe(200);
  });

  it("POST /profile/:id/login: PIN wird geprüft — 403 bei falscher PIN", async () => {
    const anlage = await req("POST", "/api/meta/profile", { name: "Zoe", pin: "4711" });
    const id = (anlage.body as { profil: { profileId: string } }).profil.profileId;
    expect((await req("POST", `/api/meta/profile/${id}/login`, { pin: "9999" })).status).toBe(403);
    expect((await req("POST", `/api/meta/profile/${id}/login`, { pin: "4711" })).status).toBe(200);
  });

  it("GET /saves liefert die Slot-Liste für die GM-Lobby-Karte", async () => {
    const leer = await req("GET", "/api/meta/saves");
    expect(leer).toEqual({ status: 200, body: { slots: [] } });
  });

  it("GET /personas liefert die Bot-Auswahl (id/name/avatar, ohne Interna)", async () => {
    const antwort = await req("GET", "/api/meta/personas");
    const personas = (antwort.body as { personas: Record<string, unknown>[] }).personas;
    expect(personas.length).toBeGreaterThan(0);
    expect(Object.keys(personas[0]).sort()).toEqual(["avatar", "id", "name"]);
  });

  it("Pfad funktioniert MIT und OHNE /api/meta-Präfix identisch (beide Transporte)", async () => {
    const mit = await req("GET", "/api/meta/shop");
    const ohne = await req("GET", "/shop");
    expect(mit.status).toBe(200);
    expect(ohne).toEqual(mit);
  });

  it("unbekannte Route ⇒ 404 unbekannte-route (kein stiller Durchfall)", async () => {
    expect(await req("GET", "/api/meta/gibts-nicht")).toEqual({
      status: 404,
      body: { error: "unbekannte-route" },
    });
    expect((await req("DELETE", "/api/meta/profile")).status).toBe(404);
  });

  it("GET /profile/:id/karte: 404 für Unbekannte, 200 mit Karte für Bekannte", async () => {
    expect((await req("GET", "/api/meta/profile/pr_gibtsnicht/karte")).status).toBe(404);
    const anlage = await req("POST", "/api/meta/profile", { name: "Coco" });
    const id = (anlage.body as { profil: { profileId: string } }).profil.profileId;
    const karte = await req("GET", `/api/meta/profile/${id}/karte`);
    expect(karte.status).toBe(200);
    expect((karte.body as { karte: { name: string } }).karte.name).toBe("Coco");
  });
});
