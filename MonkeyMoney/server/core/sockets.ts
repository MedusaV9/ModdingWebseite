// socket.io-Wiring: Nachrichten-Katalog (TECH-SPEC §3.1) → Räume/Engine.
// Transport-Reconnect macht socket.io; die FACHLICHE Wiederherstellung läuft
// über Session-Token + Snapshot/seq (hello mit Token ⇒ Slot-Restore).
import { randomUUID } from "node:crypto";
import type { Server, Socket } from "socket.io";
import {
  BuzzSchema,
  FeedbackTextSchema,
  GRACE_MS,
  GmCmdSchema,
  GmTakeoverSchema,
  HelloSchema,
  JokerBuySchema,
  JokerUseSchema,
  KategorieVoteSchema,
  PhaseReadySchema,
  PING_INTERVALL_MS,
  PlayerActionSchema,
  RadAktionSchema,
  RoomConfigSchema,
  RoomCreateSchema,
  ShakeTapSchema,
  TeamWahlSchema,
  TimePingSchema,
  VoteCastSchema,
  type Welcome,
} from "../../shared/protocol";
import type { AvatarFarbe } from "../../shared/ids";
import type { EngineAction } from "../engine/types";
import type { Room } from "../rooms/room";
import type { RoomManager } from "../rooms/room-manager";
import { handleGmCmd } from "./gm-commands";
import type { TunnelManager } from "./tunnel";

/** ADDITIVE Server-Dienste außerhalb des Raum-Modells (z. B. Internet-Link). */
export interface SocketExtras {
  /** Cloudflare-Quick-Tunnel (server/core/tunnel.ts) — optional (Tests/alt). */
  tunnel?: TunnelManager;
}

interface SocketState {
  room: Room | null;
  role: "screen" | "player" | "gm" | null;
  playerId: string | null;
  idemKeys: Set<string>;
  probeTimer: ReturnType<typeof setInterval> | null;
}

type Ack = (antwort: unknown) => void;

