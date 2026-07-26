extends MinigameBase
## Schaf-Hüten (ranchHerde) — Spiel-Szene (RANCH-2). Gooby reitet sein
## Ranch-Pferd und treibt eine Boids-Herde durch das Tor in den Pferch,
## bevor die Zeit abläuft. Die GESAMTE Herden-Simulation kommt 1:1 aus
## RanchHerdeLogic (Bot-zertifiziert, deterministisch); diese Szene mappt
## nur Zustand → 3D und Zeigefinger → Reiter-Ziel (Tippen/Ziehen aufs Feld,
## alternativ Pfeiltasten). 10 Level aus data/herde_level.json, Auswahl über
## RanchLevelSelect, Fortschritt in `ranch.spiele.herde`.

const Stage3DScript := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const GoobyActorScript := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Logic := preload("res://scripts/minigames/games/ranch_herde/herde_logic.gd")

const WOLLE := Color(0.96, 0.94, 0.88)
const WOLLE_HELL := Color(0.99, 0.97, 0.93)
const GESICHT := Color(0.45, 0.38, 0.33)
const ZAUN := Color(0.72, 0.53, 0.36)
const TOR_FARBE := Color(0.93, 0.72, 0.35)

var tune: Dictionary = {}
var level_liste: Array = []
var level: Dictionary = {}
var level_id := 0
var session_score := 0
var finished := false
var level_running := false

## Simulations-Zustand (RanchHerdeLogic).
var schafe: Array = []
var reiter := Vector2.ZERO
var ziel := Vector2.ZERO
var t_abs := 0.0
var limit := 60.0
var drin_vorher := 0

var view_size := Vector2(390.0, 844.0)

var _stage: Node3D
var _welt: Node3D
var _pferd: RanchPferd
var _gooby: Node3D
var _schaf_nodes: Array[Node3D] = []
var _select: RanchLevelSelect
var _hud: Control
var _zeit_label: Label
var _drin_label: Label
var _hint_label: Label
var _ende_timer := 0.0
var _zeiger_unten := false


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.TUNE, ctx.difficulty)
	level_liste = Logic.load_level()
	_build_select()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook — beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	if _stage != null:
		_stage.call("apply_size", view_size)
		_frame_kamera()
	if _hud != null:
		_layout_hud()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	if _stage != null:
		_stage.call("tick", delta)
	if not level_running:
		if _ende_timer > 0.0:
			_ende_timer -= delta
			if _ende_timer <= 0.0:
				_zeige_select()
		return
	_step_sim(delta)
	_step_optik(delta)


## ------------------------------------------------------------ Level-Wahl


func _build_select() -> void:
	_select = RanchLevelSelect.new()
	_select.spiel = RanchSpieleProgress.SPIEL_HERDE
	_select.title_key = "mg.ranchHerde.title"
	_select.tile_prefix = "L"
	_select.game_state = _game_state()
	_select.level_chosen.connect(_on_level_chosen)
	_select.done_pressed.connect(_finish_session)
	add_child(_select)


func _game_state() -> Object:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _on_level_chosen(id: int) -> void:
	if not running or finished:
		return
	level_id = id
	level = Logic.level_by_id(level_liste, id)
	if level.is_empty():
		return
	_select.visible = false
	_start_level()


func _zeige_select() -> void:
	_teardown_level()
	if _select != null:
		_select.game_state = _game_state()
		_select.refresh()
		_select.visible = true


func _finish_session() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": session_score})


## ------------------------------------------------------------ Level-Start


func _start_level() -> void:
	var rng := ctx.rng(ctx.run_seed + level_id * 211)
	schafe = Logic.spawn_schafe(level, rng)
	var feld: Array = level.get("feld", [12.0, 9.0])
	reiter = Vector2(0.0, float(feld[1]) * 0.9)
	ziel = reiter
	t_abs = 0.0
	limit = Logic.zeitlimit(level, tune)
	drin_vorher = 0
	_build_welt()
	_build_hud()
	level_running = true
	AudioDirector.try_play(self, "ui_confirm")


func _teardown_level() -> void:
	level_running = false
	for node: Node in [_hud, _welt, _stage]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_hud = null
	_welt = null
	_stage = null
	_pferd = null
	_gooby = null
	_schaf_nodes = []


