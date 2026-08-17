// META-Service (Glue): bindet Profile, AT-Buchung, Bots, Save/Load und
// Analytics an Räume + HTTP. Implementiert die RoomMetaHooks aus room.ts —
// Räume kennen NUR den Vertrag, der Service kennt die Stores. Alle Hooks sind
// fire-and-forget-sicher: Meta-Fehler dürfen NIE ein laufendes Match reißen.
import { atFuerEndstand } from "../../shared/economy";
import type { Rng, StatefulRng } from "../../shared/rng";
import type { Clock } from "../../shared/time";
import { levelFuerAt, type ProfilKarte } from "../../shared/meta";
import {
  PASS_STUFEN,
  XP_MATCH,
  XP_SIEG,
  itemFuer,
  leereFakten,
  matchFakten,
  passBelohnungen,
  saisonEndeMs,
  saisonIdFuer,
  saisonName,
  xpKumulativFuerStufe,
  type PassBelohnung,
  type QuestFrageInfo,
} from "../../shared/quests";
import { createAggregator, parseZeilen, type Aggregator } from "../analytics/aggregate";
import { baueReports, type AdminReports, type KatalogEintrag } from "../analytics/reports";
import type { ContentLoader } from "../content-loader/index";
import type { Storage } from "../persistence/storage";
import type { Room, RoomMetaHooks } from "../rooms/room";
import { createBotManager, type BotManager } from "./bots";
import { baueBoardFortschritt, baueBoards, baueProfilKarte, type BoardFortschritt } from "./boards";
import { createJubilaeenStore, type JubilaeenStore } from "./jubilaeen";
import type { LevelUp } from "./level";
import { createModerationStore, moderierePickQuestions, type ModerationStore } from "./moderation";
import { createPracticeService, type PracticeService } from "./practice";
import {
  anzeigeAvatar,
  createProfileStore,
  type AtBuchung,
  type BuchungsErgebnis,
  type ProfileStore,
} from "./profile-store";
import {
  createQuestService,
  type QuestAnzeige,
  type QuestDelta,
  type QuestService,
} from "./quests";
import { createSaveStore, AUTOSAVE_SLOT, SAVE_SLOTS, type SaveStore } from "./save-store";
import { createSeasonStore, type PassArchivEintrag, type SeasonStore } from "./season";

export interface MetaDeps {
  storage: Storage;
  clock: Clock;
  rng: Rng;
  contentLoader: ContentLoader;
}

/** Raum-Umschlüsselung (Save/Load) — wird vom RoomManager nachgereicht. */
export type RekeyFn = (room: Room, neuerCode: string) => { ok: boolean; error?: string };

/** Match-Ende-Meta pro Profil: Level-Up + Pass-XP + Quest-Fortschritte —
 * gepuffert fürs Handy-Polling (Match-Ende-Screen „Daily 2/3 ✓ +80 XP!"). */
export interface MatchMetaErgebnis {
  matchId: string;
  ts: number;
  profileId: string;
  /** AT aus DIESEM Match (ohne Pass-Boni). */
  at: number;
  atGesamt: number;
  level: number;
  /** Level-Up durch dieses Match inkl. Pass-AT-Boni — null wenn keins. */
  levelUp: LevelUp | null;
  /** Gesamtes Pass-XP dieses Matches (Basis + Sieg + Quest-Abschlüsse). */
  xp: number;
  stufeVorher: number;
  stufeNeu: number;
  saisonId: string;
  /** Durch dieses Match neu erreichte Pass-Belohnungen. */
  belohnungen: PassBelohnung[];
  /** Quest-Bewegungen dieses Matches (Anzeige-Deltas). */
  quests: QuestDelta[];
}

/** Landing-Tab „Pass & Quests": alles für EINE Ansicht in EINEM Read. */
export interface PassUebersicht {
  saison: { id: string; name: string; endetTs: number; stufen: number };
  xp: number;
  stufe: number;
  atBonus: number;
  /** Kumulatives XP der aktuellen/nächsten Stufe (Fortschritts-Balken). */
  stufeAbXp: number;
  naechsteAbXp: number | null;
  belohnungen: {
    stufe: number;
    art: "at" | "item";
    at?: number;
    item?: {
      id: string;
      name: string;
      emoji: string;
      typ: string;
      slot: string;
      beschreibung: string;
    };
    erreicht: boolean;
  }[];
  tagKey: string;
  quests: QuestAnzeige[];
  archiv: PassArchivEintrag[];
}

