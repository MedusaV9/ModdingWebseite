class_name RcompWertungRennen
extends RefCounted
## Grasbahn-Rennen-Wertung (RW-5, IDEAS-3 Kap. 5.2 Nr. 4) — PURE.
## Wertung = ZIELREIHENFOLGE (3 Runden Oval, 4–8 Teilnehmer).
## Windschatten: < 2 m hinter einem Pferd für 1 s → +3 % Tempo für 3 s
## (Überhol-Drama statt Gummiband). Kein Kollisions-Kontakt.

const RUNDEN := 3
const TEILNEHMER_MIN := 4
const TEILNEHMER_MAX := 8
const WINDSCHATTEN_FENSTER_M := 2.0
const WINDSCHATTEN_SEITE_M := 1.2
const WINDSCHATTEN_AUFBAU_S := 1.0
const WINDSCHATTEN_BOOST := 0.03
const WINDSCHATTEN_DAUER_S := 3.0


static func neuer_zustand() -> Dictionary:
	return {"aufbau_s": 0.0, "boost_rest_s": 0.0}


## Ein Windschatten-Schritt: `dahinter` = < 2 m hinter einem Vordermann
## UND seitlich nah genug. Nach 1 s Aufbau zündet der Boost für 3 s.
static func step_windschatten(zustand: Dictionary, dahinter: bool, dt: float) -> Dictionary:
	var aufbau := _num(zustand.get("aufbau_s"), 0.0)
	var rest := maxf(0.0, _num(zustand.get("boost_rest_s"), 0.0) - dt)
	if dahinter:
		aufbau += dt
		if aufbau >= WINDSCHATTEN_AUFBAU_S and rest <= 0.0:
			rest = WINDSCHATTEN_DAUER_S
			aufbau = 0.0
	else:
		aufbau = 0.0
	return {"aufbau_s": aufbau, "boost_rest_s": rest}


## Ist Position `hinten` im Windschatten-Fenster von `vorne`?
## `strecke_vorne_m` = Vorsprung entlang der Bahn (positiv = vorne führt).
static func im_fenster(strecke_vorne_m: float, seitlich_m: float) -> bool:
	return (
		strecke_vorne_m > 0.0
		and strecke_vorne_m < WINDSCHATTEN_FENSTER_M
		and absf(seitlich_m) <= WINDSCHATTEN_SEITE_M
	)


static func tempo_mult(zustand: Dictionary) -> float:
	return 1.0 + WINDSCHATTEN_BOOST if _num(zustand.get("boost_rest_s"), 0.0) > 0.0 else 1.0


## Zielreihenfolge aus Zielzeiten: Array aus {id, zeit_s} → sortiert;
## DNF (zeit_s <= 0) landet hinten, stabil nach Eingangsreihenfolge.
static func reihenfolge(zielzeiten: Array) -> Array:
	var fertig: Array = []
	var dnf: Array = []
	for eintrag: Variant in zielzeiten:
		if not (eintrag is Dictionary):
			continue
		if _num((eintrag as Dictionary).get("zeit_s"), 0.0) > 0.0:
			fertig.append(eintrag)
		else:
			dnf.append(eintrag)
	fertig.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _num(a.get("zeit_s"), 0.0) < _num(b.get("zeit_s"), 0.0)
	)
	return fertig + dnf


## Platz (1-basiert) einer Id in der Reihenfolge; 0 = nicht gefunden.
static func platz_von(sortiert: Array, id: String) -> int:
	for i in sortiert.size():
		if str((sortiert[i] as Dictionary).get("id", "")) == id:
			return i + 1
	return 0


## Sterne aus dem Platz: Sieg 3, Podium 2, Top-Hälfte 1.
static func sterne(platz: int, teilnehmer: int) -> int:
	if platz == 1:
		return 3
	if platz > 1 and platz <= 3:
		return 2
	if platz > 0 and platz <= maxi(1, teilnehmer / 2):
		return 1
	return 0


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
