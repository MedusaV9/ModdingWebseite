class_name SoulMood
extends RefCounted
## Durchgehende Stimmung (SEELE-2): EINE Laune 0..100, die sich über Stunden
## entwickelt und alles färbt — Ruhe-Gesicht, Ohrenstellung, Idle-Auswahl,
## Gruß-Verhalten, Stimme. Sie ersetzt die harte „happy“-Grundeinstellung.
##
## Modell (Web-Parität + Trägheit):
##  - ZIEL = Stats.mood (§C1: 0,35·min + 0,65·avg, Erschöpfungs-Deckel,
##    Früh-Weck-Debuff) — die Web-Formel bleibt die Wahrheit über „wie es
##    ihm gehen MÜSSTE“.
##  - WERT nähert sich dem Ziel exponentiell mit HALBWERT_MIN Halbwertszeit:
##    Gooby ist nicht schlagartig elend, wenn ein Wert kippt, und nicht
##    schlagartig selig nach einer Karotte — Stimmung hat Gedächtnis.
##  - Ereignis-STÖSSE (füttern, streicheln, Wiedersehen) heben/senken den
##    Wert sofort um wenige Punkte; die Trägheit zieht ihn danach wieder
##    Richtung Stats-Wahrheit.
##
## PURE Statics, Zeit wird IMMER hereingereicht (headless testbar). Der
## Save-Anteil lebt additiv im Soul-Slice (SoulState, Schlüssel "stimmung").

const Stats := preload("res://scripts/logic/stats.gd")

const DEFAULT_WERT := 62.0
## Halbwertszeit der Annäherung ans Ziel (Minuten): Stimmung entwickelt sich
## über Stunden, nicht Sekunden.
const HALBWERT_MIN := 90.0
## Über längere Lücken (App zu) konvergiert die Stimmung praktisch ganz.
const MAX_SCHRITT_MIN := 12.0 * 60.0
## Ereignis-Stöße bleiben klein — die Trägheit soll spürbar bleiben.
const STOSS_MAX := 8.0

## Band-Reihenfolge (Index steigt mit Laune) für Gates in Idle-Defs.
const BAND_ORDNUNG: Array[String] = ["miserable", "grumpy", "neutral", "happy", "ecstatic"]
## Band → Rig-Emotion. "angry" IST das Web-"grumpy" (asymmetrische Ohren,
## s. gooby_rig.gd EMOTION_POSES-Kommentar).
const BAND_EMOTION := {
	"ecstatic": "ecstatic",
	"happy": "happy",
	"neutral": "neutral",
	"grumpy": "angry",
	"miserable": "sad",
}

## Web-§C1-Schwellen fürs Ruhe-Gesicht (statOverride der emotions.js).
const ERSCHOEPFT_ENERGIE := 15.0


static func default_stimmung() -> Dictionary:
	return {"wert": DEFAULT_WERT, "aktualisiertMs": 0}


## Self-Heal wie SoulState.normalize_slice: kaputte Typen → Defaults.
static func normalize(raw: Variant) -> Dictionary:
	var out := default_stimmung()
	if raw is Dictionary:
		var wert: Variant = (raw as Dictionary).get("wert")
		if (wert is int or wert is float) and is_finite(float(wert)):
			out["wert"] = clampf(float(wert), 0.0, 100.0)
		var at: Variant = (raw as Dictionary).get("aktualisiertMs")
		if at is int or at is float:
			out["aktualisiertMs"] = maxi(0, int(at))
	return out


## Wohin die Stimmung will: die Web-Mood-Formel (§C1) inkl. Debuff.
static func ziel(stats: Dictionary, grumpy_debuff := 0.0) -> float:
	return Stats.mood(stats, {"debuff": grumpy_debuff})


## Einen Zeitschritt Richtung Ziel gehen (exponentielle Annäherung mit
## HALBWERT_MIN). Gibt eine NEUE stimmung-Map zurück; dt kommt aus
## aktualisiertMs und ist gegen Uhr-Sprünge/Riesenlücken geklammert.
static func advance(stimmung: Dictionary, ziel_wert: float, now_ms: int) -> Dictionary:
	var s := normalize(stimmung)
	var last := int(s["aktualisiertMs"])
	var dt_min := 0.0
	if last > 0 and now_ms > last:
		dt_min = minf(float(now_ms - last) / 60_000.0, MAX_SCHRITT_MIN)
	var anteil := 1.0 - pow(0.5, dt_min / HALBWERT_MIN)
	var wert := float(s["wert"]) + (clampf(ziel_wert, 0.0, 100.0) - float(s["wert"])) * anteil
	return {"wert": clampf(wert, 0.0, 100.0), "aktualisiertMs": now_ms}


