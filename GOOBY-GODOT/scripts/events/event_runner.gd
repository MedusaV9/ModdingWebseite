class_name EventRunner
extends Node3D
## Event-Runner (W3d CONTENT + BACKLOG-REST, Doc F §4.2): setzt das AKTIVE Random-Event als
## Szene im Raum um — Gooby-Pose, Props, Tap-Auflösung, Choice-Karten, Licht/Sound-Inszenierung.
## `szene_setup`-Hooks: marienkaefer, kuehlschrank, glas_scherben, teller_scherben,
##   nutella_nacht (Voll-Fenster: Nachtlicht, Schmier-Props, Fleck-Beweis), sockensuche,
##   robo_jagd, kleber_stuhl, wurm_freund, fernbedienung, karton_gooby, gewitter_angst,
##   mehl_unfall, klopapier_mumie (W13B, ausgelagert in mumie_szene.gd) — KOMPLETT SPIELBAR.
##
## Einhängen: EventRunner.attach_to(room) nach dem Raum-Aufbau (Hook-Request
## an W2a in W3d-home-requests.md). Der Runner liest das aktive Event aus dem
## `events`-Slice (RandomEventEngine) und baut die passende Szene. Verpasste
## Nutella-Nächte hinterlassen einen wegwischbaren Fleck (fail_prop).
##
## W18/E3b (Raumwechsel): Events pinnen sich beim ersten Szenen-Aufbau an
## ihren Raum (RandomEventEngine.pin_room) — `travel_started` bricht die
## laufende Inszenierung sofort ab (abort_staging: Props/Choice-Karte/
## Overlays weg, Gooby-Pose zurück), fremde Räume stagen NICHT neu, und
## erst der Rückbesuch des gepinnten Raums baut die Szene wieder auf
## (das Event bleibt aktiv; Timeout/Fail übernimmt die Engine wie bisher).
##
## W21 (Blocker #2 „Event-Kaperung“): die PRÄSENTATION der Choice-Karten
## wohnt in der EventChoreo (event_choreo.gd) — Dirigent-Einreihung,
## Vertagen-Chip, Gooby-Sichtbarkeit. Logik/Belohnungen unverändert hier.

signal event_resolved(event_id: String)

const FOOD_COLORS: Array[Color] = [
	Color("#FF9F5A"),
	Color("#8FD06C"),
	Color("#FFD166"),
	Color("#F4BFCD"),
	Color("#AFD8E8"),
]
const SHARD_COLOR := Color("#DDE3EA")
const SOCK_COLOR := Color("#FF7BA9")
const NUTELLA_COLOR := Color("#5A3A25")
const CARDBOARD := Color("#C8975B")
const ROBO_COLOR := Color("#8F9BAA")
const CUSHION_COLORS: Array[Color] = [Color("#F4BFCD"), Color("#59C9B9"), Color("#FFD166")]
const FLOUR_COLOR := Color(0.97, 0.96, 0.93)
const WORM_COLOR := Color("#E88AA0")
## Rücklings-Pose: Kippwinkel + Anhebung, damit der Rücken auf dem Boden
## aufliegt (Rig-Origin liegt an den Füßen, sonst rotiert er unter den Boden).
const MARIENKAEFER_TILT_DEG := 105.0
const MARIENKAEFER_RIG_LIFT := 0.5
## Bäuchlings-Pose (Wurm-Freund): nach vorn gekippt, gleiche Origin-Regel.
const BAEUCHLINGS_TILT_DEG := -80.0
const BAEUCHLINGS_RIG_LIFT := 0.45

var _room: Node = null
var _gs: Object = null
var _defs: Array = []
var _def: Dictionary = {}
var _props: Array = []
var _remaining := 0
var _running := false
var _wiggle: Tween = null
var _rng := RandomNumberGenerator.new()
## Szenen-Zustand der neuen Events (BACKLOG-REST).
var _robo: Node3D = null
var _robo_dodges := 0
var _robo_tween: Tween = null
var _remote_index := 0
var _flash_overlay: ColorRect = null
var _flash_timer: Timer = null
var _eyes_spot: Node3D = null
var _gewitter_found := false
var _night_layer: CanvasLayer = null
var _night_light: OmniLight3D = null
## W18/E3: aktive Choice-Karte (Nutella/Wurm/Karton) — der Abbruch beim
## Raumwechsel muss sie abräumen (sie hängt im UI-Layer, nicht in _props).
var _choice: Control = null


## Runner an einen Raum hängen; zeigt Fail-Bubble, baut liegengebliebene
## Fail-Requisiten auf und startet das aktive Event (falls dessen Szene in
## diesen Raum passt).
static func attach_to(room: Node, defs: Array = []) -> EventRunner:
	var existing := room.get_node_or_null("EventRunner")
	if existing is EventRunner:
		return existing
	# W18/4-B9: ohne Home-Gooby (Urlaub) KEIN Runner — alle Events sind
	# Gooby-Gags; das aktive Event bleibt im Slice und läuft nach der
	# Rückkehr weiter (kein Geister-Erzähler im leeren Raum).
	if room.has_method("gooby") and room.gooby() == null:
		return null
	var runner := EventRunner.new()
	runner.name = "EventRunner"
	room.add_child(runner)
	runner.setup(room, defs)
	return runner


