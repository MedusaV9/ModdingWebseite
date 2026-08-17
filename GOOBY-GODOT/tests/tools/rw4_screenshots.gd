extends SceneTree
## RW-4-Screenshot-Tool (KEIN Test): rendert die Review-Artefakte des
## Ranch-Bau-Grids und des Reit-Dorfs Hufingen und misst je Ansicht die
## Draw-Calls (Budget: <= 400). Aufruf (echter Renderer):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/rw4_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RW4"
const SETTLE := 45

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const RanchPlaySlices := preload("res://scripts/ranch/data/ranch_play_slices.gd")

var _max_calls := 0


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	await _bau_shots()
	await _dorf_shots()
	print("RW4-Screenshots fertig -> %s (max draw_calls=%d)" % [OUT_DIR, _max_calls])
	quit(0)


func _frisches_gs(coins: int) -> Node:
	RanchState.register_slice()
	var dir := "user://rw4_shots/state_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


## ------------------------------------------------------------ Bau-Modus


func _bau_shots() -> void:
	var gs := _frisches_gs(60000)
	var szene: PackedScene = load("res://scenes/ranch/dorf/ranch_bau_hof.tscn")
	var bau: Node3D = szene.instantiate()
	bau.game_state_override = gs
	root.add_child(bau)
	await _settle(20)
	# Vorher: Bestand (migrierte Stallboxen + Weide) mit Grid, Zonen gesperrt.
	bau._pivot = Vector3(24.0, 0.0, 27.0)
	bau._yaw = 0.55
	bau._dist = 52.0
	await _settle(SETTLE)
	await _shot("bau_ranch_vorher.png")
	# Ghost-Vorschau: Reithalle schwebt als Vorschau ueber dem Grid.
	bau._waehle_item("reithalle")
	var ziel: Vector3 = Vector3(4.5 * 3.0, 0.0, 11.5 * 3.0)
	bau._update_ghost(bau._kamera.unproject_position(ziel))
	await _settle(20)
	await _shot("bau_grid_vorschau_ghost.png")
	bau._ghost_weg()
	# Ausbau buchen: Bestand upgraden + neue Anlagen, Deko, Boeden, Zaeune.
	_buche(RanchBauState.zone_freischalten(gs, "nord"), "zone nord")
	_buche(RanchBauState.zone_freischalten(gs, "ost"), "zone ost")
	_buche(RanchBauState.ausbauen(gs, "stallboxen"), "stallboxen +1")
	_buche(RanchBauState.ausbauen(gs, "stallboxen"), "stallboxen +1")
	_buche(RanchBauState.ausbauen(gs, "weide"), "weide +1")
	_buche(RanchBauState.platziere(gs, "heulager", Vector2i(1, 12), 0), "heulager")
	_buche(RanchBauState.ausbauen(gs, "heulager"), "heulager +1")
	_buche(RanchBauState.platziere(gs, "wasserstelle", Vector2i(4, 12), 0), "wasserstelle")
	_buche(RanchBauState.platziere(gs, "waschplatz", Vector2i(1, 4), 0), "waschplatz")
	_buche(RanchBauState.platziere(gs, "sattelkammer", Vector2i(4, 4), 0), "sattelkammer")
	_buche(RanchBauState.platziere(gs, "fuehranlage", Vector2i(7, 2), 0), "fuehranlage")
	_buche(RanchBauState.platziere(gs, "reithalle", Vector2i(10, 6), 0), "reithalle")
	_buche(RanchBauState.ausbauen(gs, "reithalle"), "reithalle +1")
	_buche(RanchBauState.platziere(gs, "parcours", Vector2i(10, 11), 0), "parcours")
	_buche(RanchBauState.platziere(gs, "tribuene", Vector2i(10, 3), 0), "tribuene")
	for i in 4:
		_buche(RanchBauState.platziere(gs, "weg_schotter", Vector2i(3, 10 + i), 0), "weg")
	for i in 4:
		_buche(RanchBauState.platziere(gs, "weg_pflaster", Vector2i(6 + i, 11), 0), "weg")
	_buche(RanchBauState.platziere(gs, "bank_holz", Vector2i(4, 10), 0), "bank")
	_buche(RanchBauState.platziere(gs, "laterne", Vector2i(5, 11), 0), "laterne")
	_buche(RanchBauState.platziere(gs, "fahne", Vector2i(9, 12), 0), "fahne")
	_buche(RanchBauState.platziere(gs, "beet_blumen", Vector2i(2, 10), 0), "beet")
	_buche(RanchBauState.platziere(gs, "vogelhaus", Vector2i(0, 10), 0), "vogelhaus")
	_buche(RanchBauState.platziere(gs, "blumenkuebel", Vector2i(6, 12), 0), "kuebel")
	# Kanten-Zaunring um die migrierte Weide (Zellen x5..8, z7..10) —
	# der fertige Ring kommt aus RanchGridData.weide_ring (mit Tor-Lücke).
	for kante: Dictionary in RanchGridData.weide_ring(Rect2i(5, 7, 4, 4), 1):
		_buche(
			RanchBauState.platziere_kante(gs, "zaun_holz", kante["cell"], str(kante["seite"])),
			"zaun %s" % str(kante)
		)
	bau._rebuild_welt()
	bau._refresh_ui()
	await _settle(SETTLE)
	await _shot("bau_ranch_nachher_ausgebaut.png")
	# Info-Panel: Ausbaustufe + Nutzen-Text an den Stallboxen.
	bau._waehle_an_position(Vector3(1.5 * 3.0, 0.0, 8.0 * 3.0))
	await _settle(15)
	await _shot("bau_info_ausbaustufe.png")
	bau._auswahl_weg()
	# Nahaufnahme: Kanten-Zaeune um die Weide + Wege.
	bau._pivot = Vector3(21.0, 0.0, 27.0)
	bau._dist = 26.0
	bau._yaw = -0.7
	await _settle(SETTLE)
	await _shot("bau_zaun_kanten_nah.png")
	bau.queue_free()
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()


