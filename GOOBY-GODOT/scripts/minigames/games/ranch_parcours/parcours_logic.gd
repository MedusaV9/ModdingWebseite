class_name RanchParcoursLogic
extends RefCounted
## Hindernis-Parcours (ranchParcours) — PURE Logik (RANCH-2). Gooby reitet
## einen Kurs entlang (x wächst), springt per Tipp über Hindernisse und darf
## per Halten galoppieren. Bewertet werden Zeit + saubere Sprünge:
## Der Sprungbogen (RanchRideFeel-Physik) muss das Hindernis mittig treffen —
## "perfekt" nahe der Bogenmitte, "gut" im sicheren Fenster, sonst Abwurf
## (Zeitstrafe + Tempoverlust). 10 Kurse mit Steigerung aus
## data/parcours_kurse.json (Content-Pack-Namespace "ranchplay").

const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")

const KURSE_PATH := "res://scripts/minigames/games/ranch_parcours/data/parcours_kurse.json"
const KURS_ANZAHL := 10

## Bindende Spielzahlen (Fenster in Bruchteilen der Sprungweite).
const TUNE := {
	"GALOPP_MULT": 1.3,
	"SICHER_VON": 0.18,
	"SICHER_BIS": 0.82,
	"PERFEKT_M": 0.55,
	"ABWURF_STRAFE_S": 2.5,
	"ABWURF_TEMPO_MULT": 0.6,
	"PUNKTE_PERFEKT": 15,
	"PUNKTE_GUT": 10,
	"KOMBO_BONUS": 2,
	"KOMBO_DECKEL": 10,
	"ZEITBONUS_PRO_S": 4.0,
	"TOLERANZ": 1.0,
}

## §G5.3-Muster: easy verzeiht mehr, hard verlangt Präzision.
const DIFFICULTY := {
	"easy": {"toleranz": 1.25},
	"normal": {"toleranz": 1.0},
	"hard": {"toleranz": 0.8},
	"endless": {"toleranz": 0.8},
}

## Hindernis-Typen: Spannweite (m), die der Bogen sicher überdecken muss.
const HINDERNIS_BREITE := {"zaun": 0.4, "hecke": 0.9, "oxer": 1.2, "wasser": 1.6}


## Difficulty auf die Basistabelle anwenden (normal = unverändert).
static func apply_difficulty(tune: Dictionary = TUNE, mode := "normal") -> Dictionary:
	var id := mode if DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var out := tune.duplicate()
	out["TOLERANZ"] = float((DIFFICULTY[id] as Dictionary)["toleranz"])
	out["MODE"] = id
	return out


## Alle Kurse laden (Array[Dictionary], ids 1..10). registry-Duck-Typing wie
## RanchWirtschaft.load_balance; fehlt die Registry, gilt das eingebaute JSON.
static func load_kurse(registry: Object = null) -> Array:
	var daten := RanchWirtschaft.read_json(KURSE_PATH)
	var reg := registry
	if reg == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			reg = (loop as SceneTree).root.get_node_or_null("ContentRegistry")
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance("ranchplay", {})
		if overrides is Dictionary and (overrides as Dictionary).get("parcours_kurse") is Array:
			return (overrides as Dictionary)["parcours_kurse"]
	return daten.get("kurse") if daten.get("kurse") is Array else []


static func kurs_by_id(kurse: Array, id: int) -> Dictionary:
	for kurs: Variant in kurse:
		if kurs is Dictionary and int(kurs.get("id", 0)) == id:
			return kurs
	return {}


## Strukturelle Validierung der Kursliste (leer = alles gut).
static func validate_kurse(kurse: Array) -> PackedStringArray:
	var fehler := PackedStringArray()
	if kurse.size() != KURS_ANZAHL:
		fehler.append("erwartet %d Kurse, gefunden %d" % [KURS_ANZAHL, kurse.size()])
	for kurs: Variant in kurse:
		if not (kurs is Dictionary):
			fehler.append("Kurs ist kein Objekt")
			continue
		var k: Dictionary = kurs
		var tempo := float(k.get("tempo", 0.0))
		var weite := float(Feel.sprung_daten(tempo)["weite_m"])
		var vorher := -INF
		for h: Variant in k.get("hindernisse", []):
			var at := float((h as Dictionary).get("at", 0.0))
			var typ := str((h as Dictionary).get("typ", ""))
			if not HINDERNIS_BREITE.has(typ):
				fehler.append("Kurs %d: unbekannter Typ %s" % [int(k.get("id", 0)), typ])
			if at - vorher < weite * 1.2:
				fehler.append(
					(
						"Kurs %d: Hindernis bei %.1f zu dicht (< %.1f m Abstand)"
						% [int(k.get("id", 0)), at, weite * 1.2]
					)
				)
			if float(HINDERNIS_BREITE.get(typ, 0.0)) > weite * 0.64:
				fehler.append("Kurs %d: %s passt nicht in den Bogen" % [int(k.get("id", 0)), typ])
			vorher = at
			if at <= 0.0 or at >= float(k.get("laenge_m", 0.0)) - 4.0:
				fehler.append("Kurs %d: Hindernis bei %.1f außerhalb" % [int(k.get("id", 0)), at])
	return fehler