func setup(room: Node, defs: Array = []) -> void:
	_room = room
	_rng.randomize()
	_gs = room.game_state() if room.has_method("game_state") else null
	if _gs == null:
		_gs = get_node_or_null("/root/GameState")
	_defs = defs if not defs.is_empty() else RandomEventEngine.defs_from_registry()
	if _gs == null:
		return
	var fail_text := RandomEventEngine.take_fail_notice(_gs)
	if not fail_text.is_empty():
		_say_raw(fail_text)
	_show_fail_prop()
	# W18/E3b: Reiseantritt räumt die Inszenierung SOFORT ab — die W15-Tür-
	# Fahrt hält den alten Raum sichtbar am Leben, die Event-UI schwebte
	# sonst mit bis in die Küche.
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_started"):
		router.travel_started.connect(_on_travel_started)
	var active := RandomEventEngine.active_of(_gs)
	if not active.is_empty():
		var def := RandomEventEngine.def_by_id(_defs, str(active.get("id", "")))
		if not def.is_empty() and _stage_erlaubt(active):
			if not _room_id().is_empty():
				RandomEventEngine.pin_room(_gs, _room_id())
			start(def)


## Event-Szene direkt starten (Screenshots/Tests; normal via setup()).
func start(def: Dictionary) -> void:
	if _running:
		return
	_running = true
	_def = def
	# W21 (Event-Kaperung, d): steckt Gooby aus Kamerasicht hinter Möbeln
	# (Playtest: hinterm Sofa), rückt ihn die Choreo VOR dem Aufbau auf
	# die nächste freie, sichtbare Zelle — reine Präsentation.
	EventChoreo.attach_to(self).ruecke_gooby_ins_bild()
	match str(def.get("szene_setup", "")):
		"marienkaefer":
			_setup_marienkaefer()
		"kuehlschrank":
			_setup_aufsammeln(int(def.get("props", 5)), FOOD_COLORS, "events.kuehlschrank.bubble")
		"glas_scherben":
			_setup_scherben(int(def.get("props", 3)), "events.glas.bubble")
		"teller_scherben":
			_setup_scherben(int(def.get("props", 3)), "events.teller.bubble")
		"nutella_nacht":
			_setup_nutella()
		"sockensuche":
			_setup_sockensuche(int(def.get("props", 3)))
		"robo_jagd":
			_setup_robo_jagd()
		"kleber_stuhl":
			_setup_kleber_stuhl(int(def.get("props", 4)))
		"wurm_freund":
			_setup_wurm_freund()
		"fernbedienung":
			_setup_fernbedienung(int(def.get("props", 3)))
		"karton_gooby":
			_setup_karton_gooby()
		"gewitter_angst":
			GewitterSzene.setup(self)
		"mehl_unfall":
			_setup_mehl_unfall(int(def.get("props", 5)))
		"klopapier_mumie":
			MumieSzene.setup(self, int(def.get("props", 5)))
		_:
			_running = false


func is_running() -> bool:
	return _running


## W18/E3b: Inszenierung abbrechen OHNE aufzulösen — Props, Choice-Karte,
## Nachtlicht/Taschenlampen-Overlay weg, Gooby-Pose und Wandern zurück.
## Das Event bleibt aktiv (gepinnt an seinen Raum): der Rückbesuch baut
## die Szene wieder auf, sonst greift Timeout/Fail. Idempotent.
func abort_staging() -> void:
	if not _running:
		return
	_clear_props()
	_clear_choice()
	_night_off()
	_stop_flash_timer()
	if _wiggle != null:
		_wiggle.kill()
		_wiggle = null
	_reset_gooby()
	_running = false
	_def = {}


func _on_travel_started(_target: StringName = &"", _travel_type: int = 0) -> void:
	abort_staging()


## Darf die Szene des aktiven Events in DIESEM Raum aufgebaut werden?
## Ungepinnt (Erst-Aufbau) → ja; sonst nur im gepinnten Raum (E3b).
func _stage_erlaubt(active: Dictionary) -> bool:
	var pinned := str(active.get("room", ""))
	return pinned.is_empty() or pinned == _room_id()


func _room_id() -> String:
	if _room != null and "room_id" in _room:
		return str(_room.get("room_id"))
	return ""


