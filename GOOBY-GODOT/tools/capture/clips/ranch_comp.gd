extends "res://tools/capture/clip_driver.gd"
## Clip: Turnier-Springen (RW-5) — echter Wettbewerbs-Lauf über RcompLauf
## (Arena + Tribüne + Parcours + Richter), der Treiber reitet die
## Schlangenlinie selbst: Waypoint-Lenkung auf das nächste Hindernis,
## Absprung kurz davor. Verfolgerkamera kommt aus RcompLauf.

const RcompLaufScript := preload("res://scripts/ranch/comp/szene/comp_lauf.gd")

## Absprung-Distanz (m) vor dem Hindernis — Galopp ≈ 10 m/s.
const SPRUNG_DISTANZ := 4.2

var lauf: Node2D
var _ziele: Array = []
var _ziel_idx := 0


func _setup() -> void:
	duration = 12.0
	lauf = RcompLaufScript.new()
	add_child(lauf)
	(
		lauf
		. baue(
			{
				"disziplin": "springen",
				"klasse": "holz",
				"seed": 4242,
				"balance": RanchCompKatalog.load_balance(),
				"pferd": {},
				"zuschauer": 22,
			}
		)
	)
	lauf.apply_size(window_size())
	lauf.controller.keyboard_input = false
	_ziele = lauf.richter.hindernis_punkte()
	schedule(
		0.5,
		func() -> void:
			lauf.starte()
			lauf.controller.gait_up()
			lauf.controller.gait_up()
			lauf.controller.gait_up()
	)


func _tick(_delta: float) -> void:
	if lauf == null or lauf.controller == null or not lauf.laeuft:
		return
	var c: Node3D = lauf.controller
	if _ziel_idx >= _ziele.size():
		c.steer_input(0.0)
		return
	var ziel: Vector3 = _ziele[_ziel_idx]
	var d := ziel - c.position
	d.y = 0.0
	if d.length() < SPRUNG_DISTANZ:
		c.jump()
		_ziel_idx += 1
		return
	# RideController-Konvention: Fahrtrichtung = (−sin h, −cos h) und
	# positives Lenken VERKLEINERT heading — daher das Minus.
	var wunsch := atan2(-d.x, -d.z)
	var diff := wrapf(wunsch - c.heading, -PI, PI)
	c.steer_input(clampf(-diff * 1.7, -1.0, 1.0))