## Ereignis-Stoß (gefüttert +, lange allein gelassen −, ...). Bewusst
## gedeckelt: kein Ereignis wirft die Laune um mehr als STOSS_MAX.
static func bump(stimmung: Dictionary, delta: float, now_ms: int) -> Dictionary:
	var s := normalize(stimmung)
	var wert := float(s["wert"]) + clampf(delta, -STOSS_MAX, STOSS_MAX)
	return {
		"wert": clampf(wert, 0.0, 100.0), "aktualisiertMs": maxi(int(s["aktualisiertMs"]), now_ms)
	}


static func band(wert: float) -> String:
	return Stats.mood_band(wert)


static func band_index(band_id: String) -> int:
	return maxi(0, BAND_ORDNUNG.find(band_id))


## Ruhe-Emotion (das Gesicht ZWISCHEN den Momenten) nach Web-Ableitung:
## krank → sad (Pflege-Vorrang), erschöpft → sleepy (statOverride §C1),
## sonst das Band-Gesicht. Ersetzt das hart verdrahtete "happy".
static func ruhe_emotion(wert: float, stats: Dictionary, krank_grad := 0) -> String:
	if krank_grad > 0:
		return "sad"
	var energie: Variant = stats.get("energy")
	if (energie is int or energie is float) and float(energie) <= ERSCHOEPFT_ENERGIE:
		return "sleepy"
	return str(BAND_EMOTION.get(band(wert), "neutral"))


## Ausdrucks-Parameter fürs Gesicht (GoobyExpressions) — kontinuierlich,
## damit man ZWISCHENTÖNE sieht, nicht nur 5 Vorlagen:
##  ohren:  zusätzlicher Ohren-Droop 0..0.45 (rad-Parameter der Rig-Pose;
##          leichtes Aufperken −0.05 bei bester Laune)
##  lider:  schwere Lider 0..0.4 (auf den blink-Shapekey gelegt)
##  kopf:   Kopf-Häng-Zuschlag 0..0.12 (rad)
##  energie: 0.35..1.0 — skaliert Mikro-Bewegung, Reaktionstempo, Idle-Takt
static func ausdruck(wert: float) -> Dictionary:
	var w := clampf(wert, 0.0, 100.0)
	var tief := clampf((60.0 - w) / 60.0, 0.0, 1.0)
	var hoch := clampf((w - 80.0) / 20.0, 0.0, 1.0)
	return {
		"ohren": 0.45 * tief - 0.05 * hoch,
		"lider": 0.4 * clampf((40.0 - w) / 40.0, 0.0, 1.0),
		"kopf": 0.12 * tief,
		"energie": clampf(0.35 + 0.65 * (w / 100.0) + 0.1 * hoch, 0.35, 1.1),
	}


## Stimm-Parameter (GoobyVoice): Tonhöhe, Tempo und Länge folgen der Laune —
## elend = tiefer, langsamer, wortkarger; blendend = heller, flotter.
static func stimme(wert: float) -> Dictionary:
	var t := clampf(wert, 0.0, 100.0) / 100.0
	return {
		"pitch": lerpf(0.9, 1.08, t),
		"tempo": lerpf(0.8, 1.1, t),
		"laenge": lerpf(0.55, 1.0, clampf(t * 1.6, 0.0, 1.0)),
	}


## Faktor auf den Idle-Takt: schlechte Laune = träger (längere Pausen),
## gute Laune = lebhafter.
static func idle_takt_faktor(wert: float) -> float:
	return lerpf(1.8, 0.85, clampf(wert, 0.0, 100.0) / 100.0)


## Laune-Gate für Content-Defs: optionale Felder "mindest_laune" /
## "hoechst_laune" (Band-Ids). Ein elender Gooby tanzt nicht und reißt
## keine TV-Witze; ein seliger setzt sich nicht in die Trauerecke.
static func def_erlaubt(def: Dictionary, band_id: String) -> bool:
	var index := band_index(band_id)
	var minimum := str(def.get("mindest_laune", ""))
	if not minimum.is_empty() and index < band_index(minimum):
		return false
	var maximum := str(def.get("hoechst_laune", ""))
	if not maximum.is_empty() and index > band_index(maximum):
		return false
	return true