func _build_welt() -> void:
	_stage = Stage3DScript.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				"sky_top": Color(0.47, 0.7, 0.94),
				"sky_horizon": Color(0.91, 0.96, 1.0),
				# Kein Tiefen-Nebel: die Hochkant-Kamera steht weit weg,
				# Nebel würde das ganze Feld auswaschen.
				"fog": false,
				"far": 140.0,
				"shadow_distance": 30.0,
				"glow": 0.15,
			}
		)
	)
	_stage.call("apply_size", view_size)
	_welt = Node3D.new()
	_stage.add_child(_welt)
	_build_feld()
	_build_pferch()
	_build_reiter()
	_build_schafe()
	_frame_kamera()


func _build_feld() -> void:
	var feld: Array = level.get("feld", [12.0, 9.0])
	var hx := float(feld[0])
	var hz := float(feld[1])
	var gras := MeshInstance3D.new()
	var gras_mesh := BoxMesh.new()
	gras_mesh.size = Vector3(hx * 2.0 + 10.0, 0.3, hz * 2.0 + 10.0)
	gras.mesh = gras_mesh
	# Dunkler als das Reit-Gras: die Draufsicht-Kamera sieht die voll
	# besonnte Oberseite, hellere Töne kippen im ACES-Tonemapping ins Weiße.
	gras.material_override = RanchPferd.material(Color(0.42, 0.63, 0.33))
	gras.position = Vector3(0.0, -0.15, 0.0)
	_welt.add_child(gras)
	# Feldzaun: vier Riegel (je 1 Draw-Call).
	for wand: Array in [
		[Vector3(0.0, 0.5, -hz), Vector3(hx * 2.0, 0.5, 0.16)],
		[Vector3(0.0, 0.5, hz), Vector3(hx * 2.0, 0.5, 0.16)],
		[Vector3(-hx, 0.5, 0.0), Vector3(0.16, 0.5, hz * 2.0)],
		[Vector3(hx, 0.5, 0.0), Vector3(0.16, 0.5, hz * 2.0)],
	]:
		_balken(wand[0], wand[1], ZAUN)


func _build_pferch() -> void:
	var p := Logic.pferch_rect(level)
	var px := float(p["x"])
	var pz := float(p["z"])
	var w := float(p["w"])
	var t := float(p["t"])
	var tor := float(p["tor"])
	# Heller Pferch-Boden als Zielmarke.
	var boden := MeshInstance3D.new()
	var boden_mesh := BoxMesh.new()
	boden_mesh.size = Vector3(w, 0.05, t)
	boden.mesh = boden_mesh
	boden.material_override = RanchPferd.material(Color(0.8, 0.71, 0.48))
	boden.position = Vector3(px, 0.03, pz)
	boden.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_welt.add_child(boden)
	# Wände: Nord + West + Ost + Süd in zwei Segmenten (Tor-Lücke).
	_balken(Vector3(px, 0.45, pz - t * 0.5), Vector3(w, 0.9, 0.18), ZAUN)
	_balken(Vector3(px - w * 0.5, 0.45, pz), Vector3(0.18, 0.9, t), ZAUN)
	_balken(Vector3(px + w * 0.5, 0.45, pz), Vector3(0.18, 0.9, t), ZAUN)
	var sued_z := pz + t * 0.5
	var seg := (w - tor) * 0.5
	if seg > 0.05:
		_balken(Vector3(px - tor * 0.5 - seg * 0.5, 0.45, sued_z), Vector3(seg, 0.9, 0.18), ZAUN)
		_balken(Vector3(px + tor * 0.5 + seg * 0.5, 0.45, sued_z), Vector3(seg, 0.9, 0.18), ZAUN)
	# Torpfosten in Signalfarbe.
	for seite: float in [-1.0, 1.0]:
		_balken(Vector3(px + seite * tor * 0.5, 0.7, sued_z), Vector3(0.24, 1.4, 0.24), TOR_FARBE)


