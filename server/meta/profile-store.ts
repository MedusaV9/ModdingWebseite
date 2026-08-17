// Profil-Store (GAME-DESIGN §7.1): Profile ohne Account-Zwang, persistiert als
// EINE atomare JSON-Datei (meta/profiles.json). Alle Mutationen laufen strikt
// sequenziell durch eine Op-Kette (Promise-Queue) — Shop-Käufe und AT-Buchungen
// sind damit prozess-intern atomar (read → modify → writeJsonAtomic).
import { createHash, randomUUID } from "node:crypto";
import {
  WILLKOMMEN_ITEM,
  WILLKOMMEN_START_AT,
  extrasAusAusruestung,
  avatarBasis,
  avatarMitExtras,
  levelFuerAt,
  levelToken,
  type ItemSlot,
  type MetaProfil,
  type ProfilAusruestung,
} from "../../shared/meta";
import { itemFuer } from "../../shared/quests";
import type { Clock } from "../../shared/time";
import type { Storage } from "../persistence/storage";
import { kaufSperre, levelUpZwischen, type LevelUp } from "./level";

const DATEI = "meta/profiles.json";
const MAX_GEBUCHTE_MATCHES = 50;
const MAX_DEVICE_TOKENS = 8;

interface ProfilDatei {
  schemaVersion: 1;
  profile: Record<string, MetaProfil>;
}

export interface ProfilZugriff {
  pin?: string;
  deviceToken?: string;
}

export interface ProfilSummary {
  profileId: string;
  name: string;
  avatar: string; // Basis + Extras (Anzeige-Format)
  titel: string | null;
  level: number;
  atVerfuegbar: number;
  gesperrt: boolean; // PIN gesetzt
  diesesGeraet: boolean;
}

export interface AtBuchung {
  profileId: string;
  endstand: number;
  at: number;
  sieg: boolean;
}

/** Ergebnis EINER Match-Buchung (nur tatsächlich gebuchte Profile). */
export interface BuchungsErgebnis {
  profileId: string;
  at: number;
  atGesamt: number;
  /** Level-Up durch DIESE Buchung (Screen-Einblendung + Handy-Konfetti). */
  levelUp: LevelUp | null;
}

function pinHash(profileId: string, pin: string): string {
  return createHash("sha256").update(`${profileId}:${pin}`).digest("hex");
}

/** Anzeige-Avatar: Basis + Extras aus der Ausrüstung (Wire-Format-Erweiterung).
 * Das Profil-Level reist als Pseudo-Extra "lv<N>" mit — der Renderer macht
 * daraus das kleine Badge neben dem Namen (Lobby/Podium, §7.5). */
export function anzeigeAvatar(profil: MetaProfil): string {
  const extras = extrasAusAusruestung(profil.ausgeruestet);
  const lv = levelToken(levelFuerAt(profil.at.gesamt));
  if (lv !== null) extras.push(lv);
  return avatarMitExtras(profil.avatar, extras);
}

