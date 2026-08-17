class_name PipeFlowLogic
extends RefCounted
## Rohr-Wirrwarr (pipeFlow) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/pipeFlow.logic.js (PLAN2 §C1.2 #9). 5×5-Brett aus
## Geraden/Bögen/T-Stücken, per Konstruktion lösbar (Zufallspfad Hahn →
## Sprenger, danach alle Drehungen verwürfelt), Antippen dreht 90°, verbundene
## Leitung = Wasser marsch. 90 s; Score = 25·gelöst + Tap-Effizienz-Bonus
## (0–10) − 5 je Leck. Coin-Zeile: /5, 4..25, Ziel 100.
##
## HINWEIS zur Bit-Gleichheit: der Web-Generator mischt die DFS-Richtungen mit
## `[0,1,2,3].sort(() => rng() - 0.5)`. Das Ergebnis hängt an V8s TimSort
## (CountAndMakeRun + binäre Einfügesortierung) UND an der Zahl der
## Vergleicher-Aufrufe. `_shuffle_dirs_v8()` bildet genau diesen Ablauf nach,
## damit Board-Deals seed-für-seed identisch zum Web fallen (in
## tests/unit/test_mg1_pipe_flow.gd gegen Web-Golddeals gepinnt).

## Bindende §C1.2-#9-Zahlen + V2/G25-Generator-Knöpfe.
const PIPE := {
	"GRID": 5,
	"DURATION_SEC": 90.0,
	"SOLVE_POINTS": 25,
	"BONUS_MAX": 10,
	"BONUS_FULL_EXTRA": 3,
	"BONUS_ZERO_EXTRA": 15,
	"TEE_CHANCE": 0.28,
	"LEAK_FROM_PUZZLE": 3,
	"LEAK_SEC": 25.0,
	"LEAK_PENALTY": 5,
	"PREVIEW_SPEED_MULT": 1.0,
	"ROTATE_SEC": 0.16,
	"FILL_STEP_SEC": 0.09,
	"FILL_END_DELAY_SEC": 1.1,
	"ENDLESS": false,
	"ENDLESS_FAILURE_LIMIT": 3,
}

## Gewichte der Attrappen-Formen abseits des Lösungspfads.
const DECOY_WEIGHTS := {"straight": 0.38, "bend": 0.42, "tee": 0.2}

## V4/GAME-POLISH-4: Präsentations-Tuning (Hahn-Dreh, Füllwelle, Sprenger).
const PIPE_JUICE := {
	"HANDLE_SPIN_TURNS": 1.5,
	"HANDLE_SPIN_SEC": 0.8,
	"TILE_POP_SCALE": 1.14,
	"TILE_POP_SEC": 0.22,
	"SPRAY_CONFETTI": 6,
}

## Richtungen: 0=N (oben), 1=O, 2=S (unten), 3=W. Zeile 0 ist die oberste.
const DIR_N := 0
const DIR_E := 1
const DIR_S := 2
const DIR_W := 3

## Gitter-Deltas je Richtung: [dSpalte, dZeile] (Zeile wächst nach unten).
const DELTA: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Basis-Öffnungen bei rot 0 (Drehen addiert rot im Uhrzeigersinn, mod 4).
const BASE_CONNECTIONS := {
	"straight": [DIR_N, DIR_S],
	"bend": [DIR_N, DIR_E],
	"tee": [DIR_N, DIR_E, DIR_S],
}

## DFS-Knotenbudget des Solvers — echte Bretter bleiben weit darunter.
const SOLVER_NODE_BUDGET := 200000

const _MASK32 := 0xFFFFFFFF

## Formen als Index (Reihenfolge nur intern; die Board-Dicts bleiben Strings).
const _SHAPE_IDS := {"straight": 0, "bend": 1, "tee": 2}
## Öffnungen bei rot 0 als 4-Bit-Maske (Bit d = Öffnung Richtung d).
const _BASE_MASKS: Array[int] = [0b0101, 0b0011, 0b0111]
## „Unmöglich“ in der Tap-Kosten-Tabelle (min_taps_for liefert dafür INF).
const _NO_TAPS := 9
## Ganzzahliges Infinity des Solvers (echte Pfade kosten < 25·3 Taps).
const _UNREACHABLE := 1 << 28

