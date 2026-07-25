class_name MiniGolfCourse
extends RefCounted
## Bahn-Erzeugung + Geometrie für Minigolf — zahlengleicher Port der
## Course-Hälfte von GOOBY/src/minigames/games/miniGolf.logic.js.
## Sechs gesetzte Löcher (gerade / Ecke / Rampe / Kuppel / Windmühle / Tunnel,
## Par 2–3) plus das bedingte Bonusloch 7 „Nougat-Schleuse“ (§C10.2).
## Die Physik/Wertung liegt in `mini_golf_logic.gd`.

## Zellenraster: RAIL + BALL_R aus GOLF; hier gespiegelt, damit die Geometrie
## ohne Zirkelbezug auf mini_golf_logic.gd auskommt.
const RAIL := 0.055
const BALL_R := 0.08
const RAMP_H := 0.1
const NOUGAT_R := 0.18
const NOUGAT_AMPLITUDE := 0.24
const HOLE_COUNT := 6


## JS-`Math.round` rundet .5 immer nach +∞ — Godots round() rundet vom Nullpunkt
## weg. Bei negativen Zell-x (Dogleg nach links) macht das einen Unterschied.
static func js_round(v: float) -> int:
	return int(floor(v + 0.5))


static func _cell_set_of(cells: Array) -> Dictionary:
	var out := {}
	for cell: Array in cells:
		out["%d,%d" % [int(cell[0]), int(cell[1])]] = true
	return out


## Die gesetzte Sechs-Loch-Bahn; der Seed variiert Dogleg-Richtung,
## Kuppel-Position und Windmühlen-Phase. `rng` ist ein Callable -> float 0..1.
static func generate_course(rng: Callable, tune: Dictionary) -> Array[Dictionary]:
	var holes: Array[Dictionary] = []
	var par_bonus := int(tune.get("PAR_BONUS", 0))

	holes.append(
		_finish({"id": "straight", "par": 2, "cells": [[0, 0], [0, 1], [0, 2], [0, 3]]}, par_bonus)
	)

	var dir_x := 1 if float(rng.call()) < 0.5 else -1
	(
		holes
		. append(
			_finish(
				{
					"id": "corner",
					"par": 2,
					"cells": [[0, 0], [0, 1], [0, 2], [dir_x, 2], [dir_x * 2, 2]],
					"waypoints": [{"x": 0.0, "z": 2.0}],
				},
				par_bonus
			)
		)
	)

	(
		holes
		. append(
			_finish(
				{
					"id": "ramp",
					"par": 3,
					"cells": [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]],
					"ramp": {"cell": [0, 2], "dir": [0, 1], "h": RAMP_H},
					"botPowerMul": 1.45,
				},
				par_bonus
			)
		)
	)

	var bump_z := 2 if float(rng.call()) < 0.5 else 3
	var side := 0.3 if float(rng.call()) < 0.5 else -0.3
	(
		holes
		. append(
			_finish(
				{
					"id": "bump",
					"par": 2,
					"cells": [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]],
					"bump": {"x": 0.0, "z": float(bump_z)},
					"waypoints": [{"x": side, "z": float(bump_z)}],
				},
				par_bonus
			)
		)
	)

	(
		holes
		. append(
			_finish(
				{
					"id": "windmill",
					"par": 3,
					"cells": [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]],
					"windmill": {"cellX": 0, "gateZ": 2.0, "phase": float(rng.call()) * PI * 2.0},
				},
				par_bonus
			)
		)
	)

	(
		holes
		. append(
			_finish(
				{
					"id": "tunnel",
					"par": 3,
					"cells": [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5]],
					"tunnel": {"cell": [0, 3]},
				},
				par_bonus
			)
		)
	)
	return holes


static func _finish(hole: Dictionary, par_bonus: int) -> Dictionary:
	if par_bonus != 0:
		hole["par"] = int(hole["par"]) + par_bonus
	hole["cellSet"] = _cell_set_of(hole["cells"])
	var cells: Array = hole["cells"]
	hole["start"] = {"x": float(cells[0][0]), "z": float(cells[0][1])}
	var last: Array = cells[cells.size() - 1]
	hole["hole"] = {"x": float(last[0]), "z": float(last[1])}
	if not hole.has("waypoints"):
		hole["waypoints"] = []
	if not hole.has("botPowerMul"):
		hole["botPowerMul"] = 1.0
	return hole


## Bonusloch 7 „Nougat-Loop“ (§C10.2) — separat gebaut, damit die Sechs-Loch-
## Bahn und ihre Wertungszeile unverändert bleiben.
static func create_nougat_loop_hole(rng: Callable, tune: Dictionary) -> Dictionary:
	var hole := {
		"id": "nougatLoop",
		"par": 3 + int(tune.get("PAR_BONUS", 0)),
		"cells": [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5]],
		"waypoints": [{"x": 0.0, "z": 2.0}, {"x": 0.28, "z": 3.25}],
		"botPowerMul": 1.0,
		"loop": {"x": 0.0, "z": 2.0},
		"nougat":
		{
			"centerX": 0.0,
			"z": 3.15,
			"amplitude": NOUGAT_AMPLITUDE,
			"radius": NOUGAT_R,
			"phase": float(rng.call()) * PI * 2.0,
		},
	}
	hole["cellSet"] = _cell_set_of(hole["cells"])
	hole["start"] = {"x": 0.0, "z": 0.0}
	hole["hole"] = {"x": 0.0, "z": 5.0}
	return hole


