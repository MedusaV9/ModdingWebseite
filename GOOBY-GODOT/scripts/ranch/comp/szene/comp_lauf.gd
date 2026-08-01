class_name RcompLauf
extends Node2D
## Lauf-Treiber der Wettbewerbe (RW-5): baut Arena + Kurs in eine Stage3D,
## reitet mit RW-2s RanchRideController (KEINE zweite Reitphysik), füttert
## den PUREN Disziplin-Richter mit Positionen, zeichnet den Geisterlauf
## auf und spielt den besten alten als transparenten Geist ab.
## Konsumenten: ranch_turnier, ranch_tonnen, ranch_zeit (Minigames).
##
## Ablauf: baue(cfg) → starte() → _process treibt Richter/Geist/Kamera →
## `lauf_fertig(ergebnis)` sobald der Richter fertig ist. cfg-Schlüssel:
##   disziplin, klasse, seed, balance, pferd (Save-Dict), geist_b64,
##   zuschauer, bots (rennen), route + ziel_s (zeit), ideal_s (tonnen),
##   pflege + stil (schau).

signal ereignis(event: Dictionary)
signal lauf_fertig(ergebnis: Dictionary)

const Stage3DScript := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const GoobyActorScript := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Arena := preload("res://scripts/ranch/comp/szene/comp_arena.gd")
const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")
const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")
const Ghost := preload("res://scripts/ranch/comp/ghost/comp_ghost.gd")

const HOLZ := Color(0.79, 0.55, 0.35)
## W16: Creme im Gleichschritt mit RcompArena.CREME abgesenkt (§6: die
## 0.95er-Latten zogen sich als Weiss-Doppelband durchs ganze Bild).
const CREME := Color(0.9, 0.87, 0.78)
const ROT := Color(0.91, 0.4, 0.42)
const MARKER_FARBE := Color(1.0, 0.82, 0.3)
## Richter-Events, bei denen das Tribünen-Publikum jubelt (M2-Hook).
const JUBEL_EVENTS: Array[String] = [
	"perfekt",
	"hindernis_ok",
	"tor_ok",
	"aufgabe_ok",
	"tonne_ok",
	"runde",
	"windschatten",
	"figur_ok",
	"gangart_ok",
	"treffer",
	"ziel",
]
## Schau-Kommando → RanchPferd-Aktion (GLB-Clips).
const SCHAU_AKTION := {
	"verbeugen": "fressen",
	"drehen": "kopfschuetteln",
	"steigen": "sprung",
	"kompliment": "fressen",
	"kuss": "kopfschuetteln",
}

var disziplin := "springen"
var klasse := "holz"
var seed_wert := 1
var laeuft := false
var pausiert := false
var zeit := 0.0
var richter: RefCounted
var controller: RanchRideController
var stage: Node3D
var welt: Node3D
var geist: RcompGeist

var _pferd: RanchPferd
var _gooby: Node3D
var _rec: Dictionary = {}
var _pos_vorher := Vector3.ZERO
var _in_luft := false
var _bots: Array[Dictionary] = []
var _bot_pferde: Array = []
var _marker: MeshInstance3D
var _tonnen_nodes: Array = []
var _hindernis_nodes: Array = []
var _fertig_gemeldet := false
var _publikum: Node3D
var _publikum_zeit := 0.0
var _jubel := 0.0


func baue(cfg: Dictionary) -> void:
	disziplin = str(cfg.get("disziplin", "springen"))
	klasse = str(cfg.get("klasse", "holz"))
	seed_wert = int(_num(cfg.get("seed"), 1.0))
	_baue_stage(cfg)
	_baue_arena(cfg)
	_baue_richter(cfg)
	_baue_kurs_optik()
	_baue_reiter(cfg)
	_baue_geist(cfg)
	_baue_marker()
	_kamera_snap()


func starte() -> void:
	laeuft = true
	pausiert = false
	zeit = 0.0
	_fertig_gemeldet = false
	if controller != null:
		controller.active = true
	_pos_vorher = _spieler_pos()
	if disziplin != "schau":
		_rec = Ghost.neuer_recorder(disziplin, _pos_vorher)
	if geist != null:
		geist.starte()


