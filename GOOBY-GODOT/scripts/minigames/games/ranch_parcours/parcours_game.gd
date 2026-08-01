extends MinigameBase
## Hindernis-Parcours (ranchParcours) — Spiel-Szene (RANCH-2). Gooby reitet
## sein Ranch-Pferd (RanchPferd, RANCH-1) einen 3D-Kurs entlang: Galopp-
## Knopf halten für Tempo, Sprung-Knopf (oder Tipp/Leertaste) am richtigen
## Punkt — die BEWERTUNG kommt 1:1 aus RanchParcoursLogic (Bot-zertifiziert):
## Der Sprungbogen muss das Hindernis sicher überdecken, Bogenmitte nah am
## Hindernis = "perfekt". Abwurf kostet Zeit + Tempo. 10 Kurse aus
## data/parcours_kurse.json, Auswahl über RanchLevelSelect, Fortschritt in
## `ranch.spiele.parcours` (RanchSpieleProgress).

const Stage3DScript := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const GoobyActorScript := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Logic := preload("res://scripts/minigames/games/ranch_parcours/parcours_logic.gd")
const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")
## Ranch-Kulisse + Farbkanon (Deko.CREME/HOLZ/FAHNEN, Werte wie RcompArena).
const Deko := preload("res://scripts/minigames/games/ranch_parcours/parcours_deko.gd")

## Optik-Zahlen (nur Darstellung — die Mechanik lebt in Logic/Feel).
const KAMERA_HINTEN := 7.2
const KAMERA_SEITE := -3.4
const KAMERA_HOEHE := 3.4
const HUF_SOUND_MAX_HZ := 4.0

var tune: Dictionary = {}
var kurse: Array = []
var kurs: Dictionary = {}
var kurs_id := 0
var session_score := 0
var finished := false
var level_running := false

## Lauf-Zustand (Physik über RanchRideFeel).
var x := 0.0
var tempo := 0.0
var galopp := false
var sprung := {"y": 0.0, "vy": 0.0}
var in_luft := false
var elapsed := 0.0
var strafzeit := 0.0
var punkte := 0
var kombo := 0
var abwuerfe := 0
var hindernisse: Array = []
var huf_phase := 0.0

var view_size := Vector2(390.0, 844.0)

var _stage: Node3D
var _welt: Node3D
var _pferd: RanchPferd
var _reiter: Node3D
var _gooby: Node3D
var _staub: GPUParticles3D
## Mini-Gooby-Publikum auf der Tribüne (RcompArena-Helfer via Deko.build);
## _jubel hebt den Hüpfer nach Perfekt-Sprüngen und im Ziel. Eigene Uhr,
## weil `elapsed` im Ziel-Fenster (Ende-Timer) stehen bleibt.
var _publikum: Node3D
var _publikum_zeit := 0.0
var _jubel := 0.0
## Absprung-Marker: Glüh-Ring auf der Ideallinie am rechnerisch besten
## Absprungpunkt (Bogenmitte über Hindernis) — pulst gold im Sprungfenster.
var _sprung_marker: Node3D
var _marker_mat: StandardMaterial3D
var _select: RanchLevelSelect
var _hud: Control
var _zeit_label: Label
var _punkte_label: Label
var _hint_label: Label
var _galopp_btn: Button
var _sprung_btn: Button
var _ende_timer := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.TUNE, ctx.difficulty)
	kurse = Logic.load_kurse()
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
			# Ziel-Fenster: das Publikum jubelt weiter, bis das Select kommt.
			_publikum_animieren(delta)
			_ende_timer -= delta
			if _ende_timer <= 0.0:
				_zeige_select()
		return
	_step_lauf(delta)
	_step_optik(delta)


## ------------------------------------------------------------ Level-Wahl


func _build_select() -> void:
	_select = RanchLevelSelect.new()
	_select.spiel = RanchSpieleProgress.SPIEL_PARCOURS
	_select.title_key = "mg.ranchParcours.title"
	_select.tile_prefix = "K"
	_select.game_state = _game_state()
	_select.level_chosen.connect(_on_level_chosen)
	_select.done_pressed.connect(_finish_session)
	add_child(_select)


