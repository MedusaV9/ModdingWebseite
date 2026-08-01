class_name BuildUiDock
extends RefCounted
## G4/UI-BAU: Aufbau + Metrik-Pass des Baumodus-UIs — alle Bau-Werkzeuge
## liegen in EINEM unten-mittigen Dock in der Daumenzone (User-Leitidee
## „Hintergrund Vollbild, Inhalte zur Mitte“): Action-Bar über der
## Status/Ebenen-Zeile über der Lager-Karte; Kamera-Chips rechts mittig.
## Maße laufen über ScreenShell (Safe-Area, ×f, Touch-Floor, scale_fonts)
## statt Fix-Pixeln.
##
## Diese Klasse baut NUR Layout und Metrik; Verhalten (pressed-Handler,
## Sounds, Sichtbarkeit) verdrahtet BuildMode auf den exponierten Knöpfen.

const DRAWER_HEIGHT := 168.0
## VIS-2: Innenabstand der Lager-Karte — kein Label darf bündig an der
## Kartenkante starten (abgeschnittene Möbelnamen im Trailer-Review).
const DRAWER_RAND_X := 28.0
const DRAWER_RAND_Y := 10.0
## Design-Basisbreite des Docks (mittige Karte statt BOTTOM_WIDE —
## Grid-Screen-Basis der Wellen G2/G3, via ScreenShell.card_width geklemmt).
const DOCK_BASIS := 920.0
## Abstand zwischen Dock-Zeilen (Action-Bar / Ebenen / Lager), Design-px.
const DOCK_LUFT := 10.0

var ui: Control
var dock: VBoxContainer
var drawer: PanelContainer
var drawer_rand: MarginContainer
var drawer_items: HBoxContainer
var capacity_label: Label
var action_bar: HFlowContainer
var action_buttons: Array[Button] = []
var kamera_leiste: VBoxContainer
var kamera_buttons: Array[Button] = []
var ebenen_leiste: HFlowContainer
var ebenen_chips: Array[Button] = []
var status_label: Label
var presets_button: Button
var goobay_button: Button
var done_button: Button
## Letzter Metrik-Pass (ScreenShell.metrics) — der Drawer-Rebuild floort
## damit frisch gebaute Chips ohne neuen Viewport-Pass.
var m: Dictionary = {}


func build(ui_layer: Node, ebenen_keys: Array[String]) -> void:
	ui = Control.new()
	ui.name = "BuildModeUi"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.visible = false
	ui_layer.add_child(ui)
	_build_kamera_leiste()
	_build_dock(ebenen_keys)
	# Metrik-Pass erst verdrahten, wenn der Viewport existiert (Setup kann
	# vor dem Einhängen des Raums in den Baum laufen).
	if ui.is_inside_tree():
		_im_baum()
	else:
		ui.tree_entered.connect(_im_baum, CONNECT_ONE_SHOT)


func _im_baum() -> void:
	ui.get_viewport().size_changed.connect(apply_metrics)
	apply_metrics()


