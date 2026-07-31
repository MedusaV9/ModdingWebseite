extends MinigameBase
## Schaf-Hüten (ranchHerde) — Spiel-Szene (RANCH-2). Gooby reitet sein
## Ranch-Pferd und treibt eine Boids-Herde durch das Tor in den Pferch,
## bevor die Zeit abläuft. Die GESAMTE Herden-Simulation kommt 1:1 aus
## RanchHerdeLogic (Bot-zertifiziert, deterministisch); diese Szene mappt
## nur Zustand → 3D und Zeigefinger → Reiter-Ziel (Tippen/Ziehen aufs Feld,
## alternativ Pfeiltasten). 10 Level aus data/herde_level.json, Auswahl über
## RanchLevelSelect, Fortschritt in `ranch.spiele.herde`.
##
## W15/GAMESQA2-Steuergefühl (Audit d=3, "wenig Juice"): der FLUCHT_RADIUS
## ist jetzt als Boden-Ring am Pferd SICHTBAR (Schafe im Ring fliehen — das
## Warum wird lesbar), jeder Tipp setzt eine Zielfahne mit Aufsetz-Puls,
## Pfeiltasten steuern KONTINUIERLICH (Polling statt Key-Events) und
## treib_ziel() vergibt Forgiveness: ein Tipp AUF ein Schaf springt auf den
## Treibpunkt HINTER dem Schaf (vom Tor aus gesehen — die Bot-Politik als
## Eingabehilfe). Dazu Galopp-Staub. Sim/Logic unverändert.

const Stage3DScript := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const GoobyActorScript := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Logic := preload("res://scripts/minigames/games/ranch_herde/herde_logic.gd")

const WOLLE := Color(0.96, 0.94, 0.88)
const WOLLE_HELL := Color(0.99, 0.97, 0.93)
const GESICHT := Color(0.45, 0.38, 0.33)
const ZAUN := Color(0.72, 0.53, 0.36)
const TOR_FARBE := Color(0.93, 0.72, 0.35)

## Ranch-Farbkanon (wie ranch_parcours/RcompArena): die Minispiele teilen
## die Optik des Turnierplatzes — Holzzaun, Creme-Latten, Wimpel-Farben.
const GRAS_DUNKEL := Color(0.36, 0.56, 0.29)
const HOLZ_DUNKEL := Color(0.55, 0.38, 0.24)
const CREME := Color(0.95, 0.94, 0.87)
const FAHNEN: Array[Color] = [
	Color(0.91, 0.55, 0.63), Color(0.37, 0.66, 0.63), Color(0.95, 0.69, 0.3)
]

## W15: Tipp-Nähe (m), ab der ein Tipp als „dieses Schaf treiben" gilt.
const TREIB_RADIUS := 1.7
## Treibpunkt-Abstand hinter dem Schaf (wie die Bot-Politik ±).
const TREIB_ABSTAND := 2.4

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
var _einfluss_ring: MeshInstance3D
var _ziel_fahne: Node3D
var _ziel_puls := 0.0
var _staub: GPUParticles3D


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
	_poll_tasten()
	_step_sim(delta)
	_step_optik(delta)


## W15: Pfeiltasten/WASD werden PRO FRAME gepollt (vorher nur Key-Events) —
## gedrückt halten lenkt jetzt kontinuierlich, das Ziel klebt am Reiter.
func _poll_tasten() -> void:
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
		_zeige_ziel_fahne(false)


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
	_einfluss_ring = null
	_ziel_fahne = null
	_staub = null


