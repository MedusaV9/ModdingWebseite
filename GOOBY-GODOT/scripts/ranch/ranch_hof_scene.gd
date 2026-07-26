class_name RanchHofScene
extends Node3D
## Die Gooby Ranch (RANCH-1) — das Riesenfeld: großzügige Außenwelt,
## deutlich größer als die Stadtkacheln (Pack-Weltdaten, Default 480×380 m),
## aber performant über MultiMesh-Gruppen + Sichtweiten (Budget ≤ 400
## Draw-Calls in der Ranch-Ansicht). Weiden mit Gräsern, Koppeln mit
## Zäunen, Scheune, Stall, Ranch-Haus, Wassertrog, Heulager, Reitplatz,
## Schotterwege, Windrad, Teich — und die Gooby-Pferde (Idle/Trab/Galopp).
##
## Router-Contract (W1a): `ready_for_reveal` nach dem Aufbau;
## `receive_params({"frisch_gekauft": true})` zeigt den Kauf-Toast.
## Tests injizieren `game_state_override` VOR add_child.

signal ready_for_reveal

const GOOBY_GLB := "res://assets/character/gooby.glb"

var game_state_override: Object
## Tests/Screenshots erzwingen eine Uhrzeit (< 0 = echte Systemzeit).
var stunde_override := -1.0

var plan: Dictionary = {}
var pferde: Array[RanchPferd] = []
var cam: Camera3D

var _bau: RanchBau
var _windrad_rotor: Node3D
var _toast: Node
var _frisch_gekauft := false
var _galopp_an := false
var _trab_winkel := 0.0
var _cam_zeit := 0.0


func _ready() -> void:
	plan = RanchWelt.hof_plan()
	_bau = RanchBau.new(self)
	_bau.baue_licht(_stunde())
	_baue_gelaende()
	_baue_gebaeude()
	_baue_koppeln()
	_baue_gruen()
	_baue_tiere()
	_baue_gooby()
	_baue_kamera()
	_baue_hud()
	ready_for_reveal.emit()
	_zeige_toast.call_deferred(
		I18nService.t("ranch.tor.gekauft" if _frisch_gekauft else "ranch.hof.willkommen")
	)


func _process(delta: float) -> void:
	if _windrad_rotor != null:
		_windrad_rotor.rotation.z += delta * 0.9
	_bewege_trab_pferd(delta)
	_kamera_drift(delta)


## Router-Params (W1a-Contract).
func receive_params(params: Dictionary) -> void:
	_frisch_gekauft = bool(params.get("frisch_gekauft", false))


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


## Alle Pferde auf eine Gangart schalten (HUD-Knopf „Galopp!“).
func setze_gangart(gang: String) -> void:
	for pferd in pferde:
		pferd.set_gangart(gang)


## ---------------------------------------------------------------- Aufbau


func _stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0


func _baue_gelaende() -> void:
	var breite := float(plan["breite"])
	var tiefe := float(plan["tiefe"])
	_bau.baue_boden(breite, tiefe)
	for weg: Dictionary in plan["wege"]:
		_bau.baue_weg(weg["von"], weg["bis"], float(weg["breite"]))
	_bau.baue_tor(plan["tor_pos"], I18nService.t("ranch.fahrt.schild_ranch"))
	_bau.baue_reitplatz(plan["reitplatz"])
	_bau.baue_teich(plan["teich_pos"])
	_bau.baue_trog(plan["trog_pos"])
	_windrad_rotor = _bau.baue_windrad(plan["windrad_pos"])


func _baue_gebaeude() -> void:
	for geb: Dictionary in plan["gebaeude"]:
		var pos: Vector3 = geb["pos"]
		var rot := float(geb["rot_grad"])
		match str(geb["id"]):
			"scheune":
				_bau.baue_scheune(pos, rot)
			"stall":
				_bau.baue_stall(pos, rot)
			"haus":
				_bau.baue_haus(pos, rot)
			"heulager":
				_bau.baue_heulager(pos, rot)


