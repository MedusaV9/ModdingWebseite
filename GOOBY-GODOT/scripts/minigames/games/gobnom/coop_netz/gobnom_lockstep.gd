class_name GobnomLockstep
extends RefCounted
## PURER Lockstep-Kern des GOB-NOM-Netz-Coops (Doc G §5.4 M2, README-Hook):
## beide Clients simulieren GobnomLogic identisch aus Server-Seed + Input-
## Strom — getauscht werden NUR Aktionen ({t, do, id, v?}, exakt das Format
## der solution.actions; der Solver beweist die Replay-Fähigkeit).
##
## Standard-Lockstep mit Input-Delay-Fenster: lokale Aktionen werden auf
## Tick `jetzt + INPUT_DELAY` geplant (3–5 Ticks, Vorgabe C §3.8) und laufen
## auf BEIDEN Geräten exakt dort. Fences („meine Inputs bis Tick X sind
## vollständig“ = upTo) fließen wandzeit-getrieben über `_clock`, damit sich
## zwei wartende Clients nie gegenseitig verklemmen. Die Sim schreitet nur,
## solange der Partner den Tick bestätigt hat (peer_confirmed).
##
## Desync-Wächter: alle HASH_TICKS Ticks wird GobnomLogic.state_hash
## verglichen (eigener vs. Partner-Report) — bei Abweichung wird `desynced`
## gesetzt und die View bricht höflich ab (Toast statt Weiterspielen).
## Node-frei und ohne Transport: die View verschickt `take_frame()`/
## `take_hashes()` über GobnomNetSession und füttert receive_*() zurück.

## Vertrags-Defaults — der Server schickt dieselben Werte im GOBNOM_START.
const INPUT_DELAY := 4
const FENCE_TICKS := 6
const HASH_TICKS := 60
## Nur die letzten N eigenen Hashes vorhalten (Speicher-Deckel).
const HASH_KEEP := 10

var state: Dictionary = {}
var side := GobnomLogic.PLAYER_A
var input_delay := INPUT_DELAY
var hash_ticks := HASH_TICKS
## Bis zu welchem Tick (inklusive) der Partner Inputs bestätigt hat.
var peer_confirmed := -1
var desynced := false
var desync_tick := -1

## Wandzeit-Ticks der View (läuft auch beim Warten weiter — Fence-Motor).
var _clock := 0
var _sent_up_to := -100
var _frame_n := 0
var _peer_frame_n := 0
## tick -> {"a": Array, "b": Array} — geplante Aktionen beider Seiten.
var _queued: Dictionary = {}
## Lokale Aktionen, die der nächste Frame mitnimmt.
var _pending_out: Array = []
var _own_hashes: Dictionary = {}
var _peer_hashes: Dictionary = {}
var _hash_out: Array = []
## Replay-Vorspulen: keine Hash-Reports nach außen queuen.
var _quiet := false


## Frischer Netz-Lauf: Level + Balance wie lokal, Seed VOM SERVER.
func start(
	level: Dictionary, balance: Dictionary, seed_value: int, my_side: String, delay := INPUT_DELAY
) -> void:
	state = GobnomLogic.new_run(level, balance, seed_value)
	side = my_side
	input_delay = delay
	peer_confirmed = -1
	desynced = false
	desync_tick = -1
	_clock = 0
	_sent_up_to = -100
	_frame_n = 0
	_peer_frame_n = 0
	_queued = {}
	_pending_out = []
	_own_hashes = {}
	_peer_hashes = {}
	_hash_out = []


func other_side() -> String:
	return GobnomLogic.PLAYER_B if side == GobnomLogic.PLAYER_A else GobnomLogic.PLAYER_A


## Darf die Sim den nächsten Tick rechnen? (Partner-Fence liegt vor.)
func can_step() -> bool:
	if state.is_empty() or desynced or GobnomLogic.is_over(state):
		return false
	return peer_confirmed >= int(state["tick"])


