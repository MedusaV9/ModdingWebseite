class_name Funkelpark
extends Node3D
## Funkelpark (REST-4, EVAL Rang 9) — der betretbare Freizeitpark aus der
## alten Web-Version (GOOBY/src/park/parkScene.js), als Stadt-Ort erreichbar
## (city_map.json "funkelpark" → Route city/ort/funkelpark). Eingangstor mit
## Ticketschalter, Plaza-Gooby, vier Fahrgeschäfte (Achterbahn mit POV-
## Kamera, Riesenrad, Karussell, Autoscooter zum Zuschauen) plus Naschgasse
## (ParkStallSheet). Fahrten kosten Münzen + etwas Energie und schenken
## Spaß; Zähler laufen über ParkState in den `park`-Slice (Sticker-Seite
## "funkelpark", Soul-Erinnerung). Nach Einbruch der Dunkelheit gehen die
## Lichterketten an (nightVisit-Latch, Sticker nightLights).
##
## Router-Contract (W1a): `ready_for_reveal` nach Aufbau, `receive_params`
## nimmt {"ort_id": ...}. Tests setzen `game_state_override` VOR add_child
## und fahren die Fahrgeschäfte deterministisch über deren `simuliere(dt)`.

signal ready_for_reveal

const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")
const Economy := preload("res://scripts/logic/economy.gd")

## Park-Hintergrundmusik (MusicRegistry-Track, Kontext-Modus bleibt intakt:
## beim Verlassen setzt der MusicDirector über travel_finished wieder city).
const PARK_TRACK := "bordmusik-candy"
## Fahrten kosten neben Münzen (ParkState.PREIS) etwas Energie …
const RIDE_ENERGIE := 2.0
## … und schenken Spaß (Belohnungs-Teil, Web: Tagesausflug-Stimmung).
const RIDE_SPASS := 12.0
const CAPTION_SEC := 3.2

const FARBE_WEG := Color("#D9C6A5")
const FARBE_WIESE := Color("#8FBF6C")
const FARBE_ROSA := Color("#F781B0")
const FARBE_CREME := Color("#F0EFE9")
const BESUCHER_FARBEN: Array[Color] = [
	Color("#9BD7E8"), Color("#F2C14E"), Color("#B58CE4"), Color("#8FD06C")
]

@export var ort_id := "funkelpark"
## Tests/Screenshots: feste Stunde statt Systemuhr (-1 = echte Uhr).
@export var stunde_override := -1.0

var game_state_override: Object
var rig: GoobyRig
var coaster: CoasterRide
var wheel: FerrisWheel
var karussell: Karussell
var scooter: Autoscooter
## "" = keine Fahrt aktiv, sonst coaster/wheel/karussell.
var aktive_fahrt := ""

var _ui: Control
var _sheet: PanelSheet
var _toast: Node
var _caption: Label
var _caption_timer: Timer
var _ride_bar: HBoxContainer
var _hands_btn: Button
var _nacht_licht: Node3D
var _env: Environment
var _sonne: DirectionalLight3D
var _besucher: Array[Node3D] = []
var _besucher_ziele: Array[Vector3] = []
var _zeit := 0.0


func _ready() -> void:
	_baue_welt()
	_baue_eingang()
	_baue_fahrgeschaefte()
	_baue_naschgasse()
	_baue_gooby()
	_baue_besucher()
	_baue_lichter()
	_baue_ui()
	_buche_besuch()
	_wende_nacht_an()
	_starte_musik()
	ready_for_reveal.emit()
	_zeige_caption(I18nService.t("park.gate.text"))


func _process(delta: float) -> void:
	_zeit += delta
	_bewege_besucher(delta)


func receive_params(params: Dictionary) -> void:
	var id := str(params.get("ort_id", ""))
	if not id.is_empty():
		ort_id = id


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


## Aktuelle Parkstunde (Tests überschreiben via stunde_override).
func stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var uhr := Time.get_datetime_dict_from_system()
	return float(uhr["hour"]) + float(uhr["minute"]) / 60.0


func ist_nacht() -> bool:
	return ParkState.ist_nacht(stunde())


## ------------------------------------------------------------ Fahrt-Flow