func set_pausiert(an: bool) -> void:
	pausiert = an
	if controller != null:
		controller.active = laeuft and not an
	if geist != null:
		geist.laeuft = not an and geist.visible


func apply_size(size: Vector2) -> void:
	if stage != null:
		stage.call("apply_size", size)


## Schau: Kür-Tipp durchreichen (+ Pferde-Aktion bei Treffer).
func tippe() -> Dictionary:
	if disziplin != "schau" or richter == null or not laeuft:
		return {}
	var wertung: Dictionary = (richter as RcompRichterSchau).tippe()
	if str(wertung.get("typ", "")) == "treffer" and _pferd != null:
		var kommando := str((richter as RcompRichterSchau).kommandos[int(wertung["index"])]["id"])
		_pferd.spiele_aktion(str(SCHAU_AKTION.get(kommando, "kopfschuetteln")))
	return wertung


func hud_info() -> Dictionary:
	return richter.hud() if richter != null else {}


func to_screen(world: Vector3) -> Vector2:
	if stage == null:
		return Vector2.ZERO
	return stage.call("to_screen", world)


func spieler_screen() -> Vector2:
	return to_screen(_spieler_pos() + Vector3(0.0, 1.8, 0.0))


static func draw_calls() -> int:
	return Stage3DScript.draw_calls()


## Siegerehrung: Podium in die Arena, Top 3 drauf, Kamera davor.
## stand = Endstand aus RanchCompTurnier (Einträge mit ist_spieler/farbe).
func zeremonie(stand: Array) -> void:
	laeuft = false
	if controller != null:
		controller.active = false
	if geist != null:
		geist.stoppe()
	if _marker != null:
		_marker.visible = false
	var podium := Arena.baue_podium(welt, Vector3(0.0, 0.0, -2.0))
	for i in mini(3, stand.size()):
		var eintrag: Dictionary = stand[i]
		var punkt := podium.position + Arena.podium_punkt(i)
		if bool(eintrag.get("ist_spieler", false)) and controller != null:
			controller.position = punkt
			controller.rotation.y = PI
			controller.heading = PI
			if _pferd != null:
				_pferd.set_gait("stand")
		else:
			var paar: Array = RanchPferd.FELL.get(str(eintrag.get("farbe", "braun")), [])
			if paar.is_empty():
				paar = RanchPferd.FELL["braun"]
			var pferd: RanchPferd = RanchPferd.neu(paar[0], paar[1])
			pferd.position = punkt
			pferd.rotation.y = PI
			welt.add_child(pferd)
	if stage != null:
		stage.call("aim", Vector3(0.0, 4.6, 10.5), Vector3(0.0, 1.6, -2.0))
		stage.call("set_fov", 44.0)
		# W16 §6: 0.8 pumpte zusaetzlichen Glow auf die helle Sandflaeche.
		stage.call("pulse_glow", 0.4)
	# Siegerehrung = Dauer-Jubel auf der Tribuene.
	_jubel = 6.0


func _process(delta: float) -> void:
	if stage != null:
		stage.call("tick", delta)
	_marker_animieren(delta)
	_publikum_animieren(delta)
	if not laeuft or pausiert or richter == null:
		return
	zeit += delta
	var jetzt := _spieler_pos()
	if disziplin == "rennen":
		_bots_bewegen()
	var gait := controller.gait if controller != null else "stand"
	var events: Array = richter.tick(_pos_vorher, jetzt, gait, _in_luft, delta)
	for event: Variant in events:
		if event is Dictionary:
			_auf_event(event)
			ereignis.emit(event)
	if not _rec.is_empty() and controller != null:
		Ghost.tick(_rec, delta, jetzt, controller.heading, gait, _in_luft)
	_pos_vorher = jetzt
	_marker_setzen()
	if controller != null:
		_kamera_folgen(delta)
	if richter.fertig() and not _fertig_gemeldet:
		_beende()


