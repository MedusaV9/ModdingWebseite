class_name GardenGrid
extends RefCounted
## GardenGrid (Doc D §6.1) — das PURE Außen-Grid. Zellgröße 1 m (gröber als
## die 0.5 m im Haus, GridData), kein Node, vollständig headless testbar.
##
## Inhalte:
## - `cells`: Vector2i → {kind, crop, stage, progress_min, watered_until}
##   mit kind ∈ {"plot", "path", "decor", "stickSpot"}.
## - `structures`: Bauten mit Footprint (shed 2×2, werkstatt 3×2,
##   gewaechshaus 2×3 + Tür-Zelle, baum 1×1, sprinkler 1×1).
## - `edges`: Zäune sind KANTEN-Elemente zwischen/an Zellen, keine Zellfüller.
##   `{"from": Vector2i, "dir": "E"|"S", "len": n, "fence": itemId}`;
##   "E" = waagerechte Kante an der Nordseite von `from`, "S" = senkrechte
##   Kante an der Westseite von `from`.
##
## Save-Format (`home.garden`, additiv im bestehenden home-Slice):
##   {"v", "size": [b, h], "stufe", "cells": [...], "edges": [...],
##    "structures": [...], "ernte": {cropId: n}, "lastTickAt"}

## Ablehnungsgründe (stabile Strings für UI/Tests).
const REASON_OK := ""
const REASON_OOB := "out_of_bounds"
const REASON_OCCUPIED := "occupied"
const REASON_NEEDS_DOOR := "needs_door"
const REASON_UNKNOWN := "unknown_structure"

const CELL_SIZE := 1.0
## Footprints der Garten-Bauten (Doc D §2.3/§5.1/§6.2).
const STRUCTURE_SIZES := {
	"shed": Vector2i(2, 2),
	"werkstatt": Vector2i(3, 2),
	"gewaechshaus": Vector2i(2, 3),
	"baum": Vector2i(1, 1),
	"sprinkler": Vector2i(1, 1),
	"garage": Vector2i(2, 3),
}
## Reichweite der Bewässerungsanlage (3×3 um die Sprinkler-Zelle).
const SPRINKLER_RADIUS := 1

var size := Vector2i(8, 6)
var cells: Dictionary = {}
var structures: Array = []
var edges: Array = []


func _init(grid_size := Vector2i(8, 6)) -> void:
	size = grid_size


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


static func structure_size(kind: String) -> Vector2i:
	return STRUCTURE_SIZES.get(kind, Vector2i.ZERO)


