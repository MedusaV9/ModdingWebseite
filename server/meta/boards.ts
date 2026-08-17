// Bestenlisten (GAME-DESIGN §7.3, GENAU 4) + Profil-Karte (§7.1) als pure
// Ableitungen aus Profil-Store + materialisierten Aggregaten — vollständig
// aus synthetischen Daten testbar (kein IO, keine Uhr).
import {
  BOARD_SCHWELLEN,
  SHOP_ITEM_MAP,
  levelFuerAt,
  lieblingsUndNemesis,
  medianAusBuckets,
  type BoardEintrag,
  type Boards,
  type MetaProfil,
  type ProfilKarte,
  type ProfilStats,
} from "../../shared/meta";
import { anzeigeAvatar } from "./profile-store";

function eintrag(profil: MetaProfil, wert: number, anzeige: string, extra?: string): BoardEintrag {
  return {
    profileId: profil.profileId,
    name: profil.name,
    avatar: anzeigeAvatar(profil),
    titel: profil.ausgeruestet.titel
      ? (SHOP_ITEM_MAP.get(profil.ausgeruestet.titel)?.name ?? null)
      : null,
    wert,
    anzeige,
    ...(extra !== undefined ? { extra } : {}),
  };
}

function prozent(quote: number): string {
  return `${Math.round(quote * 100)} %`;
}

/** Beste Kategorie eines Profils (≥ Schwelle Antworten in der Kategorie). */
function besteKategorie(stats: ProfilStats): { kategorie: string; quote: number } | null {
  const { lieblings } = lieblingsUndNemesis(stats.matrix);
  return lieblings;
}

/**
 * Die 4 Boards bauen: Money-Boss (Lifetime-AT), Kategorie-Meister (beste
 * Quote je Kategorie, ≥ 20 Antworten), Blitz-Buzzer (MEDIAN-Zeit, ≥ 30
 * Antworten — kein Glücks-Bestwert!), Comeback-König (Win-Rate nur aus
 * Matches ohne Führung vor dem Finale, ≥ 5 solcher Matches).
 */
export function baueBoards(
  profile: MetaProfil[],
  stats: Record<string, ProfilStats>,
  topN = 10,
): Boards {
  const moneyBoss: BoardEintrag[] = profile
    .filter((p) => p.at.gesamt > 0)
    .map((p) => eintrag(p, p.at.gesamt, `${p.at.gesamt.toLocaleString("de-DE")} AT`))
    .sort((a, b) => b.wert - a.wert)
    .slice(0, topN);

  const kategorieMeister: BoardEintrag[] = [];
  const blitzBuzzer: BoardEintrag[] = [];
  const comebackKoenig: BoardEintrag[] = [];

  for (const p of profile) {
    const s = stats[p.profileId];
    if (!s) continue;

    const beste = besteKategorie(s);
    if (beste !== null) {
      kategorieMeister.push(eintrag(p, beste.quote, prozent(beste.quote), beste.kategorie));
    }

    const gewertet = s.zeitBuckets.reduce((a, b) => a + b, 0);
    if (gewertet >= BOARD_SCHWELLEN.blitzBuzzer) {
      const median = medianAusBuckets(s.zeitBuckets);
      if (median !== null) {
        blitzBuzzer.push(eintrag(p, median, `${(median / 1000).toFixed(1)} s`, `${gewertet}×`));
      }
    }

    if (s.comebackMatches >= BOARD_SCHWELLEN.comebackKoenig) {
      const rate = s.comebackSiege / s.comebackMatches;
      comebackKoenig.push(
        eintrag(p, rate, prozent(rate), `${s.comebackSiege}/${s.comebackMatches}`),
      );
    }
  }

  kategorieMeister.sort((a, b) => b.wert - a.wert);
  blitzBuzzer.sort((a, b) => a.wert - b.wert); // schneller = besser
  comebackKoenig.sort((a, b) => b.wert - a.wert);

  return {
    moneyBoss,
    kategorieMeister: kategorieMeister.slice(0, topN),
    blitzBuzzer: blitzBuzzer.slice(0, topN),
    comebackKoenig: comebackKoenig.slice(0, topN),
  };
}

/** Persönlicher Fortschritt zu den Board-Schwellen (§7.3-Fix: „Noch 2 Matches
 * bis zur Wertung" statt leerer Boards für neue Gruppen). Pure Ableitung. */
export interface BoardFortschritt {
  moneyBoss: { ist: number; schwelle: number };
  kategorieMeister: { ist: number; schwelle: number };
  blitzBuzzer: { ist: number; schwelle: number };
  comebackKoenig: { ist: number; schwelle: number };
}

export function baueBoardFortschritt(
  profil: MetaProfil,
  stats: ProfilStats | null,
): BoardFortschritt {
  // Kategorie-Meister: die meisten Antworten in EINER Kategorie zählen.
  const proKategorie = new Map<string, number>();
  for (const [key, zelle] of Object.entries(stats?.matrix ?? {})) {
    const kategorie = key.split("|")[0];
    proKategorie.set(kategorie, (proKategorie.get(kategorie) ?? 0) + zelle.n);
  }
  const meisteAntworten = Math.max(0, ...proKategorie.values());
  const gewertet = (stats?.zeitBuckets ?? []).reduce((a, b) => a + b, 0);
  return {
    moneyBoss: { ist: profil.at.gesamt, schwelle: 1 },
    kategorieMeister: { ist: meisteAntworten, schwelle: BOARD_SCHWELLEN.kategorieMeister },
    blitzBuzzer: { ist: gewertet, schwelle: BOARD_SCHWELLEN.blitzBuzzer },
    comebackKoenig: {
      ist: stats?.comebackMatches ?? 0,
      schwelle: BOARD_SCHWELLEN.comebackKoenig,
    },
  };
}

/** Profil-Karte (§7.1): Lieblings-/Nemesis-Kategorie + Bestleistungen. */
export function baueProfilKarte(profil: MetaProfil, stats: ProfilStats | null): ProfilKarte {
  const kategorien = stats ? lieblingsUndNemesis(stats.matrix) : { lieblings: null, nemesis: null };
  return {
    profileId: profil.profileId,
    name: profil.name,
    avatar: anzeigeAvatar(profil),
    titel: profil.ausgeruestet.titel
      ? (SHOP_ITEM_MAP.get(profil.ausgeruestet.titel)?.name ?? null)
      : null,
    level: levelFuerAt(profil.at.gesamt),
    at: { ...profil.at },
    lieblingsKategorie: kategorien.lieblings,
    nemesisKategorie: kategorien.nemesis,
    schnellsteAntwortMs: stats?.schnellsteAntwortMs ?? null,
    hoechsterMatchGewinn: stats?.besterEndstand ?? 0,
    laengsteSerie: stats?.laengsteSerie ?? 0,
    matches: stats?.matches ?? 0,
    siege: stats?.siege ?? 0,
    gesperrt: profil.pinHash !== null,
  };
}