## ------------------------------------------------------------------ Aufbau


func _baue_stage(_cfg: Dictionary) -> void:
	stage = Stage3DScript.new()
	add_child(stage)
	(
		stage
		. call(
			"build",
			{
				"sky_top": Color(0.45, 0.68, 0.93),
				"sky_horizon": Color(0.9, 0.95, 1.0),
				"fog_from": 60.0,
				"fog_to": 190.0,
				"far": 320.0,
				"shadow_distance": 42.0,
				# W14/GAMESQA-Request: Arena wirkte weiss ueberstrahlt (Audit
				# c=1) — die Stage-Defaults (ambient 0.6 + heller Himmel mit
				# sky_ambient 0.45 + Sonne 1.2 + kuehles Fill 0.4) summierten
				# sich auf den hellen Sand-/Gras-Albedos zur Ueberbelichtung,
				# und der Glow (Softlight ab Schwelle 0.9) bloomte den ganzen
				# sonnigen Boden. Belichtungs-Eichung nach dem hide_seek-
				# Muster (exposure runter statt Albedo-Radikalkur), dazu
				# gedrosseltes waermeres Umgebungslicht + Glow nur noch fuer
				# echte Highlights.
				# W16 Eich-Runde 2 (§6): 0.66 landete erst bei Boden-Luma
				# ~209, Zielband der "gut"-Referenz hide_seek ist ~150–170.
				# Exposure allein reichte nicht (0.56 -> immer noch ~210):
				# der eigentliche Treiber ist der TONEMAPPER (s. unten);
				# dazu Sonne/Ambient einen Tick runter. Gemessen (Filmic,
				# Boden-Luma springen): exposure 0.6/Sonne 1.15 -> 199,
				# 0.52/1.0 -> 184, 0.48/1.0 + Sand/Gras-Feintuning -> ~165.
				"exposure": 0.48,
				"glow": 0.22,
				"glow_threshold": 1.08,
				"ambient": 0.38,
				"ambient_color": Color(0.85, 0.84, 0.78),
				"sky_ambient": 0.3,
				"sun_energy": 1.0,
				"sun_color": Color(1.0, 0.92, 0.78),
				"fill_energy": 0.28,
			}
		)
	)
	# W16 Eich-Runde 2: das _3da-Kit mappt hart mit ACES — dessen Schulter
	# klemmt die helle Sandflaeche nahe Weiss fest (232 -> 212 trotz
	# exposure 0.66 -> 0.56 + Albedo-Senkung). Die "gut"-Referenz hide_seek
	# (_3dc-Kit) nutzt FILMIC: weichere Schulter, der Boden landet im
	# Zielband. Umstellung hier per Environment-Handle (Kit bleibt tabu).
	var env: Environment = stage.get("environment")
	if env != null:
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		# Zeichnung zurueckholen: auch Filmic staucht oben (hide_seek-Eichung).
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.05
		env.adjustment_saturation = 1.1
	welt = Node3D.new()
	stage.add_child(welt)


func _baue_arena(cfg: Dictionary) -> void:
	Arena.baue_boden(welt)
	Arena.baue_zaun(welt, Arena.ARENA_RECT)
	var tribuene := Arena.baue_tribuene(welt, int(_num(cfg.get("zuschauer"), 10.0)))
	_publikum = tribuene.get_meta("publikum") if tribuene.has_meta("publikum") else null
	Arena.baue_fahnen(welt, Arena.ARENA_RECT)
	Arena.baue_baeume(welt, seed_wert)


