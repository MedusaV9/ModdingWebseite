extends TestCase
## G4/P23 FLOWFEIER — Wächter für die Erste-Minuten- und Feier-Flächen:
##  - Onboarding-Karten laufen über ScreenShell (card_width, Touch-Floor,
##    Editor-Spalten stapeln im Hochformat, Slider-Griffe >= Floor),
##  - Quest-Panel hebt Abholen/Reroll auf den physischen Touch-Floor,
##  - quest_service klingt/summt nach G2-Fixliste A5 (Quellen-Wache),
##  - Bett-Nachtkarte + Geburtstags-Panel sind PanelStack-Overlays
##    (Veil, AcCard, close()-Vertrag, ScreenShell-Metriken),
##  - Tagesbonus-Kalender-Chips deckeln auf die Karten-Innenbreite,
##  - Gesprächs-Antwort-Chips erfüllen den UIKERN-Vertrag (HUD-Report H1/H3:
##    SquishButton+AcChip, 44-pt-Floor, UiAnchors-Bottom-Zone statt
##    Fix-Offsets).
## Geometrie-Tests pinnen das Fenster VOR dem Screen-Bau auf 1280×720
## (bzw. rotieren danach) und setzen es am Testende zurück.

const FLOW_SCENE := preload("res://scripts/ui/onboarding/onboarding_flow.tscn")
const QUER := Vector2i(1280, 720)
const HOCH := Vector2i(720, 1280)

var _saved_root_size := Vector2i.ZERO


## Fenster VOR dem Screen-Bau pinnen (Muster test_g3_arcade).
func _pin(win_size: Vector2i) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	DisplayServer.window_set_size(win_size)
	tree.root.size = win_size
	await wait_frames(2)


func _unpin() -> void:
	UiScale.screen_scale_override = 0.0
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		DisplayServer.window_set_size(_saved_root_size)
		_saved_root_size = Vector2i.ZERO
	await wait_frames(2)


func _floor_px() -> float:
	return float(ScreenShell.metrics(tree.root)["floor_px"])


func _hat_touch_floor(ctl: Control, floor_px: float, label: String) -> void:
	assert_true(
		ctl.custom_minimum_size.x >= floor_px - 0.5 and ctl.custom_minimum_size.y >= floor_px - 0.5,
		(
			"%s: Tippfläche >= physischer Floor (%s < %.0f)"
			% [label, ctl.custom_minimum_size, floor_px]
		)
	)


# ── Onboarding-Flow ───────────────────────────────────────────────────────────


func test_onboarding_karten_folgen_screenshell_im_querformat() -> void:
	await _pin(QUER)
	var flow: OnboardingFlow = FLOW_SCENE.instantiate()
	tree.root.add_child(flow)
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root)
	var floor_px: float = m["floor_px"]
	var card_w := ScreenShell.card_width(m, OnboardingFlow.CARD_BASE_WIDTH)
	for pfad in ["%StepWelcome", "%StepNickname", "%StepDone"]:
		assert_almost(
			(flow.get_node(pfad) as Control).custom_minimum_size.x,
			card_w,
			0.5,
			"%s: Kartenbreite = ScreenShell.card_width" % pfad
		)
	assert_almost(
		(flow.get_node("%StepEditor") as Control).custom_minimum_size.x,
		ScreenShell.card_width(m, OnboardingFlow.EDITOR_CARD_BASE_WIDTH),
		0.5,
		"Editor-Karte nutzt die eigene Design-Basis"
	)
	assert_false(
		(flow.get_node("%EditorBox") as BoxContainer).vertical,
		"Querformat: Preview und Slider NEBENEINANDER"
	)
	for pfad in ["%WelcomeNext", "%NicknameNext", "%EditorSkip", "%EditorNext", "%DoneButton"]:
		_hat_touch_floor(flow.get_node(pfad) as Control, floor_px, pfad)
	_hat_touch_floor(flow.get_node("%NameEdit") as Control, floor_px, "NameEdit")
	_hat_touch_floor(flow.get_node("%NicknameEdit") as Control, floor_px, "NicknameEdit")
	var slider := flow.get_node("%SliderRows").find_child("SliderEarLen", true, false) as HSlider
	assert_true(slider != null, "Ohrenlängen-Slider existiert")
	assert_true(
		slider.custom_minimum_size.y >= floor_px - 0.5,
		"Slider-Griffzeile >= Touch-Floor (%s)" % slider.custom_minimum_size
	)
	flow.free()
	await _unpin()