func _balken(pos: Vector3, groesse: Vector3, farbe: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mi.mesh = mesh
	mi.material_override = RanchPferd.material(farbe)
	mi.position = pos
	_welt.add_child(mi)


func _build_reiter() -> void:
	_pferd = RanchPferd.neu(Color("#C58B5A"), Color("#6E4A2E"))
	_pferd.position = Vector3(reiter.x, 0.0, reiter.y)
	_welt.add_child(_pferd)
	_gooby = GoobyActorScript.new()
	_gooby.position = Vector3(0.0, 1.32, -0.1)
	_pferd.add_child(_gooby)
	_gooby.call("mount", 0.62, 0.0, "idle")


## Billige Puschel-Schafe (7 Meshes, Kleinteile ohne Schatten) — bewusst
## eigener Bau statt RanchTier: 12 Schafe müssen ins Draw-Call-Budget.
func _build_schafe() -> void:
	_schaf_nodes = []
	for s: Variant in schafe:
		var wurzel := Node3D.new()
		wurzel.position = Vector3(float((s as Dictionary)["x"]), 0.0, float((s as Dictionary)["z"]))
		_welt.add_child(wurzel)
		_schaf_nodes.append(wurzel)
		_kugel(wurzel, Vector3(0.0, 0.48, 0.0), Vector3(0.42, 0.36, 0.5), WOLLE, true)
		_kugel(wurzel, Vector3(0.0, 0.66, -0.12), Vector3(0.22, 0.17, 0.22), WOLLE_HELL, false)
		var kopf := Node3D.new()
		kopf.name = "Kopf"
		kopf.position = Vector3(0.0, 0.58, 0.44)
		wurzel.add_child(kopf)
		_kugel(kopf, Vector3.ZERO, Vector3(0.17, 0.17, 0.18), GESICHT.lightened(0.35), false)
		_kugel(kopf, Vector3(0.0, 0.13, -0.04), Vector3(0.14, 0.09, 0.12), WOLLE, false)
		for ecke: Vector2 in [
			Vector2(-0.18, 0.14), Vector2(0.18, 0.14), Vector2(-0.18, -0.16), Vector2(0.18, -0.16)
		]:
			var bein := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.05
			mesh.bottom_radius = 0.05
			mesh.height = 0.3
			mesh.radial_segments = 8
			bein.mesh = mesh
			bein.material_override = RanchPferd.material(GESICHT)
			bein.position = Vector3(ecke.x, 0.15, ecke.y)
			bein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wurzel.add_child(bein)


func _kugel(parent: Node3D, pos: Vector3, groesse: Vector3, farbe: Color, schatten: bool) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 7
	mi.mesh = mesh
	mi.position = pos
	mi.scale = groesse * 2.0
	mi.material_override = RanchPferd.material(farbe)
	if not schatten:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Kamera: Blick von Süden (+z) übers ganze Feld — fit() macht die Distanz
## in BEIDEN Orientierungen richtig.
func _frame_kamera() -> void:
	if _stage == null or level.is_empty():
		return
	var feld: Array = level.get("feld", [12.0, 9.0])
	var hx := float(feld[0])
	var hz := float(feld[1])
	var punkte: Array = [
		Vector3(-hx, 0.0, -hz),
		Vector3(hx, 0.0, -hz),
		Vector3(-hx, 0.0, hz),
		Vector3(hx, 0.0, hz),
	]
	_stage.call("fit", punkte, Vector3(0.0, 0.0, 0.6), 54.0, 0.0, 0.9)


## --------------------------------------------------------------- Simulation


func _step_sim(delta: float) -> void:
	t_abs += delta
	reiter = Logic.reiter_step(reiter, ziel, delta, tune, level)
	schafe = Logic.step(schafe, reiter, t_abs, delta, tune, level)
	var drin := Logic.drin_anzahl(schafe)
	if drin > drin_vorher:
		_schaf_drin(drin)
	drin_vorher = drin
	if drin == schafe.size():
		_level_geschafft()
		return
	if t_abs >= limit:
		_zeit_um()
		return
	_update_labels()


func _schaf_drin(drin: int) -> void:
	# Steigende Tonhöhe pro Schaf = kleine Belohnungstreppe (SfxMap ist
	# W4-P1-Besitz; eigener ranch_pen_in-Sound ist als Wunsch angemeldet).
	AudioDirector.try_play(self, "mg_good", 1.0 + 0.03 * drin)
	if _stage != null:
		_stage.call("pulse_glow", 0.4)
	if ctx.juice != null:
		var tor := Logic.tor_pos(level)
		ctx.juice.float_text(
			_screen_pos(Vector3(tor.x, 1.4, tor.y)),
			"+1  %d/%d" % [drin, schafe.size()],
			AcTokens.LEAF_DARK
		)


func _level_geschafft() -> void:
	level_running = false
	var rest := maxf(0.0, limit - t_abs)
	var stars := Logic.sterne(rest, limit)
	var gs := _game_state()
	var first := not RanchSpieleProgress.is_cleared(gs, RanchSpieleProgress.SPIEL_HERDE, level_id)
	var score := Logic.level_score(level_id, rest, first, tune)
	RanchSpieleProgress.record_win(gs, RanchSpieleProgress.SPIEL_HERDE, level_id, stars, score)
	session_score += score
	ctx.report_score(session_score, score)
	ctx.report_coin_chunk(score)
	AudioDirector.try_play(self, "mg_win")
	if _stage != null:
		_stage.call("pulse_glow", 0.8)
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.6)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 130.0, view_size.y * 0.32),
			I18nService.t("mg.ranchHerde.geschafft", {"stars": stars, "score": score}),
			AcTokens.GOLD
		)
	_ende_timer = 1.6