## EIN Metrik-Pass für das komplette Bau-UI: Dock-Breite (card_width),
## Safe-Area-Insets, f-skalierte Ränder, Touch-Floor und Schriften. Läuft
## beim Aufbau, bei jeder Viewport-Größenänderung und beim Öffnen.
func apply_metrics() -> void:
	if ui == null or not ui.is_inside_tree():
		return
	m = ScreenShell.metrics(ui.get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var breite := ScreenShell.card_width(m, DOCK_BASIS)
	dock.anchor_left = 0.5
	dock.anchor_right = 0.5
	dock.anchor_top = 1.0
	dock.anchor_bottom = 1.0
	dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.offset_left = -breite * 0.5
	dock.offset_right = breite * 0.5
	dock.offset_bottom = -(float(insets["bottom"]) + DRAWER_RAND_Y * f)
	# Höhe wächst über die Kind-Minima automatisch nach OBEN (grow BEGIN).
	dock.offset_top = dock.offset_bottom - DRAWER_HEIGHT * f
	dock.add_theme_constant_override("separation", int(DOCK_LUFT * f))
	drawer.custom_minimum_size = Vector2(0.0, DRAWER_HEIGHT * f)
	drawer_rand.add_theme_constant_override("margin_left", int(DRAWER_RAND_X * f))
	drawer_rand.add_theme_constant_override("margin_right", int(DRAWER_RAND_X * f))
	drawer_rand.add_theme_constant_override("margin_top", int(DRAWER_RAND_Y * f))
	drawer_rand.add_theme_constant_override("margin_bottom", int(DRAWER_RAND_Y * f))
	# Kamera-Leiste rechts mittig (Daumenzone): Insets statt Fix-28-px.
	var rand_rechts := maxf(DRAWER_RAND_X * f, float(insets["right"]) + 12.0 * f)
	kamera_leiste.anchor_left = 1.0
	kamera_leiste.anchor_right = 1.0
	kamera_leiste.anchor_top = 0.5
	kamera_leiste.anchor_bottom = 0.5
	kamera_leiste.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	kamera_leiste.grow_vertical = Control.GROW_DIRECTION_BOTH
	kamera_leiste.offset_left = -rand_rechts
	kamera_leiste.offset_right = -rand_rechts
	kamera_leiste.offset_top = 0.0
	kamera_leiste.offset_bottom = 0.0
	kamera_leiste.add_theme_constant_override("separation", int(8.0 * f))
	floors_und_schrift()


## Touch-Floor (44 pt physisch) auf ALLE Bau-Knöpfe + Theme-Schriften ×f.
## Chips behalten ihre text-basierte Mindestbreite (combined minimum).
func floors_und_schrift() -> void:
	if m.is_empty() or ui == null:
		return
	var floor_px: float = m["floor_px"]
	for node in ui.find_children("*", "Button", true, false):
		(node as Control).custom_minimum_size = Vector2(floor_px, floor_px)
	ScreenShell.scale_fonts(ui, float(m["f"]))


## Aktiver Ebenen-Chip trägt die ChipLeaf-Variation (disabled-Grau las sich
## als „nicht verfügbar“ — G1-Befund ui-bau §1d).
func set_aktive_ebene(ebene: int) -> void:
	for i in ebenen_chips.size():
		ebenen_chips[i].theme_type_variation = &"ChipLeaf" if i == ebene else &"AcChip"


## Persistente, dezente Modus-Anzeige (Status-Kapsel in der Ebenen-Zeile).
func set_status(text: String) -> void:
	if status_label != null and status_label.text != text:
		status_label.text = text


## Unten-mittiges Dock: Action-Bar (nur bei Ghost/Girlande sichtbar) über
## der Status/Ebenen-Zeile über der Lager-Karte.
func _build_dock(ebenen_keys: Array[String]) -> void:
	dock = VBoxContainer.new()
	dock.name = "BauDock"
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dock)
	_build_action_bar()
	_build_ebenen_leiste(ebenen_keys)
	_build_drawer()


func _build_action_bar() -> void:
	action_bar = HFlowContainer.new()
	action_bar.name = "ActionBar"
	action_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_bar.add_theme_constant_override("h_separation", 10)
	action_bar.add_theme_constant_override("v_separation", 8)
	dock.add_child(action_bar)
	action_buttons = []
	for eintrag: Array in [
		["build.rotieren", "GhostButton"],
		["build.bestaetigen", "AccentButton"],
		["build.einlagern", "GhostButton"],
		["build.abbrechen", "GhostButton"],
	]:
		var btn := SquishButton.new()
		btn.text = I18nService.t(str(eintrag[0]))
		btn.theme_type_variation = str(eintrag[1])
		action_bar.add_child(btn)
		action_buttons.append(btn)