## Gooby aus jeder Event-Pose zurückholen (Rücklings-/Bäuchlings-Kipp,
## Tisch-/Stuhl-Lift, Gewitter-Unsichtbarkeit) und wieder wandern lassen.
func _reset_gooby() -> void:
	var gooby := _gooby()
	if gooby == null:
		return
	gooby.visible = true
	if "rig" in gooby and gooby.rig != null:
		var rig: Node3D = gooby.rig
		rig.rotation = Vector3.ZERO
		rig.position.y = 0.0
	gooby.set_wander_enabled(true)


# ── (1) Hingefallen-Marienkäfer ──────────────────────────────────────────────


## Gooby auf dem Rücken, zappelt (ragdoll-nah: Rig-Rotation + Wipp-Tween).
## Wichtig: der GoobyHome-Origin liegt an den FÜSSEN — deshalb das Rig kippen
## und anheben (sonst rotiert der Körper unter den Boden), Muster wie der
## Decken-Gag in gooby_home.gd. Tap-Hilfe → er rollt auf die Füße (+10 Spaß 5 h).
func _setup_marienkaefer() -> void:
	var gooby := _gooby()
	if gooby == null or not ("rig" in gooby) or gooby.rig == null:
		_running = false
		return
	gooby.set_wander_enabled(false)
	var rig: Node3D = gooby.rig
	rig.rotation.x = deg_to_rad(MARIENKAEFER_TILT_DEG)
	rig.position.y = MARIENKAEFER_RIG_LIFT
	if rig.has_method("set_emotion"):
		rig.set_emotion("dizzy")
	_wiggle = create_tween().set_loops()
	_wiggle.tween_property(rig, "rotation:z", 0.22, 0.28)
	_wiggle.tween_property(rig, "rotation:z", -0.22, 0.28)
	_say("events.marienkaefer.bubble")
	var helper := _make_prop(Color(1, 1, 1, 0.02), Vector3(1.0, 1.0, 1.0), _on_marienkaefer_help)
	helper.position = gooby.position
	add_child(helper)
	_props = [helper]


func _on_marienkaefer_help() -> void:
	var gooby := _gooby()
	if gooby != null and "rig" in gooby and gooby.rig != null:
		if _wiggle != null:
			_wiggle.kill()
			_wiggle = null
		var rig: Node3D = gooby.rig
		var up := create_tween()
		up.tween_property(rig, "rotation", Vector3.ZERO, 0.35)
		up.parallel().tween_property(rig, "position:y", 0.0, 0.35)
		gooby.play_clip("hop")
	_sfx("ui_confirm")
	_say("events.marienkaefer.danke")
	_resolve()


# ── (2) Kühlschrank / (3+4) Scherben / (6) Socken: Tap-Aufsammeln ────────────


func _setup_aufsammeln(count: int, colors: Array, bubble_key: String) -> void:
	_say(bubble_key)
	_set_gooby_emotion("sad")
	_scatter_props(
		count,
		func(i: int) -> Node3D:
			return _make_prop(
				colors[i % colors.size()], Vector3(0.28, 0.28, 0.28), _on_prop_collected
			)
	)


func _setup_scherben(count: int, bubble_key: String) -> void:
	_say(bubble_key)
	_set_gooby_emotion("scared")
	_scatter_props(
		count,
		func(_i: int) -> Node3D:
			return _make_prop(SHARD_COLOR, Vector3(0.3, 0.06, 0.3), _on_prop_collected)
	)


func _setup_sockensuche(count: int) -> void:
	_say("events.sockensuche.bubble")
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(true)
	_scatter_props(
		count,
		func(_i: int) -> Node3D:
			return _make_prop(SOCK_COLOR, Vector3(0.22, 0.1, 0.34), _on_prop_collected)
	)


func _scatter_props(count: int, factory: Callable) -> void:
	_props = []
	_remaining = count
	var cells := _free_cells()
	for i in count:
		var prop: Node3D = factory.call(i)
		if cells.is_empty():
			prop.position = Vector3(1.0 + i * 0.7, 0.15, 1.0)
		else:
			var cell: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
			cells.erase(cell)
			prop.position = GridData.world_center(cell, Vector2i.ONE, 0) + Vector3(0.0, 0.15, 0.0)
		add_child(prop)
		_props.append(prop)


func _on_prop_collected() -> void:
	_remaining -= 1
	_sfx("ui_click")
	if _remaining <= 0:
		match str(_def.get("szene_setup", "")):
			"sockensuche":
				_say("events.sockensuche.danke")
			"kuehlschrank":
				_say("events.kuehlschrank.danke")
			_:
				_say("events.scherben.danke")
		_set_gooby_emotion("happy")
		_resolve()


# ── (5) Nutella-Nacht (Voll-Fenster: Nachtlicht + Schmier + Fleck-Beweis) ────


