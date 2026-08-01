extends TestCase
## G4-NACHFIX — Regressions-Schutz für die FB3-Nachfix-Welle: Geometrie-
## Checks der Fix-Formeln auf den 6 umgebauten Screens (postkarten, codes,
## dlc, galerie, ikea, customize). Simuliert die FB3-Audit-Formate über
## UiScale.screen_scale_override + insets_override (Muster fb3_ui_audit
## SIZES) und prüft: Insets-Polster im Scroll-Kind, physische Touch-Floors,
## bedarfsbasierter Kopfzeilen-Umbruch (Min-Breiten-Falle G2 §4.4),
## Kachel-/Cover-Klemmen. Fenster wird VOR dem Screen-Bau gepinnt und am
## Testende zurückgesetzt.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW := 1700000000000
const BASIS := Vector2i(1280, 720)
## iPhone hoch (fb3_ui_audit SIZES): Fenster-px, screen_scale, Insets in pt.
const HOCH_FENSTER := Vector2i(1179, 2556)
const HOCH_SCALE := 3.0
const HOCH_INSETS_PT: Array = [0.0, 59.0, 0.0, 34.0]
## iPhone quer flach (828 pt kurz, Home-Indicator 21 pt).
const QUER_FENSTER := Vector2i(1792, 828)
const QUER_SCALE := 2.0
const QUER_INSETS_PT: Array = [48.0, 0.0, 48.0, 21.0]


## GameState-Double: dotted get/set + update(mutator) wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

	func _init() -> void:
		s = SaveSchema.default_state(NOW)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


var _root_size := Vector2i.ZERO
var _user_factor := 1.0
var _text_factor := 1.0
var _extra_inset := 0.0
var _dir_seq := 0


## Fenster + UiScale-Statics VOR dem Screen-Bau pinnen (deterministische
## Metriken wie im FB3-Audit): insets_pt = [l, t, r, b] in Punkten.
func _pin(fenster: Vector2i, scale: float, insets_pt: Array) -> void:
	_root_size = tree.root.size
	_user_factor = UiScale.user_factor
	_text_factor = UiScale.text_factor
	_extra_inset = UiScale.extra_inset
	UiScale.user_factor = 1.0
	UiScale.text_factor = 1.0
	UiScale.extra_inset = 0.0
	UiScale.screen_scale_override = scale
	tree.root.size = fenster
	await wait_frames(2)
	if scale > 0.0 and insets_pt.size() == 4:
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var pt_kurz := minf(float(fenster.x), float(fenster.y)) / scale
		var px_pt := minf(canvas.x, canvas.y) / pt_kurz
		var l := float(insets_pt[0]) * px_pt
		var t := float(insets_pt[1]) * px_pt
		var r := float(insets_pt[2]) * px_pt
		var b := float(insets_pt[3]) * px_pt
		UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)


## Alles zurücksetzen — Overrides ZUERST, dann die Fenstergröße.
func _unpin() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	UiScale.user_factor = _user_factor
	UiScale.text_factor = _text_factor
	UiScale.extra_inset = _extra_inset
	tree.root.size = _root_size


func _drop(screen: Node) -> void:
	screen.queue_free()
	await wait_frames(2)
	_unpin()


## Erwartetes Polster des Scroll-Kinds: Safe-Inset + EDGE_Y·f (gerundet).
func _polster_soll(m: Dictionary, seite: String) -> int:
	var insets: Dictionary = m["insets"]
	return roundi(float(insets[seite]) + ScreenShell.EDGE_Y * float(m["f"]))


## ------------------------------------------------ postkarten_screen.gd


