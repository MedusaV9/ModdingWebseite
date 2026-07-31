class_name CityScene
extends Node3D
## Stadt-Szene (W3a CITY, Doc E §1): baut die komplette Stadt PROZEDURAL aus
## city_map.json (Kenney-Kits nach Karte, Muster cityBuilder.js) — seit FIX-5
## („Die Stadt ist leer") DICHT: CityKulisse füllt jeden freien Block mit
## Häuserzeilen, Vorgärten, Park, Straßenmöblierung und Bordstein-Parkern,
## alles als MultiMesh-Gruppen (Draw-Call-Budget ≤ 400 in der Stadtansicht).
## Verkehr hält an Ampeln (CityVerkehr), Fußgänger-Goobys machen
## Schaufenster-Pausen (CityFussgaenger), nachts leuchten Fenster/Laternen/
## Schilder und die Ampeln blinken gelb. FREIE FAHRT: Energie-Abzug ERST beim
## Betreten eines Orts; „Nach Hause" ist IMMER kostenlos. Die Fahrt startet
## in der EIGENEN Hausausfahrt (Rückwärts-Ausparken, CityAusparken).
##
## Router-Contract (W1a): `ready_for_reveal` nach dem Aufbau;
## `receive_params({"spawn": "zuhause"|"<ort_id>"})`. Tests injizieren
## `game_state_override` VOR add_child (Muster W2a RoomBase).

signal ready_for_reveal
signal ort_betreten_angefordert(ort_id: String)

const ROUTE_CITY := &"city"
const GOOBY_GLB := "res://assets/character/gooby.glb"
## Fußgänger-Skalierung (Gooby-GLB ist ~1 m; Kenney-Autos stehen auf 1,8).
const FUSSGAENGER_SCALE := 1.6
## Verkehrs-Tints (jedes 2. Loop-Auto bekommt eine eigene Lackfarbe).
const VERKEHR_TINTS: Array[String] = ["#E8524A", "#4E79D6", "#F2C14E", "#8FD06C", "#B58CE4"]

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
var _licht_profil: Dictionary = {}
var _sfx_timer := 6.0
var _fussgaenger: Array[Dictionary] = []
var _fuss_zeit := 0.0
var _near_miss_sperre := 0.0
var _ausparken: CityAusparken

## Statik-Bauer (CityBau): baut Kulisse/Orte/Ampeln, hält Collider + Ampel-
## MultiMesh; CityScene behält NUR Gameplay (Auto/Verkehr/Fußgänger/HUD).
var _bau: CityBau
var _ampel_zeit := 0.0
var _ampel_farben := [Color.BLACK, Color.BLACK]


func _ready() -> void:
	karte = CityMap.laden()
	graph = CityRoadGraph.aus_karte(karte)
	_licht_profil = CityAmbiente.licht_profil(_stunde())
	_bau = CityBau.new(self, karte, _licht_profil, _stunde())
	_bau.baue_licht()
	_bau.baue_boden()
	_bau.baue_strassen()
	_bau.baue_laternen()
	_bau.baue_orte()
	_bau.baue_deko()
	_bau.baue_kulisse()
	_bau.baue_ampeln()
	_bau.baue_fenster()
	_baue_verkehr()
	_baue_fussgaenger()
	_bau.baue_voegel(leben_reduziert())
	_baue_auto()
	_baue_hud()
	# W6/RANCH: Stadtausfahrt zur Gooby Ranch (Schild + Reise-Trigger).
	RanchExit.install(self)
	ready_for_reveal.emit()


func _process(delta: float) -> void:
	_update_verkehr(delta)
	_update_fussgaenger(delta)
	_update_ampeln(delta)
	_bau.tick(delta)
	_update_ambient_sfx(delta)
	_update_minimap()


func _physics_process(_delta: float) -> void:
	_update_ausparken()
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


## „Leben reduzieren" (schwache Geräte): halber Verkehr, halbe Fußgänger,
## keine Vögel — über den City-Slice schaltbar, Default AUS.
func leben_reduziert() -> bool:
	var gs := game_state()
	return gs != null and bool(gs.get_value("city.lebenReduziert", false))