func _game_state() -> Object:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _on_level_chosen(level_id: int) -> void:
	if not running or finished:
		return
	kurs_id = level_id
	kurs = Logic.kurs_by_id(kurse, level_id)
	if kurs.is_empty():
		return
	_select.visible = false
	_start_lauf()


func _zeige_select() -> void:
	_teardown_lauf()
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


## ------------------------------------------------------------- Lauf-Start


func _start_lauf() -> void:
	x = 0.0
	tempo = float(kurs.get("tempo", 6.0))
	galopp = false
	sprung = {"y": 0.0, "vy": 0.0}
	in_luft = false
	elapsed = 0.0
	strafzeit = 0.0
	punkte = 0
	kombo = 0
	abwuerfe = 0
	huf_phase = 0.0
	_build_welt()
	_build_hud()
	level_running = true
	AudioDirector.try_play(self, "ui_confirm")


func _teardown_lauf() -> void:
	level_running = false
	for node: Node in [_hud, _welt, _stage]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_hud = null
	_welt = null
	_stage = null
	_pferd = null
	_reiter = null
	_gooby = null
	_staub = null
	_publikum = null
	_jubel = 0.0
	_sprung_marker = null
	_marker_mat = null
	hindernisse = []


func _build_welt() -> void:
	_stage = Stage3DScript.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				# Belichtung GEZÄHMT (bekannte Falle: Stage-Defaults 1.2/0.6
				# überstrahlen die Wiese um ~40 Luma-Stufen ins Weiße).
				# W16 §6: der W14-Arena-Fix fehlte hier komplett — Default-
				# Exposure 1.0 + Softlight-Glow ab Schwelle 0.9 bloomten die
				# ganze sonnige Wiese (Boden-Luma ~224). Exposure/Glow-
				# Schwelle/Adjustment jetzt identisch zur Arena
				# (comp_lauf._baue_stage, Zielband ~150–170).
				"sky_top": Color(0.45, 0.68, 0.93),
				"sky_horizon": Color(0.86, 0.93, 0.97),
				"ground_horizon": Color(0.58, 0.75, 0.46),
				"ground_bottom": Color(0.4, 0.56, 0.33),
				"exposure": 0.48,
				"sun_energy": 0.85,
				"ambient": 0.4,
				"fill_energy": 0.26,
				"fog_color": Color(0.82, 0.9, 0.92),
				"fog_from": 30.0,
				"fog_to": 90.0,
				"far": 160.0,
				"shadow_distance": 34.0,
				"glow": 0.22,
				"glow_threshold": 1.08,
			}
		)
	)
	# Wie die Arena: Filmic statt ACES (die ACES-Schulter klemmt helle
	# Böden bei Weiß fest — hide_seek-Referenz nutzt Filmic) + Zeichnung
	# über Kontrast/Sättigung zurückholen.
	var env: Environment = _stage.get("environment")
	if env != null:
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.05
		env.adjustment_saturation = 1.1
	_stage.call("apply_size", view_size)
	_welt = Node3D.new()
	_stage.add_child(_welt)
	_build_boden()
	_build_hindernisse()
	_build_reiter()
	_build_sprung_marker()
	_snap_kamera()


## Boden + komplette Ranch-Kulisse (Bahn, Zaun, Tribüne, Ziel, Wiese) —
## ausgelagert nach parcours_deko.gd (Datei-Budget), Farbkanon lebt dort.
## build() gibt das Tribünen-Publikum zurück (Jubel-Hook, M2).
func _build_boden() -> void:
	_publikum = Deko.build(_welt, float(kurs.get("laenge_m", 200.0)), ctx)