## Sprung bewerten: Absprung bei x0 mit Tempo v gegen Hindernis (Mitte, Typ).
## → {"qualitaet": "perfekt"|"gut"|"abwurf", "fehler_m": float}.
static func bewerte_sprung(
	x0: float, tempo: float, mitte: float, typ: String, tune: Dictionary = TUNE
) -> Dictionary:
	var weite := float(Feel.sprung_daten(tempo)["weite_m"])
	var toleranz := float(tune.get("TOLERANZ", 1.0))
	var breite := float(HINDERNIS_BREITE.get(typ, 0.4))
	var von := x0 + weite * float(tune["SICHER_VON"]) / toleranz
	var bis := x0 + weite * (1.0 - (1.0 - float(tune["SICHER_BIS"])) / toleranz)
	var fehler_m := absf(mitte - (x0 + weite * 0.5))
	if mitte - breite * 0.5 < von or mitte + breite * 0.5 > bis:
		return {"qualitaet": "abwurf", "fehler_m": fehler_m}
	if fehler_m <= float(tune["PERFEKT_M"]) * toleranz:
		return {"qualitaet": "perfekt", "fehler_m": fehler_m}
	return {"qualitaet": "gut", "fehler_m": fehler_m}


## Punkte für einen Sprung samt Kombo (Kombo = Zahl sauberer Sprünge davor).
static func sprung_punkte(qualitaet: String, kombo: int, tune: Dictionary = TUNE) -> int:
	match qualitaet:
		"perfekt":
			return (
				int(tune["PUNKTE_PERFEKT"])
				+ mini(int(tune["KOMBO_DECKEL"]), kombo * int(tune["KOMBO_BONUS"]))
			)
		"gut":
			return (
				int(tune["PUNKTE_GUT"])
				+ mini(int(tune["KOMBO_DECKEL"]), kombo * int(tune["KOMBO_BONUS"]))
			)
		_:
			return 0


## Zeitbonus am Ziel: (par − Zeit) · Rate, nie negativ, gerundet.
static func zeitbonus(par_s: float, zeit_s: float, tune: Dictionary = TUNE) -> int:
	return maxi(0, int(round(maxf(0.0, par_s - zeit_s) * float(tune["ZEITBONUS_PRO_S"]))))


## Kurs-Endstand: Sprungpunkte + Zeitbonus + Erst-Abschluss-Bonus.
static func kurs_score(
	sprung_punkte_summe: int, bonus: int, first_clear: bool, kurs_id: int
) -> int:
	var total := sprung_punkte_summe + bonus + kurs_id * 3
	if first_clear:
		total += 25
	return total


## Sterne: 3 = fehlerfrei UND unter Par, 2 = höchstens 1 Abwurf, sonst 1.
static func sterne(abwuerfe: int, zeit_s: float, par_s: float) -> int:
	if abwuerfe == 0 and zeit_s <= par_s:
		return 3
	return 2 if abwuerfe <= 1 else 1


## Effektives Lauftempo: Galoppieren beschleunigt um GALOPP_MULT.
static func lauf_tempo(basis: float, galopp: bool, tune: Dictionary = TUNE) -> float:
	return basis * (float(tune["GALOPP_MULT"]) if galopp else 1.0)


## Deterministische Bot-Zertifizierung eines Kurses: Der Bot springt am
## Ideal-Absprung mit seed-gestreutem Fehler (σ je Modus) und galoppiert
## auf freien Strecken. → {"score", "abwuerfe", "zeit_s", "sterne"}.
static func simulate_lauf(kurs: Dictionary, seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(TUNE, mode)
	var rng := GoobyRng.new(seed_value + int(kurs.get("id", 0)) * 101)
	var sigma := 0.7
	var galopp_ab := 14.0
	if mode == "easy":
		sigma = 0.45
		galopp_ab = 13.0
	elif mode == "hard" or mode == "endless":
		sigma = 1.05
		galopp_ab = 18.0
	var basis := float(kurs.get("tempo", 6.0))
	var laenge := float(kurs.get("laenge_m", 200.0))
	var punkte := 0
	var abwuerfe := 0
	var kombo := 0
	var zeit := 0.0
	var cursor := 0.0
	var tempo := basis
	for h: Variant in kurs.get("hindernisse", []):
		var mitte := float((h as Dictionary).get("at", 0.0))
		var typ := str((h as Dictionary).get("typ", "zaun"))
		# Anlauf: der Bot galoppiert, wenn genug freie Strecke liegt —
		# vorsichtige Bots (hard) galoppieren seltener und sind langsamer.
		var frei := mitte - cursor
		var galopp := frei > galopp_ab
		tempo = lauf_tempo(basis, galopp, tune)
		var weite := float(Feel.sprung_daten(tempo)["weite_m"])
		var ideal := mitte - weite * 0.5
		var streuung := (rng.next() * 2.0 - 1.0) * sigma
		var wertung := bewerte_sprung(ideal + streuung, tempo, mitte, typ, tune)
		zeit += frei / tempo
		if wertung["qualitaet"] == "abwurf":
			abwuerfe += 1
			kombo = 0
			zeit += float(tune["ABWURF_STRAFE_S"])
		else:
			punkte += sprung_punkte(wertung["qualitaet"], kombo, tune)
			kombo += 1
		cursor = mitte
	zeit += maxf(0.0, laenge - cursor) / lauf_tempo(basis, true, tune)
	var par := float(kurs.get("par_s", 60.0))
	var bonus := zeitbonus(par, zeit, tune)
	return {
		"seed": seed_value,
		"mode": mode,
		"score": kurs_score(punkte, bonus, false, int(kurs.get("id", 0))),
		"abwuerfe": abwuerfe,
		"zeit_s": zeit,
		"sterne": sterne(abwuerfe, zeit, par),
	}
