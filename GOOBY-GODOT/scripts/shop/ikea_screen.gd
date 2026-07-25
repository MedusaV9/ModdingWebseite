class_name IkeaScreen
extends Control
## GOUHBUS-Möbelausstellung (CONTENT-B) — der „IKEA“-Screen aus dem
## User-Wunsch D: „Möbel-AUSSTELLUNG in 3D (drehbare Modelle), Kategorien-
## Suche, Farbe/Muster/Stoff anpassen, Grid-Felder-Bedarf sichtbar; viele
## Deko-Artikel (Toaster etc.); SEHR viele Möbel am Ende.“
##
## Aufbau: links Suche + Kategorie-Chips + Regalliste, rechts die Vitrine
## (`FurnitureShowcase`) mit Farbmustern, Zoom-Slider, Preis und Kaufen.
## Gekauftes wandert ins LAGER (`ShopPurchase`), nicht direkt in den Raum.
##
## HUD-Verdrahtung (Muster ArcadeScreen, W1c-API): der Home-Besitzer
## verbindet einmalig `hud.action_pressed.connect(IkeaScreen.handle_hud_action)`
## — siehe Handoff `CONTENTB-hud-request.md`.

signal item_selected(item_id: String)
signal item_bought(item_id: String, variant_id: String)
signal back_requested

const ROUTE_IKEA := &"ikea"
const ROUTES := {ROUTE_IKEA: "res://scripts/shop/ikea_screen.tscn"}
const HUD_ACTION := &"ikea"

const CATEGORY_ALL := ""
const LIST_WIDTH := 360
const SWATCH_SIZE := 40
const SHOWCASE_MIN_HEIGHT := 260

## Tests/Screenshots: Navigation und Drehteller abschaltbar.
var auto_navigate := true
var game_state_override: Object = null

var _showcase: FurnitureShowcase
var _list: VBoxContainer
var _chips: HBoxContainer
var _chip_scroll: ScrollContainer
var _search: LineEdit
var _name_label: Label
var _meta_label: Label
var _footprint_label: Label
var _price_label: Label
var _buy_button: Button
var _coins_label: Label
var _storage_label: Label
var _swatches: HBoxContainer
var _zoom_slider: HSlider
var _toasts: ToastLayer
var _kategorie := CATEGORY_ALL
var _selected := ""
var _variant := FurnitureVariants.DEFAULT_ID


## Route am SceneRouter anmelden (idempotent) — wie ArcadeScreen.
static func register_routes() -> void:
	var router := _router()
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


## EIN Verdrahtungspunkt für den HUD-Button. true = Action konsumiert.
static func handle_hud_action(action: StringName) -> bool:
	if action != HUD_ACTION:
		return false
	register_routes()
	var router := _router()
	if router == null or not router.has_method("goto"):
		return false
	router.goto(ROUTE_IKEA, {})
	return true


static func _router() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_build_ui()
	_refresh_chips()
	_refresh_list()
	_refresh_wallet()
	var first := ShopCatalog.filter("", _kategorie)
	if not first.is_empty():
		select_item(str(first[0]["id"]))


## Ein Möbel in die Vitrine stellen (auch von Tests/Screenshots gerufen).
func select_item(item_id: String) -> void:
	var item := ShopCatalog.def(item_id)
	if item.is_empty():
		return
	_selected = item_id
	_variant = FurnitureVariants.ids_for(item)[0]
	_showcase.show_item(item, _variant)
	_refresh_details()
	item_selected.emit(item_id)


## Farbvariante wechseln (Muster-Knöpfe unter der Vitrine).
func select_variant(variant_id: String) -> void:
	var item := ShopCatalog.def(_selected)
	if item.is_empty():
		return
	_variant = FurnitureVariants.normalize(item, variant_id)
	_showcase.set_variant(_variant)
	_refresh_swatches()


