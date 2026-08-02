class_name AudioDirector
extends Node
## Zentraler Sound-Fahrer (W4-P1, Autoload-Request "Audio" — s.
## handoffs/project-godot-requests.md). Bis der Orchestrator ihn einträgt,
## hängt get_or_create() den Knoten lazy unter /root — beide Wege liefern
## DENSELBEN Zustand (Muster W3c SocialServices).
##
## Aufgaben:
## - Busse Master/Music/Sfx/Voice anlegen (fehlende werden ergänzt, nie
##   dupliziert) und ihre Lautstärke aus AppSettings (audio.master/music/
##   sfx/voice, 0..1) setzen — live via setting_changed.
## - play(id): One-Shot-SFX über die SfxMap (Pool aus AudioStreamPlayern
##   auf dem Sfx-Bus, Streams gecacht, Frame-Debounce gegen Doppel-Plops).
## Headless-sicher: ohne Audio-Device spielt der Dummy-Treiber still.

## Busname → AppSettings-Key unter "audio." (Master heißt im Setting master).
const BUS_SETTINGS := {"Master": "master", "Music": "music", "Sfx": "sfx", "Voice": "voice"}
## Fester Mix-Offset je Bus, ZUSÄTZLICH zum Nutzer-Regler (EVAL-1 S1):
## Musik sitzt nach AC-Referenz 6–10 dB UNTER den Interaktions-Sounds.
## Die Musikdateien sind auf −20 dBFS gemastert (music_registry.gd, in der
## EVAL1-Messmetrik −17); der SFX-Median liegt bei ~−22,6 — der Bus legt
## die Musik mit −13 dB auf ~7,4 dB unter die Effekte (Regler 1.0 Default).
## tests/unit/test_ef2_audio_levels.gd wacht über das Verhältnis.
const BUS_BASE_DB := {"Music": -13.0}
## Master-Limiter (EVAL-1 S1): nichts über −1 dBFS, egal was sich stapelt.
const LIMITER_CEILING_DB := -1.0
const NODE_NAME := "AudioDirector"
const POOL_SIZE := 10
## Gleiche Id innerhalb dieses Fensters nur einmal spielen (GvZ-Pop-Cluster).
const DEBOUNCE_MSEC := 45

## Duplikat-Schutz für get_or_create: das deferred add_child ist erst einen
## Frame später sichtbar, mehrere Aufrufe im selben Frame teilen diese Instanz.
static var _fallback: AudioDirector

var _pool: Array[AudioStreamPlayer] = []
var _pool_next := 0
var _streams: Dictionary = {}
var _last_played_msec: Dictionary = {}
var _warned_ids: Dictionary = {}
var _loop_players: Dictionary = {}
var _rng := RandomNumberGenerator.new()


## Bequemer One-Liner für Verdrahtungen: spielt id, wenn ein Baum da ist —
## sonst still no-op (Unit-Tests mit freien Nodes, allererster Frame).
static func try_play(from: Node, id: String, pitch := 1.0) -> void:
	if from == null or not from.is_inside_tree():
		return
	var director := get_or_create(from)
	if director.is_inside_tree():
		director.play(id, pitch)


## Dauer-Loop starten/stoppen (Wasser-/Bürsten-Foley, EVAL-1 F7) — Muster
## wie try_play: ohne Baum still no-op.
static func try_start_loop(from: Node, id: String) -> void:
	if from == null or not from.is_inside_tree():
		return
	var director := get_or_create(from)
	if director.is_inside_tree():
		director.start_loop(id)


static func try_stop_loop(from: Node, id: String) -> void:
	if from == null or not from.is_inside_tree():
		return
	var director := get_or_create(from)
	if director.is_inside_tree():
		director.stop_loop(id)


## Autoload /root/Audio bevorzugt, sonst lazy-Instanz unter /root.
static func get_or_create(from: Node) -> AudioDirector:
	var autoload := from.get_node_or_null("/root/Audio")
	if autoload is AudioDirector:
		return autoload
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is AudioDirector:
		return existing
	if _fallback != null and is_instance_valid(_fallback):
		return _fallback
	var node := AudioDirector.new()
	node.name = NODE_NAME
	_fallback = node
	from.get_tree().root.add_child.call_deferred(node)
	return node


func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	_apply_all_volumes()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"Sfx"
		add_child(player)
		_pool.append(player)
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_signal("setting_changed"):
		settings.setting_changed.connect(_on_setting_changed)
	_ensure_raum_klang()


## G6-FEEL: Orts-Raumgefühl (Reverb-Zonen auf dem Sfx-Bus) fährt als Kind
## mit — so existiert sein Router-Lauscher ab Boot (s. raum_klang.gd).
func _ensure_raum_klang() -> void:
	if get_node_or_null(RaumKlang.NODE_NAME) != null:
		return
	var raum := RaumKlang.new()
	raum.name = RaumKlang.NODE_NAME
	add_child(raum)