## ------------------------------------------------------------ Hufingen


func _dorf_shots() -> void:
	var gs := _frisches_gs(8000)
	(
		gs
		. set_value(
			"ranch.tiere.pferde",
			{
				"p1": RanchPlaySlices.neues_pferd("Keks", "braun"),
				"p2": RanchPlaySlices.neues_pferd("Wolke", "weiss"),
			}
		)
	)
	var szene: PackedScene = load("res://scenes/ranch/dorf/hufingen.tscn")
	var dorf: Node3D = szene.instantiate()
	dorf.game_state_override = gs
	dorf.receive_params({"via": "ritt"})
	root.add_child(dorf)
	await _settle(30)
	# Ortsschild: Reiter dicht davor (< 9 m loest die ENTDECKUNG aus,
	# der Toast "Hufingen entdeckt" ist im Shot sichtbar — kurz settlen,
	# der Toast lebt nur 3 Sekunden).
	dorf.reiter.springe_zu(
		Vector3(545.0, RanchGelaende.hoehe(545.0, 519.5), 519.5), deg_to_rad(-110.0)
	)
	await _settle(10)
	await _shot("dorf_ortsschild_hufingen.png")
	# Plaza-Blick: Brunnen, Theken, Laternen.
	dorf.reiter.springe_zu(
		Vector3(580.0, RanchGelaende.hoehe(580.0, 528.0), 528.0), deg_to_rad(-125.0)
	)
	await _settle(SETTLE)
	await _shot("dorf_plaza_ueberblick.png")
	# Theke der Pferdehaendlerin: Reiter dicht davor (< 6.5 m zeigt den
	# Laden-Prompt), seitlich versetzt, damit Theke + NPC frei stehen.
	dorf.reiter.springe_zu(
		Vector3(575.2, RanchGelaende.hoehe(575.2, 566.0), 566.0), deg_to_rad(132.0)
	)
	await _settle(SETTLE)
	await _shot("dorf_theke_pferdehaendlerin.png")
	# Laden-Screens (AC-Look): 3 Laeden innen + Haendlerin mit Angebot.
	for laden_id: String in ["reitladen", "futterhof", "schmiede", "pferdehaendlerin"]:
		dorf.oeffne_laden(laden_id)
		await _settle(25)
		await _shot("laden_%s.png" % laden_id)
		dorf._schliesse_laden()
		await _settle(5)
	dorf.queue_free()
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()


## ------------------------------------------------------------ Helfer


func _buche(ergebnis: Dictionary, was: String) -> void:
	if not bool(ergebnis.get("ok", false)):
		print("BUCHUNG FEHLGESCHLAGEN: %s -> %s" % [was, str(ergebnis.get("fehler"))])


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(datei: String) -> void:
	await process_frame
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_max_calls = maxi(_max_calls, calls)
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("shot: %s  draw_calls=%d" % [datei, calls])
