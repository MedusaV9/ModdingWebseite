class_name OrtRaumstation
extends OrtScene
## RAUMSTATION GOOB-1 (W13B, Doc G §7 + Doc E §3.3, User-Wunsch §E59/§G89):
## der betretbare Weltraum-Rückblick-Ort. Ankunft NUR über das space-
## Urlaubsziel: das Shuttle-Terminal am FLUGHAFEN erscheint erst, wenn
## `vacation.visited.space` gelatcht ist (`freigeschaltet()`), und meldet
## die Route hier an — die Station steht bewusst NICHT in der city_map.
##
## Innenraum: Low-Poly-Hülle aus Bordmitteln, Panorama-Fenster mit dem
## BESTEHENDEN Sternen-Sky-Shader (gooby_himmel.gdshader, sterne_staerke 1)
## + Erd-Blick, schwebender Stations-Gooby (Low-G-Hop: höher + langsamer,
## reiner Tween-Parameter), 2 SPIEL-TERMINALS (rocketRescue/starHopper über
## die öffentliche Arcade-Start-API `goto(mg_pregame, {game_id})`), 1
## Astro-Snack-Automat (Weltraum-Möhre → inventory.food) und der
## Sternenfoto-Spot (ruft NUR den Fotomodus auf).
##
## Rückweg-Mechanik: Pregame/Host verlassen IMMER nach `&"arcade"`. Beim
## Terminal-Start zeigt die `&"arcade"`-Route deshalb vorübergehend auf
## DIESE Szene (register_route ersetzt idempotent); sobald die Station
## wieder lädt — oder irgendwo die echte Arcade aufmacht
## (`ArcadeScreen.register_routes()` läuft in deren `_ready`) — ist die
## Original-Route zurück. Ein Reise-Schritt, kein Arcade-Zwischenstopp.

const Vacation := preload("res://scripts/logic/vacation.gd")

const ROUTE := &"city/ort/raumstation"
const SZENE := "res://scenes/city/orte/raumstation.tscn"
const DIALOG_PFAD := "res://scripts/city/data/dialoge/raumstation.json"
const SKY_SHADER := "res://assets/sky/gooby_himmel.gdshader"

const SPIEL_ROCKET := "rocketRescue"
const SPIEL_STAR := "starHopper"

## Deko-Kits der beiden Weltraum-Spiele (Assets liegen schon im Repo).
const KIT_ROCKET := "res://assets/minigames/rocket_rescue"
const KIT_STAR := "res://assets/minigames/star_hopper"

## Astro-Snack-Automat: Weltraum-Möhre (Food-API; Preis = Automaten-Aufschlag).
const MOEHRE_ID := "weltraumMoehre"
const MOEHRE_PREIS := 14

## Low-G-Gag (Doc G §7 „Gooby schwebt leicht“): Hop-Basis wie am Boden …
const HOP_BASIS_HOEHE := 0.22
const HOP_BASIS_DAUER := 0.9
## … und in der Station hüpft er HÖHER und LANGSAMER (reine Tween-Zahlen).
const LOW_G_HOEHE_MULT := 2.2
const LOW_G_DAUER_MULT := 1.8

## Tests: Router-Attrappe statt /root/SceneRouter.
var router_override: Object = null
## Terminal-Nodes nach Spiel-Id (Tests + Foto-Spot-Layout).
var terminals: Dictionary = {}

var _kamera: Camera3D
var _kamera_heim: Transform3D
var _schwebe_tween: Tween


## Nur wer den space-Urlaub abgeschlossen hat, kennt den Weg zur GOOB-1.
static func freigeschaltet(state: Dictionary) -> bool:
	return bool(Vacation.slice_of(state)["visited"].get("space", false))


## Route anmelden (idempotent) — ruft der Flughafen vor dem Shuttle-Start.
static func registriere_route(router: Object) -> void:
	if router != null and router.has_method("register_route"):
		router.register_route(ROUTE, SZENE)


## Low-G-Hop-Parameter (pur, testbar): höher (×2,2) und langsamer (×1,8).
static func hop_parameter(basis_hoehe: float, basis_dauer: float) -> Dictionary:
	return {"hoehe": basis_hoehe * LOW_G_HOEHE_MULT, "dauer": basis_dauer * LOW_G_DAUER_MULT}


