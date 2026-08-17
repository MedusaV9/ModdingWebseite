extends TestCase
## EVAL-2026-08 Lens B Befund 18 — SPRECHBLASEN-WACHE in VIER Geräte-
## Formaten (Auftrag: „abgeschnittene Zeilen dürfen nie vorkommen — Test,
## der lange Texte in 4 Formaten prüft“). Geprüft werden AcBubble UND
## DialogBubble mit einem langen Spruch in iPhone quer/hoch (2340×1080 @3×,
## die Eval-Referenz von Shot 17) und iPad quer/hoch (2048×1536 @2×):
## - POP-VERTRAG: die Blase erscheint NIE mit angerissener Zeile — beim
##   Pop steht mindestens die komplette erste Zeile (Einzeiler ganz),
## - WORT-REVEAL: jeder Typewriter-Zwischenstand endet an einer Wortgrenze
##   („Kannst du kurz be“ ist strukturell unmöglich),
## - KEIN CLIPPING: das Label bekommt seine volle Minimalgröße, Text-Rect
##   ⊆ Kapsel, Kapsel ⊆ Safe-Area,
## - LANE-KLEMME: die Blase endet VOR der Cockpit-Spalte des HUD (quer)
##   und hält die Hud.bubble_lane-Breite ein.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const DIALOG_SCENE := preload("res://scripts/ui/dialog_bubble.tscn")
## [Name, Fenster-px, screen_scale, Insets in PUNKTEN l/t/r/b] — Rechnung
## wie test_g7_hud_dynamik/fb3_ui_audit (physische Retina-Skala + Notch).
const FORMATE: Array = [
	["iphone_quer", Vector2i(2340, 1080), 3.0, [59.0, 0.0, 59.0, 21.0]],
	["iphone_hoch", Vector2i(1080, 2340), 3.0, [0.0, 59.0, 0.0, 34.0]],
	["ipad_quer", Vector2i(2048, 1536), 2.0, [0.0, 24.0, 0.0, 20.0]],
	["ipad_hoch", Vector2i(1536, 2048), 2.0, [0.0, 24.0, 0.0, 20.0]],
]
## Langer Fixture-Spruch (≤ GANZTEXT_MAX_ZEICHEN): wickelt in JEDEM Format
## mehrzeilig — der Wortlaut spiegelt den Eval-Shot („Kannst du kurz …“).
const LANGER_SPRUCH := (
	"Kannst du kurz bei mir bleiben? Ich wollte dir nämlich unbedingt"
	+ " erzählen, was ich heute im Garten unter der Wäscheleine gefunden"
	+ " habe — du glaubst es nie, ein glitzernder Kieselstein!"
)

var _fenster_vorher := Vector2i()
var _scale_vorher := 0.0
var _gepinnt := false


## Vorher-Zustand nur beim ERSTEN Pin merken: der Format-Loop pinnt
## mehrfach ohne Unpin dazwischen — sonst „restauriert“ _unpin das
## VORIGE Format statt des Runner-Zustands und verseucht spätere Tests
## (gefangen: test_shop_screen-Vitrine fiel im Vollauf mit 2048×1536-
## Fenster + screen_scale_override 2.0 um).
func _pin(fenster: Vector2i, scale: float, insets_pt: Array) -> void:
	if not _gepinnt:
		_fenster_vorher = tree.root.size
		_scale_vorher = UiScale.screen_scale_override
		_gepinnt = true
	UiScale.screen_scale_override = scale
	tree.root.size = fenster
	tree.root.size_changed.emit()
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var px_per_pt := minf(canvas.x, canvas.y) / (float(mini(fenster.x, fenster.y)) / scale)
	var l := float(insets_pt[0]) * px_per_pt
	var t := float(insets_pt[1]) * px_per_pt
	var r := float(insets_pt[2]) * px_per_pt
	var b := float(insets_pt[3]) * px_per_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.screen_scale_override = _scale_vorher
	UiScale.insets_override = Rect2()
	tree.root.size = _fenster_vorher
	_gepinnt = false
	tree.root.size_changed.emit()
	await wait_frames(1)