func test_postkarten_polster_touchfloor_und_kopfumbruch() -> void:
	await _pin(HOCH_FENSTER, HOCH_SCALE, HOCH_INSETS_PT)
	var gs := FakeGameState.new()
	(gs.s["vacation"] as Dictionary)["visited"] = {"beach": true, "space": true, "harbor": true}
	var screen: PostkartenScreen = PostkartenScreen.new()
	screen.gs_override = gs
	screen.now_override = NOW
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	var m := ScreenShell.metrics(screen.get_viewport())
	var insets: Dictionary = m["insets"]
	assert_true(float(insets["top"]) > 0.0, "Notch-Simulation aktiv (top-Inset > 0)")
	var pad := screen.get("_pad") as MarginContainer
	assert_true(pad != null, "SafePolster (Scroll-Kind) existiert")
	assert_eq(
		pad.get_theme_constant("margin_top"),
		_polster_soll(m, "top"),
		"oberes Polster = Notch-Inset + EDGE_Y·f (Zurück nicht mehr bei y=0)"
	)
	assert_eq(
		pad.get_theme_constant("margin_bottom"),
		_polster_soll(m, "bottom"),
		"unteres Polster = Home-Inset + EDGE_Y·f"
	)
	var floor_px := float(m["floor_px"])
	var back := screen.get("_back") as Button
	assert_true(
		minf(back.custom_minimum_size.x, back.custom_minimum_size.y) >= floor_px - 0.5,
		"Zurück hält den physischen Touch-Floor (44 pt)"
	)
	var claim := screen.find_child("Claim_3", true, false) as Button
	assert_true(claim != null, "Stufe 3 bietet den Abholen-Knopf an")
	if claim != null:
		assert_true(claim.custom_minimum_size.y >= floor_px - 0.5, "Abholen hält den Touch-Floor")
	# Kopfzeilen-Umbruch: hoch/f=3 verlangte die Kopfzeile 1591 px Minbreite
	# (> 1136er-Klemme) und drückte die GANZE Spalte auf — der Zähler-Chip
	# muss deshalb in der eigenen Zeile stehen.
	var chip := screen.get("_anzahl_chip") as Control
	var chip_zeile := screen.get("_chip_zeile") as Control
	assert_true(chip.get_parent() == chip_zeile, "Zähler-Chip wandert auf hoch in die Chip-Zeile")
	assert_true(chip_zeile.visible, "Chip-Zeile sichtbar")
	var spalte := ScreenShell.content_width(m)
	var header := screen.get("_header") as Control
	assert_true(
		header.get_combined_minimum_size().x <= spalte + 2.0,
		"Kopfzeilen-Minbreite <= Spalten-Klemme"
	)
	var rows := screen.get("_rows") as Control
	assert_true(
		rows.get_combined_minimum_size().x <= spalte + 2.0,
		"Spalten-Minbreite <= Klemme (Min-Breiten-Falle behoben)"
	)
	await _drop(screen)


func test_postkarten_kopfzeile_bleibt_einzeilig_auf_desktop() -> void:
	await _pin(BASIS, 0.0, [])
	var gs := FakeGameState.new()
	var screen: PostkartenScreen = PostkartenScreen.new()
	screen.gs_override = gs
	screen.now_override = NOW
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	var chip := screen.get("_anzahl_chip") as Control
	var header := screen.get("_header") as Control
	var chip_zeile := screen.get("_chip_zeile") as Control
	assert_true(chip.get_parent() == header, "Desktop-Basis: Chip bleibt in der Kopfzeile")
	assert_false(chip_zeile.visible, "Chip-Zeile bleibt unsichtbar")
	await _drop(screen)


## ------------------------------------------------ codes_screen.gd


func test_codes_polster_und_touch_floors() -> void:
	await _pin(HOCH_FENSTER, HOCH_SCALE, HOCH_INSETS_PT)
	var gs := FakeGameState.new()
	var screen: CodesScreen = CodesScreen.new()
	screen.gs_override = gs
	screen.now_override = NOW
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	var m := ScreenShell.metrics(screen.get_viewport())
	var pad := screen.get("_pad") as MarginContainer
	assert_true(pad != null, "SafePolster (Scroll-Kind) existiert")
	assert_eq(
		pad.get_theme_constant("margin_top"), _polster_soll(m, "top"), "oberes Polster gesetzt"
	)
	assert_eq(
		pad.get_theme_constant("margin_bottom"),
		_polster_soll(m, "bottom"),
		"unteres Polster gesetzt"
	)
	var floor_px := float(m["floor_px"])
	for feld: String in ["_back", "_redeem_btn"]:
		var knopf := screen.get(feld) as Button
		assert_true(
			minf(knopf.custom_minimum_size.x, knopf.custom_minimum_size.y) >= floor_px - 0.5,
			"%s hält den physischen Touch-Floor (44 pt)" % feld
		)
	await _drop(screen)