func _baue_richter(cfg: Dictionary) -> void:
	var balance: Dictionary = cfg.get("balance") if cfg.get("balance") is Dictionary else {}
	match disziplin:
		"springen":
			richter = RcompRichterSpringen.new()
		"dressur":
			richter = RcompRichterDressur.new()
		"gelaende":
			richter = RcompRichterGelaende.new()
		"rennen":
			richter = RcompRichterRennen.new()
		"trail":
			richter = RcompRichterTrail.new()
		"schau":
			richter = RcompRichterSchau.new()
		"tonnen":
			richter = RcompRichterTonnen.new()
		"zeit":
			richter = RcompRichterGelaende.new()
	match disziplin:
		"zeit":
			var route: Array[Dictionary] = []
			for tor: Variant in cfg.get("route", []):
				if tor is Dictionary:
					route.append(tor)
			(richter as RcompRichterGelaende).setup_route(route, _num(cfg.get("ziel_s"), 60.0))
		"rennen":
			_bots = []
			for bot: Variant in cfg.get("bots", []):
				if bot is Dictionary:
					_bots.append(bot)
			(richter as RcompRichterRennen).setup_bots(_bots)
		_:
			richter.setup(balance, klasse, seed_wert)
	if disziplin == "tonnen" and cfg.has("ideal_s"):
		(richter as RcompRichterTonnen).setze_ideal(_num(cfg.get("ideal_s"), 24.0))
	if disziplin == "schau":
		(richter as RcompRichterSchau).setze_basis(
			_num(cfg.get("pflege"), 70.0), _num(cfg.get("stil"), 40.0)
		)


func _baue_reiter(cfg: Dictionary) -> void:
	var pferd_dict: Dictionary = cfg.get("pferd") if cfg.get("pferd") is Dictionary else {}
	_pferd = RanchPferd.neu(RanchPferd.FELL["braun"][0], RanchPferd.FELL["braun"][1])
	if not pferd_dict.is_empty():
		_pferd.set_aussehen(pferd_dict)
	if disziplin == "schau":
		# Vorführen an der Hand: Pferd steht im Rampenlicht, Gooby daneben.
		_pferd.position = Vector3(0.0, 0.0, 0.0)
		_pferd.rotation.y = PI
		welt.add_child(_pferd)
		_gooby = GoobyActorScript.new()
		_gooby.position = Vector3(1.6, 0.0, 1.2)
		welt.add_child(_gooby)
		_gooby.call("mount", 0.62, 0.0, "wave")
		return
	controller = RanchRideController.new()
	controller.use_camera = false
	controller.keyboard_input = true
	controller.active = false
	controller.add_child(_pferd)
	controller.set_horse(_pferd)
	if not pferd_dict.is_empty():
		controller.set_pferd(pferd_dict)
	var pose := _start_pose()
	controller.position = pose["pos"]
	controller.heading = _num(pose.get("heading"), 0.0)
	controller.rotation.y = controller.heading
	var grenzen := _reit_grenzen()
	controller.set_bounds(Vector3.ZERO, grenzen)
	welt.add_child(controller)
	# Erst NACH dem Einhängen mounten: GoobyRig baut seinen AnimationTree
	# in _ready — ein Mount außerhalb des Baums lässt den Reiter in T-Pose.
	_gooby = GoobyActorScript.new()
	_gooby.position = Vector3(0.0, 1.3, 0.1)
	_pferd.add_child(_gooby)
	_gooby.call("mount", 0.62, PI, "idle")
	if disziplin == "springen":
		controller.set_hindernisse((richter as RcompRichterSpringen).hindernis_punkte())
		controller.sprung_gewertet.connect(
			func(wertung: String, _punkte: int) -> void:
				(richter as RcompRichterSpringen).notiere_sprung(wertung)
		)
	if disziplin == "rennen":
		_baue_rennen_bots()


func _baue_geist(cfg: Dictionary) -> void:
	var b64 := str(cfg.get("geist_b64", ""))
	if b64.is_empty() or disziplin == "schau" or disziplin == "rennen":
		return
	var node := RcompGeist.new()
	if node.lade(b64):
		geist = node
		welt.add_child(geist)
	else:
		node.free()


## ------------------------------------------------------------- Kurs-Optik