func test_onboarding_editor_stapelt_im_hochformat() -> void:
	await _pin(QUER)
	var flow: OnboardingFlow = FLOW_SCENE.instantiate()
	tree.root.add_child(flow)
	await wait_frames(2)
	# Rotation: size_changed muss den Relayout-Pass selbst anstoßen.
	DisplayServer.window_set_size(HOCH)
	tree.root.size = HOCH
	await wait_frames(2)
	assert_true(
		(flow.get_node("%EditorBox") as BoxContainer).vertical,
		"Hochformat: Preview ÜBER den Slidern (Spalten stapeln)"
	)
	var m := ScreenShell.metrics(tree.root)
	var card_w := ScreenShell.card_width(m, OnboardingFlow.CARD_BASE_WIDTH)
	var welcome := flow.get_node("%StepWelcome") as Control
	assert_almost(welcome.custom_minimum_size.x, card_w, 0.5, "Kartenbreite folgt der Rotation")
	var text := flow.get_node("%WelcomeText") as Control
	var sb := welcome.get_theme_stylebox("panel")
	var pad := sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	assert_true(
		text.custom_minimum_size.x <= card_w - pad + 0.5,
		(
			"Autowrap-Text sprengt die Karte nicht (%.0f in %.0f)"
			% [text.custom_minimum_size.x, card_w - pad]
		)
	)
	flow.free()
	await _unpin()


# ── Quest-Panel + Service-Sound ───────────────────────────────────────────────


func test_quest_panel_hebt_claim_und_reroll_auf_touch_floor() -> void:
	await _pin(QUER)
	var panel := DailyQuestPanel.new()
	var row := {
		"def": {"id": "feed3", "kategorie": "care", "muenzen": 20, "xp": 10},
		"target": 3,
		"progress": 1,
		"complete": false,
		"claimed": false,
	}
	# Service-Reihenfolge nachstellen: rebuild() läuft VOR add_content.
	panel.rebuild([row], {"muenzen": 20, "xp": 10}, true, 1.0)
	tree.root.add_child(panel)
	await wait_frames(1)
	var floor_px := _floor_px()
	var claim := panel.find_child("ClaimFeed3", true, false) as Control
	assert_true(claim != null, "Abholen-Knopf existiert")
	_hat_touch_floor(claim, floor_px, "Abholen")
	var reroll := panel.find_child("RerollButton", true, false) as Control
	assert_true(reroll != null, "Reroll-Knopf existiert")
	_hat_touch_floor(reroll, floor_px, "Reroll")
	panel.free()
	await _unpin()


## W21-Wächter („nichts hat die gleiche Größe“): rebuild(f) skaliert die
## THEME-SCHRIFTEN des Sheet-Inhalts mit — vorher blieben Untertitel/Zeilen
## in Basis-px (Caption 15), während das Sheet seinen Titel skalierte.
func test_quest_panel_skaliert_theme_schriften_mit_f() -> void:
	await _pin(QUER)
	var panel := DailyQuestPanel.new()
	var row := {
		"def": {"id": "feed3", "kategorie": "care", "muenzen": 20, "xp": 10},
		"target": 3,
		"progress": 1,
		"complete": false,
		"claimed": false,
	}
	# Service-Reihenfolge: rebuild() läuft VOR dem Einhängen ins Sheet.
	panel.rebuild([row], {"muenzen": 20, "xp": 10}, true, 2.0)
	tree.root.add_child(panel)
	await wait_frames(1)
	var subtitle := panel.find_child("Untertitel", true, false) as Label
	assert_true(subtitle != null, "Untertitel existiert")
	assert_eq(
		subtitle.get_theme_font_size("font_size"),
		roundi(AcTokens.FONT_SIZE_CAPTION * 2.0),
		"Untertitel (CaptionLabel) skaliert mit f=2"
	)
	var claim := panel.find_child("ClaimFeed3", true, false) as Button
	assert_eq(
		claim.get_theme_font_size("font_size"),
		roundi(AcTokens.FONT_SIZE_BUTTON * 2.0),
		"Abholen-Knopf skaliert mit f=2"
	)
	panel.free()
	await _unpin()


