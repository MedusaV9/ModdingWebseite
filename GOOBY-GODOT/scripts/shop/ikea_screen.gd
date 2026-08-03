class_name IkeaScreen
extends Control
## IKEA-Möbelausstellung (CONTENT-B) — der „IKEA“-Screen aus dem
## User-Wunsch D: „Möbel-AUSSTELLUNG in 3D (drehbare Modelle), Kategorien-
## Suche, Farbe/Muster/Stoff anpassen, Grid-Felder-Bedarf sichtbar; viele
## Deko-Artikel (Toaster etc.); SEHR viele Möbel am Ende.“
## G3: Screen-Titel von „GOUHBUS Möbelausstellung“ auf den Karten-Namen
## „IKEA“ umgestellt (Verwechslung mit Doktor GOOUHBUS, texte-Grenzfall 1).
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
## Inhaltsspalte W16: eigene Grid-Basis — die 2-Spalten-Auslage braucht mehr
## Breite als die 660er-Menü-Spalte, bleibt auf iPad aber gedeckelt + mittig.
const GRID_BASE := 880.0
## Höhen-Anteil der Vitrinen-/Detail-Spalte im Hochformat-Stapel.
const PORTRAIT_DETAIL_SHARE := 0.55

## Tests/Screenshots: Navigation und Drehteller abschaltbar.
var auto_navigate := true
var game_state_override: Object = null

var _showcase: FurnitureShowcase
## G7-P55: lebendiger Vitrinen-Hintergrund (verschwommene Ausstellung mit
## wandelnden Silhouetten) hinter dem transparenten Showcase-Viewport.
var _schaufenster: IkeaSchaufenster
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
var _swatches: HFlowContainer
var _zoom_slider: HSlider
var _toasts: ToastLayer
var _kategorie := CATEGORY_ALL
var _selected := ""
var _variant := FurnitureVariants.DEFAULT_ID
## FB3: Metrik-Pass (Safe-Area/Touch-Floor/UiScale) bei jedem Resize.
var _rows_box: VBoxContainer
var _back_btn: Button
## G4-Nachfix: Kopfzeilen-Teile für den bedarfsbasierten Umbruch — die
## Wallet-Labels wandern auf schmalen Spalten in die eigene Zeile.
var _header_zeile: HBoxContainer
var _wallet_zeile: HBoxContainer
var _title_label: Label
var _body: BoxContainer
var _left_column: VBoxContainer
## PT2-B6: rechte Spalte = Scroller + Sticky-Kauf-Footer (Kaufen bleibt
## IMMER im Bild, nur die Details darüber scrollen).
var _right_column: VBoxContainer
var _detail_scroll: ScrollContainer
var _detail_panel: PanelContainer
var _kauf_footer: PanelContainer
var _f := 1.0
var _floor := float(AcTokens.TOUCH_FLOOR)


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
	_apply_metrics()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_refresh_chips()
	_refresh_list()
	_refresh_wallet()
	var first := ShopCatalog.filter("", _kategorie)
	if not first.is_empty():
		select_item(str(first[0]["id"]))


func _on_viewport_resized() -> void:
	if not is_inside_tree():
		return
	_apply_metrics()
	_refresh_chips()
	_refresh_list()
	_refresh_swatches()


