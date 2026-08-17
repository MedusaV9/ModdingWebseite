// Kosmetik-Renderer (Welle 3): Katalog ↔ Renderer-Abdeckung (kein Item darf
// „visuell" versprechen ohne sichtbare Wirkung), Fell-Pattern-Kacheln
// (Maße + Palette-Durchschein via var(--fell)) und die Vorschau-Helfer
// (Slot-Exklusivität wie beim echten Anlegen). Läuft im Node-Env — die
// reinen Helfer brauchen kein DOM, nur schmueckePuppen selbst täte das.
import { describe, expect, it } from "vitest";
import { SHOP_ITEMS } from "../../shared/meta";
import { saisonItems } from "../../shared/quests";
import { AFFEN } from "./fx/avatar";
import { fellMusterFuer, hatKopfAnker, hatVisuellenRenderer, vorschauAvatar } from "./meta-avatar";

describe("meta-avatar: Renderer-Abdeckung (Katalog-Integrität)", () => {
  it("JEDES visuelle Katalog-Item hat einen Renderer (Overlay/Muster/Swap/Stil)", () => {
    for (const item of SHOP_ITEMS) {
      if (item.visuell !== true) continue;
      if (item.typ === "banner") {
        expect(item.stil, `${item.id}: Banner ohne stil`).toBeDefined();
      } else if (item.typ === "namestil") {
        expect(item.klasse ?? item.stil, `${item.id}: Namens-Stil ohne klasse/stil`).toBeDefined();
      } else {
        expect(hatVisuellenRenderer(item.id), `${item.id}: kein Renderer`).toBe(true);
      }
    }
  });

  it("Saison-1-Exklusive (Pass) bleiben renderbar (Banner/Namens-Stil via stil)", () => {
    for (const item of saisonItems("2026-08")) {
      if (item.visuell !== true) continue;
      expect(item.stil ?? item.klasse, `${item.id}: Saison-Item ohne Stil`).toBeDefined();
    }
  });

  it("Fell-Muster-Kacheln: gültige Maße + var(--fell)-Basis (Palette scheint durch)", () => {
    for (const id of [
      "fell-tiger",
      "fell-dalmatiner",
      "fell-sterne",
      "fell-camo",
      "fell-goldglitzer",
    ]) {
      const muster = fellMusterFuer(id);
      expect(muster, `${id}: Kachel fehlt`).not.toBeNull();
      expect(muster!.breite).toBeGreaterThan(0);
      expect(muster!.hoehe).toBeGreaterThan(0);
      expect(muster!.kachel).toContain("var(--fell");
    }
    expect(fellMusterFuer("fell-leopard")).toBeNull(); // Farb-Swap, kein Muster
  });

  it("jede Puppe hat einen Kopf-Anker (Hüte/Brillen sitzen sonst daneben)", () => {
    // Die Köpfe teilen KEINE Position (Kiki 120/166, Paule 120/74 …) — jedes
    // Overlay wird per Anker gemappt. Neue Affen ⇒ KOPF_ANKER ergänzen.
    for (const affe of AFFEN) {
      expect(hatKopfAnker(affe.id), `${affe.id}: Kopf-Anker fehlt`).toBe(true);
    }
  });
});

describe("meta-avatar: Shop-Vorschau (Welle 3)", () => {
  it("vorschauAvatar: Item probeweise anlegen ersetzt NUR denselben Slot", () => {
    const basis = "don-bananas.gelb.hut-zylinder+fell-tiger+lv7";
    // Anderer Hut ⇒ Zylinder fliegt raus (Slot-Exklusivität); Fell UND das
    // Level-Pseudo-Extra (lv7, kein Katalog-Item) bleiben unangetastet.
    expect(vorschauAvatar(basis, "hut-krone")).toBe("don-bananas.gelb.fell-tiger+lv7+hut-krone");
    // Anderes Muster ⇒ Tiger raus, Hut bleibt.
    expect(vorschauAvatar(basis, "fell-goldglitzer")).toBe(
      "don-bananas.gelb.hut-zylinder+lv7+fell-goldglitzer",
    );
    // Neuer Slot (Podium) ⇒ rein additiv.
    expect(vorschauAvatar("don-bananas.gelb", "podium-goldrahmen")).toBe(
      "don-bananas.gelb.podium-goldrahmen",
    );
    // Unbekanntes Item / keine Auswahl ⇒ Avatar unverändert.
    expect(vorschauAvatar(basis, "gibtsnicht")).toBe(basis);
    expect(vorschauAvatar(basis, null)).toBe(basis);
  });
});