func _baue_kurs_optik() -> void:
	match disziplin:
		"springen":
			_optik_springen()
		"dressur":
			_optik_dressur()
		"gelaende":
			_optik_tore((richter as RcompRichterGelaende).tore)
		"zeit":
			_optik_tore((richter as RcompRichterGelaende).tore)
		"rennen":
			_optik_rennen()
		"trail":
			_optik_trail()
		"tonnen":
			_optik_tonnen()
		"schau":
			_optik_schau()


func _optik_springen() -> void:
	_hindernis_nodes = []
	for h: Dictionary in (richter as RcompRichterSpringen).kurs:
		var wurzel := Node3D.new()
		wurzel.position = h["pos"]
		welt.add_child(wurzel)
		for seite: float in [-1.0, 1.0]:
			_quader(wurzel, Vector3(0.0, 0.55, seite * 1.9), Vector3(0.2, 1.1, 0.2), HOLZ)
		var stange := _quader(wurzel, Vector3(0.0, 0.72, 0.0), Vector3(0.12, 0.12, 3.8), ROT)
		_quader(wurzel, Vector3(0.0, 0.4, 0.0), Vector3(0.1, 0.1, 3.8), CREME)
		_hindernis_nodes.append(stange)


func _optik_tore(tore: Array[Dictionary]) -> void:
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.06
	mast_mesh.bottom_radius = 0.08
	mast_mesh.height = 2.4
	mast_mesh.radial_segments = 6
	var masten := _multi(welt, mast_mesh, CREME, tore.size() * 2)
	var wimpel_mesh := PrismMesh.new()
	wimpel_mesh.size = Vector3(0.7, 0.5, 0.06)
	var wimpel := _multi(welt, wimpel_mesh, ROT, tore.size() * 2)
	var halb := RcompRichterGelaende.TOR_HALBBREITE
	for i in tore.size():
		var tor: Dictionary = tore[i]
		var quer: Vector3 = tor["quer"]
		for j in 2:
			var seite := -1.0 if j == 0 else 1.0
			var fuss: Vector3 = (tor["pos"] as Vector3) + quer * halb * seite
			masten.multimesh.set_instance_transform(
				i * 2 + j, Transform3D(Basis.IDENTITY, fuss + Vector3(0.0, 1.2, 0.0))
			)
			wimpel.multimesh.set_instance_transform(
				i * 2 + j,
				Transform3D(Basis(Vector3.RIGHT, PI * 0.5), fuss + Vector3(0.0, 2.3, 0.0))
			)


func _optik_rennen() -> void:
	var umfang := Kurs.rennen_umfang()
	var segmente := int(umfang / 4.0)
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(4.4, 0.05, 6.0)
	var band := _multi(welt, band_mesh, Color(0.62, 0.72, 0.4), segmente)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pfosten_mesh := BoxMesh.new()
	pfosten_mesh.size = Vector3(0.12, 0.9, 0.12)
	var pfosten := _multi(welt, pfosten_mesh, CREME, segmente * 2)
	for i in segmente:
		var s := umfang * float(i) / segmente
		var punkt := Kurs.rennen_punkt(s)
		var voraus := Kurs.rennen_punkt(s + 0.8)
		var tangente := (voraus - punkt).normalized()
		var winkel := atan2(tangente.x, tangente.z)
		var basis := Basis(Vector3.UP, winkel)
		band.multimesh.set_instance_transform(
			i, Transform3D(basis, punkt + Vector3(0.0, 0.03, 0.0))
		)
		var quer := Vector3(-tangente.z, 0.0, tangente.x)
		for j in 2:
			var seite := -1.0 if j == 0 else 1.0
			pfosten.multimesh.set_instance_transform(
				i * 2 + j,
				Transform3D(Basis.IDENTITY, punkt + quer * 3.4 * seite + Vector3(0.0, 0.45, 0.0))
			)
	# Startlinie auf der Süd-Geraden.
	var linie := _quader(welt, Kurs.rennen_punkt(0.0) + Vector3(0.0, 0.06, 0.0), Vector3.ONE, CREME)
	(linie.mesh as BoxMesh).size = Vector3(0.5, 0.04, 6.4)