func _ready() -> void:
	if ort_id.is_empty():
		ort_id = "raumstation"
	super._ready()
	# Rückweg-Umleitung auflösen: ab jetzt zeigt &"arcade" wieder auf die
	# echte Arcade (register_routes ersetzt idempotent).
	ArcadeScreen.register_routes()
	UrlaubsBonus.sync(game_state(), _now_ms(), self)
	_starte_schwebe_hop()
	# W15/VOICE2 (W13-Request): Station betreten → Weltraum-Kommentar. Die
	# Ort-Szene hat keinen eigenen GoobyReactions-Runner — der statische
	# Einstieg spricht über den zuletzt aktiven SeeleRunner (None-sicher).
	SeeleRunner.kommentar_global("w13.raumstation")


## ---------------------------------------------------------------- Aufbau


## Weltraum-Ambiente statt Ladenraum: Sternen-Sky (BESTEHENDER Shader),
## Metallboden, Hüllen-Wand mit Panorama-Fenster + Erd-Blick, warmes
## Innenlicht. Ersetzt das Basis-`_baue_raum()` komplett.
func _baue_raum() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = _sternen_sky()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.78)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-50.0, -25.0, 0.0)
	licht.light_energy = 0.5
	licht.light_color = Color(0.85, 0.88, 1.0)
	add_child(licht)
	var innen := OmniLight3D.new()
	innen.position = Vector3(0.0, 3.2, -0.6)
	innen.omni_range = 12.0
	innen.light_energy = 1.1
	innen.light_color = Color(1.0, 0.95, 0.86)
	add_child(innen)
	_baue_boden()
	_baue_huelle()
	_baue_erde()
	_kamera = Camera3D.new()
	_kamera.position = Vector3(0.0, 2.0, 4.2)
	_kamera.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	_kamera.current = true
	add_child(_kamera)
	_kamera_heim = _kamera.transform


func _baue_innenraum() -> void:
	terminals[SPIEL_ROCKET] = _baue_terminal(
		SPIEL_ROCKET, Vector3(-3.4, 0.0, -3.2), 18.0, Color("#F2784B")
	)
	terminals[SPIEL_STAR] = _baue_terminal(
		SPIEL_STAR, Vector3(3.4, 0.0, -3.2), -18.0, Color("#7FD1F0")
	)
	_baue_automat(Vector3(5.2, 0.0, -1.6), -35.0)
	_baue_foto_spot(Vector3(-1.4, 0.0, -2.6))
	# Deko aus den vorhandenen Weltraum-Kits (volle res://-Pfade, _prop
	# schluckt Fehlpfade still).
	_prop("%s/craft_speederA.glb" % KIT_STAR, Vector3(-5.4, 0.0, -2.2), 40.0, 0.9)
	_prop("%s/meteor_detailed.glb" % KIT_STAR, Vector3(1.6, 0.0, -3.4), 0.0, 0.7)
	_prop("%s/rock_largeA.glb" % KIT_ROCKET, Vector3(-2.2, 0.0, -3.5), 15.0, 0.8)
	_prop("%s/rock_smallA.glb" % KIT_ROCKET, Vector3(2.4, 0.0, -2.9), 60.0, 0.9)
	_prop("%s/carrot.glb" % KIT_STAR, Vector3(5.1, 1.15, -1.55), -35.0, 0.35)


func _dialog_pfad() -> String:
	return DIALOG_PFAD


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#B8A7E8"), "emotion": "happy", "pos": Vector3(0.6, 0.0, -1.8)}


## Dialog-Effekt „laden“ öffnet hier den Astro-Snack-Automaten.
func oeffne_laden() -> void:
	var inhalt := HaendlerSheet.new()
	inhalt.gs = game_state()
	inhalt.waren = [
		{
			"id": MOEHRE_ID,
			"name_de": I18nService.t("raumstation.automat.moehre"),
			"preis": MOEHRE_PREIS,
		}
	]
	zeige_sheet(I18nService.t("raumstation.automat.titel"), inhalt)