func _zeit_um() -> void:
	level_running = false
	AudioDirector.try_play(self, "mg_lose")
	if ctx.juice != null:
		ctx.juice.shake(0.4)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 90.0, view_size.y * 0.36),
			I18nService.t("mg.ranchHerde.zeit_um"),
			AcTokens.DANGER
		)
	_ende_timer = 1.6


## ------------------------------------------------------------------ Optik


func _step_optik(delta: float) -> void:
	if _pferd == null:
		return
	var davor := Vector2(_pferd.position.x, _pferd.position.z)
	_pferd.position = Vector3(reiter.x, 0.0, reiter.y)
	var bewegung := (reiter - davor).length() / maxf(delta, 0.0001)
	if bewegung > 0.3:
		var richtung := reiter - davor
		_pferd.rotation.y = atan2(richtung.x, richtung.y)
	_pferd.set_gangart(
		(
			RanchPferd.GANG_GALOPP
			if bewegung > float(tune["REITER_TEMPO"]) * 0.7
			else (RanchPferd.GANG_TRAB if bewegung > 0.3 else RanchPferd.GANG_IDLE)
		)
	)
	if _gooby != null:
		_gooby.call("tick", delta)
	for i in mini(schafe.size(), _schaf_nodes.size()):
		var s: Dictionary = schafe[i]
		var node := _schaf_nodes[i]
		node.position = Vector3(float(s["x"]), 0.0, float(s["z"]))
		var vel := Vector2(float(s["vx"]), float(s["vz"]))
		if vel.length() > 0.2:
			node.rotation.y = atan2(vel.x, vel.y)
		# Puschel-Hoppeln: kleine Hüpfer nach Schaf-Phase + Tempo.
		node.position.y = (
			absf(sin(t_abs * 6.0 + float(s["phase"]))) * 0.06 * minf(1.0, vel.length())
		)


func _screen_pos(world: Vector3) -> Vector2:
	if _stage == null:
		return view_size * 0.4
	return _stage.call("to_screen", world)


## -------------------------------------------------------------------- HUD


func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_zeit_label = Label.new()
	_zeit_label.theme_type_variation = &"HeadlineLabel"
	_hud.add_child(_zeit_label)
	_drin_label = Label.new()
	_drin_label.theme_type_variation = &"CaptionLabel"
	_hud.add_child(_drin_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.ranchHerde.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_hint_label)
	_layout_hud()
	_update_labels()


func _layout_hud() -> void:
	if _zeit_label == null:
		return
	_zeit_label.position = Vector2(16.0, 10.0)
	_drin_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(view_size.x * 0.5 - 180.0, view_size.y - 44.0)
	_hint_label.size = Vector2(360.0, 34.0)


func _update_labels() -> void:
	if _zeit_label == null:
		return
	_zeit_label.text = I18nService.t("mg.ranchHerde.zeit", {"s": "%.0f" % maxf(0.0, limit - t_abs)})
	_drin_label.text = I18nService.t("mg.ranchHerde.drin", {"n": drin_vorher, "max": schafe.size()})


## Tippen/Ziehen aufs Feld = Reit-Ziel (Screen → Bodenebene y=0).
func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or not level_running or _stage == null:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_zeiger_unten = touch.pressed
		if touch.pressed:
			_setze_ziel(touch.position)
	elif event is InputEventScreenDrag and _zeiger_unten:
		_setze_ziel((event as InputEventScreenDrag).position)


func _setze_ziel(screen: Vector2) -> void:
	var punkt: Vector3 = _stage.call("plane_point", screen, 0.0)
	ziel = Vector2(punkt.x, punkt.z)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_active() or finished or not level_running:
		return
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	var richtung := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		richtung.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		richtung.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		richtung.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		richtung.y += 1.0
	if richtung != Vector2.ZERO:
		ziel = reiter + richtung.normalized() * 4.0