## FB3: Safe-Area + zentrale Skalierung + Touch-Floor — vorher feste
## 20/14-px-Ränder (Notch), 58er-Zeilen und 40er-Swatches (< 44 pt).
## Inhaltsspalte W16 (G3): der ganze Screen sitzt jetzt in der zentrierten,
## breiten-gedeckelten Spalte (eigene Grid-Basis 880) statt voller Safe-Breite.
func _apply_metrics() -> void:
	if _rows_box == null or not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	_f = m["f"]
	_floor = m["floor_px"]
	var canvas: Vector2 = m["canvas"]
	ScreenShell.content_frame(_rows_box, m, GRID_BASE)
	if _back_btn != null:
		ScreenShell.touch_target(_back_btn, m)
	var portrait := (
		OrientationService.classify(Vector2i(canvas)) == OrientationService.Orientation.PORTRAIT
	)
	_apply_body_layout(portrait, m)
	_search.custom_minimum_size = Vector2(0.0, _floor)
	_chip_scroll.custom_minimum_size = Vector2(0.0, _floor + 8.0)
	_zoom_slider.custom_minimum_size = Vector2(120.0 * _f, _floor)
	_buy_button.custom_minimum_size = Vector2(150.0 * _f, _floor)
	ScreenShell.scale_fonts(self, _f)
	_layout_header(m)
	# Font-Overrides aus scale_fonts propagieren DEFERRED (THEME_CHANGED) —
	# bereits geshapte Labels melden im selben Frame noch ALTE Minbreiten.
	# Ein nachgezogener Pass misst nach dem Flush die echten Werte.
	call_deferred("_layout_header_nachziehen")
	# Vitrine: nimmt den Platz, der NACH dem Detail-Panel übrig bleibt
	# (Höhen-Budget statt fester Mindesthöhe) — reicht er nicht, scrollt
	# die rechte Spalte, statt den Kaufen-Knopf aus dem Canvas zu drücken.
	var insets: Dictionary = m["insets"]
	var body_h := (
		canvas.y - float(insets["top"]) - float(insets["bottom"]) - 28.0 * _f - _floor - 10.0
	)
	if portrait:
		# Im Hochformat-Stapel gehört der Vitrinen-Spalte nur ihr Anteil.
		body_h *= PORTRAIT_DETAIL_SHARE
	# PT2-B6: der Kauf-Footer wohnt AUSSERHALB des Scrollers — er gehört
	# trotzdem ins Höhen-Budget (plus die 8er-Separation der Spalte).
	var detail_h := (
		_detail_panel.get_combined_minimum_size().y
		+ _kauf_footer.get_combined_minimum_size().y
		+ 8.0
	)
	var show_min := clampf(body_h - detail_h - 44.0, 140.0, canvas.y * 0.4)
	_showcase.custom_minimum_size = Vector2(0.0, show_min)


## G4-Nachfix: Kopfzeilen-Falle hoch (G3 §2 #3). Zurück + Titel + Wallet
## verlangten mehr Minbreite (1212 px), als die card_width-Klemme hergibt
## (1136 px auf hoch/f=3) — die Spalte schob nach rechts, SearchField und
## Chip-Leiste liefen aus dem Canvas. Die Wallet-Labels wandern deshalb in
## die eigene Zeile, sobald die Kopfzeile nicht mehr in die Spalte passt.
func _layout_header(m: Dictionary) -> void:
	var sep := float(_header_zeile.get_theme_constant("separation"))
	var noetig := (
		_back_btn.get_combined_minimum_size().x
		+ _title_label.get_combined_minimum_size().x
		+ _coins_label.get_combined_minimum_size().x
		+ _storage_label.get_combined_minimum_size().x
		+ 3.0 * sep
	)
	var unten := noetig > ScreenShell.content_width(m, GRID_BASE)
	if unten != (_coins_label.get_parent() == _wallet_zeile):
		for label: Label in [_coins_label, _storage_label]:
			label.get_parent().remove_child(label)
			(_wallet_zeile if unten else _header_zeile).add_child(label)
	_wallet_zeile.visible = unten


## Deferred-Pass des Kopf-Umbruchs mit FRISCHEN Metriken (s. _apply_metrics).
func _layout_header_nachziehen() -> void:
	if is_inside_tree():
		_layout_header(ScreenShell.metrics(get_viewport()))


