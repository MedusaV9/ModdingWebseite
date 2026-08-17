// Quest-Store (Meta-Agent 2): Daily-/Monats-Quest-Fortschritt pro Profil,
// persistiert als EINE atomare Datei (meta/quests.json). Fortschritt wird
// SERVER-seitig beim matchBeendet-Hook aus den Match-Fakten gebucht
// (shared/quests.ts#matchFakten liest sie aus dem Event-Log) — idempotent pro
// matchId. Tages-/Saison-Rollover passiert lazy beim nächsten Kontakt:
// Dailies rotieren per Datum (3 aus ~20), Monats-Quests hängen an der Saison.
import {
  QUEST_MAP,
  dailyQuestIdsFuer,
  monatsQuestIdsFuer,
  saisonIdFuer,
  tagKeyFuer,
  type MatchFakten,
  type QuestDef,
} from "../../shared/quests";
import type { Clock } from "../../shared/time";
import type { Storage } from "../persistence/storage";

const DATEI = "meta/quests.json";
const MAX_GEBUCHTE_MATCHES = 50;

export interface QuestStand {
  fortschritt: number;
  fertig: boolean;
}

interface QuestProfil {
  tagKey: string;
  daily: Record<string, QuestStand>;
  saisonId: string;
  monat: Record<string, QuestStand>;
  gebuchteMatches: string[];
}

interface QuestDatei {
  schemaVersion: 1;
  profile: Record<string, QuestProfil>;
}

/** Was hat EIN Match an einer Quest bewegt? (Anzeige „Daily 2/3 ✓ +80 XP"). */
export interface QuestDelta {
  questId: string;
  art: "daily" | "monat";
  text: string;
  ziel: number;
  vorher: number;
  nachher: number;
  /** JETZT abgeschlossen ⇒ XP-Gutschrift (einmalig). */
  fertigJetzt: boolean;
  xp: number;
}

export interface QuestAnzeige {
  questId: string;
  art: "daily" | "monat";
  text: string;
  ziel: number;
  fortschritt: number;
  fertig: boolean;
  xp: number;
}

export interface QuestService {
  /** Match-Fakten in die aktiven Quests buchen — idempotent pro matchId. */
  verbucheMatch(
    matchId: string,
    profileId: string,
    fakten: MatchFakten,
  ): Promise<{ deltas: QuestDelta[]; xp: number }>;
  /** m-pass-15: Fortschritt = erreichte Pass-Stufe (nach XP-Buchung rufen). */
  aktualisierePassStufe(profileId: string, stufe: number): Promise<QuestDelta | null>;
  /** Aktive Quests + Fortschritt (Landing-Tab + Handy-Anzeige). */
  stand(profileId: string): Promise<{ tagKey: string; saisonId: string; quests: QuestAnzeige[] }>;
}

function leeresProfil(tagKey: string, saisonId: string): QuestProfil {
  return { tagKey, daily: {}, saisonId, monat: {}, gebuchteMatches: [] };
}

/** Tages-/Saison-Rollover (mutiert p): neue Rotation = frischer Fortschritt. */
function rolle(p: QuestProfil, tagKey: string, saisonId: string): void {
  if (p.tagKey !== tagKey) {
    p.tagKey = tagKey;
    p.daily = {};
  }
  if (p.saisonId !== saisonId) {
    p.saisonId = saisonId;
    p.monat = {};
  }
}

function aktiveQuests(
  p: QuestProfil,
): { def: QuestDef; stand: QuestStand; art: "daily" | "monat" }[] {
  const liste: { def: QuestDef; stand: QuestStand; art: "daily" | "monat" }[] = [];
  for (const id of dailyQuestIdsFuer(p.tagKey)) {
    const def = QUEST_MAP.get(id);
    if (!def) continue;
    liste.push({ def, stand: (p.daily[id] ??= { fortschritt: 0, fertig: false }), art: "daily" });
  }
  for (const id of monatsQuestIdsFuer(p.saisonId)) {
    const def = QUEST_MAP.get(id);
    if (!def) continue;
    liste.push({ def, stand: (p.monat[id] ??= { fortschritt: 0, fertig: false }), art: "monat" });
  }
  return liste;
}