export interface ProfileStore {
  erstelle(opts: {
    name: string;
    avatar: string;
    pin?: string;
    deviceToken?: string;
  }): Promise<MetaProfil>;
  /** NUR Profile DIESES Geräts (Datenschutz auf geteilten Servern, P1-Fix):
   * fremde Profile erreicht man ausschließlich über ladeNachName (Name+PIN). */
  liste(deviceToken?: string): Promise<ProfilSummary[]>;
  hole(profileId: string): Promise<MetaProfil | null>;
  /**
   * Zugriff prüfen + Gerät binden: bekanntes Gerät ODER korrekte PIN ODER
   * Profil ohne PIN (frictionless, §7.1). Erfolg registriert den deviceToken.
   * WICHTIG: eine EXPLIZIT mitgegebene PIN wird IMMER wirklich geprüft —
   * auch auf vertrautem Gerät (keine Scheinprüfung, P1-Fix).
   */
  login(profileId: string, zugriff: ProfilZugriff): Promise<MetaProfil | { fehler: string }>;
  /** „Anderes Profil laden": Profil per NAME holen (fremdes Gerät) — PIN
   * wird server-seitig geprüft, Erfolg bindet das Gerät. */
  ladeNachName(name: string, zugriff: ProfilZugriff): Promise<MetaProfil | { fehler: string }>;
  /** AT-Buchung am Match-Ende — idempotent pro matchId (gebuchteMatches-Ring).
   * Liefert pro GEBUCHTEM Profil den neuen Stand + Level-Up (falls erreicht). */
  bucheMatch(matchId: string, buchungen: AtBuchung[]): Promise<BuchungsErgebnis[]>;
  /** AT-EINNAHME außerhalb eines Matches (Pass-Stufen-Boni) — füttert das Level. */
  gutschrift(profileId: string, at: number): Promise<BuchungsErgebnis | null>;
  /** Items OHNE Kauf in den Besitz legen (Pass-Belohnungen) — idempotent. */
  gewaehreItems(profileId: string, itemIds: string[]): Promise<void>;
  /** Shop-Kauf: Preis abbuchen + Besitz eintragen — atomar, mit klaren Fehlern. */
  kaufe(
    profileId: string,
    itemId: string,
    zugriff: ProfilZugriff,
  ): Promise<MetaProfil | { fehler: string }>;
  /** Item an-/ablegen (itemId null = Slot leeren). */
  ruesteAus(
    profileId: string,
    slot: ItemSlot,
    itemId: string | null,
    zugriff: ProfilZugriff,
  ): Promise<MetaProfil | { fehler: string }>;
  /** Name/Avatar/PIN ändern (PIN nur mit Zugriff). */
  aktualisiere(
    profileId: string,
    patch: { name?: string; avatar?: string; pin?: string | null },
    zugriff: ProfilZugriff,
  ): Promise<MetaProfil | { fehler: string }>;
  /** Alle Profile (Boards/Aggregation) — Lese-Snapshot. */
  alleProfile(): Promise<MetaProfil[]>;
}

