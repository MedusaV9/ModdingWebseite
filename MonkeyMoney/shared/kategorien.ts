// Anzeige-Labels für Kategorien + Schwierigkeiten — DER zentrale Helfer für
// Erklärkarten, Votings und Screen-Badges (Playtest 3: Rohlabels wie
// „staedte wahrzeichen" / „medium / hard" wirkten technisch). Die Namen kommen
// aus content/taxonomie.json (Ober- UND Unterkategorien); unbekannte Ids
// fallen auf eine Titel-Schreibung des Slugs zurück.
import taxonomie from "../content/taxonomie.json";

const KATEGORIE_NAMEN = new Map<string, string>();
for (const ober of taxonomie.oberkategorien) KATEGORIE_NAMEN.set(ober.id, ober.name);
for (const unter of taxonomie.unterkategorien) KATEGORIE_NAMEN.set(unter.slug, unter.name);

const UNTER_ZU_OBER = new Map<string, string>();
for (const unter of taxonomie.unterkategorien) UNTER_ZU_OBER.set(unter.slug, unter.oberkategorie);

/** "staedte_wahrzeichen" → "Städte & Wahrzeichen" (Taxonomie-Name oder Titel-Fallback). */
export function kategorieLabel(id: string): string {
  const name = KATEGORIE_NAMEN.get(id);
  if (name !== undefined) return name;
  return id
    .split("_")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

/** "minecraft" → "Gaming · Minecraft" (Ober · Unter) — der Kontext-Anker fürs
 * Kategorie-Badge über JEDER Frage (Eval 5: Franchise-Fragen ohne Universum).
 * Ohne bekannte Oberkategorie bleibt nur das Unter-Label. */
export function kategoriePfadLabel(unterSlug: string): string {
  const unterLabel = kategorieLabel(unterSlug);
  const ober = UNTER_ZU_OBER.get(unterSlug);
  if (ober === undefined) return unterLabel;
  const oberLabel = kategorieLabel(ober);
  return oberLabel === unterLabel ? unterLabel : `${oberLabel} · ${unterLabel}`;
}

/** Engine-Schwierigkeit → deutsches Show-Label (ULTRAHARD bleibt der Brand-Schrei). */
const SCHWIERIGKEIT_LABELS: Record<string, string> = {
  easy: "Leicht",
  medium: "Mittel",
  hard: "Schwer",
  ultrahard: "ULTRAHARD",
};

export function schwierigkeitLabel(schwierigkeit: string): string {
  return SCHWIERIGKEIT_LABELS[schwierigkeit] ?? schwierigkeit;
}