/** Fehlerhaft-Queue-Zeile MIT Moderations-Status (Admin-Fix W20): Flags nach
 * „Entkräften" ausgeblendet, Quarantäne/Geprüft-Zustand sichtbar. */
export interface FehlerhaftModZeile {
  questionId: string;
  text: string;
  anzahl: number;
  flags: { grund: string; ts: number; matchId: string }[];
  /** Anzeige-Empfehlung ab 2 aktiven Flags — sperrt NICHT automatisch. */
  ausRotationEmpfohlen: boolean;
  /** true = per Admin-Aktion wirklich aus der Match-Rotation genommen. */
  quarantaene: boolean;
  geprueftTs: number | null;
}

export type AdminReportsMod = Omit<AdminReports, "fehlerhaft"> & {
  fehlerhaft: FehlerhaftModZeile[];
};

export interface MetaService extends RoomMetaHooks {
  readonly profile: ProfileStore;
  readonly practice: PracticeService;
  readonly saves: SaveStore;
  readonly bots: BotManager;
  readonly aggregator: Aggregator;
  /** Fragen-Moderation (Quarantäne/Entkräften/Geprüft) — Admin-Aktionen. */
  readonly moderation: ModerationStore;
  /** v2 Jubiläums-Erkennung: Gruppen-Meilensteine (10./25./50. Abend, 100k). */
  readonly jubilaeen: JubilaeenStore;
  /** Bananen-Pass (Saison-XP/Stufen) + Quest-Fortschritt (Meta-Agent 2). */
  readonly season: SeasonStore;
  readonly quests: QuestService;
  /** Nach Manager-Erzeugung anbinden (Save/Load braucht die Umschlüsselung). */
  verbindeManager(rekey: RekeyFn): void;
  /** Crash-Schutz (Eval-7 P1): beim Server-Boot Räume mit frischem Autosave
   * (< 10 min) automatisch wiederherstellen — Spieler-Tokens resumen nahtlos.
   * Stale Autosaves werden dabei aufgeräumt (reiner Crash-Schutz, kein Archiv). */
  bootWiederbelebung(fabrik: {
    erzeuge(): Room | null;
    verwerfe(room: Room): void;
  }): Promise<{ code: string; phase: string; frageNr: number; alterMs: number }[]>;
  profilKarte(profileId: string): Promise<ProfilKarte | null>;
  boards(): Promise<ReturnType<typeof baueBoards>>;
  /** Persönlicher Fortschritt zu den Board-Schwellen („Noch 2 bis zur Wertung"). */
  boardFortschritt(profileId: string): Promise<BoardFortschritt | null>;
  reports(refresh: boolean): Promise<AdminReportsMod>;
  /** Letztes Match-Ende-Meta eines Profils (Handy-Polling nach Match-Ende). */
  matchErgebnis(profileId: string): MatchMetaErgebnis | null;
  /** Pass-Leiste + Quest-Karten + Archiv für den Landing-Tab. */
  passUebersicht(profileId: string): Promise<PassUebersicht>;
  /** Match-Ende-Meta verbuchen (Pass-XP + Quests) — wartet aufs Event-Log.
   * Öffentlich für Tests/Regression; matchBeendet feuert sie fire-and-forget. */
  verbucheMatchMeta(
    matchId: string,
    ergebnisse: BuchungsErgebnis[],
    buchungen: AtBuchung[],
  ): Promise<MatchMetaErgebnis[]>;
}

function istStateful(rng: Rng): rng is StatefulRng {
  return typeof (rng as StatefulRng).getState === "function";
}

