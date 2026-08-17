// viewFor: rollen-gefilterte Views aus dem Engine-State. Geheimnisse (correctIndex,
// Regal-Antworten, Flüster-Tipps) werden HIER serverseitig gefiltert — Clients
// bekommen nur, was ihre Rolle sehen darf.
import { rueckenwindFaktor } from "../../shared/economy";
import type { PlayerId, Role } from "../../shared/ids";
import { kategoriePfadLabel } from "../../shared/kategorien";
import {
  TEAM_DEFS,
  TEAM_MIN_SPIELER,
  angeboteneTeams,
  teamAnzeigeName,
  teamMitglieder,
  teamStaende,
} from "../../shared/teams";
import { RAD_SEGMENT_MAP, type RadSegmentId } from "../../shared/wheel";
import type {
  AbschnittInfo,
  AnyView,
  ErklaerkarteView,
  GmView,
  HighlightsView,
  JubilaeumsView,
  KategorieWahlView,
  ModifierView,
  PlayerView,
  RadView,
  ScreenView,
  SiegerehrungView,
  SpielerPublic,
  TeamsView,
  TiebreakerView,
  VotingErgebnisView,
  VotingView,
} from "../../shared/views";
import type { Ctx } from "../minigames/_api/plugin";
import {
  aktuelleFrageDesFormats,
  aktuellerAbschnitt,
  kontostaende,
  verbundene,
  type EngineDeps,
} from "./flow";
import { aktuelleRunde, hatKlauSchutz, jokerLeiste } from "./jokers";
import { regalKandidaten } from "./plan";
import { HIGHLIGHT_KARTE_MS, type EngineState } from "./types";

/** Raum-Kontext, den die Engine selbst nicht kennt (Code, URLs, GM-Log). */
export interface RoomInfo {
  roomCode: string;
  joinUrl: string;
  qrPath: string;
  gmPin: string;
  gmLog: { id: string; ts: number; cmd: string; text: string }[];
  /** v2 Jubiläums-Erkennung: Gruppen-Meilenstein DIESES Matches (META-Schicht). */
  jubilaeum?: JubilaeumsView | null;
  /** LOBBY (ADDITIV): Anzeige-Name + Sichtbarkeit für die Screen-Lobby. */
  lobbyName?: string;
  oeffentlich?: boolean;
}

/** 1-Satz-Erklärtexte der Formate (Erklärkarte) — Fallback: Meta-Name. */
const ERKLAER_TEXTE: Record<string, string> = {
  "vier-lianen": "Vier Lianen, eine trägt: tippt die richtige Antwort — schnell zahlt sich aus!",
  "kokosnuss-uhr": "Der Geldsack schrumpft im Takt — antworte früh und sichere dir mehr!",
  "bananen-tresor": "Schätzt den Wert am Slider — wer am nächsten dran ist, knackt den Tresor!",
  affenleiter: "Sortiert die vier Sprossen in die richtige Reihenfolge — unten anfangen!",
  "pixel-dschungel": "Das Bild wird langsam scharf — je früher du tippst, desto mehr Beute!",
  stinkbanane: "Antwortet richtig, sonst bleibt die Stinkbanane bei euch kleben — sie explodiert!",
  taschendieb: "Buzzer bereit! Wer zuerst drückt und richtig liegt, klaut dem Vordermann Beute.",
  "bananen-basics": "Lockeres Aufwärmen: 4 Antworten, milde Werte — baut eure Streak auf!",
  affenbank:
    "Die Kette wächst mit jeder Mehrheits-Antwort — wer BANK! drückt, sichert sich den Pott!",
  "alles-oder-banane":
    "Erst geheim setzen, dann kommt die Frage: richtig = Einsatz verdoppelt, falsch = weg!",
  "lianen-finale":
    "Jeder hängt an seiner Liane über dem Krokodil-Fluss — jede Antwort zählt W_final!",
};

/** Tutorial-Videos je Format (assets/video/, via /media ausgeliefert) —
 * Erklärkarten bieten sie NUR bei Match-Setting tutorialVideos=AN an.
 * Render-Pipeline: remotion/scripts/render-tutorials.sh (HowToCard-Template,
 * Props aus remotion/src/tutorials.ts — abgeleitet aus den explainCards). */