## ---------------------------------------------------------------- Aufbau


## Uhrzeit mit Bruchteilen (Tests/Screenshots setzen stunde_override).
func _stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0


## Ambient-Verkehr (FIX-5): mehr Loops, mehr Modelle, eigene Lackfarben —
## Fahrlogik (Ampel-Stopp, Vordermann, Tageszeit-Menge) in CityVerkehr.
func _baue_verkehr() -> void:
	var modelle: Array[String] = [
		"van", "suv", "hatchback-sports", "sedan", "taxi", "delivery", "police", "truck"
	]
	var loops := karte.traffic_loops()
	if loops.is_empty():
		return
	var loop_punkte: Array[PackedVector3Array] = []
	for ecken: Array in loops:
		var tiles := graph.schleife(ecken)
		var punkte := PackedVector3Array()
		for tile in tiles:
			var p := karte.tile_zu_welt(tile)
			p.y = CityCarFeel.ROAD_Y
			punkte.append(p)
		loop_punkte.append(punkte)
	var anzahl := CityVerkehr.anzahl(_stunde())
	if leben_reduziert():
		anzahl = maxi(1, anzahl / 2)
	for i in anzahl:
		var punkte := loop_punkte[i % loop_punkte.size()]
		if punkte.size() < 2:
			continue
		var wagen := _bau.lade_glb(
			"%s/autos/%s.glb" % [CityBau.ASSETS, modelle[i % modelle.size()]], CityCarFeel.CAR_SCALE
		)
		if wagen == null:
			continue
		add_child(wagen)
		if i % 2 == 0:
			_bau.faerbe(wagen, Color(VERKEHR_TINTS[(i / 2) % VERKEHR_TINTS.size()]), 0.45)
		if _licht_profil["lichter_an"]:
			_bau.haenge_autolichter(wagen)
		(
			_verkehr
			. append(
				{
					"node": wagen,
					"punkte": punkte,
					"s": float(i) * 47.0 + float(i % loop_punkte.size()) * 23.0,
					"tempo": CityCarFeel.TRAFFIC_SPEED,
					"laenge": CityRoadGraph.polyline_laenge(punkte, true),
				}
			)
		)


## Fußgänger-Goobys (Doc E §1.4 „Leben auf der Straße"): BILLIG instanziert —
## nur das Gooby-GLB plus sein AnimationPlayer, ohne die GoobyRig-Maschinerie.
## Routen/Pausen/Winken kommen aus dem puren CityFussgaenger; die Menge hängt
## an der Tageszeit (und halbiert sich im Spar-Modus).
func _baue_fussgaenger() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Fussgaenger"
	add_child(wurzel)
	var anzahl := CityFussgaenger.anzahl(_stunde())
	if leben_reduziert():
		anzahl = maxi(1, anzahl / 2)
	var routen := CityFussgaenger.routen(karte, anzahl, karte.deko_seed())
	var szene: PackedScene = load(GOOBY_GLB) if ResourceLoader.exists(GOOBY_GLB) else null
	if szene == null:
		return
	for route in routen:
		var node: Node3D = szene.instantiate()
		node.scale = Vector3.ONE * FUSSGAENGER_SCALE
		wurzel.add_child(node)
		_bau.faerbe(node, route["tint"], 0.5)
		route["node"] = node
		route["player"] = node.find_child("AnimationPlayer", true, false)
		route["anim"] = ""
		_fussgaenger.append(route)
	_update_fussgaenger(0.0)


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
	# Jede MANUELLE Eingabe beendet das automatische Ausparken — der Daumen
	# des Spielers gewinnt immer.
	hud.steer_changed.connect(
		func(v: float) -> void:
			if v != 0.0:
				_ausparken_abbrechen()
			auto.set_steer(v)
	)
	hud.brake_changed.connect(
		func(on: bool) -> void:
			if on:
				_ausparken_abbrechen()
			auto.set_brake(on)
	)
	hud.reverse_changed.connect(
		func(on: bool) -> void:
			if on:
				_ausparken_abbrechen()
			auto.set_reverse(on)
	)
	hud.nach_hause_pressed.connect(_on_nach_hause)
	hud.betreten_pressed.connect(_on_betreten)
	hud.minimap.karte = karte
	hud.minimap.aktualisiere_pins()
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
	if taste.pressed:
		_ausparken_abbrechen()
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