## Eine Fahrt kaufen und starten (auch der Test-Einstieg). Liefert true,
## wenn die Fahrt losgeht.
func fahre(ride_id: String) -> bool:
	if not aktive_fahrt.is_empty():
		_zeige_toast(I18nService.t("park.ride.laeuft"))
		return false
	var gs := game_state()
	if gs == null:
		return false
	if float(gs.get_value("gooby.stats.energy", 100.0)) < RIDE_ENERGIE + 1.0:
		_zeige_toast(I18nService.t("park.ride.zu_muede"))
		return false
	var preis := int(ParkState.PREIS.get(ride_id, 0))
	# Vorab prüfen (Lambda-Captures sind by-value — kein Out-Flag möglich);
	# der eigentliche Abzug läuft trotzdem atomar in EINEM gs.update.
	if preis > 0 and int(gs.get_value("economy.coins", 0)) < preis:
		_zeige_toast(I18nService.t("park.ride.zu_teuer"))
		return false
	gs.update(
		func(state: Dictionary) -> void:
			if preis > 0 and not Economy.spend(state["economy"], preis, "park_ride"):
				return
			var stats: Dictionary = state["gooby"]["stats"]
			stats["energy"] = maxf(0.0, float(stats["energy"]) - RIDE_ENERGIE)
			stats["fun"] = minf(100.0, float(stats["fun"]) + RIDE_SPASS)
	)
	aktive_fahrt = ride_id
	if rig != null:
		rig.visible = false
	_setze_ride_bar_aktiv(false)
	match ride_id:
		"coaster":
			_zeige_caption(I18nService.t("park.coaster.board"))
			if _hands_btn != null:
				_hands_btn.visible = true
			coaster.starte_fahrt()
		"wheel":
			_zeige_caption(I18nService.t("park.wheel.board"))
			wheel.starte_fahrt()
		"karussell":
			karussell.starte_fahrt()
	return true


func _on_ride_event(id: String) -> void:
	match id:
		"wheee":
			ParkState.schreibe(
				game_state(),
				func(slice: Variant) -> Dictionary: return ParkState.record_hands_up(slice)
			)
		"photo":
			_zeige_caption(I18nService.t("park.coaster.photo"))
			_knipse_fahrtfoto("park.coaster.photo_saved")
		"apex":
			_zeige_caption(I18nService.t("park.wheel.apex"))
			_knipse_fahrtfoto("park.wheel.photo_saved")
		"board", "depart":
			pass
		_:
			var key := "park.coaster.%s" % id
			if I18nService.has_key(key):
				_zeige_caption(I18nService.t(key))


func _on_ride_finished(ride_id: String) -> void:
	aktive_fahrt = ""
	if _hands_btn != null:
		_hands_btn.visible = false
		_hands_btn.button_pressed = false
	if rig != null:
		rig.visible = true
		rig.play_clip("celebrate")
	_setze_ride_bar_aktiv(true)
	ParkState.schreibe(
		game_state(),
		func(slice: Variant) -> Dictionary: return ParkState.record_ride(slice, ride_id)
	)
	var done_key := "park.%s.done" % ride_id
	if I18nService.has_key(done_key):
		_zeige_caption(I18nService.t(done_key))


## Fahrtfoto: Viewport sichern und in die Galerie legen (Ort = Funkelpark).
func _knipse_fahrtfoto(toast_key: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var bild := viewport.get_texture().get_image()
	if bild == null or bild.is_empty():
		return
	var jetzt := int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FotoModus.FOTO_DIR))
	var pfad := FotoModus.foto_pfad(jetzt)
	if bild.save_png(pfad) != OK:
		return
	FotoModus.merke_foto(game_state(), pfad, jetzt * 1000, ort_id)
	_zeige_toast(I18nService.t(toast_key))


func _oeffne_naschgasse() -> void:
	if _sheet == null:
		return
	var inhalt := ParkStallSheet.new()
	inhalt.gs = game_state()
	_sheet.set_title(I18nService.t("park.alley.title"))
	_sheet.add_content(inhalt)
	_sheet.open()


func _buche_besuch() -> void:
	var nacht := ist_nacht()
	ParkState.schreibe(
		game_state(),
		func(slice: Variant) -> Dictionary: return ParkState.record_visit(slice, nacht)
	)