## Aktuelle Auswahl kaufen. Liefert den ShopPurchase-Ergebniscode.
func buy_selected() -> String:
	var item := ShopCatalog.def(_selected)
	if item.is_empty():
		return ShopPurchase.RESULT_UNKNOWN
	var result := ShopPurchase.buy(_game_state(), _selected, _variant)
	_show_result(item, result)
	_refresh_wallet()
	_refresh_details()
	if result == ShopPurchase.RESULT_OK:
		item_bought.emit(_selected, _variant)
	return result


func selected_id() -> String:
	return _selected


func selected_variant() -> String:
	return _variant


func showcase() -> FurnitureShowcase:
	return _showcase


## Kategorie-Filter setzen ("" = alles).
func set_kategorie(kategorie: String) -> void:
	_kategorie = kategorie
	_refresh_chips()
	_refresh_list()


func set_search(query: String) -> void:
	_search.text = query
	_refresh_list()


func _game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


# ── Aufbau ──────────────────────────────────────────────────────────────


func _build_ui() -> void:
	var paper := AcWallpaper.new()
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 20.0
	rows.offset_right = -20.0
	rows.offset_top = 14.0
	rows.offset_bottom = -14.0
	rows.add_theme_constant_override("separation", 10)
	add_child(rows)
	rows.add_child(_build_header())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	rows.add_child(body)
	body.add_child(_build_left_column())
	body.add_child(_build_right_column())
	_toasts = ToastLayer.new()
	add_child(_toasts)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.name = "BackButton"
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("shop.ikea.back")
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("shop.ikea.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.theme_type_variation = &"HeadlineLabel"
	header.add_child(_coins_label)
	_storage_label = Label.new()
	_storage_label.name = "StorageLabel"
	_storage_label.theme_type_variation = &"CaptionLabel"
	header.add_child(_storage_label)
	return header


func _build_left_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	column.add_theme_constant_override("separation", 8)
	_search = LineEdit.new()
	_search.name = "SearchField"
	_search.placeholder_text = I18nService.t("shop.ikea.search")
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	column.add_child(_search)
	_chip_scroll = ScrollContainer.new()
	_chip_scroll.custom_minimum_size = Vector2(0, 52)
	_chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_chip_scroll)
	_chips = HBoxContainer.new()
	_chips.name = "CategoryChips"
	_chips.add_theme_constant_override("separation", 6)
	_chip_scroll.add_child(_chips)
	var list_scroll := ScrollContainer.new()
	list_scroll.name = "ItemScroll"
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.name = "ItemList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	list_scroll.add_child(_list)
	return column


func _build_right_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCardLg"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(card)
	_showcase = FurnitureShowcase.new()
	_showcase.name = "Showcase"
	_showcase.custom_minimum_size = Vector2(0, SHOWCASE_MIN_HEIGHT)
	_showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(_showcase)
	column.add_child(_build_detail_panel())
	return column


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AcCard"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	_name_label = Label.new()
	_name_label.name = "ItemName"
	_name_label.theme_type_variation = &"HeadlineLabel"
	rows.add_child(_name_label)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 12)
	rows.add_child(meta)
	_footprint_label = Label.new()
	_footprint_label.name = "FootprintLabel"
	_footprint_label.theme_type_variation = &"CaptionLabel"
	meta.add_child(_footprint_label)
	_meta_label = Label.new()
	_meta_label.name = "MetaLabel"
	_meta_label.theme_type_variation = &"CaptionLabel"
	meta.add_child(_meta_label)
	rows.add_child(_build_variant_row())
	rows.add_child(_build_zoom_row())
	rows.add_child(_build_buy_row())
	return panel


func _build_variant_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionLabel"
	caption.text = I18nService.t("shop.ikea.variants")
	row.add_child(caption)
	_swatches = HBoxContainer.new()
	_swatches.name = "Swatches"
	_swatches.add_theme_constant_override("separation", 6)
	row.add_child(_swatches)
	return row