## Ein Wandzeit-Tick der View: plant Fences und rechnet — wenn erlaubt —
## genau einen Sim-Tick. {stepped: bool, events: Array}; stepped=false
## heißt „auf Partner warten“ (die View zeigt dann den Warte-Hinweis).
func advance() -> Dictionary:
	if state.is_empty() or desynced or GobnomLogic.is_over(state):
		return {"stepped": false, "events": []}
	_clock += 1
	if not can_step():
		return {"stepped": false, "events": []}
	state["events"] = []
	_apply_due()
	var action_events: Array = (state["events"] as Array).duplicate()
	var step_events := GobnomLogic.step(state)
	var events := action_events + step_events
	var tick := int(state["tick"])
	if tick % hash_ticks == 0:
		_record_own_hash(tick)
	return {"stepped": true, "events": events}


## Lokale Aktion planen (do: cut|pop|puff|fan|slide). Läuft NICHT sofort,
## sondern deterministisch auf beiden Geräten bei Tick `t` — die Sim-Gates
## (fremde Seite, Schnitt-Budget) entscheiden erst bei der Ausführung.
func schedule(do_kind: String, id: int, v := NAN) -> Dictionary:
	if state.is_empty() or desynced or GobnomLogic.is_over(state):
		return {}
	var t := maxi(maxi(_clock, int(state["tick"])) + input_delay, _sent_up_to + 1)
	if do_kind == "slide":
		# Drag-Moves koaleszieren: ein slide je Seil+Tick, letzter Wert zählt.
		for pending: Dictionary in _pending_out:
			if (
				str(pending["do"]) == "slide"
				and int(pending["id"]) == id
				and int(pending["t"]) == t
			):
				pending["v"] = v
				return pending
	var action := {"t": t, "do": do_kind, "id": id}
	if not is_nan(v):
		action["v"] = v
	_pending_out.append(action)
	_enqueue(action, side)
	return action


## Nächsten Input-Frame fürs Netz abholen ({} = gerade nichts fällig).
## Frames tragen n (strikt monoton), upTo (Fence) und die Aktionen.
func take_frame(force := false) -> Dictionary:
	if state.is_empty() or desynced:
		return {}
	var target := maxi(_clock + input_delay - 1, 0)
	if not force and _pending_out.is_empty() and target - _sent_up_to < FENCE_TICKS:
		return {}
	_frame_n += 1
	var frame := {
		"n": _frame_n,
		"upTo": maxi(target, _sent_up_to),
		"a": _pending_out.duplicate(true),
	}
	_sent_up_to = int(frame["upTo"])
	_pending_out = []
	return frame


## Fällige eigene Hash-Reports abholen (Array aus {t, h}).
func take_hashes() -> Array:
	var out := _hash_out
	_hash_out = []
	return out


## Partner-Frame einspielen (aus GN_INPUT). false = alt/dupliziert.
func receive_frame(body: Dictionary) -> bool:
	var n := int(body.get("n", 0))
	if n <= _peer_frame_n:
		return false
	_peer_frame_n = n
	peer_confirmed = maxi(peer_confirmed, int(body.get("upTo", -1)))
	for raw: Variant in body.get("a", []) as Array:
		if not (raw is Dictionary):
			continue
		var action := (raw as Dictionary).duplicate()
		# Verspätete Aktionen (t schon simuliert) verletzen den Fence-Vertrag
		# — still verwerfen; eine echte Divergenz fängt der Hash-Wächter.
		if int(action.get("t", -1)) < int(state["tick"]):
			continue
		_enqueue(action, other_side())
	return true


## Partner-Hash einspielen (aus GN_HASH) → Desync-Vergleich.
func receive_hash(tick: int, hash_text: String) -> void:
	if desynced:
		return
	if _own_hashes.has(tick):
		if str(_own_hashes[tick]) != hash_text:
			_mark_desync(tick)
		return
	_peer_hashes[tick] = hash_text


