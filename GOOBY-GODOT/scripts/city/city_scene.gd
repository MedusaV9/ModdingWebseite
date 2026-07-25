class_name CityScene
extends Node3D
## Stadt-Szene (W3a CITY, Doc E §1): baut die komplette Stadt PROZEDURAL aus
## city_map.json (Kenney-Kits nach Karte, Muster cityBuilder.js): Straßen aus
## Nachbarschaft, Orte mit Fassaden-Tint + Markise + Parkplatz-Trigger,
## Deko-Gebäude, geseedete Bäume (Seed variiert NUR Deko), Tageszeit-Licht,
## 3 Ambient-Loop-Autos. FREIE FAHRT: Energie-Abzug ERST beim Betreten eines
## Orts; „Nach Hause“ ist IMMER kostenlos.
##
## Router-Contract (W1a): `ready_for_reveal` nach dem Aufbau;
## `receive_params({"spawn": "zuhause"|"<ort_id>"})`. Tests injizieren
## `game_state_override` VOR add_child (Muster W2a RoomBase).

signal ready_for_reveal
signal ort_betreten_angefordert(ort_id: String)

const ASSETS := "res://assets/city"
const ROUTE_CITY := &"city"

## Distrikt-Grundfarben für Boden-Pads unter den Vierteln (dezent).
const DISTRIKT_FARBEN := {
	"gewerbe": Color(0.82, 0.80, 0.74),
	"zentrum": Color(0.85, 0.81, 0.72),
	"wohnen": Color(0.78, 0.82, 0.70),
	"park": Color(0.62, 0.78, 0.55),
	"flughafen": Color(0.80, 0.80, 0.82),
}

var game_state_override: Object
## Tests/Screenshots erzwingen eine Uhrzeit (< 0 = echte Systemzeit).
var stunde_override := -1.0

var karte: CityMap
var graph: CityRoadGraph
var auto: CarController
var cam: ChaseCam
var hud: DriveHud

var _verkehr: Array[Dictionary] = []
var _prompt_ort := ""
var _toast: Node
var _colliders: Array[Dictionary] = []
var _licht_profil: Dictionary = {}
var _sfx_timer := 6.0


func _ready() -> void:
	karte = CityMap.laden()
	graph = CityRoadGraph.aus_karte(karte)
	_licht_profil = CityAmbiente.licht_profil(_stunde())
	_baue_licht()
	_baue_boden()
	_baue_strassen()
	_baue_laternen()
	_baue_orte()
	_baue_deko()
	_baue_natur()
	_baue_verkehr()
	_baue_auto()
	_baue_hud()
	ready_for_reveal.emit()


func _process(delta: float) -> void:
	_update_verkehr(delta)
	_update_ambient_sfx(delta)


func _physics_process(_delta: float) -> void:
	_update_parkplatz()


## Router-Params (W1a-Contract): spawn = "zuhause" oder Ort-Id.
func receive_params(params: Dictionary) -> void:
	var spawn := str(params.get("spawn", ""))
	if not spawn.is_empty():
		_spawn_bei.call_deferred(spawn)


## Routen fürs SceneRouter-Setup (Orchestrator ruft das einmal beim Boot).
static func register_routes(router: Object) -> void:
	router.register_route(ROUTE_CITY, "res://scenes/city/city_scene.tscn")
	for eintrag: Dictionary in CityMap.laden().orte():
		var szene := str(eintrag.get("szene", ""))
		if not szene.is_empty():
			router.register_route(StringName("city/ort/%s" % eintrag.get("id")), szene)


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func now_ms() -> int:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## ---------------------------------------------------------------- Aufbau


## Uhrzeit mit Bruchteilen (Tests/Screenshots setzen stunde_override).
func _stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0