## Ebenen-Umschalter (W13B, Doc D §2.1) in der Daumenzone: Status-Kapsel
## (persistente Modus-/Ebenen-Anzeige) + Boden/Wand/Decke-Chips als Flow —
## schmale Formate brechen um statt abzuschneiden.
func _build_ebenen_leiste(ebenen_keys: Array[String]) -> void:
	ebenen_leiste = HFlowContainer.new()
	ebenen_leiste.name = "EbenenLeiste"
	ebenen_leiste.alignment = FlowContainer.ALIGNMENT_CENTER
	ebenen_leiste.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ebenen_leiste.add_theme_constant_override("h_separation", 8)
	ebenen_leiste.add_theme_constant_override("v_separation", 6)
	dock.add_child(ebenen_leiste)
	var kapsel := PanelContainer.new()
	kapsel.name = "ModusKapsel"
	kapsel.theme_type_variation = "StatusCapsule"
	kapsel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ebenen_leiste.add_child(kapsel)
	status_label = Label.new()
	status_label.theme_type_variation = "CaptionLabel"
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kapsel.add_child(status_label)
	ebenen_chips = []
	for key: String in ebenen_keys:
		var btn := SquishButton.new()
		btn.text = I18nService.t(key)
		btn.theme_type_variation = "AcChip"
		btn.focus_mode = Control.FOCUS_NONE
		ebenen_leiste.add_child(btn)
		ebenen_chips.append(btn)


## Kamera-Knöpfe (FIX-3): Draufsicht/Schrägsicht + 2×90°-Drehung, rechts am
## Rand — weit weg von Dock und Action-Bar. Offsets setzt der Metrik-Pass.
func _build_kamera_leiste() -> void:
	kamera_leiste = VBoxContainer.new()
	kamera_leiste.name = "KameraLeiste"
	kamera_leiste.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	kamera_leiste.grow_vertical = Control.GROW_DIRECTION_BOTH
	kamera_leiste.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	kamera_leiste.position.x -= DRAWER_RAND_X
	kamera_leiste.add_theme_constant_override("separation", 8)
	ui.add_child(kamera_leiste)
	kamera_buttons = []
	for key: String in [
		"build.kamera.oben", "build.kamera.schraeg", "build.kamera.links", "build.kamera.rechts"
	]:
		var btn := SquishButton.new()
		btn.text = I18nService.t(key)
		btn.theme_type_variation = "AcChip"
		btn.focus_mode = Control.FOCUS_NONE
		kamera_leiste.add_child(btn)
		kamera_buttons.append(btn)


## Lager als mittige Karte im Dock (statt BOTTOM_WIDE-Randleiste): der
## 3D-Raum bleibt Vollbild, der Inhalt rückt in die Daumenzone.
func _build_drawer() -> void:
	drawer = PanelContainer.new()
	drawer.name = "LagerKarte"
	drawer.theme_type_variation = "AcCard"
	drawer.custom_minimum_size = Vector2(0, DRAWER_HEIGHT)
	dock.add_child(drawer)
	drawer_rand = MarginContainer.new()
	drawer_rand.add_theme_constant_override("margin_left", int(DRAWER_RAND_X))
	drawer_rand.add_theme_constant_override("margin_right", int(DRAWER_RAND_X))
	drawer_rand.add_theme_constant_override("margin_top", int(DRAWER_RAND_Y))
	drawer_rand.add_theme_constant_override("margin_bottom", int(DRAWER_RAND_Y))
	drawer.add_child(drawer_rand)
	var box := VBoxContainer.new()
	drawer_rand.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	capacity_label = Label.new()
	capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wenn der Platz doch mal knapp wird: Ellipse statt hartem Schnitt.
	capacity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(capacity_label)
	# Layout-Presets (W13C, Doc D §10) an der Lager-Karte: Tausch = Grid+Lager.
	presets_button = SquishButton.new()
	presets_button.text = I18nService.t("build.preset.knopf")
	presets_button.theme_type_variation = "AcChip"
	header.add_child(presets_button)
	# Goobay (Doc D §5.4): verkauft wird aus dem LAGER — deshalb sitzt der
	# Einstieg direkt an der Lager-Karte.
	goobay_button = SquishButton.new()
	goobay_button.text = I18nService.t("goobay.verkaufen")
	goobay_button.theme_type_variation = "AcChip"
	header.add_child(goobay_button)
	done_button = SquishButton.new()
	done_button.text = I18nService.t("build.fertig")
	done_button.theme_type_variation = "PrimaryButton"
	header.add_child(done_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)
	drawer_items = HBoxContainer.new()
	drawer_items.add_theme_constant_override("separation", 8)
	scroll.add_child(drawer_items)