## Portrait-Reflow (G3, Scout ui-shop §1): im Hochformat stapelt der Body
## 1-spaltig — Vitrine + Details oben, Suche/Chips/Regalliste darunter;
## im Querformat die gewohnten zwei Spalten (Liste links, Vitrine rechts).
func _apply_body_layout(portrait: bool, m: Dictionary) -> void:
	if _body == null or _right_column == null:
		return
	_body.vertical = portrait
	if portrait:
		if _body.get_child(0) != _right_column:
			_body.move_child(_right_column, 0)
		_left_column.custom_minimum_size = Vector2.ZERO
		_left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_left_column.size_flags_stretch_ratio = 1.0 - PORTRAIT_DETAIL_SHARE
		_right_column.size_flags_stretch_ratio = PORTRAIT_DETAIL_SHARE
		return
	if _body.get_child(0) != _left_column:
		_body.move_child(_left_column, 0)
	var spalte := ScreenShell.content_width(m, GRID_BASE)
	_left_column.custom_minimum_size = Vector2(minf(LIST_WIDTH * _f, spalte * 0.42), 0.0)
	_left_column.size_flags_vertical = Control.SIZE_FILL
	_left_column.size_flags_stretch_ratio = 1.0
	_right_column.size_flags_stretch_ratio = 1.0


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
	_rows_box = VBoxContainer.new()
	_rows_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rows_box.add_theme_constant_override("separation", 10)
	add_child(_rows_box)
	_rows_box.add_child(_build_header())
	# G3: BoxContainer mit vertical-Flag statt fester HBox — der Metrik-Pass
	# schaltet den Body im Hochformat auf 1-spaltiges Stapeln um.
	_body = BoxContainer.new()
	_body.name = "Body"
	_body.vertical = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	_rows_box.add_child(_body)
	_body.add_child(_build_left_column())
	_body.add_child(_build_right_column())
	_toasts = ToastLayer.new()
	add_child(_toasts)


func _build_header() -> Control:
	# G4-Nachfix: Kopf als 2-Zeilen-Gerüst — Zeile 1 wie gehabt, Zeile 2
	# nimmt die Wallet-Labels auf, wenn die Kopfzeile nicht in die Spalte
	# passt (_layout_header; FB3-Befund hoch: Kopf-Minbreite 1212 px drückte
	# die Spalte auf, SearchField/Chips liefen aus dem Canvas).
	var kopf := VBoxContainer.new()
	kopf.add_theme_constant_override("separation", 4)
	_header_zeile = HBoxContainer.new()
	_header_zeile.add_theme_constant_override("separation", 10)
	kopf.add_child(_header_zeile)
	_back_btn = Button.new()
	_back_btn.name = "BackButton"
	_back_btn.theme_type_variation = &"GhostButton"
	_back_btn.text = I18nService.t("shop.ikea.back")
	_back_btn.pressed.connect(_on_back_pressed)
	_header_zeile.add_child(_back_btn)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"TitleLabel"
	_title_label.text = I18nService.t("shop.ikea.title")
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Langer Titel darf den Header nie breiter als den Canvas drücken (Hoch).
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_zeile.add_child(_title_label)
	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.theme_type_variation = &"HeadlineLabel"
	_header_zeile.add_child(_coins_label)
	_storage_label = Label.new()
	_storage_label.name = "StorageLabel"
	_storage_label.theme_type_variation = &"CaptionLabel"
	_header_zeile.add_child(_storage_label)
	_wallet_zeile = HBoxContainer.new()
	_wallet_zeile.name = "WalletZeile"
	_wallet_zeile.add_theme_constant_override("separation", 10)
	_wallet_zeile.alignment = BoxContainer.ALIGNMENT_END
	_wallet_zeile.visible = false
	kopf.add_child(_wallet_zeile)
	return kopf