export const TUTORIAL_VIDEOS: Record<string, string> = {
  stinkbanane: "/media/video/tutorial_stinkbanane.mp4",
  "vier-lianen": "/media/video/tutorial_vier-lianen.mp4",
  "bananen-basics": "/media/video/tutorial_bananen-basics.mp4",
  "kokosnuss-uhr": "/media/video/tutorial_kokosnuss-uhr.mp4",
  "bananen-tresor": "/media/video/tutorial_bananen-tresor.mp4",
  affenleiter: "/media/video/tutorial_affenleiter.mp4",
  "pixel-dschungel": "/media/video/tutorial_pixel-dschungel.mp4",
  taschendieb: "/media/video/tutorial_taschendieb.mp4",
  affenbank: "/media/video/tutorial_affenbank.mp4",
  "alles-oder-banane": "/media/video/tutorial_alles-oder-banane.mp4",
  "lianen-finale": "/media/video/tutorial_lianen-finale.mp4",
  "monkey-market": "/media/video/tutorial_monkey-market.mp4",
  "bananen-bluff": "/media/video/tutorial_bananen-bluff.mp4",
  "bananen-boerse": "/media/video/tutorial_bananen-boerse.mp4",
  "affen-auktion": "/media/video/tutorial_affen-auktion.mp4",
  "lianensteg-duell": "/media/video/tutorial_lianensteg-duell.mp4",
  "goldener-affe": "/media/video/tutorial_goldener-affe.mp4",
  "buchstaben-telegramm": "/media/video/tutorial_buchstaben-telegramm.mp4",
  "musikvideo-raten": "/media/video/tutorial_musikvideo-raten.mp4",
  "song-rueckwaerts": "/media/video/tutorial_song-rueckwaerts.mp4",
  "song-snippet": "/media/video/tutorial_song-snippet.mp4",
};

function spielerListe(state: EngineState): SpielerPublic[] {
  const fuehrender = Math.max(0, ...state.order.map((id) => state.players[id].balance));
  const runde = aktuelleRunde(state);
  return state.order.map((id) => {
    const p = state.players[id];
    const rw = rueckenwindFaktor(p.balance, fuehrender);
    return {
      id: p.id,
      name: p.name,
      avatar: p.avatar,
      connected: p.connected,
      graceUntil: p.graceUntil ?? undefined,
      balance: p.balance,
      streak: p.streak,
      rueckenwind: rw > 1 ? rw : undefined,
      schild: hatKlauSchutz(state, id) || undefined,
      clown: (p.clownBisRunde !== null && p.clownBisRunde >= runde) || undefined,
    };
  });
}

function standings(state: EngineState) {
  return [...state.order]
    .map((id) => state.players[id])
    .sort((a, b) => b.balance - a.balance)
    .map((p) => ({ id: p.id, name: p.name, avatar: p.avatar, balance: p.balance }));
}

function abschnittInfo(state: EngineState, deps: EngineDeps): AbschnittInfo | null {
  const a = aktuellerAbschnitt(state);
  if (!a || !state.plan) return null;
  const meta = deps.getPlugin(a.minigameId).meta;
  return {
    typ: a.typ,
    rundeNr: a.nr,
    rundenTotal: state.plan.rundenTotal,
    slot: a.slot,
    minigameId: a.minigameId,
    minigameName: meta.name,
    kategorie: a.kategorie,
    frageInRunde: Math.max(1, state.frageInAbschnitt + 1),
    fragenInRunde: a.fragen,
    wFinal: a.typ === "finale" ? (state.finaleWert ?? undefined) : undefined,
  };
}

function kategorieWahlView(state: EngineState, playerId?: string): KategorieWahlView | null {
  const wahl = state.kategorieWahl;
  if (!wahl) return null;
  return {
    optionen: wahl.optionen,
    stimmen: wahl.optionen.map((o) => Object.values(wahl.stimmen).filter((s) => s === o).length),
    nurLetzterWaehlt: wahl.nurLetzter !== null,
    waehlerName: wahl.nurLetzter !== null ? state.players[wahl.nurLetzter]?.name : undefined,
    endetAt: wahl.endetAt,
    deineStimme:
      playerId !== undefined
        ? wahl.optionen.includes(wahl.stimmen[playerId] ?? "")
          ? wahl.optionen.indexOf(wahl.stimmen[playerId])
          : null
        : undefined,
  };
}

