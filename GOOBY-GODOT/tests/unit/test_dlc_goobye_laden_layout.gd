extends TestCase
## G8-PT2 Geometrie-Regression für den „Goo und Bye“-Laden (FIX-4):
##
##  - B2 HOCH: der Backen-Knopf wohnt in der Bottom-LEISTE (Layout-Zeile,
##    McGooby-Lektion) und überlappt in KEINEM Format mehr die Regal-Slots
##    — vorher lag die Unproject-Pill quer über Slot 0–2 und schluckte
##    deren Taps. Geprüft im Leitformat 2868×1320 quer UND hoch.
##  - B12: der Tür-Ausschnitt der rechten Wand (GoobyeLadenDeko) liegt im
##    Querformat KOMPLETT im Bild und der Kunden-Spawn (TUER_POS) führt
##    mittig durch die Öffnung — Kunden laufen sichtbar ein.
##  - Spielgefühl: Alwins 9-Uhr-Auftritt zeigt eine ECHTE AcBubble-
##    Sprechblase (Witz-Stil) mit seinem Tages-Spruch statt nur Toast.
##
## Fenster-Pinning nach dem Muster test_dlc_mcgooby_welle_b (_pin/_unpin).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const LadenSzene := preload("res://scripts/dlc/goobye/laden_scene.tscn")

## Leitformat iPhone 17 Pro Max (physische px, Screen-Scale 3) quer + hoch.
const LEIT_QUER := Vector2i(2868, 1320)
const LEIT_HOCH := Vector2i(1320, 2868)
## Sonderwunsch-Seed: alwin_menge(12345) == 2 (s. test_dlc_goobye_welle_b).
const ALWIN_SEED := 12345

var _dir_seq := 0
var _saved_root_size := Vector2i.ZERO


func test_leitformat_quer_backen_in_leiste_und_tuer_im_bild() -> void:
	await _pruefe_format(LEIT_QUER, true)


func test_leitformat_hoch_backen_in_leiste() -> void:
	await _pruefe_format(LEIT_HOCH, false)


func test_alwin_auftritt_zeigt_sprechblase() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs()
	var szene := _szene(gs)
	await wait_frames(3)
	szene.slot_tippen(0)
	szene.slot_tippen(1)
	szene.laden_oeffnen()
	await wait_frames(2)
	var blase: AcBubble = szene.find_child("AcBubble", true, false)
	assert_true(blase != null, "Alwins Auftritt erzeugt eine AcBubble (kein Toast mehr)")
	if blase != null:
		assert_eq(
			blase.current_line(),
			I18nService.t(GoobyeAlwin.auftritt_key(ALWIN_SEED)),
			"Blase trägt Alwins Tages-Spruch (Sonderwunsch-Seed)"
		)
		# Abgang räumt auf: spätestens mit Alwins Abgang ist die Blase weg
		# (dismiss in _kunde_weg) — nichts bleibt am UI-Layer hängen. Die
		# Lambda fängt die Instance-Id (nie das Objekt — freed-Capture
		# würde als ERROR ins Log rauschen, s. Warn-Budget-Wache).
		var blase_id := blase.get_instance_id()
		var weg := await wait_until(
			func() -> bool: return not is_instance_valid(instance_from_id(blase_id)), 10000
		)
		assert_true(weg, "Blase verschwindet mit Alwins Abgang")
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)


## ---------------------------------------------------------------- Prüfkern


## Ein Format pinnen und die B2-/B12-Geometrie der Laden-Szene prüfen.
func _pruefe_format(format: Vector2i, quer: bool) -> void:
	await _pin(format, 3.0)
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs()
	var szene := _szene(gs)
	await wait_frames(3)
	# Rotation nachstellen: Relayout mit GESETZTEN Knopf-Größen (der
	# _ready-Relayout sah frisch gebaute Controls noch mit size 0).
	tree.root.size_changed.emit()
	await wait_frames(3)
	var m := ScreenShell.metrics(szene.get_viewport())
	var canvas: Vector2 = m["canvas"]
	var leiste: Control = szene.find_child("LadenKnoepfe", true, false)
	var backen: Button = szene.find_child("Backen", true, false)
	assert_true(leiste != null, "Bottom-Leiste existiert")
	assert_true(backen != null, "Backen-Knopf existiert")
	if leiste == null or backen == null:
		szene.queue_free()
		await wait_frames(2)
		_teardown_gs(gs)
		await _unpin()
		return
	assert_true(
		backen.get_parent() == leiste,
		"B2: Backen wohnt in der Bottom-Leiste (Layout-Zeile statt Ofen-Overlay)"
	)
	var slots: Array[Button] = []
	for i in GoobyeRegal.SLOTS:
		var slot: Button = szene.find_child("Slot%d" % i, true, false)
		assert_true(slot != null, "Slot-Knopf %d existiert" % i)
		slots.append(slot)
	# Kern von B2: KEIN Leisten-Knopf überlappt IRGENDEINEN Slot-Knopf.
	for kind in leiste.get_children():
		if not (kind is Control):
			continue
		var knopf_rect := (kind as Control).get_global_rect()
		for slot in slots:
			assert_false(
				knopf_rect.intersects(slot.get_global_rect()),
				(
					"B2 (%s): %s überlappt %s nicht"
					% ["quer" if quer else "hoch", kind.name, slot.name]
				)
			)
	# Die ganze Leiste bleibt UNTER den Slot-Pills (Daumenzone).
	var slots_unterkante := 0.0
	for slot in slots:
		slots_unterkante = maxf(slots_unterkante, slot.get_global_rect().end.y)
	assert_true(
		leiste.get_global_rect().position.y > slots_unterkante,
		"B2: Leiste liegt komplett unter den Slot-Pills"
	)
	if quer:
		_pruefe_quer_details(szene, canvas, leiste, slots)
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)
	await _unpin()