## ---------------------------------------------------------------- Aufbau


func _baue_welt() -> void:
	var env_node := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.62, 0.79, 0.94)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(1.0, 0.97, 0.92)
	_env.ambient_light_energy = 1.0
	env_node.environment = _env
	add_child(env_node)
	_sonne = DirectionalLight3D.new()
	_sonne.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	add_child(_sonne)
	var wiese := MeshInstance3D.new()
	var wiese_mesh := PlaneMesh.new()
	wiese_mesh.size = Vector2(64.0, 56.0)
	var wiese_mat := StandardMaterial3D.new()
	wiese_mat.albedo_color = FARBE_WIESE
	wiese_mesh.material = wiese_mat
	wiese.mesh = wiese_mesh
	wiese.position = Vector3(0.0, -0.02, -6.0)
	add_child(wiese)
	var weg := MeshInstance3D.new()
	var weg_mesh := PlaneMesh.new()
	weg_mesh.size = Vector2(26.0, 30.0)
	var weg_mat := StandardMaterial3D.new()
	weg_mat.albedo_color = FARBE_WEG
	weg_mesh.material = weg_mat
	weg.mesh = weg_mesh
	weg.position = Vector3(0.0, 0.0, 4.0)
	add_child(weg)
	var kamera := Camera3D.new()
	kamera.name = "ParkCam"
	kamera.position = Vector3(0.0, 9.5, 24.0)
	kamera.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	kamera.fov = 62.0
	kamera.current = true
	add_child(kamera)


func _baue_eingang() -> void:
	var tor := Node3D.new()
	tor.name = "Eingang"
	tor.position = Vector3(0.0, 0.0, 16.0)
	add_child(tor)
	for seite: float in [-1.0, 1.0]:
		var pfeiler := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 4.4, 0.7)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FARBE_CREME
		box.material = mat
		pfeiler.mesh = box
		pfeiler.position = Vector3(seite * 4.0, 2.2, 0.0)
		tor.add_child(pfeiler)
	var bogen := MeshInstance3D.new()
	var bogen_mesh := BoxMesh.new()
	bogen_mesh.size = Vector3(9.4, 1.0, 0.8)
	var bogen_mat := StandardMaterial3D.new()
	bogen_mat.albedo_color = FARBE_ROSA
	bogen_mesh.material = bogen_mat
	bogen.mesh = bogen_mesh
	bogen.position = Vector3(0.0, 4.6, 0.0)
	tor.add_child(bogen)
	var schild := Label3D.new()
	schild.text = I18nService.t("park.ort.funkelpark")
	schild.font_size = 220
	schild.pixel_size = 0.01
	schild.modulate = Color("#5B4636")
	schild.position = Vector3(0.0, 4.62, 0.45)
	tor.add_child(schild)
	# Ticketschalter (Kasse) neben dem Tor.
	var kasse := Node3D.new()
	kasse.name = "Ticketschalter"
	kasse.position = Vector3(6.6, 0.0, 15.2)
	add_child(kasse)
	var haus := MeshInstance3D.new()
	var haus_mesh := BoxMesh.new()
	haus_mesh.size = Vector3(2.4, 2.2, 1.8)
	var haus_mat := StandardMaterial3D.new()
	haus_mat.albedo_color = Color("#F2C14E")
	haus_mesh.material = haus_mat
	haus.mesh = haus_mesh
	haus.position = Vector3(0.0, 1.1, 0.0)
	kasse.add_child(haus)
	var dach := MeshInstance3D.new()
	var dach_mesh := BoxMesh.new()
	dach_mesh.size = Vector3(2.8, 0.24, 2.2)
	var dach_mat := StandardMaterial3D.new()
	dach_mat.albedo_color = FARBE_ROSA
	dach_mesh.material = dach_mat
	dach.mesh = dach_mesh
	dach.position = Vector3(0.0, 2.32, 0.0)
	kasse.add_child(dach)
	var tafel := Label3D.new()
	tafel.text = I18nService.t("park.gate.tafel")
	tafel.font_size = 140
	tafel.pixel_size = 0.01
	tafel.modulate = Color("#5B4636")
	tafel.position = Vector3(0.0, 1.7, 0.95)
	kasse.add_child(tafel)


