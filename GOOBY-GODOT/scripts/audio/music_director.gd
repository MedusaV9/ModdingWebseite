class_name MusicDirector
extends Node
## Zentraler Musik-Fahrer (FIX-4) — Port des Web-musicDirector/radioPlayer:
## spielt die ECHTEN generierten Tracks (MusicRegistry) pro Szenen-Kontext mit
## weichem Crossfade (1,5 s) auf dem Music-Bus. Autoload-Wunsch "Music"
## (s. handoffs/project-godot-requests.md); bis dahin hängt get_or_create()
## den Knoten lazy unter /root — Muster AudioDirector.
##
## - set_context("home"|"city"|"arcade"|"game:<id>"|...) → Registry-Track,
##   Crossfade; unbekannte Spiel-Kontexte fallen auf "arcade" zurück.
## - push_context/pop_context: Overlay-Stapel (Shop-Panel über dem Raum).
## - radio_play(station): Radio-Modus ERSETZT die Kontext-Musik (Web
##   replaceContext) — geshuffelte Sender-Queue, Level-Schranken respektiert,
##   radio_stop() blendet zurück in den Szenen-Kontext.
## - play_stinger("stinger-levelup"): One-Shot über die laufende Musik.
## Hängt sich selbst an SceneRouter.travel_finished (ROUTE_CONTEXTS) — Räume
## brauchen KEINE eigene Verdrahtung. Headless-sicher (Dummy-Treiber spielt
## still, Tweens degradieren zu Sofort-Sprüngen ohne Baum).

signal track_changed(track_id: String)
signal station_changed(station_id: String)

## Weicher Übergang zwischen Kontext-Tracks (User-Wunsch ~1,5 s).
const CROSSFADE_S := 1.5
## Radio an/aus blendet schneller (Web 0.4 s).
const RADIO_FADE_S := 0.4
const FADE_OUT_DB := -40.0
## Stinger sind Belohnungs-One-Shots und sollen ÜBER dem Musikbett sitzen:
## Der Music-Bus liegt fix −10 dB unter den Effekten (AudioDirector
## BUS_BASE_DB), die Stinger-Dateien sind auf −17 dBFS gemastert — der
## Boost hebt sie in die Nähe der SFX-Ebene (eff. ≈ −21 dBFS), Peaks
## bleiben dank Datei-Headroom + Master-Limiter unter −1 dBFS.
const STINGER_BOOST_DB := 6.0
const NODE_NAME := "MusicDirector"

## SceneRouter-Ziel → Musik-Kontext. mg_host wird dynamisch aufgelöst
## (game_id der Szene); city/ort/* fällt auf "city" zurück.
const ROUTE_CONTEXTS := {
	"home/living": "home",
	"home/kitchen": "room:kitchen",
	"home/bathroom": "room:bathroom",
	"home/bedroom": "room:bedroom",
	"home/garden": "garden",
	"city": "city",
	"city/ort/rehwei": "shop",
	"city/ort/goobytheke": "vet",
	"city/ort/flughafen": "vacation",
	"ikea": "shop",
	"arcade": "arcade",
	"mg_pregame": "arcade",
}

static var _fallback: MusicDirector

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _streams: Dictionary = {}
var _base_context := ""
var _overlays: Array[String] = []
var _current_track := ""
var _radio_station := ""
var _radio_queue: Array[String] = []
var _radio_pos := 0
var _stinger_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


## Autoload /root/Music bevorzugt, sonst lazy-Instanz unter /root.
static func get_or_create(from: Node) -> MusicDirector:
	var autoload := from.get_node_or_null("/root/Music")
	if autoload is MusicDirector:
		return autoload
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is MusicDirector:
		return existing
	if _fallback != null and is_instance_valid(_fallback):
		return _fallback
	var node := MusicDirector.new()
	node.name = NODE_NAME
	_fallback = node
	from.get_tree().root.add_child.call_deferred(node)
	return node


## Bequemer One-Liner: Kontext setzen, wenn ein Baum da ist — sonst no-op.
static func try_context(from: Node, context: String) -> void:
	if from == null or not from.is_inside_tree():
		return
	get_or_create(from).set_context(context)


