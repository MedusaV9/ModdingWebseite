// Meta-API transport-neutral (W4 iPad-Standalone): EINE Routen-Logik für
// BEIDE Transporte — im Node-Pfad hängt http-api.ts sie als Express-Catch-all
// unter /api/meta ein, im Standalone bedient server/host-browser/boot.ts das
// Wire-Event "meta.http" (Telefone erreichen den Browser-Server ja NUR über
// das Relay, HTTP liefert dort nur statische Dateien). Die Antworten sind
// bit-identisch zum bisherigen Express-Pfad (Status-Codes + Bodies) — die
// Clients (meta-join/meta-ende/meta-gm/meta-landing) merken keinen
// Unterschied, sie tauschen nur fetch gegen metaFetch.
import {
  BOT_PERSONAS,
  SHOP_ITEMS,
  WILLKOMMEN_ITEM,
  preisInAbenden,
  seltenheitFuerPreis,
  type MetaProfil,
} from "../../shared/meta";
import { anzeigeAvatar } from "./profile-store";
import type { MetaService } from "./index";

/** Request über beide Transporte: Pfad MIT /api/meta-Präfix und Query-String. */
export interface MetaWireRequest {
  method: string;
  pfad: string;
  body?: unknown;
}

export interface MetaWireAntwort {
  status: number;
  body: unknown;
}

/** Profil-Antwort fürs Wire (ohne pinHash/deviceTokens — nie herausgeben!). */
function profilAntwort(p: MetaProfil): Record<string, unknown> {
  return {
    profileId: p.profileId,
    name: p.name,
    avatarBasis: p.avatar,
    avatar: anzeigeAvatar(p),
    at: p.at,
    besitz: p.besitz,
    ausgeruestet: p.ausgeruestet,
    gesperrt: p.pinHash !== null,
  };
}

function zugriffAus(body: Record<string, unknown>): { pin?: string; deviceToken?: string } {
  return {
    pin: typeof body.pin === "string" ? body.pin : undefined,
    deviceToken: typeof body.deviceToken === "string" ? body.deviceToken : undefined,
  };
}

const ok = (body: unknown): MetaWireAntwort => ({ status: 200, body });
const fehler = (status: number, error: string): MetaWireAntwort => ({ status, body: { error } });

/**
 * Bearbeitet EINEN Meta-Request (Pfad relativ zur Origin, z. B.
 * "/api/meta/profile?device=d_1"). Unbekannte Routen ⇒ 404 — Validierung wie
 * bisher pro Route (das Wire ist Systemgrenze, Payloads sind Nutzereingaben).
 */