func _build_left_column() -> Control:
	_left_column = VBoxContainer.new()
	var column := _left_column
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
	# FB3: die Spalte scrollt vertikal — vorher drückte ihre Minimalhöhe
	# (Vitrine + Detail-Panel) in Quer-Formaten den ganzen Body unter den
	# Canvas-Rand (Kaufen-Knopf/Swatches unerreichbar).
	# PT2-B6: die Kaufzeile wohnt jetzt als STICKY-FOOTER unter dem
	# Scroller (Muster HaendlerSheet: Aktion immer im Bild) — am Listenende
	# im Scroller lag sie im Leitformat quer unterm Falz („kein Kaufknopf“).
	_right_column = VBoxContainer.new()
	_right_column.name = "DetailColumn"
	_right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_column.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	_detail_scroll = scroll
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_column.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCardLg"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(card)
	# G7-P55: Ausstellungs-Hintergrund ZUERST einhängen — der Showcase-
	# Viewport ist transparent, die Silhouetten wandern dahinter vorbei.
	_schaufenster = IkeaSchaufenster.new()
	_schaufenster.name = "Schaufenster"
	card.add_child(_schaufenster)
	_showcase = FurnitureShowcase.new()
	_showcase.name = "Showcase"
	_showcase.custom_minimum_size = Vector2(0, SHOWCASE_MIN_HEIGHT)
	_showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(_showcase)
	column.add_child(_build_detail_panel())
	_right_column.add_child(_build_kauf_footer())
	return _right_column


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	_detail_panel = panel
	panel.theme_type_variation = &"AcCard"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	_name_label = Label.new()
	_name_label.name = "ItemName"
	_name_label.theme_type_variation = &"HeadlineLabel"
	# Umbruch statt Mindestbreite: lange Namen dürfen die Detail-Spalte
	# nicht über den Canvas-Rand hinausschieben.
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	return panel


## PT2-B6: Kaufzeile als eigene Karte UNTER dem Scroller — bleibt in jedem
## Format ohne Scrollen sichtbar (der Erst-Eindruck „kein Kaufknopf“ war
## ein Tap ins Leere unterm Falz, Beleg pt2_b1/047).
func _build_kauf_footer() -> Control:
	_kauf_footer = PanelContainer.new()
	_kauf_footer.name = "KaufFooter"
	_kauf_footer.theme_type_variation = &"AcCard"
	_kauf_footer.add_child(_build_buy_row())
	return _kauf_footer


func _build_variant_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionLabel"
	caption.text = I18nService.t("shop.ikea.variants")
	row.add_child(caption)
	# FB3: Swatches umbrechen (HFlow) — im Hochformat drückte die Zeile
	# sonst die ganze Spalte über den rechten Canvas-Rand.
	_swatches = HFlowContainer.new()
	_swatches.name = "Swatches"
	_swatches.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_swatches.add_theme_constant_override("h_separation", 6)
	_swatches.add_theme_constant_override("v_separation", 6)
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
	# HFlow: Preis + Kaufen brechen im Hochformat untereinander um, statt
	# rechts aus dem Canvas zu laufen.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 6)
	# W14: Preis als goldene AC-Pille (Web-Preis-Badge) statt nackter Zahl.
	var pille := PanelContainer.new()
	pille.name = "PricePill"
	pille.add_theme_stylebox_override("panel", _pillen_stylebox())
	pille.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN | Control.SIZE_EXPAND
	pille.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price_label = Label.new()
	_price_label.name = "PriceLabel"
	_price_label.theme_type_variation = &"HeadlineLabel"
	pille.add_child(_price_label)
	row.add_child(pille)
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
	if is_inside_tree():
		ScreenShell.scale_fonts(_chips, _f)
	# Die Chip-Leiste ist breiter als die Spalte — die aktive Kategorie muss
	# sichtbar bleiben, sonst weiß niemand, wonach gerade gefiltert wird.
	_scroll_to_chip.call_deferred(aktiv)


func _make_chip(kategorie: String, text: String) -> Button:
	var chip := Button.new()
	chip.name = "Chip_%s" % (kategorie if kategorie != "" else "alle")
	chip.theme_type_variation = &"ChipLeaf" if kategorie == _kategorie else &"AcChip"
	chip.text = text
	# Floor auf BEIDEN Achsen — kurze Texte („Bad“) unterschreiten sonst
	# die Tippflächen-Breite.
	chip.custom_minimum_size = Vector2(_floor, _floor)
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
	var row_nodes: Array = []
	for item: Dictionary in items:
		var row := _make_row(item)
		_list.add_child(row)
		row_nodes.append(row)
	if is_inside_tree():
		ScreenShell.scale_fonts(_list, _f)
	# FB3-Polish: Regalzeilen blenden gestaffelt ein (Web-Stagger).
	UiMotion.stagger_in(row_nodes, 0.015)


