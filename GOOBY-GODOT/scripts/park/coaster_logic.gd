class_name CoasterLogic
extends RefCounted
## Funkel-Looping — PURE Fahrlogik (REST-4, Port des Web-Vorbilds
## GOOBY/src/park/coasterRide.logic.js in Godot-Metern). Kein Node, kein
## Zufall, kein Uhr-Lesen: der Haupt-Runner fährt die komplette Runde
## headless durch (tests/unit/test_rest4_park.gd) und die Szene
## (coaster_ride.gd) rendert GENAU diese Simulation.
##
## Der Rundkurs: Bahnhof → Kettenlift (langsames Klack-Klack) → Kuppe →
## Sturzflug → Beschleunigungsgerade → VERTIKAL-LOOPING (der Wow-Moment) →
## Foto-Gerade (Blitz!) → Hügelhüpfer → Bremsstrecke → Heimkurve zurück in
## den Bahnhof. Physik-light wie im Web: Lift/Bahnhof fahren Zielgeschwindig-
## keit, freie Strecke integriert dv = (−G·Steigung − Reibung·v)·dt, harte
## Klemmen halten v in [V_MIN, V_MAX] — die Bahn kann NIE liegenbleiben und
## NIE durchgehen (test-gepinnt). Der Looping bekommt einen Launch-Boost
## davor (echte Bahnen machen das auch) plus eine eigene Mindestgeschwindig-
## keit für die Scheitel-Klemme.

## Bindende Zahlen (web COASTER, auf Meter skaliert).
const G := 9.8
const FRICTION := 0.022
const GRADE_H := 0.35
const BOARD_SEC := 4.0
const DEPART_SPEED := 3.0
const LIFT_SPEED := 2.0
const CREST_SPEED := 2.6
const APPROACH_RATE := 3.0
const BOOST_SPEED := 14.0
const BOOST_ACCEL := 8.0
const VMIN_RUN := 3.0
const VMIN_LOOP := 7.0
const VMAX := 16.0
const BRAKE_DECEL := 4.0
const BRAKE_TARGET := 3.0
const END_STOP_EPS := 0.08
const MAX_SUBSTEP := 1.0 / 60.0
const WATCHDOG_SEC := 90.0
const PHOTO_FRACTION := 0.55

## Kamera-Rig (Meter, cart-lokal): Verfolger hinter/über dem Zug.
const CAM_BACK := 2.6
const CAM_UP := 1.7
const CAM_LOOKAHEAD := 4.0

## Der geauthorte Rundkurs: Punkt + Zone des SEGMENTS, das dort beginnt.
## Looping in der XY-Ebene mit Z-Drift (Klothoiden-Versatz, nichts schneidet).
const KEY_POINTS := [
	{"p": Vector3(-14.0, 0.8, 10.0), "zone": "station"},
	{"p": Vector3(-6.0, 0.8, 10.0), "zone": "lift"},
	{"p": Vector3(2.0, 1.2, 10.0), "zone": "lift"},
	{"p": Vector3(12.0, 9.0, 10.0), "zone": "crest"},
	{"p": Vector3(16.0, 9.6, 6.0), "zone": "crest"},
	{"p": Vector3(16.0, 8.8, 2.0), "zone": "drop"},
	{"p": Vector3(15.5, 1.4, -4.0), "zone": "launch"},
	{"p": Vector3(10.0, 1.1, -8.0), "zone": "launch"},
	{"p": Vector3(4.0, 1.0, -8.4), "zone": "loop"},
	{"p": Vector3(0.8, 4.2, -8.8), "zone": "loop"},
	{"p": Vector3(4.0, 7.4, -9.2), "zone": "loop"},
	{"p": Vector3(7.2, 4.2, -9.6), "zone": "loop"},
	{"p": Vector3(4.0, 1.0, -10.0), "zone": "photo"},
	{"p": Vector3(-2.0, 1.0, -10.0), "zone": "photo"},
	{"p": Vector3(-8.0, 1.0, -10.0), "zone": "hills"},
	{"p": Vector3(-11.0, 2.8, -9.4), "zone": "hills"},
	{"p": Vector3(-14.0, 1.0, -8.0), "zone": "hills"},
	{"p": Vector3(-16.5, 2.4, -5.5), "zone": "hills"},
	{"p": Vector3(-18.5, 1.0, -2.0), "zone": "brake"},
	{"p": Vector3(-19.0, 0.8, 3.0), "zone": "brake"},
	{"p": Vector3(-18.0, 0.8, 7.0), "zone": "home"},
	{"p": Vector3(-16.5, 0.8, 9.2), "zone": "home"},
]

## Zonen, in denen „Hände hoch“ zählt (Web: Fenster ≥ 3 s bei Fahrttempo).
const HANDS_UP_ZONES: Array[String] = ["drop", "loop", "photo", "hills"]

## Caption-Events je Zonen-EINTRITT (einmalig, in Fahrt-Reihenfolge).
const ZONE_EVENTS := {
	"lift": "lift",
	"drop": "drop",
	"loop": "loop",
	"hills": "hills",
	"brake": "brake",
}


## Den geschlossenen Rundkurs als Curve3D bauen (Catmull-Rom-Griffe).
static func make_curve() -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.2
	var n := KEY_POINTS.size()
	for i in n + 1:
		var hier: Vector3 = KEY_POINTS[i % n]["p"]
		var davor: Vector3 = KEY_POINTS[(i - 1 + n) % n]["p"]
		var danach: Vector3 = KEY_POINTS[(i + 1) % n]["p"]
		var tangente := (danach - davor) * 0.22
		curve.add_point(hier, -tangente, tangente)
	return curve