export function createProfileStore(storage: Storage, clock: Clock): ProfileStore {
  // Op-Kette: ALLE Lese-Modifikations-Schreib-Zyklen laufen nacheinander.
  let kette: Promise<unknown> = Promise.resolve();
  function seriell<T>(op: () => Promise<T>): Promise<T> {
    const ergebnis = kette.then(op, op);
    kette = ergebnis.catch(() => undefined);
    return ergebnis;
  }

  async function lade(): Promise<ProfilDatei> {
    const daten = await storage.readJson<ProfilDatei>(DATEI);
    return daten ?? { schemaVersion: 1, profile: {} };
  }

  async function speichere(daten: ProfilDatei): Promise<void> {
    await storage.writeJsonAtomic(DATEI, daten);
  }

  function hatZugriff(profil: MetaProfil, zugriff: ProfilZugriff): boolean {
    // Eine EXPLIZIT eingegebene PIN wird IMMER wirklich geprüft — sonst wäre
    // der PIN-Dialog auf vertrautem Gerät eine Scheinprüfung (P1-Fix).
    if (profil.pinHash !== null && zugriff.pin !== undefined) {
      return pinHash(profil.profileId, zugriff.pin) === profil.pinHash;
    }
    if (zugriff.deviceToken && profil.deviceTokens.includes(zugriff.deviceToken)) return true;
    return profil.pinHash === null;
  }

  function bindeGeraet(profil: MetaProfil, deviceToken?: string): void {
    if (!deviceToken || profil.deviceTokens.includes(deviceToken)) return;
    profil.deviceTokens = [...profil.deviceTokens, deviceToken].slice(-MAX_DEVICE_TOKENS);
  }

  return {
    erstelle(opts) {
      return seriell(async () => {
        const daten = await lade();
        const profileId = `pr_${randomUUID().slice(0, 8)}`;
        // Willkommens-Paket (P2-Fix Null-AT-Einstieg): NUR das ERSTE Profil
        // pro Gerät — idempotent, weil der Token danach am Profil hängt.
        const erstesGeraeteProfil =
          opts.deviceToken !== undefined &&
          !Object.values(daten.profile).some((p) =>
            p.deviceTokens.includes(opts.deviceToken as string),
          );
        const profil: MetaProfil = {
          profileId,
          name: opts.name.slice(0, 24),
          avatar: avatarBasis(opts.avatar),
          pinHash: opts.pin && opts.pin.length >= 4 ? pinHash(profileId, opts.pin) : null,
          createdAt: clock.now(),
          deviceTokens: opts.deviceToken ? [opts.deviceToken] : [],
          at: erstesGeraeteProfil
            ? { gesamt: WILLKOMMEN_START_AT, verfuegbar: WILLKOMMEN_START_AT }
            : { gesamt: 0, verfuegbar: 0 },
          besitz: erstesGeraeteProfil ? [WILLKOMMEN_ITEM.id] : [],
          ausgeruestet: erstesGeraeteProfil ? { titel: WILLKOMMEN_ITEM.id } : {},
          ersteMale: {},
          gebuchteMatches: [],
        };
        daten.profile[profileId] = profil;
        await speichere(daten);
        return { ...profil };
      });
    },

    async liste(deviceToken) {
      const daten = await lade();
      // P1-Fix: NUR Profile mit DIESEM Geräte-Token — fremde Profile dürfen
      // auf geteilten Servern nie als „Willkommen zurück" auftauchen.
      const eigene = Object.values(daten.profile)
        .filter((p) => deviceToken !== undefined && p.deviceTokens.includes(deviceToken))
        .map((p) => ({
          profileId: p.profileId,
          name: p.name,
          avatar: anzeigeAvatar(p),
          titel: p.ausgeruestet.titel ? (itemFuer(p.ausgeruestet.titel)?.name ?? null) : null,
          level: levelFuerAt(p.at.gesamt),
          atVerfuegbar: p.at.verfuegbar,
          gesperrt: p.pinHash !== null,
          diesesGeraet: true,
        }));
      return eigene.sort((a, b) => b.level - a.level);
    },

    async hole(profileId) {
      const daten = await lade();
      const p = daten.profile[profileId];
      return p ? { ...p } : null;
    },

    login(profileId, zugriff) {
      return seriell(async () => {
        const daten = await lade();
        const profil = daten.profile[profileId];
        if (!profil) return { fehler: "profil-unbekannt" };
        if (!hatZugriff(profil, zugriff)) return { fehler: "pin-falsch" };
        bindeGeraet(profil, zugriff.deviceToken);
        await speichere(daten);
        return { ...profil };
      });
    },

    ladeNachName(name, zugriff) {
      return seriell(async () => {
        const daten = await lade();
        const gesucht = name.trim().toLowerCase();
        if (gesucht.length === 0) return { fehler: "profil-unbekannt" };
        const namensgleich = Object.values(daten.profile).filter(
          (p) => p.name.trim().toLowerCase() === gesucht,
        );
        if (namensgleich.length === 0) return { fehler: "profil-unbekannt" };
        const zugaenglich = namensgleich.filter((p) => hatZugriff(p, zugriff));
        if (zugaenglich.length === 0) return { fehler: "pin-falsch" };
        if (zugaenglich.length > 1) return { fehler: "name-mehrdeutig" };
        const profil = zugaenglich[0];
        bindeGeraet(profil, zugriff.deviceToken);
        await speichere(daten);
        return { ...profil };
      });
    },

    bucheMatch(matchId, buchungen) {
      return seriell(async () => {
        const daten = await lade();
        const ergebnisse: BuchungsErgebnis[] = [];
        for (const b of buchungen) {
          const profil = daten.profile[b.profileId];
          if (!profil) continue;
          if (profil.gebuchteMatches.includes(matchId)) continue; // Doppel-Buchungs-Schutz
          const vorher = profil.at.gesamt;
          profil.at = {
            gesamt: profil.at.gesamt + b.at,
            verfuegbar: profil.at.verfuegbar + b.at,
          };
          if (b.sieg) profil.ersteMale = { ...profil.ersteMale, sieg: true };
          profil.gebuchteMatches = [...profil.gebuchteMatches, matchId].slice(
            -MAX_GEBUCHTE_MATCHES,
          );
          ergebnisse.push({
            profileId: b.profileId,
            at: b.at,
            atGesamt: profil.at.gesamt,
            levelUp: levelUpZwischen(vorher, profil.at.gesamt),
          });
        }
        if (ergebnisse.length > 0) await speichere(daten);
        return ergebnisse;
      });
    },

    gutschrift(profileId, at) {
      return seriell(async () => {
        const daten = await lade();
        const profil = daten.profile[profileId];
        if (!profil || at <= 0) return null;
        const vorher = profil.at.gesamt;
        profil.at = {
          gesamt: profil.at.gesamt + at,
          verfuegbar: profil.at.verfuegbar + at,
        };
        await speichere(daten);
        return {
          profileId,
          at,
          atGesamt: profil.at.gesamt,
          levelUp: levelUpZwischen(vorher, profil.at.gesamt),
        };
      });
    },

    gewaehreItems(profileId, itemIds) {
      return seriell(async () => {
        const daten = await lade();
        const profil = daten.profile[profileId];
        if (!profil) return;
        const neue = itemIds.filter((id) => !profil.besitz.includes(id));
        if (neue.length === 0) return;
        profil.besitz = [...profil.besitz, ...neue];
        await speichere(daten);
      });
    },

    kaufe(profileId, itemId, zugriff) {
      return seriell(async () => {
        const daten = await lade();
        const profil = daten.profile[profileId];
        if (!profil) return { fehler: "profil-unbekannt" };
        if (!hatZugriff(profil, zugriff)) return { fehler: "pin-falsch" };
        const item = itemFuer(itemId);
        if (!item) return { fehler: "item-unbekannt" };
        // Level-Gate (§7.5): Pass-Exklusive sind NIE kaufbar, minLevel prüft
        // Lifetime-AT — Ausgeben senkt das Level nie, das Gate bleibt offen.
        const sperre = kaufSperre(item, profil.at.gesamt);
        if (sperre !== null) return { fehler: sperre };
        // Spenden-Badge ist mehrfach kaufbar (AT-Senke) — alles andere nur 1×.
        if (item.typ !== "badge" && profil.besitz.includes(itemId)) {
          return { fehler: "schon-gekauft" };
        }
        if (profil.at.verfuegbar < item.preis) return { fehler: "zu-wenig-at" };
        profil.at = { ...profil.at, verfuegbar: profil.at.verfuegbar - item.preis };
        if (!profil.besitz.includes(itemId)) profil.besitz = [...profil.besitz, itemId];
        bindeGeraet(profil, zugriff.deviceToken);
        await speichere(daten);
        return { ...profil };
      });
    },

    ruesteAus(profileId, slot, itemId, zugriff) {
      return seriell(async () => {
        const daten = await lade();
        const profil = daten.profile[profileId];
        if (!profil) return { fehler: "profil-unbekannt" };
        if (!hatZugriff(profil, zugriff)) return { fehler: "pin-falsch" };
        if (itemId !== null) {
          // itemFuer kennt auch Saison-Exklusive (via Pass verdient ⇒ anlegbar).
          const item = itemFuer(itemId);
          if (!item) return { fehler: "item-unbekannt" };
          if (item.slot !== slot) return { fehler: "falscher-slot" };
          if (!profil.besitz.includes(itemId)) return { fehler: "nicht-im-besitz" };
        }
        const ausgeruestet: ProfilAusruestung = { ...profil.ausgeruestet };
        if (itemId === null) delete ausgeruestet[slot as keyof ProfilAusruestung];
        else ausgeruestet[slot as keyof ProfilAusruestung] = itemId;
        profil.ausgeruestet = ausgeruestet;
        await speichere(daten);
        return { ...profil };
      });
    },

    aktualisiere(profileId, patch, zugriff) {
      return seriell(async () => {
        const daten = await lade();
        const profil = daten.profile[profileId];
        if (!profil) return { fehler: "profil-unbekannt" };
        if (!hatZugriff(profil, zugriff)) return { fehler: "pin-falsch" };
        if (patch.name !== undefined && patch.name.length > 0) {
          profil.name = patch.name.slice(0, 24);
        }
        if (patch.avatar !== undefined) profil.avatar = avatarBasis(patch.avatar);
        if (patch.pin !== undefined) {
          profil.pinHash =
            patch.pin === null || patch.pin.length < 4 ? null : pinHash(profileId, patch.pin);
        }
        await speichere(daten);
        return { ...profil };
      });
    },

    async alleProfile() {
      const daten = await lade();
      return Object.values(daten.profile).map((p) => ({ ...p }));
    },
  };
}
