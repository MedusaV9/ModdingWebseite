class_name GvzPvpLockstep
extends RefCounted
## PURER Lockstep-Kern des GvZ-PvP übers Netz (G5/P26, Doc G §4.5 — Vorlage
## GobnomLockstep/W15): beide Clients simulieren GvzLogic identisch aus
## Server-Seed + Input-Strom — getauscht werden NUR Aktionen ({t, do, …}).
## Die TABU-Sim wird ausschließlich AUFGERUFEN: Gooby-Seite plant
## place/shovel/collect (GvzLogic-Aktionsfunktionen), die Zombie-Seite
## beschwört über den vorhandenen Hook GvzZombies.spawn(). Die PvP-Ökonomie
## (Matsch-Tropf + Eskalation, Kosten/Cooldowns je Zombie-Typ) und der
## Überlebens-Timer leben HIER und kommen aus data/gvz_pvp.json.
##
## Standard-Lockstep mit Input-Delay-Fenster (3–5 Ticks, C §3.8): lokale
## Aktionen laufen auf BEIDEN Geräten exakt bei Tick `jetzt + INPUT_DELAY`.
## Fences („meine Inputs bis Tick X sind vollständig“ = upTo) fließen
## wandzeit-getrieben über `_clock`; die Sim schreitet nur, solange der
## Partner den Tick bestätigt hat (peer_confirmed).
##
## Desync-Wächter: alle HASH_TICKS Ticks wird state_hash_text() verglichen
## (GvzLogic.state_hash + Matsch/Cooldowns/Winner) — bei Abweichung wird
## `desynced` gesetzt und die View bricht höflich ab (Toast).
## Node-frei und ohne Transport: die View verschickt take_frame()/
## take_hashes() über GvzNetSession und füttert receive_*() zurück.

const SIDE_GOOBY := "gooby"
const SIDE_ZOMBIE := "zombie"

## Vertrags-Defaults — der Server schickt dieselben Werte im GVZ_START.
const INPUT_DELAY := 4
const FENCE_TICKS := 6
const HASH_TICKS := 60
## Nur die letzten N eigenen Hashes vorhalten (Speicher-Deckel).
const HASH_KEEP := 10

var state: Dictionary = {}
var side := SIDE_GOOBY
var input_delay := INPUT_DELAY
var hash_ticks := HASH_TICKS
## PvP-Ressource der Zombie-Seite (Doc G §4.5) — Teil des Drift-Hashes.
var matsch := 0
## Zombie-Typ → Tick, ab dem er wieder beschworen werden darf.
var zombie_cooldowns: Dictionary = {}
## Gooby-Sieg-Timer in Ticks (match.gooby_survive_sec × ticks_per_second).
var survive_ticks := 4200
## "" solange das Match läuft, sonst SIDE_GOOBY | SIDE_ZOMBIE.
var winner := ""
## Bis zu welchem Tick (inklusive) der Partner Inputs bestätigt hat.
var peer_confirmed := -1
var desynced := false
var desync_tick := -1

var _pvp: Dictionary = {}
## Wandzeit-Ticks der View (läuft auch beim Warten weiter — Fence-Motor).
var _clock := 0
var _sent_up_to := -100
var _frame_n := 0
var _peer_frame_n := 0
## tick -> {"gooby": Array, "zombie": Array} — geplante Aktionen.
var _queued: Dictionary = {}
## Lokale Aktionen, die der nächste Frame mitnimmt.
var _pending_out: Array = []
var _own_hashes: Dictionary = {}
var _peer_hashes: Dictionary = {}
var _hash_out: Array = []


## PvP-Regeln aus data/gvz_pvp.json (JSON-Zahlen bleiben float — alle
## Leser hier int()en explizit, damit der Determinismus hält).
static func load_pvp() -> Dictionary:
	return GvzData.read_json(GvzData.PVP_PATH)


## PvP-Arena: alle 5 Reihen, alle Standard-Türme frei (kein Code-Gate),
## KEINE geskripteten Wellen/Bosse. Der Wächter-Spawn in ferner Zukunft
## hält GvzLogic._check_outcome offen (ein leerer Spawn-Plan hieße
## Sofort-Sieg im ersten Tick) — das Match endet vorher deterministisch
## über den Überlebens-Timer bzw. den Haus-Durchbruch.
static func arena_level(balance: Dictionary) -> Dictionary:
	var towers: Array = []
	for type: Variant in balance.get("towers", {}):
		if not bool(balance["towers"][type].get("code_gate", false)):
			towers.append(str(type))
	return {
		"id": 0,
		"lanes": [0, 1, 2, 3, 4],
		"unlock_towers": towers,
		"spawns": [{"t": 999000.0, "lane": 0, "type": "schlurfi"}],
		"waves": [],
		"mods": {},
	}


