// Die 5 Admin-Reports (GAME-DESIGN §7.6) als pure Ableitungen aus den
// materialisierten Aggregaten + dem Content-Katalog:
// 1 Fehlerhaft-Queue · 2 Schwierigkeits-Drift (Umstufung nach CONTENT-PLAN-
// Bändern) · 3 Abnutzung/zu-oft-gespielt · 4 Kategorie-Lücken (Soll-Logik aus
// tools/content/stats.mjs) · 5 Feedback-Inbox.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { bereinigteQuote, driftUrteil } from "../../shared/meta";
import type { AggregatDaten, FeedbackEintrag } from "./aggregate";

export interface KatalogEintrag {
  text: string;
  kategorie: string; // Unterkategorie-Slug
  oberkategorie: string;
  schwierigkeit: string; // Engine-Stufe (easy|medium|hard|ultrahard)
}

export interface AbnutzungZeile {
  questionId: string;
  text: string;
  ausspielungen: number;
  in60Tagen: number;
  cooldownEmpfohlen: boolean; // ab 3× in 60 Tagen (§7.6/3)
  quote: number | null;
  frageDerSchande: boolean; // 0-%-Quote bei ≥ 10 Antworten
}

export interface DriftZeile {
  questionId: string;
  text: string;
  stufe: string;
  quote: number | null;
  antworten: number;
  urteil: "vorschlag" | "quarantaene";
  zielStufe?: string;
}

export interface FehlerhaftZeile {
  questionId: string;
  text: string;
  anzahl: number;
  flags: { grund: string; ts: number; matchId: string }[];
  ausRotation: boolean; // ab 2 Flags automatisch raus (§7.6/1)
}

export interface LueckenZeile {
  slug: string;
  oberkategorie: string;
  kern: boolean;
  ist: Record<string, number>; // leicht|mittel|schwer|ultrahard
  soll: Record<string, number>;
  luecke: number;
  gespielt60: number;
  reichweiteAbende: number | null; // Vorrat ÷ Verbrauch/Abend (null = kein Verbrauch)
}

export interface AdminReports {
  aktualisiertTs: number;
  matchesVerarbeitet: number;
  fehlerhaft: FehlerhaftZeile[];
  drift: DriftZeile[];
  abnutzung: AbnutzungZeile[];
  luecken: { zeilen: LueckenZeile[]; gesamtIst: number; gesamtSoll: number; gesamtLuecke: number };
  feedback: FeedbackEintrag[];
}

const TAGE_60_MS = 60 * 24 * 60 * 60 * 1000;
const STUFEN = ["leicht", "mittel", "schwer", "ultrahard"] as const;
// Mengen-Soll je Unter-Kategorie × Schwierigkeit (CONTENT-PLAN §4.2 — identisch
// zu tools/content/stats.mjs).
const SOLL_KERN: Record<string, number> = { leicht: 20, mittel: 20, schwer: 15, ultrahard: 5 };
const SOLL_STANDARD: Record<string, number> = { leicht: 10, mittel: 10, schwer: 6, ultrahard: 2 };

const ENGINE_NACH_PLAN: Record<string, string> = {
  easy: "leicht",
  medium: "mittel",
  hard: "schwer",
  ultrahard: "ultrahard",
};

function findeContentDir(): string | null {
  const kandidaten = [
    resolve(process.cwd(), "content"),
    resolve(fileURLToPath(new URL(".", import.meta.url)), "../../content"),
  ];
  for (const pfad of kandidaten) if (existsSync(pfad)) return pfad;
  return null;
}

interface RohFrage {
  id: string;
  unterkategorie: string;
  schwierigkeit: string;
}

/** Ist-Zählung über ALLE Pack-Fragen (auch nicht-choice4) — wie stats.mjs. */
function zaehlePacks(contentDir: string): Map<string, Record<string, number>> {
  const ist = new Map<string, Record<string, number>>();
  const stapel = [join(contentDir, "packs")];
  while (stapel.length > 0) {
    const dir = stapel.pop() as string;
    if (!existsSync(dir)) continue;
    for (const eintrag of readdirSync(dir)) {
      const voll = join(dir, eintrag);
      if (statSync(voll).isDirectory()) {
        stapel.push(voll);
      } else if (eintrag.endsWith(".json")) {
        try {
          const pack = JSON.parse(readFileSync(voll, "utf8")) as { fragen?: RohFrage[] };
          for (const f of pack.fragen ?? []) {
            const zeile = ist.get(f.unterkategorie) ?? {
              leicht: 0,
              mittel: 0,
              schwer: 0,
              ultrahard: 0,
            };
            if ((STUFEN as readonly string[]).includes(f.schwierigkeit)) {
              zeile[f.schwierigkeit] += 1;
            }
            ist.set(f.unterkategorie, zeile);
          }
        } catch {
          // kaputtes Pack: der Loader meckert beim Boot — hier still überspringen
        }
      }
    }
  }
  return ist;
}