## Küche nachts: Raum abgedunkelt, warmes Kühlschrank-Licht, Gooby am Tisch
## mit Nutella-Glas + Schmier-Props an der Schnute, „uhhh UPPPS“, Choice:
## schlafen schicken (−5 Freude +10 Energie) / weitermachen (+10 Freude
## −5 Energie, Glas-Kratz-Sound) — danach räumt er auf + tapst zurück ins
## Bett. Verpasst man das Fenster, bleibt ein wegwischbarer Fleck (setup()).
func _setup_nutella() -> void:
	var gooby := _gooby()
	_night_on()
	var jar := _make_prop(NUTELLA_COLOR, Vector3(0.22, 0.3, 0.22), func() -> void: pass)
	if gooby != null:
		gooby.set_wander_enabled(false)
		gooby.play_clip("sit")
		if "rig" in gooby and gooby.rig != null:
			gooby.rig.set_emotion("scared")
			_attach_smear(gooby)
		jar.position = gooby.position + Vector3(0.45, 0.15, 0.0)
		if _night_light != null:
			_night_light.global_position = gooby.global_position + Vector3(0.6, 1.2, 0.6)
	add_child(jar)
	_props.append(jar)
	_sfx("ui_open")
	_say("events.nutella.upps")
	_show_choice(
		[
			{"key": "events.nutella.ab_ins_bett", "variation": &"BtnTeal", "to_bed": true},
			{"key": "events.nutella.weitermachen", "variation": &"BtnPink", "to_bed": false},
		],
		_on_nutella_choice
	)


## Nutella-Schmier: kleine braune Kleckse an Schnute + Pfote (Doc F §4.2
## „Pfoten & Schnute voller Nutella“) — hängen am Gooby, fliegen beim
## Aufräumen mit weg (_clear_props).
func _attach_smear(gooby: Node) -> void:
	for offset: Vector3 in [Vector3(0.08, 0.62, 0.16), Vector3(-0.12, 0.3, 0.14)]:
		var smear := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.045
		ball.height = 0.09
		smear.mesh = ball
		smear.material_override = _flat_mat(NUTELLA_COLOR)
		smear.position = offset
		gooby.add_child(smear)
		_props.append(smear)


func _on_nutella_choice(option: Dictionary) -> void:
	var to_bed := bool(option.get("to_bed", true))
	_apply_stat_delta("fun", -5.0 if to_bed else 10.0)
	_apply_stat_delta("energy", 10.0 if to_bed else -5.0)
	var gooby := _gooby()
	if to_bed:
		_say("events.nutella.murmel")
		_set_gooby_emotion("sad")
	else:
		_say("events.nutella.strahlen")
		_set_gooby_emotion("ecstatic")
		_sfx("mg_perfect")
	await _sleep_s(2.0)
	# Aufräumen + zurück ins Bett tapsen (kurzer Walk + sleep-Clip).
	_say("events.nutella.aufraeumen")
	_clear_props()
	_night_off()
	if gooby != null and is_instance_valid(gooby):
		await gooby.walk_to(gooby.position + Vector3(1.5, 0.0, 1.0), 4.0)
		gooby.play_clip("sleep")
	_resolve()


## Abdunkeln + warmes Kühlschrank-Licht (CanvasLayer unter der Event-UI).
func _night_on() -> void:
	if _night_layer != null:
		return
	_night_layer = CanvasLayer.new()
	_night_layer.name = "NutellaNacht"
	_night_layer.layer = 4
	add_child(_night_layer)
	var dark := ColorRect.new()
	dark.color = Color(0.05, 0.06, 0.14, 0.42)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_layer.add_child(dark)
	_night_light = OmniLight3D.new()
	_night_light.light_color = Color(1.0, 0.88, 0.66)
	_night_light.light_energy = 2.2
	_night_light.omni_range = 4.0
	add_child(_night_light)


func _night_off() -> void:
	if _night_layer != null:
		_night_layer.queue_free()
		_night_layer = null
	if _night_light != null:
		_night_light.queue_free()
		_night_light = null


## Liegengebliebener Nutella-Fleck (fail_prop): brauner Fleck am Boden,
## Tap wischt ihn weg — der Beweis verschwindet „spurlos“.
func _show_fail_prop() -> void:
	if _gs == null or RandomEventEngine.fail_prop_of(_gs) != "nutella_fleck":
		return
	var stain := _make_prop(NUTELLA_COLOR, Vector3(0.42, 0.03, 0.36), _on_fail_prop_wiped)
	var cells := _free_cells()
	if cells.is_empty():
		stain.position = Vector3(1.2, 0.02, 1.2)
	else:
		var cell: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
		stain.position = GridData.world_center(cell, Vector2i.ONE, 0) + Vector3(0.0, 0.02, 0.0)
	add_child(stain)


func _on_fail_prop_wiped() -> void:
	if _gs != null:
		RandomEventEngine.clear_fail_prop(_gs)
	_sfx("ui_click")
	_say("events.nutella.fleck_weg")


# ── (7) Robo-Jagd ────────────────────────────────────────────────────────────