func _build_hindernisse() -> void:
	hindernisse = []
	for h: Variant in kurs.get("hindernisse", []):
		var at := float((h as Dictionary).get("at", 0.0))
		var typ := str((h as Dictionary).get("typ", "zaun"))
		var node := _hindernis_node(typ)
		node.position = Vector3(at, 0.0, 0.0)
		_welt.add_child(node)
		hindernisse.append({"at": at, "typ": typ, "node": node, "state": "offen"})


## Hindernis-Optik je Typ: zaun = rot-weiß gestreifte Stange, hecke =
## Buschkasten mit Blattkuppen, oxer = Doppelstange (pink + teal), wasser =
## blaues Becken. Jedes Hindernis bekommt einen dunklen Sand-Anker auf der
## Bahn (Position sofort lesbar) und Wimpel auf den Ständern.
func _hindernis_node(typ: String) -> Node3D:
	var wurzel := Node3D.new()
	var breite := float(Logic.HINDERNIS_BREITE.get(typ, 0.4))
	_balken(
		wurzel,
		Vector3(0.0, 0.045, 0.0),
		Vector3(maxf(1.0, breite + 0.5), 0.02, 3.6),
		Color(0.72, 0.6, 0.42),
		false
	)
	# "Kipp" trägt den Hindernis-Körper — beim Abwurf kippt NUR er, nicht
	# der Boden-Anker und nicht die Ständer.
	var kipp := Node3D.new()
	kipp.name = "Kipp"
	wurzel.add_child(kipp)
	match typ:
		"hecke":
			_balken(kipp, Vector3(0.0, 0.36, 0.0), Vector3(breite, 0.72, 3.0), Color("4F9A40"))
			for k in 3:
				var kuppe := MeshInstance3D.new()
				var kuppe_mesh := SphereMesh.new()
				kuppe_mesh.radius = 0.3
				kuppe_mesh.height = 0.6
				kuppe_mesh.radial_segments = 8
				kuppe_mesh.rings = 4
				kuppe.mesh = kuppe_mesh
				kuppe.material_override = RanchPferd.material(Color("5FAE4C"))
				kuppe.position = Vector3(0.0, 0.74, -1.0 + float(k))
				kuppe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				kipp.add_child(kuppe)
		"wasser":
			_balken(kipp, Vector3(0.0, 0.05, 0.0), Vector3(breite, 0.1, 3.2), Color("3E93D4"))
			_balken(
				kipp,
				Vector3(breite * 0.18, 0.11, 0.0),
				Vector3(breite * 0.5, 0.02, 2.9),
				Color("7CC0EA"),
				false
			)
			_balken(kipp, Vector3(-breite * 0.5, 0.3, 0.0), Vector3(0.08, 0.6, 3.2), Deko.CREME)
		"oxer":
			_streifen_stange(kipp, -breite * 0.5, 0.62, Deko.FAHNEN[0])
			_streifen_stange(kipp, breite * 0.5, 0.78, Deko.FAHNEN[1])
		_:
			_streifen_stange(kipp, 0.0, 0.7, Color("D9564E"))
	for seite: float in [-1.0, 1.0]:
		_balken(wurzel, Vector3(0.0, 0.55, seite * 1.7), Vector3(0.18, 1.1, 0.18), Deko.HOLZ)
		var wimpel := MeshInstance3D.new()
		var wimpel_mesh := PrismMesh.new()
		wimpel_mesh.size = Vector3(0.3, 0.34, 0.05)
		wimpel.mesh = wimpel_mesh
		wimpel.material_override = RanchPferd.material(Deko.FAHNEN[2])
		wimpel.position = Vector3(0.0, 1.25, seite * 1.7)
		wimpel.rotation.x = PI
		wimpel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wurzel.add_child(wimpel)
	return wurzel


## Turnier-Stange mit 5 Farbwechsel-Segmenten (weiß/farbig) — die klassische
## Springreit-Optik macht Höhe und Lage der Stange auf einen Blick lesbar.
func _streifen_stange(parent: Node3D, at_x: float, hoehe: float, farbe: Color) -> void:
	var segment := 3.4 / 5.0
	for s in 5:
		_balken(
			parent,
			Vector3(at_x, hoehe, -1.7 + (float(s) + 0.5) * segment),
			Vector3(0.13, 0.13, segment),
			Deko.CREME if s % 2 == 0 else farbe,
			false
		)