## Frischer Netz-Lauf: Balance/PvP-Regeln wie lokal, Seed VOM SERVER.
## Schwierigkeit ist im PvP IMMER "normal" (Fairness beider Seiten).
func start(
	balance: Dictionary, pvp: Dictionary, seed_value: int, my_side: String, delay := INPUT_DELAY
) -> void:
	_pvp = pvp
	state = GvzLogic.new_run(arena_level(balance), balance, "normal", seed_value)
	# Doc G §4.5: „Dampfwalzen aus im PvP“ — als bereits verbraucht markieren
	# (identische Setup-Mutation auf beiden Geräten, Sim-Regeln unberührt).
	if not bool(pvp.get("match", {}).get("mowers_enabled", false)):
		for lane: Variant in state["mowers"]:
			state["mowers"][lane]["used"] = true
	side = my_side
	input_delay = delay
	matsch = int(pvp.get("matsch", {}).get("start", 0))
	zombie_cooldowns = {}
	survive_ticks = int(pvp.get("match", {}).get("gooby_survive_sec", 210)) * _tps()
	winner = ""
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
	return SIDE_ZOMBIE if side == SIDE_GOOBY else SIDE_GOOBY


func is_match_over() -> bool:
	return winner != ""


## Darf die Sim den nächsten Tick rechnen? (Partner-Fence liegt vor.)
func can_step() -> bool:
	if state.is_empty() or desynced or is_match_over():
		return false
	return peer_confirmed >= int(state["tick"])


## Ein Wandzeit-Tick der View: plant Fences und rechnet — wenn erlaubt —
## genau einen Sim-Tick. {stepped: bool, events: Array}; stepped=false
## heißt „auf Partner warten“ (die View zeigt dann den Warte-Hinweis).
func advance() -> Dictionary:
	if state.is_empty() or desynced or is_match_over():
		return {"stepped": false, "events": []}
	_clock += 1
	if not can_step():
		return {"stepped": false, "events": []}
	state["events"] = []
	_apply_due()
	var action_events: Array = (state["events"] as Array).duplicate()
	var step_events := GvzLogic.tick(state)
	var events := action_events + step_events
	_matsch_tick()
	_check_winner()
	var tick := int(state["tick"])
	if tick % hash_ticks == 0:
		_record_own_hash(tick)
	return {"stepped": true, "events": events}


## ── Aktionen planen (laufen deterministisch bei Tick t auf BEIDEN Sims;
## die Sim-Gates entscheiden erst bei der Ausführung) ─────────────────────


func schedule_place(type: String, lane: int, col: int) -> Dictionary:
	return _schedule({"do": "place", "type": type, "lane": lane, "col": col})


func schedule_shovel(lane: int, col: int) -> Dictionary:
	return _schedule({"do": "shovel", "lane": lane, "col": col})


func schedule_collect(drop_id: int) -> Dictionary:
	return _schedule({"do": "collect", "id": drop_id})


func schedule_spawn(type: String, lane: int) -> Dictionary:
	return _schedule({"do": "spawn", "type": type, "lane": lane})


## ── Zombie-Seite: Matsch-Kosten/Cooldowns (Doc G §4.5, gvz_pvp.json) ──────


## Beschwörbare Zombie-Typen in Daten-Reihenfolge (leichte zuerst).
func zombie_types() -> Array:
	var out: Array = []
	for type: Variant in _pvp.get("zombie_costs", {}):
		out.append(str(type))
	return out


func zombie_cost(type: String) -> int:
	return int((_pvp.get("zombie_costs", {}) as Dictionary).get(type, 0))


func zombie_cooldown_ticks(type: String) -> int:
	return int((_pvp.get("zombie_cooldown_ticks", {}) as Dictionary).get(type, 0))


## Verbleibende Beschwör-Abklingzeit in Ticks (0 = bereit).
func zombie_cooldown_left(type: String) -> int:
	var ready := int(zombie_cooldowns.get(type, 0))
	return maxi(0, ready - int(state["tick"]))


## Beschwör-Prüfung OHNE Seiteneffekte: {ok, reason}.
## reason: outcome|unknown_zombie|lane|cooldown|matsch.
func can_spawn(type: String, lane: int) -> Dictionary:
	if state.is_empty() or is_match_over():
		return {"ok": false, "reason": "outcome"}
	if not (_pvp.get("zombie_costs", {}) as Dictionary).has(type):
		return {"ok": false, "reason": "unknown_zombie"}
	if not (state["lanes"] as Array).has(lane):
		return {"ok": false, "reason": "lane"}
	if zombie_cooldown_left(type) > 0:
		return {"ok": false, "reason": "cooldown"}
	if matsch < zombie_cost(type):
		return {"ok": false, "reason": "matsch"}
	return {"ok": true, "reason": ""}


## Verbleibende Match-Zeit in Sekunden (Gooby-Sieg bei 0).
func seconds_left() -> int:
	if state.is_empty():
		return 0
	return maxi(0, _idiv(survive_ticks - int(state["tick"]) + _tps() - 1, _tps()))


## ── Netz-Kanäle (Frames/Hashes — exakt das GOB-NOM-Muster) ────────────────


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


## Partner-Frame einspielen (aus GP_INPUT). false = alt/dupliziert.
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