## One-Shot-SFX nach SfxMap-Id; unbekannte Id warnt einmalig und ist no-op.
func play(id: String, pitch := 1.0) -> void:
	if _pool.is_empty():
		return
	var row := SfxMap.entry(id)
	if row.is_empty():
		if not _warned_ids.has(id):
			_warned_ids[id] = true
			push_warning("[audio] unbekannte SFX-Id '%s' (s. sfx_map.gd)" % id)
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played_msec.get(id, -DEBOUNCE_MSEC)) < DEBOUNCE_MSEC:
		return
	_last_played_msec[id] = now
	var stream := _stream_for(id, row)
	if stream == null:
		return
	var player := _next_player()
	player.stream = stream
	player.volume_db = float(row.get("volume_db", 0.0))
	var jitter := float(row.get("pitch_jitter", 0.0))
	player.pitch_scale = maxf(0.05, pitch + _rng.randf_range(-jitter, jitter))
	player.play()


## Geloopten Foley-Sound starten (care_wasser/care_buersten). Ein zweiter
## Aufruf derselben Id ist no-op; stop_loop(id) blendet weich aus. Der
## Stream wird dupliziert, damit der One-Shot-Cache loop-frei bleibt.
func start_loop(id: String) -> void:
	if _loop_players.has(id):
		return
	var row := SfxMap.entry(id)
	if row.is_empty():
		if not _warned_ids.has(id):
			_warned_ids[id] = true
			push_warning("[audio] unbekannte SFX-Id '%s' (s. sfx_map.gd)" % id)
		return
	var stream := _stream_for(id, row)
	if stream == null:
		return
	var looped: AudioStream = stream.duplicate()
	if looped is AudioStreamOggVorbis:
		(looped as AudioStreamOggVorbis).loop = true
	elif looped is AudioStreamWAV:
		(looped as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var player := AudioStreamPlayer.new()
	player.bus = &"Sfx"
	player.stream = looped
	player.volume_db = float(row.get("volume_db", 0.0))
	add_child(player)
	player.play()
	_loop_players[id] = player


## Loop weich beenden (150-ms-Fade gegen Abschalt-Klick).
func stop_loop(id: String) -> void:
	var player: AudioStreamPlayer = _loop_players.get(id)
	if player == null:
		return
	_loop_players.erase(id)
	if not is_inside_tree():
		player.queue_free()
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(player, "volume_db", -40.0, 0.15)
	tween.tween_callback(player.queue_free)


func is_loop_playing(id: String) -> bool:
	return _loop_players.has(id)


## Lautstärke eines Busses live nachziehen (0..1, 0 = mute). Der feste
## Mix-Offset aus BUS_BASE_DB kommt IMMER obendrauf — der Regler steuert
## also relativ zur eingemessenen Mix-Balance.
func apply_volume(bus_name: String, level: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var clamped := clampf(level, 0.0, 1.0)
	var base_db := float(BUS_BASE_DB.get(bus_name, 0.0))
	AudioServer.set_bus_mute(idx, clamped <= 0.0)
	AudioServer.set_bus_volume_db(idx, base_db + linear_to_db(maxf(clamped, 0.0001)))


func _ensure_buses() -> void:
	for bus_name: String in BUS_SETTINGS:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	_ensure_master_limiter()


## Brickwall auf dem Master (EVAL-1 S1): 37 Tracks clippten früher nach
## gain_trim; die Dateien sind jetzt zwar gemastert, aber Stapel-Momente
## (Fanfare + Konfetti + Musik) sollen physikalisch nie über −1 dBFS.
func _ensure_master_limiter() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = LIMITER_CEILING_DB
	AudioServer.add_bus_effect(idx, limiter)


func _apply_all_volumes() -> void:
	for bus_name: String in BUS_SETTINGS:
		apply_volume(bus_name, _settings_level(str(BUS_SETTINGS[bus_name])))


func _settings_level(key: String) -> float:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("audio_level"):
		return settings.audio_level(key)
	return 1.0


func _on_setting_changed(key: String, value: Variant) -> void:
	if not key.begins_with("audio."):
		return
	var setting := key.trim_prefix("audio.")
	for bus_name: String in BUS_SETTINGS:
		if str(BUS_SETTINGS[bus_name]) == setting:
			apply_volume(bus_name, float(value))


## Pfad kommt aus SfxMap.path() — die Ranch-Familie (RW-8) nutzt absolute
## res://-Einträge, alle anderen hängen wie bisher an BASE_DIR.
func _stream_for(id: String, _row: Dictionary) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var path := SfxMap.path(id)
	if not ResourceLoader.exists(path):
		if not _warned_ids.has(id):
			_warned_ids[id] = true
			push_warning("[audio] SFX-Datei fehlt: %s" % path)
		return null
	var stream: AudioStream = load(path)
	_streams[id] = stream
	return stream


## Round-Robin über den Pool; sind alle beschäftigt, wird der älteste geklaut.
func _next_player() -> AudioStreamPlayer:
	for _i in _pool.size():
		var candidate := _pool[_pool_next]
		_pool_next = (_pool_next + 1) % _pool.size()
		if not candidate.playing:
			return candidate
	var stolen := _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	return stolen