## Robo-Staubsauger dreht Runden, Gooby flüchtet auf den Tisch („ER WEISS,
## DASS ICH KRÜMEL BIN!“). Tap fängt den Sauger — er weicht 2× aus, der
## dritte Tap schaltet ihn ab (+Spaß-Buff, Boden sauber: +Hygiene).
func _setup_robo_jagd() -> void:
	var gooby := _gooby()
	var center := Vector3(0.0, 0.0, 0.0)
	if gooby != null:
		gooby.set_wander_enabled(false)
		center = gooby.position
		# Fluchttisch unter Gooby: Platte + angehobenes Rig.
		var table := EventProps.table_top()
		table.position = center + Vector3(0.0, 0.62, 0.0)
		add_child(table)
		_props.append(table)
		if "rig" in gooby and gooby.rig != null:
			gooby.rig.position.y = 0.66
			gooby.rig.set_emotion("scared")
	_say("events.robo.bubble")
	_robo_dodges = 0
	_robo = _make_prop(ROBO_COLOR, Vector3(0.45, 0.12, 0.45), _on_robo_tapped, false)
	_robo.position = center + Vector3(1.1, 0.07, 0.4)
	add_child(_robo)
	_props.append(_robo)
	_sfx("gvz_mower")
	_robo_drive(center)


## Kreisfahrt um den Tisch (Loop-Tween über 4 Wegpunkte).
func _robo_drive(center: Vector3) -> void:
	if _robo_tween != null:
		_robo_tween.kill()
	_robo_tween = create_tween().set_loops()
	var radius := 1.1
	for i in 4:
		var angle := TAU * float(i + 1) / 4.0
		var target := center + Vector3(cos(angle) * radius, 0.07, sin(angle) * radius)
		_robo_tween.tween_property(_robo, "position", target, 0.9)


func _on_robo_tapped() -> void:
	if _robo == null or not is_instance_valid(_robo):
		return
	if _robo_dodges < 2:
		_robo_dodges += 1
		_sfx("gvz_pop")
		_say("events.robo.ausweichen")
		if _robo_tween != null:
			_robo_tween.kill()
		var dodge := create_tween()
		var jump := Vector3(_rng.randf_range(-1.2, 1.2), 0.07, _rng.randf_range(-1.2, 1.2))
		dodge.tween_property(_robo, "position", _robo.position + jump, 0.25)
		dodge.tween_callback(_robo_drive.bind(_gooby_pos()))
		return
	if _robo_tween != null:
		_robo_tween.kill()
		_robo_tween = null
	_sfx("ui_toggle")
	_say("events.robo.danke")
	var gooby := _gooby()
	if gooby != null and "rig" in gooby and gooby.rig != null:
		var down := create_tween()
		down.tween_property(gooby.rig, "position:y", 0.0, 0.3)
		gooby.rig.set_emotion("happy")
		gooby.play_clip("hop")
	# Boden sauber: kleiner Hygiene-Bonus obendrauf (Doc F §4.2).
	_apply_stat_delta("hygiene", 10.0)
	_resolve()


# ── (8) Kleber-Stuhl ─────────────────────────────────────────────────────────


## Gooby klebt am Stuhl fest („Ich bin jetzt ein Stuhlgooby.“) — Rubbel-Taps
## lösen den Kleber, beim letzten gibt es ein *plopp* + Fake-Tumble rückwärts.
func _setup_kleber_stuhl(rub_taps: int) -> void:
	var gooby := _gooby()
	if gooby == null:
		_running = false
		return
	gooby.set_wander_enabled(false)
	gooby.play_clip("sit")
	_set_gooby_emotion("sad")
	# Stuhl: Sitzfläche + Lehne unter/hinter Gooby.
	for teil: MeshInstance3D in EventProps.chair_parts(gooby.position):
		add_child(teil)
		_props.append(teil)
	if "rig" in gooby and gooby.rig != null:
		gooby.rig.position.y = 0.27
	_say("events.kleber.bubble")
	_remaining = maxi(1, rub_taps)
	var rub := _make_prop(Color(1, 1, 1, 0.02), Vector3(0.9, 1.1, 0.9), _on_kleber_rubbed, false)
	rub.position = gooby.position + Vector3(0.0, 0.5, 0.0)
	add_child(rub)
	_props.append(rub)


func _on_kleber_rubbed() -> void:
	_remaining -= 1
	_sfx("gvz_pop")
	var gooby := _gooby()
	if _remaining > 0:
		_say("events.kleber.rubbel")
		if gooby != null and "rig" in gooby and gooby.rig != null:
			var wobble := create_tween()
			wobble.tween_property(gooby.rig, "rotation:z", 0.12, 0.1)
			wobble.tween_property(gooby.rig, "rotation:z", 0.0, 0.1)
		return
	_sfx("ui_confirm")
	_say("events.kleber.plopp")
	if gooby != null and "rig" in gooby and gooby.rig != null:
		var rig: Node3D = gooby.rig
		var tumble := create_tween()
		tumble.tween_property(rig, "position:y", 0.0, 0.3)
		tumble.parallel().tween_property(rig, "rotation:x", -TAU, 0.5)
		tumble.tween_callback(
			func() -> void:
				rig.rotation.x = 0.0
				gooby.play_clip("hop")
				rig.set_emotion("happy")
		)
	_resolve()


