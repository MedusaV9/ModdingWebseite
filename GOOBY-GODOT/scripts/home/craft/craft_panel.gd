class_name CraftPanel
extends Control
## Crafting-Panel der Werkstatt (Doc D §5.2/§5.3): links die Rezeptliste,
## rechts Materialbedarf + BAUEN-Knopf mit Fortschrittsbalken, oben das
## eigene Materiallager.
##
## Das Panel ist reine Anzeige — Regeln und Zustand kommen aus CraftState /
## CraftLogic. Alle Farben stammen aus dem globalen Theme (ThemeService/
## AcTokens), alle Symbole aus HomeIcons (keine rohen Emojis).

signal crafted(item_id: String, count: int)
signal closed

const ICON_PX := 22
const CARD_MIN := Vector2(720, 430)
## Fortschritt läuft nie länger als das, egal was das Rezept sagt.
const MAX_CRAFT_S := 6.0

var _gs: Object
var _room: Node
var _recipe_id := ""
var _busy := false

var _material_bar: HBoxContainer
var _recipe_list: VBoxContainer
var _detail: VBoxContainer
var _status: Label
var _progress: ProgressBar
var _craft_button: Button


## Panel in eine UI-Ebene hängen und öffnen. `room` (optional) bekommt die
## Gooby-Bubbles ab.
static func open_in(ui_layer: Node, gs: Object, room: Node = null) -> CraftPanel:
	var panel := CraftPanel.new()
	panel.name = "CraftPanel"
	panel._gs = gs
	panel._room = room
	# Anker VOR add_child: unter einem CanvasLayer bleibt ein Control sonst
	# 0×0 groß (Godot rechnet die Preset-Offsets nur beim Eintritt aus).
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(panel)
	return panel


func _ready() -> void:
	theme = ThemeService.theme()
	_build_ui()
	refresh()
	AudioDirector.try_play(self, "ui_open")


func close() -> void:
	AudioDirector.try_play(self, "ui_close")
	closed.emit()
	queue_free()


## Materialleiste, Rezeptliste und Detailspalte neu aufbauen.
func refresh() -> void:
	_refresh_materials()
	_refresh_recipes()
	_refresh_detail()


func select_recipe(recipe_id: String) -> void:
	_recipe_id = recipe_id
	_refresh_recipes()
	_refresh_detail()


## Craft auslösen (Fortschritt → CraftState.craft). Auch von Tests gerufen.
func craft_selected() -> void:
	if _busy or _recipe_id == "":
		return
	var pruefung := CraftState.check(_gs, _recipe_id)
	if not bool(pruefung["ok"]):
		_status.text = _reason_text(str(pruefung["reason"]))
		AudioDirector.try_play(self, "ui_error")
		return
	_busy = true
	_craft_button.disabled = true
	_progress.visible = true
	_progress.value = 0.0
	_status.text = I18nService.t("craft.laeuft")
	AudioDirector.try_play(self, "build_hammer")
	await _run_progress()
	var ergebnis := CraftState.craft(_gs, _recipe_id)
	_busy = false
	_progress.visible = false
	# Erst neu aufbauen, dann die Meldung setzen — refresh() überschreibt den
	# Status sonst sofort wieder mit dem (leeren) Prüf-Hinweis.
	refresh()
	if not bool(ergebnis["ok"]):
		_status.text = _reason_text(str(ergebnis["reason"]))
		return
	var name_text := FurnitureCatalog.display_name(
		FurnitureCatalog.def(str(ergebnis["item"])), I18nService.get_locale()
	)
	_status.text = I18nService.t("craft.fertig", {"name": name_text})
	AudioDirector.try_play(self, "ui_confirm")
	if _room != null and _room.has_method("say"):
		_room.say(_status.text)
	crafted.emit(str(ergebnis["item"]), int(ergebnis["count"]))


func _run_progress() -> void:
	var dauer := minf(MAX_CRAFT_S, float(CraftRecipes.recipe(_recipe_id).get("craft_sek", 3.0)))
	if ThemeService.is_reduced_motion(self):
		dauer = 0.2
	var tween := create_tween()
	tween.tween_property(_progress, "value", 100.0, dauer)
	await tween.finished


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	var veil := ColorRect.new()
	veil.color = AcTokens.VEIL
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var card := PanelContainer.new()
	card.theme_type_variation = "AcCard"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = CARD_MIN
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(_build_header())
	_material_bar = HBoxContainer.new()
	_material_bar.add_theme_constant_override("separation", 12)
	box.add_child(_material_bar)
	box.add_child(_build_body())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(HomeIcons.node("hammer", ICON_PX + 4))
	var titel := Label.new()
	titel.text = I18nService.t("craft.titel")
	titel.theme_type_variation = "TitleLabel"
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titel)
	var zu := Button.new()
	zu.text = I18nService.t("craft.schliessen")
	zu.theme_type_variation = "GhostButton"
	zu.pressed.connect(close)
	header.add_child(zu)
	return header