export function wireSockets(io: Server, manager: RoomManager, extras: SocketExtras = {}): void {
  // INTERNET-LINK (ADDITIV): der Tunnel ist SERVER-global (ein Prozess, ein
  // Tunnel) — Status-Übergänge gehen als Broadcast an alle Screen-/GM-Sockets
  // (socket.io-Raum "tunnel-status", Beitritt bei der Anmeldung unten).
  const tunnel = extras.tunnel ?? null;
  tunnel?.onStatus((status) => io.to("tunnel-status").emit("tunnel.status", status));

  // LOBBY (ADDITIV): Live-Update für abonnierte Landing-Clients — 1-s-Vergleich
  // statt Hooks an jeder Änderungsstelle (Join/Leave/Phase/Config/TTL greifen alle).
  let letzterLobbyStand = "";
  setInterval(() => {
    const lobbys = manager.lobbyListe();
    const stand = JSON.stringify(lobbys);
    if (stand === letzterLobbyStand) return;
    letzterLobbyStand = stand;
    io.to("lobby-browser").emit("lobby.update", { lobbys });
  }, 1_000);

  io.on("connection", (socket) => {
    const state: SocketState = {
      room: null,
      role: null,
      playerId: null,
      idemKeys: new Set(),
      probeTimer: null,
    };

    // #1 room.create — erzeugt Raum; Antwort {code, gmPin, qrPath}.
    // LOBBY (ADDITIV): oeffentlich/name — Sichtbarkeit ist Opt-in (Default privat).
    socket.on("room.create", (payload: unknown, ack?: Ack) => {
      const parsed = RoomCreateSchema.safeParse(payload);
      if (!parsed.success) return ack?.({ ok: false, error: "ungueltig" });
      const room = manager.erzeugeRaum(parsed.data.origin, {
        oeffentlich: parsed.data.oeffentlich,
        name: parsed.data.name,
      });
      if (!room) return ack?.({ ok: false, error: "max-rooms" });
      ack?.({ ok: true, code: room.code, gmPin: room.gmPin, qrPath: `/api/qr?code=${room.code}` });
    });

    // LOBBY (ADDITIV) room.config — Sichtbarkeit/Name ändern: nur der Screen
    // des Raums oder das aktive GM-Cockpit (Beobachter-GMs nicht).
    socket.on("room.config", (payload: unknown, ack?: Ack) => {
      const parsed = RoomConfigSchema.safeParse(payload);
      if (!parsed.success) return ack?.({ ok: false, error: "ungueltig" });
      if (!state.room) return ack?.({ ok: false, error: "kein-raum" });
      const darf =
        state.role === "screen" || (state.role === "gm" && state.room.istAktiverGm(socket.id));
      if (!darf) return ack?.({ ok: false, error: "keine-berechtigung" });
      manager.setzeLobbyEinstellungen(state.room, parsed.data);
      ack?.({ ok: true, name: state.room.lobbyName, oeffentlich: state.room.oeffentlich });
    });

    // LOBBY (ADDITIV) lobby.subscribe — Landing abonniert die Live-Liste.
    socket.on("lobby.subscribe", () => {
      void socket.join("lobby-browser");
      socket.emit("lobby.update", { lobbys: manager.lobbyListe() });
    });

    socket.on("lobby.unsubscribe", () => {
      void socket.leave("lobby-browser");
    });

    // #2 hello — Join UND Rejoin (mit Token: Slot-Restore). Antwort: welcome.
    socket.on("hello", (payload: unknown, ack?: Ack) => {
      const parsed = HelloSchema.safeParse(payload);
      if (!parsed.success) return ack?.({ ok: false, error: "ungueltig" });
      const hello = parsed.data;
      const room = manager.finde(hello.roomCode);
      if (!room) return ack?.({ ok: false, error: "raum-nicht-gefunden" });

      if (hello.role === "screen") {
        // Screen: tokenlos, mehrfach erlaubt; seine Origin bestimmt die Join-URL.
        if (hello.origin) room.origin = hello.origin;
        anmelden(room, "screen", null);
        return ack?.(welcome(room, "screen", null, null));
      }

      if (hello.role === "gm") {
        const session = hello.sessionToken ? room.sessions.restore(hello.sessionToken) : null;
        if (!session || session.role !== "gm") {
          if (hello.gmPin !== room.gmPin) return ack?.({ ok: false, error: "gm-pin-falsch" });
        }
        const token = session?.token ?? room.sessions.erstelle("gm", null).token;
        anmelden(room, "gm", null);
        // EIN aktives Cockpit: weitere GM-Verbindungen starten als Beobachter.
        const beobachter = room.gmAngemeldet(socket.id);
        return ack?.({ ...welcome(room, "gm", null, token), gmBeobachter: beobachter });
      }

      // Spieler: erst Token-Restore versuchen (Reconnect = Normalfall) …
      const session = hello.sessionToken ? room.sessions.restore(hello.sessionToken) : null;
      if (session && session.role === "player" && session.playerId) {
        anmelden(room, "player", session.playerId);
        room.applyAction({
          type: "presence",
          playerId: session.playerId,
          connected: true,
          graceUntil: null,
        });
        return ack?.(welcome(room, "player", session.playerId, session.token));
      }

      // … sonst Neu-Join (nur in der Lobby, 2–8-Grenzen prüft die Engine).
      // META (§7.1): Join MIT Profil — Name/Avatar kommen aus dem Profil-Store,
      // der Slot wird ans Profil gebunden (AT-Buchung + Stats-Zuordnung).
      const meta = room.deps.meta;
      if (hello.profileId !== undefined && meta !== undefined) {
        const profileId = hello.profileId;
        void meta
          .profilJoin(profileId, { pin: hello.profilPin, deviceToken: hello.deviceToken })
          .then((profil) => {
            if (!profil.ok || profil.name === undefined) {
              return ack?.({ ok: false, error: profil.error ?? "profil-fehler" });
            }
            const antwort = spielerJoin(room, profil.name, profil.avatar ?? "gelb");
            if (antwort.ok === true && antwort.playerId !== null) {
              // staerke (Lifetime-AT) füttert die Team-Auto-Balance (§1.4).
              room.bindeProfil(antwort.playerId, profileId, profil.staerke);
            }
            ack?.(antwort);
          });
        return;
      }
      if (!hello.name) return ack?.({ ok: false, error: "name-fehlt" });
      ack?.(spielerJoin(room, hello.name, hello.avatar ?? "gelb"));
    });

    /** Gemeinsamer Neu-Join-Pfad (Gast UND Profil): Engine-Join + Session + Slot. */
    function spielerJoin(
      room: Room,
      name: string,
      avatar: string,
    ): ({ ok: true } & Welcome) | { ok: false; error?: string; playerId?: null } {
      // Namens-Check (Eval 6): doppelte Namen ablehnen — der Client zeigt
      // „Name schon vergeben — bist du das?" mit Session-Restore-Hinweis.
      if (room.nameVergeben(name)) return { ok: false, error: "name-vergeben", playerId: null };
      const playerId = `p_${randomUUID().slice(0, 8)}`;
      const result = room.applyAction({
        type: "join",
        playerId,
        name,
        avatar: avatar as AvatarFarbe,
      });
      if (!result.ok) return { ok: false, error: result.error, playerId: null };
      const neueSession = room.sessions.erstelle("player", playerId);
      anmelden(room, "player", playerId);
      return welcome(room, "player", playerId, neueSession.token);
    }

    // #7 time.ping — Heartbeat auf App-Ebene + Zeit-Offset-Messung.
    socket.on("time.ping", (payload: unknown) => {
      const parsed = TimePingSchema.safeParse(payload);
      if (!parsed.success) return;
      socket.emit("time.pong", { t0: parsed.data.t0, serverTime: manager.clock.now() });
    });

    // time.probe-Echo — Server misst daraus den Median-RTT (Buzzer-Fairness §3.3).
    socket.on("time.probe", (payload: unknown) => {
      const t = (payload as { t?: unknown } | null)?.t;
      if (typeof t !== "number" || !state.room || !state.playerId) return;
      const rtt = manager.clock.now() - t;
      if (rtt >= 0 && rtt < 30_000) state.room.recordRtt(state.playerId, rtt);
    });

    // #6 sync.request — erzwingt Voll-Snapshot (Selbstheilung bei seq-Lücke).
    socket.on("sync.request", () => {
      if (!state.room || !state.role) return;
      state.room.sendSnapshot({ socket, role: state.role, playerId: state.playerId });
    });

    // #8 player.action — alle Minigame-Inputs, idemKey macht Retries idempotent.
    socket.on("player.action", (payload: unknown, ack?: Ack) => {
      const parsed = PlayerActionSchema.safeParse(payload);
      if (!parsed.success) return ack?.({ ok: false, error: "ungueltig" });
      if (!state.room || state.role !== "player" || !state.playerId) {
        return ack?.({ ok: false, error: "kein-spieler" });
      }
      if (state.idemKeys.has(parsed.data.idemKey)) return ack?.({ ok: true, dup: true });
      state.idemKeys.add(parsed.data.idemKey);
      const result = state.room.applyAction({
        type: "playerAction",
        playerId: state.playerId,
        minigameId: parsed.data.minigameId,
        action: { type: parsed.data.actionId, ...(parsed.data.payload as object) },
        atServerTime: manager.clock.now(),
      });
      ack?.(result);
    });

    // #9 buzz — Latenz-kompensierter Sonderfall von player.action (TECH-SPEC §3.3).
    socket.on("buzz", (payload: unknown, ack?: Ack) => {
      const parsed = BuzzSchema.safeParse(payload);
      if (!parsed.success) return ack?.({ ok: false, error: "ungueltig" });
      if (!state.room || state.role !== "player" || !state.playerId) {
        return ack?.({ ok: false, error: "kein-spieler" });
      }
      if (state.idemKeys.has(parsed.data.idemKey)) return ack?.({ ok: true, dup: true });
      state.idemKeys.add(parsed.data.idemKey);
      ack?.(state.room.applyBuzz(state.playerId, parsed.data));
    });

    // ---------- Engine-Ausbau: Spieler-Nachrichten der neuen Phasen ----------
    const spielerAktion = (
      event: string,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      schema: { safeParse(v: unknown): { success: boolean; data?: any } },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      toAction: (data: any, playerId: string) => EngineAction,
    ): void => {
      socket.on(event, (payload: unknown, ack?: Ack) => {
        const parsed = schema.safeParse(payload);
        if (!parsed.success) return ack?.({ ok: false, error: "ungueltig" });
        if (!state.room || state.role !== "player" || !state.playerId) {
          return ack?.({ ok: false, error: "kein-spieler" });
        }
        const idemKey = (parsed.data as { idemKey?: string }).idemKey;
        if (idemKey !== undefined) {
          if (state.idemKeys.has(idemKey)) return ack?.({ ok: true, dup: true });
          state.idemKeys.add(idemKey);
        }
        ack?.(state.room.applyAction(toAction(parsed.data, state.playerId)));
      });
    };

    spielerAktion("joker.use", JokerUseSchema, (d, playerId) => ({
      type: "jokerUse",
      playerId,
      jokerId: d.jokerId,
      stufe: d.stufe,
    }));
    spielerAktion("joker.buy", JokerBuySchema, (d, playerId) => ({
      type: "jokerBuy",
      playerId,
      jokerId: d.jokerId,
    }));
    spielerAktion("kategorie.vote", KategorieVoteSchema, (d, playerId) => ({
      type: "kategorieVote",
      playerId,
      kategorie: d.kategorie,
    }));
    spielerAktion("vote.cast", VoteCastSchema, (d, playerId) => ({
      type: "voteCast",
      playerId,
      option: d.option,
    }));
    spielerAktion("phase.ready", PhaseReadySchema, (d, playerId) =>
      d.was === "streik" ? { type: "playerStreik", playerId } : { type: "playerReady", playerId },
    );
    spielerAktion("rad.aktion", RadAktionSchema, (d, playerId) => ({
      type: "radAktion",
      playerId,
      wahl: d.wahl,
    }));
    spielerAktion("feedback.text", FeedbackTextSchema, (d, playerId) => ({
      type: "feedbackText",
      playerId,
      text: d.text,
    }));
    // v2 Sudden-Death: Kokosnuss-Shake-Taps (Batch ~250 ms, Server kappt).
    spielerAktion("shake.tap", ShakeTapSchema, (d, playerId) => ({
      type: "shakeTap",
      playerId,
      taps: d.taps,
    }));
    // Team-Modus „Affenbanden": Team-Wunsch in der Lobby (GAME-DESIGN §1.4).
    spielerAktion("team.wahl", TeamWahlSchema, (d, playerId) => ({
      type: "teamWahl",
      playerId,
      team: d.team,
    }));

    // #10 gm.cmd — EIN Kanal für alle GM-Kommandos; ACK gm.ack.
    // Meta-Kommandos (save.*, bot.*) sind async ⇒ ACK erst nach dem Promise.
    socket.on("gm.cmd", (payload: unknown, ack?: Ack) => {
      const parsed = GmCmdSchema.safeParse(payload);
      if (!parsed.success) return ack?.({ cmdId: "?", ok: false, error: "ungueltig" });
      if (!state.room || state.role !== "gm") {
        return ack?.({ cmdId: parsed.data.cmdId, ok: false, error: "kein-gm" });
      }
      // Beobachter-GMs kommandieren NICHT (EIN aktives Cockpit) — erst Takeover.
      if (!state.room.istAktiverGm(socket.id)) {
        return ack?.({ cmdId: parsed.data.cmdId, ok: false, error: "beobachter-modus" });
      }
      // raum.schliessen (Eval-7 P2 „max-rooms unter Last"): braucht den Manager
      // (Raum-Lebenszyklus) und lebt deshalb HIER statt in gm-commands.ts.
      // Nur im Ende-Screen — mitten im Match wäre der Knopf ein Show-Killer.
      if (parsed.data.cmd === "raum.schliessen") {
        if (state.room.state.phase !== "ende") {
          return ack?.({ cmdId: parsed.data.cmdId, ok: false, error: "nur-im-ende" });
        }
        manager.schliesseRaum(state.room, "gm-ende");
        return ack?.({ cmdId: parsed.data.cmdId, ok: true });
      }
      void Promise.resolve(handleGmCmd(state.room, parsed.data)).then((antwort) => ack?.(antwort));
    });

    // Welle 1 „Start/Skip ohne GameMaster": der SCREEN des Raums (Ersteller-
    // Gerät, iPad/TV) darf den Universal-Weiter drücken — Lobby: Match-Start,
    // sonst gm.next (Skip). Spieler und Beobachter bleiben außen vor.
    socket.on("screen.next", (_payload: unknown, ack?: Ack) => {
      if (!state.room || state.role !== "screen") {
        return ack?.({ ok: false, error: "kein-screen" });
      }
      const warLobby = state.room.state.phase === "lobby";
      const result = warLobby
        ? state.room.startMatch()
        : state.room.applyAction({ type: "gm.next" });
      if (result.ok) {
        state.room.gmLogEintrag(
          "screen.next",
          {},
          warLobby ? "Match gestartet (Screen)" : "Weiter (Screen)",
        );
      }
      ack?.(result);
    });

    // ---------- INTERNET-LINK (ADDITIV): Tunnel-Kommandos + Status ----------
    // Berechtigt sind NUR der Screen des Raums (Ersteller-Gerät) und das
    // AKTIVE GM-Cockpit — Spieler und Beobachter-GMs starten keine Tunnel.
    const tunnelBerechtigt = (): boolean =>
      state.room !== null &&
      (state.role === "screen" || (state.role === "gm" && state.room.istAktiverGm(socket.id)));

    socket.on("tunnel.start", (_payload: unknown, ack?: Ack) => {
      if (!tunnel) return ack?.({ ok: false, error: "kein-tunnel" });
      if (!tunnelBerechtigt()) return ack?.({ ok: false, error: "keine-berechtigung" });
      ack?.({ ok: true, status: tunnel.start() });
    });

    socket.on("tunnel.stop", (_payload: unknown, ack?: Ack) => {
      if (!tunnel) return ack?.({ ok: false, error: "kein-tunnel" });
      if (!tunnelBerechtigt()) return ack?.({ ok: false, error: "keine-berechtigung" });
      ack?.({ ok: true, status: tunnel.stop() });
    });

    // gm.takeover — Beobachter übernimmt das aktive Cockpit (NUR mit PIN).
    socket.on("gm.takeover", (payload: unknown, ack?: Ack) => {
      const parsed = GmTakeoverSchema.safeParse(payload);
      if (!parsed.success) return ack?.({ ok: false, error: "ungueltig" });
      if (!state.room || state.role !== "gm") return ack?.({ ok: false, error: "kein-gm" });
      ack?.(state.room.gmTakeover(socket.id, parsed.data.pin));
    });

    // Disconnect: Spieler-Drop ⇒ „offline"-Badge + Grace-Period (kein Rauswurf).
    // Doppelgerät (Eval-7 P1): offline NUR, wenn KEIN weiterer Socket mit
    // derselben playerId mehr verbunden ist — sonst setzte ein geschlossener
    // Zweit-Tab den Spieler dauerhaft auf Falsch-Offline (Affenbank/Votings!).
    socket.on("disconnect", () => {
      if (state.probeTimer !== null) clearInterval(state.probeTimer);
      if (!state.room) return;
      state.room.detachClient(socket.id);
      if (state.role === "player" && state.playerId) {
        if (state.room.hatVerbundenenSpieler(state.playerId)) return;
        state.room.applyAction({
          type: "presence",
          playerId: state.playerId,
          connected: false,
          graceUntil: manager.clock.now() + GRACE_MS,
        });
      }
    });

    function anmelden(room: Room, role: "screen" | "player" | "gm", playerId: string | null): void {
      if (state.room && state.room !== room) state.room.detachClient(socket.id);
      state.room = room;
      state.role = role;
      state.playerId = playerId;
      room.attachClient({ socket: socket as Socket, role, playerId });
      // INTERNET-LINK: Screen+GM abonnieren den Tunnel-Status (Broadcast-Raum)
      // und bekommen den AKTUELLEN Stand sofort (Reconnect/spätes Cockpit).
      if (tunnel && (role === "screen" || role === "gm")) {
        void socket.join("tunnel-status");
        socket.emit("tunnel.status", tunnel.status());
      }
      // Spieler bekommen periodische time.probe-Pakete (Median-RTT-Messung).
      if (state.probeTimer !== null) clearInterval(state.probeTimer);
      if (role === "player") {
        const probe = (): void => {
          socket.emit("time.probe", { t: manager.clock.now() });
        };
        probe();
        state.probeTimer = setInterval(probe, PING_INTERVALL_MS);
      }
    }

    function welcome(
      room: Room,
      role: "screen" | "player" | "gm",
      playerId: string | null,
      sessionToken: string | null,
    ): { ok: true } & Welcome {
      return {
        ok: true,
        playerId,
        sessionToken,
        roomCode: room.code,
        ...(role !== "player" ? { gmPin: room.gmPin } : {}),
        seq: room.seq,
        view: room.viewFuer(role, playerId ?? undefined),
        serverTime: manager.clock.now(),
      };
    }
  });
}