func _ready() -> void:
	_rng.randomize()
	_ensure_music_bus()
	for _i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = &"Music"
		add_child(player)
		_players.append(player)
	_stinger_player = AudioStreamPlayer.new()
	_stinger_player.bus = &"Music"
	add_child(_stinger_player)
	for player in _players:
		player.finished.connect(_on_player_finished)
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)


# ── Kontext-Musik ─────────────────────────────────────────────────────────────


## Szenen-Basis-Kontext setzen ("" stoppt die Musik). Läuft das Radio,
## wird nur der Wunsch gemerkt (Radio ersetzt Kontext-Musik).
func set_context(context: String) -> void:
	_base_context = context
	_apply()


## Overlay-Kontext (Panel/Screen über der Szene) — pop stellt zurück.
func push_context(context: String) -> void:
	_overlays.append(context)
	_apply()


func pop_context(context: String) -> void:
	var idx := _overlays.rfind(context)
	if idx >= 0:
		_overlays.remove_at(idx)
	_apply()


## Der Kontext, der gerade klingen SOLL (Overlay vor Basis; "" = keiner).
func active_context() -> String:
	if not _overlays.is_empty():
		return _overlays[_overlays.size() - 1]
	return _base_context


func current_track_id() -> String:
	return _current_track


## Kontext → Track-Id inkl. Fallbacks (pur, testbar): unbekannte
## "game:"-Kontexte klingen nach Arcade, Schlafzimmer nach Schlaf-Variante.
func resolve_track(context: String, sleeping := false) -> String:
	if context.is_empty():
		return ""
	var track := MusicRegistry.track_for(context, sleeping)
	if track.is_empty() and context.begins_with("game:"):
		track = MusicRegistry.track_for("arcade")
	return track


## Musik ganz ausblenden (z. B. Cutscene-Stille).
func stop_music(fade_s := CROSSFADE_S) -> void:
	_base_context = ""
	_overlays.clear()
	_crossfade_to("", fade_s)


## Direkt einen bestimmten Track spielen (Cutscenes/Recap) — verlässt den
## Kontext-Modus, bis wieder set_context()/radio_play() gerufen wird.
func play_track(track_id: String, fade_s := CROSSFADE_S, loop := true) -> void:
	_base_context = ""
	_overlays.clear()
	_crossfade_to(track_id, fade_s, loop)


# ── Radio (Sender-Queue, ersetzt Kontext-Musik) ──────────────────────────────


## Sender abspielen: geshuffelte Queue, Level-Schranken respektiert.
func radio_play(station_id: String) -> void:
	var queue := radio_queue_for(station_id, _player_level())
	if queue.is_empty():
		push_warning("[music] Sender '%s' hat keine freigeschalteten Tracks." % station_id)
		return
	_radio_station = station_id
	_radio_queue = []
	for track_id in queue:
		_radio_queue.append(track_id)
	_shuffle(_radio_queue)
	_radio_pos = 0
	station_changed.emit(station_id)
	_crossfade_to(_radio_queue[0], RADIO_FADE_S, false)


func radio_stop() -> void:
	if _radio_station.is_empty():
		return
	_radio_station = ""
	_radio_queue.clear()
	station_changed.emit("")
	_apply()


func radio_next() -> void:
	if _radio_station.is_empty() or _radio_queue.is_empty():
		return
	_radio_pos = (_radio_pos + 1) % _radio_queue.size()
	_crossfade_to(_radio_queue[_radio_pos], RADIO_FADE_S, false)


func radio_station() -> String:
	return _radio_station


func is_radio_playing() -> bool:
	return not _radio_station.is_empty()


## Abspielbare Sender-Tracks für ein Spieler-Level (pur, testbar).
static func radio_queue_for(station_id: String, level: int) -> Array:
	var out: Array = []
	for track_id: String in MusicRegistry.station_track_ids(station_id):
		if int(MusicRegistry.entry(track_id).get("unlock_level", 1)) <= level:
			out.append(track_id)
	return out