## ------------------------------------------------ dlc_screen.gd


func test_dlc_polster_touchfloors_und_cover_deckel() -> void:
	await _pin(QUER_FENSTER, QUER_SCALE, QUER_INSETS_PT)
	var gs := FakeGameState.new()
	var screen: DlcScreen = DlcScreen.new()
	screen.gs_override = gs
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	var m := ScreenShell.metrics(screen.get_viewport())
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	assert_true(float(insets["bottom"]) > 0.0, "Home-Indicator-Simulation aktiv")
	var pad := screen.get("_pad") as MarginContainer
	assert_eq(
		pad.get_theme_constant("margin_bottom"),
		_polster_soll(m, "bottom"),
		"unteres Content-Polster hebt den letzten Ansehen-Knopf über den Home-Indicator"
	)
	assert_eq(
		pad.get_theme_constant("margin_top"), _polster_soll(m, "top"), "oberes Polster gesetzt"
	)
	var floor_px := float(m["floor_px"])
	var back := screen.get("_back") as Button
	assert_true(
		minf(back.custom_minimum_size.x, back.custom_minimum_size.y) >= floor_px - 0.5,
		"Zurück hält den Touch-Floor"
	)
	var knoepfe: Array = screen.get("_ansehen_knoepfe")
	assert_true(knoepfe.size() >= 2, "Katalog baut Ansehen-Knöpfe")
	for knopf: Button in knoepfe:
		assert_true(knopf.custom_minimum_size.y >= floor_px - 0.5, "Ansehen hält den Touch-Floor")
	# Cover-Deckel: flacher Quer-Canvas (720 px hoch) — 240·f (~418 px) wird
	# auf COVER_MAX_SHARE der Canvas-Höhe gedeckelt, sonst schiebt das Cover
	# die Namenszeile dauerhaft in die Home-Indicator-Zone.
	var paare: Array = screen.get("_parallax_cover")
	assert_true(paare.size() >= 2, "Cover-Rahmen registriert")
	for paar: Dictionary in paare:
		var rahmen := paar["rahmen"] as Control
		assert_true(
			rahmen.custom_minimum_size.y <= canvas.y * DlcScreen.COVER_MAX_SHARE + 0.5,
			"Cover-Höhe <= COVER_MAX_SHARE der Canvas-Höhe"
		)
	await _drop(screen)


## ------------------------------------------------ galerie_screen.gd


func test_galerie_kopfumbruch_und_kachelklemme() -> void:
	await _pin(HOCH_FENSTER, HOCH_SCALE, HOCH_INSETS_PT)
	var gs := FakeGameState.new()
	var screen: GalerieScreen = GalerieScreen.new()
	screen.gs_override = gs
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	var m := ScreenShell.metrics(screen.get_viewport())
	var spalte := ScreenShell.content_width(m)
	# Kopfzeilen-Umbruch: hoch/f=3 verlangte die Kopfzeile 1322 px Minbreite
	# (> 1136er-Klemme, Spalten-Zentrum −93 px) — der Speicher-Chip muss in
	# der eigenen Zeile stehen.
	var chip := screen.get("_speicher_chip") as Control
	var chip_zeile := screen.get("_chip_zeile") as Control
	assert_true(chip.get_parent() == chip_zeile, "Speicher-Chip wandert auf hoch in die Chip-Zeile")
	var header := screen.get("_header") as Control
	assert_true(
		header.get_combined_minimum_size().x <= spalte + 2.0,
		"Kopfzeilen-Minbreite <= Spalten-Klemme"
	)
	var rows := screen.get("_rows") as Control
	assert_true(rows.get_combined_minimum_size().x <= spalte + 2.0, "Spalten-Minbreite <= Klemme")
	# Kachel-Klemme: columns × Kachelbreite + Separation <= Spalte.
	var grid := screen.get("_grid") as GridContainer
	var kachel: Vector2 = screen.call("_kachel_groesse")
	var sep := float(grid.get_theme_constant("h_separation"))
	assert_true(
		float(grid.columns) * kachel.x + sep * float(grid.columns - 1) <= spalte + 2.0,
		"Kachel-Zeile passt in die Spalte"
	)
	assert_almost(kachel.y, kachel.x * 0.75, 0.6, "Kacheln behalten das 4:3-Seitenverhältnis")
	await _drop(screen)