func _build_body() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	var links := ScrollContainer.new()
	links.custom_minimum_size = Vector2(260, 240)
	links.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(links)
	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.add_theme_constant_override("separation", 6)
	links.add_child(_recipe_list)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	body.add_child(_detail)
	return body


func _refresh_materials() -> void:
	for child in _material_bar.get_children():
		child.queue_free()
	var lager := CraftState.materials(_gs)
	var titel := Label.new()
	titel.text = I18nService.t("craft.materialien")
	_material_bar.add_child(titel)
	for material_id: String in CraftMaterials.ids():
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.add_child(HomeIcons.node(str(CraftMaterials.def(material_id)["icon"]), ICON_PX))
		var wert := Label.new()
		wert.text = (
			"%s %d"
			% [
				CraftMaterials.display_name(material_id, I18nService.get_locale()),
				CraftLogic.count_of(lager, material_id),
			]
		)
		chip.add_child(wert)
		_material_bar.add_child(chip)


func _refresh_recipes() -> void:
	for child in _recipe_list.get_children():
		child.queue_free()
	for eintrag: Dictionary in CraftState.recipe_states(_gs):
		var recipe: Dictionary = eintrag["recipe"]
		var id := str(recipe["id"])
		var btn := Button.new()
		btn.text = I18nService.t("craft.rezept.%s" % id)
		btn.theme_type_variation = "AccentButton" if id == _recipe_id else "AcChip"
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = str(eintrag["reason"]) == CraftLogic.REASON_BLUEPRINT
		btn.pressed.connect(select_recipe.bind(id))
		_recipe_list.add_child(btn)


func _refresh_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()
	_progress = null
	_craft_button = null
	if _recipe_id == "":
		var hinweis := Label.new()
		hinweis.text = I18nService.t("craft.kein_rezept")
		_detail.add_child(hinweis)
		return
	var recipe := CraftRecipes.recipe(_recipe_id)
	var lager := CraftState.materials(_gs)
	var kopf := Label.new()
	kopf.text = I18nService.t("craft.rezept.%s" % _recipe_id)
	kopf.theme_type_variation = "TitleLabel"
	_detail.add_child(kopf)
	for material_id: String in recipe["materialien"]:
		_detail.add_child(
			_material_zeile(material_id, int(recipe["materialien"][material_id]), lager)
		)
	var kosten := CraftLogic.baumarkt_kosten(recipe, lager)
	if kosten > 0:
		var hinweis := Label.new()
		hinweis.text = I18nService.t("craft.kosten_baumarkt", {"preis": kosten})
		_detail.add_child(hinweis)
	_detail.add_child(_build_craft_row())


func _material_zeile(material_id: String, brauchen: int, lager: Dictionary) -> Control:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 6)
	zeile.add_child(HomeIcons.node(str(CraftMaterials.def(material_id)["icon"]), ICON_PX))
	var haben := CraftLogic.count_of(lager, material_id)
	var label := Label.new()
	label.text = (
		I18nService
		. t(
			"craft.brauchst",
			{
				"material": CraftMaterials.display_name(material_id, I18nService.get_locale()),
				"haben": haben,
				"brauchen": brauchen,
			}
		)
	)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(label)
	if haben < brauchen:
		var quelle := Label.new()
		quelle.text = I18nService.t(CraftMaterials.quelle_key(material_id))
		zeile.add_child(quelle)
	return zeile


func _build_craft_row() -> Control:
	var zeile := VBoxContainer.new()
	zeile.add_theme_constant_override("separation", 6)
	_progress = ProgressBar.new()
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.visible = false
	zeile.add_child(_progress)
	_craft_button = Button.new()
	_craft_button.text = I18nService.t("craft.bauen")
	_craft_button.theme_type_variation = "PrimaryButton"
	var pruefung := CraftState.check(_gs, _recipe_id)
	_craft_button.disabled = not bool(pruefung["ok"])
	if not bool(pruefung["ok"]):
		_status.text = _reason_text(str(pruefung["reason"]))
	elif not _busy:
		_status.text = ""
	_craft_button.pressed.connect(craft_selected)
	zeile.add_child(_craft_button)
	return zeile


func _reason_text(reason: String) -> String:
	match reason:
		CraftLogic.REASON_STATION:
			return I18nService.t("craft.werkstatt_fehlt")
		CraftLogic.REASON_BLUEPRINT:
			return I18nService.t("craft.bauplan_fehlt")
		CraftLogic.REASON_STORAGE:
			return I18nService.t("craft.lager_voll")
		CraftLogic.REASON_MATERIAL:
			return I18nService.t("craft.material_fehlt")
	return ""