func _baue_ui() -> void:
	super._baue_ui()
	var reihe := HBoxContainer.new()
	reihe.name = "StationsKnoepfe"
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	reihe.add_theme_constant_override("separation", 10)
	reihe.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20
	)
	reihe.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui.add_child(reihe)
	reihe.add_child(
		_knopf("TerminalRocket", I18nService.t("mg.rocketRescue.title"), "PrimaryButton")
	)
	reihe.add_child(_knopf("TerminalStar", I18nService.t("mg.starHopper.title"), "PrimaryButton"))
	reihe.add_child(_knopf("Automat", I18nService.t("raumstation.automat.knopf"), "AccentButton"))
	reihe.add_child(_knopf("Sternenfoto", I18nService.t("raumstation.foto.knopf"), "AccentButton"))
	(reihe.get_node("TerminalRocket") as Button).pressed.connect(starte_spiel.bind(SPIEL_ROCKET))
	(reihe.get_node("TerminalStar") as Button).pressed.connect(starte_spiel.bind(SPIEL_STAR))
	(reihe.get_node("Automat") as Button).pressed.connect(oeffne_laden)
	(reihe.get_node("Sternenfoto") as Button).pressed.connect(_on_sternenfoto)


## ------------------------------------------------------- Spiel-Terminals


## Öffentliche Arcade-Start-API (wie eine Arcade-Kachel): Pregame → Host.
## Vorher wird die &"arcade"-Route auf DIESE Szene umgebogen, damit der
## Spiel-Ausstieg zurück zur Station führt (s. Kopfkommentar).
func starte_spiel(game_id: String) -> void:
	AudioDirector.try_play(self, "ui_click")
	ArcadeScreen.register_routes()
	var router := _router()
	if router == null:
		return
	if router.has_method("register_route"):
		router.register_route(ArcadeScreen.ROUTE_ARCADE, SZENE)
	var game := MinigameRegistry.get_game(game_id)
	(
		LoadingVeil
		. set_travel_hint(
			{
				"game_id": game_id,
				"title": I18nService.t(str(game.get("title_key", game_id))),
				"cover": ArcadeScreen.cover_texture(game_id),
				"targets": [ArcadeScreen.ROUTE_PREGAME, ArcadeScreen.ROUTE_HOST],
			}
		)
	)
	if router.has_method("goto"):
		router.goto(ArcadeScreen.ROUTE_PREGAME, {"game_id": game_id})


## ---------------------------------------------------------- Sternenfoto


## Foto-Spot: Kamera schwenkt vors Panorama-Fenster (Spezial-Hintergrund =
## Sternen-Sky + Erde), dann macht der BESTEHENDE Fotomodus die Arbeit.
func _on_sternenfoto() -> void:
	var gs := game_state()
	if gs == null:
		return
	if not FotoModus.ist_frei(gs):
		zeige_toast(I18nService.t("raumstation.foto.keine_kamera"))
		return
	AudioDirector.try_play(self, "ui_click")
	if _kamera != null:
		var ziel := Transform3D(Basis.IDENTITY, Vector3(0.0, 2.2, 0.6))
		ziel = ziel.looking_at(Vector3(0.0, 2.4, -10.0), Vector3.UP)
		create_tween().tween_property(_kamera, "transform", ziel, 0.5).set_trans(Tween.TRANS_SINE)
	var modus := FotoModus.oeffne(self, gs)
	modus.geschlossen.connect(_on_foto_zu)


func _on_foto_zu() -> void:
	if _kamera != null:
		create_tween().tween_property(_kamera, "transform", _kamera_heim, 0.5).set_trans(
			Tween.TRANS_SINE
		)


## ----------------------------------------------------------- Rückreise


## Verlassen = Shuttle zurück zum Flughafen (die Station liegt nicht an
## einer Straße — der Stadt-Spawn der Basis-Klasse griffe ins Leere).
func _on_verlassen() -> void:
	verlassen_angefordert.emit()
	var router := _router()
	if router != null and router.has_method("goto"):
		router.goto(&"city/ort/flughafen", {})


## ------------------------------------------------------------ Low-G-Gag