func _build_welt() -> void:
	_stage = Stage3DScript.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				"sky_top": Color(0.47, 0.7, 0.94),
				"sky_horizon": Color(0.88, 0.94, 0.97),
				"ground_horizon": Color(0.56, 0.73, 0.44),
				"ground_bottom": Color(0.4, 0.56, 0.33),
				# Belichtung GEZÄHMT (bekannte Falle: Stage-Defaults 1.2/0.6
				# strahlen die voll besonnte Draufsicht ~40 Luma-Stufen aus).
				"sun_energy": 0.8,
				"ambient": 0.38,
				"fill_energy": 0.24,
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
	gras_mesh.size = Vector3(hx * 2.0 + 16.0, 0.3, hz * 2.0 + 16.0)
	gras.mesh = gras_mesh
	# Dunkler als das Reit-Gras: die Draufsicht-Kamera sieht die voll
	# besonnte Oberseite, hellere Töne kippen im ACES-Tonemapping ins Weiße.
	gras.material_override = RanchPferd.material(Color(0.42, 0.63, 0.33))
	gras.position = Vector3(0.0, -0.15, 0.0)
	_welt.add_child(gras)
	# Ranch-Feldzaun: Creme-Latten (2 Höhen je Seite) + EIN Pfosten-MultiMesh
	# — dieselbe Optik wie Parcours/Turnierplatz statt vier nackter Riegel.
	for hoehe: float in [0.34, 0.68]:
		for wand: Array in [
			[Vector3(0.0, hoehe, -hz), Vector3(hx * 2.0 + 0.2, 0.09, 0.07)],
			[Vector3(0.0, hoehe, hz), Vector3(hx * 2.0 + 0.2, 0.09, 0.07)],
			[Vector3(-hx, hoehe, 0.0), Vector3(0.07, 0.09, hz * 2.0 + 0.2)],
			[Vector3(hx, hoehe, 0.0), Vector3(0.07, 0.09, hz * 2.0 + 0.2)],
		]:
			var latte := MeshInstance3D.new()
			var latte_mesh := BoxMesh.new()
			latte_mesh.size = wand[1]
			latte.mesh = latte_mesh
			latte.material_override = RanchPferd.material(CREME)
			latte.position = wand[0]
			latte.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_welt.add_child(latte)
	_build_zaunpfosten(hx, hz)
	_build_wiese_deko(hx, hz)
	_build_tribuene(hx, hz)


## Zaunpfosten rund ums Feld als EIN MultiMesh (1 Draw-Call).
func _build_zaunpfosten(hx: float, hz: float) -> void:
	var plaetze: Array[Vector3] = []
	var schritt := 3.0
	var nx := maxi(2, int(hx * 2.0 / schritt))
	var nz := maxi(2, int(hz * 2.0 / schritt))
	for i in nx + 1:
		var at_x := -hx + float(i) * hx * 2.0 / float(nx)
		plaetze.append(Vector3(at_x, 0.4, -hz))
		plaetze.append(Vector3(at_x, 0.4, hz))
	for i in nz - 1:
		var at_z := -hz + float(i + 1) * hz * 2.0 / float(nz)
		plaetze.append(Vector3(-hx, 0.4, at_z))
		plaetze.append(Vector3(hx, 0.4, at_z))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.14, 0.85, 0.14)
	var pfosten := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = plaetze.size()
	for i in plaetze.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, plaetze[i]))
	pfosten.multimesh = mm
	pfosten.material_override = RanchPferd.material(HOLZ_DUNKEL)
	_welt.add_child(pfosten)