## Alle sechs Grundlöcher müssen Par+1 oder besser sein, um Loch 7 zu öffnen.
static func qualifies_nougat_loop(results: Array) -> bool:
	if results.size() != HOLE_COUNT:
		return false
	for row: Dictionary in results:
		if not bool(row.get("holed", true)):
			return false
		if int(row["strokes"]) > int(row["par"]) + 1:
			return false
	return true


## x-Position der wandernden Nougatschleuse (Optik und Physik teilen sie).
static func nougat_x_at(hole: Dictionary, theta: float) -> float:
	var nougat: Dictionary = hole.get("nougat", {})
	if nougat.is_empty():
		return INF
	return (
		float(nougat["centerX"]) + sin(theta + float(nougat["phase"])) * float(nougat["amplitude"])
	)


## Renderrollen der Pfadzellen (Kachelplatzierung + Ein-/Ausgangsrichtung).
static func cell_roles(hole: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cells: Array = hole["cells"]
	for i in cells.size():
		var x := int(cells[i][0])
		var z := int(cells[i][1])
		var in_dir: Variant = null
		var out_dir: Variant = null
		if i > 0:
			in_dir = [x - int(cells[i - 1][0]), z - int(cells[i - 1][1])]
		if i + 1 < cells.size():
			out_dir = [int(cells[i + 1][0]) - x, int(cells[i + 1][1]) - z]
		out.append(
			{
				"x": x,
				"z": z,
				"role": _role_of(hole, x, z, i, in_dir, out_dir),
				"inDir": in_dir,
				"outDir": out_dir
			}
		)
	return out


static func _role_of(
	hole: Dictionary, x: int, z: int, i: int, in_dir: Variant, out_dir: Variant
) -> String:
	if i == 0:
		return "start"
	if out_dir == null:
		return "hole"
	var ramp: Dictionary = hole.get("ramp", {})
	if not ramp.is_empty() and int(ramp["cell"][0]) == x and int(ramp["cell"][1]) == z:
		return "ramp"
	var mill: Dictionary = hole.get("windmill", {})
	if not mill.is_empty() and int(mill["cellX"]) == x and int(mill["gateZ"]) == z:
		return "windmill"
	var tunnel: Dictionary = hole.get("tunnel", {})
	if not tunnel.is_empty() and int(tunnel["cell"][0]) == x and int(tunnel["cell"][1]) == z:
		return "tunnel"
	var bump: Dictionary = hole.get("bump", {})
	if not bump.is_empty() and js_round(float(bump["x"])) == x and js_round(float(bump["z"])) == z:
		return "bump"
	if in_dir != null and (in_dir[0] != out_dir[0] or in_dir[1] != out_dir[1]):
		return "corner"
	return "straight"


## Bodenhöhe an einem Punkt (Rampenlöcher heben das Plateau dahinter an).
static func height_at(hole: Dictionary, x: float, z: float) -> float:
	var ramp: Dictionary = hole.get("ramp", {})
	if ramp.is_empty():
		return 0.0
	var cell: Array = ramp["cell"]
	var dir: Array = ramp["dir"]
	var p := (x - float(cell[0])) * float(dir[0]) + (z - float(cell[1])) * float(dir[1])
	if p <= -0.5:
		return 0.0
	if p >= 0.5:
		return float(ramp["h"])
	return float(ramp["h"]) * (p + 0.5)


static func on_ramp(hole: Dictionary, x: float, z: float) -> bool:
	var ramp: Dictionary = hole.get("ramp", {})
	if ramp.is_empty():
		return false
	return js_round(x) == int(ramp["cell"][0]) and js_round(z) == int(ramp["cell"][1])


## Darf der Ballmittelpunkt hier ruhen? Zellzugehörigkeit + Bandenversatz.
static func can_be_at(hole: Dictionary, x: float, z: float) -> bool:
	var cells: Dictionary = hole["cellSet"]
	var cx := js_round(x)
	var cz := js_round(z)
	if not cells.has("%d,%d" % [cx, cz]):
		return false
	var lim := 0.5 - RAIL - BALL_R
	var lx := x - cx
	var lz := z - cz
	if lx > lim and not cells.has("%d,%d" % [cx + 1, cz]):
		return false
	if lx < -lim and not cells.has("%d,%d" % [cx - 1, cz]):
		return false
	if lz > lim and not cells.has("%d,%d" % [cx, cz + 1]):
		return false
	if lz < -lim and not cells.has("%d,%d" % [cx, cz - 1]):
		return false
	return true


## Liegt der Ball still? Auf der Rampe zieht ihn die Schwerkraft weiter.
static func is_stopped(hole: Dictionary, ball: Dictionary) -> bool:
	var speed := sqrt(float(ball["vx"]) * float(ball["vx"]) + float(ball["vz"]) * float(ball["vz"]))
	return speed < 0.01 and not on_ramp(hole, float(ball["x"]), float(ball["z"]))