# ── (9) Wurm-Freund ──────────────────────────────────────────────────────────


## Gooby liegt bäuchlings vorm Regenwurm Herbert. Choice: draußen lassen
## (er winkt dem Beet) oder mit eingießen (Gieß-Tröpfchen-Partikel).
func _setup_wurm_freund() -> void:
	var gooby := _gooby()
	if gooby == null or not ("rig" in gooby) or gooby.rig == null:
		_running = false
		return
	gooby.set_wander_enabled(false)
	var rig: Node3D = gooby.rig
	rig.rotation.x = deg_to_rad(BAEUCHLINGS_TILT_DEG)
	rig.position.y = BAEUCHLINGS_RIG_LIFT
	rig.set_emotion("happy")
	var worm := MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.radius = 0.045
	caps.height = 0.3
	worm.mesh = caps
	worm.material_override = _flat_mat(WORM_COLOR)
	worm.rotation.z = PI / 2.0
	worm.position = gooby.position + Vector3(0.0, 0.05, -0.55)
	add_child(worm)
	_props.append(worm)
	var wiggle := create_tween().set_loops()
	wiggle.tween_property(worm, "rotation:y", 0.35, 0.5)
	wiggle.tween_property(worm, "rotation:y", -0.35, 0.5)
	_say("events.wurm.bubble")
	_show_choice(
		[
			{"key": "events.wurm.draussen", "variation": &"BtnTeal", "giessen": false},
			{"key": "events.wurm.giessen", "variation": &"BtnPink", "giessen": true},
		],
		_on_wurm_choice
	)


func _on_wurm_choice(option: Dictionary) -> void:
	var gooby := _gooby()
	if gooby != null and "rig" in gooby and gooby.rig != null:
		var rig: Node3D = gooby.rig
		var up := create_tween()
		up.tween_property(rig, "rotation", Vector3.ZERO, 0.35)
		up.parallel().tween_property(rig, "position:y", 0.0, 0.35)
	if bool(option.get("giessen", false)):
		_say("events.wurm.giessen_danke")
		_sfx("mg_good")
		if not _props.is_empty() and is_instance_valid(_props[0]):
			_puff_at((_props[0] as Node3D).position + Vector3(0, 0.4, 0), Color("#7FBBE8"))
	else:
		_say("events.wurm.winken")
		if gooby != null:
			gooby.play_clip("wave")
	_set_gooby_emotion("happy")
	await _sleep_s(1.2)
	_resolve()


# ── (10) Fernbedienung ───────────────────────────────────────────────────────


## GOB.TY brüllt auf Maximallautstärke, Gooby klappt die Ohren zu. Unter
## einem von drei Sofakissen steckt die Fernbedienung — falsche Kissen
## puffen nur, das richtige macht den Fernseher leise.
func _setup_fernbedienung(cushions: int) -> void:
	var gooby := _gooby()
	var center := _gooby_pos()
	if gooby != null:
		gooby.set_wander_enabled(false)
		_set_gooby_emotion("scared")
	# Brüllender Fernseher: Korpus + heller Screen, wackelt vor Lärm.
	var tv := EventProps.tv_set()
	tv.position = center + Vector3(0.0, 0.8, -1.4)
	add_child(tv)
	_props.append(tv)
	var rattle := create_tween().set_loops()
	rattle.tween_property(tv, "position:x", tv.position.x + 0.03, 0.06)
	rattle.tween_property(tv, "position:x", tv.position.x - 0.03, 0.06)
	tv.set_meta("rattle", rattle)
	_sfx("gvz_wave")
	_say("events.fernbedienung.bubble")
	var count := maxi(2, cushions)
	_remote_index = _rng.randi_range(0, count - 1)
	for i in count:
		var cushion := _make_prop(
			CUSHION_COLORS[i % CUSHION_COLORS.size()],
			Vector3(0.4, 0.14, 0.4),
			_on_cushion_tapped.bind(i, tv),
			false
		)
		cushion.position = center + Vector3(-0.7 + 0.7 * float(i), 0.1, 0.9)
		add_child(cushion)
		_props.append(cushion)


func _on_cushion_tapped(index: int, tv: Node3D) -> void:
	if index != _remote_index:
		_sfx("gvz_pop")
		_say("events.fernbedienung.nix")
		return
	# Gefunden: Screen aus, Wackeln stoppen, Aufatmen.
	_sfx("ui_confirm")
	if is_instance_valid(tv):
		var rattle: Variant = tv.get_meta("rattle")
		if rattle is Tween:
			(rattle as Tween).kill()
		var screen := tv.get_node_or_null("Screen")
		if screen is MeshInstance3D:
			(screen as MeshInstance3D).material_override = _flat_mat(Color(0.12, 0.13, 0.16))
	_say("events.fernbedienung.danke")
	_set_gooby_emotion("happy")
	_resolve()