## Koppel-Zäune als MultiMesh (ein Draw-Call je Mesh-Sorte) + Torpfosten.
func _baue_koppeln() -> void:
	var latten: Array = []
	for koppel: Dictionary in plan["koppeln"]:
		for eintrag: Dictionary in RanchWelt.zaun_ring(
			koppel["rect"], 2.6, str(koppel["tor_seite"])
		):
			var basis := Basis(Vector3.UP, float(eintrag["rot"])).scaled(Vector3.ONE * 2.6)
			latten.append(Transform3D(basis, eintrag["pos"]))
	# Reitplatz-Zaun ohne Tor-Lücke ist Teil desselben MultiMeshes.
	for eintrag: Dictionary in RanchWelt.zaun_ring(plan["reitplatz"], 2.6, "ost"):
		var basis := Basis(Vector3.UP, float(eintrag["rot"])).scaled(Vector3.ONE * 2.6)
		latten.append(Transform3D(basis, eintrag["pos"]))
	_bau.baue_multimesh(self, "%s/natur/fence_simple.glb" % RanchBau.ASSETS, latten)


## Gras/Blumen/Bäume als gestreute MultiMesh-Gruppen mit Sichtweiten-Ende.
func _baue_gruen() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(RanchWelt.welt_daten()["deko_seed"]) + 99
	var gras: Array = []
	var blumen_gelb: Array = []
	var blumen_rot: Array = []
	for zone: Rect2 in plan["gras_zonen"]:
		for _i in 2400:
			var pos := Vector3(
				rng.randf_range(zone.position.x, zone.end.x),
				0.0,
				rng.randf_range(zone.position.y, zone.end.y)
			)
			# Hof-Mitte + Wege frei halten, damit der Schotter lesbar bleibt.
			if absf(pos.x) < 24.0 and pos.z > -10.0:
				continue
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 3.4)
			gras.append(Transform3D(basis, pos))
			if rng.randf() < 0.1:
				var blumen_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 3.0)
				var ziel := blumen_gelb if rng.randf() < 0.5 else blumen_rot
				ziel.append(Transform3D(blumen_basis, pos + Vector3(1.2, 0.0, 0.8)))
	_bau.baue_multimesh(
		self, "%s/natur/grass_large.glb" % RanchBau.ASSETS, gras, "", RanchBau.KLEINTEIL_SICHT_M
	)
	_bau.baue_multimesh(
		self,
		"%s/natur/flower_yellowA.glb" % RanchBau.ASSETS,
		blumen_gelb,
		"",
		RanchBau.KLEINTEIL_SICHT_M
	)
	_bau.baue_multimesh(
		self,
		"%s/natur/flower_redA.glb" % RanchBau.ASSETS,
		blumen_rot,
		"",
		RanchBau.KLEINTEIL_SICHT_M
	)
	var baeume: Array = []
	var i := 0
	for pos: Vector3 in plan["baeume"]:
		var basis := Basis(Vector3.UP, float(i) * 1.7).scaled(Vector3.ONE * 9.0)
		baeume.append(Transform3D(basis, pos))
		i += 1
	_bau.baue_multimesh(self, "%s/natur/tree_oak.glb" % RanchBau.ASSETS, baeume)