func _optik_trail() -> void:
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(Kurs.TRAIL_LAENGE_M, 0.22, 0.14)
	var rails := _multi(welt, rail_mesh, HOLZ, Kurs.TRAIL_STATIONEN.size() * 2)
	for i in Kurs.TRAIL_STATIONEN.size():
		var station: Dictionary = Kurs.TRAIL_STATIONEN[i]
		var winkel := float(station["winkel"])
		var quer := Vector3(-sin(winkel), 0.0, cos(winkel))
		var basis := Basis(Vector3.UP, -winkel)
		for j in 2:
			var seite := -1.0 if j == 0 else 1.0
			var mitte: Vector3 = (
				(station["pos"] as Vector3)
				+ quer * (float(station["breite"]) + 0.35) * seite
				+ Vector3(0.0, 0.12, 0.0)
			)
			rails.multimesh.set_instance_transform(i * 2 + j, Transform3D(basis, mitte))


func _optik_dressur() -> void:
	var punkte: Array[Vector3] = []
	for figur: Dictionary in (richter as RcompRichterDressur).figuren:
		for p: Variant in figur["punkte"]:
			if p is Vector3:
				punkte.append(p)
	var kugel := SphereMesh.new()
	kugel.radius = 0.16
	kugel.height = 0.32
	kugel.radial_segments = 8
	kugel.rings = 4
	var dots := _multi(welt, kugel, Color(0.98, 0.9, 0.62), punkte.size())
	dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in punkte.size():
		dots.multimesh.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, punkte[i] + Vector3(0.0, 0.16, 0.0))
		)


func _optik_tonnen() -> void:
	_tonnen_nodes = []
	for pos in Kurs.TONNEN_POSITIONEN:
		var tonne := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.42
		mesh.bottom_radius = 0.46
		mesh.height = 1.05
		mesh.radial_segments = 10
		tonne.mesh = mesh
		tonne.material_override = RanchPferd.material(Color(0.36, 0.55, 0.78))
		tonne.position = pos + Vector3(0.0, 0.52, 0.0)
		welt.add_child(tonne)
		_tonnen_nodes.append(tonne)
	var linie := _quader(welt, Kurs.TONNEN_START + Vector3(0.0, 0.05, 0.0), Vector3.ONE, CREME)
	(linie.mesh as BoxMesh).size = Vector3(10.0, 0.04, 0.5)


func _optik_schau() -> void:
	var buehne := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 4.2
	mesh.bottom_radius = 4.4
	mesh.height = 0.12
	mesh.radial_segments = 24
	buehne.mesh = mesh
	buehne.material_override = RanchPferd.material(Color(0.97, 0.9, 0.75))
	buehne.position = Vector3(0.0, 0.06, 0.0)
	welt.add_child(buehne)


func _baue_rennen_bots() -> void:
	_bot_pferde = []
	for bot in _bots:
		var paar: Array = RanchPferd.FELL.get(str(bot.get("farbe", "braun")), [])
		if paar.is_empty():
			paar = RanchPferd.FELL["braun"]
		var pferd: RanchPferd = RanchPferd.neu(paar[0], paar[1])
		welt.add_child(pferd)
		_bot_pferde.append(pferd)
	_bots_bewegen()


func _baue_marker() -> void:
	if disziplin == "schau":
		return
	_marker = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.42
	mesh.height = 0.85
	mesh.radial_segments = 8
	_marker.mesh = mesh
	_marker.rotation.x = PI
	_marker.material_override = RanchPferd.material(MARKER_FARBE)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(_marker)
	_marker_setzen()


## --------------------------------------------------------------- Laufzeit


func _spieler_pos() -> Vector3:
	if controller != null:
		return controller.position
	return _pferd.position if _pferd != null else Vector3.ZERO


