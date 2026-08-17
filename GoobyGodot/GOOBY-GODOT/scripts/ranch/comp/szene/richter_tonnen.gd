class_name RcompRichterTonnen
extends RefCounted
## Richter Tonnenrennen (RW-5): Kleeblatt — jede Tonne der Reihe nach
## umrunden (Winkel-Sweep ≥ 300°), Anrempeln kippt sie (+5 s, Doc-Formel),
## dann zurück über die Startlinie. PURE (Positionen rein).

const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")
const Wertung := preload("res://scripts/ranch/comp/wertung/wertung_tonnen.gd")

const SWEEP_ZIEL := 5.2
const SWEEP_RADIUS := 8.0
const RAMM_ABSTAND := 1.15
const ZIEL_HALBBREITE := 7.0

var tonnen: Array[Vector3] = []
var idx := 0
var umgeworfen := 0
var ideal := 24.0
var heim := false

var _sweep := 0.0
var _winkel_vorher := 0.0
var _winkel_init := false
var _gerammt: Dictionary = {}


func setup(_balance: Dictionary, klasse: String, _seed_wert: int) -> void:
	tonnen = Kurs.TONNEN_POSITIONEN.duplicate()
	ideal = Wertung.idealzeit(klasse)


## Arcade-Variante: eigene Idealzeit (Level-Leiter).
func setze_ideal(ziel_s: float) -> void:
	ideal = ziel_s


func fertig() -> bool:
	return heim


func tick(vorher: Vector3, jetzt: Vector3, _gait: String, _in_luft: bool, _dt: float) -> Array:
	var events: Array = []
	# Rammen zählt für JEDE noch stehende Tonne (auch außer der Reihe).
	for i in tonnen.size():
		if _gerammt.has(i):
			continue
		if Vector2(jetzt.x - tonnen[i].x, jetzt.z - tonnen[i].z).length() < RAMM_ABSTAND:
			_gerammt[i] = true
			umgeworfen += 1
			events.append({"typ": "tonne_um", "index": i})
	if idx < tonnen.size():
		_sweep_um_tonne(vorher, jetzt, events)
	elif Kurs.tor_durchritten(
		vorher, jetzt, Kurs.TONNEN_START, Vector3(1.0, 0.0, 0.0), ZIEL_HALBBREITE
	):
		heim = true
		events.append({"typ": "ziel"})
	return events


func ergebnis(zeit_s: float) -> Dictionary:
	return {
		"wert": Wertung.wertung_s(zeit_s, umgeworfen),
		"zeit_s": zeit_s,
		"detail": {"umgeworfen": umgeworfen, "ideal": ideal},
	}


func hud() -> Dictionary:
	return {"key": "rcomp.hud.tonnen", "params": {"n": mini(idx, 3)}}


func _sweep_um_tonne(_vorher: Vector3, jetzt: Vector3, events: Array) -> void:
	var tonne := tonnen[idx]
	var d := Vector2(jetzt.x - tonne.x, jetzt.z - tonne.z)
	if d.length() > SWEEP_RADIUS:
		_winkel_init = false
		return
	var winkel := atan2(d.y, d.x)
	if not _winkel_init:
		_winkel_init = true
		_winkel_vorher = winkel
		return
	var delta := fposmod(winkel - _winkel_vorher + PI, TAU) - PI
	_winkel_vorher = winkel
	_sweep += delta
	if absf(_sweep) >= SWEEP_ZIEL:
		events.append({"typ": "tonne_ok", "index": idx, "nummer": idx + 1})
		idx += 1
		_sweep = 0.0
		_winkel_init = false