func _balken(
	parent: Node3D, pos: Vector3, groesse: Vector3, farbe: Color, schatten := true
) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mi.mesh = mesh
	mi.material_override = RanchPferd.material(farbe)
	mi.position = pos
	if not schatten:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _build_reiter() -> void:
	_reiter = Node3D.new()
	_welt.add_child(_reiter)
	_pferd = RanchPferd.neu(Color("#D9A066"), Color("#8A5A33"))
	_pferd.rotation.y = PI * 0.5
	_reiter.add_child(_pferd)
	_gooby = GoobyActorScript.new()
	_gooby.position = Vector3(0.0, 1.32, -0.1)
	_gooby.rotation.y = PI * 0.5
	_pferd.add_child(_gooby)
	_gooby.call("mount", 0.62, 0.0, "idle")
	_staub = _build_staub()
	_reiter.add_child(_staub)


## Absprung-Marker: flacher Glüh-Ring auf der Ideallinie. Er liegt am
## rechnerisch besten Absprungpunkt (Bogenmitte über dem nächsten Hindernis)
## und pulst gold, sobald ein Sprung JETZT das Hindernis sicher nimmt.
func _build_sprung_marker() -> void:
	_sprung_marker = Node3D.new()
	_sprung_marker.visible = false
	_welt.add_child(_sprung_marker)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.62
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.albedo_color = Color(1.0, 0.84, 0.35)
	_marker_mat.emission_enabled = true
	_marker_mat.emission = Color(1.0, 0.78, 0.3)
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = _marker_mat
	ring.position = Vector3(0.0, 0.1, 0.0)
	ring.scale = Vector3(1.0, 0.22, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sprung_marker.add_child(ring)


func _build_staub() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 20
	particles.lifetime = 0.6
	particles.emitting = false
	particles.local_coords = false
	particles.position = Vector3(-0.7, 0.1, 0.0)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(-0.6, 1.0, 0.0)
	mat.spread = 30.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.3
	mat.gravity = Vector3(0.0, -0.4, 0.0)
	mat.scale_min = 0.5
	mat.scale_max = 1.1
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 6
	mesh.rings = 3
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.8, 0.7, 0.55, 0.5)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh
	return particles


## --------------------------------------------------------------- Simulation


func _step_lauf(delta: float) -> void:
	elapsed += delta
	var basis := float(kurs.get("tempo", 6.0))
	tempo = Feel.step_tempo(tempo, Logic.lauf_tempo(basis, galopp, tune), delta)
	x += tempo * delta
	if in_luft:
		sprung = Feel.step_sprung(sprung, delta)
		if float(sprung["y"]) <= 0.0:
			in_luft = false
			AudioDirector.try_play(self, "mg_good", 0.8)
	_pruefe_hindernisse()
	if x >= float(kurs.get("laenge_m", 200.0)):
		_lauf_geschafft()
		return
	_update_labels()


func _sprung_input() -> void:
	if not level_running or in_luft or not is_active():
		return
	if not Feel.kann_springen(tempo, float(sprung["y"])):
		return
	sprung = {"y": 0.001, "vy": Feel.SPRUNG_VY}
	in_luft = true
	AudioDirector.try_play(self, "ui_open")
	# Bewertung am Absprungpunkt: erstes offenes Hindernis im Bogenfenster.
	var weite := float(Feel.sprung_daten(tempo)["weite_m"])
	for h: Dictionary in hindernisse:
		if str(h["state"]) != "offen":
			continue
		var mitte := float(h["at"])
		if mitte <= x or mitte > x + weite:
			continue
		h["state"] = Logic.bewerte_sprung(x, tempo, mitte, str(h["typ"]), tune)
		break


