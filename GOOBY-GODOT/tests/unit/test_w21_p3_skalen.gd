extends TestCase
## W21/P3 — Wächter des P3-Pakets (Sheets + Menü-Screens):
## (1) Skalen-Konformitäts-Probe über die P3-Dateien: reiner Quelltext-
##     Scan, der die Abnahme aus UI-DESIGN-ACNH §8/P3 („0 Overrides
##     außerhalb der Skala“) headless einfriert. Vor dem P3-Umbau standen
##     hier 152 Ausreißer (Mess-Tabellen profil_menues_befunde.md).
## (2) Profil-Kartenraster: ALLE Karten der Profil-Spalte teilen Variation
##     (AcCard → gleicher Radius/Polster) und Breite („beim Profil sieht
##     man ja auch das nichts die gleiche Größe hat“).
## (3) Stempel-/Blatt-Slide-RM-Verträge an den P3-Call-Sites: Quest-Häkchen
##     (mark_claimed) und PanelSheet.open/close springen unter Reduced
##     Motion SOFORT in den Endzustand (Kit-Primitive: test_w21_motion_kit).
## JEDE Scan-Regel prüft eine der dokumentierten Inkonsistenz-Familien:
##   R1  Font-Overrides NUR über AcTokens.font_px()/AcTokens.SIZE_-Basen
##       (löste die „Font-Lotterie“: 6+ freie Basisgrößen pro Screen).
##   R1b Literal-Basen in font_px() liegen AUF der Typo-Skala (5 Stufen).
##   R2  KEINE int()-Trunkierung skalierter Maße (round()-Konvention —
##       Befund „TitleLabel 45 vs. 46“).
##   R3  Radien NUR aus der Radien-Skala (AcTokens.RADIUS_*).
##   R4  KEINE nackten Zahlen-Literale × f — jedes skalierte Maß geht durch
##       AcTokens.px()/font_px() (oder eine benannte Design-Konstante).
##   R4b Literal-Basen in AcTokens.px() sind Spacing-Grid-Vielfache (4er).
## Bewusst NICHT im Umfang: foto_modus/kamera_app (Kamera-Sucher-Geometrie,
## kein Menü-Blatt — Restarbeit P3-Folgepaket).

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")

## Frame-Deckel für „Animation fertig“-Schleifen (Watchdog-freundlich).
const MAX_FRAMES := 240

## Datei-Grenzen des P3-Pakets (Sheets + Menü-Screens).
const P3_DATEIEN: Array[String] = [
	"res://scripts/ui/panel_sheet.gd",
	"res://scripts/ui/screen_shell.gd",
	"res://scripts/ui/quests/quest_panel.gd",
	"res://scripts/ui/profil/profil_screen.gd",
	"res://scripts/ui/profil/passport_card.gd",
	"res://scripts/ui/profil/achievements_screen.gd",
	"res://scripts/ui/profil/mrz_gag.gd",
	"res://scripts/ui/album/album_screen.gd",
	"res://scripts/ui/album/collections_view.gd",
	"res://scripts/ui/album/sticker_card.gd",
	"res://scripts/shop/ikea_screen.gd",
	"res://scripts/cosmetics/wardrobe_screen.gd",
	"res://scripts/home/customize/customize_screen.gd",
	"res://scripts/ui/dlc/dlc_screen.gd",
	"res://scripts/ui/settings_screen.gd",
	"res://scripts/ui/settings/settings_rows_basis.gd",
	"res://scripts/ui/radio/radio_sheet.gd",
	"res://scripts/ui/codes/codes_screen.gd",
	"res://scripts/ui/galerie/galerie_screen.gd",
	"res://scripts/ui/news_50_panel.gd",
	"res://scripts/city/phone/phone_shell.gd",
	"res://scripts/city/phone/friends_app.gd",
	"res://scripts/city/phone/instant_gooby_app.gd",
]

var _re_font_override := RegEx.create_from_string("add_theme_font_size_override")
var _re_font_px_literal := RegEx.create_from_string("font_px\\(\\s*(\\d+(?:\\.\\d+)?)")
var _re_int_trunkierung := RegEx.create_from_string("\\bint\\(.*\\*\\s*_?t?f\\b")
var _re_radius := RegEx.create_from_string("set_corner_radius_all\\(")
var _re_nacktes_literal := RegEx.create_from_string("\\d(\\.\\d+)?\\s*\\*\\s*(maxf\\()?_?t?f\\b")
var _re_px_literal := RegEx.create_from_string("AcTokens\\.px\\(\\s*(\\d+(?:\\.\\d+)?)")


