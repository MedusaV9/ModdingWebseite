// Profil-Store: Anlegen/PIN/Geräte-Wiedererkennung, AT-Buchung (idempotent!),
// Shop-Transaktionen (atomar, klare Fehler), Ausrüsten mit Slot-Prüfung.
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createTestClock } from "../../shared/time";
import { createFileStorage } from "../persistence/storage";
import { anzeigeAvatar, createProfileStore, type ProfileStore } from "./profile-store";

let dir: string;
let store: ProfileStore;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-meta-"));
  store = createProfileStore(createFileStorage(dir), createTestClock(1_000_000));
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("meta: Profile (§7.1)", () => {
  it("legt Profile an; PIN optional, Gerät wird gemerkt", async () => {
    const p = await store.erstelle({
      name: "Anna",
      avatar: "don-bananas.gelb.altes-extra",
      pin: "1234",
      deviceToken: "d_geraet1",
    });
    expect(p.profileId).toMatch(/^pr_/);
    expect(p.avatar).toBe("don-bananas.gelb"); // Extras gehören NICHT in die Basis
    expect(p.pinHash).not.toBeNull();
    const liste = await store.liste("d_geraet1");
    expect(liste[0].diesesGeraet).toBe(true);
  });

  it("GERÄTE-FILTER (P1): fremde Geräte sehen fremde Profile NIE in der Liste", async () => {
    await store.erstelle({ name: "Anna", avatar: "gelb", deviceToken: "d_geraet1" });
    await store.erstelle({ name: "Ben", avatar: "rot", pin: "4711", deviceToken: "d_geraet1" });
    // Fremdes Gerät ⇒ leere Liste; ohne Token ⇒ ebenfalls leer.
    expect(await store.liste("d_fremd")).toEqual([]);
    expect(await store.liste(undefined)).toEqual([]);
    // Eigenes Gerät ⇒ beide Profile, alle als diesesGeraet markiert.
    const eigene = await store.liste("d_geraet1");
    expect(eigene).toHaveLength(2);
    expect(eigene.every((p) => p.diesesGeraet)).toBe(true);
  });

  it("login: bekanntes Gerät ODER PIN; falsche PIN blockt", async () => {
    const p = await store.erstelle({ name: "Ben", avatar: "gelb", pin: "4711" });
    expect(await store.login(p.profileId, { pin: "9999" })).toEqual({ fehler: "pin-falsch" });
    const ok = await store.login(p.profileId, { pin: "4711", deviceToken: "d_neu" });
    expect("fehler" in ok).toBe(false);
    // Gerät ist jetzt gebunden ⇒ Login ohne PIN klappt.
    expect("fehler" in (await store.login(p.profileId, { deviceToken: "d_neu" }))).toBe(false);
  });

  it("KEINE SCHEINPRÜFUNG (P1): explizit falsche PIN blockt AUCH auf vertrautem Gerät", async () => {
    const p = await store.erstelle({
      name: "Cari",
      avatar: "gelb",
      pin: "2468",
      deviceToken: "d_vertraut",
    });
    // Vertrautes Gerät ohne PIN: ok (Geräte-Token IST der Zugriffs-Beweis).
    expect("fehler" in (await store.login(p.profileId, { deviceToken: "d_vertraut" }))).toBe(false);
    // Vertrautes Gerät MIT falscher PIN: die eingegebene PIN wird WIRKLICH
    // geprüft — 0000 darf nie durchrutschen (Playtest-4-Befund).
    expect(await store.login(p.profileId, { pin: "0000", deviceToken: "d_vertraut" })).toEqual({
      fehler: "pin-falsch",
    });
    // Käufe mit falscher PIN auf vertrautem Gerät blocken genauso.
    expect(await store.kaufe(p.profileId, "hut-zylinder", { pin: "0000" })).toEqual({
      fehler: "pin-falsch",
    });
  });

  it("ladeNachName (P1): Name + PIN lädt fremdes Profil und bindet das Gerät", async () => {
    const p = await store.erstelle({
      name: "Delia",
      avatar: "pink",
      pin: "1234",
      deviceToken: "d_alt",
    });
    // Falsche PIN blockt server-seitig; unbekannter Name meldet sich klar.
    expect(await store.ladeNachName("Delia", { pin: "9999", deviceToken: "d_neu" })).toEqual({
      fehler: "pin-falsch",
    });
    expect(await store.ladeNachName("Gibtsnicht", { pin: "1234" })).toEqual({
      fehler: "profil-unbekannt",
    });
    // Ohne PIN auf fremdem Gerät: gesperrtes Profil bleibt zu.
    expect(await store.ladeNachName("delia", { deviceToken: "d_neu" })).toEqual({
      fehler: "pin-falsch",
    });
    // Korrekte PIN (Name case-insensitiv) ⇒ Profil + Geräte-Bindung.
    const ok = await store.ladeNachName("  delia ", { pin: "1234", deviceToken: "d_neu" });
    expect("fehler" in ok).toBe(false);
    if (!("fehler" in ok)) expect(ok.profileId).toBe(p.profileId);
    expect((await store.liste("d_neu")).map((x) => x.profileId)).toEqual([p.profileId]);
  });

  it("ladeNachName: namensgleiche zugängliche Profile sind mehrdeutig", async () => {
    await store.erstelle({ name: "Zwilling", avatar: "gelb" });
    await store.erstelle({ name: "Zwilling", avatar: "rot" });
    expect(await store.ladeNachName("Zwilling", { deviceToken: "d_x" })).toEqual({
      fehler: "name-mehrdeutig",
    });
  });

  it("Profil OHNE PIN ist frei zugänglich (kein Account-Zwang)", async () => {
    const p = await store.erstelle({ name: "Cleo", avatar: "rot" });
    expect("fehler" in (await store.login(p.profileId, {}))).toBe(false);
  });

  it("WILLKOMMENS-PAKET (P2): erstes Profil pro Gerät bekommt 300 AT + Titel — einmalig", async () => {
    const erste = await store.erstelle({ name: "Neu", avatar: "gelb", deviceToken: "d_neu1" });
    expect(erste.at).toEqual({ gesamt: 300, verfuegbar: 300 });
    expect(erste.besitz).toEqual(["titel-frischer-affe"]);
    expect(erste.ausgeruestet.titel).toBe("titel-frischer-affe");
    // Zweites Profil auf DEMSELBEN Gerät: kein zweites Paket (idempotent).
    const zweite = await store.erstelle({ name: "Zwei", avatar: "rot", deviceToken: "d_neu1" });
    expect(zweite.at).toEqual({ gesamt: 0, verfuegbar: 0 });
    expect(zweite.besitz).toEqual([]);
    // Anderes Gerät ⇒ eigenes Paket; OHNE Geräte-Token ⇒ keines (nicht zuordenbar).
    const anderes = await store.erstelle({ name: "Drei", avatar: "blau", deviceToken: "d_neu2" });
    expect(anderes.at.gesamt).toBe(300);
    const ohne = await store.erstelle({ name: "Vier", avatar: "pink" });
    expect(ohne.at.gesamt).toBe(0);
  });

  it("Willkommens-Titel ist anlegbar, aber NICHT kaufbar (Geschenk-Exklusiv)", async () => {
    const p = await store.erstelle({ name: "Gina", avatar: "gelb", deviceToken: "d_g1" });
    // Ablegen + wieder anlegen funktioniert (Item ist im Besitz).
    const ab = await store.ruesteAus(p.profileId, "titel", null, {});
    expect("fehler" in ab).toBe(false);
    const an = await store.ruesteAus(p.profileId, "titel", "titel-frischer-affe", {});
    expect("fehler" in an).toBe(false);
    // Kaufen kann man ihn nie — passExklusiv sperrt den Shop-Weg.
    const zweit = await store.erstelle({ name: "Hugo", avatar: "rot", deviceToken: "d_g1" });
    await store.bucheMatch("m_w", [
      { profileId: zweit.profileId, endstand: 9000, at: 900, sieg: false },
    ]);
    expect(await store.kaufe(zweit.profileId, "titel-frischer-affe", {})).toEqual({
      fehler: "nur-im-pass",
    });
  });

  it("AT-Buchung: idempotent pro matchId (Doppel-Buchungs-Schutz)", async () => {
    const p = await store.erstelle({ name: "Dario", avatar: "blau" });
    const buchung = [{ profileId: p.profileId, endstand: 12_000, at: 1800, sieg: true }];
    await store.bucheMatch("m_1", buchung);
    await store.bucheMatch("m_1", buchung); // Retry/Doppel-Event
    const nachher = await store.hole(p.profileId);
    expect(nachher?.at).toEqual({ gesamt: 1800, verfuegbar: 1800 });
    expect(nachher?.ersteMale.sieg).toBe(true);
    await store.bucheMatch("m_2", [{ profileId: p.profileId, endstand: 500, at: 50, sieg: false }]);
    expect((await store.hole(p.profileId))?.at.gesamt).toBe(1850);
  });

  it("parallele Buchungen laufen strikt sequenziell (keine Lost Updates)", async () => {
    const p = await store.erstelle({ name: "Emma", avatar: "pink" });
    await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        store.bucheMatch(`m_${i}`, [
          { profileId: p.profileId, endstand: 1000, at: 100, sieg: false },
        ]),
      ),
    );
    expect((await store.hole(p.profileId))?.at.gesamt).toBe(1000);
  });
});