## Beim Überqueren der Hindernis-Mitte wird die Wertung fällig; wer am Boden
## durchläuft, reißt (Abwurf).
func _pruefe_hindernisse() -> void:
	for h: Dictionary in hindernisse:
		var mitte := float(h["at"])
		if mitte > x or bool(h.get("gewertet", false)):
			continue
		h["gewertet"] = true
		var state: Variant = h["state"]
		if state is Dictionary and str((state as Dictionary)["qualitaet"]) != "abwurf":
			_sprung_geschafft(h, str((state as Dictionary)["qualitaet"]))
		else:
			_abwurf(h)


func _sprung_geschafft(h: Dictionary, qualitaet: String) -> void:
	var plus := Logic.sprung_punkte(qualitaet, kombo, tune)
	kombo += 1
	punkte += plus
	session_score += plus
	ctx.report_score(session_score, plus)
	AudioDirector.try_play(
		self, "mg_combo" if qualitaet == "perfekt" else "mg_good", 1.0 + 0.02 * mini(kombo, 8)
	)
	if _stage != null and qualitaet == "perfekt":
		# W16 §6: ≤0.4 — mehr pumpte Glow auf die helle Wiese.
		_stage.call("pulse_glow", 0.4)
	_jubel = maxf(_jubel, 2.2)
	if _gooby != null:
		_gooby.call("emote", "ecstatic" if qualitaet == "perfekt" else "happy", 0.9)
	if ctx.juice != null:
		var at := _screen_pos(Vector3(float(h["at"]), 1.6, 0.0))
		var text := (
			I18nService.t("mg.ranchParcours.perfekt")
			if qualitaet == "perfekt"
			else I18nService.t("mg.ranchParcours.gut")
		)
		ctx.juice.float_text(at, "%s +%d" % [text, plus], AcTokens.GOLD)


func _abwurf(h: Dictionary) -> void:
	abwuerfe += 1
	kombo = 0
	strafzeit += float(tune["ABWURF_STRAFE_S"])
	tempo *= float(tune["ABWURF_TEMPO_MULT"])
	AudioDirector.try_play(self, "mg_spill")
	if _stage != null:
		_stage.call("shake", 0.18, 0.3)
	if _gooby != null:
		_gooby.call("emote", "sad", 1.2)
	if ctx.juice != null:
		ctx.juice.hit_freeze(70)
		ctx.juice.float_text(
			_screen_pos(Vector3(float(h["at"]), 1.6, 0.0)),
			I18nService.t("mg.ranchParcours.abwurf"),
			AcTokens.DANGER
		)
	# Optik: der Hindernis-Körper ("Kipp"-Gruppe) kippt und sackt ab.
	var node: Node3D = h["node"]
	if node != null:
		var kipp := node.get_node_or_null("Kipp") as Node3D
		if kipp != null:
			kipp.rotation.x = 0.5
			kipp.position.y = -0.3


func _lauf_geschafft() -> void:
	level_running = false
	var zeit := elapsed + strafzeit
	var par := float(kurs.get("par_s", 60.0))
	var stars := Logic.sterne(abwuerfe, zeit, par)
	var gs := _game_state()
	var first := not RanchSpieleProgress.is_cleared(gs, RanchSpieleProgress.SPIEL_PARCOURS, kurs_id)
	var score := Logic.kurs_score(punkte, Logic.zeitbonus(par, zeit, tune), first, kurs_id)
	RanchSpieleProgress.record_win(gs, RanchSpieleProgress.SPIEL_PARCOURS, kurs_id, stars, score)
	session_score += score - punkte
	ctx.report_score(session_score, score - punkte)
	ctx.report_coin_chunk(int(round(score * _coin_mult(gs))))
	AudioDirector.try_play(self, "mg_win")
	if _stage != null:
		# W16 §6: ≤0.4 — der 0.8er-Puls überstrahlte den Ziel-Moment.
		_stage.call("pulse_glow", 0.4)
	_jubel = 6.0
	if _gooby != null:
		_gooby.call("emote", "ecstatic", 2.0)
		_gooby.call("play_for", "celebrate", 1.6)
	if ctx.juice != null:
		ctx.juice.confetti(70)
		ctx.juice.bloom_pulse(0.6)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 130.0, view_size.y * 0.32),
			I18nService.t("mg.ranchParcours.geschafft", {"stars": stars, "score": score}),
			AcTokens.GOLD
		)
	_ende_timer = 1.6