func _zeilen(path: String) -> PackedStringArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	return file.get_as_text().split("\n")


## Code-Anteil einer Zeile (naive Kommentar-Kappung — Strings in diesen
## Dateien enthalten kein '#', der Scan bleibt bewusst simpel).
func _code(zeile: String) -> String:
	var idx := zeile.find("#")
	if idx < 0:
		return zeile
	return zeile.substr(0, idx)


func _pruefe_datei(path: String) -> Array[String]:
	var befunde: Array[String] = []
	var zeilen := _zeilen(path)
	assert_true(zeilen.size() > 0, "%s lesbar" % path)
	for i in zeilen.size():
		var code := _code(zeilen[i])
		var wo := "%s:%d" % [path, i + 1]
		if _re_font_override.search(code) != null:
			# gdformat bricht lange Aufrufe um — das Argument darf in den
			# zwei Folgezeilen stehen (3-Zeilen-Fenster).
			var fenster := code
			for j in range(i + 1, mini(i + 3, zeilen.size())):
				fenster += " " + _code(zeilen[j])
			var skala_basis := (
				fenster.contains("AcTokens.font_px(") or fenster.contains("AcTokens.SIZE_")
			)
			if not skala_basis:
				befunde.append("%s — Font-Override ohne AcTokens.font_px/SIZE_-Basis" % wo)
		var font_literal := _re_font_px_literal.search(code)
		if font_literal != null:
			var basis := int(float(font_literal.get_string(1)))
			if basis not in AcTokens.TYPO_SKALA:
				befunde.append("%s — font_px-Basis %d liegt nicht auf der Typo-Skala" % [wo, basis])
		if _re_int_trunkierung.search(code) != null:
			if not code.contains("AcTokens.px(") and not code.contains("AcTokens.font_px("):
				befunde.append("%s — int()-Trunkierung eines skalierten Maßes" % wo)
		if _re_radius.search(code) != null and not code.contains("AcTokens.RADIUS_"):
			befunde.append("%s — Radius außerhalb der Radien-Skala" % wo)
		if _re_nacktes_literal.search(code) != null:
			befunde.append("%s — nacktes Zahlen-Literal × f (AcTokens.px fehlt)" % wo)
		var px_literal := _re_px_literal.search(code)
		if px_literal != null:
			var wert := int(float(px_literal.get_string(1)))
			if wert % AcTokens.SPACE_GRID != 0:
				befunde.append("%s — px-Basis %d ist kein Spacing-Grid-Vielfaches" % [wo, wert])
	return befunde


## DIE Abnahme aus dem Plan: 0 Overrides außerhalb der Skala in den
## P3-Dateien. Jeder Befund nennt Datei:Zeile + verletzte Regel.
func test_p3_dateien_ohne_skalen_ausreisser() -> void:
	var alle: Array[String] = []
	for path in P3_DATEIEN:
		alle.append_array(_pruefe_datei(path))
	for befund in alle:
		fail_test(befund)
	assert_eq(alle.size(), 0, "0 Skalen-Ausreißer in den P3-Dateien (siehe Einzel-Befunde)")


# ── (2) Profil-Kartenraster: gleiche Breite + gleicher Radius ────────────────


## GameState-Double (Muster test_w20_sheets_layout): dotted get/set auf dem
## Schema-Default — reicht dem Profil-Screen (state/get_value, Zeit gepinnt).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

	func _init() -> void:
		s = SaveSchema.default_state(1768478400000)

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

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func test_profil_kartenraster_konsistent() -> void:
	var gs := FakeGameState.new()
	var screen := ProfilScreen.new()
	screen.auto_navigate = false
	screen.gs_override = gs
	tree.root.add_child(screen)
	await wait_frames(4)
	var liste: VBoxContainer = screen.get("_list_box")
	assert_true(liste != null, "Profil-Inhaltsspalte da")
	var karten: Array[PanelContainer] = []
	for kind in liste.get_children():
		if kind is PanelContainer:
			karten.append(kind)
	assert_true(karten.size() >= 7, "Profil hat >= 7 Karten (%d)" % karten.size())
	var breite := -1.0
	for karte in karten:
		assert_eq(
			String(karte.theme_type_variation),
			"AcCard",
			"%s nutzt die EINE Karten-Rolle (Radius/Polster aus dem Theme)" % karte.name
		)
		var stil := karte.get_theme_stylebox("panel") as StyleBoxFlat
		assert_true(stil != null, "%s: Karten-StyleBox aufgelöst" % karte.name)
		if stil != null:
			assert_eq(
				stil.corner_radius_top_left,
				AcTokens.RADIUS_CARD,
				"%s: Radius = RADIUS_CARD" % karte.name
			)
		if breite < 0.0:
			breite = karte.size.x
		assert_almost(karte.size.x, breite, 1.0, "%s: gleiche Kartenbreite im Raster" % karte.name)
	assert_true(breite > 0.0, "Karten haben eine echte Layout-Breite")
	screen.queue_free()
	await wait_frames(2)