## Tag/Nacht-Licht (W4-P3 POLISH-8): komplette 24-h-Kurve aus CityAmbiente
## — nachts fahler Mond, dunkler Himmel, Laternen + Autolichter an.
func _baue_licht() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = _licht_profil["himmel_oben"]
	sky_mat.sky_horizon_color = _licht_profil["himmel_horizont"]
	# Boden-Hemisphäre grünlich statt dunkelbraun — sonst steht am Rand der
	# endlichen Bodenplatte ein dunkler Horizont-Balken.
	sky_mat.ground_horizon_color = _licht_profil["boden_horizont"]
	sky_mat.ground_bottom_color = _licht_profil["boden_unten"]
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = _licht_profil["ambient_energie"]
	env.environment = e
	add_child(env)
	var sonne := DirectionalLight3D.new()
	sonne.name = "Sonne"
	sonne.shadow_enabled = true
	sonne.rotation_degrees = Vector3(-float(_licht_profil["elevation"]), -35.0, 0.0)
	sonne.light_color = _licht_profil["sonnen_farbe"]
	sonne.light_energy = _licht_profil["sonnen_energie"]
	add_child(sonne)


func _baue_boden() -> void:
	var boden := MeshInstance3D.new()
	boden.name = "Boden"
	var mesh := PlaneMesh.new()
	var halb := karte.welt_halb()
	mesh.size = Vector2(halb.x * 2.0 + 80.0, halb.y * 2.0 + 80.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.45)
	mesh.material = mat
	boden.mesh = mesh
	add_child(boden)
	# Dezente Distrikt-Pads unter den Vierteln
	for name: String in karte.daten.get("distrikte", {}):
		for zone: Array in karte.daten["distrikte"][name].get("zonen", []):
			var pad := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			var breite := (float(zone[3]) - float(zone[1]) + 1.0) * karte.tile_m
			var tiefe := (float(zone[2]) - float(zone[0]) + 1.0) * karte.tile_m
			pm.size = Vector2(breite, tiefe)
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = DISTRIKT_FARBEN.get(name, Color(0.8, 0.8, 0.8))
			pm.material = pmat
			pad.mesh = pm
			pad.position = karte.welt_von(
				(float(zone[0]) + float(zone[2])) / 2.0, (float(zone[1]) + float(zone[3])) / 2.0
			)
			pad.position.y = 0.05
			add_child(pad)


func _baue_strassen() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Strassen"
	add_child(wurzel)
	for tile in karte.strassen_tiles():
		var glb: String
		var rot := 0
		if karte.ist_kreisel(tile):
			glb = "road-roundabout"
		else:
			var stueck := CityMap.road_piece_for(
				karte.ist_strasse(tile + Vector2i(-1, 0)),
				karte.ist_strasse(tile + Vector2i(0, 1)),
				karte.ist_strasse(tile + Vector2i(1, 0)),
				karte.ist_strasse(tile + Vector2i(0, -1))
			)
			glb = str(stueck["piece"])
			rot = int(stueck["rot_grad"])
		var node := _glb("%s/strassen/%s.glb" % [ASSETS, glb], karte.tile_m)
		if node != null:
			node.position = karte.tile_zu_welt(tile)
			node.rotation_degrees.y = rot
			wurzel.add_child(node)


## Straßenlaternen (W4-P3 POLISH-8): deterministisch auf jedem 3. Straßen-
## Tile (Kenney streetlight); bei Dämmerung/Nacht kriegt der Kopf eine
## warme Emissiv-Birne. Bewusst OHNE echte OmniLights (Mobile-Budget A §7).
func _baue_laternen() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Laternen"
	add_child(wurzel)
	var an: bool = _licht_profil["lichter_an"]
	for tile in karte.strassen_tiles():
		if karte.ist_kreisel(tile) or (tile.x + tile.y) % 3 != 0:
			continue
		var lampe := _glb("%s/deko/streetlight.gltf" % ASSETS, 5.0)
		if lampe == null:
			continue
		var mitte := karte.tile_zu_welt(tile)
		lampe.position = mitte + Vector3(7.0, 0.4, 7.0)
		lampe.rotation_degrees.y = 180.0
		wurzel.add_child(lampe)
		if an:
			var birne := MeshInstance3D.new()
			var kugel := SphereMesh.new()
			kugel.radius = 0.09
			kugel.height = 0.18
			kugel.radial_segments = 8
			kugel.rings = 4
			birne.mesh = kugel
			birne.material_override = CityAmbiente.leuchten_material(Color(1.0, 0.85, 0.55))
			birne.position = Vector3(0.0, _aabb_hoehe(lampe) * 0.94, 0.0)
			lampe.add_child(birne)


