extends TestCase
## FB3 — Konformitäts-Wächter: Screens/Panels MÜSSEN die zentralen
## Bausteine benutzen (UiScale/ScreenShell/HudLayoutLogic-Touch-Floor)
## statt eigener Festpixel-Regeln (P0 „skaliert nicht mit der
## Gerätegröße“). Reiner Quelltext-Scan — schnell und headless.
## G7/P57: zusätzlich LIVE-Wächter im Leitformat iPhone 17 Pro Max
## (2868×1320 @3x, User-Wunsch „iPhone 17 Pro Max, Querformat"): Fenster
## wird deterministisch gepinnt und ZURÜCKGESTELLT; geprüft werden die
## P57-Fixes (RMP-Tippflächen ≥ 44 pt, Onboarding-Knopfleiste im Canvas).

## Vollbild-Screens + Overlays: mindestens EINE zentrale Regel referenzieren.
const MUST_USE_SCALE: Array[String] = [
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/panel_sheet.gd",
	"res://scripts/ui/toast.gd",
	"res://scripts/ui/hud_status_sheet.gd",
	"res://scripts/ui/news_50_panel.gd",
	"res://scripts/ui/friends/friends_screen.gd",
	"res://scripts/ui/album/album_screen.gd",
	"res://scripts/ui/social/social_screen.gd",
	"res://scripts/ui/settings_screen.gd",
	"res://scripts/minigames/arcade_screen.gd",
	"res://scripts/minigames/pregame.gd",
	"res://scripts/minigames/results.gd",
	"res://scripts/minigames/minigame_host.gd",
	"res://scripts/minigames/ui/pause_modal.gd",
	# W17/G5 P33: G4-Domänen (Baumodus/Telefon/Radio/Ranch-MP/Level-
	# Selects/Onboarding/Reise) — seit G4 auf den UIKERN-Verträgen, der
	# FB3-Audit misst die Geometrie live (Stationen 10–22).
	"res://scripts/home/build_mode/build_ui_dock.gd",
	"res://scripts/city/phone/phone_shell.gd",
	"res://scripts/ui/radio/radio_sheet.gd",
	"res://scripts/ranch/mp/rmp_menu_panel.gd",
	"res://scripts/ranch/mp/rmp_lobby_panel.gd",
	"res://scripts/ranch/mp/rmp_leaderboard_panel.gd",
	"res://scripts/ranch/mp/rmp_besuch_panel.gd",
	"res://scripts/minigames/games/gvz/gvz_level_select.gd",
	"res://scripts/minigames/games/gobnom/gobnom_level_select.gd",
	"res://scripts/ranch/comp/szene/comp_level_select.gd",
	"res://scripts/ui/onboarding/onboarding_flow.gd",
	"res://scripts/city/travel/reise_app.gd",
]
const SCALE_MARKERS: Array[String] = ["UiScale.", "ScreenShell.", "touch_floor_canvas"]
## Safe-Area-Pflicht für VOLLBILD-Screens/Overlays (Sheet-INHALTE wie
## hud_status_sheet/news_50_panel erben die Safe-Area vom PanelSheet).
const MUST_USE_SAFE_AREA: Array[String] = [
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/panel_sheet.gd",
	"res://scripts/ui/toast.gd",
	"res://scripts/ui/friends/friends_screen.gd",
	"res://scripts/ui/album/album_screen.gd",
	"res://scripts/ui/social/social_screen.gd",
	"res://scripts/ui/settings_screen.gd",
	"res://scripts/minigames/arcade_screen.gd",
	"res://scripts/minigames/pregame.gd",
	"res://scripts/minigames/results.gd",
	"res://scripts/minigames/minigame_host.gd",
	"res://scripts/minigames/ui/pause_modal.gd",
	# W17/G5 P33: Vollbild-Flächen der G4-Domänen. Sheet-INHALTE
	# (radio_sheet, rmp_*_panel, reise_app) erben die Safe-Area weiter
	# vom PanelSheet und stehen bewusst NICHT hier.
	"res://scripts/home/build_mode/build_ui_dock.gd",
	"res://scripts/city/phone/phone_shell.gd",
	"res://scripts/minigames/games/gvz/gvz_level_select.gd",
	"res://scripts/minigames/games/gobnom/gobnom_level_select.gd",
	"res://scripts/ranch/comp/szene/comp_level_select.gd",
	"res://scripts/ui/onboarding/onboarding_flow.gd",
]
const SAFE_MARKERS: Array[String] = ["safe_insets_canvas", "ScreenShell.metrics", "_safe_insets"]
## Inhaltsspalte W16: umgestellte Screens MÜSSEN zentriert bauen — direkt
## über ScreenShell.content_frame( ODER über das dokumentierte Alternativ-
## Muster für Ganzseiten-Scroller/Settings (EXPAND|SHRINK_CENTER-Content
## plus Breiten-Deckel), das das Meta-Flag ScreenShell.META_CONTENT_COLUMN
## setzt. Der FB3-Audit prüft die Geometrie; DIESER Scan hält die Screens
## headless (bei jedem Push) auf dem Muster.
const MUST_USE_CONTENT_COLUMN: Array[String] = [
	"res://scripts/ui/friends/friends_screen.gd",
	"res://scripts/ui/profil/profil_screen.gd",
	"res://scripts/ui/profil/achievements_screen.gd",
	"res://scripts/ui/postkarten/postkarten_screen.gd",
	"res://scripts/ui/codes/codes_screen.gd",
	"res://scripts/ui/dlc/dlc_screen.gd",
	"res://scripts/ui/galerie/galerie_screen.gd",
	"res://scripts/ui/settings_screen.gd",
	# W16/G3 „Welle 2": Grid-Screens mit eigener Spalten-Basisbreite
	# (content_frame + content_width, siehe G3-Bericht §2 / G4-P14).
	"res://scripts/minigames/arcade_screen.gd",
	"res://scripts/shop/ikea_screen.gd",
	"res://scripts/cosmetics/wardrobe_screen.gd",
	"res://scripts/home/customize/customize_screen.gd",
	"res://scripts/ui/album/album_screen.gd",
	# W17/G5 P33: Die G4-Domänen nutzen das card_width-Karten-Muster,
	# NICHT die Inhaltsspalte (kein content_frame/Meta im Code) — daher
	# hier bewusst keine Einträge; die Deckel-Messung übernimmt der
	# FB3-Audit über COLUMN_BASE_BY_SCREEN (Audit-seitige Markierung).
]
const CONTENT_COLUMN_MARKERS: Array[String] = [
	"ScreenShell.content_frame(",
	"ScreenShell.META_CONTENT_COLUMN",
]