# ── (3) Stempel-/Blatt-Slide-RM-Verträge (P3-Call-Sites) ─────────────────────


func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func _quest_board() -> Array:
	# Echte Katalog-Id (feed3): die Zeile baut mit echten String-Keys.
	return [
		{
			"def": {"id": "feed3", "kategorie": "care", "muenzen": 20, "xp": 10},
			"target": 3,
			"progress": 3,
			"complete": true,
			"claimed": false,
		}
	]


func test_stempel_rm_vertrag_quest_haken() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var panel := DailyQuestPanel.new()
	tree.root.add_child(panel)
	panel.rebuild(_quest_board(), {"muenzen": 20, "xp": 10}, true, 1.0)
	await wait_frames(2)
	panel.mark_claimed("feed3", {"muenzen": 20, "xp": 10})
	var check := panel.find_child("CheckFeed3", true, false) as TextureRect
	assert_true(check != null and check.visible, "Häkchen sichtbar nach mark_claimed")
	# RM-Vertrag: der Stempel LANDET sofort (Scale 1, Rotation 0, sichtbar).
	assert_eq(check.scale, Vector2.ONE, "RM: Stempel sofort in Ruhelage")
	assert_almost(check.rotation, 0.0, 1e-6, "RM: keine Rest-Drehung")
	assert_almost(check.modulate.a, 1.0, 1e-6, "RM: sofort voll sichtbar")
	panel.queue_free()
	await wait_frames(1)
	# Ohne RM: der Stempel STARTET groß/gedreht (Tween übernimmt die Landung).
	_set_reduced_motion(false)
	var panel2 := DailyQuestPanel.new()
	tree.root.add_child(panel2)
	panel2.rebuild(_quest_board(), {"muenzen": 20, "xp": 10}, true, 1.0)
	await wait_frames(2)
	panel2.mark_claimed("feed3", {"muenzen": 20, "xp": 10})
	var check2 := panel2.find_child("CheckFeed3", true, false) as TextureRect
	assert_true(check2 != null, "Häkchen 2 da")
	assert_almost(check2.scale.x, MotionKit.STEMPEL_START_SCALE, 1e-3, "Stempel startet groß (1.6)")
	panel2.queue_free()
	await wait_frames(1)
	_set_reduced_motion(rm_vorher)


func test_blatt_slide_rm_vertrag_panel_sheet() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var sheet: PanelSheet = SHEET_SCENE.instantiate()
	tree.root.add_child(sheet)
	await wait_frames(1)
	var inhalt := Label.new()
	inhalt.text = "RM-Vertrag"
	sheet.add_content(inhalt)
	sheet.open()
	var blatt := sheet.find_child("Sheet", true, false) as Control
	assert_true(blatt != null, "Blatt-Karte da")
	# RM-Vertrag: kein Slide-Tween, Blatt sofort voll sichtbar.
	assert_eq(sheet.get("_motion_tween"), null, "RM: open() ohne Motion-Tween")
	assert_almost(blatt.modulate.a, 1.0, 1e-6, "RM: Blatt sofort deckend")
	sheet.close()
	assert_false(sheet.visible, "RM: close() versteckt sofort (kein Abgangs-Slide)")
	# Ohne RM: open() fährt per Blatt-Slide ein (Tween läuft, Ruhelage am Ende).
	_set_reduced_motion(false)
	sheet.open()
	var tween: Tween = sheet.get("_motion_tween")
	assert_true(tween != null and tween.is_valid(), "open() startet den Blatt-Slide")
	var rest_y: float = sheet.get("_rest_y")
	assert_true(blatt.position.y > rest_y, "Blatt startet UNTER der Ruhelage (Einflug)")
	var frames := 0
	while tween.is_valid() and frames < MAX_FRAMES:
		await wait_frames(1)
		frames += 1
	assert_almost(blatt.modulate.a, 1.0, 1e-3, "Slide endet voll sichtbar")
	assert_almost(blatt.position.y, sheet.get("_rest_y"), 1.0, "Slide endet in der Ruhelage")
	sheet.close()
	await wait_frames(2)
	sheet.queue_free()
	await wait_frames(1)
	_set_reduced_motion(rm_vorher)
