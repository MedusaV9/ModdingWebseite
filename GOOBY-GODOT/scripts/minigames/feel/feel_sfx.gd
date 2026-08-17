class_name FeelSfx
extends Node
## Game-Feel-Soundkarte der Minispiele (POLISH-A): semantische Feel-Id →
## OGG unter assets/audio/sfx/game/ (weiche numpy-Synth-Plucks im Stil der
## soft/-UI-Familie — kein harter Klick). Eigene Karte statt SfxMap, damit
## die zentrale UI-Landkarte (Owner: Audio-Agent) unberührt bleibt.
##
## Spielweg: FeelSfx.play(node, id, pitch) — spielt über einen kleinen
## eigenen Player-Pool auf dem Sfx-Bus (Lautstärke folgt damit den
## AppSettings wie bei AudioDirector). combo_pitch(streak) ist DIE eine
## Tonhöhen-Treppe für Serien: +1 Halbton pro Combo-Stufe, bei +12 gedeckelt.

const BASE_DIR := "res://assets/audio/sfx/game"
const NODE_NAME := "FeelSfxPlayer"
const POOL_SIZE := 8
## Gleiche Id innerhalb dieses Fensters nur einmal (Cluster-Schutz).
const DEBOUNCE_MSEC := 40
## Combo-Treppe: Halbtonschritte, Deckel bei einer Oktave (+12).
const COMBO_SEMITONE_CAP := 12

## id → {file, volume_db (Default 0.0)}. Pflicht-Kontrakt für alle
## Minispiele: Treffer, Fehler, Combo, Countdown, Sieg und Niederlage
## MÜSSEN eine Id haben (test_feel_sfx.gd prüft Existenz + Dateien).
const SOUNDS := {
	"game_hit": {"file": "game_hit.ogg", "volume_db": -5.0},
	"game_pop": {"file": "game_pop.ogg", "volume_db": -6.0},
	"game_miss": {"file": "game_miss.ogg", "volume_db": -5.0},
	"game_combo": {"file": "game_combo.ogg", "volume_db": -4.0},
	"game_count": {"file": "game_count.ogg", "volume_db": -9.0},
	"game_countdown": {"file": "game_countdown.ogg", "volume_db": -5.0},
	"game_go": {"file": "game_go.ogg", "volume_db": -3.0},
	"game_win": {"file": "game_win.ogg", "volume_db": -3.0},
	"game_lose": {"file": "game_lose.ogg", "volume_db": -5.0},
	"game_star": {"file": "game_star.ogg", "volume_db": -4.0},
	"game_record": {"file": "game_record.ogg", "volume_db": -3.0},
	"game_coin": {"file": "game_coin.ogg", "volume_db": -7.0},
	"game_whoosh": {"file": "game_whoosh.ogg", "volume_db": -9.0},
	"game_perfect": {"file": "game_perfect.ogg", "volume_db": -4.0},
}

## Die sechs Pflicht-Momente (Doku + test_feel_sfx-Kontrakt).
const REQUIRED_MOMENT_IDS: Array[String] = [
	"game_hit",
	"game_miss",
	"game_combo",
	"game_countdown",
	"game_win",
	"game_lose",
]

static var _shared: FeelSfx

var _pool: Array[AudioStreamPlayer] = []
var _pool_next := 0
var _streams: Dictionary = {}
var _last_played_msec: Dictionary = {}


## One-Shot nach Feel-Id; ohne Baum/im Headless-Dummy still no-op.
static func play(from: Node, id: String, pitch := 1.0) -> void:
	if from == null or not from.is_inside_tree():
		return
	var node := _get_or_create(from)
	if node.is_inside_tree():
		node.play_id(id, pitch)


## DIE Tonhöhen-Treppe für Serien: Stufe 1 = Grundton, danach +1 Halbton
## pro Stufe (musikalisch chromatisch aufwärts), Deckel bei +12 (Oktave).
static func combo_pitch(streak: int) -> float:
	var steps := clampi(streak - 1, 0, COMBO_SEMITONE_CAP)
	return pow(2.0, float(steps) / 12.0)


## Ressourcen-Pfad zu einer Id ("" = unbekannt) — für Tests/Preload.
static func path(id: String) -> String:
	var row: Dictionary = SOUNDS.get(id, {})
	if row.is_empty():
		return ""
	return "%s/%s" % [BASE_DIR, row["file"]]


static func ids() -> Array:
	return SOUNDS.keys()


static func _get_or_create(from: Node) -> FeelSfx:
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is FeelSfx:
		return existing
	if _shared != null and is_instance_valid(_shared):
		return _shared
	var node := FeelSfx.new()
	node.name = NODE_NAME
	_shared = node
	from.get_tree().root.add_child.call_deferred(node)
	return node


func _ready() -> void:
	for _i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		# Über den Sfx-Bus (existiert er noch nicht, legt AudioDirector ihn
		# an; bis dahin fällt Godot lautlos auf Master zurück).
		player.bus = &"Sfx"
		add_child(player)
		_pool.append(player)


func play_id(id: String, pitch := 1.0) -> void:
	if _pool.is_empty():
		return
	var row: Dictionary = SOUNDS.get(id, {})
	if row.is_empty():
		push_warning("[feel_sfx] unbekannte Feel-Id '%s'" % id)
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played_msec.get(id, -DEBOUNCE_MSEC)) < DEBOUNCE_MSEC:
		return
	_last_played_msec[id] = now
	var stream := _stream_for(id)
	if stream == null:
		return
	var player := _next_player()
	player.stream = stream
	player.volume_db = float(row.get("volume_db", 0.0))
	player.pitch_scale = maxf(0.05, pitch)
	player.play()


func _stream_for(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var res_path := FeelSfx.path(id)
	if not ResourceLoader.exists(res_path):
		push_warning("[feel_sfx] Datei fehlt: %s" % res_path)
		return null
	var stream: AudioStream = load(res_path)
	_streams[id] = stream
	return stream


func _next_player() -> AudioStreamPlayer:
	for _i in _pool.size():
		var candidate := _pool[_pool_next]
		_pool_next = (_pool_next + 1) % _pool.size()
		if not candidate.playing:
			return candidate
	var stolen := _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	return stolen