## Nachschlagetabelle shape*64 + rot*16 + Wunschmaske → minimale Taps (0..3)
## bzw. _NO_TAPS. Ersetzt die O(n)-Suche über connections_of() im Solver —
## rein eine Beschleunigung, die Zahlen sind dieselben wie im Web.
static var _min_taps_table := PackedByteArray()


## §G5 Sequenz-/Puzzle-Difficulty; `normal` liefert PIPE unverändert.
static func apply_difficulty(tune: Dictionary = PIPE, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var preview_mult := 1.15 if hard else 0.85
	var window_mult := 0.8 if hard else 1.25
	var out := tune.duplicate()
	out["PREVIEW_SPEED_MULT"] = preview_mult
	out["ROTATE_SEC"] = float(tune["ROTATE_SEC"]) / preview_mult
	out["FILL_STEP_SEC"] = float(tune["FILL_STEP_SEC"]) / preview_mult
	out["FILL_END_DELAY_SEC"] = float(tune["FILL_END_DELAY_SEC"]) / preview_mult
	out["LEAK_SEC"] = maxf(0.35, float(tune["LEAK_SEC"]) * window_mult)
	out["LEAK_FROM_PUZZLE"] = maxi(1, int(tune["LEAK_FROM_PUZZLE"]) + (-1 if hard else 1))
	out["ENDLESS"] = mode == "endless"
	return out


## Gegenrichtung.
static func opposite(d: int) -> int:
	return (d + 2) % 4


## xmur3-artiger String-Hash → uint32 (dieselbe Rezeptur wie im Web).
static func hash32(text: String) -> int:
	var h := (1779033703 ^ text.length()) & _MASK32
	for i in text.length():
		h = _imul(h ^ text.unicode_at(i), 3432918353)
		h = (((h << 13) & _MASK32) | (h >> 19)) & _MASK32
	h = _imul(h ^ (h >> 16), 2246822507)
	h = _imul(h ^ (h >> 13), 3266489909)
	return (h ^ (h >> 16)) & _MASK32


## Öffnungen einer Kachel bei ihrer aktuellen Drehung (aufsteigend sortiert).
static func connections_of(tile: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for d: int in BASE_CONNECTIONS[tile["shape"]]:
		out.append((d + int(tile["rot"])) % 4)
	out.sort()
	return out


## Öffnungsmaske einer Form bei einer Drehung (Bit d = offen Richtung d).
static func mask_of(shape: String, rot: int) -> int:
	var base: int = _BASE_MASKS[int(_SHAPE_IDS[shape])]
	var r := rot & 3
	return ((base << r) | (base >> (4 - r))) & 0b1111


## Hat die Kachel eine Öffnung Richtung `dir`?
static func has_connection(tile: Dictionary, dir: int) -> bool:
	return (mask_of(str(tile["shape"]), int(tile["rot"])) & (1 << dir)) != 0


## Kachel 90° im Uhrzeigersinn drehen (ein Tap) — liefert eine neue Kachel.
static func rotate_tile(tile: Dictionary) -> Dictionary:
	return {"shape": tile["shape"], "rot": (int(tile["rot"]) + 1) % 4}


## Optisches Drehziel aus einer unbegrenzten Tap-Zählung (Tween-freundlich).
static func rotation_target(turns: int) -> float:
	var safe_turns := maxi(0, turns)
	return 0.0 if safe_turns == 0 else -float(safe_turns) * (PI / 2.0)


## Deterministische Tropfstelle ab Rätsel 3 (−1 = noch keine).
static func leak_joint_for(board: Dictionary, puzzle_no: int, tune: Dictionary = PIPE) -> int:
	if puzzle_no < int(tune["LEAK_FROM_PUZZLE"]):
		return -1
	var tiles: Array = board["tiles"]
	return hash32("leak:%d:%d" % [int(board["seed"]), puzzle_no]) % tiles.size()


## Die Leck-Strafe fällt genau an der 25-Sekunden-Grenze an — einmal.
static func leak_penalty_due(
	puzzle_elapsed: float, already_applied: bool, tune: Dictionary = PIPE
) -> bool:
	return not already_applied and puzzle_elapsed >= float(tune["LEAK_SEC"])


## Minimale Taps (0..3), damit die Kachel ALLE `dirs` öffnet (INF = unmöglich).
static func min_taps_for(tile: Dictionary, dirs: Array) -> float:
	var need := 0
	for d: int in dirs:
		need |= 1 << d
	var taps := taps_lookup(int(_SHAPE_IDS[str(tile["shape"])]), int(tile["rot"]), need)
	return INF if taps == _NO_TAPS else float(taps)


## Tabellen-Nachschlag: minimale Taps für (Form-Id, Drehung, Wunschmaske).
static func taps_lookup(shape_id: int, rot: int, need_mask: int) -> int:
	if _min_taps_table.is_empty():
		_build_min_taps_table()
	return _min_taps_table[shape_id * 64 + (rot & 3) * 16 + need_mask]


static func _build_min_taps_table() -> void:
	var table := PackedByteArray()
	table.resize(3 * 64)
	table.fill(_NO_TAPS)
	for shape_id in 3:
		var base: int = _BASE_MASKS[shape_id]
		for rot in 4:
			for need in 16:
				for k in 4:
					var r := (rot + k) & 3
					var mask := ((base << r) | (base >> (4 - r))) & 0b1111
					if (mask & need) == need:
						table[shape_id * 64 + rot * 16 + need] = k
						break
	_min_taps_table = table


## Wasser vom Hahn fluten (BFS über gegenüberliegende Öffnungen).
static func water_reach(board: Dictionary) -> Dictionary:
	var size := int(board["size"])
	var masks := _board_masks(board["tiles"])
	var depths := {}
	var src_idx := int(board["srcCol"])
	if (masks[src_idx] & (1 << DIR_N)) == 0:
		return {"solved": false, "depths": depths}
	depths[src_idx] = 0
	var queue: Array[int] = [src_idx]
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var col := idx % size
		var row := (idx - col) / size
		var depth: int = depths[idx]
		var mask := masks[idx]
		for dir in 4:
			if (mask & (1 << dir)) == 0:
				continue
			var nc := col + DELTA[dir].x
			var nr := row + DELTA[dir].y
			if nc < 0 or nc >= size or nr < 0 or nr >= size:
				continue
			var n_idx := nr * size + nc
			if depths.has(n_idx):
				continue
			if (masks[n_idx] & (1 << opposite(dir))) == 0:
				continue
			depths[n_idx] = depth + 1
			queue.append(n_idx)
	var goal_idx := (size - 1) * size + int(board["goalCol"])
	var solved := depths.has(goal_idx) and (masks[goal_idx] & (1 << DIR_S)) != 0
	return {"solved": solved, "depths": depths}


## Öffnungsmasken aller Kacheln — der heiße Pfad von BFS und Solver.
static func _board_masks(tiles: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(tiles.size())
	for i in tiles.size():
		var tile: Dictionary = tiles[i]
		out[i] = mask_of(str(tile["shape"]), int(tile["rot"]))
	return out


## Tap-Kosten je (Kachel, Wunschmaske) — 16 Einträge pro Kachel, O(1)-Zugriff.
static func _board_tap_costs(tiles: Array) -> PackedByteArray:
	if _min_taps_table.is_empty():
		_build_min_taps_table()
	var out := PackedByteArray()
	out.resize(tiles.size() * 16)
	for i in tiles.size():
		var tile: Dictionary = tiles[i]
		var offset: int = int(_SHAPE_IDS[str(tile["shape"])]) * 64 + (int(tile["rot"]) & 3) * 16
		for need in 16:
			out[i * 16 + need] = _min_taps_table[offset + need]
	return out


## Verbindet das Wasser Hahn → Sprenger?
static func is_solved(board: Dictionary) -> bool:
	return bool(water_reach(board)["solved"])


## Ein Deal erzeugen (§C1.2 #9) — lösbar per Konstruktion, optimalTaps geprüft.
static func generate_board(seed_value: int, tune: Dictionary = PIPE) -> Dictionary:
	var rng := GoobyRng.new(hash32("pipe:%d" % seed_value))
	var size := int(tune["GRID"])
	var src_col := int(floor(rng.next() * float(size)))
	var goal_col := int(floor(rng.next() * float(size)))
	var path := _random_path(rng, size, src_col, goal_col)

	var tiles: Array[Dictionary] = []
	tiles.resize(size * size)
	var on_path := {}
	for idx in path:
		on_path[idx] = true

	for i in path.size():
		var idx: int = path[i]
		# Wasser tritt an der Seite zum Vorgänger ein (Quelle: N-Kante) und
		# verlässt die Kachel Richtung Nachfolger (Sprenger: S-Kante).
		var in_dir := DIR_N
		if i > 0:
			var prev: int = path[i - 1]
			var d_col := (idx % size) - (prev % size)
			var d_row := (idx / size) - (prev / size)
			in_dir = opposite(_delta_index(d_col, d_row))
		var out_dir := DIR_S
		if i < path.size() - 1:
			var next: int = path[i + 1]
			var d_col2 := (next % size) - (idx % size)
			var d_row2 := (next / size) - (idx / size)
			out_dir = _delta_index(d_col2, d_row2)
		var shape := _shape_for_openings(rng, in_dir, out_dir, tune)
		tiles[idx] = {"shape": shape, "rot": _solved_rot_for(shape, [in_dir, out_dir], rng)}

	for idx in size * size:
		if on_path.has(idx):
			continue
		tiles[idx] = {"shape": _decoy_shape(rng, tune), "rot": int(floor(rng.next() * 4.0))}

	var board := {
		"size": size,
		"tiles": tiles,
		"srcCol": src_col,
		"goalCol": goal_col,
		"optimalTaps": 0,
		"seed": seed_value,
	}

	# Alle Drehungen verwürfeln; neu würfeln, falls der Deal schon verbunden
	# rauskam (der Spieler soll etwas zu tun haben).
	for _guard in 8:
		for idx in size * size:
			var t: Dictionary = tiles[idx]
			tiles[idx] = {
				"shape": t["shape"],
				"rot": (int(t["rot"]) + int(floor(rng.next() * 4.0))) % 4,
			}
		if not is_solved(board):
			break

	var solution: Array = solve_board(board)["taps"]
	board["optimalTaps"] = solution.size()
	return board


## BFS/Branch-and-Bound-Solver: minimale Tap-Folge (oder solvable=false).
static func solve_board(board: Dictionary) -> Dictionary:
	if is_solved(board):
		return {"taps": [] as Array[int], "solvable": true}
	var legs := _search_best_path(board)
	if legs.is_empty():
		return {"taps": [] as Array[int], "solvable": false}
	var taps: Array[int] = []
	for leg: Dictionary in legs:
		for _i in int(leg["taps"]):
			taps.append(int(leg["idx"]))
	# Verifizieren (der §C1.5-Beweis): auf einer Kopie nachspielen.
	var copy_tiles: Array[Dictionary] = []
	for tile: Dictionary in board["tiles"]:
		copy_tiles.append(tile.duplicate())
	var copy := board.duplicate()
	copy["tiles"] = copy_tiles
	for idx in taps:
		copy_tiles[idx] = rotate_tile(copy_tiles[idx])
	return {"taps": taps, "solvable": is_solved(copy)}


## Tap-Effizienz-Bonus: 10 bis optimal+3, linear auf 0 bei optimal+15.
static func tap_efficiency_bonus(
	total_taps: int, optimal_taps: int, tune: Dictionary = PIPE
) -> int:
	var extra := maxi(0, total_taps - optimal_taps)
	if extra <= int(tune["BONUS_FULL_EXTRA"]):
		return int(tune["BONUS_MAX"])
	if extra >= int(tune["BONUS_ZERO_EXTRA"]):
		return 0
	var span := float(int(tune["BONUS_ZERO_EXTRA"]) - int(tune["BONUS_FULL_EXTRA"]))
	return int(
		round(float(int(tune["BONUS_MAX"]) * (int(tune["BONUS_ZERO_EXTRA"]) - extra)) / span)
	)


## Rundenscore: 25·gelöst + Effizienzbonus − 5 je Leck (Bonus erst ab 1 Lösung).
static func pipe_score(
	solved: int, total_taps: int, optimal_taps: int, tune: Dictionary = PIPE, leaks := 0
) -> int:
	if solved <= 0:
		return 0
	return maxi(
		0,
		(
			int(tune["SOLVE_POINTS"]) * solved
			+ tap_efficiency_bonus(total_taps, optimal_taps, tune)
			- maxi(0, leaks) * int(tune["LEAK_PENALTY"])
		)
	)


## §G5.4 Endlos endet nach drei ungelösten/undichten Rätseln.
static func endless_should_end(failures: int, tune: Dictionary = PIPE) -> bool:
	return bool(tune["ENDLESS"]) and failures >= int(tune["ENDLESS_FAILURE_LIMIT"])


## Solver-gestützte deterministische Bot-Zertifizierung.
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(PIPE, mode)
	var duration := 150.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	var elapsed := 0.0
	var puzzle := 0
	var solved := 0
	var failures := 0
	var taps := 0
	var optimal := 0
	while elapsed < duration and failures < int(tune["ENDLESS_FAILURE_LIMIT"]):
		puzzle += 1
		var board := generate_board(seed_value * 1009 + puzzle, tune)
		var solution: Array = solve_board(board)["taps"]
		# Schnellere Previews lassen weniger Zeit, jede Kachel zu lesen. Der
		# Bot liest das als Studier-/Tap-Druck, nicht als Gratis-Durchsatz.
		var solve_sec := (3.2 + float(solution.size()) * 0.34) * float(tune["PREVIEW_SPEED_MULT"])
		var leaking := (
			puzzle >= int(tune["LEAK_FROM_PUZZLE"]) and solve_sec >= float(tune["LEAK_SEC"])
		)
		elapsed += solve_sec + float(tune["FILL_END_DELAY_SEC"])
		if elapsed > duration:
			if bool(tune["ENDLESS"]):
				failures += 1
			break
		if leaking:
			failures += 1
		solved += 1
		taps += solution.size()
		optimal += solution.size()
	return {
		"seed": seed_value,
		"mode": mode,
		"score": pipe_score(solved, taps, optimal, tune, failures),
		"solved": solved,
		"failures": failures,
	}


## JS Math.imul-Replikat: (a·b) mod 2^32 auf 32-Bit-Mustern.
static func _imul(a: int, b: int) -> int:
	var ua := a & _MASK32
	var ub := b & _MASK32
	var hi := (((ua >> 16) * ub) & 0xFFFF) << 16
	return (hi + (ua & 0xFFFF) * ub) & _MASK32


## Index der Richtung mit genau diesem [dSpalte, dZeile]-Delta.
static func _delta_index(d_col: int, d_row: int) -> int:
	for i in DELTA.size():
		if DELTA[i].x == d_col and DELTA[i].y == d_row:
			return i
	return -1


## `[0,1,2,3].sort(() => rng() - 0.5)` — V8-TimSort für kurze Arrays
## nachgebaut: CountAndMakeRun, dann binäre Einfügesortierung. Der
## Vergleicher ignoriert seine Argumente und verbraucht je Aufruf EIN rng().
static func _shuffle_dirs_v8(rng: GoobyRng) -> Array[int]:
	var a: Array[int] = [0, 1, 2, 3]
	var run_length := _count_and_make_run(a, rng)
	# min_run_length(4) == 4 → der Rest wandert per Einfügesortierung rein.
	if run_length < a.size():
		_binary_insertion_sort(a, 0, run_length, a.size(), rng)
	return a


static func _count_and_make_run(a: Array[int], rng: GoobyRng) -> int:
	var high := a.size()
	if high <= 1:
		return high
	var run_length := 2
	var is_descending := (rng.next() - 0.5) < 0.0
	for _idx in range(2, high):
		var order := rng.next() - 0.5
		if is_descending:
			if order >= 0.0:
				break
		elif order < 0.0:
			break
		run_length += 1
	if is_descending:
		var slice := a.slice(0, run_length)
		slice.reverse()
		for i in run_length:
			a[i] = slice[i]
	return run_length


static func _binary_insertion_sort(
	a: Array[int], low: int, start_arg: int, high: int, rng: GoobyRng
) -> void:
	var start := start_arg + 1 if low == start_arg else start_arg
	while start < high:
		var left := low
		var right := start
		var pivot := a[start]
		while left < right:
			var mid := left + ((right - left) >> 1)
			if (rng.next() - 0.5) < 0.0:
				right = mid
			else:
				left = mid + 1
		for i in range(start, left, -1):
			a[i] = a[i - 1]
		a[left] = pivot
		start += 1


## Geseedeter selbstmeidender Pfad (srcCol, 0) → (goalCol, size−1) per DFS.
static func _random_path(rng: GoobyRng, size: int, src_col: int, goal_col: int) -> Array[int]:
	var state := {
		"rng": rng,
		"size": size,
		"goal": (size - 1) * size + goal_col,
		"visited": {},
		"path": [] as Array[int],
	}
	_path_dfs(state, src_col)
	return state["path"]


static func _path_dfs(state: Dictionary, idx: int) -> bool:
	var visited: Dictionary = state["visited"]
	var path: Array[int] = state["path"]
	var size: int = state["size"]
	visited[idx] = true
	path.append(idx)
	if idx == int(state["goal"]):
		return true
	var col := idx % size
	var row := (idx - col) / size
	for dir in _shuffle_dirs_v8(state["rng"]):
		var nc := col + DELTA[dir].x
		var nr := row + DELTA[dir].y
		if nc < 0 or nc >= size or nr < 0 or nr >= size:
			continue
		var n_idx := nr * size + nc
		if visited.has(n_idx):
			continue
		if _path_dfs(state, n_idx):
			return true
	path.pop_back()
	return false


## Form wählen, die beide Richtungen bedienen kann (geseedet).
static func _shape_for_openings(
	rng: GoobyRng, in_dir: int, out_dir: int, tune: Dictionary
) -> String:
	var straight_fits := opposite(in_dir) == out_dir
	if rng.next() < float(tune["TEE_CHANCE"]):
		# Ein T bedient jedes Paar unterschiedlicher Richtungen.
		return "tee"
	return "straight" if straight_fits else "bend"


## Gelöste Drehung einer Form, die alle `dirs` öffnen muss.
static func _solved_rot_for(shape: String, dirs: Array, rng: GoobyRng) -> int:
	var fits: Array[int] = []
	for rot in 4:
		var conns := connections_of({"shape": shape, "rot": rot})
		var all_in := true
		for d: int in dirs:
			if not conns.has(d):
				all_in = false
				break
		if all_in:
			fits.append(rot)
	return fits[int(floor(rng.next() * float(fits.size())))]


## Gewichtete Attrappen-Form.
static func _decoy_shape(rng: GoobyRng, _tune: Dictionary) -> String:
	var r := rng.next()
	if r < float(DECOY_WEIGHTS["straight"]):
		return "straight"
	if r < float(DECOY_WEIGHTS["straight"]) + float(DECOY_WEIGHTS["bend"]):
		return "bend"
	return "tee"


## Branch-and-Bound-DFS über EINFACHE Hahn→Sprenger-Pfade.
static func _search_best_path(board: Dictionary) -> Array:
	var search := _PathSearch.new()
	search.size = int(board["size"])
	search.goal = (search.size - 1) * search.size + int(board["goalCol"])
	search.cost = _board_tap_costs(board["tiles"])
	search.h = _relaxed_to_goal(board, search.cost)
	search.visited.resize(search.size * search.size)
	var src_col := int(board["srcCol"])
	search.visited[src_col] = 1
	search.dfs(src_col, DIR_N, 0)
	return search.best_legs


## Zulässige Heuristik: relaxierte Restkosten je (Zelle, Eintrittsseite).
## O(V²)-Dijkstra auf dem umgedrehten Graphen; _NO_TAPS steht für „nie“.
static func _relaxed_to_goal(board: Dictionary, cost: PackedByteArray) -> PackedInt32Array:
	var size := int(board["size"])
	var state_count := size * size * 4
	var goal_idx := (size - 1) * size + int(board["goalCol"])
	var h := PackedInt32Array()
	h.resize(state_count)
	h.fill(_UNREACHABLE)
	var settled := PackedByteArray()
	settled.resize(state_count)
	# Endkanten: die Zielzelle über `entry` betreten und nach S verlassen.
	for entry in 4:
		if entry == DIR_S:
			continue
		var k: int = cost[goal_idx * 16 + ((1 << entry) | (1 << DIR_S))]
		if k != _NO_TAPS:
			h[goal_idx * 4 + entry] = k
	while true:
		var u := -1
		var u_cost := _UNREACHABLE
		for s in state_count:
			if settled[s] == 0 and h[s] < u_cost:
				u = s
				u_cost = h[s]
		if u == -1:
			break
		settled[u] = 1
		var entry := u % 4
		var idx := (u - entry) / 4
		var col := idx % size
		var row := (idx - col) / size
		var exit_dir := opposite(entry)
		var pc := col - DELTA[exit_dir].x
		var pr := row - DELTA[exit_dir].y
		if pc < 0 or pc >= size or pr < 0 or pr >= size:
			continue
		var p_idx := pr * size + pc
		for p_entry in 4:
			if p_entry == exit_dir:
				continue
			var k: int = cost[p_idx * 16 + ((1 << p_entry) | (1 << exit_dir))]
			if k == _NO_TAPS:
				continue
			var v := p_idx * 4 + p_entry
			if u_cost + k < h[v]:
				h[v] = u_cost + k
	return h


## Solver-Zustand als eigenes Objekt: Felder statt Dictionary-Zugriffe halten
## die Rekursion in GDScript schnell genug für die Bot-Zertifizierung.
class _PathSearch:
	extends RefCounted

	var size := 5
	var goal := 0
	var cost := PackedByteArray()
	var h := PackedInt32Array()
	var visited := PackedByteArray()
	var best := _UNREACHABLE
	var best_legs: Array = []
	var legs: Array = []
	var nodes := 0

	func dfs(idx: int, entry: int, g: int) -> void:
		nodes += 1
		if nodes > SOLVER_NODE_BUDGET:
			return
		if g + h[idx * 4 + entry] >= best:
			return
		var col := idx % size
		var row := (idx - col) / size
		var base := idx * 16
		var entry_bit := 1 << entry
		for exit_dir in 4:
			if exit_dir == entry:
				continue
			var k: int = cost[base + (entry_bit | (1 << exit_dir))]
			if k == _NO_TAPS:
				continue
			if idx == goal and exit_dir == DIR_S:
				if g + k < best:
					best = g + k
					best_legs = legs.duplicate()
					best_legs.append({"idx": idx, "taps": k})
				continue
			var nc := col + DELTA[exit_dir].x
			var nr := row + DELTA[exit_dir].y
			if nc < 0 or nc >= size or nr < 0 or nr >= size:
				continue
			var n_idx := nr * size + nc
			if visited[n_idx] == 1:
				continue
			visited[n_idx] = 1
			legs.append({"idx": idx, "taps": k})
			dfs(n_idx, PipeFlowLogic.opposite(exit_dir), g + k)
			legs.pop_back()
			visited[n_idx] = 0