func _baue_fahrgeschaefte() -> void:
	coaster = CoasterRide.new()
	coaster.name = "Coaster"
	coaster.position = Vector3(2.0, 0.0, -18.0)
	add_child(coaster)
	coaster.ride_event.connect(_on_ride_event)
	coaster.ride_finished.connect(func() -> void: _on_ride_finished("coaster"))
	wheel = FerrisWheel.new()
	wheel.name = "Riesenrad"
	wheel.position = Vector3(-16.0, 0.0, 0.0)
	wheel.rotation_degrees.y = 90.0
	add_child(wheel)
	wheel.ride_event.connect(_on_ride_event)
	wheel.ride_finished.connect(func() -> void: _on_ride_finished("wheel"))
	karussell = Karussell.new()
	karussell.name = "Karussell"
	karussell.position = Vector3(10.0, 0.0, 2.0)
	add_child(karussell)
	karussell.ride_finished.connect(func() -> void: _on_ride_finished("karussell"))
	scooter = Autoscooter.new()
	scooter.name = "Autoscooter"
	scooter.position = Vector3(16.5, 0.0, 9.0)
	add_child(scooter)


## Naschgasse: drei Jahrmarkt-Stände (Theke + Markise + Schild) westlich.
func _baue_naschgasse() -> void:
	var gasse := Node3D.new()
	gasse.name = "Naschgasse"
	gasse.position = Vector3(-8.0, 0.0, 10.0)
	add_child(gasse)
	for i in ParkState.STALLS.size():
		var stall: Dictionary = ParkState.STALLS[i]
		var stand := Node3D.new()
		stand.position = Vector3(float(i) * 3.4, 0.0, 0.0)
		stand.rotation_degrees.y = 12.0
		gasse.add_child(stand)
		var theke := MeshInstance3D.new()
		var theke_mesh := BoxMesh.new()
		theke_mesh.size = Vector3(2.4, 1.1, 1.4)
		var theke_mat := StandardMaterial3D.new()
		theke_mat.albedo_color = FARBE_CREME
		theke_mesh.material = theke_mat
		theke.mesh = theke_mesh
		theke.position = Vector3(0.0, 0.55, 0.0)
		stand.add_child(theke)
		var markise := MeshInstance3D.new()
		var markise_mesh := CylinderMesh.new()
		markise_mesh.top_radius = 0.12
		markise_mesh.bottom_radius = 1.7
		markise_mesh.height = 0.8
		var markise_mat := StandardMaterial3D.new()
		markise_mat.albedo_color = stall["tint"]
		markise_mesh.material = markise_mat
		markise.mesh = markise_mesh
		markise.position = Vector3(0.0, 2.4, 0.0)
		stand.add_child(markise)
		var mast := MeshInstance3D.new()
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.06
		mast_mesh.bottom_radius = 0.06
		mast_mesh.height = 1.0
		mast_mesh.material = theke_mat
		mast.mesh = mast_mesh
		mast.position = Vector3(0.0, 1.6, 0.0)
		stand.add_child(mast)
		var schild := Label3D.new()
		schild.text = I18nService.t("park.stall.%s.name" % stall["id"])
		schild.font_size = 96
		schild.pixel_size = 0.01
		schild.modulate = Color("#5B4636")
		schild.position = Vector3(0.0, 1.25, 0.75)
		stand.add_child(schild)


func _baue_gooby() -> void:
	rig = GoobyRig.new()
	rig.name = "PlazaGooby"
	rig.position = Vector3(0.0, 0.0, 10.0)
	rig.rotation_degrees.y = 180.0
	add_child(rig)
	rig.set_emotion("ecstatic")
	var gs := game_state()
	if gs != null:
		rig.apply_saved_morphs(gs)


