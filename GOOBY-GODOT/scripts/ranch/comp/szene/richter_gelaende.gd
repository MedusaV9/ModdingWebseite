class_name RcompRichterGelaende
extends RefCounted
## Richter Geländeritt (RW-5) + Arcade-Zeitrennen: der Reihe nach durch
## Flaggentore; wer ein Tor auslässt (ein späteres zuerst durchreitet),
## kassiert die 8-s-Strafe der Doc-Formel. PURE (Positionen rein).

const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")
const Wertung := preload("res://scripts/ranch/comp/wertung/wertung_gelaende.gd")
const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")

const TOR_HALBBREITE := 3.2

var tore: Array[Dictionary] = []
var idx := 0
var verpasst := 0
var richtzeit := 150.0


func setup(balance: Dictionary, klasse: String, seed_wert: int) -> void:
	tore = Kurs.gelaende(klasse, seed_wert)
	richtzeit = Katalog.richtzeit_s(balance, "gelaende", klasse)


## Arcade-Variante: eigene Route statt Klassen-Ellipse.
func setup_route(route: Array[Dictionary], ziel_s: float) -> void:
	tore = route
	richtzeit = ziel_s


func fertig() -> bool:
	return idx >= tore.size()


func tick(vorher: Vector3, jetzt: Vector3, _gait: String, _in_luft: bool, _dt: float) -> Array:
	if fertig():
		return []
	var events: Array = []
	# Auch spätere Tore prüfen: wer vorbeireitet, lässt die dazwischen aus.
	for j in range(idx, tore.size()):
		var tor: Dictionary = tore[j]
		if not Kurs.tor_durchritten(vorher, jetzt, tor["pos"], tor["quer"], TOR_HALBBREITE):
			continue
		for uebersprungen in range(idx, j):
			verpasst += 1
			events.append({"typ": "tor_verpasst", "index": uebersprungen})
		events.append({"typ": "tor_ok", "index": j, "nummer": j + 1})
		idx = j + 1
		break
	return events


func ergebnis(zeit_s: float) -> Dictionary:
	return {
		"wert": Wertung.wertung_s(zeit_s, verpasst),
		"zeit_s": zeit_s,
		"detail": {"verpasst": verpasst, "tore": tore.size()},
	}


func hud() -> Dictionary:
	return {
		"key": "rcomp.hud.tor",
		"params": {"n": mini(idx + 1, tore.size()), "max": tore.size()},
	}