## Wiesen-Struktur: dunklere Grasflecken IM Feld, Blumen + Bäume mit Stamm
## AUSSEN — alles MultiMesh (4 Draw-Calls gesamt).
func _build_wiese_deko(hx: float, hz: float) -> void:
	var rng := ctx.rng(613)
	var flecken := MultiMeshInstance3D.new()
	var fmm := MultiMesh.new()
	fmm.transform_format = MultiMesh.TRANSFORM_3D
	var scheibe := CylinderMesh.new()
	scheibe.top_radius = 0.5
	scheibe.bottom_radius = 0.5
	scheibe.height = 0.04
	scheibe.radial_segments = 8
	fmm.mesh = scheibe
	fmm.instance_count = 26
	for i in 26:
		var s := 0.7 + rng.next() * 1.6
		fmm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(s, 1.0, s * (0.6 + rng.next() * 0.5))),
				Vector3(
					(rng.next() * 2.0 - 1.0) * (hx - 1.0),
					0.005,
					(rng.next() * 2.0 - 1.0) * (hz - 1.0)
				)
			)
		)
	flecken.multimesh = fmm
	flecken.material_override = RanchPferd.material(GRAS_DUNKEL)
	flecken.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_welt.add_child(flecken)
	var blumen := MultiMeshInstance3D.new()
	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	var tupfer := SphereMesh.new()
	tupfer.radius = 0.09
	tupfer.height = 0.18
	tupfer.radial_segments = 6
	tupfer.rings = 3
	bmm.mesh = tupfer
	bmm.instance_count = 18
	for i in 18:
		var rand_x := (hx + 0.8 + rng.next() * 4.0) * (-1.0 if i % 2 == 0 else 1.0)
		bmm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(rand_x, 0.08, (rng.next() * 2.0 - 1.0) * hz))
		)
	blumen.multimesh = bmm
	blumen.material_override = RanchPferd.material(Color(0.97, 0.9, 0.72))
	blumen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_welt.add_child(blumen)
	# Bäume außen: Kronen + Stämme (je EIN MultiMesh, identische Plätze).
	var plaetze: Array[Vector3] = []
	var groessen: Array[float] = []
	for i in 10:
		var seite := -1.0 if i % 2 == 0 else 1.0
		plaetze.append(
			Vector3(
				(rng.next() * 2.0 - 1.0) * (hx + 5.0), 0.0, seite * (hz + 2.5 + rng.next() * 4.0)
			)
		)
		groessen.append(0.7 + rng.next() * 0.5)
	var kronen := MultiMeshInstance3D.new()
	var kmm := MultiMesh.new()
	kmm.transform_format = MultiMesh.TRANSFORM_3D
	var kugel := SphereMesh.new()
	kugel.radius = 1.4
	kugel.height = 2.8
	kugel.radial_segments = 12
	kugel.rings = 6
	kmm.mesh = kugel
	kmm.instance_count = plaetze.size()
	for i in plaetze.size():
		kmm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * groessen[i]),
				plaetze[i] + Vector3(0.0, 1.2 + groessen[i], 0.0)
			)
		)
	kronen.multimesh = kmm
	kronen.material_override = RanchPferd.material(Color(0.36, 0.6, 0.36))
	kronen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_welt.add_child(kronen)
	var staemme := MultiMeshInstance3D.new()
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	var stamm := CylinderMesh.new()
	stamm.top_radius = 0.13
	stamm.bottom_radius = 0.17
	stamm.height = 1.6
	stamm.radial_segments = 6
	smm.mesh = stamm
	smm.instance_count = plaetze.size()
	for i in plaetze.size():
		smm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * groessen[i]),
				plaetze[i] + Vector3(0.0, 0.8 * groessen[i], 0.0)
			)
		)
	staemme.multimesh = smm
	staemme.material_override = RanchPferd.material(HOLZ_DUNKEL)
	staemme.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_welt.add_child(staemme)


## Kleine Tribüne mit Publikum hinter der Nord-Seite — Zuschauer fürs
## Hüte-Turnier, dieselbe Bauweise wie beim Parcours. Sie weicht dem Pferch
## seitlich aus (steht sonst optisch AUF dem Pferch, beide sind mittig).
func _build_tribuene(hx: float, hz: float) -> void:
	var p := Logic.pferch_rect(level)
	var seite := 1.0 if float(p["x"]) <= 0.0 else -1.0
	var wurzel := Node3D.new()
	wurzel.position = Vector3(seite * hx * 0.55, 0.0, -hz - 2.2)
	_welt.add_child(wurzel)
	for stufe in 2:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(7.0, 0.5, 1.05)
		box.mesh = mesh
		box.material_override = RanchPferd.material(ZAUN if stufe % 2 == 0 else HOLZ_DUNKEL)
		box.position = Vector3(0.0, 0.27 + float(stufe) * 0.5, -float(stufe) * 1.05)
		wurzel.add_child(box)
	var kugel := SphereMesh.new()
	kugel.radius = 0.3
	kugel.height = 0.6
	kugel.radial_segments = 8
	kugel.rings = 4
	var publikum := MultiMeshInstance3D.new()
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = kugel
	pmm.instance_count = 8
	var rng := ctx.rng(227)
	for i in 8:
		var reihe := i % 2
		pmm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY,
				Vector3(
					-2.8 + float(i / 2) * 1.9 + rng.next() * 0.8,
					0.85 + float(reihe) * 0.5,
					-float(reihe) * 1.05 + rng.next() * 0.25
				)
			)
		)
	publikum.multimesh = pmm
	publikum.material_override = RanchPferd.material(Color(0.98, 0.83, 0.55))
	publikum.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(publikum)


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
	# Torpfosten in Signalfarbe + Wimpelkette darüber: das Tor ist DIE
	# Zielmarke des Spiels und muss aus der Draufsicht sofort ins Auge fallen.
	for seite: float in [-1.0, 1.0]:
		_balken(Vector3(px + seite * tor * 0.5, 0.8, sued_z), Vector3(0.24, 1.6, 0.24), TOR_FARBE)
	_wimpel_kette(Vector3(px - tor * 0.5, 1.65, sued_z), Vector3(px + tor * 0.5, 1.65, sued_z))