## ------------------------------------------------ ikea_screen.gd


func test_ikea_wallet_umbruch_hoch_und_zurueck() -> void:
	await _pin(HOCH_FENSTER, HOCH_SCALE, HOCH_INSETS_PT)
	var screen := IkeaScreen.new()
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	screen.showcase().set_spin_enabled(false)
	var m := ScreenShell.metrics(screen.get_viewport())
	var spalte := ScreenShell.content_width(m, IkeaScreen.GRID_BASE)
	# Kopfzeilen-Falle hoch: Zurück + Titel + Wallet verlangten 1212 px
	# Minbreite (> card_width-Klemme) — die Wallet-Labels müssen in der
	# eigenen Zeile stehen, die Kopfzeile hält die Klemme.
	var coins := screen.get("_coins_label") as Label
	var lager := screen.get("_storage_label") as Label
	var wallet_zeile := screen.get("_wallet_zeile") as Control
	assert_true(coins.get_parent() == wallet_zeile, "Münzen-Label wandert in die Wallet-Zeile")
	assert_true(lager.get_parent() == wallet_zeile, "Lager-Label wandert in die Wallet-Zeile")
	assert_true(wallet_zeile.visible, "Wallet-Zeile sichtbar")
	var header_zeile := screen.get("_header_zeile") as Control
	assert_true(
		header_zeile.get_combined_minimum_size().x <= spalte + 2.0,
		"Kopfzeilen-Minbreite <= card_width-Klemme"
	)
	# Zurück ins Desktop-Format: der Metrik-Pass holt die Wallet-Labels in
	# die Kopfzeile zurück (Umbruch ist bedarfsbasiert, kein Einbahn-Pfad).
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	tree.root.size = BASIS
	await wait_frames(3)
	assert_true(coins.get_parent() == header_zeile, "Desktop: Münzen-Label zurück in der Kopfzeile")
	assert_false(wallet_zeile.visible, "Desktop: Wallet-Zeile wieder unsichtbar")
	await _drop(screen)


## ------------------------------------------------ customize_screen.gd


func test_customize_kopfumbruch_haelt_das_zentrum() -> void:
	await _pin(HOCH_FENSTER, HOCH_SCALE, HOCH_INSETS_PT)
	HomeState.register_slice()
	_dir_seq += 1
	var dir := "user://g4_nachfix_tests/ui_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	var screen := CustomizeScreen.new()
	screen.auto_navigate = false
	screen.game_state_override = gs
	tree.root.add_child(screen)
	await wait_frames(3)
	var m := ScreenShell.metrics(screen.get_viewport())
	var spalte := ScreenShell.content_width(m, CustomizeScreen.SPALTE_BASIS)
	var coins := screen.get("_coins_label") as Label
	var wallet_zeile := screen.get("_wallet_zeile") as Control
	assert_true(coins.get_parent() == wallet_zeile, "Münzen-Label wandert auf hoch in die Zeile 2")
	var header_zeile := screen.get("_header_zeile") as Control
	assert_true(
		header_zeile.get_combined_minimum_size().x <= spalte + 2.0,
		"Kopfzeilen-Minbreite <= Spalten-Klemme"
	)
	# DER Befund (hoch: Zentrum −2,5 px): die Spalte muss im Safe-Zentrum
	# sitzen — Minbreite <= Klemme heißt, content_frame kann sie zentrieren.
	var rows := screen.get("_rows_box") as Control
	assert_true(rows.get_combined_minimum_size().x <= spalte + 2.0, "Spalten-Minbreite <= Klemme")
	var insets: Dictionary = m["insets"]
	var canvas: Vector2 = m["canvas"]
	var safe_mitte := (float(insets["left"]) + canvas.x - float(insets["right"])) / 2.0
	assert_almost(
		rows.get_global_rect().get_center().x, safe_mitte, 2.0, "Spalte im Safe-Zentrum (±2 px)"
	)
	screen.queue_free()
	await wait_frames(2)
	gs.free()
	_unpin()