func _build_zoom_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionLabel"
	caption.text = I18nService.t("shop.ikea.zoom")
	row.add_child(caption)
	_zoom_slider = HSlider.new()
	_zoom_slider.name = "ZoomSlider"
	# Slider wächst nach rechts = näher ran, deshalb invertiert gemappt.
	_zoom_slider.min_value = FurnitureShowcase.ZOOM_MIN
	_zoom_slider.max_value = FurnitureShowcase.ZOOM_MAX
	_zoom_slider.step = 0.02
	_zoom_slider.value = FurnitureShowcase.ZOOM_DEFAULT
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.custom_minimum_size = Vector2(120, AcTokens.TOUCH_FLOOR)
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	row.add_child(_zoom_slider)
	return row


func _build_buy_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_price_label = Label.new()
	_price_label.name = "PriceLabel"
	_price_label.theme_type_variation = &"HeadlineLabel"
	_price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_price_label)
	_buy_button = Button.new()
	_buy_button.name = "BuyButton"
	_buy_button.theme_type_variation = &"PrimaryButton"
	_buy_button.text = I18nService.t("shop.ikea.buy")
	_buy_button.custom_minimum_size = Vector2(150, AcTokens.TOUCH_FLOOR)
	_buy_button.pressed.connect(_on_buy_pressed)
	row.add_child(_buy_button)
	return row


# ── Auffrischen ─────────────────────────────────────────────────────────


func _refresh_chips() -> void:
	_leeren(_chips)
	var aktiv := _make_chip(CATEGORY_ALL, I18nService.t("shop.ikea.alle"))
	_chips.add_child(aktiv)
	for kategorie: String in ShopCatalog.categories():
		var chip := _make_chip(kategorie, _kategorie_label(kategorie))
		_chips.add_child(chip)
		if kategorie == _kategorie:
			aktiv = chip
	# Die Chip-Leiste ist breiter als die Spalte — die aktive Kategorie muss
	# sichtbar bleiben, sonst weiß niemand, wonach gerade gefiltert wird.
	_scroll_to_chip.call_deferred(aktiv)


func _make_chip(kategorie: String, text: String) -> Button:
	var chip := Button.new()
	chip.name = "Chip_%s" % (kategorie if kategorie != "" else "alle")
	chip.theme_type_variation = &"ChipLeaf" if kategorie == _kategorie else &"AcChip"
	chip.text = text
	chip.custom_minimum_size = Vector2(0, AcTokens.TOUCH_FLOOR)
	chip.pressed.connect(_on_chip_pressed.bind(kategorie))
	return chip