## Reitplatz-Ausbau gibt einen Coin-Bonus im Parcours (RanchWirtschaft).
func _coin_mult(gs: Object) -> float:
	if gs == null:
		return 1.0
	var wirtschaft: Variant = gs.get_value("ranch.wirtschaft", {})
	if not (wirtschaft is Dictionary):
		return 1.0
	return RanchWirtschaft.parcours_coin_mult(wirtschaft, RanchWirtschaft.load_balance())


## ------------------------------------------------------------------ Optik


func _step_optik(delta: float) -> void:
	if _pferd == null:
		return
	_reiter.position = Vector3(x, float(sprung["y"]), 0.0)
	var gangart := "galopp" if galopp else "trab"
	_pferd.set_gangart(RanchPferd.GANG_GALOPP if galopp else RanchPferd.GANG_TRAB)
	if _gooby != null:
		_gooby.call("tick", delta)
	if in_luft:
		_pferd.rotation.x = clampf(-float(sprung["vy"]) * 0.06, -0.35, 0.35)
	else:
		_pferd.rotation.x = 0.0
	_staub.amount_ratio = maxf(0.05, Feel.staub_anteil(gangart))
	_staub.emitting = not in_luft
	_publikum_animieren(delta)
	_update_sprung_marker()
	_spiele_hufschlaege(delta, gangart)
	_folge_kamera(delta)


## Tribünen-Publikum: Takt-Sway immer, Jubel nach Perfekt/Ziel (M2);
## Reduced Motion lässt nur den Grund-Sway stehen.
func _publikum_animieren(delta: float) -> void:
	if _publikum == null or not is_instance_valid(_publikum):
		return
	_publikum_zeit += delta
	_jubel = maxf(0.0, _jubel - delta)
	var reduced := _stage != null and bool(_stage.call("reduced_motion"))
	RcompArena.publikum_tick(_publikum, _publikum_zeit, 0.0 if reduced else minf(1.0, _jubel))


## Marker nachführen: nächstes offenes Hindernis, Ideal-Absprung aus dem
## AKTUELLEN Tempo (Bogenmitte = Hindernismitte). Gold + Puls, solange ein
## Sprung jetzt sicher wäre; creme-neutral, solange man noch zu weit weg ist.
func _update_sprung_marker() -> void:
	if _sprung_marker == null:
		return
	var h := _naechstes_hindernis()
	var weite := float(Feel.sprung_daten(tempo)["weite_m"])
	if h.is_empty() or in_luft or weite <= 0.0:
		_sprung_marker.visible = false
		return
	var mitte := float(h["at"])
	var ideal := mitte - weite * 0.5
	if ideal - x > 26.0:
		_sprung_marker.visible = false
		return
	_sprung_marker.visible = true
	_sprung_marker.position = Vector3(ideal, 0.0, 0.0)
	var wertung := Logic.bewerte_sprung(x, tempo, mitte, str(h["typ"]), tune)
	var springbar := (
		str(wertung["qualitaet"]) != "abwurf" and Feel.kann_springen(tempo, float(sprung["y"]))
	)
	if _marker_mat == null:
		return
	if springbar:
		var puls := 0.5 + 0.5 * sin(elapsed * 10.0)
		_marker_mat.albedo_color = Color(1.0, 0.84, 0.3)
		_marker_mat.emission = Color(1.0, 0.75, 0.25)
		_sprung_marker.scale = Vector3.ONE * (1.0 + 0.14 * puls)
	else:
		_marker_mat.albedo_color = Color(0.95, 0.94, 0.87)
		_marker_mat.emission = Color(0.65, 0.63, 0.55)
		_sprung_marker.scale = Vector3.ONE