## Zellen eines Bauwerks (Rotation 1/3 tauscht Breite/Tiefe).
static func structure_cells(kind: String, at: Vector2i, rot := 0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var footprint := structure_size(kind)
	if footprint == Vector2i.ZERO:
		return out
	if posmod(rot, 2) == 1:
		footprint = Vector2i(footprint.y, footprint.x)
	for dy in footprint.y:
		for dx in footprint.x:
			out.append(at + Vector2i(dx, dy))
	return out


## Alle von Bauten belegten Zellen (uid-los: Garten-Bauten sind eindeutig
## über ihre Zellen adressiert).
func occupied_cells() -> Dictionary:
	var taken: Dictionary = {}
	for entry: Dictionary in structures:
		for cell in structure_cells(str(entry["kind"]), entry["at"], int(entry.get("rot", 0))):
			taken[cell] = str(entry["kind"])
	return taken


## Kann `kind` an `at` stehen? Gewächshaus braucht zusätzlich eine Tür-Zelle
## am Rand des eigenen Footprints, die an eine freie Nachbarzelle grenzt.
func can_place_structure(
	kind: String, at: Vector2i, rot := 0, door := Vector2i(-1, -1)
) -> Dictionary:
	if structure_size(kind) == Vector2i.ZERO:
		return {"ok": false, "reason": REASON_UNKNOWN}
	var taken := occupied_cells()
	var footprint := structure_cells(kind, at, rot)
	for cell in footprint:
		if not in_bounds(cell):
			return {"ok": false, "reason": REASON_OOB}
		if taken.has(cell) or _cell_kind(cell) == "plot":
			return {"ok": false, "reason": REASON_OCCUPIED}
	if kind == "gewaechshaus" and not _door_valid(footprint, door, taken):
		return {"ok": false, "reason": REASON_NEEDS_DOOR}
	return {"ok": true, "reason": REASON_OK}


func place_structure(kind: String, at: Vector2i, rot := 0, door := Vector2i(-1, -1)) -> Dictionary:
	var check := can_place_structure(kind, at, rot, door)
	if not check["ok"]:
		return check
	var entry := {"kind": kind, "at": at, "rot": posmod(rot, 4), "level": 1}
	if kind == "gewaechshaus":
		entry["door"] = door
	structures.append(entry)
	return check


## Bauwerk an einer Zelle ({} = keins).
func structure_at(cell: Vector2i) -> Dictionary:
	for entry: Dictionary in structures:
		if structure_cells(str(entry["kind"]), entry["at"], int(entry.get("rot", 0))).has(cell):
			return entry
	return {}


func structures_of_kind(kind: String) -> Array:
	var out: Array = []
	for entry: Dictionary in structures:
		if str(entry["kind"]) == kind:
			out.append(entry)
	return out


func remove_structure(cell: Vector2i) -> bool:
	for i in structures.size():
		var entry: Dictionary = structures[i]
		if structure_cells(str(entry["kind"]), entry["at"], int(entry.get("rot", 0))).has(cell):
			structures.remove_at(i)
			return true
	return false


## Zellen INNERHALB eines Gewächshauses (Wetter- und windfrei, Faktor 1.25).
func greenhouse_cells() -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in structures_of_kind("gewaechshaus"):
		for cell in structure_cells("gewaechshaus", entry["at"], int(entry.get("rot", 0))):
			if cell != entry.get("door", Vector2i(-1, -1)):
				out[cell] = true
	return out


## Von der Bewässerungsanlage abgedeckte Zellen (3×3 je Sprinkler).
func sprinkler_cells() -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in structures_of_kind("sprinkler"):
		var at: Vector2i = entry["at"]
		for dy in range(-SPRINKLER_RADIUS, SPRINKLER_RADIUS + 1):
			for dx in range(-SPRINKLER_RADIUS, SPRINKLER_RADIUS + 1):
				var cell := at + Vector2i(dx, dy)
				if in_bounds(cell):
					out[cell] = true
	return out


## Zellen, die ein Zaun gegen Wind abschirmt (bis SHIELD_DEPTH hinter der
## Kante — Doc D §6.2: „Zaun/Hecke an der Wind-Kante schirmt 3 Zellen ab“).
func fence_shielded_cells(depth := 3) -> Dictionary:
	var out: Dictionary = {}
	for edge: Dictionary in edges:
		var from: Vector2i = edge["from"]
		var length := maxi(1, int(edge.get("len", 1)))
		var horizontal := str(edge.get("dir", "E")) == "E"
		for step in length:
			for d in depth:
				var cell := from + Vector2i(step, d) if horizontal else from + Vector2i(d, step)
				if in_bounds(cell):
					out[cell] = true
	return out


## Beet-Zellen (kind == "plot").
func plot_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if _cell_kind(cell) == "plot":
			out.append(cell)
	out.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y * size.x + a.x < b.y * size.x + b.x
	)
	return out


## Freie Zellen (kein Bauwerk, kein Beet) — Stock-Spawns, neue Bauten.
func free_cells() -> Array[Vector2i]:
	var taken := occupied_cells()
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if taken.has(cell) or cells.has(cell):
				continue
			out.append(cell)
	return out


func cell(at: Vector2i) -> Dictionary:
	return cells.get(at, {})


func set_cell(at: Vector2i, data: Dictionary) -> void:
	cells[at] = data