## Partner-Hash einspielen (aus GP_HASH) → Desync-Vergleich.
func receive_hash(tick: int, hash_text: String) -> void:
	if desynced:
		return
	if _own_hashes.has(tick):
		if str(_own_hashes[tick]) != hash_text:
			_mark_desync(tick)
		return
	_peer_hashes[tick] = hash_text


## Drift-Hash des kompletten Match-Zustands: Sim-Hash (GvzLogic, PvP-safe)
## + Matsch + Zombie-Cooldowns + Winner (alles deterministisch).
func state_hash_text() -> String:
	return (
		"%d|%d|%s|%s" % [GvzLogic.state_hash(state), matsch, var_to_str(zombie_cooldowns), winner]
	)


## ── Interne Helfer ───────────────────────────────────────────────────────


func _schedule(action: Dictionary) -> Dictionary:
	if state.is_empty() or desynced or is_match_over():
		return {}
	action["t"] = maxi(maxi(_clock, int(state["tick"])) + input_delay, _sent_up_to + 1)
	_pending_out.append(action)
	_enqueue(action, side)
	return action


func _enqueue(action: Dictionary, from_side: String) -> void:
	var t := int(action.get("t", -1))
	if t < 0:
		return
	if not _queued.has(t):
		_queued[t] = {SIDE_GOOBY: [], SIDE_ZOMBIE: []}
	((_queued[t] as Dictionary)[from_side] as Array).append(action)


## Aktionen des anstehenden Ticks in DETERMINISTISCHER Ordnung ausführen:
## erst Gooby-Seite, dann Zombie-Seite; innerhalb in Sende-Reihenfolge.
func _apply_due() -> void:
	var t := int(state["tick"])
	if not _queued.has(t):
		return
	var buckets: Dictionary = _queued[t]
	for player: String in [SIDE_GOOBY, SIDE_ZOMBIE]:
		for action: Dictionary in buckets[player] as Array:
			_dispatch(action, player)
	_queued.erase(t)


## Seiten-Gate im Dispatch: fremdseitige Aktionen werden still verworfen —
## deterministisch identisch auf beiden Geräten.
func _dispatch(action: Dictionary, from_side: String) -> void:
	match str(action.get("do", "")):
		"place":
			if from_side == SIDE_GOOBY:
				GvzLogic.place_tower(
					state,
					str(action.get("type", "")),
					int(action.get("lane", -1)),
					int(action.get("col", -1))
				)
		"shovel":
			if from_side == SIDE_GOOBY:
				GvzLogic.remove_tower(
					state, int(action.get("lane", -1)), int(action.get("col", -1))
				)
		"collect":
			if from_side == SIDE_GOOBY:
				GvzLogic.collect_drop(state, int(action.get("id", -1)))
		"spawn":
			if from_side == SIDE_ZOMBIE:
				_spawn_zombie(str(action.get("type", "")), int(action.get("lane", -1)))


func _spawn_zombie(type: String, lane: int) -> void:
	if not bool(can_spawn(type, lane)["ok"]):
		return
	matsch -= zombie_cost(type)
	zombie_cooldowns[type] = int(state["tick"]) + zombie_cooldown_ticks(type)
	GvzZombies.spawn(state, type, lane, GvzLogic.SPAWN_X)


## Matsch-Tropf (Doc G §4.5): 15 alle 10 s, alle 45 s +5 Eskalation —
## rein tick-basiert, damit beide Sims dieselben Beträge buchen.
func _matsch_tick() -> void:
	var rules: Dictionary = _pvp.get("matsch", {})
	var interval := maxi(1, int(rules.get("drip_interval_sec", 10)) * _tps())
	var tick := int(state["tick"])
	if tick % interval != 0:
		return
	var esc_interval := maxi(1, int(rules.get("escalation_interval_sec", 45)) * _tps())
	matsch += int(rules.get("drip_amount", 15))
	matsch += int(rules.get("escalation_bonus", 5)) * _idiv(tick, esc_interval)


## Sieg-Check nach jedem Tick: Haus-Durchbruch (Sim-outcome "lost") =
## Zombie-Sieg; Timer abgelaufen = Gooby-Sieg. Das Sim-"won" kann dank
## Wächter-Spawn regulär nicht eintreten — sicherheitshalber Gooby-Sieg.
func _check_winner() -> void:
	if winner != "":
		return
	if str(state["outcome"]) == "lost":
		winner = SIDE_ZOMBIE
	elif str(state["outcome"]) == "won" or int(state["tick"]) >= survive_ticks:
		winner = SIDE_GOOBY


func _record_own_hash(tick: int) -> void:
	var hash_text := state_hash_text()
	_own_hashes[tick] = hash_text
	_own_hashes.erase(tick - HASH_KEEP * hash_ticks)
	_hash_out.append({"t": tick, "h": hash_text})
	if _peer_hashes.has(tick):
		if str(_peer_hashes[tick]) != hash_text:
			_mark_desync(tick)
		_peer_hashes.erase(tick)


func _mark_desync(tick: int) -> void:
	desynced = true
	desync_tick = tick


func _tps() -> int:
	return int(state["balance"].get("ticks_per_second", 20))


@warning_ignore("integer_division")
func _idiv(a: int, b: int) -> int:
	return a / b