describe("meta: Shop-Transaktionen (§7.4)", () => {
  it("Kauf: Preis wird abgebucht, Besitz eingetragen; zu wenig AT blockt", async () => {
    const p = await store.erstelle({ name: "Fips", avatar: "gelb" });
    expect(await store.kaufe(p.profileId, "hut-zylinder", {})).toEqual({ fehler: "zu-wenig-at" });
    await store.bucheMatch("m_1", [{ profileId: p.profileId, endstand: 0, at: 600, sieg: false }]);
    const nachKauf = await store.kaufe(p.profileId, "hut-zylinder", {});
    expect("fehler" in nachKauf).toBe(false);
    if (!("fehler" in nachKauf)) {
      expect(nachKauf.at.verfuegbar).toBe(100); // 600 − 500
      expect(nachKauf.at.gesamt).toBe(600); // Lifetime bleibt (Level-Basis!)
      expect(nachKauf.besitz).toContain("hut-zylinder");
    }
    // Doppelkauf blockt (außer Spenden-Badge).
    expect(await store.kaufe(p.profileId, "hut-zylinder", {})).toEqual({
      fehler: "schon-gekauft",
    });
    expect(await store.kaufe(p.profileId, "gibts-nicht", {})).toEqual({
      fehler: "item-unbekannt",
    });
  });

  it("Spenden-Badge ist mehrfach kaufbar (reine AT-Senke)", async () => {
    const p = await store.erstelle({ name: "Gina", avatar: "pink" });
    await store.bucheMatch("m_1", [{ profileId: p.profileId, endstand: 0, at: 2500, sieg: false }]);
    expect("fehler" in (await store.kaufe(p.profileId, "badge-spende", {}))).toBe(false);
    const zweite = await store.kaufe(p.profileId, "badge-spende", {});
    expect("fehler" in zweite).toBe(false);
    if (!("fehler" in zweite)) expect(zweite.at.verfuegbar).toBe(500); // 2500 − 2×1000
  });

  it("Ausrüsten: nur besessene Items, Slot muss passen; Extras landen im Avatar", async () => {
    const p = await store.erstelle({ name: "Hugo", avatar: "don-bananas.gelb" });
    expect(await store.ruesteAus(p.profileId, "hut", "hut-zylinder", {})).toEqual({
      fehler: "nicht-im-besitz",
    });
    await store.bucheMatch("m_1", [{ profileId: p.profileId, endstand: 0, at: 999, sieg: false }]);
    await store.kaufe(p.profileId, "hut-zylinder", {});
    expect(await store.ruesteAus(p.profileId, "gesicht", "hut-zylinder", {})).toEqual({
      fehler: "falscher-slot",
    });
    const an = await store.ruesteAus(p.profileId, "hut", "hut-zylinder", {});
    if (!("fehler" in an)) {
      expect(an.ausgeruestet.hut).toBe("hut-zylinder");
      expect(anzeigeAvatar(an)).toBe("don-bananas.gelb.hut-zylinder");
    }
    const ab = await store.ruesteAus(p.profileId, "hut", null, {});
    if (!("fehler" in ab)) expect(anzeigeAvatar(ab)).toBe("don-bananas.gelb");
  });

  it("WELLE 3 — Slot-Exklusivität: zweiter Kopf ERSETZT den ersten; podium/einlauf additiv", async () => {
    const p = await store.erstelle({ name: "Kai", avatar: "glitzer-gina.pink" });
    await store.bucheMatch("m_1", [
      { profileId: p.profileId, endstand: 0, at: 99_000, sieg: false },
    ]);
    for (const id of ["hut-pirat", "hut-krone", "fell-tiger", "podium-goldrahmen"]) {
      expect("fehler" in (await store.kaufe(p.profileId, id, {})), id).toBe(false);
    }
    await store.ruesteAus(p.profileId, "hut", "hut-pirat", {});
    await store.ruesteAus(p.profileId, "fell", "fell-tiger", {});
    await store.ruesteAus(p.profileId, "podium", "podium-goldrahmen", {});
    // Krone anlegen ⇒ Piratenhut fliegt automatisch raus (nur 1 Kopf-Slot).
    const an = await store.ruesteAus(p.profileId, "hut", "hut-krone", {});
    expect("fehler" in an).toBe(false);
    if (!("fehler" in an)) {
      expect(an.ausgeruestet.hut).toBe("hut-krone");
      const extras = anzeigeAvatar(an).split(".")[2].split("+");
      expect(extras).toContain("hut-krone");
      expect(extras).not.toContain("hut-pirat");
      // Neue Slots reisen im selben Wire-Format mit (rückwärtskompatibel).
      expect(extras).toContain("fell-tiger");
      expect(extras).toContain("podium-goldrahmen");
    }
    // Einlauf-Item mit Level-Gate: Level 33 (99.000 AT) ⇒ kaufbar + anlegbar.
    expect("fehler" in (await store.kaufe(p.profileId, "einlauf-blitz", {}))).toBe(false);
    const einlauf = await store.ruesteAus(p.profileId, "einlauf", "einlauf-blitz", {});
    if (!("fehler" in einlauf)) {
      expect(anzeigeAvatar(einlauf)).toContain("einlauf-blitz");
    }
  });

  it("PIN-geschütztes Profil: Kauf ohne Zugriff blockt", async () => {
    const p = await store.erstelle({ name: "Ivy", avatar: "rot", pin: "0000" });
    await store.bucheMatch("m_1", [{ profileId: p.profileId, endstand: 0, at: 999, sieg: false }]);
    expect(await store.kaufe(p.profileId, "hut-zylinder", { pin: "1111" })).toEqual({
      fehler: "pin-falsch",
    });
    expect("fehler" in (await store.kaufe(p.profileId, "hut-zylinder", { pin: "0000" }))).toBe(
      false,
    );
  });
});