## W14/UISCREENS-B: Regalzeile als AC-Karte — Name links (Ellipse statt
## Layoutbruch: die längste Zeile darf die Spaltenbreite nicht diktieren),
## Preis als goldene Pille rechts (Web-Preis-Badge). Kinder sind
## MOUSE_FILTER_IGNORE, damit die ganze Karte tippbar bleibt.
func _make_row(item: Dictionary) -> Button:
	var id := str(item["id"])
	var row := Button.new()
	row.name = "Row_%s" % id
	row.theme_type_variation = &"AcCardButton"
	row.custom_minimum_size = Vector2(0, maxf(58.0 * _f, _floor))
	row.pressed.connect(_on_row_pressed.bind(id))
	var inner := HBoxContainer.new()
	inner.name = "RowInner"
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 14.0
	inner.offset_right = -12.0
	inner.add_theme_constant_override("separation", 10)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(inner)
	var name_label := Label.new()
	name_label.name = "RowName"
	name_label.text = FurnitureCatalog.display_name(item, I18nService.get_locale())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(name_label)
	inner.add_child(_preis_pille(int(item["preis"])))
	return row


## Goldene Preis-Pille (RADIUS_PILL + Yellow-Rand) — EIN Look für Regal-
## Zeilen und Kaufen-Zeile.
func _preis_pille(betrag: int) -> PanelContainer:
	var pille := PanelContainer.new()
	pille.name = "PreisPille"
	pille.add_theme_stylebox_override("panel", _pillen_stylebox())
	pille.size_flags_horizontal = Control.SIZE_SHRINK_END
	pille.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pille.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := Label.new()
	text.name = "PreisText"
	text.theme_type_variation = &"CaptionLabel"
	text.text = I18nService.t("shop.ikea.preis", {"n": betrag})
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pille.add_child(text)
	return pille


static func _pillen_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = AcTokens.PAPER.lerp(AcTokens.YELLOW, 0.35)
	box.set_corner_radius_all(AcTokens.RADIUS_PILL)
	box.set_border_width_all(1)
	box.border_color = Color(AcTokens.YELLOW_DARK, 0.6)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


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
	# FB3: Swatches halten den PHYSISCHEN Touch-Floor (waren 40 Design-px).
	swatch.custom_minimum_size = Vector2.ONE * maxf(SWATCH_SIZE * _f, _floor)
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
	# G4-Nachfix: neue Texte = neue Minbreiten — Kopf-Umbruch nachziehen
	# (sofort + deferred, s. _apply_metrics zu den Font-Overrides).
	if is_inside_tree():
		_layout_header(ScreenShell.metrics(get_viewport()))
		call_deferred("_layout_header_nachziehen")


func _kategorie_label(kategorie: String) -> String:
	var key := "shop.kategorie.%s" % kategorie
	return I18nService.t(key) if I18nService.has_key(key) else kategorie


func _show_result(item: Dictionary, result: String) -> void:
	var name_text := FurnitureCatalog.display_name(item, I18nService.get_locale())
	match result:
		ShopPurchase.RESULT_OK:
			# Sound-Fixliste F3: Kauf-Erfolg klingt wie Kauf (Audio-Grammatik).
			AudioDirector.try_play(self, "ui_buy")
			_toasts.show_toast(I18nService.t("shop.ikea.gekauft", {"name": name_text}))
			# W14 Kauf-Feier (UIKERN-Vertrag): Doppelimpuls + Gold-Funken.
			Haptics.success(self)
			UiMotion.sparkle(_buy_button)
			UiMotion.bounce(_coins_label)
		ShopPurchase.RESULT_BROKE:
			Haptics.warn(self)
			_toasts.show_toast(I18nService.t("shop.ikea.zu_teuer"), true)
		ShopPurchase.RESULT_FULL:
			Haptics.warn(self)
			_toasts.show_toast(I18nService.t("shop.ikea.lager_voll"), true)
		_:
			Haptics.warn(self)
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
