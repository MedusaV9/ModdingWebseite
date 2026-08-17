// GM-Kommando-Handler: übersetzt den EINEN Kommando-Kanal (gm.cmd) in
// Engine-Aktionen — alle 17 Werkzeuge aus GAME-DESIGN §4.2. Jeder Erfolg landet
// im Aktions-Log; Budgets/Leitplanken prüft der Engine-Reducer (gm.ts).
import { formatMM } from "../../shared/money";
import type { GmAck, GmCmd } from "../../shared/protocol";
import type { EngineAction } from "../engine/types";
import type { Room } from "../rooms/room";

function uebersetze(
  room: Room,
  cmd: string,
  args: Record<string, unknown>,
): { action: EngineAction | "start"; logText: string } | null {
  const spielerName = (playerId: string): string => room.state.players[playerId]?.name ?? playerId;

  switch (cmd) {
    // 1) Punkte ± [Spieler, Betrag, Grund] — Begründungs-Chip ist Pflicht.
    case "score.adjust": {
      const playerId = String(args.playerId ?? "");
      const delta = Number(args.delta ?? 0);
      const grund = String(args.grund ?? "");
      return {
        action: {
          type: "gm.scoreAdjust",
          playerId,
          delta,
          grund,
          override: args.override === true,
        },
        logText: `Punkte: ${spielerName(playerId)} ${delta >= 0 ? "+" : ""}${formatMM(delta)} (${grund})`,
      };
    }

    // 2) Zeit +15 s (immer für ALLE).
    case "timer.extend": {
      const ms = Number(args.ms ?? 15_000);
      return {
        action: { type: "gm.timerExtend", ms },
        logText: `Zeit +${Math.round(ms / 1000)} s`,
      };
    }

    // 11) Bananen-Pause / Timeout-Screen (optional mit Countdown, z. B. 10 min).
    case "session.pause": {
      const text = String(args.text ?? "Kurze Pause — gleich geht's weiter!");
      const dauerMs = args.dauerMs !== undefined ? Number(args.dauerMs) : undefined;
      return { action: { type: "gm.pause", text, dauerMs }, logText: `Pause: „${text}“` };
    }

    case "session.resume":
      return { action: { type: "gm.resume" }, logText: "Weiter nach Pause" };

    // Universal-Weiter (in der Lobby: Match-Start mit Fragen aus dem Content-Loader).
    case "flow.next":
      return {
        action: room.state.phase === "lobby" ? "start" : { type: "gm.next" },
        logText: room.state.phase === "lobby" ? "Match gestartet" : "Weiter (Skip)",
      };

    // Settings (Modus/Joker/Rad/Kategorien-Wahl/Auto-GM/kurze Show).
    case "settings.set":
      return {
        action: { type: "gm.settings", patch: args },
        logText: `Settings: ${JSON.stringify(args)}`,
      };

    // 2/3) Kategorie-Pick + Fragen-Regal.
    case "kategorie.pick": {
      const kategorie = String(args.kategorie ?? "");
      return {
        action: { type: "gm.kategoriePick", kategorie },
        logText: `Kategorie gewählt: ${kategorie}`,
      };
    }

    case "question.pick": {
      const questionId = String(args.questionId ?? "");
      return {
        action: { type: "gm.questionPick", questionId },
        logText: `Nächste Frage gepickt: ${questionId}`,
      };
    }

    // Maßanzug-Modus: Frage pro Spieler zuweisen (questionId null = entfernen).
    case "question.assign": {
      const playerId = String(args.playerId ?? "");
      const questionId = args.questionId === null ? null : String(args.questionId ?? "");
      return {
        action: { type: "gm.questionAssign", playerId, questionId },
        logText: `Maßanzug: ${spielerName(playerId)} ← ${questionId ?? "(entfernt)"}`,
      };
    }

    case "regal.filter": {
      const kategorie = args.kategorie === null ? null : (args.kategorie as string | undefined);
      const schwierigkeit =
        args.schwierigkeit === null ? null : (args.schwierigkeit as string | undefined);
      return {
        action: { type: "gm.regalFilter", kategorie, schwierigkeit },
        logText: `Regal-Filter: ${kategorie ?? "alle"} / ${schwierigkeit ?? "alle"}`,
      };
    }

    // 6/7) Tipp-Kanone global (sichtbarer Abzug) + Flüster-Tipp privat.
    case "hint.global":
      return { action: { type: "gm.hintGlobal" }, logText: "Tipp-Kanone (global, −25 %)" };

    case "hint.whisper": {
      const playerId = String(args.playerId ?? "");
      return {
        action: { type: "gm.hintWhisper", playerId, text: String(args.text ?? "") },
        logText: `Flüster-Tipp an ${spielerName(playerId)}`,
      };
    }

    // 8) Publikums-Voting.
    case "vote.start": {
      const optionen = Array.isArray(args.optionen) ? args.optionen.map(String) : [];
      return {
        action: {
          type: "gm.voteStart",
          frage: String(args.frage ?? ""),
          optionen,
          dauerMs: args.dauerMs !== undefined ? Number(args.dauerMs) : undefined,
        },
        logText: `Voting: „${String(args.frage ?? "")}“`,
      };
    }

    // 9) Fehlerhaft-Markierung (annul | grantAll).
    case "question.markBroken": {
      const refund = args.refund === "grantAll" ? "grantAll" : "annul";
      return {
        action: { type: "gm.markBroken", grund: String(args.grund ?? "fehlerhaft"), refund },
        logText: `Frage fehlerhaft markiert (${refund})`,
      };
    }

    // 10) Skip-Game + Buggy-Flag.
    case "game.skip":
      return {
        action: { type: "gm.gameSkip", keepPoints: args.keepPoints === true },
        logText: `Runde geskippt (${args.keepPoints === true ? "Punkte behalten" : "ohne Punkte"})`,
      };

    case "game.flagBuggy":
      return {
        action: { type: "gm.flagBuggy", grund: String(args.grund ?? "buggy") },
        logText: "Minispiel als buggy geflaggt",
      };

    // 12) Bestrafungs-Karte (bananensteuer | clown).
    case "player.punish": {
      const playerId = String(args.playerId ?? "");
      const strafe = String(args.strafe ?? "bananensteuer");
      return {
        action: { type: "gm.punish", playerId, strafe },
        logText: `Bestrafung: ${spielerName(playerId)} (${strafe})`,
      };
    }

    // 13) Underdog-Boost mit Begründungs-Chip.
    case "player.boost": {
      const playerId = String(args.playerId ?? "");
      const art = args.art === "plus300" ? "plus300" : args.art === "joker" ? "joker" : "x2";
      return {
        action: { type: "gm.boost", playerId, art, grund: String(args.grund ?? "") },
        logText: `Boost: ${spielerName(playerId)} (${art}: ${String(args.grund ?? "")})`,
      };
    }

    // 15) Joker-Vergabe (Budget 6 Chips; ziel = playerId oder "alle").
    case "joker.grant": {
      const ziel = String(args.ziel ?? "");
      return {
        action: { type: "gm.jokerGrant", ziel, jokerId: String(args.jokerId ?? "") },
        logText: `Joker vergeben: ${String(args.jokerId ?? "")} → ${ziel === "alle" ? "alle" : spielerName(ziel)}`,
      };
    }

    // 16) Glücksrad (nur im Zwischenstand; rigTarget = heimliches Wunsch-Segment).
    case "wheel.spin":
      return {
        action: {
          type: "gm.wheelSpin",
          rigTarget: args.rigTarget !== undefined ? String(args.rigTarget) : undefined,
        },
        logText: args.rigTarget !== undefined ? "Rad gedreht (gerigged)" : "Rad gedreht",
      };

    // 17) Blitz-Stimmung (3/Session).
    case "mood.poll":
      return { action: { type: "gm.moodPoll" }, logText: "Blitz-Stimmung gestartet" };

    // 14) Feedback einsammeln (Freitext auf allen Handys).
    case "feedback.collect":
      return { action: { type: "gm.feedbackCollect" }, logText: "Feedback-Runde gestartet" };

    // Zugabe: +1 Frage in dieser Runde.
    case "flow.encore":
      return { action: { type: "gm.encore" }, logText: "ZUGABE! +1 Frage" };

    // Soundboard.
    case "sound.play":
      return {
        action: { type: "gm.sound", sfxId: String(args.sfxId ?? "tusch") },
        logText: `Sound: ${String(args.sfxId ?? "tusch")}`,
      };

    // Musik-Rotation: „Nächster Track" fürs Show-Bett (Screen skippt).
    case "musik.skip":
      return { action: { type: "gm.musikSkip" }, logText: "Musik: nächster Track" };

    // Team-Modus: GM weist einen Spieler in der Lobby einem Team zu (null löscht).
    case "team.assign": {
      const playerId = String(args.playerId ?? "");
      const team = args.team === null ? null : String(args.team ?? "");
      return {
        action: { type: "gm.teamAssign", playerId, team },
        logText: `Team: ${spielerName(playerId)} → ${team ?? "(frei)"}`,
      };
    }

    // Auto-GM an/aus.
    case "autogm.set":
      return {
        action: { type: "gm.autoGm", enabled: args.enabled === true },
        logText: `Auto-GM ${args.enabled === true ? "AN" : "AUS"}`,
      };

    // Match sofort beenden → Siegerehrung.
    case "session.ende":
      return { action: { type: "gm.ende" }, logText: "Match beendet → Siegerehrung" };

    default:
      return null;
  }
}

export function handleGmCmd(room: Room, msg: GmCmd): GmAck | Promise<GmAck> {
  const { cmd, args, cmdId } = msg;
  const uebersetzt = uebersetze(room, cmd, args);
  if (!uebersetzt) {
    // META-Delegation (save.*, bot.*): Kommandos außerhalb des Engine-Katalogs.
    const metaErgebnis = room.deps.meta?.gmMetaCmd(room, cmd, args);
    if (metaErgebnis) {
      return metaErgebnis.then((r) => {
        if (r.ok) {
          room.gmLogEintrag(cmd, args, r.logText ?? cmd);
          room.broadcastSnapshots();
        }
        return { cmdId, ok: r.ok, error: r.error };
      });
    }
    return { cmdId, ok: false, error: `unbekanntes-kommando:${cmd}` };
  }

  const result =
    uebersetzt.action === "start" ? room.startMatch() : room.applyAction(uebersetzt.action);

  if (result.ok) {
    room.gmLogEintrag(cmd, args, uebersetzt.logText);
    // GM-Kommandos ändern oft Dinge, die nur als Snapshot sauber ankommen.
    room.broadcastSnapshots();
  }
  return { cmdId, ok: result.ok, error: result.error };
}