## Save → Modell. Unbekannte Bauten/Zellen außerhalb des Grids fallen weg
## (Content-Update kann die Größe geändert haben — nie hart scheitern).
static func from_save(raw: Dictionary) -> GardenGrid:
	var size_raw: Array = raw.get("size", [8, 6])
	var grid := GardenGrid.new(Vector2i(int(size_raw[0]), int(size_raw[1])))
	for entry: Variant in raw.get("cells", []):
		if not (entry is Dictionary):
			continue
		var at := _as_cell(entry.get("at", []))
		if not grid.in_bounds(at):
			continue
		grid.cells[at] = {
			"kind": str(entry.get("kind", "plot")),
			"crop": str(entry.get("crop", "")),
			"stage": maxi(0, int(entry.get("stage", 0))),
			"progress_min": maxf(0.0, float(entry.get("progress_min", 0.0))),
			"watered_until": maxf(0.0, float(entry.get("watered_until", 0.0))),
		}
	for entry: Variant in raw.get("structures", []):
		if not (entry is Dictionary) or structure_size(str(entry.get("kind", ""))) == Vector2i.ZERO:
			continue
		var struct := {
			"kind": str(entry["kind"]),
			"at": _as_cell(entry.get("at", [])),
			"rot": posmod(int(entry.get("rot", 0)), 4),
			"level": maxi(1, int(entry.get("level", 1))),
		}
		if entry.has("door"):
			struct["door"] = _as_cell(entry["door"])
		grid.structures.append(struct)
	for entry: Variant in raw.get("edges", []):
		if not (entry is Dictionary):
			continue
		(
			grid
			. edges
			. append(
				{
					"from": _as_cell(entry.get("from", [])),
					"dir": "S" if str(entry.get("dir", "E")) == "S" else "E",
					"len": maxi(1, int(entry.get("len", 1))),
					"fence": str(entry.get("fence", "fence_wood")),
				}
			)
		)
	return grid


## Modell → Save (deterministisch sortiert, damit Diffs ruhig bleiben).
func to_save() -> Dictionary:
	var cell_list: Array = []
	var keys := cells.keys()
	keys.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y * size.x + a.x < b.y * size.x + b.x
	)
	for at: Vector2i in keys:
		var data: Dictionary = cells[at]
		(
			cell_list
			. append(
				{
					"at": [at.x, at.y],
					"kind": str(data.get("kind", "plot")),
					"crop": str(data.get("crop", "")),
					"stage": int(data.get("stage", 0)),
					"progress_min": float(data.get("progress_min", 0.0)),
					"watered_until": float(data.get("watered_until", 0.0)),
				}
			)
		)
	var struct_list: Array = []
	for entry: Dictionary in structures:
		var out := {
			"kind": str(entry["kind"]),
			"at": [entry["at"].x, entry["at"].y],
			"rot": int(entry.get("rot", 0)),
			"level": int(entry.get("level", 1)),
		}
		if entry.has("door"):
			out["door"] = [entry["door"].x, entry["door"].y]
		struct_list.append(out)
	var edge_list: Array = []
	for entry: Dictionary in edges:
		(
			edge_list
			. append(
				{
					"from": [entry["from"].x, entry["from"].y],
					"dir": str(entry["dir"]),
					"len": int(entry["len"]),
					"fence": str(entry["fence"]),
				}
			)
		)
	return {
		"size": [size.x, size.y],
		"cells": cell_list,
		"structures": struct_list,
		"edges": edge_list,
	}


static func _as_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


func _cell_kind(at: Vector2i) -> String:
	return str(cells.get(at, {}).get("kind", ""))


func _door_valid(footprint: Array[Vector2i], door: Vector2i, taken: Dictionary) -> bool:
	if not footprint.has(door):
		return false
	for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var outside: Vector2i = door + step
		if footprint.has(outside):
			continue
		if in_bounds(outside) and not taken.has(outside):
			return true
	return false