function erklaerkarteView(state: EngineState, deps: EngineDeps): ErklaerkarteView | null {
  const karte = state.erklaerkarte;
  const a = aktuellerAbschnitt(state);
  if (!karte || !a) return null;
  const meta = deps.getPlugin(a.minigameId).meta;
  const text =
    a.typ === "jackpot"
      ? `JACKPOT-FRAGE: 2.000 MM + das Glas (${state.jackpotGlas} MM) für den Schnellsten!`
      : a.typ === "finale"
        ? `FINALE: Jede Frage ist ${state.finaleWert ?? "?"} MM wert — falsch kostet die Hälfte!`
        : (ERKLAER_TEXTE[a.minigameId] ?? meta.name);
  return {
    minigameId: a.minigameId,
    minigameName: meta.name,
    slot: a.slot,
    text,
    kategorie: a.kategorie,
    schwierigkeiten: a.schwierigkeiten,
    bereit: karte.bereit,
    streik: karte.streik,
    endetAt: karte.endetAt,
    wFinal: a.typ === "finale" ? (state.finaleWert ?? undefined) : undefined,
    videoUrl: state.settings.tutorialVideos ? TUTORIAL_VIDEOS[a.minigameId] : undefined,
  };
}

function radView(state: EngineState, playerId?: string): RadView | null {
  const rad = state.rad;
  if (!rad) return null;
  const segView = (id: RadSegmentId) => {
    const seg = RAD_SEGMENT_MAP[id];
    return { id: seg.id, name: seg.name, klasse: seg.klasse };
  };
  const seg = RAD_SEGMENT_MAP[rad.ergebnis];
  return {
    segmente: rad.segmente.map(segView),
    ergebnisIndex: rad.ergebnisIndex,
    dreh: { startetAt: rad.drehStartetAt, dauerMs: rad.drehDauerMs },
    ergebnis:
      rad.subphase === "dreh"
        ? null
        : {
            id: seg.id,
            name: seg.name,
            klasse: seg.klasse,
            wirkung: seg.wirkung,
            betroffen: rad.betroffen,
          },
    interaktion:
      rad.subphase === "interaktion" && seg.interaktion
        ? {
            typ: seg.interaktion.typ,
            endetAt: rad.subEndetAt,
            paar: rad.paar ?? undefined,
            deineWahl: playerId !== undefined ? (rad.wahlen[playerId] ?? null) : undefined,
          }
        : null,
  };
}

const MODIFIER_NAMEN: Record<string, string> = {
  "goldene-banane": "Goldene Banane ×2",
  "boost-x2": "GM-Boost ×2",
};

function modifierViews(state: EngineState): ModifierView[] {
  return state.modifiers.map((m) => ({
    id: m.id,
    name: MODIFIER_NAMEN[m.id] ?? RAD_SEGMENT_MAP[m.id as RadSegmentId]?.name ?? m.id,
    scope: m.scope,
    betroffen: m.betroffen.length > 0 ? m.betroffen : undefined,
  }));
}

function votingView(state: EngineState, playerId?: string): VotingView | null {
  const v = state.voting;
  if (!v) return null;
  return {
    frage: v.frage,
    optionen: v.optionen,
    stimmen: v.optionen.map((_, i) => Object.values(v.stimmen).filter((x) => x === i).length),
    endetAt: v.endetAt,
    deineStimme: playerId !== undefined ? (v.stimmen[playerId] ?? null) : undefined,
  };
}

function votingErgebnisView(state: EngineState): VotingErgebnisView | null {
  const e = state.votingErgebnis;
  if (!e) return null;
  return {
    frage: e.frage,
    optionen: e.optionen,
    stimmen: e.stimmen,
    gewinnerIndex: e.gewinnerIndex,
    endetAt: e.endetAt,
  };
}

/** Maßanzug-Ziel: WELCHES Format bekommt die nächste Frage — und kann es
 * per-Spieler-Fragen? (Ehrliche Anzeige im GM-Cockpit, Befund „Maßanzug"). */
function zuweisungsZiel(
  state: EngineState,
  deps: EngineDeps,
): { minigameId: string; minigameName: string; verfuegbar: boolean } | null {
  if (!state.plan) return null;
  // Im Zwischenstand/Rad kommt die nächste Frage aus dem NÄCHSTEN Abschnitt.
  const idx =
    state.phase === "zwischenstand" || state.phase === "rad"
      ? state.abschnittIndex + 1
      : Math.max(0, state.abschnittIndex);
  const a = state.plan.abschnitte[idx];
  if (!a) return null;
  const meta = deps.getPlugin(a.minigameId).meta;
  return {
    minigameId: a.minigameId,
    minigameName: meta.name,
    verfuegbar: meta.perSpielerFragen === true,
  };
}

