extends TestCase
## FIX1 P0 „Panels nehmen den ganzen Platz ein / überschneiden“ + „Patchnotes
## broken“: pure Sheet-Geometrie `PanelSheetLayout` — Breiten-Deckel,
## Höhen-Klemmung in den sicheren Bereich und HUD-Reserve oben.

const CANVAS_QUER := Vector2(1558.3, 720.0)  # iPhone 11 quer
const CANVAS_HOCH := Vector2(1280.0, 2770.4)  # iPhone 11 hoch
const CANVAS_DESKTOP := Vector2(1280.0, 720.0)

const NOTCH_QUER := {"left": 59.0, "top": 0.0, "right": 59.0, "bottom": 21.0}
const NOTCH_HOCH := {"left": 0.0, "top": 91.0, "right": 0.0, "bottom": 53.0}
const OHNE := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}


func test_sheet_breite_ist_gedeckelt() -> void:
	# Querformat: Sheet ist höchstens MAX_WIDTH×f breit — NICHT vollflächig.
	var w := PanelSheetLayout.sheet_width(CANVAS_QUER, NOTCH_QUER, 1.0)
	assert_almost(w, PanelSheetLayout.MAX_WIDTH, 1e-4, "quer: Breiten-Deckel greift")
	assert_true(
		w < CANVAS_QUER.x - 118.0, "Sheet deutlich schmaler als der Canvas (HUD bleibt sichtbar)"
	)
	# Schmaler Hochkant-Canvas: Breite = sicherer Bereich minus Ränder.
	var f := 1280.0 / 720.0
	var w_hoch := PanelSheetLayout.sheet_width(CANVAS_HOCH, NOTCH_HOCH, f)
	var erwartet := minf(
		PanelSheetLayout.MAX_WIDTH * f, CANVAS_HOCH.x - 2.0 * PanelSheetLayout.MARGIN * f
	)
	assert_almost(w_hoch, erwartet, 1e-4, "hoch: nutzt die Breite, aber nie die Ränder")


func test_sheet_rect_bleibt_im_sicheren_bereich() -> void:
	for probe: Array in [
		[CANVAS_QUER, NOTCH_QUER, 1.0],
		[CANVAS_HOCH, NOTCH_HOCH, 1280.0 / 720.0],
		[CANVAS_DESKTOP, OHNE, 1.0],
	]:
		var canvas: Vector2 = probe[0]
		var insets: Dictionary = probe[1]
		var f: float = probe[2]
		# Absichtlich absurd hoher Inhalt (der Patchnotes-Fall).
		var rect := PanelSheetLayout.sheet_rect(canvas, insets, f, 99_999.0)
		assert_true(rect.position.x >= float(insets["left"]) - 1e-4, "links im Safe-Bereich")
		assert_true(
			rect.end.x <= canvas.x - float(insets["right"]) + 1e-4, "rechts im Safe-Bereich"
		)
		assert_true(
			rect.end.y <= canvas.y - float(insets["bottom"]) + 1e-4, "über dem Home-Indicator"
		)
		# HUD-Reserve: oben bleibt der Statuszeilen-Streifen frei —
		# das Sheet ÜBERDECKT NIE den ganzen Bildschirm.
		assert_true(
			rect.position.y >= float(insets["top"]) + PanelSheetLayout.TOP_RESERVE * f - 1e-4,
			"HUD-Streifen oben bleibt frei (canvas %s)" % canvas
		)
		# Horizontal zentriert im sicheren Bereich.
		var safe_mitte := (
			float(insets["left"])
			+ (canvas.x - float(insets["left"]) - float(insets["right"])) / 2.0
		)
		assert_almost(rect.position.x + rect.size.x / 2.0, safe_mitte, 0.01, "zentriert")


func test_kleiner_inhalt_bekommt_kleines_sheet() -> void:
	# Kleine Inhalte (Status-Sheet) bleiben klein — kein künstliches Aufblasen.
	var rect := PanelSheetLayout.sheet_rect(CANVAS_QUER, NOTCH_QUER, 1.0, 240.0)
	assert_almost(rect.size.y, 240.0, 1e-4, "Wunschhöhe wird respektiert")
	var unten := CANVAS_QUER.y - float(NOTCH_QUER["bottom"]) - PanelSheetLayout.BOTTOM_GAP
	assert_almost(rect.end.y, unten, 1e-4, "liegt unten überm Home-Indicator")


func test_panel_sheet_szene_klemmt_und_scrollt() -> void:
	# Integrationsprobe der echten Szene: riesiger Inhalt → Sheet bleibt im
	# Rahmen, der Überschuss wandert in den ScrollContainer.
	PanelStack.clear()
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var sheet: PanelSheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
	host.add_child(sheet)
	sheet.set_title("Patchnotes-Probe")
	var riese := VBoxContainer.new()
	for i in 60:
		var row := Label.new()
		row.text = "Eintrag %d — sehr wichtiger Patchnote-Text" % i
		riese.add_child(row)
	sheet.add_content(riese)
	sheet.open()
	await wait_frames(3)
	var canvas := Vector2(sheet.get_viewport().get_visible_rect().size)
	var karte := sheet.get_node("Sheet") as Control
	assert_true(karte.size.y <= canvas.y + 1e-3, "Karte wächst nie aus dem Bildschirm")
	assert_true(karte.position.y >= 0.0, "Karte beginnt im Bild (vorher: leerer Screen)")
	var scroll := sheet.get_node("%SheetScroll") as ScrollContainer
	var inhalt := scroll.get_node("SheetBody") as Control
	assert_true(
		inhalt.get_combined_minimum_size().y > scroll.size.y,
		"Überschuss liegt im Scroll-Fenster (Inhalt größer als Sichtbereich)"
	)
	sheet.close()
	host.queue_free()
	await wait_frames(1)
