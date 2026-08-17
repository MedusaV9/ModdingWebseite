extends Node3D
## Tempo- und Reaktions-Schicht des Gooby-Runners (MP-F Tiefenpolitur).
## Reines VIEW-Gefühl — keine Spielzahl wird angefasst:
##   - Kamera fällt mit dem Tempo leicht zurück (cam_back_extra, weich).
##   - Staubfahne an Goobys Fersen ab hohem Tempo (reduced-motion-gated).
##   - Fahrtwind: wiederkehrender Whoosh, dessen Tonhöhe mit dem Tempo steigt.
##   - Beinahe-Unfall-Erkennung: ein Hindernis zieht in Goobys Spur unter/über
##     ihm durch → kurzer Schreck (der Aufrufer spielt Mimik/Ton).
## KEIN Screenshake — Motion-Comfort-Regel der Dauerlauf-Spiele.

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

## Wie weit die Kamera bei Vollgas zusätzlich zurückfällt (m).
const CAM_BACK_MAX := 0.9
## Fahrtwind-Takt (s) bei Vollgas; darunter wird er seltener.
const WIND_GAP_SEC := 1.1
## Ab diesem Tempoband (0..1) laufen Staubfahne und Fahrtwind an.
const FEEL_MIN_BAND := 0.45

var cam_back_extra := 0.0

var _trail: GPUParticles3D
var _wind_t := 0.0
var _handled_rows: Dictionary = {}


## Staubfahne bauen und einhängen (Aufrufer hängt DIESEN Knoten in die Bühne).
func build() -> void:
	_trail = (
		Fx
		. particles(
			{
				"color": Color(0.93, 0.9, 0.82, 0.6),
				"amount": 14,
				"lifetime": 0.4,
				"speed": Vector2(0.6, 1.4),
				"spread": 30.0,
				"direction": Vector3(0.0, 0.4, 1.0),
				"gravity": Vector3(0.0, -0.6, 0.0),
				"size": Vector2(0.05, 0.12),
			}
		)
	)
	add_child(_trail)


## Pro Frame: `band01` = Tempoband 0..1, `lane_x` = Goobys Weg-x.
func tick(dt: float, band01: float, lane_x: float, reduced: bool, host: Node) -> void:
	cam_back_extra = lerpf(cam_back_extra, CAM_BACK_MAX * band01, minf(1.0, dt * 2.5))
	var feel_on := band01 >= FEEL_MIN_BAND and not reduced
	_trail.emitting = feel_on
	if feel_on:
		_trail.position = Vector3(lane_x, 0.07, 0.55)
		_trail.amount_ratio = clampf(band01, 0.4, 1.0)
	_wind_t -= dt
	if band01 >= FEEL_MIN_BAND and _wind_t <= 0.0:
		_wind_t = WIND_GAP_SEC + (1.0 - band01) * 1.6
		FeelSfx.play(host, "game_whoosh", 0.8 + band01 * 0.5)


## Beinahe-Unfall dieses Frames? Ein Hindernis hat GERADE (z-Übergang über
## −0,2) Goobys Spur passiert, ohne Treffer — also wurde es übersprungen,
## unterrutscht oder in letzter Sekunde umkurvt. Jede Zeile zählt nur einmal.
func near_miss(obstacles: Array[Dictionary], dz: float, lane: int) -> bool:
	var found := false
	for ob in obstacles:
		var z := float(ob["z"])
		if z < -0.2 or z - dz >= -0.2:
			continue
		if int(ob["lane"]) != lane:
			continue
		var row := int(ob["row"])
		if _handled_rows.has(row):
			continue
		_handled_rows[row] = true
		if _handled_rows.size() > 24:
			_handled_rows.clear()
			_handled_rows[row] = true
		found = true
	return found