/** Team-Modus „Affenbanden" (ADDITIV, §1.4): Lobby-Wahl-Spalten bzw. das
 * Live-Team-Ranking (Topf = Summe der Konten, Doppel-Affe ×2) mit
 * Individual-Aufschlüsselung — null wenn Team-Modus aus/nicht aktiv. */
function teamsView(state: EngineState, playerId?: string): TeamsView | null {
  const mitglied = (pid: string, doppelAffe: boolean) => ({
    playerId: pid,
    name: state.players[pid]?.name ?? "?",
    avatar: state.players[pid]?.avatar ?? ("gelb" as const),
    balance: state.players[pid]?.balance ?? 0,
    doppelAffe,
  });
  // Laufendes Match: echte Aufstellung mit Topf + Platz (nach Rang sortiert).
  const teams = state.teams;
  if (teams !== null) {
    const staende = teamStaende(teams, kontostaende(state));
    const platzVon = new Map(staende.map((s) => [s.teamId, s.platz]));
    const topfVon = new Map(staende.map((s) => [s.teamId, s.topf]));
    return {
      modus: teams.modus,
      wahlOffen: false,
      minSpieler: TEAM_MIN_SPIELER,
      teams: teams.teams
        .map((t) => ({
          id: t.id,
          name: t.name,
          farbe: t.farbe,
          emoji: t.emoji,
          topf: topfVon.get(t.id) ?? 0,
          platz: platzVon.get(t.id) ?? 0,
          mitglieder: teamMitglieder(teams, t.id, state.order).map((pid) =>
            mitglied(pid, teams.doppelAffe === pid),
          ),
        }))
        .sort((a, b) => a.platz - b.platz),
      deinTeam: playerId !== undefined ? (teams.zuordnung[playerId] ?? null) : undefined,
    };
  }
  // Lobby: Wahl-Spalten mit den aktuellen Wünschen (Topf/Platz noch 0).
  if (state.phase !== "lobby" || state.settings.teams === "aus") return null;
  const modus = state.settings.teams;
  const ids = angeboteneTeams(modus, Math.max(state.order.length, TEAM_MIN_SPIELER));
  return {
    modus,
    wahlOffen: true,
    minSpieler: TEAM_MIN_SPIELER,
    teams: ids.map((id) => ({
      id,
      name: teamAnzeigeName(id),
      farbe: TEAM_DEFS[id].farbe,
      emoji: TEAM_DEFS[id].emoji,
      topf: 0,
      platz: 0,
      mitglieder: state.order
        .filter((pid) => state.teamWuensche[pid] === id)
        .map((pid) => mitglied(pid, false)),
    })),
    deinTeam: playerId !== undefined ? (state.teamWuensche[playerId] ?? null) : undefined,
  };
}

function siegerehrungView(state: EngineState): SiegerehrungView | null {
  const sg = state.siegerehrung;
  if (!sg) return null;
  return {
    platzierungen: sg.platzierungen.map((p) => ({
      ...p,
      name: state.players[p.playerId]?.name ?? "?",
      avatar: state.players[p.playerId]?.avatar ?? "gelb",
    })),
    awards: sg.awards.map((a) => ({
      ...a,
      name: state.players[a.playerId]?.name ?? "?",
    })),
    // Team-Modus: Team-Podest (Reihenfolge aus der Engine — Shake-Tiebreak!).
    teams: sg.teamPlatzierungen?.map((t) => {
      const info = state.teams?.teams.find((x) => x.id === t.teamId);
      return {
        teamId: t.teamId,
        name: info?.name ?? t.teamId,
        farbe: info?.farbe ?? "#888",
        emoji: info?.emoji ?? "🐒",
        platz: t.platz,
        topf: t.topf,
      };
    }),
  };
}

