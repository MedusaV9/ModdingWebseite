class_name HimmelStimmungen
extends RefCounted
## Himmel-Stimmungen aller GOOBY-Welten (FB-2) — PURE + headless-testbar.
## Sieben handgestimmte Pastell-Stimmungen (klarer Morgen, Mittag, goldene
## Stunde, Abendrot, Nacht, bedeckt, Gewitter) als Uniform-Sätze für den
## prozeduralen Sky-Shader (assets/sky/gooby_himmel.gdshader). `parameter()`
## mischt deterministisch: erst die Tageszeit über Keyframes, dann das
## Wetter (Bewölkung → bedeckt, Gewitter → Gewitter-Stimmung) — dadurch
## blendet der Himmel stufenlos zwischen ALLEN Kombinationen.

## Alle Stimmungs-Ids (Reihenfolge = Doku-Reihenfolge).
const STIMMUNGEN: Array[String] = [
	"morgen", "mittag", "goldene_stunde", "abendrot", "nacht", "bedeckt", "gewitter"
]

## Uniform-Sätze je Stimmung — weich, warm, nie grell (GOOBY-Pastell).
const PARAMETER := {
	"morgen":
	{
		"zenit": Color(0.52, 0.70, 0.90),
		"horizont": Color(0.99, 0.90, 0.78),
		"boden": Color(0.72, 0.80, 0.66),
		"dunst": 0.45,
		"sonne_farbe": Color(1.0, 0.92, 0.72),
		"sonne_groesse": 0.042,
		"sonne_glow": 0.42,
		"wolken_farbe": Color(1.0, 0.97, 0.92, 0.75),
		"wolken_menge": 0.18,
		"sterne": 0.0,
	},
	"mittag":
	{
		"zenit": Color(0.44, 0.65, 0.90),
		"horizont": Color(0.80, 0.90, 0.97),
		"boden": Color(0.70, 0.80, 0.64),
		"dunst": 0.24,
		"sonne_farbe": Color(1.0, 0.97, 0.88),
		"sonne_groesse": 0.033,
		"sonne_glow": 0.30,
		"wolken_farbe": Color(1.0, 1.0, 1.0, 0.8),
		"wolken_menge": 0.16,
		"sterne": 0.0,
	},
	"goldene_stunde":
	{
		"zenit": Color(0.50, 0.58, 0.82),
		"horizont": Color(1.0, 0.80, 0.55),
		"boden": Color(0.72, 0.74, 0.58),
		"dunst": 0.48,
		"sonne_farbe": Color(1.0, 0.84, 0.55),
		"sonne_groesse": 0.05,
		"sonne_glow": 0.55,
		"wolken_farbe": Color(1.0, 0.88, 0.74, 0.8),
		"wolken_menge": 0.24,
		"sterne": 0.0,
	},
	"abendrot":
	{
		"zenit": Color(0.36, 0.36, 0.60),
		"horizont": Color(0.96, 0.56, 0.46),
		"boden": Color(0.52, 0.52, 0.48),
		"dunst": 0.55,
		"sonne_farbe": Color(1.0, 0.64, 0.46),
		"sonne_groesse": 0.055,
		"sonne_glow": 0.5,
		"wolken_farbe": Color(0.94, 0.68, 0.62, 0.82),
		"wolken_menge": 0.3,
		"sterne": 0.12,
	},
	"nacht":
	{
		"zenit": Color(0.05, 0.07, 0.16),
		"horizont": Color(0.13, 0.16, 0.28),
		"boden": Color(0.08, 0.10, 0.12),
		"dunst": 0.35,
		"sonne_farbe": Color(0.0, 0.0, 0.0),
		"sonne_groesse": 0.0,
		"sonne_glow": 0.0,
		"wolken_farbe": Color(0.20, 0.23, 0.32, 0.7),
		"wolken_menge": 0.14,
		"sterne": 1.0,
	},
	"bedeckt":
	{
		"zenit": Color(0.60, 0.65, 0.72),
		"horizont": Color(0.78, 0.80, 0.83),
		"boden": Color(0.60, 0.66, 0.58),
		"dunst": 0.5,
		"sonne_farbe": Color(0.9, 0.9, 0.88),
		"sonne_groesse": 0.015,
		"sonne_glow": 0.08,
		"wolken_farbe": Color(0.86, 0.87, 0.90, 0.92),
		"wolken_menge": 0.85,
		"sterne": 0.0,
	},
	"gewitter":
	{
		"zenit": Color(0.28, 0.31, 0.40),
		"horizont": Color(0.46, 0.48, 0.55),
		"boden": Color(0.36, 0.40, 0.38),
		"dunst": 0.55,
		"sonne_farbe": Color(0.0, 0.0, 0.0),
		"sonne_groesse": 0.0,
		"sonne_glow": 0.0,
		"wolken_farbe": Color(0.34, 0.36, 0.44, 0.95),
		"wolken_menge": 0.96,
		"sterne": 0.0,
	},
}

