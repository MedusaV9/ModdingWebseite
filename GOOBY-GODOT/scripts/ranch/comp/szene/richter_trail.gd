class_name RcompRichterTrail
extends RefCounted
## Richter Westerntrail (RW-5): 6 Korridor-Stationen der Reihe nach,
## langsam und mittig hindurch. Streifen der Markierung = Berührung (−2 P),
## Station überspringen = 0 P (Doc-Formel via RcompWertungTrail).
## PURE (Positionen rein).

const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")
const Wertung := preload("res://scripts/ranch/comp/wertung/wertung_trail.gd")

const BERUEHR_COOLDOWN_S := 0.8
const MAX_BERUEHRUNGEN := 3

var stationen: Array[Dictionary] = []
var idx := 0
var punkte: Array = []

var _beruehrungen := 0
var _cooldown := 0.0


func setup(_balance: Dictionary, _klasse: String, _seed_wert: int) -> void:
	stationen = Kurs.TRAIL_STATIONEN.duplicate(true)


func fertig() -> bool:
	return idx >= stationen.size()


func aktuelle_station() -> Dictionary:
	return stationen[idx] if idx < stationen.size() else {}


func tick(vorher: Vector3, jetzt: Vector3, _gait: String, _in_luft: bool, dt: float) -> Array:
	_cooldown = maxf(0.0, _cooldown - dt)
	if fertig():
		return []
	var events: Array = []
	# Streifen der aktuellen Station (im Korridor, aber zu weit außen).
	var station: Dictionary = stationen[idx]
	var lokal := _lokal(jetzt, station)
	var breite := float(station["breite"])
	if absf(lokal.x) <= Kurs.TRAIL_LAENGE_M * 0.5 and _cooldown <= 0.0:
		if absf(lokal.y) > breite and absf(lokal.y) <= breite + 0.8:
			if _beruehrungen < MAX_BERUEHRUNGEN:
				_beruehrungen += 1
				events.append({"typ": "beruehrung", "index": idx})
				_cooldown = BERUEHR_COOLDOWN_S
	# Ausgang durchritten? Auch spätere Stationen prüfen (Auslassen).
	for j in range(idx, stationen.size()):
		var s: Dictionary = stationen[j]
		if not Kurs.tor_durchritten(vorher, jetzt, _ausgang(s), _quer(s), float(s["breite"]) + 0.8):
			continue
		for uebersprungen in range(idx, j):
			punkte.append(0)
			events.append({"typ": "aufgabe_ausgelassen", "index": uebersprungen})
		var wert := Wertung.aufgabe_punkte(_beruehrungen, false)
		punkte.append(wert)
		events.append({"typ": "aufgabe_ok", "index": j, "punkte": wert})
		idx = j + 1
		_beruehrungen = 0
		break
	return events


func ergebnis(zeit_s: float) -> Dictionary:
	var gesamt := Wertung.gesamt(punkte, zeit_s)
	return {
		"wert": float(gesamt),
		"zeit_s": zeit_s,
		"detail": {"aufgaben": punkte.duplicate(), "zeitbonus": Wertung.zeitbonus(zeit_s)},
	}


func hud() -> Dictionary:
	var station := aktuelle_station()
	return {
		"key": "rcomp.hud.aufgabe",
		"params":
		{
			"n": mini(idx + 1, stationen.size()),
			"max": stationen.size(),
			"name": str(station.get("id", "")),
		},
	}


## Weltposition → Korridor-Koordinaten (x = entlang, y = quer).
func _lokal(pos: Vector3, station: Dictionary) -> Vector2:
	var mitte: Vector3 = station["pos"]
	var winkel := float(station["winkel"])
	var d := Vector2(pos.x - mitte.x, pos.z - mitte.z)
	var entlang := Vector2(cos(winkel), sin(winkel))
	return Vector2(d.dot(entlang), d.dot(Vector2(-entlang.y, entlang.x)))


func _ausgang(station: Dictionary) -> Vector3:
	var winkel := float(station["winkel"])
	var mitte: Vector3 = station["pos"]
	return mitte + Vector3(cos(winkel), 0.0, sin(winkel)) * (Kurs.TRAIL_LAENGE_M * 0.5)


func _quer(station: Dictionary) -> Vector3:
	var winkel := float(station["winkel"])
	return Vector3(-sin(winkel), 0.0, cos(winkel))