## Gibt true zurück, wenn wirklich ein Klang lief (der Near-Miss-Toast
## erzählt sonst von einer Hupe, die man nie gehört hat).
func _spiele_ambient_sfx(sfx_name: String) -> bool:
	# W4-P1-AudioDirector: die Ids city_hupe/city_vogel sind als Wunsch im
	# W4P1-sfx-wiring-Handoff angemeldet; bis sie in der SfxMap stehen,
	# verzichten wir LEISE (kein push_warning-Spam pro Roll).
	var id := "city_%s" % sfx_name
	if SfxMap.entry(id).is_empty():
		return false
	AudioDirector.try_play(self, id, 1.0)
	return true


func _update_verkehr(delta: float) -> void:
	_ampel_zeit += delta
	var blinkt := CityVerkehr.ampel_blinkt(_stunde())
	var ampeln: Dictionary = {} if blinkt else _bau.ampel_lookup
	for eintrag in _verkehr:
		var abstand := CityVerkehr.vordermann_abstand(eintrag, _verkehr, float(eintrag["laenge"]))
		CityVerkehr.schritt(eintrag, delta, _ampel_zeit, karte, ampeln, abstand)
		var bei := CityRoadGraph.punkt_bei_laenge(eintrag["punkte"], float(eintrag["s"]), true)
		var node: Node3D = eintrag["node"]
		node.position = bei["punkt"]
		var richtung: Vector3 = bei["richtung"]
		node.rotation.y = atan2(richtung.x, richtung.z)
	_pruefe_near_miss(delta)


## Ampel-Birnen umfärben, wenn sich die Phase ändert (Instanzfarben im
## MultiMesh — kein zusätzlicher Draw-Call, kein Material-Wechsel).
func _update_ampeln(_delta: float) -> void:
	if _bau.ampel_mm == null:
		return
	var blinkt := CityVerkehr.ampel_blinkt(_stunde())
	var farbe_ns := CityVerkehr.ampel_farbe(false, _ampel_zeit, blinkt)
	var farbe_ew := CityVerkehr.ampel_farbe(true, _ampel_zeit, blinkt)
	if farbe_ns == _ampel_farben[0] and farbe_ew == _ampel_farben[1]:
		return
	_ampel_farben = [farbe_ns, farbe_ew]
	for i in _bau.ampel_achsen.size():
		_bau.ampel_mm.set_instance_color(i, farbe_ew if _bau.ampel_achsen[i] else farbe_ns)


func _pruefe_near_miss(delta: float) -> void:
	_near_miss_sperre = maxf(0.0, _near_miss_sperre - delta)
	if auto == null or _near_miss_sperre > 0.0 or _verkehr.is_empty():
		return
	var hier := Vector2(auto.position.x, auto.position.z)
	for eintrag in _verkehr:
		var node: Node3D = eintrag["node"]
		var abstand := hier.distance_to(Vector2(node.position.x, node.position.z))
		if not CityAmbiente.ist_beinahe(abstand, auto.speed):
			continue
		_near_miss_sperre = CityAmbiente.NEAR_MISS_PAUSE_S
		# W13B (Doc E §1.5): Funkengarbe am Berührungspunkt — Entscheidung
		# (inkl. Reduced-Motion) + one-shot-Aufräumen stecken im Modul.
		var settings := get_node_or_null("/root/AppSettings")
		var reduced: bool = settings != null and settings.is_reduced_motion()
		if NearMissFunken.soll_funken(abstand, auto.speed, reduced):
			NearMissFunken.spawne(self, NearMissFunken.funkenpunkt(auto.position, node.position))
		var gehupt := _spiele_ambient_sfx("hupe")
		_zeige_toast(I18nService.t("city.fahren.beinahe_hupe" if gehupt else "city.fahren.beinahe"))
		return