## Wimpelkette zwischen zwei Punkten: EIN MultiMesh mit Instanzfarben aus
## dem Ranch-Fahnenkanon, leicht durchhängend (wie beim Parcours).
func _wimpel_kette(from: Vector3, to: Vector3) -> void:
	var count := maxi(4, int(from.distance_to(to) / 0.6))
	var prisma := PrismMesh.new()
	prisma.size = Vector3(0.3, 0.36, 0.04)
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = true
	prisma.material = mat
	var kette := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = prisma
	mm.instance_count = count
	var flip := Basis(Vector3.RIGHT, PI)
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var at := from.lerp(to, t) + Vector3(0.0, -sin(t * PI) * 0.22, 0.0)
		mm.set_instance_transform(i, Transform3D(flip, at))
		mm.set_instance_color(i, FAHNEN[i % FAHNEN.size()])
	kette.multimesh = mm
	kette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_welt.add_child(kette)


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
	_build_einfluss_ring()
	_build_staub()
	_build_ziel_fahne()


## W15: der Flucht-Radius als flacher Boden-Ring am Pferd — Schafe IM Ring
## fliehen, das „Warum reagiert das Schaf nicht?" wird damit sichtbar.
func _build_einfluss_ring() -> void:
	_einfluss_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	var radius := float(tune["FLUCHT_RADIUS"])
	torus.inner_radius = radius - 0.14
	torus.outer_radius = radius
	torus.rings = 48
	torus.ring_segments = 6
	_einfluss_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.98, 0.9, 0.34)
	_einfluss_ring.material_override = mat
	_einfluss_ring.position = Vector3(0.0, 0.05, 0.0)
	_einfluss_ring.scale = Vector3(1.0, 0.03, 1.0)
	_einfluss_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pferd.add_child(_einfluss_ring)


## W15: Galopp-Staub hinter den Hufen (aus, solange das Pferd steht).
func _build_staub() -> void:
	_staub = GPUParticles3D.new()
	_staub.amount = 14
	_staub.lifetime = 0.55
	_staub.emitting = false
	_staub.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, -1.0)
	pm.spread = 24.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.0, -1.2, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	_staub.process_material = pm
	var puff := SphereMesh.new()
	puff.radius = 0.09
	puff.height = 0.18
	puff.radial_segments = 6
	puff.rings = 3
	_staub.draw_pass_1 = puff
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.87, 0.8, 0.68, 0.5)
	puff.material = mat
	_staub.position = Vector3(0.0, 0.12, -0.7)
	_pferd.add_child(_staub)


## W15: Zielfahne — zeigt, WOHIN das Pferd gerade reitet (mit Aufsetz-Puls).
func _build_ziel_fahne() -> void:
	_ziel_fahne = Node3D.new()
	_ziel_fahne.visible = false
	_welt.add_child(_ziel_fahne)
	var stab := MeshInstance3D.new()
	var stab_mesh := CylinderMesh.new()
	stab_mesh.top_radius = 0.035
	stab_mesh.bottom_radius = 0.035
	stab_mesh.height = 0.9
	stab_mesh.radial_segments = 6
	stab.mesh = stab_mesh
	stab.material_override = RanchPferd.material(HOLZ_DUNKEL)
	stab.position = Vector3(0.0, 0.45, 0.0)
	stab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ziel_fahne.add_child(stab)
	var tuch := MeshInstance3D.new()
	var tuch_mesh := PrismMesh.new()
	tuch_mesh.size = Vector3(0.42, 0.3, 0.03)
	tuch.mesh = tuch_mesh
	tuch.material_override = RanchPferd.material(TOR_FARBE)
	tuch.position = Vector3(0.2, 0.78, 0.0)
	tuch.rotation = Vector3(PI, 0.0, PI * 0.5)
	tuch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ziel_fahne.add_child(tuch)
	var puls := MeshInstance3D.new()
	puls.name = "Puls"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.32
	ring.outer_radius = 0.45
	ring.rings = 24
	ring.ring_segments = 6
	puls.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.55, 0.8)
	puls.material_override = mat
	puls.position = Vector3(0.0, 0.05, 0.0)
	puls.scale = Vector3(1.0, 0.05, 1.0)
	puls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ziel_fahne.add_child(puls)