## Tageszeit-Keyframes (Stunde → Stimmung); dazwischen wird gemischt.
const TAGES_KEYFRAMES: Array = [
	[0.0, "nacht"],
	[5.0, "nacht"],
	[7.0, "morgen"],
	[10.5, "mittag"],
	[16.0, "mittag"],
	[17.8, "goldene_stunde"],
	[19.4, "abendrot"],
	[20.8, "nacht"],
	[24.0, "nacht"],
]

## Wettertypen, die den Himmel Richtung „bedeckt" ziehen (Anteil 0..1).
const BEDECKT_ANTEIL := {
	"sonne": 0.0,
	"wolken": 0.75,
	"niesel": 0.88,
	"regen": 0.94,
	"gewitter": 1.0,
	"nebel": 0.85,
}


## Parameter einer Stimmung (Kopie).
static func stimmung(id: String) -> Dictionary:
	var p: Dictionary = PARAMETER.get(id, PARAMETER["mittag"])
	return p.duplicate(true)


## Dominante Stimmung zu Stunde + Wettertyp (für Tests/Screenshots).
static func stimmung_bei(stunde: float, wetter_typ: String) -> String:
	if wetter_typ == "gewitter":
		return "gewitter"
	if float(BEDECKT_ANTEIL.get(wetter_typ, 0.0)) >= 0.5:
		return "bedeckt"
	var mix := _tages_mix(stunde)
	return str(mix["b"]) if float(mix["t"]) >= 0.5 else str(mix["a"])


## Fertig gemischter Uniform-Satz zu Stunde + Wetter-Zustand (RanchWetter-
## Schema: typ, vorher, blend, bewoelkung). Deterministisch + stetig.
static func parameter(stunde: float, wetter: Dictionary) -> Dictionary:
	var mix := _tages_mix(stunde)
	var tag := _mische(stimmung(str(mix["a"])), stimmung(str(mix["b"])), float(mix["t"]))
	var typ := str(wetter.get("typ", "sonne"))
	var vorher := str(wetter.get("vorher", typ))
	var blend := clampf(float(wetter.get("blend", 1.0)), 0.0, 1.0)
	var grau := lerpf(_grau_anteil(vorher), _grau_anteil(typ), blend)
	var gewitter := lerpf(_gewitter_anteil(vorher), _gewitter_anteil(typ), blend)
	# Nachts wird auch „bedeckt" dunkel: Overlay-Ziel Richtung Nacht ziehen.
	var nacht_anteil := 1.0 - tageslicht(stunde)
	if grau > 0.001:
		var ziel := _mische(stimmung("bedeckt"), stimmung("nacht"), nacht_anteil * 0.85)
		tag = _mische(tag, ziel, grau)
	if gewitter > 0.001:
		var ziel_g := _mische(stimmung("gewitter"), stimmung("nacht"), nacht_anteil * 0.7)
		tag = _mische(tag, ziel_g, gewitter)
	return tag


## Tageslicht 0..1 (weiche Rampen; Spiegel der Stadt-Kurve, hier PURE
## dupliziert, damit die Bibliothek keine City-Abhängigkeit hat).
static func tageslicht(stunde: float) -> float:
	var s := fposmod(stunde, 24.0)
	var auf := smoothstep(5.5, 8.0, s)
	var ab := 1.0 - smoothstep(18.0, 20.5, s)
	return clampf(minf(auf, ab), 0.0, 1.0)


## ------------------------------------------------------------------ intern


## Nachbar-Keyframes + Mischfaktor zur Stunde: {a, b, t}.
static func _tages_mix(stunde: float) -> Dictionary:
	var s := fposmod(stunde, 24.0)
	for i in TAGES_KEYFRAMES.size() - 1:
		var von: Array = TAGES_KEYFRAMES[i]
		var bis: Array = TAGES_KEYFRAMES[i + 1]
		if s <= float(bis[0]):
			var spanne := maxf(0.001, float(bis[0]) - float(von[0]))
			var t := clampf((s - float(von[0])) / spanne, 0.0, 1.0)
			return {"a": str(von[1]), "b": str(bis[1]), "t": smoothstep(0.0, 1.0, t)}
	return {"a": "nacht", "b": "nacht", "t": 1.0}


static func _grau_anteil(typ: String) -> float:
	if typ == "gewitter":
		return 0.0
	return float(BEDECKT_ANTEIL.get(typ, 0.0))


static func _gewitter_anteil(typ: String) -> float:
	return 1.0 if typ == "gewitter" else 0.0


static func _mische(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key: String in a:
		var wert_a: Variant = a[key]
		var wert_b: Variant = b.get(key, wert_a)
		if wert_a is Color:
			out[key] = (wert_a as Color).lerp(wert_b, t)
		else:
			out[key] = lerpf(float(wert_a), float(wert_b), t)
	return out