## Höhe (lokale Model-Einheiten) des höchsten Meshes unter `node`.
func _aabb_hoehe(node: Node3D) -> float:
	var top := 0.8
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		var aabb := mi.get_aabb()
		var mesh_top := mi.position.y + aabb.position.y + aabb.size.y
		top = maxf(top, mesh_top)
	return top


func _baue_orte() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Orte"
	add_child(wurzel)
	for eintrag: Dictionary in karte.orte():
		var fassade: Dictionary = eintrag.get("fassade", {})
		var tiles: Array = eintrag.get("tiles", [[0, 0]])
		var erste := CityMap._tile_von(tiles[0])
		var strasse := CityMap._tile_von(eintrag.get("strasse", [0, 0]))
		var mitte := karte.tile_zu_welt(erste)
		var glb := str(fassade.get("glb", "building-a"))
		var gebaeude := _glb("%s/gebaeude/%s.glb" % [ASSETS, glb], 10.0)
		if gebaeude != null:
			gebaeude.position = mitte
			# Gebäude stehen NEBEN den 0,4 m dicken Straßenplatten auf dem
			# Distrikt-Pad (y=0,05) — nicht auf Straßenhöhe (schwebt sonst).
			gebaeude.position.y = 0.05
			gebaeude.rotation.y = _rot_zu(erste, strasse)
			_tinte(gebaeude, str(fassade.get("tint", "")))
			wurzel.add_child(gebaeude)
			if bool(fassade.get("awning", false)):
				var markise := _glb("%s/gebaeude/detail-awning.glb" % ASSETS, 10.0)
				if markise != null:
					markise.position = mitte + Vector3(0, 0.05, 0)
					markise.rotation.y = _rot_zu(erste, strasse)
					markise.translate_object_local(Vector3(0, 0.32, 0.52))
					wurzel.add_child(markise)
		# Namensschild überm Eingang
		var schild := Label3D.new()
		schild.text = I18nService.t(str(eintrag.get("name_key", "")))
		schild.font_size = 220
		schild.pixel_size = 0.011
		schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		schild.modulate = Color(0.29, 0.23, 0.21)
		schild.outline_size = 24
		schild.position = mitte + Vector3(0, 8.0, 0)
		wurzel.add_child(schild)
		# Kollisions-AABBs für alle Ort-Tiles
		for tile_raw: Array in tiles:
			_collider_fuer_tile(CityMap._tile_von(tile_raw), 7.5)


func _baue_deko() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Deko"
	add_child(wurzel)
	for eintrag: Dictionary in karte.deko():
		var tile: Array = eintrag.get("tile", [0, 0])
		var node := _glb(
			"%s/%s" % [ASSETS, str(eintrag.get("glb", ""))], float(eintrag.get("scale", 10.0))
		)
		if node == null:
			continue
		node.position = karte.welt_von(float(tile[0]), float(tile[1]))
		node.position.y = 0.05
		node.rotation_degrees.y = float(eintrag.get("rot", 0))
		_tinte(node, str(eintrag.get("tint", "")))
		wurzel.add_child(node)
		if str(eintrag.get("glb", "")).begins_with("gebaeude/"):
			var halb := float(eintrag.get("scale", 10.0)) * 0.5
			_collider_bei(node.position, halb)