## Rejoin-Replay: identischer Lauf aus Seed + komplettem Frame-Puffer beider
## Seiten (GOBNOM_SNAPSHOT.frames), vorgespult bis beide Fences es erlauben.
func resume(
	level: Dictionary,
	balance: Dictionary,
	seed_value: int,
	my_side: String,
	frames: Dictionary,
	delay := INPUT_DELAY
) -> void:
	start(level, balance, seed_value, my_side, delay)
	_quiet = true
	var own_up := -1
	for raw: Variant in frames.get(side, []) as Array:
		if not (raw is Dictionary):
			continue
		var frame: Dictionary = raw
		_frame_n = maxi(_frame_n, int(frame.get("n", 0)))
		own_up = maxi(own_up, int(frame.get("upTo", -1)))
		for entry: Variant in frame.get("a", []) as Array:
			if entry is Dictionary:
				_enqueue((entry as Dictionary).duplicate(), side)
	for raw: Variant in frames.get(other_side(), []) as Array:
		if raw is Dictionary:
			receive_frame(raw)
	_sent_up_to = own_up
	var limit := mini(own_up, peer_confirmed)
	while int(state["tick"]) <= limit and not GobnomLogic.is_over(state):
		state["events"] = []
		_apply_due()
		GobnomLogic.step(state)
		var tick := int(state["tick"])
		if tick % hash_ticks == 0:
			_record_own_hash(tick)
	_clock = maxi(int(state["tick"]), own_up - input_delay + 1)
	_quiet = false


## Pure Abfrage fürs Swipe-Schneiden: welche ungeschnittenen Seile kreuzt
## das Segment? (Wie GobnomLogic.cut_segment, aber OHNE Mutation — die
## Schnitte laufen als geplante cut-Aktionen durch den Lockstep.)
func ropes_crossed(from: Vector2, to: Vector2) -> Array[int]:
	var out: Array[int] = []
	if state.is_empty() or from.is_equal_approx(to):
		return out
	var candy := GobnomLogic.candy_pos(state)
	for rope: Dictionary in state["ropes"]:
		if bool(rope["cut"]):
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(
			from, to, Vector2(rope["anchor"]), candy
		)
		if hit != null:
			out.append(int(rope["id"]))
	return out


## ── Interne Helfer ───────────────────────────────────────────────────────


func _enqueue(action: Dictionary, from_side: String) -> void:
	var t := int(action.get("t", -1))
	if t < 0:
		return
	if not _queued.has(t):
		_queued[t] = {GobnomLogic.PLAYER_A: [], GobnomLogic.PLAYER_B: []}
	((_queued[t] as Dictionary)[from_side] as Array).append(action)


## Aktionen des anstehenden Ticks in DETERMINISTISCHER Ordnung ausführen:
## erst Seite a, dann b; innerhalb der Seite in Sende-Reihenfolge.
func _apply_due() -> void:
	var t := int(state["tick"])
	if not _queued.has(t):
		return
	var buckets: Dictionary = _queued[t]
	for player: String in [GobnomLogic.PLAYER_A, GobnomLogic.PLAYER_B]:
		for action: Dictionary in buckets[player] as Array:
			_dispatch(action, player)
	_queued.erase(t)


func _dispatch(action: Dictionary, from_side: String) -> void:
	var id := int(action.get("id", -1))
	match str(action.get("do", "")):
		"cut":
			GobnomLogic.cut_rope(state, id, from_side)
		"pop":
			GobnomLogic.pop_bubble(state, id, from_side)
		"puff":
			GobnomLogic.puff_cushion(state, id, from_side)
		"fan":
			GobnomLogic.toggle_fan(state, id, from_side)
		"slide":
			GobnomLogic.move_anchor(state, id, float(action.get("v", 0.0)), from_side)


func _record_own_hash(tick: int) -> void:
	var hash_text := str(GobnomLogic.state_hash(state))
	_own_hashes[tick] = hash_text
	_own_hashes.erase(tick - HASH_KEEP * hash_ticks)
	if not _quiet:
		_hash_out.append({"t": tick, "h": hash_text})
	if _peer_hashes.has(tick):
		if str(_peer_hashes[tick]) != hash_text:
			_mark_desync(tick)
		_peer_hashes.erase(tick)


func _mark_desync(tick: int) -> void:
	desynced = true
	desync_tick = tick