## Frische Simulation. `curve` kommt aus make_curve() (oder Test-Injektion).
static func neu(curve: Curve3D) -> Dictionary:
	var laenge := curve.get_baked_length()
	var zonen: Array = []
	var n := KEY_POINTS.size()
	for i in n:
		var start := curve.get_closest_offset(KEY_POINTS[i]["p"])
		zonen.append({"start": start, "zone": KEY_POINTS[i]["zone"]})
	# Foto-Blitzpunkt: Anteil PHOTO_FRACTION der photo-Zone.
	var photo_start := _zonen_start(zonen, "photo")
	var photo_ende := _zonen_start(zonen, "hills")
	return {
		"curve": curve,
		"laenge": laenge,
		"zonen": zonen,
		"s": 0.0,
		"v": 0.0,
		"t": 0.0,
		"boarding": true,
		"done": false,
		"gefeuert": {},
		"foto_s": photo_start + (photo_ende - photo_start) * PHOTO_FRACTION,
		"runden_ende": laenge - END_STOP_EPS,
	}


## Zone an Bogenlänge s (letzte Zone, deren Start <= s).
static func zone_bei(sim: Dictionary, s: float) -> String:
	var zone := "station"
	for eintrag: Dictionary in sim["zonen"]:
		if s >= float(eintrag["start"]) - 0.001:
			zone = str(eintrag["zone"])
	return zone


static func hands_up_erlaubt(zone: String) -> bool:
	return HANDS_UP_ZONES.has(zone)


## Einen Frame weiterrechnen; liefert die NEU gefeuerten Events (Reihenfolge
## board → depart → lift → drop → loop → photo → hills → brake → done).
static func step(sim: Dictionary, dt: float) -> Array[String]:
	var events: Array[String] = []
	if sim["done"]:
		return events
	_feuere(sim, "board", events)
	var rest := maxf(0.0, dt)
	while rest > 0.0 and not sim["done"]:
		var schritt := minf(rest, MAX_SUBSTEP)
		rest -= schritt
		_substep(sim, schritt, events)
	if float(sim["t"]) >= WATCHDOG_SEC and not sim["done"]:
		_beende(sim, events)
	return events


static func _substep(sim: Dictionary, dt: float, events: Array[String]) -> void:
	sim["t"] = float(sim["t"]) + dt
	if sim["boarding"]:
		if float(sim["t"]) >= BOARD_SEC:
			sim["boarding"] = false
			_feuere(sim, "depart", events)
		return
	var s := float(sim["s"])
	var zone := zone_bei(sim, s)
	var v := _neues_tempo(sim, zone, float(sim["v"]), s, dt)
	sim["v"] = v
	var s_neu := s + v * dt
	if s_neu >= float(sim["runden_ende"]):
		_beende(sim, events)
		return
	sim["s"] = s_neu
	var zone_neu := zone_bei(sim, s_neu)
	if zone_neu != zone and ZONE_EVENTS.has(zone_neu):
		_feuere(sim, str(ZONE_EVENTS[zone_neu]), events)
	if s < float(sim["foto_s"]) and s_neu >= float(sim["foto_s"]):
		_feuere(sim, "photo", events)


## Tempo-Update je Zone: Zielfahrten (Bahnhof/Lift/Kuppe/Bremse) nähern sich
## linear, freie Strecke integriert die Energie-Physik mit harten Klemmen.
static func _neues_tempo(sim: Dictionary, zone: String, v: float, s: float, dt: float) -> float:
	match zone:
		"station", "home":
			return move_toward(v, DEPART_SPEED, APPROACH_RATE * dt)
		"lift":
			return move_toward(v, LIFT_SPEED, APPROACH_RATE * dt)
		"crest":
			return move_toward(v, CREST_SPEED, APPROACH_RATE * dt)
		"launch":
			return move_toward(v, BOOST_SPEED, BOOST_ACCEL * dt)
		"brake":
			return maxf(BRAKE_TARGET, v - BRAKE_DECEL * dt)
		_:
			var grade := _steigung(sim, s)
			v += (-G * grade - FRICTION * v) * dt
			var vmin := VMIN_LOOP if zone == "loop" else VMIN_RUN
			return clampf(v, vmin, VMAX)


## Steigung dh/ds via zentralem Differenzenquotienten auf der Kurve.
static func _steigung(sim: Dictionary, s: float) -> float:
	var curve: Curve3D = sim["curve"]
	var laenge := float(sim["laenge"])
	var vor := curve.sample_baked(clampf(s + GRADE_H, 0.0, laenge)).y
	var zurueck := curve.sample_baked(clampf(s - GRADE_H, 0.0, laenge)).y
	return (vor - zurueck) / (2.0 * GRADE_H)


static func _beende(sim: Dictionary, events: Array[String]) -> void:
	sim["done"] = true
	sim["v"] = 0.0
	sim["s"] = 0.0
	_feuere(sim, "done", events)


static func _feuere(sim: Dictionary, event: String, events: Array[String]) -> void:
	var gefeuert: Dictionary = sim["gefeuert"]
	if gefeuert.has(event):
		return
	gefeuert[event] = true
	events.append(event)


static func _zonen_start(zonen: Array, zone: String) -> float:
	for eintrag: Dictionary in zonen:
		if str(eintrag["zone"]) == zone:
			return float(eintrag["start"])
	return 0.0