export function baueReports(
  agg: AggregatDaten,
  katalog: Map<string, KatalogEintrag>,
  now: number,
): AdminReports {
  const text = (qid: string): string => katalog.get(qid)?.text ?? qid;

  // ---------- 1) Fehlerhaft-Queue ----------
  const fehlerhaft: FehlerhaftZeile[] = Object.entries(agg.fragen)
    .filter(([, f]) => f.flags.length > 0)
    .map(([qid, f]) => ({
      questionId: qid,
      text: text(qid),
      anzahl: f.flags.length,
      flags: f.flags.slice(-5),
      ausRotation: f.flags.length >= 2,
    }))
    .sort((a, b) => b.anzahl - a.anzahl);

  // ---------- 2) Schwierigkeits-Drift (Bänder aus CONTENT-PLAN §2.3) ----------
  const drift: DriftZeile[] = [];
  for (const [qid, f] of Object.entries(agg.fragen)) {
    const info = katalog.get(qid);
    if (!info) continue;
    const urteil = driftUrteil(info.schwierigkeit, f.richtig, f.antworten);
    if (urteil.art !== "vorschlag" && urteil.art !== "quarantaene") continue;
    drift.push({
      questionId: qid,
      text: info.text,
      stufe: info.schwierigkeit,
      quote: urteil.quote,
      antworten: f.antworten,
      urteil: urteil.art,
      zielStufe: urteil.zielStufe,
    });
  }
  drift.sort((a, b) => b.antworten - a.antworten);

  // ---------- 3) Abnutzung / zu-oft-gespielt ----------
  const abnutzung: AbnutzungZeile[] = Object.entries(agg.fragen)
    .filter(([, f]) => f.ausspielungen > 0)
    .map(([qid, f]) => {
      const in60 = f.gespieltTs.filter((ts) => now - ts < TAGE_60_MS).length;
      const quote = bereinigteQuote(f.richtig, f.antworten);
      return {
        questionId: qid,
        text: text(qid),
        ausspielungen: f.ausspielungen,
        in60Tagen: in60,
        cooldownEmpfohlen: in60 >= 3,
        quote,
        frageDerSchande: f.antworten >= 10 && f.richtig === 0,
      };
    })
    .sort((a, b) => b.in60Tagen - a.in60Tagen || b.ausspielungen - a.ausspielungen)
    .slice(0, 30);

  // ---------- 4) Kategorie-Lücken (Soll aus stats.mjs, + Reichweiten-Prognose) ----------
  const contentDir = findeContentDir();
  const zeilen: LueckenZeile[] = [];
  let gesamtIst = 0;
  let gesamtSoll = 0;
  let gesamtLuecke = 0;
  if (contentDir !== null) {
    const ist = zaehlePacks(contentDir);
    let taxonomie: {
      unterkategorien: { slug: string; oberkategorie: string; kern?: boolean }[];
    } | null = null;
    try {
      taxonomie = JSON.parse(readFileSync(join(contentDir, "taxonomie.json"), "utf8"));
    } catch {
      taxonomie = null;
    }
    // Verbrauch: Ausspielungen der letzten 60 Tage je Unterkategorie + Spielabende.
    const verbrauch = new Map<string, number>();
    const abendeSet = new Set<string>();
    for (const [qid, f] of Object.entries(agg.fragen)) {
      const slug = katalog.get(qid)?.kategorie;
      for (const ts of f.gespieltTs) {
        if (now - ts >= TAGE_60_MS) continue;
        abendeSet.add(new Date(ts).toISOString().slice(0, 10));
        if (slug !== undefined) verbrauch.set(slug, (verbrauch.get(slug) ?? 0) + 1);
      }
    }
    const abende = Math.max(1, abendeSet.size);
    const unterkategorien =
      taxonomie?.unterkategorien ??
      [...ist.keys()].map((slug) => ({ slug, oberkategorie: "?", kern: false }));
    for (const u of unterkategorien) {
      const soll = u.kern ? SOLL_KERN : SOLL_STANDARD;
      const zaehler = ist.get(u.slug) ?? { leicht: 0, mittel: 0, schwer: 0, ultrahard: 0 };
      const summeIst = STUFEN.reduce((s, st) => s + zaehler[st], 0);
      const summeSoll = STUFEN.reduce((s, st) => s + soll[st], 0);
      const luecke = STUFEN.reduce((s, st) => s + Math.max(0, soll[st] - zaehler[st]), 0);
      gesamtIst += summeIst;
      gesamtSoll += summeSoll;
      gesamtLuecke += luecke;
      const v60 = verbrauch.get(u.slug) ?? 0;
      zeilen.push({
        slug: u.slug,
        oberkategorie: u.oberkategorie,
        kern: u.kern === true,
        ist: zaehler,
        soll,
        luecke,
        gespielt60: v60,
        reichweiteAbende: v60 > 0 ? Math.round(summeIst / (v60 / abende)) : null,
      });
    }
    zeilen.sort((a, b) => b.luecke - a.luecke || Number(b.kern) - Number(a.kern));
  }

  return {
    aktualisiertTs: agg.aktualisiertTs,
    matchesVerarbeitet: agg.verarbeitet.length,
    fehlerhaft,
    drift,
    abnutzung,
    luecken: { zeilen, gesamtIst, gesamtSoll, gesamtLuecke },
    feedback: [...agg.feedback].sort((a, b) => b.ts - a.ts).slice(0, 100),
  };
}

export { ENGINE_NACH_PLAN };