export async function bearbeiteMetaRequest(
  meta: MetaService,
  req: MetaWireRequest,
): Promise<MetaWireAntwort> {
  const [pfadRoh, queryRoh] = String(req.pfad).split("?", 2);
  const query = new URLSearchParams(queryRoh ?? "");
  const pfad = pfadRoh.startsWith("/api/meta") ? pfadRoh.slice("/api/meta".length) : pfadRoh;
  const segmente = pfad.split("/").filter((s) => s.length > 0);
  const methode = req.method.toUpperCase();
  const b = (typeof req.body === "object" && req.body !== null ? req.body : {}) as Record<
    string,
    unknown
  >;

  const route = `${methode} /${segmente
    .map((s, i) => (i === 1 && segmente[0] === "profile" && s !== "laden" ? ":id" : s))
    .join("/")}`;
  const id = segmente[0] === "profile" ? (segmente[1] ?? "") : "";

  switch (route) {
    // ---------- Profile (§7.1) ----------
    case "GET /profile": {
      const device = query.get("device") ?? undefined;
      try {
        return ok({ profile: await meta.profile.liste(device) });
      } catch {
        return fehler(500, "profil-lesefehler");
      }
    }
    case "POST /profile": {
      const name = typeof b.name === "string" ? b.name.trim() : "";
      if (name.length === 0) return fehler(400, "name-fehlt");
      try {
        const p = await meta.profile.erstelle({
          name,
          avatar: typeof b.avatar === "string" ? b.avatar : "gelb",
          pin: typeof b.pin === "string" && b.pin.length >= 4 ? b.pin : undefined,
          deviceToken: typeof b.deviceToken === "string" ? b.deviceToken : undefined,
        });
        return ok({ profil: profilAntwort(p) });
      } catch {
        return fehler(500, "profil-schreibfehler");
      }
    }
    case "POST /profile/laden": {
      const name = typeof b.name === "string" ? b.name.trim() : "";
      if (name.length === 0) return fehler(400, "name-fehlt");
      try {
        const r = await meta.profile.ladeNachName(name, zugriffAus(b));
        if ("fehler" in r) return fehler(r.fehler === "profil-unbekannt" ? 404 : 403, r.fehler);
        return ok({ profil: profilAntwort(r) });
      } catch {
        return fehler(500, "profil-lesefehler");
      }
    }
    case "POST /profile/:id/login": {
      try {
        const r = await meta.profile.login(id, zugriffAus(b));
        if ("fehler" in r) return fehler(403, r.fehler);
        return ok({ profil: profilAntwort(r) });
      } catch {
        return fehler(500, "profil-lesefehler");
      }
    }
    case "GET /profile/:id/karte": {
      try {
        const karte = await meta.profilKarte(id);
        return karte === null ? fehler(404, "profil-unbekannt") : ok({ karte });
      } catch {
        return fehler(500, "karten-fehler");
      }
    }
    case "POST /profile/:id/update": {
      try {
        const r = await meta.profile.aktualisiere(
          id,
          {
            name: typeof b.name === "string" ? b.name : undefined,
            avatar: typeof b.avatar === "string" ? b.avatar : undefined,
            pin: b.neuePin === null ? null : typeof b.neuePin === "string" ? b.neuePin : undefined,
          },
          zugriffAus(b),
        );
        if ("fehler" in r) return fehler(403, r.fehler);
        return ok({ profil: profilAntwort(r) });
      } catch {
        return fehler(500, "profil-schreibfehler");
      }
    }

    // ---------- Shop (§7.4 — KEIN Echtgeld, AT only) ----------
    case "GET /shop":
      return ok({
        items: [...SHOP_ITEMS, WILLKOMMEN_ITEM].map((i) => ({
          ...i,
          seltenheit: seltenheitFuerPreis(i.preis),
          inAbenden: preisInAbenden(i.preis),
        })),
      });
    case "POST /profile/:id/kaufe": {
      try {
        const r = await meta.profile.kaufe(id, String(b.itemId ?? ""), zugriffAus(b));
        if ("fehler" in r) return fehler(409, r.fehler);
        return ok({ profil: profilAntwort(r) });
      } catch {
        return fehler(500, "kauf-fehler");
      }
    }
    case "POST /profile/:id/ruestung": {
      try {
        const itemId = b.itemId === null ? null : String(b.itemId ?? "");
        const r = await meta.profile.ruesteAus(
          id,
          String(b.slot ?? "") as never,
          itemId,
          zugriffAus(b),
        );
        if ("fehler" in r) return fehler(409, r.fehler);
        return ok({ profil: profilAntwort(r) });
      } catch {
        return fehler(500, "ruestung-fehler");
      }
    }

    // ---------- Bananen-Pass & Match-Ende-Meta ----------
    case "GET /profile/:id/pass": {
      try {
        return ok({ pass: await meta.passUebersicht(id) });
      } catch {
        return fehler(500, "pass-fehler");
      }
    }
    case "GET /profile/:id/match-meta":
      return ok({ ergebnis: meta.matchErgebnis(id) });

    // ---------- Bestenlisten (§7.3) ----------
    case "GET /boards": {
      try {
        return ok({ boards: await meta.boards() });
      } catch {
        return fehler(500, "board-fehler");
      }
    }
    case "GET /profile/:id/board-fortschritt": {
      try {
        const fortschritt = await meta.boardFortschritt(id);
        return fortschritt === null ? fehler(404, "profil-unbekannt") : ok({ fortschritt });
      } catch {
        return fehler(500, "board-fehler");
      }
    }

    // ---------- Übungsmodus (§6.2 „Trainingslager") ----------
    case "GET /uebung/kategorien":
      return ok({ kategorien: meta.practice.kategorien() });
    case "POST /uebung/frage": {
      try {
        const r = await meta.practice.naechsteFrage(String(b.key ?? "anonym"), {
          kategorie: typeof b.kategorie === "string" && b.kategorie ? b.kategorie : undefined,
          schwierigkeit:
            typeof b.schwierigkeit === "string" && b.schwierigkeit ? b.schwierigkeit : undefined,
        });
        return "fehler" in r ? fehler(404, r.fehler) : ok(r);
      } catch {
        return fehler(500, "uebung-fehler");
      }
    }
    case "POST /uebung/antwort": {
      try {
        const r = await meta.practice.antwort(
          String(b.key ?? "anonym"),
          String(b.questionId ?? ""),
          Number(b.choice ?? -1),
          Number(b.dauerMs ?? 0),
        );
        return "fehler" in r ? fehler(409, r.fehler) : ok(r);
      } catch {
        return fehler(500, "uebung-fehler");
      }
    }
    case "POST /uebung/tipp": {
      const r = meta.practice.tipp(String(b.key ?? "anonym"), String(b.questionId ?? ""));
      return "fehler" in r ? fehler(409, r.fehler) : ok(r);
    }
    case "GET /uebung/stats": {
      try {
        return ok({ stats: await meta.practice.stats(query.get("key") ?? "anonym") });
      } catch {
        return fehler(500, "uebung-fehler");
      }
    }

    // ---------- Save-Slots (GM lädt aus der Lobby) ----------
    case "GET /saves": {
      try {
        return ok({ slots: await meta.saves.liste() });
      } catch {
        return fehler(500, "save-fehler");
      }
    }

    // ---------- Bot-Personas (GM-Lobby-Auswahl) ----------
    case "GET /personas":
      return ok({
        personas: BOT_PERSONAS.map((p) => ({ id: p.id, name: p.name, avatar: p.avatar })),
      });

    default:
      return fehler(404, "unbekannte-route");
  }
}
