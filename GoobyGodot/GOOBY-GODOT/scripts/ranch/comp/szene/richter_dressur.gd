class_name RcompRichterDressur
extends RefCounted
## Richter Dressur (RW-5): 5 Figuren (Zirkel, Acht, Schlangenlinie,
## Halten, Rückwärtsrichten) als Wegpunkt-Ketten mit Soll-Gangart.
## Abweichung von der Ideallinie wird laufend gemessen (Doc-Formel via
## RcompWertungDressur), Gangartwechsel zählen für den Taktbonus.
## PURE (Positionen + Gangart rein).

const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")
const Wertung := preload("res://scripts/ranch/comp/wertung/wertung_dressur.gd")

const PUNKT_TOLERANZ_M := 3.0
const MESS_INTERVALL_S := 0.4
## Sekunden in falscher Gangart je Gangartfehler.
const FEHLER_JE_S := 2.5
const MAX_GANGARTFEHLER := 2
## Gnadenfrist nach dem Wechselsignal, bevor die Takt-Uhr zählt (ms).
const TAKT_GNADE_MS := 400.0
## Wer so lange gar nicht wechselt, verliert den Taktbonus sicher (s).
const TAKT_MAX_S := 4.0

var figuren: Array[Dictionary] = []
var figur_idx := 0
var punkt_idx := 0
var figuren_punkte: Array = []
var takt_abweichungen: Array = []

var _abweichungen: Array = []
var _falsch_s := 0.0
var _mess_rest := 0.0
var _wechsel_offen_s := -1.0


func setup(_balance: Dictionary, _klasse: String, _seed_wert: int) -> void:
	figuren = Kurs.dressur_figuren()
	_wechsel_offen_s = 0.0


func fertig() -> bool:
	return figur_idx >= figuren.size()


func aktuelle_figur() -> Dictionary:
	return figuren[figur_idx] if figur_idx < figuren.size() else {}


func ziel_punkt() -> Vector3:
	var figur := aktuelle_figur()
	if figur.is_empty():
		return Vector3.ZERO
	var punkte: Array = figur["punkte"]
	return punkte[mini(punkt_idx, punkte.size() - 1)]


func soll_gangart() -> String:
	return str(aktuelle_figur().get("gangart", "schritt"))


func tick(_vorher: Vector3, jetzt: Vector3, gait: String, _in_luft: bool, dt: float) -> Array:
	if fertig():
		return []
	var events: Array = []
	# Taktfenster: nach Figurstart wartet der Richter auf die Soll-Gangart.
	if _wechsel_offen_s >= 0.0:
		_wechsel_offen_s += dt
		if gait == soll_gangart():
			takt_abweichungen.append(maxf(0.0, _wechsel_offen_s * 1000.0 - TAKT_GNADE_MS))
			_wechsel_offen_s = -1.0
			events.append({"typ": "gangart_ok"})
		elif _wechsel_offen_s > TAKT_MAX_S:
			takt_abweichungen.append(9999.0)
			_wechsel_offen_s = -1.0
	elif gait != soll_gangart() and gait != "stand":
		_falsch_s += dt
	# Ideallinien-Abweichung im Messraster sammeln.
	_mess_rest -= dt
	if _mess_rest <= 0.0:
		_mess_rest = MESS_INTERVALL_S
		_abweichungen.append(_abstand_zur_linie(jetzt))
	# Wegpunkt erreicht?
	var ziel := ziel_punkt()
	if Vector2(jetzt.x - ziel.x, jetzt.z - ziel.z).length() <= PUNKT_TOLERANZ_M:
		punkt_idx += 1
		var punkte: Array = aktuelle_figur()["punkte"]
		if punkt_idx >= punkte.size():
			_schliesse_figur(events)
	return events


func ergebnis(zeit_s: float) -> Dictionary:
	var takt := takt_abweichungen.size() >= figuren.size() and Wertung.takt_ok(takt_abweichungen)
	var gesamt := Wertung.gesamt(figuren_punkte, takt)
	return {
		"wert": gesamt,
		"zeit_s": zeit_s,
		"detail": {"figuren": figuren_punkte.duplicate(), "takt": takt},
	}


func hud() -> Dictionary:
	var figur := aktuelle_figur()
	return {
		"key": "rcomp.hud.figur",
		"params":
		{
			"n": mini(figur_idx + 1, figuren.size()),
			"max": figuren.size(),
			"name": str(figur.get("id", "")),
			"gangart": soll_gangart(),
		},
	}


func _schliesse_figur(events: Array) -> void:
	var d_mittel := 0.0
	for wert: Variant in _abweichungen:
		d_mittel += float(wert)
	d_mittel = d_mittel / maxf(1.0, _abweichungen.size())
	var fehler := mini(int(_falsch_s / FEHLER_JE_S), MAX_GANGARTFEHLER)
	var wert := Wertung.figur_punkte(d_mittel, fehler)
	figuren_punkte.append(wert)
	events.append({"typ": "figur_ok", "index": figur_idx, "punkte": wert})
	figur_idx += 1
	punkt_idx = 0
	_abweichungen = []
	_falsch_s = 0.0
	if not fertig():
		_wechsel_offen_s = 0.0
		events.append({"typ": "gangart_wechsel", "gangart": soll_gangart()})


## Abstand zur aktuellen Ideallinie (Strecke vorheriger → nächster Punkt).
func _abstand_zur_linie(pos: Vector3) -> float:
	var figur := aktuelle_figur()
	if figur.is_empty():
		return 0.0
	var punkte: Array = figur["punkte"]
	var b: Vector3 = punkte[mini(punkt_idx, punkte.size() - 1)]
	var a: Vector3 = punkte[maxi(0, punkt_idx - 1)] if punkt_idx > 0 else b
	return Kurs.abstand_zur_strecke(pos, a, b)