/** v2 Replay-Highlights: Karten mit Namen/Avataren anreichern (nur in der Phase). */
function highlightsView(state: EngineState): HighlightsView | null {
  const hl = state.highlights;
  if (!hl || state.phase !== "highlights") return null;
  return {
    karten: hl.karten.map((k) => ({
      id: k.id,
      art: k.art,
      titel: k.titel,
      text: k.text,
      playerId: k.playerId,
      playerName: state.players[k.playerId]?.name ?? "?",
      avatar: state.players[k.playerId]?.avatar ?? "gelb",
      gegnerId: k.gegnerId,
      gegnerName: k.gegnerId !== undefined ? state.players[k.gegnerId]?.name : undefined,
      betrag: k.betrag,
      frageNr: k.frageNr,
    })),
    index: hl.index,
    endetAt: hl.endetAt,
    karteMs: HIGHLIGHT_KARTE_MS,
  };
}

/** v2 Sudden-Death: Teilnehmer + Live-Taps (Taps sind ÖFFENTLICH — Drama!). */
function tiebreakerView(state: EngineState): TiebreakerView | null {
  const tb = state.tiebreaker;
  if (!tb || state.phase !== "tiebreaker") return null;
  return {
    subphase: tb.subphase,
    endetAt: tb.endetAt,
    runde: tb.runde,
    betrag: tb.betrag,
    teilnehmer: tb.teilnehmer.map((id) => ({
      playerId: id,
      name: state.players[id]?.name ?? "?",
      avatar: state.players[id]?.avatar ?? "gelb",
      taps: tb.taps[id] ?? 0,
    })),
    siegerId: tb.sieger,
  };
}

function dramaMeter(state: EngineState): { score: number; empfehlung: string | null } {
  const sortiert = [...state.order].sort(
    (a, b) => state.players[b].balance - state.players[a].balance,
  );
  if (sortiert.length < 2) return { score: 50, empfehlung: null };
  const erster = state.players[sortiert[0]].balance;
  const zweiter = state.players[sortiert[1]].balance;
  const abstand = erster > 0 ? (erster - zweiter) / erster : 0;
  const score = Math.round(Math.max(0, Math.min(100, 100 - abstand * 100)));
  const empfehlung =
    abstand > 0.5
      ? "Match läuft auseinander — Rad drehen oder Underdog boosten!"
      : abstand < 0.1 && erster > 0
        ? "Kopf-an-Kopf-Rennen — perfekt für eine ULTRAHARD-Frage!"
        : null;
  return { score, empfehlung };
}

/** Kategorie-Badge („Gaming · Minecraft") der laufenden Frage — der zentrale
 * Kontext-Anker in ALLEN Frage-Formaten (Eval 5). Nur bei Frage-Formaten
 * (quiz/estimate/sort/media): Song-/none-Formate zeigen keine Pool-Frage. */
function frageKategorieBadge(state: EngineState, deps: EngineDeps): string | null {
  if (state.phase !== "frage" && state.phase !== "aufloesung") return null;
  if (!state.minigameId) return null;
  const kind = deps.getPlugin(state.minigameId).meta.contentKind;
  if (kind !== "quiz" && kind !== "estimate" && kind !== "sort" && kind !== "media") return null;
  const kategorie = aktuelleFrageDesFormats(state, deps)?.category;
  return kategorie !== undefined ? kategoriePfadLabel(kategorie) : null;
}