func _start_pose() -> Dictionary:
	var pose := {"pos": Vector3.ZERO, "heading": PI}
	match disziplin:
		"springen":
			pose = {"pos": Vector3(-27.0, 0.0, 11.0), "heading": -PI * 0.5}
		"dressur":
			pose = {"pos": Vector3(9.0, 0.0, 6.0), "heading": 0.0}
		"gelaende":
			var start := Vector3(0.0, 0.0, 30.0)
			var tore: Array[Dictionary] = (richter as RcompRichterGelaende).tore
			var richtung := PI if tore.is_empty() else _heading_zu(start, tore[0]["pos"])
			pose = {"pos": start, "heading": richtung}
		"zeit":
			var start_z := Vector3(0.0, 0.0, 58.0)
			var route: Array[Dictionary] = (richter as RcompRichterGelaende).tore
			var kurs := 0.0 if route.is_empty() else _heading_zu(start_z, route[0]["pos"])
			pose = {"pos": start_z, "heading": kurs}
		"rennen":
			pose = {"pos": Kurs.rennen_punkt(0.0), "heading": -PI * 0.5}
		"trail":
			pose = {"pos": Vector3(-25.0, 0.0, 8.0), "heading": -PI * 0.5}
		"tonnen":
			pose = {"pos": Kurs.TONNEN_START, "heading": 0.0}
	return pose


func _reit_grenzen() -> Vector2:
	match disziplin:
		"gelaende", "zeit":
			return Vector2(94.0, 69.0)
		"rennen":
			return Vector2(46.0, 26.0)
	return Vector2(29.0, 17.0)


func _bots_bewegen() -> void:
	var rennen := richter as RcompRichterRennen
	for i in _bots.size():
		var bot: Dictionary = _bots[i]
		var fortschritt := rennen.bot_fortschritt_m(bot, zeit)
		bot["fortschritt_m"] = fortschritt
		var punkt := Kurs.rennen_punkt(fortschritt)
		var voraus := Kurs.rennen_punkt(fortschritt + 0.8)
		var tangente := (voraus - punkt).normalized()
		var quer := Vector3(-tangente.z, 0.0, tangente.x)
		var lane := (float(i) - (_bots.size() - 1) * 0.5) * 1.15
		var pos := punkt + quer * lane
		bot["pos"] = pos
		if i >= _bot_pferde.size():
			continue
		var node: RanchPferd = _bot_pferde[i]
		node.position = pos
		node.rotation.y = atan2(-tangente.x, -tangente.z)
		var im_ziel := zeit >= _num(bot.get("zeit_s"), 90.0)
		node.set_gait("schritt" if im_ziel else "galopp")


func _marker_setzen() -> void:
	if _marker == null or richter == null:
		return
	var ziel := _marker_ziel()
	_marker.visible = not ziel.is_empty()
	if not ziel.is_empty():
		var punkt: Vector3 = ziel["pos"]
		_marker.position = Vector3(punkt.x, _marker.position.y, punkt.z)


func _marker_ziel() -> Dictionary:
	var ziel := {}
	match disziplin:
		"springen":
			var springen := richter as RcompRichterSpringen
			if springen.idx < springen.kurs.size():
				ziel = {"pos": springen.kurs[springen.idx]["pos"]}
		"gelaende", "zeit":
			var gelaende := richter as RcompRichterGelaende
			if gelaende.idx < gelaende.tore.size():
				ziel = {"pos": gelaende.tore[gelaende.idx]["pos"]}
		"trail":
			var trail := richter as RcompRichterTrail
			if not trail.fertig():
				ziel = {"pos": trail.aktuelle_station()["pos"]}
		"dressur":
			var dressur := richter as RcompRichterDressur
			if not dressur.fertig():
				ziel = {"pos": dressur.ziel_punkt()}
		"tonnen":
			var tonnen := richter as RcompRichterTonnen
			if tonnen.idx < tonnen.tonnen.size():
				ziel = {"pos": tonnen.tonnen[tonnen.idx]}
			else:
				ziel = {"pos": Kurs.TONNEN_START}
	return ziel


func _marker_animieren(delta: float) -> void:
	if _marker == null or not _marker.visible:
		return
	_marker.position.y = 2.1 + sin(Time.get_ticks_msec() / 1000.0 * TAU * 0.8) * 0.18
	_marker.rotate_y(delta * 2.2)