## Nur Leitformat quer: eine Knopf-Zeile, Slots tippbar im Bild, Tür (B12)
## komplett im Kamerakegel und Kunden-Spawn mittig durch die Öffnung.
func _pruefe_quer_details(
	szene: GoobyeLadenScene, canvas: Vector2, leiste: Control, slots: Array[Button]
) -> void:
	var reihen := {}
	for kind in leiste.get_children():
		if kind is Control:
			reihen[roundi((kind as Control).global_position.y)] = true
	assert_eq(reihen.size(), 1, "Leitformat quer: alle 4 Leisten-Knöpfe in EINER Zeile")
	for slot in slots:
		var rect := slot.get_global_rect()
		assert_true(
			rect.position.x >= -1.0 and rect.end.x <= canvas.x + 1.0,
			"%s liegt horizontal im Bild" % slot.name
		)
	var cam := szene.get_viewport().get_camera_3d()
	assert_true(cam != null, "Laden-Kamera aktiv")
	for ecke: Vector3 in [
		Vector3(GoobyeLadenDeko.WAND_X, 0.1, GoobyeLadenDeko.TUER_Z_HINTEN),
		Vector3(GoobyeLadenDeko.WAND_X, 0.1, GoobyeLadenDeko.TUER_Z_VORN),
		Vector3(GoobyeLadenDeko.WAND_X, GoobyeLadenDeko.TUER_HOEHE, GoobyeLadenDeko.TUER_Z_HINTEN),
		Vector3(GoobyeLadenDeko.WAND_X, GoobyeLadenDeko.TUER_HOEHE, GoobyeLadenDeko.TUER_Z_VORN),
	]:
		var punkt := cam.unproject_position(ecke)
		assert_true(
			punkt.x >= 0.0 and punkt.x <= canvas.x and punkt.y >= 0.0 and punkt.y <= canvas.y,
			"B12: Tür-Ecke %s liegt im Bild (%s)" % [ecke, punkt]
		)
	# Spawn draußen, Laufweg mittig durch den Tür-Ausschnitt (B12-Vertrag
	# zwischen Szene und Deko-Baustein).
	assert_true(
		GoobyeLadenScene.TUER_POS.x > GoobyeLadenDeko.WAND_X,
		"Kunden-Spawn liegt AUSSERHALB der Wand (läuft sichtbar ein)"
	)
	assert_true(
		(
			GoobyeLadenScene.TUER_POS.z > GoobyeLadenDeko.TUER_Z_HINTEN
			and GoobyeLadenScene.TUER_POS.z < GoobyeLadenDeko.TUER_Z_VORN
		),
		"Kunden-Laufweg führt durch die Tür-Öffnung"
	)


## ---------------------------------------------------------------- Helfer


## Echter GameState mit gekauftem Laden (Startlager!) + gesehenem Intro.
func _fresh_gs() -> Node:
	GoobyeState.register_slice()
	_dir_seq += 1
	var dir := "user://goobye_laden_layout/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", 12)
	gs.set_value("economy.coins", GoobyeKatalog.preis() + 200)
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_OK, "Vorbereitung: Laden gekauft")
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(GoobyeState.SLICE_ID)
	GoobyeState.reset_for_tests()
	GoobyeKatalog.registry_override = null
	GoobyeKatalog.reset_cache()


func _szene(gs: Node) -> GoobyeLadenScene:
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.seed_override = ALWIN_SEED
	szene.tempo = 0.05
	szene.auto_navigate = false
	tree.root.add_child(szene)
	return szene


## Fenster fürs Leitformat pinnen/zurückstellen (Muster test_g7_phone).
func _pin(size: Vector2i, screen_scale := 0.0) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	UiScale.screen_scale_override = screen_scale
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.screen_scale_override = 0.0
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		_saved_root_size = Vector2i.ZERO
	tree.root.size_changed.emit()
	await wait_frames(2)
