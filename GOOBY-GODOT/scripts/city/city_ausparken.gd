class_name CityAusparken
extends RefCounted
## Rückwärts-Ausparken aus der Hausausfahrt (FIX-5 „Fahren startet am
## eigenen Haus"): PURE Zustandsmaschine — das Auto steht mit der Nase zum
## Haus in der Einfahrt, setzt gerade zurück bis auf die Fahrbahn und
## schwenkt dann im Bogen auf die Ziel-Fahrtrichtung der Straße. CityScene
## füttert `kommando()` pro Physik-Schritt in den CarController; jede
## MANUELLE Eingabe des Spielers bricht die Sequenz ab (Daumen gewinnt).

enum Phase { GERADE, BOGEN, FERTIG }

## Gerade zurück, bis das Auto so nah an der Straßenachse ist (m) …
const BOGEN_START_M := 5.0
## … dann Voll-Lenk-Bogen, bis das Heading der Straße anliegt (rad).
const HEADING_EPS := 0.14
## Failsafe: hinter der Straßenmitte ist IMMER Schluss mit Rückwärts (m).
const ACHSE_MIN_M := 0.6

var phase := Phase.GERADE

var _strasse_pos: Vector3
var _richtung_haus: Vector3
var _ziel_heading: float
var _bogen_steer: float


## `strasse_pos` = Mitte des Straßen-Tiles vor der Einfahrt,
## `richtung_haus` = Einheitsvektor Straße→Haus, `start_heading` = geparkte
## Blickrichtung (zur Haustür), `ziel_heading` = Fahrtrichtung der Straße.
func _init(
	strasse_pos: Vector3, richtung_haus: Vector3, start_heading: float, ziel_heading: float
) -> void:
	_strasse_pos = strasse_pos
	_richtung_haus = richtung_haus
	_ziel_heading = ziel_heading
	# Rückwärts dreht positiver Steer das Heading auf — der Bogen lenkt in
	# die Richtung, in der der Restwinkel zum Ziel-Heading liegt.
	_bogen_steer = signf(CityCarFeel.wrap_angle(ziel_heading - start_heading))
	if _bogen_steer == 0.0:
		_bogen_steer = 1.0


## Steuerkommando für die aktuelle Auto-Lage. {reverse, steer, fertig}.
func kommando(pos: Vector3, heading: float) -> Dictionary:
	match phase:
		Phase.GERADE:
			if _achsen_abstand(pos) <= BOGEN_START_M:
				phase = Phase.BOGEN
			else:
				return {"reverse": true, "steer": 0.0, "fertig": false}
		Phase.FERTIG:
			return {"reverse": false, "steer": 0.0, "fertig": true}
		_:
			pass
	var rest := CityCarFeel.wrap_angle(_ziel_heading - heading)
	if absf(rest) <= HEADING_EPS or _achsen_abstand(pos) <= ACHSE_MIN_M:
		phase = Phase.FERTIG
		return {"reverse": false, "steer": 0.0, "fertig": true}
	return {"reverse": true, "steer": _bogen_steer, "fertig": false}


func laeuft() -> bool:
	return phase != Phase.FERTIG


## Abstand des Autos zur Straßenachse, gemessen entlang Straße→Haus (m).
func _achsen_abstand(pos: Vector3) -> float:
	return (pos - _strasse_pos).dot(_richtung_haus)