func _update_fussgaenger(delta: float) -> void:
	if _fussgaenger.is_empty():
		return
	_fuss_zeit += delta
	for route in _fussgaenger:
		var zustand := CityFussgaenger.zustand(route, _fuss_zeit)
		var node: Node3D = route["node"]
		node.position = zustand["pos"]
		node.rotation.y = float(zustand["heading"])
		var soll := "walk"
		if bool(zustand["steht"]):
			soll = "wave" if bool(zustand["winkt"]) else "idle"
		_spiele_gooby_clip(route, soll)


## Clip-Wechsel eines Fußgängers (walk/idle/wave; Importer strippt teils
## das "-loop"-Suffix — beide Namen zulassen). `wave` loopt nicht und wird
## während der Pause einfach neu angeworfen.
func _spiele_gooby_clip(route: Dictionary, soll: String) -> void:
	var player: AnimationPlayer = route.get("player")
	if player == null:
		return
	if str(route.get("anim", "")) == soll and (player.is_playing() or soll != "wave"):
		return
	for kandidat: String in [soll, soll + "-loop"]:
		if player.has_animation(kandidat):
			player.play(kandidat)
			route["anim"] = soll
			return
	# Clip fehlt (alter GLB-Build): auf walk zurückfallen.
	if soll != "walk":
		route["anim"] = soll


func _update_minimap() -> void:
	if hud == null or hud.minimap == null or auto == null:
		return
	hud.minimap.setze_spieler(auto.position, auto.heading)
	hud.minimap.setze_aktiv(_prompt_ort)


## Rückwärts aus der Hausausfahrt (FIX-5): die pure CityAusparken-Maschine
## kommandiert den CarController, bis das Auto auf der Straße steht.
func _update_ausparken() -> void:
	if _ausparken == null or auto == null:
		return
	var cmd := _ausparken.kommando(auto.position, auto.heading)
	auto.set_reverse(bool(cmd["reverse"]))
	auto.set_steer(float(cmd["steer"]))
	if bool(cmd["fertig"]):
		_ausparken = null


## Manuelle Eingabe bricht das automatische Ausparken ab.
func _ausparken_abbrechen() -> void:
	if _ausparken == null:
		return
	_ausparken = null
	if auto != null:
		auto.set_reverse(false)
		auto.set_steer(0.0)


func _update_parkplatz() -> void:
	if auto == null or hud == null:
		return
	# Während des Ausparkens keinen Betreten-Prompt zeigen — man steht ja
	# noch in der eigenen Einfahrt.
	if _ausparken != null:
		if not _prompt_ort.is_empty():
			_prompt_ort = ""
			hud.verstecke_prompt()
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


## Spawn: „zuhause" parkt das Auto IN DER EIGENEN EINFAHRT (Nase zum Haus)
## und startet das Rückwärts-Ausparken; an Orten steht es am Bordstein.
func _spawn_bei(spawn: String) -> void:
	_ausparken = null
	auto.set_reverse(false)
	auto.set_steer(0.0)
	if spawn == "zuhause" or spawn.is_empty() or karte.ort(spawn).is_empty():
		var einfahrt := karte.zuhause_einfahrt()
		var pos: Vector3 = einfahrt["pos"]
		auto.teleport(pos.x, pos.z, float(einfahrt["heading"]))
		_ausparken = CityAusparken.new(
			einfahrt["strasse_pos"],
			einfahrt["richtung_haus"],
			float(einfahrt["heading"]),
			float(einfahrt["ziel_heading"])
		)
	else:
		var eintrag := karte.ort(spawn)
		var strasse := CityMap._tile_von(eintrag.get("strasse", [0, 0]))
		var welt := karte.tile_zu_welt(strasse)
		var start_heading := 0.0 if karte.ist_strasse(strasse + Vector2i(1, 0)) else PI / 2.0
		auto.teleport(welt.x, welt.z, start_heading)
	auto.colliders = _bau.colliders
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