## Pferde aus dem Save (`ranch.tiere.pferde`, RANCH-2-Struktur — nach dem
## Kauf) bzw. als Katalog-Vorschau; dazu Kühe, Schafe und Hühner an ihren
## Plan-Plätzen. Nachts (RanchOffline.wohin) stehen die Pferde am Stall.
func _baue_tiere() -> void:
	var gs := game_state()
	var pferd_daten: Array = []
	var bestand := RanchState.pferde(gs)
	for pferd_id: Variant in bestand:
		if bestand[pferd_id] is Dictionary:
			pferd_daten.append(bestand[pferd_id])
	if pferd_daten.is_empty():
		for eintrag: Dictionary in RanchKatalog.tiere():
			if str(eintrag.get("art", "")) == "pferd" and bool(eintrag.get("start", false)):
				pferd_daten.append(eintrag)
	var plaetze: Array = plan["pferde"]
	if RanchOffline.wohin(_stunde()) == "stall":
		plaetze = _stall_plaetze(plaetze.size())
	for i in mini(pferd_daten.size(), plaetze.size()):
		var farben := _pferd_farben(pferd_daten[i])
		var pferd := RanchPferd.neu(farben["fell"], farben["maehne"])
		pferd.position = plaetze[i]
		pferd.rotation.y = float(i) * 1.9
		add_child(pferd)
		pferde.append(pferd)
	if pferde.size() > 1:
		pferde[1].set_gangart(RanchPferd.GANG_TRAB)
	for pos: Vector3 in plan["kuehe"]:
		var kuh := RanchTier.neu("kuh", Color("#F5EFE4"), Color("#7A5C43"))
		kuh.position = pos
		kuh.rotation.y = pos.x * 0.3
		add_child(kuh)
	for pos: Vector3 in plan["schafe"]:
		var schaf := RanchTier.neu("schaf", Color("#F7F3EA"))
		schaf.position = pos
		schaf.rotation.y = pos.z * 0.4
		add_child(schaf)
	for pos: Vector3 in plan["huehner"]:
		var huhn := RanchTier.neu("huhn", Color("#F2C14E"))
		huhn.position = pos
		huhn.rotation.y = pos.x
		add_child(huhn)


## Fell/Mähne aus Save-Pferd (farbeHex/maehneHex bzw. Fellfarben-Id) oder
## Katalog-Eintrag (farbe/maehne als Hex).
func _pferd_farben(daten: Dictionary) -> Dictionary:
	var fell_hex := str(daten.get("farbeHex", daten.get("farbe", "")))
	if not fell_hex.begins_with("#"):
		var paar: Array = RanchPferd.FELL.get(fell_hex, RanchPferd.FELL["braun"])
		return {"fell": paar[0], "maehne": paar[1]}
	var fell := Color.from_string(fell_hex, Color("#D9A066"))
	var maehne_hex := str(daten.get("maehneHex", daten.get("maehne", "")))
	var maehne := fell.darkened(0.4)
	if maehne_hex.begins_with("#"):
		maehne = Color.from_string(maehne_hex, maehne)
	return {"fell": fell, "maehne": maehne}


## Stall-Aufstellung für die Nacht (RANCH-2-Tagesrhythmus, §3).
func _stall_plaetze(anzahl: int) -> Array:
	var stall_pos := Vector3.ZERO
	for geb: Dictionary in plan["gebaeude"]:
		if str(geb["id"]) == "stall":
			stall_pos = geb["pos"]
	var tiefe := RanchWelt.gebaeude_groesse("stall").z
	var out: Array = []
	for i in anzahl:
		out.append(stall_pos + Vector3(float(i) * 3.2 - 3.2, 0.0, tiefe / 2.0 + 4.0))
	return out


## Gooby selbst steht als Ranch-Besucher am Hauptweg (Kulissen-billig,
## Muster CityScene-Fußgänger: nur GLB + AnimationPlayer).
func _baue_gooby() -> void:
	if not ResourceLoader.exists(GOOBY_GLB):
		return
	var szene: PackedScene = load(GOOBY_GLB)
	var gooby: Node3D = szene.instantiate()
	gooby.scale = Vector3.ONE * 1.6
	gooby.position = Vector3(4.0, 0.0, float(plan["tor_pos"].z) - 100.0)
	gooby.rotation.y = PI
	add_child(gooby)
	var player: AnimationPlayer = gooby.find_child("AnimationPlayer", true, false)
	if player != null:
		for kandidat: String in ["idle", "idle-loop"]:
			if player.has_animation(kandidat):
				player.play(kandidat)
				break


