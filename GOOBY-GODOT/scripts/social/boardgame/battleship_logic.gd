class_name BattleshipLogic
extends RefCounted
## Schiffe versenken — PURE Spiellogik (W3c VISIT, Plan §2.3: deterministisch,
## keine Legalitäts-Engine im Server — der Server bleibt Turn-Relay).
##
## 10×10-Brett, Flotte 5/4/3/3/2. Eine Instanz = das EIGENE Brett eines
## Spielers (nimmt Schüsse entgegen); fürs gegnerische Brett gibt es den
## `Tracker` (merkt sich eigene Schüsse + versenkte Schiffe) und für den
## Zug-Spiegel des Server-Zustands den `Turn` (n/phase/turn — exakt die
## Regeln aus GOOBY-SERVER/src/boardgames.js).
##
## Schiff-Format (überall gleich, JSON-tauglich):
##   {"at": [x, y], "len": int, "horizontal": bool}   x/y 0..9, at = Bug.

const GRID := 10
const FLEET: Array[int] = [5, 4, 3, 3, 2]
const COLS := "ABCDEFGHIJ"

## Stabile Ablehnungsgründe von validate_fleet (für UI/Tests).
const REASON_OK := ""
const REASON_WRONG_COUNT := "wrong_count"
const REASON_WRONG_LENGTHS := "wrong_lengths"
const REASON_OUT_OF_BOUNDS := "out_of_bounds"
const REASON_OVERLAP := "overlap"

var ships: Array[Dictionary] = []
var shots_received: Dictionary = {}  # Vector2i -> true

var _cell_to_ship: Dictionary = {}  # Vector2i -> ship-Index