export function viewFor(
  state: EngineState,
  role: Role,
  deps: EngineDeps,
  room: RoomInfo,
  ctx: Ctx,
  playerId?: string,
): AnyView {
  const blackout = state.modifiers.some((m) => m.id === "blackout");
  let minigame: { id: string; view: unknown } | null = null;
  if (state.minigameId && (state.phase === "frage" || state.phase === "aufloesung")) {
    const plugin = deps.getPlugin(state.minigameId);
    // Blackout (Rad): der Bildschirm zeigt Sendeausfall statt der Frage (§5.3/11).
    const view =
      blackout && role === "screen" && state.phase === "frage"
        ? { blackout: true }
        : plugin.viewFor(state.minigameState, role, playerId as PlayerId | undefined);
    minigame = { id: state.minigameId, view };
  }

  const basis = {
    phase: state.phase,
    roomCode: room.roomCode,
    players: spielerListe(state),
    paused: state.paused
      ? { text: state.paused.text, seit: state.paused.seit, bis: state.paused.bis ?? undefined }
      : null,
    serverTime: ctx.clock.now(),
    frageNr: state.fragenZaehler,
    frageTotal: state.plan?.fragenTotal ?? 0,
    minigame,
    abschnitt: abschnittInfo(state, deps),
    jackpotGlas: state.jackpotGlas,
    pott: state.pott,
    modifiers: modifierViews(state),
    momente: state.momente,
    kategorieWahl: kategorieWahlView(state, playerId),
    erklaerkarte: erklaerkarteView(state, deps),
    rad: radView(state, playerId),
    voting: votingView(state, playerId),
    votingErgebnis: votingErgebnisView(state),
    siegerehrung: siegerehrungView(state),
    feedbackAngefragt: state.feedbackAngefragt,
    alltimeItems: state.settings.alltimeItems,
    highlights: highlightsView(state),
    tiebreaker: tiebreakerView(state),
    jubilaeum: room.jubilaeum ?? null,
    teams: teamsView(state, playerId),
    // Tipp-Kanone: enthüllte Tipps sind ÖFFENTLICH (Screen + alle Handys).
    tipps: state.phase === "frage" ? (state.gezeigteTipps ?? []) : [],
    frageKategorie: frageKategorieBadge(state, deps),
    // Musik-Rotation (ADDITIV): !== "aus" hält Alt-Saves ohne Feld auf AN.
    musikAn: state.settings.musik !== "aus",
    musikVolume:
      typeof state.settings.musikVolume === "number"
        ? Math.min(1, Math.max(0, state.settings.musikVolume))
        : 1,
    musikSkips: state.musikSkips ?? 0,
  };

  if (role === "screen") {
    const view: ScreenView = {
      ...basis,
      role: "screen",
      joinUrl: room.joinUrl,
      qrPath: room.qrPath,
      gmPin: room.gmPin,
      standings: standings(state),
      // LOBBY (ADDITIV): Name + Sichtbarkeit (Teilen-Knopf/Toggle in der Lobby).
      lobbyName: room.lobbyName ?? "",
      oeffentlich: room.oeffentlich === true,
    };
    return view;
  }

  if (role === "gm") {
    const plugin = state.minigameId ? deps.getPlugin(state.minigameId) : null;
    const view: GmView = {
      ...basis,
      role: "gm",
      joinUrl: room.joinUrl,
      standings: standings(state),
      log: room.gmLog.slice(-20),
      settings: state.settings,
      autoGm: state.settings.autoGm,
      regal: regalKandidaten(state).map((q) => ({
        id: q.id,
        kategorie: q.category,
        schwierigkeit: q.difficulty,
        text: q.text,
        antwort: q.options[q.answer] ?? "?",
      })),
      zuweisungen: state.zuweisungen,
      zuweisungsZiel: zuweisungsZiel(state, deps),
      dramaMeter: dramaMeter(state),
      budgets: {
        jokerChips: state.gm.jokerChips,
        verlaengerungenDieseFrage: state.gm.verlaengerungenDieseFrage,
        encoresDieseRunde: state.gm.encoresDieseRunde,
        blitzStimmungen: state.gm.blitzStimmungen,
        hintStufe: state.gm.hintStufeDieseFrage,
      },
      feedback: state.feedback.map((f) => ({
        playerId: f.playerId,
        name: state.players[f.playerId]?.name ?? "?",
        text: f.text,
      })),
      stimmung: state.gm.stimmungsHistorie,
      // Spickzettel: die Autoren-Tipps der laufenden Frage (GEHEIM bis gesendet).
      spickzettelTipps:
        state.phase === "frage" || state.phase === "aufloesung"
          ? (aktuelleFrageDesFormats(state, deps)?.tips ?? [])
          : [],
    };
    void plugin;
    return view;
  }

  const you = playerId ? state.players[playerId] : undefined;
  const alle = spielerListe(state);
  const view: PlayerView = {
    ...basis,
    role: "player",
    you: alle.find((p) => p.id === playerId) ?? {
      id: "?",
      name: "?",
      avatar: "gelb",
      connected: true,
      balance: 0,
      streak: 0,
    },
    standings: standings(state),
    jokers:
      you !== undefined && state.phase !== "lobby"
        ? jokerLeiste(
            state,
            playerId ?? "",
            state.minigameId ? deps.getPlugin(state.minigameId) : null,
          )
        : [],
    fluesterTipp: playerId !== undefined ? (state.fluesterTipp[playerId] ?? null) : null,
    hinweis: playerId !== undefined ? (state.hinweis[playerId] ?? null) : null,
    mood:
      state.mood && playerId !== undefined
        ? { endetAt: state.mood.endetAt, deineWahl: state.mood.werte[playerId] ?? null }
        : null,
  };
  return view;
}

export { verbundene };