## Pastell-Besucher (billige Kapsel+Kugel-Blobs), die über die Plaza schlendern.
func _baue_besucher() -> void:
	for i in BESUCHER_FARBEN.size():
		var blob := Node3D.new()
		blob.name = "Besucher%d" % i
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BESUCHER_FARBEN[i]
		var koerper := MeshInstance3D.new()
		var kapsel := CapsuleMesh.new()
		kapsel.radius = 0.28
		kapsel.height = 0.9
		kapsel.material = mat
		koerper.mesh = kapsel
		koerper.position.y = 0.45
		blob.add_child(koerper)
		var kopf := MeshInstance3D.new()
		var kugel := SphereMesh.new()
		kugel.radius = 0.22
		kugel.height = 0.44
		kugel.material = mat
		kopf.mesh = kugel
		kopf.position.y = 1.05
		blob.add_child(kopf)
		blob.position = _besucher_punkt(i)
		add_child(blob)
		_besucher.append(blob)
		_besucher_ziele.append(_besucher_punkt(i + 2))


func _bewege_besucher(delta: float) -> void:
	for i in _besucher.size():
		var blob := _besucher[i]
		var ziel := _besucher_ziele[i]
		var d := ziel - blob.position
		d.y = 0.0
		if d.length() < 0.3:
			_besucher_ziele[i] = _besucher_punkt(randi() % 8)
			continue
		blob.position += d.normalized() * delta * 1.1
		blob.rotation.y = atan2(d.x, d.z)


func _besucher_punkt(seed_i: int) -> Vector3:
	var punkte: Array[Vector3] = [
		Vector3(-4.0, 0.0, 12.0),
		Vector3(4.5, 0.0, 8.0),
		Vector3(-9.0, 0.0, 6.5),
		Vector3(7.0, 0.0, 12.5),
		Vector3(-2.0, 0.0, 5.0),
		Vector3(11.0, 0.0, 7.0),
		Vector3(-6.5, 0.0, 13.5),
		Vector3(2.0, 0.0, 14.0),
	]
	return punkte[seed_i % punkte.size()]