## Nächstes noch offenes (nicht angesprungenes) Hindernis vor dem Pferd.
func _naechstes_hindernis() -> Dictionary:
	for h: Dictionary in hindernisse:
		if bool(h.get("gewertet", false)):
			continue
		if not (h["state"] is String) or str(h["state"]) != "offen":
			continue
		if float(h["at"]) < x:
			continue
		return h
	return {}


func _spiele_hufschlaege(delta: float, gangart: String) -> void:
	if in_luft:
		return
	var vorher := huf_phase
	huf_phase = fmod(huf_phase + minf(Feel.schritt_hz(gangart), HUF_SOUND_MAX_HZ) * delta, 1.0)
	var schlaege := Feel.hufschlaege(vorher, huf_phase)
	if huf_phase < vorher:
		schlaege = Feel.hufschlaege(vorher, 1.0) + Feel.hufschlaege(0.0, huf_phase)
	if schlaege > 0:
		# Hufschläge über SfxMap-Bestand (eigene Ids bei W4-P1 angefragt).
		var id := "door_knock" if galopp else "ui_tick"
		AudioDirector.try_play(self, id, 1.0 + randf_range(-0.04, 0.04))


func _folge_kamera(delta: float) -> void:
	var ziel := Vector3(x - KAMERA_HINTEN, KAMERA_HOEHE, KAMERA_SEITE * -1.0)
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return
	var f := Feel.cam_follow_factor(delta)
	cam.position = cam.position.lerp(ziel, f)
	cam.look_at(Vector3(x + 4.0, 1.0, 0.0), Vector3.UP)
	_stage.set("_cam_base", cam.transform)
	_stage.call("set_fov", Feel.fov_fuer_tempo(tempo) * 0.86)


func _snap_kamera() -> void:
	_stage.call(
		"aim", Vector3(x - KAMERA_HINTEN, KAMERA_HOEHE, -KAMERA_SEITE), Vector3(x + 4.0, 1.0, 0.0)
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
	_punkte_label = Label.new()
	_punkte_label.theme_type_variation = &"CaptionLabel"
	_hud.add_child(_punkte_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.ranchParcours.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_hint_label)
	_galopp_btn = Button.new()
	_galopp_btn.toggle_mode = true
	_galopp_btn.text = I18nService.t("mg.ranchParcours.galopp")
	_galopp_btn.custom_minimum_size = Vector2(150, 64)
	_galopp_btn.toggled.connect(func(an: bool) -> void: galopp = an)
	_hud.add_child(_galopp_btn)
	_sprung_btn = Button.new()
	_sprung_btn.text = I18nService.t("mg.ranchParcours.sprung")
	_sprung_btn.custom_minimum_size = Vector2(150, 64)
	_sprung_btn.pressed.connect(_sprung_input)
	_hud.add_child(_sprung_btn)
	for btn: Button in [_galopp_btn, _sprung_btn]:
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_hud()
	_update_labels()


func _layout_hud() -> void:
	if _zeit_label == null:
		return
	_zeit_label.position = Vector2(16.0, 10.0)
	_punkte_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(view_size.x * 0.5 - 170.0, 12.0)
	_hint_label.size = Vector2(340.0, 34.0)
	_galopp_btn.position = Vector2(18.0, view_size.y - 82.0)
	_sprung_btn.position = Vector2(view_size.x - 168.0, view_size.y - 82.0)


func _update_labels() -> void:
	if _zeit_label == null:
		return
	_zeit_label.text = I18nService.t("mg.ranchParcours.zeit", {"s": "%.1f" % (elapsed + strafzeit)})
	_punkte_label.text = I18nService.t("mg.ranchParcours.punkte", {"n": punkte, "kombo": kombo})


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or not level_running:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_sprung_input()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_active() or finished or not level_running:
		return
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			if key.pressed:
				_sprung_input()
		KEY_UP, KEY_W:
			galopp = key.pressed
			if _galopp_btn != null:
				_galopp_btn.button_pressed = key.pressed