# ── Stinger ───────────────────────────────────────────────────────────────────


## One-Shot-Stinger (Level-Up/Results) ÜBER der laufenden Musik.
func play_stinger(track_id: String) -> void:
	var stream := _stream_for(track_id)
	if stream == null or _stinger_player == null:
		return
	_stinger_player.stream = stream
	_stinger_player.volume_db = MusicRegistry.trim_db(track_id) + STINGER_BOOST_DB
	_stinger_player.play()


# ── Intern ────────────────────────────────────────────────────────────────────


func _apply() -> void:
	if not _radio_station.is_empty():
		return
	var context := active_context()
	var track := resolve_track(context, _is_sleeping())
	_crossfade_to(track, CROSSFADE_S)


func _crossfade_to(track_id: String, fade_s: float, loop := true) -> void:
	if track_id == _current_track:
		return
	_current_track = track_id
	if _players.is_empty():
		return
	var old := _players[_active]
	_active = (_active + 1) % _players.size()
	var next := _players[_active]
	_fade_out(old, fade_s)
	if track_id.is_empty():
		track_changed.emit("")
		return
	var stream := _stream_for(track_id)
	if stream == null:
		track_changed.emit("")
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	next.stream = stream
	next.volume_db = FADE_OUT_DB
	next.play()
	_fade_volume(next, MusicRegistry.trim_db(track_id), fade_s)
	track_changed.emit(track_id)


func _fade_out(player: AudioStreamPlayer, fade_s: float) -> void:
	if player == null or not player.playing:
		return
	if not is_inside_tree():
		player.stop()
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(player, "volume_db", FADE_OUT_DB, maxf(0.05, fade_s))
	tween.tween_callback(player.stop)


func _fade_volume(player: AudioStreamPlayer, target_db: float, fade_s: float) -> void:
	if player == null:
		return
	if not is_inside_tree():
		player.volume_db = target_db
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(player, "volume_db", target_db, maxf(0.05, fade_s))


func _on_player_finished() -> void:
	# Kontext-Tracks loopen im Stream; endet einer, war es das Radio.
	if not _radio_station.is_empty():
		radio_next()


func _on_travel_finished(target: StringName) -> void:
	var key := String(target)
	if ROUTE_CONTEXTS.has(key):
		set_context(str(ROUTE_CONTEXTS[key]))
		return
	if key == "mg_host":
		var router := get_node_or_null("/root/SceneRouter")
		var scene: Node = router.get_current_scene() if router != null else null
		var game_id := str(scene.get("game_id")) if scene != null else ""
		set_context("game:%s" % game_id if not game_id.is_empty() else "arcade")
		return
	if key.begins_with("city/ort/"):
		set_context("city")
	# Unbekannte Ziele (Social/Album/...) behalten die laufende Musik.


func _is_sleeping() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_value"):
		return false
	return bool(gs.get_value("gooby.sleep.sleeping", false))


func _player_level() -> int:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_value"):
		return 1
	return int(gs.get_value("progression.level", 1))


func _stream_for(track_id: String) -> AudioStream:
	if _streams.has(track_id):
		return _streams[track_id]
	var stream_path := MusicRegistry.path(track_id)
	if stream_path.is_empty() or not ResourceLoader.exists(stream_path):
		push_warning("[music] Track fehlt: '%s' (%s)" % [track_id, stream_path])
		return null
	var stream: AudioStream = load(stream_path)
	_streams[track_id] = stream
	return stream


func _shuffle(queue: Array[String]) -> void:
	for i in range(queue.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := queue[i]
		queue[i] = queue[j]
		queue[j] = tmp


func _ensure_music_bus() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Music")
	AudioServer.set_bus_send(idx, &"Master")
	# Fallback ohne AudioDirector: Mix-Offset trotzdem anwenden, damit die
	# Musik nie wieder 9 dB über den Effekten liegt (EVAL-1 S1).
	AudioServer.set_bus_volume_db(idx, float(AudioDirector.BUS_BASE_DB.get("Music", 0.0)))