## Tribünen-Publikum: Takt-Sway immer, Jubel-Hüpfer nach guten Events /
## in der Zeremonie (M2). Reduced Motion lässt nur den Grund-Sway stehen.
func _publikum_animieren(delta: float) -> void:
	if _publikum == null:
		return
	_publikum_zeit += delta
	_jubel = maxf(0.0, _jubel - delta)
	var reduced := stage != null and bool(stage.call("reduced_motion"))
	Arena.publikum_tick(_publikum, _publikum_zeit, 0.0 if reduced else minf(1.0, _jubel))


## Sichtbare Reaktionen auf Richter-Events (Kippen/Fallen) — Callouts,
## Sounds und Juice übernimmt RcompHud.
func _auf_event(event: Dictionary) -> void:
	if str(event.get("typ", "")) in JUBEL_EVENTS:
		_jubel = maxf(_jubel, 2.2)
	match str(event.get("typ", "")):
		"tonne_um":
			var i := int(_num(event.get("index"), 0.0))
			if i < _tonnen_nodes.size():
				var tonne: MeshInstance3D = _tonnen_nodes[i]
				tonne.rotation.z = 1.35
				tonne.position.y = 0.3
		"abwurf":
			var j := int(_num(event.get("index"), 0.0))
			if j < _hindernis_nodes.size():
				var stange: MeshInstance3D = _hindernis_nodes[j]
				stange.rotation.x = 0.4
				stange.position.y = 0.18


func _beende() -> void:
	_fertig_gemeldet = true
	laeuft = false
	if controller != null:
		controller.active = false
	var ergebnis: Dictionary = richter.ergebnis(zeit)
	ergebnis["disziplin"] = disziplin
	var samples: Array = _rec.get("samples", []) if not _rec.is_empty() else []
	ergebnis["geist_b64"] = Ghost.to_b64(_rec) if samples.size() > 0 else ""
	lauf_fertig.emit(ergebnis)


## ----------------------------------------------------------------- Kamera


func _kamera_snap() -> void:
	if stage == null:
		return
	if disziplin == "schau":
		stage.call("aim", Vector3(0.0, 3.6, 9.5), Vector3(0.0, 1.3, 0.0))
		stage.call("set_fov", 42.0)
		return
	if controller == null:
		return
	var hinten := Vector3(sin(controller.heading), 0.0, cos(controller.heading))
	var von := controller.position + hinten * Feel.CAM_BACK + Vector3(0.0, Feel.CAM_HEIGHT, 0.0)
	stage.call("aim", von, controller.position + Vector3(0.0, 1.2, 0.0))


func _kamera_folgen(delta: float) -> void:
	var cam: Camera3D = stage.get("camera")
	if cam == null:
		return
	var hinten := Vector3(sin(controller.heading), 0.0, cos(controller.heading))
	var ziel := controller.position + hinten * Feel.CAM_BACK + Vector3(0.0, Feel.CAM_HEIGHT, 0.0)
	var f := Feel.cam_follow_factor(delta)
	cam.position = cam.position.lerp(ziel, f)
	cam.look_at(controller.position + Vector3(0.0, 1.2, 0.0) - hinten * 2.0)
	stage.set("_cam_base", cam.transform)
	stage.call("set_fov", Feel.fov_fuer_tempo(controller.tempo) * 0.92)


## ------------------------------------------------------------------ Helfer


static func _heading_zu(von: Vector3, nach: Vector3) -> float:
	var d := nach - von
	return atan2(-d.x, -d.z)


func _quader(parent: Node3D, pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mi.mesh = mesh
	mi.material_override = RanchPferd.material(farbe)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _multi(parent: Node3D, mesh: Mesh, farbe: Color, anzahl: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = maxi(0, anzahl)
	mmi.multimesh = mm
	mmi.material_override = RanchPferd.material(farbe)
	parent.add_child(mmi)
	return mmi


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