func test_quest_service_sound_und_haptik_zeilen() -> void:
	# Quellen-Wache (Muster test_g3_arcade): G2-Fixliste A5 — der Claim
	# behält seinen EINEN Sticker-Sound und bekommt die Erfolgs-Haptik,
	# der Reroll klingt als ui_chip, aber nur wenn wirklich getauscht.
	var src := FileAccess.get_file_as_string("res://scripts/logic/quests/quest_service.gd")
	assert_false(src.is_empty(), "quest_service.gd lesbar")
	assert_eq(
		src.count('AudioDirector.try_play(self, "ui_sticker")'),
		1,
		"Claim-Sound bleibt EIN ui_sticker (kein Doppel-Klang)"
	)
	assert_true(src.contains("Haptics.success(self)"), "Claim summt als Erfolgs-Doppelimpuls")
	assert_true(src.contains("if reroll():"), "Reroll-Sound nur bei echtem Tausch")
	assert_true(
		src.contains('AudioDirector.try_play(self, "ui_chip")'), "Reroll klingt als ui_chip"
	)


# ── Bett-Nachtkarte ───────────────────────────────────────────────────────────


func test_bett_overlay_veil_panelstack_metrics() -> void:
	await _pin(QUER)
	PanelStack.clear()
	var overlay := Bett.BettOverlay.new()
	var karte := PanelContainer.new()
	karte.name = "BettKarte"
	karte.theme_type_variation = "AcCard"
	overlay.add_child(karte)
	overlay.karte = karte
	var btn := SquishButton.new()
	btn.text = "Schlafen"
	karte.add_child(btn)
	var geschlossen: Array = []
	overlay.weg_gewuenscht.connect(func() -> void: geschlossen.append(true))
	tree.root.add_child(overlay)
	await wait_frames(2)
	assert_true(overlay.get_node_or_null("Veil") is ColorRect, "Veil dunkelt den Raum ab")
	assert_true(PanelStack.is_top(overlay), "Overlay meldet sich am PanelStack an")
	var m := ScreenShell.metrics(tree.root)
	var want_w := ScreenShell.card_width(m, Bett.BettOverlay.CARD_BASE_WIDTH)
	assert_almost(karte.offset_right - karte.offset_left, want_w, 0.5, "Kartenbreite = card_width")
	var canvas: Vector2 = m["canvas"]
	assert_almost(
		(karte.offset_left + karte.offset_right) / 2.0,
		canvas.x / 2.0,
		1.0,
		"Karte mittig in der Safe-Area"
	)
	_hat_touch_floor(btn, float(m["floor_px"]), "Nachtkarten-Knopf")
	# Back/Escape-Pfad: close_top ruft close() — das Bett schließt über
	# weg_gewuenscht (EIN Dismiss-Pfad), nie hart am Signal vorbei.
	PanelStack.close_top()
	assert_eq(geschlossen.size(), 1, "Back-Geste löst weg_gewuenscht aus")
	# Backdrop-Tap wirkt nur als oberstes Panel.
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	overlay._on_veil_input(tap)
	assert_eq(geschlossen.size(), 2, "Veil-Tap schließt als oberstes Panel")
	var oben := Control.new()
	PanelStack.push(oben)
	overlay._on_veil_input(tap)
	assert_eq(geschlossen.size(), 2, "unter einem anderen Panel schluckt der Veil den Tap")
	PanelStack.remove(oben)
	oben.free()
	overlay.free()
	PanelStack.clear()
	await _unpin()


# ── Geburtstags-Panel ─────────────────────────────────────────────────────────