export function createMetaService(deps: MetaDeps): MetaService {
  const { storage, clock, rng, contentLoader } = deps;

  // Fragen-Katalog (Id → Metadaten) — für Aggregation + Reports; lazy, weil
  // der Loader beim Service-Bau noch keine Packs geladen hat.
  let katalogCache: Map<string, KatalogEintrag> | null = null;
  const katalog = (): Map<string, KatalogEintrag> => {
    if (katalogCache === null) {
      katalogCache = new Map(
        contentLoader.alleFragen().map((k) => [
          k.frage.id,
          {
            text: k.frage.text,
            kategorie: k.frage.category,
            oberkategorie: k.oberkategorie,
            schwierigkeit: k.frage.difficulty,
          },
        ]),
      );
    }
    return katalogCache;
  };

  const profile = createProfileStore(storage, clock);
  // Ruhefenster: Abspann-Feedback (nach match_ended) noch mitnehmen.
  const AGGREGATIONS_RUHE_MS = 90_000;
  const aggregator = createAggregator(
    storage,
    (qid) => {
      const info = katalog().get(qid);
      return info ? { kategorie: info.kategorie, schwierigkeit: info.schwierigkeit } : null;
    },
    () => clock.now(),
    AGGREGATIONS_RUHE_MS,
  );
  // Fragen-Moderation (Admin-Aktionen): Cache füllen + Quarantäne-Sperre
  // in-place an den geteilten Loader hängen — wirkt auf Match-Rotation UND
  // (über istGesperrt) aufs Training, ohne Wiring-Änderung in core/.
  const moderation = createModerationStore(storage, clock);
  void moderation
    .ladeInitial()
    .catch((err) => console.error("Moderation-Laden fehlgeschlagen:", err));
  moderierePickQuestions(contentLoader, moderation);
  const practice = createPracticeService(storage, contentLoader, rng, clock, (qid) =>
    moderation.istGesperrt(qid),
  );
  const saves = createSaveStore(storage, clock);
  const bots = createBotManager(rng);
  // v2 Jubiläen: Cache sofort füllen — der Match-Start-Lookup ist synchron.
  const jubilaeen = createJubilaeenStore(storage);
  void jubilaeen.ladeInitial().catch((err) => console.error("Jubiläen-Laden fehlgeschlagen:", err));
  // Bananen-Pass + Quests (Meta-Agent 2): eigene Stores, gleiche Storage-Wurzel.
  const season = createSeasonStore(storage, clock);
  const quests = createQuestService(storage, clock);
  // Match-Ende-Meta-Puffer: profileId → letztes Ergebnis (Handy pollt kurz nach
  // Match-Ende; in-memory reicht — nach Neustart fehlt nur die EINE Einblendung).
  const matchMetaPuffer = new Map<string, MatchMetaErgebnis>();
  const MAX_MATCH_META = 200;

  const questFrageInfo = (qid: string): QuestFrageInfo | null => {
    const info = katalog().get(qid);
    return info
      ? {
          kategorie: info.kategorie,
          oberkategorie: info.oberkategorie,
          schwierigkeit: info.schwierigkeit,
        }
      : null;
  };

  /** Event-Log lesen, bis match_ended drinsteht (append-Kette ist async). */
  async function leseMatchZeilen(matchId: string): Promise<ReturnType<typeof parseZeilen>> {
    for (let versuch = 0; versuch < 10; versuch++) {
      const text = await storage.readText(`events/${matchId}.jsonl`);
      if (text !== null) {
        const zeilen = parseZeilen(text);
        if (zeilen.some((z) => z.type === "match_ended")) return zeilen;
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    return [];
  }

  /** Pass-Belohnungen einlösen: Items in den Besitz, AT-Boni als Einnahme. */
  async function loeseBelohnungenEin(
    profileId: string,
    belohnungen: PassBelohnung[],
  ): Promise<{ atGesamt: number | null; levelUp: LevelUp | null }> {
    const itemIds = belohnungen.flatMap((b) =>
      b.art === "item" && b.itemId !== undefined ? [b.itemId] : [],
    );
    if (itemIds.length > 0) await profile.gewaehreItems(profileId, itemIds);
    const atBonus = belohnungen.reduce((s, b) => s + (b.art === "at" ? (b.at ?? 0) : 0), 0);
    if (atBonus <= 0) return { atGesamt: null, levelUp: null };
    const g = await profile.gutschrift(profileId, atBonus);
    return { atGesamt: g?.atGesamt ?? null, levelUp: g?.levelUp ?? null };
  }

  async function verbucheMatchMeta(
    matchId: string,
    ergebnisse: BuchungsErgebnis[],
    buchungen: AtBuchung[],
  ): Promise<MatchMetaErgebnis[]> {
    if (ergebnisse.length === 0) return [];
    const zeilen = await leseMatchZeilen(matchId);
    const fakten = matchFakten(zeilen, questFrageInfo);
    const alle: MatchMetaErgebnis[] = [];
    for (const e of ergebnisse) {
      const buchung = buchungen.find((b) => b.profileId === e.profileId);
      // Fallback ohne Log (verspäteter Flush): Basis-Fakten aus der AT-Buchung.
      const f = fakten.get(e.profileId) ?? {
        ...leereFakten(),
        endstand: buchung?.endstand ?? 0,
        sieg: buchung?.sieg ?? false,
      };
      // 1) Quests verbuchen (idempotent pro matchId) ⇒ Quest-XP.
      const quest = await quests.verbucheMatch(matchId, e.profileId, f);
      let deltas = quest.deltas;
      let xpGesamt = XP_MATCH + (f.sieg ? XP_SIEG : 0) + quest.xp;
      // 2) Pass-XP gutschreiben ⇒ neue Stufen + Belohnungen.
      const erg = await season.gibXp(e.profileId, xpGesamt);
      let belohnungen = erg.belohnungen;
      let stufeNeu = erg.stufeNeu;
      // 3) Monats-Quest „Erreiche Pass-Stufe 15" nachziehen — deren Abschluss
      // gibt selbst XP (einmalig), also EINE zweite Runde.
      const passDelta = await quests.aktualisierePassStufe(e.profileId, stufeNeu);
      if (passDelta !== null) {
        deltas = [...deltas, passDelta];
        if (passDelta.xp > 0) {
          xpGesamt += passDelta.xp;
          const nachschlag = await season.gibXp(e.profileId, passDelta.xp);
          belohnungen = [...belohnungen, ...nachschlag.belohnungen];
          stufeNeu = nachschlag.stufeNeu;
        }
      }
      // 4) Belohnungen einlösen (Items + AT-Boni — Boni füttern das Level).
      const einloesung = await loeseBelohnungenEin(e.profileId, belohnungen);
      const atGesamt = einloesung.atGesamt ?? e.atGesamt;
      const levelUp: LevelUp | null =
        e.levelUp !== null || einloesung.levelUp !== null
          ? {
              von: e.levelUp?.von ?? einloesung.levelUp?.von ?? 0,
              zu: einloesung.levelUp?.zu ?? e.levelUp?.zu ?? 0,
            }
          : null;
      const meta: MatchMetaErgebnis = {
        matchId,
        ts: clock.now(),
        profileId: e.profileId,
        at: e.at,
        atGesamt,
        level: levelFuerAt(atGesamt),
        levelUp,
        xp: xpGesamt,
        stufeVorher: erg.stufeVorher,
        stufeNeu,
        saisonId: saisonIdFuer(clock.now()),
        belohnungen,
        quests: deltas,
      };
      matchMetaPuffer.delete(e.profileId);
      matchMetaPuffer.set(e.profileId, meta);
      alle.push(meta);
    }
    // Puffer begrenzen (älteste zuerst raus — Map hält Einfüge-Reihenfolge).
    while (matchMetaPuffer.size > MAX_MATCH_META) {
      const aeltester = matchMetaPuffer.keys().next().value;
      if (aeltester === undefined) break;
      matchMetaPuffer.delete(aeltester);
    }
    return alle;
  }

  /** Gebundene Profil-Ids der Spieler eines Raums (Basis der Gruppen-Erkennung). */
  const gebundeneProfile = (room: Room): string[] =>
    room.state.order.flatMap((pid) => {
      const profileId = room.profilBindungen.get(pid);
      return profileId !== undefined ? [profileId] : [];
    });

  let rekey: RekeyFn | null = null;

  /** Aggregation nach dem Match-Ende anstoßen: einmal kurz nach dem
   * Event-Log-Flush (fängt ALTE, bereits ruhende Logs) und einmal ~95 s
   * später — direkt nach Ablauf des Ruhefensters, damit die Profil-Karte
   * OHNE manuellen Trigger binnen ≤2 min echte Match-Stats zeigt (P1-Fix).
   * unref(): Timer dürfen weder Tests noch den Prozess-Exit blockieren —
   * optional gerufen, denn im Browser-Host (Standalone-Meta, W4) liefert
   * setTimeout eine Zahl ohne unref. */
  function aggregationSpaeter(): void {
    const spaeter = (ms: number): void => {
      const timer = setTimeout(() => void aggregator.aktualisiere().catch(() => undefined), ms) as {
        unref?: () => void;
      };
      timer.unref?.();
    };
    spaeter(2000);
    spaeter(AGGREGATIONS_RUHE_MS + 5000);
  }

  function saveVon(room: Room, slot: number): Parameters<SaveStore["schreibe"]>[0] {
    return {
      slot,
      roomCode: room.code,
      gmPin: room.gmPin,
      matchId: room.matchId,
      seq: room.seq,
      engineState: room.state,
      rngState: istStateful(rng) ? rng.getState() : null,
      sessions: room.sessions.alle(),
      profilBindungen: Object.fromEntries(room.profilBindungen),
      bots: bots.botsVon(room),
    };
  }

  const LAUFENDE_PHASEN = new Set(["lobby", "ende"]);
  const matchLaeuft = (room: Room): boolean => !LAUFENDE_PHASEN.has(room.state.phase);

  // ---------- Crash-Schutz: periodischer Autosave + Boot-Wiederbelebung ----------

  /** Autosave-Takt (~30 s): Bei SIGKILL gehen höchstens 30 s Match verloren. */
  const AUTOSAVE_INTERVALL_MS = 30_000;
  /** Nur FRISCHE Autosaves werden beim Boot wiederbelebt (ältere = Abend vorbei). */
  const BOOT_AUTOSAVE_MAX_ALTER_MS = 10 * 60_000;
  /** Drossel-Stand pro Raum: Zeitpunkt + seq des letzten Autosaves. */
  const autosaveStand = new WeakMap<Room, { ts: number; seq: number }>();

  async function schreibeSave(room: Room, slot: number): Promise<{ ok: boolean; error?: string }> {
    if (!matchLaeuft(room)) return { ok: false, error: "kein-laufendes-match" };
    await saves.schreibe(saveVon(room, slot));
    return { ok: true };
  }

  async function ladeSave(room: Room, slot: number): Promise<{ ok: boolean; error?: string }> {
    if (room.state.phase !== "lobby") return { ok: false, error: "nur-in-lobby" };
    if (rekey === null) return { ok: false, error: "kein-manager" };
    const save = await saves.lade(slot);
    if (!save) return { ok: false, error: "slot-leer" };
    // Raum auf den GESPEICHERTEN Code umschlüsseln: Spieler finden Join-URL
    // (/j/CODE) und Session-Token (localStorage mm:CODE) unverändert wieder.
    const umgeschluesselt = rekey(room, save.roomCode);
    if (!umgeschluesselt.ok) return umgeschluesselt;
    room.uebernimmSave(save);
    // Determinismus: Rng-Zustand des Save-Zeitpunkts wiederherstellen.
    if (save.rngState !== null && istStateful(rng)) rng.setState(save.rngState);
    bots.restauriere(room, save.bots);
    room.broadcastSnapshots();
    return { ok: true };
  }

  return {
    profile,
    practice,
    saves,
    bots,
    aggregator,
    moderation,
    jubilaeen,
    season,
    quests,
    verbucheMatchMeta,

    verbindeManager(fn) {
      rekey = fn;
    },

    // ---------- RoomMetaHooks ----------

    matchGestartet(room) {
      // v2 Jubiläums-Erkennung: Gruppen-Meilenstein fürs Opening (synchron).
      return jubilaeen.fuerMatchStart(gebundeneProfile(room));
    },

    async profilJoin(profileId, zugriff) {
      const r = await profile.login(profileId, zugriff);
      if ("fehler" in r) return { ok: false, error: r.fehler };
      // Anzeige-Avatar = Basis + ausgerüstete Extras (Wire-Format-Erweiterung,
      // parseAvatar der Alt-Clients liest weiterhin nur "affe.farbe").
      // staerke = Lifetime-AT: Basis der Team-Auto-Balance (GAME-DESIGN §1.4).
      return { ok: true, name: r.name, avatar: anzeigeAvatar(r), staerke: r.at.gesamt };
    },

    matchBeendet(room) {
      // Platzierungen aus dem End-State; die AT-Formel (§3.6) rechnet economy.
      // Die Engine-Siegerehrung hat Vorrang: sie kennt Shake-Tiebreaks UND den
      // Team-Modus (Team-Sieger-Bonus für ALLE Mitglieder, GAME-DESIGN §1.4).
      const sg = room.state.siegerehrung;
      const teams = room.state.teams;
      const siegerTeamId = sg?.teamPlatzierungen?.[0]?.teamId;
      const standings =
        sg !== null
          ? sg.platzierungen.map((p) => ({
              playerId: p.playerId,
              balance: p.balance,
              at: p.at,
              sieg:
                teams !== null && siegerTeamId !== undefined
                  ? teams.zuordnung[p.playerId] === siegerTeamId
                  : p.platz === 1,
            }))
          : [...room.state.order]
              .map((id) => ({ playerId: id, balance: room.state.players[id]?.balance ?? 0 }))
              .sort((a, b) => b.balance - a.balance)
              .map((s, i) => ({
                ...s,
                at: atFuerEndstand(s.balance, i === 0),
                sieg: i === 0,
              }));
      const buchungen = standings.flatMap((s) => {
        const profileId = room.profilBindungen.get(s.playerId);
        if (profileId === undefined) return [];
        return [{ profileId, endstand: s.balance, at: s.at, sieg: s.sieg }];
      });
      if (buchungen.length > 0) {
        // AT-Buchung ⇒ danach Pass-XP + Quests (nur für WIRKLICH neu gebuchte
        // Profile — bucheMatch ist idempotent pro matchId, die Meta-Kette erbt
        // das). Fire-and-forget: Meta-Fehler reißen nie ein Match.
        void profile
          .bucheMatch(room.matchId, buchungen)
          .then((ergebnisse) => verbucheMatchMeta(room.matchId, ergebnisse, buchungen))
          .catch((err) => console.error("Match-Meta-Buchung fehlgeschlagen:", err));
      }
      // v2 Jubiläen: Gruppen-Historie fortschreiben (nur gebundene Profile).
      const endstaende = standings.flatMap((s) => {
        if (!room.profilBindungen.has(s.playerId)) return [];
        const name = room.state.players[s.playerId]?.name ?? "?";
        return [{ name, balance: s.balance }];
      });
      jubilaeen.verbucheMatch(gebundeneProfile(room), endstaende);
      // Match sauber vorbei ⇒ Crash-Schutz-Autosave hat ausgedient.
      void saves.loescheAutosave(room.matchId).catch(() => undefined);
      aggregationSpaeter();
    },

    botTick(room) {
      bots.tick(room);
    },

    autosaveTick(room) {
      // Crash-Schutz (Eval-7 P1): laufende Matches alle ~30 s nach
      // saves/auto/<matchId>.json sichern — aber NUR wenn sich seit dem
      // letzten Autosave etwas getan hat (seq), sonst ist es Write-Spam.
      // Siegerehrung ist AUSGENOMMEN (W4): das Match ist entschieden und
      // matchBeendet hat den Autosave bereits gelöscht — ein Re-Save würde
      // beim nächsten Boot ein FERTIGES Match wiederbeleben (Podium-Zombie).
      if (!matchLaeuft(room) || room.state.phase === "siegerehrung") return;
      const stand = autosaveStand.get(room);
      const jetzt = clock.now();
      if (stand !== undefined && jetzt - stand.ts < AUTOSAVE_INTERVALL_MS) return;
      if (stand !== undefined && stand.seq === room.seq) return;
      autosaveStand.set(room, { ts: jetzt, seq: room.seq });
      // Fire-and-forget: ein Autosave-Fehler darf NIE das Match reißen;
      // writeJsonAtomic serialisiert Writes pro Datei (keine rename-Rennen).
      void saves
        .schreibeAutosave(saveVon(room, AUTOSAVE_SLOT))
        .catch((err) => console.error("Autosave fehlgeschlagen:", err));
    },

    async bootWiederbelebung(fabrik) {
      if (rekey === null) return [];
      const alle = await saves.listeAutosaves();
      const jetzt = clock.now();
      const frisch = alle
        .filter((s) => jetzt - s.savedAt <= BOOT_AUTOSAVE_MAX_ALTER_MS)
        // Fertige Matches (siegerehrung: AT längst gebucht) nie wiederbeleben —
        // Alt-Autosaves solcher Phasen werden unten mit aufgeräumt.
        .filter((s) => !["lobby", "ende", "siegerehrung"].includes(s.engineState.phase))
        // Älteste zuerst wiederbeleben ⇒ der rngState des JÜNGSTEN gewinnt.
        .sort((a, b) => a.savedAt - b.savedAt);
      for (const s of alle) {
        if (!frisch.includes(s)) {
          void saves.loescheAutosave(s.matchId).catch(() => undefined);
        }
      }
      const wiederbelebt: { code: string; phase: string; frageNr: number; alterMs: number }[] = [];
      for (const save of frisch) {
        const room = fabrik.erzeuge();
        if (room === null) break; // max-rooms — Rest bleibt als Autosave liegen
        const umgeschluesselt = rekey(room, save.roomCode);
        if (!umgeschluesselt.ok) {
          fabrik.verwerfe(room);
          continue;
        }
        room.uebernimmSave(save);
        if (save.rngState !== null && istStateful(rng)) rng.setState(save.rngState);
        bots.restauriere(room, save.bots);
        wiederbelebt.push({
          code: room.code,
          phase: room.state.phase,
          frageNr: room.state.fragenZaehler,
          alterMs: jetzt - save.savedAt,
        });
      }
      return wiederbelebt;
    },

    gmMetaCmd(room, cmd, args) {
      switch (cmd) {
        case "bot.add": {
          const r = bots.addBot(
            room,
            typeof args.personaId === "string" ? args.personaId : undefined,
          );
          return Promise.resolve({ ...r, logText: r.ok ? `Bot dazu: ${r.name}` : undefined });
        }
        case "bot.remove": {
          const r = bots.removeBot(room);
          return Promise.resolve({ ...r, logText: r.ok ? `Bot raus: ${r.name}` : undefined });
        }
        case "save.write": {
          const slot = Number(args.slot ?? 1);
          if (!(SAVE_SLOTS as readonly number[]).includes(slot)) {
            return Promise.resolve({ ok: false, error: "ungueltiger-slot" });
          }
          return schreibeSave(room, slot).then((r) => ({
            ...r,
            logText: r.ok ? `💾 Spielstand → Slot ${slot}` : undefined,
          }));
        }
        case "save.load": {
          const slot = Number(args.slot ?? 1);
          return ladeSave(room, slot).then((r) => ({
            ...r,
            logText: r.ok
              ? `📂 Spielstand aus Slot ${slot} geladen — Raum ${room.code}`
              : undefined,
          }));
        }
        default:
          return null;
      }
    },

    raumSchliesst(room, reason) {
      // Auto-Save beim TTL-Abbau: laufende Matches überleben den Raum-Tod.
      if (reason === "ttl" && matchLaeuft(room)) {
        void saves
          .schreibe(saveVon(room, AUTOSAVE_SLOT))
          .catch((err) => console.error("Autosave fehlgeschlagen:", err));
      }
      // Raum weg ⇒ Crash-Schutz-Autosave weg (laufende TTL-Matches liegen ab
      // hier im manuellen Autosave-Slot 0; Boot-Wiederbelebung wäre falsch,
      // der Abend ist ja bewusst abgebaut worden).
      void saves.loescheAutosave(room.matchId).catch(() => undefined);
      aggregationSpaeter();
    },

    // ---------- Lese-APIs (HTTP) ----------

    async profilKarte(profileId) {
      const p = await profile.hole(profileId);
      if (!p) return null;
      const agg = await aggregator.lese();
      const karte = baueProfilKarte(p, agg.profile[profileId] ?? null);
      // Ehrlichkeits-Flag (UX-Fix): AT-Konto ist sofort aktuell, die Match-
      // Statistik erst nach dem 90-s-Analytics-Ruhefenster — der Client zeigt
      // dann „Statistik aktualisiert sich …" und pollt nach.
      const verarbeitet = new Set(agg.verarbeitet);
      karte.statsAusstehend = p.gebuchteMatches.some((id) => !verarbeitet.has(id));
      return karte;
    },

    async boards() {
      const [alle, agg] = await Promise.all([profile.alleProfile(), aggregator.lese()]);
      return baueBoards(alle, agg.profile);
    },

    async boardFortschritt(profileId) {
      const p = await profile.hole(profileId);
      if (!p) return null;
      const agg = await aggregator.lese();
      return baueBoardFortschritt(p, agg.profile[profileId] ?? null);
    },

    async reports(refresh) {
      const agg = refresh ? await aggregator.aktualisiere() : await aggregator.lese();
      const roh = baueReports(agg, katalog(), clock.now());
      // Fehlerhaft-Queue MIT Moderations-Overlay: entkräftete Flags werden
      // ausgeblendet, Quarantäne-/Geprüft-Status reist mit. Quarantänisierte
      // Fragen bleiben auch OHNE aktive Flags sichtbar (sonst wäre die
      // Sperre nicht mehr auffindbar/aufhebbar).
      const mod = moderation.alle();
      const qids = new Set<string>([
        ...Object.entries(agg.fragen)
          .filter(([, f]) => f.flags.length > 0)
          .map(([qid]) => qid),
        ...Object.entries(mod)
          .filter(([, e]) => e.quarantaene)
          .map(([qid]) => qid),
      ]);
      const fehlerhaft: FehlerhaftModZeile[] = [];
      for (const qid of qids) {
        const e = mod[qid];
        const alleFlags = agg.fragen[qid]?.flags ?? [];
        const bis = e?.entkraeftetBis ?? null;
        const aktiv = bis !== null ? alleFlags.filter((f) => f.ts > bis) : alleFlags;
        if (aktiv.length === 0 && e?.quarantaene !== true) continue;
        fehlerhaft.push({
          questionId: qid,
          text: katalog().get(qid)?.text ?? qid,
          anzahl: aktiv.length,
          flags: aktiv.slice(-5),
          ausRotationEmpfohlen: aktiv.length >= 2,
          quarantaene: e?.quarantaene === true,
          geprueftTs: e?.geprueftTs ?? null,
        });
      }
      fehlerhaft.sort(
        (a, b) => Number(b.quarantaene) - Number(a.quarantaene) || b.anzahl - a.anzahl,
      );
      return { ...roh, fehlerhaft };
    },

    matchErgebnis(profileId) {
      return matchMetaPuffer.get(profileId) ?? null;
    },

    async passUebersicht(profileId) {
      const [pass, questStand] = await Promise.all([
        season.stand(profileId),
        quests.stand(profileId),
      ]);
      const belohnungen = passBelohnungen(pass.saisonId).map((b) => {
        const item = b.itemId !== undefined ? itemFuer(b.itemId) : undefined;
        return {
          stufe: b.stufe,
          art: b.art,
          ...(b.at !== undefined ? { at: b.at } : {}),
          ...(item !== undefined
            ? {
                item: {
                  id: item.id,
                  name: item.name,
                  emoji: item.emoji,
                  typ: item.typ,
                  slot: item.slot,
                  beschreibung: item.beschreibung,
                },
              }
            : {}),
          erreicht: b.stufe <= pass.stufe,
        };
      });
      return {
        saison: {
          id: pass.saisonId,
          name: saisonName(pass.saisonId),
          endetTs: saisonEndeMs(pass.saisonId),
          stufen: PASS_STUFEN,
        },
        xp: pass.xp,
        stufe: pass.stufe,
        atBonus: pass.atBonus,
        stufeAbXp: xpKumulativFuerStufe(pass.stufe),
        naechsteAbXp: pass.stufe >= PASS_STUFEN ? null : xpKumulativFuerStufe(pass.stufe + 1),
        belohnungen,
        tagKey: questStand.tagKey,
        quests: questStand.quests,
        archiv: pass.archiv,
      };
    },
  };
}