func _baue_kamera() -> void:
	cam = Camera3D.new()
	cam.name = "HofKamera"
	# Establishing-Blick MITTEN im Feld: Schotterweg, Haus, Scheune, Stall
	# und Windrad füllen das Bild — das Tor hat seine eigene Ankunftsszene.
	cam.position = Vector3(-40.0, 14.0, 108.0)
	cam.look_at_from_position(cam.position, Vector3(16.0, 3.0, 0.0), Vector3.UP)
	cam.fov = 58.0
	cam.current = true
	add_child(cam)


func _baue_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	var hud := Control.new()
	hud.name = "HofHud"
	hud.theme = ThemeService.theme()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	var titel := Label.new()
	titel.theme_type_variation = "TitleLabel"
	titel.text = I18nService.t("ranch.hof.titel")
	titel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)
	hud.add_child(titel)
	var stadt := Button.new()
	stadt.theme_type_variation = "GhostButton"
	stadt.text = I18nService.t("ranch.fahrt.zur_stadt")
	stadt.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	stadt.pressed.connect(_on_zur_stadt)
	hud.add_child(stadt)
	var galopp := Button.new()
	galopp.theme_type_variation = "PrimaryButton"
	galopp.toggle_mode = true
	galopp.text = I18nService.t("ranch.hof.pferde_galopp")
	galopp.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24
	)
	galopp.toggled.connect(_on_galopp_toggled)
	hud.add_child(galopp)
	# RW-1: Ausritt in die offene Ranch-Region (Zonen, Wetter, Wildtiere).
	var ausritt := Button.new()
	ausritt.theme_type_variation = "PrimaryButton"
	ausritt.text = I18nService.t("rwelt.hud.ausreiten")
	ausritt.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24
	)
	ausritt.pressed.connect(_on_ausreiten)
	hud.add_child(ausritt)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	layer.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## ------------------------------------------------------------- Bewegung


func _on_galopp_toggled(an: bool) -> void:
	_galopp_an = an
	setze_gangart(RanchPferd.GANG_GALOPP if an else RanchPferd.GANG_IDLE)
	if not an and pferde.size() > 1:
		pferde[1].set_gangart(RanchPferd.GANG_TRAB)


## Pferd 2 läuft eine Ellipse in der Pferdekoppel (Trab/Galopp).
func _bewege_trab_pferd(delta: float) -> void:
	if pferde.size() < 2:
		return
	var pferd := pferde[1]
	if pferd.gangart == RanchPferd.GANG_IDLE:
		return
	var koppel: Rect2 = plan["koppeln"][0]["rect"]
	var mitte := koppel.get_center()
	var rx := koppel.size.x / 2.0 - 10.0
	var rz := koppel.size.y / 2.0 - 10.0
	var tempo := 0.55 if pferd.gangart == RanchPferd.GANG_GALOPP else 0.3
	_trab_winkel += delta * tempo
	pferd.position = Vector3(
		mitte.x + cos(_trab_winkel) * rx, 0.0, mitte.y + sin(_trab_winkel) * rz
	)
	# Blickrichtung des Modells ist -z (RANCH-2-Vertrag): -Fahrtrichtung.
	pferd.rotation.y = atan2(sin(_trab_winkel) * rx, -cos(_trab_winkel) * rz)


## Sanfter Kamera-Drift über den Hof (einladender Establishing-Blick).
func _kamera_drift(delta: float) -> void:
	if cam == null:
		return
	_cam_zeit += delta
	cam.position.x = -40.0 + sin(_cam_zeit * 0.08) * 8.0
	cam.look_at(Vector3(16.0, 3.0, 0.0), Vector3.UP)


func _on_zur_stadt() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		_zeige_toast("(Route city — Router fehlt)")
		return
	router.goto(&"city", {})


## Ausritt in die offene Ranch-Region (RW-1) — Spawn am Hof-Plateau.
func _on_ausreiten() -> void:
	if not RanchWeltRouten.reite_los(get_tree(), {"spawn_zone": "hof"}):
		_zeige_toast("(Route ranch/welt — Router fehlt)")


func _zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)