func test_birthday_panel_als_accard_mit_steppern() -> void:
	await _pin(QUER)
	PanelStack.clear()
	var room := RoomStub.new()
	tree.root.add_child(room)
	var reactions := GoobyReactions.new()
	reactions.room = room
	reactions._open_birthday_panel()
	await wait_frames(2)
	var overlay := room.layer.get_node("SoulBirthdayPanel") as Control
	assert_true(overlay != null, "Overlay hängt am ui_layer")
	assert_true(overlay.get_node_or_null("Veil") is ColorRect, "Veil vorhanden")
	assert_true(PanelStack.is_top(overlay), "PanelStack kennt das Panel")
	var karte := overlay.find_child("BirthdayKarte", true, false) as PanelContainer
	assert_true(karte != null, "Karte existiert")
	assert_eq(str(karte.theme_type_variation), "AcCard", "Karte trägt AcCard-Optik")
	var m := ScreenShell.metrics(tree.root)
	assert_almost(
		karte.custom_minimum_size.x,
		ScreenShell.card_width(m, SoulBirthdayPanel.CARD_BASE_WIDTH),
		0.5,
		"Kartenbreite = card_width"
	)
	var floor_px: float = m["floor_px"]
	for btn: Node in overlay.find_children("*", "Button", true, false):
		assert_true(btn is SquishButton, "%s squisht" % btn.name)
		_hat_touch_floor(btn as Control, floor_px, str(btn.name))
	# Stepper: Umlauf 1 → 12 beim Runterzählen, kein SpinBox-Gefrickel.
	var wert := overlay.find_child("WertMonth", true, false) as Label
	var minus := overlay.find_child("MinusMonth", true, false) as Button
	var plus := overlay.find_child("PlusMonth", true, false) as Button
	assert_eq(wert.text, "1", "Monat startet bei 1")
	minus.pressed.emit()
	assert_eq(wert.text, "12", "Runterzählen läuft um (1 → 12)")
	plus.pressed.emit()
	assert_eq(wert.text, "1", "Hochzählen läuft zurück (12 → 1)")
	# Abbrechen räumt Panel UND PanelStack auf.
	(overlay.find_child("BirthdayCancel", true, false) as Button).pressed.emit()
	await wait_frames(2)
	assert_false(is_instance_valid(overlay), "Abbrechen räumt das Overlay weg")
	assert_eq(PanelStack.count(), 0, "PanelStack wieder leer")
	reactions.free()
	room.free()
	PanelStack.clear()
	await _unpin()


# ── Tagesbonus-Kalender ───────────────────────────────────────────────────────


func test_daily_bonus_kalender_chips_deckeln_in_schmaler_lane() -> void:
	# iPhone-hoch-Simulation (Muster test_fb3_screen_metrics): f=3 treibt
	# die Chips groß, seitliche Insets machen die Lane schmal — ohne Deckel
	# sprengte die 7er-Zeile die Karte.
	await _pin(HOCH)
	PanelStack.clear()
	UiScale.screen_scale_override = 3.0
	var popup := DailyBonusPopup.new()
	popup.theme = ThemeService.theme()
	var canvas := Vector2(tree.root.get_visible_rect().size)
	popup.safe_area_override = Rect2(150.0, 0.0, canvas.x - 300.0, canvas.y)
	tree.root.add_child(popup)
	await wait_frames(2)
	var m := ScreenShell.metrics(tree.root, popup.safe_area_override)
	var komfort := maxf(DailyBonusPopup.CHIP_BASE * float(m["f"]), float(m["floor_px"]) * 0.72)
	var card := popup.get("_card") as PanelContainer
	var row := card.find_child("CalendarRow", true, false) as HBoxContainer
	var chip := row.get_child(0) as Control
	assert_true(
		chip.custom_minimum_size.x < komfort - 0.5,
		(
			"Deckel greift: Chip (%.0f) unter dem Komfortmaß (%.0f)"
			% [chip.custom_minimum_size.x, komfort]
		)
	)
	var sb := card.get_theme_stylebox("panel")
	var innen: float = (
		card.custom_minimum_size.x - sb.get_margin(SIDE_LEFT) - sb.get_margin(SIDE_RIGHT)
	)
	assert_true(
		row.get_combined_minimum_size().x <= innen + 0.5,
		(
			"Kalender-Zeile (%.0f) passt in die Karten-Innenbreite (%.0f)"
			% [row.get_combined_minimum_size().x, innen]
		)
	)
	# Breite Fläche: der Deckel bremst nicht — Komfortmaß gilt wieder.
	UiScale.screen_scale_override = 0.0
	popup.safe_area_override = Rect2()
	DisplayServer.window_set_size(QUER)
	tree.root.size = QUER
	await wait_frames(2)
	var m2 := ScreenShell.metrics(tree.root)
	assert_almost(
		chip.custom_minimum_size.x,
		maxf(DailyBonusPopup.CHIP_BASE * float(m2["f"]), float(m2["floor_px"]) * 0.72),
		0.5,
		"auf breiter Fläche gilt das Komfortmaß"
	)
	popup.free()
	PanelStack.clear()
	await _unpin()


# ── Gesprächs-Antwort-Chips (HUD-Report H1/H3) ────────────────────────────────


