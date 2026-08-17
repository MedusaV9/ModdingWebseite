class_name RcompRichterSpringen
extends RefCounted
## Richter Springparcours (RW-5) — wertet einen Lauf anhand von
## Positionen/Zuständen, die der Treiber (comp_lauf) je Frame liefert.
## PURE genug für Bot-Tests: kein Node, keine Szene.

const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")
const Wertung := preload("res://scripts/ranch/comp/wertung/wertung_springen.gd")
const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")

const TOR_HALBBREITE := 2.4
## "Perfekt"-Merker aus dem RideController gilt so lange (s).
const PERFEKT_FENSTER_S := 1.4

var kurs: Array[Dictionary] = []
var idx := 0
var abwuerfe := 0
var verweigerungen := 0
var perfekte := 0
var richtzeit := 60.0

var _perfekt_rest := 0.0


func setup(balance: Dictionary, klasse: String, _seed_wert: int) -> void:
	kurs = Kurs.springen(klasse)
	richtzeit = Katalog.richtzeit_s(balance, "springen", klasse)


## Der RideController hat einen Sprung gewertet ("perfekt"|"gut"|"daneben").
func notiere_sprung(wertung: String) -> void:
	if wertung == "perfekt":
		_perfekt_rest = PERFEKT_FENSTER_S


## Hindernis-Positionen fürs Sprung-Timing des Controllers.
func hindernis_punkte() -> Array:
	var punkte: Array = []
	for h in kurs:
		punkte.append(h["pos"])
	return punkte


func fertig() -> bool:
	return idx >= kurs.size()


## → Events [{typ, index}]; typ: hindernis_ok|perfekt|abwurf|verweigert.
func tick(vorher: Vector3, jetzt: Vector3, gait: String, in_luft: bool, dt: float) -> Array:
	_perfekt_rest = maxf(0.0, _perfekt_rest - dt)
	if fertig():
		return []
	var h: Dictionary = kurs[idx]
	if not Kurs.tor_durchritten(vorher, jetzt, h["pos"], h["quer"], TOR_HALBBREITE):
		return []
	var events: Array = []
	if in_luft:
		if _perfekt_rest > 0.0:
			perfekte += 1
			events.append({"typ": "perfekt", "index": idx})
		else:
			events.append({"typ": "hindernis_ok", "index": idx})
	elif gait == "stand" or gait == "schritt":
		verweigerungen += 1
		events.append({"typ": "verweigert", "index": idx})
	else:
		abwuerfe += 1
		events.append({"typ": "abwurf", "index": idx})
	idx += 1
	return events


func ergebnis(zeit_s: float) -> Dictionary:
	var score := Wertung.score(abwuerfe, verweigerungen, zeit_s, richtzeit, perfekte)
	return {
		"wert": float(score),
		"zeit_s": zeit_s,
		"detail": {"abwuerfe": abwuerfe, "verweigerungen": verweigerungen, "perfekte": perfekte},
	}


func hud() -> Dictionary:
	return {
		"key": "rcomp.hud.hindernis",
		"params": {"n": mini(idx + 1, kurs.size()), "max": kurs.size()},
	}