func _starte_schwebe_hop() -> void:
	if rig == null or _reduced_motion():
		return
	var hop := hop_parameter(HOP_BASIS_HOEHE, HOP_BASIS_DAUER)
	var basis_y := rig.position.y
	_schwebe_tween = create_tween().set_loops()
	(
		_schwebe_tween
		. tween_property(
			rig, "position:y", basis_y + float(hop["hoehe"]), float(hop["dauer"]) * 0.5
		)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_schwebe_tween
		. tween_property(rig, "position:y", basis_y, float(hop["dauer"]) * 0.5)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN)
	)


## --------------------------------------------------------------- Helfer


func _router() -> Object:
	if router_override != null:
		return router_override
	return get_node_or_null("/root/SceneRouter")


func _now_ms() -> int:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return (
		settings != null
		and settings.has_method("is_reduced_motion")
		and settings.is_reduced_motion()
	)


func _knopf(name_id: String, text: String, variation: String) -> Button:
	var btn := Button.new()
	btn.name = name_id
	btn.text = text
	btn.theme_type_variation = variation
	btn.custom_minimum_size = Vector2(0.0, 52.0)
	return btn


## Sternen-Himmel aus dem BESTEHENDEN Sky-Shader: Nacht-Uniforms + volle
## Sterne, keine Wolken, keine Sonne — Weltraum eben.
func _sternen_sky() -> Sky:
	var material := ShaderMaterial.new()
	material.shader = load(SKY_SHADER)
	material.set_shader_parameter("zenit_farbe", Color(0.015, 0.02, 0.06))
	material.set_shader_parameter("horizont_farbe", Color(0.03, 0.04, 0.10))
	material.set_shader_parameter("boden_farbe", Color(0.01, 0.012, 0.03))
	material.set_shader_parameter("dunst_staerke", 0.0)
	material.set_shader_parameter("sonnen_groesse", 0.0)
	material.set_shader_parameter("sonnen_glow", 0.0)
	material.set_shader_parameter("wolken_menge", 0.0)
	material.set_shader_parameter("sterne_staerke", 1.0)
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	return sky


func _baue_boden() -> void:
	var boden := MeshInstance3D.new()
	boden.name = "Metallboden"
	var bm := PlaneMesh.new()
	bm.size = Vector2(14.0, 10.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.32, 0.35, 0.42)
	bmat.metallic = 0.4
	bmat.roughness = 0.55
	bm.material = bmat
	boden.mesh = bm
	add_child(boden)


## Hüllen-Wand mit Panorama-Fenster-Ausschnitt (x −2…2, y 1…3,2 bei z=−4).
func _baue_huelle() -> void:
	var wand := Color(0.78, 0.80, 0.86)
	_wandstueck(Vector3(-4.5, 2.5, -4.0), Vector3(5.0, 5.0, 0.3), wand)
	_wandstueck(Vector3(4.5, 2.5, -4.0), Vector3(5.0, 5.0, 0.3), wand)
	_wandstueck(Vector3(0.0, 4.1, -4.0), Vector3(4.0, 1.8, 0.3), wand)
	_wandstueck(Vector3(0.0, 0.5, -4.0), Vector3(4.0, 1.0, 0.3), wand)
	# Fensterrahmen (schmale helle Leisten um den Ausschnitt).
	var rahmen := Color(0.95, 0.96, 1.0)
	_wandstueck(Vector3(-2.05, 2.1, -3.95), Vector3(0.14, 2.4, 0.34), rahmen)
	_wandstueck(Vector3(2.05, 2.1, -3.95), Vector3(0.14, 2.4, 0.34), rahmen)
	_wandstueck(Vector3(0.0, 3.25, -3.95), Vector3(4.2, 0.14, 0.34), rahmen)
	_wandstueck(Vector3(0.0, 0.95, -3.95), Vector3(4.2, 0.14, 0.34), rahmen)


func _wandstueck(pos: Vector3, groesse: Vector3, farbe: Color) -> void:
	var stueck := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = groesse
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = farbe
	wmat.roughness = 0.7
	wm.material = wmat
	stueck.mesh = wm
	stueck.position = pos
	add_child(stueck)