## G7/P57 Leitformat iPhone 17 Pro Max — [Fenster-px, screen_scale, Insets
## in PUNKTEN [l, t, r, b]], Werte wie fb3_ui_audit.SIZES
## (Dynamic-Island-Klasse der 2556×1179er).
const LEIT_QUER: Array = [Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]]
const LEIT_HOCH: Array = [Vector2i(1320, 2868), 3.0, [0.0, 59.0, 0.0, 34.0]]
const ALT_QUER_828: Array = [Vector2i(1792, 828), 2.0, [48.0, 0.0, 48.0, 21.0]]
const MIN_TAP_PT := 44.0
const TAP_TOLERANZ_PT := 0.5

## Format-Kontext der Live-Wächter (setzt _pin_format).
var _fenster_vorher := Vector2i.ZERO
var _canvas := Vector2.ZERO
var _safe_rect := Rect2()
var _px_per_pt := 1.0


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func test_screens_nutzen_die_zentrale_skalierung() -> void:
	for path in MUST_USE_SCALE:
		var src := _source(path)
		assert_true(not src.is_empty(), "%s lesbar" % path)
		var found := false
		for marker in SCALE_MARKERS:
			if src.contains(marker):
				found = true
				break
		assert_true(found, "%s nutzt UiScale/ScreenShell/Touch-Floor" % path)


func test_screens_respektieren_die_safe_area() -> void:
	for path in MUST_USE_SAFE_AREA:
		var src := _source(path)
		var found := false
		for marker in SAFE_MARKERS:
			if src.contains(marker):
				found = true
				break
		assert_true(found, "%s zieht die Safe-Area-Insets" % path)


func test_screens_nutzen_die_inhaltsspalte() -> void:
	for path in MUST_USE_CONTENT_COLUMN:
		var src := _source(path)
		assert_true(not src.is_empty(), "%s lesbar" % path)
		var found := false
		for marker in CONTENT_COLUMN_MARKERS:
			if src.contains(marker):
				found = true
				break
		assert_true(found, "%s nutzt die W16-Inhaltsspalte (content_frame/Meta-Flag)" % path)


func test_pause_modal_bleibt_kompakt_konfiguriert() -> void:
	# Wächter gegen Rückbau: Karte deutlich schmaler als die Design-Basis
	# 720 (PanelSheetLayout.MAX_WIDTH) und ein Dim-Backdrop existiert.
	assert_true(
		MinigamePauseModal.CARD_BASE_WIDTH <= PanelSheetLayout.MAX_WIDTH * 0.6,
		"Pause-Karte bleibt kompakt (Basis %d)" % int(MinigamePauseModal.CARD_BASE_WIDTH)
	)
	assert_true(MinigamePauseModal.DIM_COLOR.a >= 0.35, "Abdunkelung vorhanden")


## ---- G7/P57: Leitformat iPhone 17 Pro Max (Live-Wächter) ------------------