func _baue_natur() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Natur"
	add_child(wurzel)
	var rng := RandomNumberGenerator.new()
	rng.seed = karte.deko_seed()
	var belegt := {}
	for eintrag: Dictionary in karte.orte():
		for tile_raw: Array in eintrag.get("tiles", []):
			belegt[CityMap._tile_von(tile_raw)] = true
	for eintrag: Dictionary in karte.deko():
		var tile: Array = eintrag.get("tile", [0, 0])
		belegt[Vector2i(roundi(float(tile[0])), roundi(float(tile[1])))] = true
	var baeume: Array[String] = ["tree_default", "tree_pineRoundA", "plant_bush"]
	for r in karte.reihen:
		for c in karte.spalten:
			var tile := Vector2i(r, c)
			if karte.ist_strasse(tile) or belegt.has(tile):
				continue
			if rng.randf() > 0.4:
				continue
			var glb := baeume[rng.randi_range(0, baeume.size() - 1)]
			var baum := _glb("%s/natur/%s.glb" % [ASSETS, glb], 6.0 * rng.randf_range(0.8, 1.3))
			if baum == null:
				continue
			var mitte := karte.tile_zu_welt(tile)
			baum.position = mitte + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
			baum.rotation.y = rng.randf() * TAU
			wurzel.add_child(baum)


func _baue_verkehr() -> void:
	var modelle: Array[String] = ["van", "suv", "hatchback-sports"]
	var loops := karte.traffic_loops()
	for i in mini(3, loops.size()):
		var tiles := graph.schleife(loops[i])
		var punkte := PackedVector3Array()
		for tile in tiles:
			var p := karte.tile_zu_welt(tile)
			p.y = CityCarFeel.ROAD_Y
			punkte.append(p)
		var wagen := _glb("%s/autos/%s.glb" % [ASSETS, modelle[i]], CityCarFeel.CAR_SCALE)
		if wagen == null or punkte.size() < 2:
			continue
		add_child(wagen)
		if _licht_profil["lichter_an"]:
			_haenge_autolichter(wagen)
		(
			_verkehr
			. append(
				{
					"node": wagen,
					"punkte": punkte,
					"s": float(i) * 60.0,
					"laenge": CityRoadGraph.polyline_laenge(punkte, true),
				}
			)
		)


## Scheinwerfer-Paar (POLISH-8): zwei warme Emissiv-Kugeln an der Front
## (lokale Model-Einheiten — der Wagen-Root ist bereits skaliert).
func _haenge_autolichter(wagen: Node3D) -> void:
	var front := _aabb_grenze_z(wagen)
	for seite: float in [-1.0, 1.0]:
		var licht := MeshInstance3D.new()
		var kugel := SphereMesh.new()
		kugel.radius = 0.05
		kugel.height = 0.1
		kugel.radial_segments = 8
		kugel.rings = 4
		licht.mesh = kugel
		licht.material_override = CityAmbiente.leuchten_material(Color(1.0, 0.95, 0.75), 2.2)
		licht.position = Vector3(seite * 0.22, 0.25, front)
		wagen.add_child(licht)


## Vorderkante (+Z, lokale Model-Einheiten) des Wagens.
func _aabb_grenze_z(node: Node3D) -> float:
	var kante := 0.6
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		var aabb := mi.get_aabb()
		kante = maxf(kante, mi.position.z + aabb.position.z + aabb.size.z)
	return kante


func _baue_auto() -> void:
	auto = CarController.new()
	auto.name = "SpielerAuto"
	var halb := karte.welt_halb()
	auto.welt_halb = Vector2(halb.x - 2.0, halb.y - 2.0)
	auto.licht_an = _licht_profil["lichter_an"]
	add_child(auto)
	_spawn_bei(_gespeicherter_spawn())
	cam = ChaseCam.new()
	cam.name = "ChaseCam"
	cam.ziel = auto
	cam.current = true
	add_child(cam)
	cam.snap()