## Der Erd-Blick vorm Fenster (Doc G §7): knuffige blaue Kugel im All.
func _baue_erde() -> void:
	var erde := MeshInstance3D.new()
	erde.name = "Erde"
	var kugel := SphereMesh.new()
	kugel.radius = 1.6
	kugel.height = 3.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.55, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.10, 0.22, 0.38)
	mat.emission_energy_multiplier = 0.6
	kugel.material = mat
	erde.mesh = kugel
	erde.position = Vector3(1.2, 2.6, -11.0)
	add_child(erde)


## Arcade-Automaten-Optik: dunkles Gehäuse, leuchtender Cover-Screen,
## Akzent-Blende + Titel-Schild.
func _baue_terminal(game_id: String, pos: Vector3, rot_grad: float, akzent: Color) -> Node3D:
	var terminal := Node3D.new()
	terminal.name = "Terminal%s" % game_id.capitalize()
	terminal.position = pos
	terminal.rotation_degrees.y = rot_grad
	add_child(terminal)
	var gehaeuse := MeshInstance3D.new()
	var korpus := BoxMesh.new()
	korpus.size = Vector3(0.95, 1.7, 0.65)
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.16, 0.17, 0.22)
	kmat.roughness = 0.5
	korpus.material = kmat
	gehaeuse.mesh = korpus
	gehaeuse.position = Vector3(0.0, 0.85, 0.0)
	terminal.add_child(gehaeuse)
	var blende := MeshInstance3D.new()
	var bl := BoxMesh.new()
	bl.size = Vector3(0.95, 0.22, 0.7)
	var blmat := StandardMaterial3D.new()
	blmat.albedo_color = akzent
	blmat.emission_enabled = true
	blmat.emission = akzent
	blmat.emission_energy_multiplier = 0.5
	bl.material = blmat
	blende.mesh = bl
	blende.position = Vector3(0.0, 1.81, 0.0)
	terminal.add_child(blende)
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.54)
	var smat := StandardMaterial3D.new()
	var cover := ArcadeScreen.cover_texture(game_id)
	if cover != null:
		smat.albedo_texture = cover
	smat.emission_enabled = true
	smat.emission = Color(0.9, 0.9, 1.0)
	smat.emission_energy_multiplier = 0.35
	smat.emission_texture = cover
	quad.material = smat
	screen.mesh = quad
	screen.position = Vector3(0.0, 1.25, 0.34)
	screen.rotation_degrees.x = -8.0
	terminal.add_child(screen)
	var schild := Label3D.new()
	schild.text = I18nService.t("mg.%s.title" % game_id)
	schild.font_size = 64
	schild.pixel_size = 0.004
	schild.modulate = akzent
	schild.position = Vector3(0.0, 2.05, 0.2)
	schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	terminal.add_child(schild)
	return terminal


## Astro-Snack-Automat (Souvenir-Automat): rot-weißes Gehäuse + Sichtfenster.
func _baue_automat(pos: Vector3, rot_grad: float) -> void:
	var automat := Node3D.new()
	automat.name = "AstroAutomat"
	automat.position = pos
	automat.rotation_degrees.y = rot_grad
	add_child(automat)
	var korpus := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 1.9, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.30, 0.32)
	mat.roughness = 0.5
	box.material = mat
	korpus.mesh = box
	korpus.position = Vector3(0.0, 0.95, 0.0)
	automat.add_child(korpus)
	var fenster := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 1.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.75, 0.88, 0.95, 0.85)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = fmat
	fenster.mesh = quad
	fenster.position = Vector3(0.0, 1.25, 0.36)
	automat.add_child(fenster)
	var schild := Label3D.new()
	schild.text = I18nService.t("raumstation.automat.schild")
	schild.font_size = 48
	schild.pixel_size = 0.004
	schild.modulate = Color(1.0, 0.92, 0.5)
	schild.position = Vector3(0.0, 2.05, 0.2)
	schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	automat.add_child(schild)


## Foto-Spot-Markierung am Fenster (leuchtender Stern-Kreis am Boden).
func _baue_foto_spot(pos: Vector3) -> void:
	var spot := MeshInstance3D.new()
	spot.name = "FotoSpot"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 0.8
	ring.material = mat
	spot.mesh = ring
	spot.position = pos + Vector3(0.0, 0.02, 0.0)
	add_child(spot)