func test_gespraech_chips_erfuellen_uikern_vertrag() -> void:
	await _pin(QUER)
	UiAnchors.reset_for_tests()
	var kette := _gespraech_aufbauen()
	var gespraech: GoobyGespraech = kette["gespraech"]
	var room: RoomStub = kette["room"]
	gespraech._zeige_chips(_echte_ebene())
	await wait_frames(2)
	var panel := room.layer.get_node("GoobyGespraechChips") as Control
	assert_true(panel != null, "Chips-Panel steht am ui_layer")
	var m := ScreenShell.metrics(tree.root)
	var floor_px: float = m["floor_px"]
	var row := panel.get_child(0) as HBoxContainer
	assert_eq(row.get_child_count(), 2, "zwei Antwort-Chips")
	for chip: Node in row.get_children():
		assert_true(chip is SquishButton, "Chip squisht (SquishButton statt Button)")
		assert_eq((chip as Button).theme_type_variation, &"AcChip", "Chip trägt die AcChip-Optik")
		_hat_touch_floor(chip as Control, floor_px, str((chip as Button).text))
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	var unterkante := panel.position.y + panel.size.y
	assert_true(
		unterkante <= canvas.y - float(insets["bottom"]) - 0.5,
		"Chips bleiben ÜBER der Safe-Area-Unterkante (keine Fix-Offsets mehr)"
	)
	assert_almost(
		panel.position.x + panel.size.x / 2.0,
		canvas.x / 2.0,
		1.0,
		"Chips mittig in der Daumen-Zone"
	)
	assert_true(
		UiAnchors.occupants(UiAnchors.ZONE_BOTTOM).has(panel),
		"Chips reservieren die Bottom-Zone (Bubbles/Toasts dodgen)"
	)
	gespraech._chips_weg()
	assert_false(
		UiAnchors.occupants(UiAnchors.ZONE_BOTTOM).has(panel),
		"weg = Bottom-Zone wieder freigegeben"
	)
	room.free()
	kette["seele"].free()
	UiAnchors.reset_for_tests()
	await _unpin()


func test_gespraech_chips_dodgen_belegte_bottom_zone() -> void:
	await _pin(QUER)
	UiAnchors.reset_for_tests()
	var kette := _gespraech_aufbauen()
	var gespraech: GoobyGespraech = kette["gespraech"]
	var room: RoomStub = kette["room"]
	# „Sprechblase“ unten mittig — belegt die Bottom-Zone wie AcBubble.
	var bubble := Control.new()
	bubble.position = Vector2(340.0, 560.0)
	bubble.size = Vector2(600.0, 140.0)
	room.layer.add_child(bubble)
	UiAnchors.reserve(UiAnchors.ZONE_BOTTOM, bubble)
	gespraech._zeige_chips(_echte_ebene())
	await wait_frames(2)
	var panel := room.layer.get_node("GoobyGespraechChips") as Control
	assert_true(
		panel.position.y + panel.size.y <= bubble.position.y - UiAnchors.GAP_PX + 0.5,
		"Chips rutschen ÜBER die belegte Bubble (dodge) statt zu überlappen"
	)
	gespraech._chips_weg()
	room.free()
	kette["seele"].free()
	UiAnchors.reset_for_tests()
	await _unpin()


## Stub-Kette Raum → Runner → Seele → GoobyGespraech (nur ui_layer-Vertrag).
func _gespraech_aufbauen() -> Dictionary:
	var room := RoomStub.new()
	tree.root.add_child(room)
	var runner := RunnerStub.new()
	runner.room = room
	room.add_child(runner)
	var seele := SeeleStub.new()
	seele.runner = runner
	tree.root.add_child(seele)
	var gespraech := GoobyGespraech.new()
	gespraech.name = "GoobyGespraech"
	seele.add_child(gespraech)
	gespraech.seele = seele
	return {"room": room, "seele": seele, "gespraech": gespraech}


## Echte Ebene-1-Daten aus dem Content-JSON (wie test_w14_voice).
func _echte_ebene() -> Dictionary:
	var ebene := GoobyGespraech.fuer_anlass(GoobyGespraech.lade(), "gruss_eingeschnappt")
	assert_false(ebene.is_empty(), "gruss_eingeschnappt dockt an ein Gespräch an")
	return ebene


class RoomStub:
	extends Node
	## Minimaler Raum: nur der ui_layer()-Vertrag der echten Räume.

	var layer := CanvasLayer.new()

	func _init() -> void:
		add_child(layer)

	func ui_layer() -> CanvasLayer:
		return layer


class RunnerStub:
	extends Node
	## SeeleRunner-Double: GoobyGespraech liest nur .room.

	var room: Node


class SeeleStub:
	extends Node
	## Seelen-Double: GoobyGespraech liest nur .runner.

	var runner: Node