export function createQuestService(storage: Storage, clock: Clock): QuestService {
  let kette: Promise<unknown> = Promise.resolve();
  function seriell<T>(op: () => Promise<T>): Promise<T> {
    const ergebnis = kette.then(op, op);
    kette = ergebnis.catch(() => undefined);
    return ergebnis;
  }

  async function lade(): Promise<QuestDatei> {
    const daten = await storage.readJson<QuestDatei>(DATEI);
    return daten ?? { schemaVersion: 1, profile: {} };
  }

  function profilVon(daten: QuestDatei, profileId: string): QuestProfil {
    const tagKey = tagKeyFuer(clock.now());
    const saisonId = saisonIdFuer(clock.now());
    const p = (daten.profile[profileId] ??= leeresProfil(tagKey, saisonId));
    rolle(p, tagKey, saisonId);
    return p;
  }

  return {
    verbucheMatch(matchId, profileId, fakten) {
      return seriell(async () => {
        const daten = await lade();
        const p = profilVon(daten, profileId);
        if (p.gebuchteMatches.includes(matchId)) return { deltas: [], xp: 0 };
        p.gebuchteMatches = [...p.gebuchteMatches, matchId].slice(-MAX_GEBUCHTE_MATCHES);

        const deltas: QuestDelta[] = [];
        let xp = 0;
        for (const { def, stand } of aktiveQuests(p)) {
          const zuwachs = stand.fertig ? 0 : Math.max(0, def.misst(fakten));
          if (zuwachs === 0) continue;
          const vorher = stand.fortschritt;
          stand.fortschritt = Math.min(def.ziel, vorher + zuwachs);
          const fertigJetzt = !stand.fertig && stand.fortschritt >= def.ziel;
          if (fertigJetzt) {
            stand.fertig = true;
            xp += def.xp;
          }
          deltas.push({
            questId: def.id,
            art: def.art,
            text: def.text,
            ziel: def.ziel,
            vorher,
            nachher: stand.fortschritt,
            fertigJetzt,
            xp: fertigJetzt ? def.xp : 0,
          });
        }
        await storage.writeJsonAtomic(DATEI, daten);
        return { deltas, xp };
      });
    },

    aktualisierePassStufe(profileId, stufe) {
      return seriell(async () => {
        const daten = await lade();
        const p = profilVon(daten, profileId);
        const def = QUEST_MAP.get("m-pass-15");
        if (!def || !monatsQuestIdsFuer(p.saisonId).includes(def.id)) return null;
        const stand = (p.monat[def.id] ??= { fortschritt: 0, fertig: false });
        const vorher = stand.fortschritt;
        const neu = Math.min(def.ziel, Math.max(vorher, stufe));
        if (neu === vorher) return null;
        stand.fortschritt = neu;
        const fertigJetzt = !stand.fertig && neu >= def.ziel;
        if (fertigJetzt) stand.fertig = true;
        await storage.writeJsonAtomic(DATEI, daten);
        return {
          questId: def.id,
          art: def.art,
          text: def.text,
          ziel: def.ziel,
          vorher,
          nachher: neu,
          fertigJetzt,
          xp: fertigJetzt ? def.xp : 0,
        };
      });
    },

    async stand(profileId) {
      const daten = await lade();
      const p = profilVon(daten, profileId);
      return {
        tagKey: p.tagKey,
        saisonId: p.saisonId,
        quests: aktiveQuests(p).map(({ def, stand, art }) => ({
          questId: def.id,
          art,
          text: def.text,
          ziel: def.ziel,
          fortschritt: stand.fortschritt,
          fertig: stand.fertig,
          xp: def.xp,
        })),
      };
    },
  };
}