## Billige Puschel-Schafe (7 Meshes, Kleinteile ohne Schatten) — bewusst
## eigener Bau statt RanchTier: 12 Schafe müssen ins Draw-Call-Budget.
## PERSÖNLICHKEIT ohne Extra-Meshes: die beim Spawn gewürfelte Schaf-Phase
## bestimmt Größe (kleine Flitzer, dicke Brocken), Wollton (jedes 5. Schaf
## ist ein dunkles) und den Charakter der Kopf-Animation in _step_optik.
func _build_schafe() -> void:
	_schaf_nodes = []
	var index := 0
	for s: Variant in schafe:
		var phase := float((s as Dictionary)["phase"])
		var wurzel := Node3D.new()
		wurzel.position = Vector3(float((s as Dictionary)["x"]), 0.0, float((s as Dictionary)["z"]))
		wurzel.scale = Vector3.ONE * (0.88 + 0.24 * (0.5 + 0.5 * sin(phase * 3.1)))
		_welt.add_child(wurzel)
		_schaf_nodes.append(wurzel)
		var dunkel := index % 5 == 4
		var wolle := Color(0.42, 0.38, 0.36) if dunkel else WOLLE.darkened(0.06 * sin(phase))
		var schopf := Color(0.5, 0.46, 0.44) if dunkel else WOLLE_HELL
		_kugel(wurzel, Vector3(0.0, 0.48, 0.0), Vector3(0.42, 0.36, 0.5), wolle, true)
		_kugel(wurzel, Vector3(0.0, 0.66, -0.12), Vector3(0.22, 0.17, 0.22), schopf, false)
		var kopf := Node3D.new()
		kopf.name = "Kopf"
		kopf.position = Vector3(0.0, 0.58, 0.44)
		wurzel.add_child(kopf)
		_kugel(kopf, Vector3.ZERO, Vector3(0.17, 0.17, 0.18), GESICHT.lightened(0.35), false)
		_kugel(kopf, Vector3(0.0, 0.13, -0.04), Vector3(0.14, 0.09, 0.12), wolle, false)
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
		index += 1


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
	if _gooby != null:
		_gooby.call("emote", "happy", 0.8)
	if ctx.juice != null:
		var tor := Logic.tor_pos(level)
		ctx.juice.float_text(
			_screen_pos(Vector3(tor.x, 1.4, tor.y)),
			"+1  %d/%d" % [drin, schafe.size()],
			AcTokens.LEAF_DARK
		)
		ctx.juice.scale_pop(_drin_label, 1.3)


func _level_geschafft() -> void:
	level_running = false
	# Endstand anzeigen: der Sim-Schritt bricht VOR _update_labels ab, sonst
	# bliebe der Zähler auf dem Stand vor dem letzten Schaf stehen.
	_update_labels()
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
	if _gooby != null:
		_gooby.call("emote", "ecstatic", 2.0)
		_gooby.call("play_for", "celebrate", 1.6)
	if ctx.juice != null:
		ctx.juice.confetti(70)
		ctx.juice.bloom_pulse(0.6)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 130.0, view_size.y * 0.32),
			I18nService.t("mg.ranchHerde.geschafft", {"stars": stars, "score": score}),
			AcTokens.GOLD
		)
	_ende_timer = 1.6


func _zeit_um() -> void:
	level_running = false
	_update_labels()
	AudioDirector.try_play(self, "mg_lose")
	if _gooby != null:
		_gooby.call("emote", "sad", 1.6)
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
	if _staub != null:
		_staub.emitting = bewegung > float(tune["REITER_TEMPO"]) * 0.5
	if _einfluss_ring != null:
		# Sanfter Atem-Puls: der Ring lebt, ohne zu blinken.
		var puls := 1.0 + 0.025 * sin(t_abs * 2.4)
		_einfluss_ring.scale = Vector3(puls, 0.03, puls)
	_tick_ziel_fahne(delta)
	if _gooby != null:
		_gooby.call("tick", delta)


## Zielfahne einblenden/pulsen lassen; erreicht das Pferd sie, sinkt sie weg.
func _zeige_ziel_fahne(puls: bool) -> void:
	if _ziel_fahne == null:
		return
	_ziel_fahne.visible = true
	_ziel_fahne.position = Vector3(ziel.x, 0.0, ziel.y)
	if puls:
		_ziel_puls = 1.0