## Zellen eines Schiffs (Bug `at`, Länge, Richtung).
static func ship_cells(ship: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var at := to_cell(ship.get("at", [0, 0]))
	var horizontal := bool(ship.get("horizontal", true))
	for i in int(ship.get("len", 0)):
		cells.append(at + (Vector2i(i, 0) if horizontal else Vector2i(0, i)))
	return cells


static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID and cell.y < GRID


## Flotten-Validierung: exakt 5/4/3/3/2, alles im Brett, keine Überlappung.
static func validate_fleet(fleet: Array) -> Dictionary:
	if fleet.size() != FLEET.size():
		return {"ok": false, "reason": REASON_WRONG_COUNT}
	var lengths: Array[int] = []
	for ship: Variant in fleet:
		if not (ship is Dictionary):
			return {"ok": false, "reason": REASON_WRONG_LENGTHS}
		lengths.append(int((ship as Dictionary).get("len", 0)))
	lengths.sort()
	var wanted := FLEET.duplicate()
	wanted.sort()
	if lengths != wanted:
		return {"ok": false, "reason": REASON_WRONG_LENGTHS}
	var taken: Dictionary = {}
	for ship: Dictionary in fleet:
		for cell in ship_cells(ship):
			if not in_bounds(cell):
				return {"ok": false, "reason": REASON_OUT_OF_BOUNDS}
			if taken.has(cell):
				return {"ok": false, "reason": REASON_OVERLAP}
			taken[cell] = true
	return {"ok": true, "reason": REASON_OK}


## Deterministische Zufallsflotte (GoobyRng = mulberry32, W2d): gleicher Seed
## ⇒ gleiche Flotte auf jedem Gerät — Grundlage der Integrationstests.
static func auto_fleet(seed_value: int) -> Array[Dictionary]:
	var rng := GoobyRng.new(seed_value)
	var fleet: Array[Dictionary] = []
	var taken: Dictionary = {}
	for length in FLEET:
		var placed := false
		while not placed:
			var horizontal := rng.next() < 0.5
			var max_x := GRID - (length if horizontal else 1)
			var max_y := GRID - (1 if horizontal else length)
			var at := Vector2i(
				int(rng.next() * float(max_x + 1)), int(rng.next() * float(max_y + 1))
			)
			var ship := {"at": [at.x, at.y], "len": length, "horizontal": horizontal}
			var free := true
			for cell in ship_cells(ship):
				if taken.has(cell):
					free = false
					break
			if free:
				for cell in ship_cells(ship):
					taken[cell] = true
				fleet.append(ship)
				placed = true
	return fleet


## Zellen-Notation des Protokolls: "B4" = Spalte B (x=1), Reihe 4 (y=3).
static func cell_to_ref(cell: Vector2i) -> String:
	if not in_bounds(cell):
		return ""
	return "%s%d" % [COLS[cell.x], cell.y + 1]


## "B4" -> Vector2i(1, 3); Vector2i(-1, -1) bei Unsinn.
static func ref_to_cell(ref: String) -> Vector2i:
	var text := ref.strip_edges().to_upper()
	if text.length() < 2 or text.length() > 3:
		return Vector2i(-1, -1)
	var x := COLS.find(text[0])
	if x < 0 or not text.substr(1).is_valid_int():
		return Vector2i(-1, -1)
	var y := int(text.substr(1)) - 1
	var cell := Vector2i(x, y)
	return cell if in_bounds(cell) else Vector2i(-1, -1)


## `at` als [x, y]-Array ODER Vector2i akzeptieren (JSON-Roundtrip).
static func to_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


## Eigenes Brett aufsetzen. false = Flotte ungültig (Brett bleibt leer).
func setup(fleet: Array) -> bool:
	if not validate_fleet(fleet)["ok"]:
		return false
	ships = []
	shots_received = {}
	_cell_to_ship = {}
	for ship: Dictionary in fleet:
		var normalized := {
			"at": [to_cell(ship["at"]).x, to_cell(ship["at"]).y],
			"len": int(ship["len"]),
			"horizontal": bool(ship.get("horizontal", true)),
		}
		ships.append(normalized)
		for cell in ship_cells(normalized):
			_cell_to_ship[cell] = ships.size() - 1
	return true


func is_ready() -> bool:
	return ships.size() == FLEET.size()


## Schuss aufs EIGENE Brett auswerten (der Beschossene antwortet SHOT_RESULT).
## {hit, sunk, sunk_cells, all_sunk, repeat} — repeat = Zelle schon beschossen
## (Wasser melden, nichts doppelt zählen).
func receive_shot(cell: Vector2i) -> Dictionary:
	var out := {"hit": false, "sunk": false, "sunk_cells": [], "all_sunk": false, "repeat": false}
	if not in_bounds(cell):
		return out
	if shots_received.has(cell):
		out["repeat"] = true
		out["hit"] = _cell_to_ship.has(cell)
		return out
	shots_received[cell] = true
	if not _cell_to_ship.has(cell):
		return out
	out["hit"] = true
	var ship: Dictionary = ships[_cell_to_ship[cell]]
	var cells := ship_cells(ship)
	var sunk := true
	for ship_cell in cells:
		if not shots_received.has(ship_cell):
			sunk = false
			break
	if sunk:
		out["sunk"] = true
		for ship_cell in cells:
			(out["sunk_cells"] as Array).append([ship_cell.x, ship_cell.y])
		out["all_sunk"] = remaining_ships() == 0
	return out


## Noch schwimmende (nicht komplett getroffene) Schiffe.
func remaining_ships() -> int:
	var remaining := 0
	for ship in ships:
		for cell in ship_cells(ship):
			if not shots_received.has(cell):
				remaining += 1
				break
	return remaining


## Gegner-Brett-Sicht des Schützen: eigene Schüsse + versenkte Schiffe.
class Tracker:
	extends RefCounted

	var shots: Dictionary = {}  # Vector2i -> hit: bool
	var sunk_count := 0

	func is_new_target(cell: Vector2i) -> bool:
		return BattleshipLogic.in_bounds(cell) and not shots.has(cell)

	func record(cell: Vector2i, hit: bool, sunk: bool) -> void:
		shots[cell] = hit
		if sunk:
			sunk_count += 1

	func has_won() -> bool:
		return sunk_count >= BattleshipLogic.FLEET.size()


## Client-Spiegel der Server-Turn-Ownership (boardgames.js): SHOT nur wer
## dran ist, SHOT_RESULT nur vom Beschossenen, n exakt; nach dem Paar
## wechselt der Zug. Runde = abgeschlossene Paare BEIDER Spieler (/2).
class Turn:
	extends RefCounted

	var n := 1
	var phase := "shot"  # "shot" -> "result" -> Zugwechsel
	var turn_code := ""
	var exchanges := 0

	var _players: Array[String] = []

	func _init(first: String, players: Array) -> void:
		turn_code = first
		for code: Variant in players:
			_players.append(str(code))

	func can_shoot(code: String) -> bool:
		return phase == "shot" and turn_code == code

	func can_answer(code: String) -> bool:
		return phase == "result" and turn_code != code

	func on_shot() -> void:
		phase = "result"

	func on_result() -> void:
		phase = "shot"
		n += 1
		exchanges += 1
		for code in _players:
			if code != turn_code:
				turn_code = code
				break

	## Runden-Zählung EXAKT wie der Server (fürs Tomaten-Limit).
	func round_index() -> int:
		return exchanges / 2
