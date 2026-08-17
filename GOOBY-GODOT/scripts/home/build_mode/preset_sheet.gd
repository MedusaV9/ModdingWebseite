class_name PresetSheet
extends Control
## Preset-Sheet im Baumodus (W13C, Doc D §10): die 3 Layout-Slots des Raums
## mit Mini-Vorschau-Info („12 Möbel · 2 Girlanden“), Namensfeld und den
## Aktionen Speichern/Überschreiben, Anwenden und Löschen — Anwenden und
## Löschen wollen eine Bestätigung (zweiter Tap auf „Sicher?“).
##
## Daten + Sicherheitsnetz liegen komplett in LayoutPresetsLogic; dieses
## Sheet ist reine Anzeige/Verdrahtung (Muster: GoobayPanel).
##
## G4/UI-BAU: Metrik-Pass (ScreenShell) — Karte auf card_width gedeckelt,
## Touch-Floor auf allen Knöpfen, Schriften ×f, Slot-Zeilen als HFlow
## (Hochformat bricht um statt zu quetschen) und Tastatur-Ausweich: bei
## fokussiertem Namensfeld ankert die Karte oben (iOS-Tastatur verdeckt
## sonst das Feld).

signal angewendet(fehlend: int)
signal closed

## Design-Basisbreite der Karte (wird über ScreenShell.card_width geklemmt).
const CARD_BASIS := 560.0

var _gs: Object
var _room_id := ""
var _card: PanelContainer
var _name_feld: LineEdit
var _slot_zeilen: VBoxContainer
var _hinweis: Label
## Letzter Metrik-Pass (für Floors auf frisch gebauten Slot-Zeilen).
var _m: Dictionary = {}
## Armierte Bestätigung ("anwenden:0", "loeschen:2", "" = keine).
var _bestaetigung := ""


static func open_in(ui_layer: Node, gs: Object, room_id: String) -> PresetSheet:
	var sheet := PresetSheet.new()
	sheet.name = "PresetSheet"
	sheet._gs = gs
	sheet._room_id = room_id
	# Anker VOR add_child (GoobayPanel-Muster): unter einem CanvasLayer
	# bleibt ein Control sonst 0×0 groß.
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(sheet)
	return sheet


func _ready() -> void:
	theme = ThemeService.theme()
	_build_ui()
	_refresh()
	get_viewport().size_changed.connect(_apply_metrics)
	_apply_metrics()
	AudioDirector.try_play(self, "ui_open")


func close() -> void:
	AudioDirector.try_play(self, "ui_close")
	closed.emit()
	queue_free()


## Slot speichern/überschreiben (Name kommt aus dem Feld). Auch für Tests.
func speichern(slot: int) -> bool:
	var grund := LayoutPresetsLogic.save_slot(_gs, _room_id, slot, _name_feld.text)
	if grund == LayoutPresetsLogic.REASON_NAME_LEER:
		AudioDirector.try_play(self, "ui_error")
		Haptics.warn(self)
		_sag(I18nService.t("build.preset.name_hinweis"))
		return false
	if grund != "":
		return false
	AudioDirector.try_play(self, "ui_confirm")
	_sag(I18nService.t("build.preset.gespeichert"))
	_refresh()
	return true


## Slot anwenden (nach Bestätigung). Auch für Tests.
func anwenden(slot: int) -> bool:
	var plan := LayoutPresetsLogic.apply_slot(_gs, _room_id, slot)
	if not bool(plan["ok"]):
		if str(plan["reason"]) == LayoutPresetsLogic.REASON_LAGER_VOLL:
			_sag(I18nService.t("build.preset.lager_voll"))
			AudioDirector.try_play(self, "ui_error")
			Haptics.warn(self)
		return false
	AudioDirector.try_play(self, "ui_confirm")
	angewendet.emit(int(plan["fehlend"]))
	close()
	return true


func loeschen(slot: int) -> void:
	LayoutPresetsLogic.delete_slot(_gs, _room_id, slot)
	# Destruktive Aktion (Audio-Grammatik): Standard-Klang + Warn-Haptik.
	AudioDirector.try_play(self, "ui_click")
	Haptics.warn(self)
	_sag(I18nService.t("build.preset.geloescht"))
	_refresh()


# ── UI ───────────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_card = PanelContainer.new()
	_card.theme_type_variation = "AcCard"
	_karte_verankern(false)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_card.add_child(box)
	var kopf := HBoxContainer.new()
	box.add_child(kopf)
	var titel := Label.new()
	titel.text = I18nService.t("build.preset.titel")
	titel.theme_type_variation = "TitleLabel"
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	var zu := SquishButton.new()
	zu.text = I18nService.t("build.preset.schliessen")
	zu.theme_type_variation = "GhostButton"
	# close() spielt ui_close — der Druck selbst bleibt stumm (Doppel-Klang).
	zu.pressed.connect(close)
	kopf.add_child(zu)
	_name_feld = LineEdit.new()
	_name_feld.placeholder_text = I18nService.t("build.preset.name_platzhalter")
	_name_feld.max_length = LayoutPresetsLogic.NAME_MAX
	# Tastatur-Ausweich: solange getippt wird, hängt die Karte oben — die
	# Bildschirm-Tastatur (bis ~50 % Höhe quer) verdeckt sonst das Feld.
	_name_feld.focus_entered.connect(_karte_verankern.bind(true))
	_name_feld.focus_exited.connect(_karte_verankern.bind(false))
	box.add_child(_name_feld)
	_slot_zeilen = VBoxContainer.new()
	_slot_zeilen.add_theme_constant_override("separation", 8)
	box.add_child(_slot_zeilen)
	_hinweis = Label.new()
	_hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hinweis)