# ── (11) Karton-Gooby ────────────────────────────────────────────────────────


## Gooby sitzt im Lieferkarton („Ich bin jetzt ein Möbel.“). Choice: raus
## (Hop + Freude) oder Möbel bleiben (er hält ERSTAUNLICH lange still).
func _setup_karton_gooby() -> void:
	var gooby := _gooby()
	if gooby == null:
		_running = false
		return
	gooby.set_wander_enabled(false)
	gooby.play_clip("sit")
	_set_gooby_emotion("neutral")
	var walls: Array[Vector3] = [
		Vector3(0.0, 0.3, 0.45),
		Vector3(0.0, 0.3, -0.45),
		Vector3(0.45, 0.3, 0.0),
		Vector3(-0.45, 0.3, 0.0),
	]
	for i in walls.size():
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.6, 0.06) if i < 2 else Vector3(0.06, 0.6, 0.9)
		wall.mesh = box
		wall.material_override = _flat_mat(CARDBOARD)
		wall.position = gooby.position + walls[i]
		add_child(wall)
		_props.append(wall)
	_say("events.karton.bubble")
	_show_choice(
		[
			{"key": "events.karton.raus", "variation": &"BtnTeal", "raus": true},
			{"key": "events.karton.moebel", "variation": &"BtnPink", "raus": false},
		],
		_on_karton_choice
	)


func _on_karton_choice(option: Dictionary) -> void:
	var gooby := _gooby()
	if bool(option.get("raus", true)):
		_sfx("gvz_pop")
		_say("events.karton.raus_danke")
		if gooby != null:
			gooby.play_clip("hop")
			_set_gooby_emotion("ecstatic")
		# Karton-Wände kippen nach außen.
		for prop: Node3D in _props:
			if is_instance_valid(prop) and prop is MeshInstance3D:
				var away := (prop.position - _gooby_pos()) * 0.6
				var fall := create_tween()
				fall.tween_property(prop, "position", prop.position + away, 0.3)
				fall.parallel().tween_property(prop, "rotation:x", PI / 2.0, 0.3)
		await _sleep_s(0.8)
	else:
		_say("events.karton.moebel_ok")
		_set_gooby_emotion("sleepy")
		await _sleep_s(3.0)
		_say("events.karton.moebel_ende")
	_resolve()


# ── (12) Gewitter-Angst (W18-Split: gewitter_szene.gd) ──────────────────────


## Dünne Delegaten — Tests und die Szene selbst rufen die Runner-API an,
## der Code wohnt in gewitter_szene.gd (CI-Split, Muster mumie_szene.gd).
func _on_gewitter_found() -> void:
	GewitterSzene.found(self)


func _on_gewitter_petted() -> void:
	GewitterSzene.petted(self)


# ── (13) Mehl-Unfall ─────────────────────────────────────────────────────────