func _tick_ziel_fahne(delta: float) -> void:
	if _ziel_fahne == null or not _ziel_fahne.visible:
		return
	_ziel_puls = maxf(0.0, _ziel_puls - delta * 2.6)
	var ring := _ziel_fahne.get_node_or_null("Puls") as MeshInstance3D
	if ring != null:
		var s := 1.0 + (1.0 - _ziel_puls) * 1.6
		ring.scale = Vector3(s, 0.05, s)
		ring.visible = _ziel_puls > 0.0
	if reiter.distance_to(ziel) < 0.6:
		_ziel_fahne.visible = false
	for i in mini(schafe.size(), _schaf_nodes.size()):
		var s: Dictionary = schafe[i]
		var node := _schaf_nodes[i]
		node.position = Vector3(float(s["x"]), 0.0, float(s["z"]))
		var vel := Vector2(float(s["vx"]), float(s["vz"]))
		var speed := vel.length()
		if speed > 0.2:
			node.rotation.y = atan2(vel.x, vel.y)
		# Puschel-Hoppeln: kleine Hüpfer nach Schaf-Phase + Tempo.
		node.position.y = absf(sin(t_abs * 6.0 + float(s["phase"]))) * 0.06 * minf(1.0, speed)
		_schaf_kopf(node, s, speed)


## Kopf-Animation = Persönlichkeit: gemütliche Schafe grasen (Kopf unten),
## schreckhafte reißen den Kopf hoch und zittern beim Flüchten, drin-Schafe
## nicken zufrieden im Takt.
func _schaf_kopf(node: Node3D, s: Dictionary, speed: float) -> void:
	var kopf := node.get_node_or_null("Kopf") as Node3D
	if kopf == null:
		return
	var phase := float(s["phase"])
	if bool(s["drin"]):
		kopf.rotation.x = 0.1 + 0.08 * sin(t_abs * 3.0 + phase)
		kopf.rotation.z = 0.0
		return
	var flucht := clampf(speed / 3.0, 0.0, 1.0)
	# Grasen: langsame Schafe senken den Kopf (je nach Phase verschieden
	# tief — die störrischen fressen einfach weiter).
	var grasen := (0.5 + 0.4 * sin(t_abs * 0.9 + phase * 2.0)) * (1.0 - flucht)
	kopf.rotation.x = lerpf(grasen * 0.7, -0.35, flucht)
	# Schreckhaft: beim Flüchten zittert der Kopf seitlich.
	kopf.rotation.z = sin(t_abs * 14.0 + phase) * 0.12 * flucht


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
			_setze_ziel(touch.position, true)
	elif event is InputEventScreenDrag and _zeiger_unten:
		_setze_ziel((event as InputEventScreenDrag).position, false)


func _setze_ziel(screen: Vector2, tipp: bool) -> void:
	var punkt: Vector3 = _stage.call("plane_point", screen, 0.0)
	# Forgiveness NUR beim Tippen: der Finger meint „dieses Schaf treiben",
	# beim Ziehen lenkt er das Pferd frei.
	ziel = (
		treib_ziel(Vector2(punkt.x, punkt.z), schafe, level) if tipp else Vector2(punkt.x, punkt.z)
	)
	_zeige_ziel_fahne(tipp)


## PURE Eingabehilfe (W15): landet ein Tipp nahe an einem freien Schaf,
## springt das Reit-Ziel auf den Treibpunkt HINTER diesem Schaf (vom Tor aus
## gesehen — dieselbe Politik wie Logic.bot_ziel, inkl. Tor-Korridor-Schutz:
## im Korridor nie nördlich der Torlinie, sonst drückt der Reiter das Schaf
## wieder heraus). Sonst kommt der Tipp-Punkt unverändert zurück.
static func treib_ziel(tipp: Vector2, herde: Array, lvl: Dictionary) -> Vector2:
	var schaf := Vector2.ZERO
	var best := TREIB_RADIUS
	var gefunden := false
	for s: Variant in herde:
		if bool((s as Dictionary)["drin"]):
			continue
		var pos := Vector2(float((s as Dictionary)["x"]), float((s as Dictionary)["z"]))
		var d := tipp.distance_to(pos)
		if d <= best:
			best = d
			schaf = pos
			gefunden = true
	if not gefunden:
		return tipp
	var tor := Logic.tor_pos(lvl)
	var richtung := (schaf - tor).normalized() if schaf != tor else Vector2(0.0, 1.0)
	var ziel_neu := schaf + richtung * TREIB_ABSTAND
	var p := Logic.pferch_rect(lvl)
	if absf(schaf.x - float(p["x"])) < float(p["tor"]) * 0.5 + 1.0:
		ziel_neu.y = maxf(ziel_neu.y, float(p["z"]) + float(p["t"]) * 0.5 + 0.6)
	return ziel_neu