func _baue_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = DriveHud.new()
	hud.name = "DriveHud"
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	hud.theme = ThemeService.theme()
	layer.add_child(hud)
	hud.steer_changed.connect(func(v: float) -> void: auto.set_steer(v))
	hud.brake_changed.connect(func(on: bool) -> void: auto.set_brake(on))
	hud.reverse_changed.connect(func(on: bool) -> void: auto.set_reverse(on))
	hud.nach_hause_pressed.connect(_on_nach_hause)
	hud.betreten_pressed.connect(_on_betreten)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	layer.add_child(_toast)
	# ToastLayer setzt in _ready nur Anker (kein Offsets-Reset) — nach
	# add_child von Hand auf Full-Rect ziehen.
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Tastatur (Desktop-Dev): Pfeile lenken/bremsen wie im Web.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or auto == null:
		return
	var taste: InputEventKey = event
	match taste.keycode:
		KEY_LEFT:
			auto.set_steer(-1.0 if taste.pressed else 0.0)
		KEY_RIGHT:
			auto.set_steer(1.0 if taste.pressed else 0.0)
		KEY_DOWN, KEY_SPACE:
			auto.set_brake(taste.pressed)
		KEY_R:
			auto.set_reverse(taste.pressed)


## ------------------------------------------------------------ Fahr-Logik


## Gelegentliche Hupe/Vogel (POLISH-8): geplant über CityAmbiente, gespielt
## über den W4-P1-AudioDirector. Ohne dessen Autoload: leiser Verzicht.
func _update_ambient_sfx(delta: float) -> void:
	_sfx_timer -= delta
	if _sfx_timer > 0.0:
		return
	_sfx_timer = CityAmbiente.sfx_pause_s(randf())
	_spiele_ambient_sfx(CityAmbiente.sfx_wahl(_stunde(), randf()))


func _spiele_ambient_sfx(sfx_name: String) -> void:
	# W4-P1-AudioDirector: die Ids city_hupe/city_vogel sind als Wunsch im
	# W4P1-sfx-wiring-Handoff angemeldet; bis sie in der SfxMap stehen,
	# verzichten wir LEISE (kein push_warning-Spam pro Roll).
	var id := "city_%s" % sfx_name
	if SfxMap.entry(id).is_empty():
		return
	AudioDirector.try_play(self, id, 1.0)


func _update_verkehr(delta: float) -> void:
	for eintrag in _verkehr:
		var s := float(eintrag["s"]) + CityCarFeel.TRAFFIC_SPEED * delta
		eintrag["s"] = fposmod(s, float(eintrag["laenge"]))
		var bei := CityRoadGraph.punkt_bei_laenge(eintrag["punkte"], float(eintrag["s"]), true)
		var node: Node3D = eintrag["node"]
		node.position = bei["punkt"]
		var richtung: Vector3 = bei["richtung"]
		node.rotation.y = atan2(richtung.x, richtung.z)


func _update_parkplatz() -> void:
	if auto == null or hud == null:
		return
	var radius := karte.park_radius() + 3.0
	var gefunden := ""
	var gefunden_name := ""
	var energie := 0
	for eintrag: Dictionary in karte.orte():
		var id := str(eintrag.get("id", ""))
		var park := karte.parkplatz_welt(id)
		if Vector2(auto.position.x, auto.position.z).distance_to(Vector2(park.x, park.z)) <= radius:
			gefunden = id
			gefunden_name = I18nService.t(str(eintrag.get("name_key", "")))
			energie = karte.energie_kosten(id)
			break
	if gefunden.is_empty():
		var heim := karte.parkplatz_welt("zuhause")
		var d := Vector2(auto.position.x, auto.position.z).distance_to(Vector2(heim.x, heim.z))
		if d <= radius:
			gefunden = "zuhause"
			gefunden_name = I18nService.t("city.ort.zuhause")
	if gefunden == _prompt_ort:
		return
	_prompt_ort = gefunden
	if gefunden.is_empty():
		hud.verstecke_prompt()
	else:
		hud.zeige_prompt(gefunden, gefunden_name, energie)


func _on_nach_hause() -> void:
	# IMMER kostenlos (User-Wunsch): Auto heim-teleportieren + Route heim.
	var gs := game_state()
	if gs != null:
		gs.set_value("city.autoTile", [])
	_gehe_zu_route(&"home/living", {})