## Fenster deterministisch auf ein Geräteformat pinnen (Muster
## test_fb3_screen_metrics._enter_format) — _unpin_format stellt zurück.
func _pin_format(format: Array) -> void:
	if _fenster_vorher == Vector2i.ZERO:
		_fenster_vorher = tree.root.size
	var win: Vector2i = format[0]
	var scale := float(format[1])
	UiScale.screen_scale_override = scale
	DisplayServer.window_set_size(win)
	tree.root.size = win
	await wait_frames(2)
	_canvas = Vector2(tree.root.get_visible_rect().size)
	var pt_kurz := minf(float(win.x), float(win.y)) / scale
	_px_per_pt = minf(_canvas.x, _canvas.y) / pt_kurz
	var insets_pt: Array = format[2]
	var l := float(insets_pt[0]) * _px_per_pt
	var t := float(insets_pt[1]) * _px_per_pt
	var r := float(insets_pt[2]) * _px_per_pt
	var b := float(insets_pt[3]) * _px_per_pt
	_safe_rect = Rect2(l, t, _canvas.x - l - r, _canvas.y - t - b)
	UiScale.insets_override = Rect2(_safe_rect)


func _unpin_format() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	if _fenster_vorher != Vector2i.ZERO:
		tree.root.size = _fenster_vorher
		DisplayServer.window_set_size(_fenster_vorher)
		_fenster_vorher = Vector2i.ZERO
	await wait_frames(2)


## Wache gegen Rückbau der Format-Matrix: das Leitformat bleibt ERSTES
## Audit-Format, das zugehörige Hochformat wird mitgeprüft.
func test_leitformat_steht_vorn_in_der_audit_matrix() -> void:
	var audit := load("res://tests/unit/fb3_ui_audit.gd") as GDScript
	var sizes: Array = audit.get_script_constant_map()["SIZES"]
	assert_eq(String(sizes[0][0]), "quer_2868x1320", "Leitformat ist ERSTES Audit-Format")
	assert_eq(sizes[0][1], Vector2i(2868, 1320), "Leitformat-Fenstergröße")
	var labels: Array[String] = []
	for eintrag: Array in sizes:
		labels.append(String(eintrag[0]))
	assert_true("hoch_1320x2868" in labels, "Hochformat des Leitgeräts in der Matrix")


## P57-Fix (a): RMP-Menü/Lobby-Tippflächen ≥ 44 pt — im HOCH-Format des
## Leitgeräts (dort war der Altbefund mit 18,7–20,6 pt am schlimmsten).
func test_leitformat_hoch_rmp_tippflaechen_44pt() -> void:
	await _pin_format(LEIT_HOCH)
	for eintrag: Array in [
		["RmpMenuPanel", RmpMenuPanel.new()], ["RmpLobbyPanel", RmpLobbyPanel.new()]
	]:
		var panel_name := String(eintrag[0])
		var panel: Control = eintrag[1]
		tree.root.add_child(panel)
		await wait_frames(3)
		var geprueft := 0
		for knopf: Control in panel.find_children("*", "BaseButton", true, false):
			if not knopf.is_visible_in_tree() or (knopf as BaseButton).disabled:
				continue
			geprueft += 1
			var kurz_pt := minf(knopf.size.x, knopf.size.y) / _px_per_pt
			assert_true(
				kurz_pt >= MIN_TAP_PT - TAP_TOLERANZ_PT,
				(
					"%s: %s Tippfläche %.1f pt ≥ %d pt (hoch_1320x2868)"
					% [panel_name, knopf.name, kurz_pt, MIN_TAP_PT]
				)
			)
		assert_true(geprueft > 0, "%s: aktive Knöpfe gefunden" % panel_name)
		panel.free()
	await _unpin_format()


## P57-Fix (b): die Onboarding-Editor-Knopfleiste bleibt im Canvas UND in
## der Safe-Area — in BEIDEN Quer-Formaten des Altbefunds (Leitformat
## 2868×1320 und 1792×828).
func test_leitformat_onboarding_editor_knoepfe_im_canvas() -> void:
	for format: Array in [LEIT_QUER, ALT_QUER_828]:
		await _pin_format(format)
		var flow: OnboardingFlow = (
			(load("res://scripts/ui/onboarding/onboarding_flow.tscn") as PackedScene).instantiate()
		)
		tree.root.add_child(flow)
		await wait_frames(2)
		(flow.get_node("%NameEdit") as LineEdit).text = "Wache"
		flow._on_welcome_next()
		flow._on_nickname_next()
		# Slide ausfedern lassen (TRANS_BACK überschwingt): deterministisch
		# auf die Ruhelage warten statt Frames zu raten.
		var steps := flow.get_node("Steps") as Control
		var ruhig := await wait_until(
			func() -> bool: return absf(steps.position.x - flow._steps_rest.x) <= 0.5, 4000
		)
		assert_true(ruhig, "Slide erreicht die Ruhelage (%s)" % format[0])
		await wait_frames(2)
		var canvas_rect := Rect2(Vector2.ZERO, _canvas)
		for knopf_name: String in ["EditorSkip", "EditorNext"]:
			var knopf := flow.find_child(knopf_name, true, false) as Control
			var rect := knopf.get_global_rect()
			assert_true(
				canvas_rect.grow(1.0).encloses(rect),
				"%s bleibt im Canvas (%s: %s)" % [knopf_name, format[0], rect]
			)
			assert_true(
				_safe_rect.grow(2.0).encloses(rect),
				"%s bleibt im sicheren Bereich (%s: %s)" % [knopf_name, format[0], rect]
			)
		flow.free()
	await _unpin_format()