## Küche weiß bestäubt, Gooby komplett weiß („Der Sack war… explosiver als
## gedacht.“) — Abklopf-Taps mit Mehl-Puffs, danach 1 Gratis-Pfannkuchen.
func _setup_mehl_unfall(taps: int) -> void:
	var gooby := _gooby()
	if gooby == null:
		_running = false
		return
	gooby.set_wander_enabled(false)
	_set_gooby_emotion("dizzy")
	# Mehl-Wolke um Gooby + weiße Flecken am Boden.
	var cloud := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.55
	ball.height = 1.1
	cloud.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(FLOUR_COLOR, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud.material_override = mat
	cloud.position = gooby.position + Vector3(0.0, 0.6, 0.0)
	cloud.name = "MehlWolke"
	add_child(cloud)
	_props.append(cloud)
	var cells := _free_cells()
	for i in 4:
		var spot := MeshInstance3D.new()
		var disc := BoxMesh.new()
		disc.size = Vector3(0.5, 0.02, 0.5)
		spot.mesh = disc
		spot.material_override = _flat_mat(FLOUR_COLOR)
		if cells.is_empty():
			spot.position = gooby.position + Vector3(0.7 * float(i - 2), 0.02, 0.5)
		else:
			var cell: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
			cells.erase(cell)
			spot.position = GridData.world_center(cell, Vector2i.ONE, 0) + Vector3(0.0, 0.02, 0.0)
		add_child(spot)
		_props.append(spot)
	_say("events.mehl.bubble")
	_remaining = maxi(1, taps)
	var zone := _make_prop(Color(1, 1, 1, 0.02), Vector3(1.0, 1.2, 1.0), _on_mehl_klopfen, false)
	zone.position = gooby.position + Vector3(0.0, 0.55, 0.0)
	add_child(zone)
	_props.append(zone)


func _on_mehl_klopfen() -> void:
	_remaining -= 1
	_sfx("gvz_pop")
	_puff_at(_gooby_pos() + Vector3(0.0, 0.8, 0.0), FLOUR_COLOR)
	var cloud := get_node_or_null("MehlWolke")
	if cloud is MeshInstance3D:
		var shrink := create_tween()
		shrink.tween_property(cloud, "scale", cloud.scale * 0.72, 0.2)
	if _remaining > 0:
		return
	if cloud is MeshInstance3D:
		(cloud as MeshInstance3D).visible = false
	_sfx("ui_confirm")
	_say("events.mehl.danke")
	_set_gooby_emotion("happy")
	# Der versprochene Pfannkuchen: einmalig +12 Hunger (Doc F §4.2).
	_apply_stat_delta("hunger", 12.0)
	_resolve()


# ── gemeinsame Helfer ────────────────────────────────────────────────────────


func _resolve() -> void:
	var event_id := str(_def.get("id", ""))
	var hook := str(_def.get("sticker_hook", ""))
	if _gs != null:
		RandomEventEngine.resolve_active(_gs, _defs, _now_ms())
		if not hook.is_empty():
			StickerUnlocks.fire_event_hook(_gs, hook)
	_clear_props()
	_clear_choice()
	_night_off()
	_stop_flash_timer()
	var gooby := _gooby()
	var keep_pose: Array[String] = ["nutella_nacht", "gewitter_angst"]
	if gooby != null and not keep_pose.has(str(_def.get("szene_setup", ""))):
		gooby.set_wander_enabled(true)
	_running = false
	_def = {}
	event_resolved.emit(event_id)


## Generische Choice-Karte (Nutella/Wurm/Karton) — läuft über die
## Event-Choreo (W21 Blocker #2): Dirigent-Einreihung + Vertagen-Chip;
## `_choice` hält die Choreo aktuell (abort_staging/Alt-Tests lesen sie).
func _show_choice(options: Array, on_pick: Callable) -> void:
	EventChoreo.attach_to(self).zeigen(options, on_pick)


func _clear_choice() -> void:
	var choreo := get_node_or_null("EventChoreo")
	if choreo is EventChoreo:
		(choreo as EventChoreo).abraeumen()
	if _choice != null and is_instance_valid(_choice):
		_choice.queue_free()
	_choice = null


func _stop_flash_timer() -> void:
	if _flash_timer != null and is_instance_valid(_flash_timer):
		_flash_timer.stop()
		_flash_timer.queue_free()
	_flash_timer = null


## Antippbare Requisite (Fabrik in `event_props.gd`).
func _make_prop(color: Color, box_size: Vector3, on_tap: Callable, free_on_tap := true) -> Node3D:
	return EventProps.make_prop(
		color, box_size, on_tap, free_on_tap, func(prop: Node3D) -> void: _props.erase(prop)
	)


func _puff_at(pos: Vector3, color: Color) -> void:
	EventProps.puff_at(self, pos, color)


func _flat_mat(color: Color) -> StandardMaterial3D:
	return EventProps.flat_mat(color)


func _clear_props() -> void:
	for prop: Node3D in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props = []
	_robo = null
	_eyes_spot = null
	if _robo_tween != null:
		_robo_tween.kill()
		_robo_tween = null
	if _flash_overlay != null and is_instance_valid(_flash_overlay):
		_flash_overlay.queue_free()
		_flash_overlay = null


func _apply_stat_delta(stat: String, delta: float) -> void:
	if _gs == null:
		return
	_gs.update(
		func(state: Dictionary) -> void:
			var stats: Variant = state.get("gooby", {}).get("stats")
			if stats is Dictionary:
				stats[stat] = clampf(float(stats.get(stat, 50.0)) + delta, 0.0, 100.0)
	)


func _free_cells() -> Array:
	if _room == null or not ("grid" in _room) or _room.grid == null:
		return []
	return _room.grid.free_cells()


func _gooby() -> Node:
	if _room != null and _room.has_method("gooby"):
		return _room.gooby()
	return null


func _gooby_pos() -> Vector3:
	var gooby := _gooby()
	return gooby.position if gooby != null else Vector3.ZERO


func _set_gooby_emotion(emotion: String) -> void:
	var gooby := _gooby()
	if gooby != null and "rig" in gooby and gooby.rig != null:
		gooby.rig.set_emotion(emotion)


func _say(key: String) -> void:
	_say_raw(I18nService.t(key))


func _say_raw(text: String) -> void:
	if _room != null and _room.has_method("say"):
		_room.say(text)


func _sfx(id: String) -> void:
	AudioDirector.try_play(self, id)


func _ui_layer() -> CanvasLayer:
	var existing := get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	add_child(layer)
	return layer


func _sleep_s(seconds: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(seconds).timeout


func _now_ms() -> int:
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