## Metrik-Pass: Kartenbreite (card_width-Klemmung), Touch-Floor auf alle
## Knöpfe + Namensfeld, Theme-Schriften ×f. Läuft bei _ready, jeder
## Viewport-Größenänderung und nach jedem Slot-Rebuild.
func _apply_metrics() -> void:
	if _card == null or not is_inside_tree():
		return
	_m = ScreenShell.metrics(get_viewport())
	_card.custom_minimum_size = Vector2(ScreenShell.card_width(_m, CARD_BASIS), 0.0)
	_floors_und_schrift()


func _floors_und_schrift() -> void:
	if _m.is_empty():
		return
	var floor_px: float = _m["floor_px"]
	for node in find_children("*", "Button", true, false):
		(node as Control).custom_minimum_size = Vector2(floor_px, floor_px)
	_name_feld.custom_minimum_size = Vector2(0.0, floor_px)
	ScreenShell.scale_fonts(self, float(_m["f"]))


## Karte mittig (Normalfall) oder oben verankern (Tastatur-Ausweich bei
## fokussiertem Namensfeld). Breite kommt aus custom_minimum_size + grow.
func _karte_verankern(oben: bool) -> void:
	if _card == null:
		return
	var f := float(_m.get("f", 1.0))
	var insets: Dictionary = _m.get("insets", {"top": 0.0})
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP if oben else Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = (Control.GROW_DIRECTION_END if oben else Control.GROW_DIRECTION_BOTH)
	_card.offset_left = 0.0
	_card.offset_right = 0.0
	_card.offset_top = (float(insets["top"]) + ScreenShell.EDGE_Y * f) if oben else 0.0
	_card.offset_bottom = _card.offset_top if oben else 0.0


func _refresh() -> void:
	_bestaetigung = ""
	for child in _slot_zeilen.get_children():
		child.queue_free()
	var liste := LayoutPresetsLogic.slots(_gs, _room_id)
	for slot in liste.size():
		_slot_zeilen.add_child(_slot_zeile(slot, liste[slot]))
	_floors_und_schrift()


## Slot-Zeile als Flow: in schmalen Formaten brechen die Knöpfe unter das
## Info-Label um, statt es zur Ellipse zu quetschen (G1 ui-bau §2).
func _slot_zeile(slot: int, preset: Dictionary) -> HFlowContainer:
	var zeile := HFlowContainer.new()
	zeile.add_theme_constant_override("h_separation", 8)
	zeile.add_theme_constant_override("v_separation", 6)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if preset.is_empty():
		info.text = I18nService.t("build.preset.frei")
		zeile.add_child(info)
		_zeile_knopf(zeile, slot, "speichern", "AccentButton", false)
		return zeile
	var kurz := LayoutPresetsLogic.zusammenfassung(preset)
	info.text = (
		"%s — %s"
		% [
			str(preset.get("name", "")),
			I18nService.t("build.preset.info", kurz),
		]
	)
	zeile.add_child(info)
	_zeile_knopf(zeile, slot, "anwenden", "PrimaryButton", true)
	_zeile_knopf(zeile, slot, "ueberschreiben", "AcChip", false)
	_zeile_knopf(zeile, slot, "loeschen", "GhostButton", true)
	return zeile


## Aktions-Knopf einer Slot-Zeile; `bestaetigen` = zweiter Tap nötig.
func _zeile_knopf(
	zeile: HFlowContainer, slot: int, aktion: String, stil: String, sicher: bool
) -> void:
	var btn := SquishButton.new()
	btn.text = I18nService.t("build.preset.%s" % aktion)
	btn.theme_type_variation = stil
	btn.pressed.connect(_on_aktion.bind(slot, aktion, sicher, btn))
	zeile.add_child(btn)


func _on_aktion(slot: int, aktion: String, sicher: bool, btn: Button) -> void:
	var schluessel := "%s:%d" % [aktion, slot]
	if sicher and _bestaetigung != schluessel:
		_bestaetigung = schluessel
		AudioDirector.try_play(self, "ui_click")
		btn.text = I18nService.t("build.preset.sicher")
		_sag("")
		return
	_bestaetigung = ""
	match aktion:
		"speichern", "ueberschreiben":
			speichern(slot)
		"anwenden":
			anwenden(slot)
		"loeschen":
			loeschen(slot)


func _sag(text: String) -> void:
	if _hinweis != null:
		_hinweis.text = text