## Kinder SOFORT aushängen und dann freigeben: ein reines queue_free() lässt
## die alten Knöpfe noch einen Frame im Container hängen — der Layout-Lauf
## rechnet dann mit doppelter Breite (Chip-Leiste scrollte ans falsche Ende).
func _leeren(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## Aktive Kategorie mittig in die Chip-Leiste rücken (ensure_control_visible
## würde sie an den Rand kleben und halb abschneiden).
func _scroll_to_chip(chip: Control) -> void:
	if _chip_scroll == null or not is_instance_valid(chip) or not chip.is_inside_tree():
		return
	var mitte := chip.position.x + chip.size.x * 0.5 - _chip_scroll.size.x * 0.5
	_chip_scroll.scroll_horizontal = int(maxf(0.0, mitte))


func _refresh_list() -> void:
	_leeren(_list)
	var items := ShopCatalog.filter(_search.text if _search != null else "", _kategorie)
	if items.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"SoftLabel"
		empty.text = I18nService.t("shop.ikea.leer")
		_list.add_child(empty)
		return
	for item: Dictionary in items:
		_list.add_child(_make_row(item))


func _make_row(item: Dictionary) -> Button:
	var id := str(item["id"])
	var row := Button.new()
	row.name = "Row_%s" % id
	row.theme_type_variation = &"AcCardButton"
	row.custom_minimum_size = Vector2(0, 58)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = (
		"%s   ·   %s"
		% [
			FurnitureCatalog.display_name(item, I18nService.get_locale()),
			I18nService.t("shop.ikea.preis", {"n": int(item["preis"])}),
		]
	)
	row.pressed.connect(_on_row_pressed.bind(id))
	return row


func _refresh_details() -> void:
	var item := ShopCatalog.def(_selected)
	if item.is_empty():
		return
	_name_label.text = FurnitureCatalog.display_name(item, I18nService.get_locale())
	var fp: Vector2i = item["footprint"]
	_footprint_label.text = I18nService.t("shop.ikea.felder", {"x": fp.x, "y": fp.y})
	_meta_label.text = (
		"%s · %s"
		% [
			_kategorie_label(str(item["kategorie"])),
			I18nService.t("shop.ikea.lagerwert", {"n": int(item["lagerwert"])}),
		]
	)
	_price_label.text = I18nService.t("shop.ikea.preis", {"n": int(item["preis"])})
	_buy_button.disabled = not ShopPurchase.can_buy(_game_state(), _selected)
	_refresh_swatches()


func _refresh_swatches() -> void:
	_leeren(_swatches)
	var item := ShopCatalog.def(_selected)
	if item.is_empty():
		return
	for variant_id: String in FurnitureVariants.ids_for(item):
		_swatches.add_child(_make_swatch(variant_id))


func _make_swatch(variant_id: String) -> Button:
	var swatch := Button.new()
	swatch.name = "Swatch_%s" % variant_id
	swatch.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
	swatch.tooltip_text = FurnitureVariants.label(variant_id)
	var active := variant_id == _variant
	var box := StyleBoxFlat.new()
	box.bg_color = FurnitureVariants.tint(variant_id)
	box.set_corner_radius_all(AcTokens.RADIUS_ROW)
	box.set_border_width_all(3 if active else 1)
	box.border_color = AcTokens.PINK if active else AcTokens.OUTLINE_SOFT
	swatch.add_theme_stylebox_override("normal", box)
	swatch.add_theme_stylebox_override("hover", box)
	swatch.add_theme_stylebox_override("pressed", box)
	swatch.pressed.connect(_on_swatch_pressed.bind(variant_id))
	return swatch


func _refresh_wallet() -> void:
	var gs := _game_state()
	var coins := 0
	var capacity := 0
	var free := 0
	if gs != null:
		coins = int(gs.get_value("economy.coins", 0))
		capacity = int(gs.get_value("home.storageCapacity", 100))
		free = ShopPurchase.storage_free(gs)
	_coins_label.text = I18nService.t("shop.ikea.muenzen", {"n": coins})
	_storage_label.text = I18nService.t("shop.ikea.lager", {"frei": free, "gesamt": capacity})


func _kategorie_label(kategorie: String) -> String:
	var key := "shop.kategorie.%s" % kategorie
	return I18nService.t(key) if I18nService.has_key(key) else kategorie


func _show_result(item: Dictionary, result: String) -> void:
	var name_text := FurnitureCatalog.display_name(item, I18nService.get_locale())
	match result:
		ShopPurchase.RESULT_OK:
			AudioDirector.try_play(self, "ui_confirm")
			_toasts.show_toast(I18nService.t("shop.ikea.gekauft", {"name": name_text}))
		ShopPurchase.RESULT_BROKE:
			_toasts.show_toast(I18nService.t("shop.ikea.zu_teuer"), true)
		ShopPurchase.RESULT_FULL:
			_toasts.show_toast(I18nService.t("shop.ikea.lager_voll"), true)
		_:
			_toasts.show_toast(I18nService.t("shop.ikea.fehler"), true)


# ── Signale ─────────────────────────────────────────────────────────────


func _on_chip_pressed(kategorie: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	set_kategorie(kategorie)


func _on_search_changed(_text: String) -> void:
	_refresh_list()


func _on_row_pressed(item_id: String) -> void:
	AudioDirector.try_play(self, "ui_click")
	select_item(item_id)


func _on_swatch_pressed(variant_id: String) -> void:
	AudioDirector.try_play(self, "ui_toggle")
	select_variant(variant_id)


func _on_zoom_changed(value: float) -> void:
	_showcase.set_zoom(value)


func _on_buy_pressed() -> void:
	buy_selected()


func _on_back_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	back_requested.emit()
	if not auto_navigate:
		return
	var router := _router()
	if router == null or not router.has_method("goto"):
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})