## Spiegel von AcBubble._erste_zeile_zeichen (TextParagraph, gleiche
## Break-Flags) — die Wache rechnet die erste Zeile UNABHÄNGIG nach.
func _erste_zeile_mirror(label: Label, text: String) -> int:
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		return text.length()
	var absatz := TextParagraph.new()
	absatz.break_flags = (
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	absatz.width = maxf(label.custom_minimum_size.x, 1.0)
	absatz.add_string(text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
	if absatz.get_line_count() <= 0:
		return text.length()
	return absatz.get_line_range(0).y


func _pruefe_acbubble(hud: Hud, name: String) -> void:
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	UiAnchors.reset_for_tests()
	var layer := Control.new()
	tree.root.add_child(layer)
	var bubble := AcBubble.show_bubble(layer, LANGER_SPRUCH, {"dauer_s": 600.0})
	bubble.auto_zeit = false
	var kapsel := bubble.get_node("Kapsel") as PanelContainer
	var label := bubble.get_node("Kapsel/BubbleText") as Label
	# POP-VERTRAG: nie mit angerissener Zeile erscheinen.
	var vc := label.visible_characters
	if vc >= 0:
		assert_true(vc > 0, "%s: Pop nie mit leerer Blase" % name)
		assert_eq(vc, AcBubble.wort_grenze(LANGER_SPRUCH, vc), "%s: Pop an Wortgrenze" % name)
		assert_true(
			vc >= _erste_zeile_mirror(label, LANGER_SPRUCH),
			"%s: Pop zeigt mindestens die komplette erste Zeile (%d Zeichen)" % [name, vc]
		)
	# WORT-REVEAL: Zwischenstände enden immer an Wortgrenzen.
	for _i in 30:
		bubble.advance_time(1.0 / GoobyVoice.RATE)
		var jetzt := label.visible_characters
		if jetzt < 0:
			break
		assert_eq(
			jetzt,
			AcBubble.wort_grenze(LANGER_SPRUCH, jetzt),
			"%s: Zwischenstand an Wortgrenze" % name
		)
	# Fertig tippen + settlen: kein Clipping, Kapsel in Safe-Area und Lane.
	bubble.advance_time(600.0 / GoobyVoice.RATE)
	await wait_frames(3)
	bubble.advance_time(0.05)
	assert_eq(label.visible_characters, -1, "%s: fertig = alles sichtbar" % name)
	var label_min := label.get_combined_minimum_size()
	assert_true(
		label_min.y <= label.size.y + 0.5,
		"%s: keine verschluckte Zeile (min %.1f > ist %.1f)" % [name, label_min.y, label.size.y]
	)
	assert_true(
		label.position.y + label.size.y <= kapsel.size.y + 0.5,
		"%s: Text-Rect endet in der Kapsel" % name
	)
	var safe := UiScale.insets_override
	var rect := Rect2(kapsel.position, kapsel.size)
	assert_true(
		safe.grow(1.0).encloses(rect), "%s: Kapsel in der Safe-Area (%s ⊄ %s)" % [name, rect, safe]
	)
	# LANE-KLEMME: Breite ≤ bubble_lane-Breite; quer endet die Blase VOR
	# der Cockpit-Spalte (kein Pixel unter den Kacheln).
	var lane: Dictionary = hud.bubble_lane()
	assert_true(
		kapsel.size.x <= float(lane["width"]) + 1.0,
		"%s: Kapsel-Breite %.1f ≤ Lane %.1f" % [name, kapsel.size.x, float(lane["width"])]
	)
	var spalte := hud.get_node("%LandscapeColumn") as Control
	if spalte.is_visible_in_tree():
		var schnitt := rect.intersection(spalte.get_global_rect())
		assert_false(
			schnitt.size.x > 1.0 and schnitt.size.y > 1.0,
			"%s: Blase schneidet die Cockpit-Spalte (%s)" % [name, schnitt]
		)
	bubble.dismiss()
	layer.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()


func _pruefe_dialogbubble(hud: Hud, name: String) -> void:
	UiAnchors.reset_for_tests()
	var db := DIALOG_SCENE.instantiate() as DialogBubble
	db.sofort_override = 1
	tree.root.add_child(db)
	await wait_frames(1)
	var panel := db.get_node("%Bubble") as PanelContainer
	var label := db.get_node("%BubbleText") as Label
	db.show_lines([LANGER_SPRUCH] as Array[String])
	await wait_frames(3)
	assert_eq(label.visible_characters, -1, "%s: Sofort-Modus zeigt alles" % name)
	var label_min := label.get_combined_minimum_size()
	assert_true(
		label_min.y <= label.size.y + 0.5,
		(
			"%s: DialogBubble verliert keine Zeile (min %.1f > ist %.1f)"
			% [name, label_min.y, label.size.y]
		)
	)
	assert_true(
		panel.size.y >= panel.get_combined_minimum_size().y - 0.5,
		"%s: DialogBubble-Kapsel hoch genug" % name
	)
	# Blase respektiert die HUD-Lane (Breite + Unterkante über der Lane).
	var lane: Dictionary = hud.bubble_lane()
	var breite := panel.offset_right - panel.offset_left
	assert_true(
		breite <= float(lane["width"]) + 1.0,
		"%s: DialogBubble-Breite %.1f ≤ Lane %.1f" % [name, breite, float(lane["width"])]
	)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	assert_true(
		canvas.y + panel.offset_bottom <= float(lane["top"]) + 0.5,
		(
			"%s: DialogBubble endet über der Lane (%.1f > %.1f)"
			% [name, canvas.y + panel.offset_bottom, float(lane["top"])]
		)
	)
	db.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()


func test_lange_texte_in_vier_formaten() -> void:
	for format: Array in FORMATE:
		var name := str(format[0])
		await _pin(format[1], float(format[2]), format[3])
		var hud: Hud = HUD_SCENE.instantiate()
		tree.root.add_child(hud)
		await wait_frames(2)
		await _pruefe_acbubble(hud, name)
		await _pruefe_dialogbubble(hud, name)
		hud.free()
		await wait_frames(1)
	await _unpin()