func _on_betreten(ort_id: String) -> void:
	var gs := game_state()
	if ort_id == "zuhause":
		_on_nach_hause()
		return
	var eintrag := karte.ort(ort_id)
	if str(eintrag.get("typ", "")) == "stub" or str(eintrag.get("szene", "")).is_empty():
		_zeige_toast(I18nService.t("city.ort.bald_offen"))
		return
	var kosten := karte.energie_kosten(ort_id)
	if gs != null:
		var energie := float(gs.get_value("gooby.stats.energy", 100.0))
		if energie < float(kosten):
			_zeige_toast(I18nService.t("city.fahren.zu_muede"))
			return
		gs.update(
			func(state: Dictionary) -> void:
				var stats: Dictionary = state["gooby"]["stats"]
				stats["energy"] = maxf(0.0, float(stats["energy"]) - float(kosten))
		)
		var strasse := karte.welt_zu_tile(auto.position)
		gs.set_value("city.autoTile", [strasse.x, strasse.y])
	ort_betreten_angefordert.emit(ort_id)
	_gehe_zu_route(StringName("city/ort/%s" % ort_id), {"ort_id": ort_id})


func _spawn_bei(spawn: String) -> void:
	var strasse := karte.zuhause_strasse()
	if spawn != "zuhause" and not spawn.is_empty():
		var eintrag := karte.ort(spawn)
		if not eintrag.is_empty():
			strasse = CityMap._tile_von(eintrag.get("strasse", [0, 0]))
	var welt := karte.tile_zu_welt(strasse)
	var start_heading := 0.0 if karte.ist_strasse(strasse + Vector2i(1, 0)) else PI / 2.0
	auto.teleport(welt.x, welt.z, start_heading)
	auto.colliders = _colliders
	if cam != null:
		cam.snap()


func _gespeicherter_spawn() -> String:
	var gs := game_state()
	if gs == null:
		return "zuhause"
	var tile: Variant = gs.get_value("city.autoTile", [])
	if tile is Array and tile.size() == 2:
		# Letzte Parkposition: nächstgelegenen Ort raten, sonst zuhause.
		for eintrag: Dictionary in karte.orte():
			if (
				CityMap._tile_von(eintrag.get("strasse", [0, 0]))
				== Vector2i(int(tile[0]), int(tile[1]))
			):
				return str(eintrag.get("id", ""))
	return "zuhause"


func _gehe_zu_route(ziel: StringName, params: Dictionary) -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		_zeige_toast("(Route %s — Router fehlt)" % ziel)
		return
	router.goto(ziel, params)


func _zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)


## ------------------------------------------------------------- Bau-Helfer


func _collider_fuer_tile(tile: Vector2i, halb: float) -> void:
	_collider_bei(karte.tile_zu_welt(tile), halb)


func _collider_bei(mitte: Vector3, halb: float) -> void:
	(
		_colliders
		. append(
			{
				"min_x": mitte.x - halb,
				"max_x": mitte.x + halb,
				"min_z": mitte.z - halb,
				"max_z": mitte.z + halb,
			}
		)
	)
	if auto != null:
		auto.colliders = _colliders


## GLB/GLTF instanzieren + uniform skalieren (null bei Fehlpfad).
func _glb(pfad: String, groesse: float) -> Node3D:
	if not ResourceLoader.exists(pfad):
		push_warning("Asset fehlt: %s" % pfad)
		return null
	var szene: PackedScene = load(pfad)
	if szene == null:
		return null
	var node: Node3D = szene.instantiate()
	node.scale = Vector3.ONE * groesse
	return node


## Fassaden-/Deko-Tint: alle Mesh-Materialien duplizieren + einfärben.
func _tinte(node: Node3D, hex: String) -> void:
	if hex.is_empty():
		return
	var farbe := Color.from_string(hex, Color.WHITE)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.65)
				mi.set_surface_override_material(i, kopie)


## Rotation, damit die geauthorte Front (+Z) zum Straßen-Tile zeigt.
func _rot_zu(von: Vector2i, nach: Vector2i) -> float:
	var richtung := Vector2(float(nach.y - von.y), float(nach.x - von.x))
	return atan2(richtung.x, richtung.y)