## Lichterketten (EIN MultiMesh Kügelchen) + zwei warme Lichter — aus am Tag.
func _baue_lichter() -> void:
	_nacht_licht = Node3D.new()
	_nacht_licht.name = "Nachtlichter"
	add_child(_nacht_licht)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var kugel := SphereMesh.new()
	kugel.radius = 0.09
	kugel.height = 0.18
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#FFE28A")
	mat.emission_enabled = true
	mat.emission = Color("#FFD166")
	mat.emission_energy_multiplier = 2.0
	kugel.material = mat
	mm.mesh = kugel
	var punkte: Array[Vector3] = []
	for i in 14:
		var t := float(i) / 13.0
		punkte.append(Vector3(-4.2 + t * 8.4, 4.7 + sin(t * PI) * -0.35, 16.0))
	for i in 12:
		var t2 := float(i) / 11.0
		punkte.append(Vector3(-9.5 + t2 * 10.5, 3.1 + sin(t2 * 6.0) * 0.18, 10.6))
	mm.instance_count = punkte.size()
	for i in punkte.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, punkte[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_nacht_licht.add_child(mmi)
	for pos: Vector3 in [Vector3(0.0, 4.0, 15.0), Vector3(-4.0, 3.2, 10.0)]:
		var licht := OmniLight3D.new()
		licht.position = pos
		licht.light_color = Color("#FFD166")
		licht.light_energy = 1.4
		licht.omni_range = 10.0
		_nacht_licht.add_child(licht)


## Nacht anwenden: Umgebung dimmen, Lichter an, nightVisit-Latch buchen.
func _wende_nacht_an() -> void:
	var nacht := ist_nacht()
	_nacht_licht.visible = nacht
	if not nacht:
		return
	_env.background_color = Color(0.13, 0.16, 0.30)
	_env.ambient_light_color = Color(0.62, 0.66, 0.86)
	_env.ambient_light_energy = 0.55
	_sonne.light_energy = 0.25
	_sonne.light_color = Color(0.72, 0.78, 1.0)
	_zeige_toast(I18nService.t("park.nacht.lichter"))


func _starte_musik() -> void:
	if not is_inside_tree():
		return
	# Verzögert: der MusicDirector setzt bei travel_finished city-Kontext —
	# danach überblenden wir auf den Park-Track (Radio hat Vorrang).
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(
		func() -> void:
			if not is_inside_tree():
				return
			var md := MusicDirector.get_or_create(self)
			if not md.is_radio_playing():
				md.play_track(PARK_TRACK)
	)


## ------------------------------------------------------------------- UI


func _baue_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UiLayer"
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Theme explizit: Window-Theme propagiert NICHT durch CanvasLayer.
	_ui.theme = ThemeService.theme()
	layer.add_child(_ui)
	var zurueck := Button.new()
	zurueck.name = "Verlassen"
	zurueck.text = I18nService.t("city.ort.verlassen")
	zurueck.theme_type_variation = "GhostButton"
	zurueck.set_anchors_preset(Control.PRESET_TOP_LEFT)
	zurueck.position = Vector2(16.0, 16.0)
	zurueck.pressed.connect(_on_verlassen)
	_ui.add_child(zurueck)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.theme_type_variation = "HeadlineLabel"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 32
	)
	_caption.visible = false
	_ui.add_child(_caption)
	_caption_timer = Timer.new()
	_caption_timer.one_shot = true
	_caption_timer.wait_time = CAPTION_SEC
	_caption_timer.timeout.connect(func() -> void: _caption.visible = false)
	add_child(_caption_timer)
	_baue_ride_bar()
	_hands_btn = Button.new()
	_hands_btn.name = "HandsUp"
	_hands_btn.text = I18nService.t("park.coaster.hands_up")
	_hands_btn.theme_type_variation = "AccentButton"
	_hands_btn.toggle_mode = true
	_hands_btn.custom_minimum_size = Vector2(180.0, 64.0)
	_hands_btn.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24
	)
	_hands_btn.visible = false
	_hands_btn.toggled.connect(func(an: bool) -> void: coaster.set_hands_up(an))
	_ui.add_child(_hands_btn)
	_sheet = PanelSheetScene.instantiate()
	_sheet.theme = ThemeService.theme()
	layer.add_child(_sheet)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	layer.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _baue_ride_bar() -> void:
	_ride_bar = HBoxContainer.new()
	_ride_bar.name = "RideBar"
	_ride_bar.add_theme_constant_override("separation", 10)
	_ride_bar.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20
	)
	_ui.add_child(_ride_bar)
	_ride_knopf("coaster", "park.coaster.name")
	_ride_knopf("wheel", "park.wheel.name")
	_ride_knopf("karussell", "park.karussell.name")
	var gasse := Button.new()
	gasse.name = "Naschgasse"
	gasse.text = I18nService.t("park.alley.title")
	gasse.theme_type_variation = "AccentButton"
	gasse.custom_minimum_size = Vector2(0.0, 56.0)
	gasse.pressed.connect(_oeffne_naschgasse)
	_ride_bar.add_child(gasse)
	var scooter_btn := Button.new()
	scooter_btn.name = "Scooter"
	scooter_btn.text = I18nService.t("park.scooter.name")
	scooter_btn.theme_type_variation = "GhostButton"
	scooter_btn.custom_minimum_size = Vector2(0.0, 56.0)
	scooter_btn.pressed.connect(func() -> void: _zeige_caption(I18nService.t("park.scooter.hint")))
	_ride_bar.add_child(scooter_btn)


func _ride_knopf(ride_id: String, name_key: String) -> void:
	var btn := Button.new()
	btn.name = ride_id.capitalize()
	var preis := int(ParkState.PREIS.get(ride_id, 0))
	btn.text = (
		"%s — %s"
		% [
			I18nService.t(name_key),
			I18nService.t("park.ride.fahren", {"preis": preis}),
		]
	)
	btn.theme_type_variation = "PrimaryButton"
	btn.custom_minimum_size = Vector2(0.0, 56.0)
	btn.pressed.connect(func() -> void: fahre(ride_id))
	_ride_bar.add_child(btn)


func _setze_ride_bar_aktiv(aktiv: bool) -> void:
	if _ride_bar == null:
		return
	for kind in _ride_bar.get_children():
		if kind is Button:
			(kind as Button).disabled = not aktiv


func _zeige_caption(text: String) -> void:
	if _caption == null:
		return
	_caption.text = text
	_caption.visible = true
	_caption_timer.start()


func _zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)


func _on_verlassen() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null:
		router.goto(CityScene.ROUTE_CITY, {"spawn": ort_id})
