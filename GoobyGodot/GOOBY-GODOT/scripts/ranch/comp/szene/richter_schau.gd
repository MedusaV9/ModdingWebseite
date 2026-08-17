class_name RcompRichterSchau
extends RefCounted
## Richter Schau (RW-5, Kap. 5.2 Nr. 6): das Pferd steht im Rampenlicht,
## Pflege + Stil stehen vor dem Auftritt fest, die Kür ist Simon-Says —
## 5 Kommandos erscheinen im Takt, der Tipp im ±300-ms-Fenster trifft
## (RcompWertungSchau). PURE: Zeit rein, Tipps über tippe().

const Wertung := preload("res://scripts/ranch/comp/wertung/wertung_schau.gd")

## Erstes Kommando nach 3 s, dann alle 4 s (Ansage 1,5 s vorher).
const START_S := 3.0
const ABSTAND_S := 4.0
const ANSAGE_VORLAUF_S := 1.5
## Nach dem Idealmoment bleibt so lange Zeit, dann gilt "daneben" (s).
const FENSTER_S := 1.2

var kommandos: Array[Dictionary] = []
var idx := 0
var treffer := 0
var abweichungen: Array = []
var pflege_wert := 70.0
var stil_wert := 40.0

var _zeit := 0.0
var _angesagt := false


func setup(_balance: Dictionary, _klasse: String, seed_wert: int) -> void:
	var rng := GoobyRng.new(seed_wert)
	var pool: Array = Wertung.KOMMANDOS.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := int(rng.next() * (i + 1))
		var tausch: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tausch
	for i in Wertung.KUER_KOMMANDOS:
		kommandos.append({"id": str(pool[i % pool.size()]), "zeit_s": START_S + i * ABSTAND_S})


## Pflege/Stil VOR dem Auftritt setzen (aus basis_aus_pferd oder Tests).
func setze_basis(pflege: float, stil: float) -> void:
	pflege_wert = clampf(pflege, 0.0, 100.0)
	stil_wert = clampf(stil, 0.0, 100.0)


func fertig() -> bool:
	return idx >= kommandos.size()


func aktuelles_kommando() -> Dictionary:
	return kommandos[idx] if idx < kommandos.size() else {}


## Countdown (s) bis zum Idealmoment des aktuellen Kommandos (<0 = vorbei).
func countdown_s() -> float:
	if fertig():
		return 0.0
	return float(kommandos[idx]["zeit_s"]) - _zeit


func tick(_vorher: Vector3, _jetzt: Vector3, _g: String, _luft: bool, dt: float) -> Array:
	if fertig():
		return []
	_zeit += dt
	var events: Array = []
	var kommando: Dictionary = kommandos[idx]
	var soll := float(kommando["zeit_s"])
	if not _angesagt and _zeit >= soll - ANSAGE_VORLAUF_S:
		_angesagt = true
		events.append({"typ": "kommando", "id": str(kommando["id"]), "index": idx})
	if _zeit > soll + FENSTER_S:
		abweichungen.append((FENSTER_S + 1.0) * 1000.0)
		events.append({"typ": "daneben", "index": idx})
		idx += 1
		_angesagt = false
	return events


## Spieler-Tipp: Timing gegen den Idealmoment werten. Viel zu früh
## (vor der Ansage) verpufft kinderfreundlich ohne Strafe.
func tippe() -> Dictionary:
	if fertig():
		return {}
	var kommando: Dictionary = kommandos[idx]
	var abweichung_ms := (_zeit - float(kommando["zeit_s"])) * 1000.0
	if abweichung_ms < -ANSAGE_VORLAUF_S * 1000.0:
		return {"typ": "zu_frueh"}
	abweichungen.append(absf(abweichung_ms))
	var getroffen := Wertung.kuer_treffer(abweichung_ms)
	if getroffen:
		treffer += 1
	idx += 1
	_angesagt = false
	return {
		"typ": "treffer" if getroffen else "daneben",
		"index": idx - 1,
		"abweichung_ms": abweichung_ms,
	}


func ergebnis(zeit_s: float) -> Dictionary:
	var kuer := Wertung.kuer(treffer)
	return {
		"wert": Wertung.gesamt(pflege_wert, stil_wert, kuer),
		"zeit_s": zeit_s,
		"detail": {"pflege": pflege_wert, "stil": stil_wert, "kuer": kuer, "treffer": treffer},
	}


func hud() -> Dictionary:
	return {
		"key": "rcomp.hud.kommando",
		"params": {"n": mini(idx + 1, kommandos.size()), "max": kommandos.size()},
	}


## Pflege/Stil defensiv aus dem Pferde-Save ableiten: Pflege = (Sauberkeit
## + Laune)/2; Stil zählt die angelegte Ausrüstung (je Teil "selten",
## ab 3 Teilen Set-Bonus). gear = Eintrag aus
## ranch.wirtschaft.gear.equippedByHorse.<id> (Array oder Dictionary).
static func basis_aus_pferd(pferd: Dictionary, gear: Variant) -> Dictionary:
	var werte: Dictionary = pferd.get("werte") if pferd.get("werte") is Dictionary else {}
	var sauberkeit := _num(werte.get("sauberkeit"), 75.0)
	var laune := 70.0
	if not werte.is_empty():
		laune = RanchHorseCare.laune(werte, _num(pferd.get("bindung"), 50.0))
	var teile := 0
	if gear is Array:
		teile = (gear as Array).size()
	elif gear is Dictionary:
		for slot: Variant in (gear as Dictionary).values():
			if str(slot) != "":
				teile += 1
	var raritaeten: Array = []
	for _i in teile:
		raritaeten.append("selten")
	return {
		"pflege": Wertung.pflege(sauberkeit, laune),
		"stil": Wertung.stil(raritaeten, teile >= 3, false),
	}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
