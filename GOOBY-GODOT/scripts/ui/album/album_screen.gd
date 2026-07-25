class_name AlbumScreen
extends Control
## Sticker-Album (W3d CONTENT, Doc H §3): AC-Theme-Screen mit Drift-Wallpaper
## (W1c AcWallpaper), Seiten-Rail links (Legacy-Seiten + Garten/Stadt/GvZ),
## 2×3-Sticker-Grid, Mystery-Locked-Slots (generische Silhouette + „???“ —
## nie das Motiv, H §3.4), Detail-Sheet (W1c PanelSheet) und Unlock-Toast +
## Konfetti über den signal-basierten StickerUnlocks-Service.
##
## HUD-Verdrahtung (W1c-API): der Home-Besitzer verbindet
##   hud.action_pressed.connect(AlbumScreen.handle_hud_action)
## — Request an W2a: /tmp/gooby-godot/handoffs/W3d-home-requests.md.

signal ready_for_reveal

const ICON_DIR := "res://assets/ui/icons/"
const ROUTE_ALBUM := &"album"
const ROUTES := {ROUTE_ALBUM: "res://scripts/ui/album/album_screen.tscn"}
const RARITY_BORDER := {
	"haeufig": Color("#FFFFFF"),
	"selten": Color("#C7CBD6"),
	"episch": Color("#FFD34D"),
	"geheim": Color("#C9A6E8"),
}

## Tests: Navigation abschaltbar.
var auto_navigate := true

var _gs: Object = null
var _catalog: Array = []
var _pages: Array = []
var _by_page: Dictionary = {}
var _current_page := ""
var _grid: GridContainer
var _page_title: Label
var _count_label: Label
var _rail_box: VBoxContainer
var _toasts: ToastLayer
var _sheet: PanelSheet
var _unlocks: StickerUnlocks


## Album-Route am SceneRouter anmelden (idempotent).
static func register_routes() -> void:
	var router := _router()
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


## EIN Verdrahtungspunkt für den HUD-Album-Button (W1c action_pressed).
## Liefert true, wenn die Action konsumiert wurde.
static func handle_hud_action(action: StringName) -> bool:
	if action != &"album":
		return false
	register_routes()
	var router := _router()
	if router == null or not router.has_method("goto"):
		return false
	router.goto(ROUTE_ALBUM, {})
	return true


func _ready() -> void:
	# Und NICHT set_anchors_preset: das würde den (noch leeren) Ist-Rect via
	# Offsets konservieren, wenn der Parent schon Größe hat → 0×0-Screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_gs = get_node_or_null("/root/GameState")
	_catalog = StickerCatalog.all()
	_pages = StickerCatalog.pages()
	_by_page = StickerCatalog.by_page(_catalog)
	if not _pages.is_empty():
		_current_page = str(_pages[0].get("id", ""))
	_build_ui()
	_show_page(_current_page)
	_attach_unlock_service()
	ready_for_reveal.emit()


## Seite hart anwählen (Screenshots/Tests).
func show_page(page_id: String) -> void:
	_show_page(page_id)


func unlocked_count() -> int:
	if _gs == null:
		return 0
	return StickerUnlocks.unlocked_count(_gs.state(), _catalog)


func _build_ui() -> void:
	var wallpaper := AcWallpaper.new()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)

	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 24.0
	rows.offset_right = -24.0
	rows.offset_top = 16.0
	rows.offset_bottom = -16.0
	rows.add_theme_constant_override("separation", 12)
	add_child(rows)
	rows.add_child(_build_header())

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	rows.add_child(split)
	split.add_child(_build_rail())
	split.add_child(_build_page_panel())

	_toasts = ToastLayer.new()
	add_child(_toasts)
	# ToastLayer._ready konserviert seinen 0-Rect (Parent hat hier schon
	# Größe) — Offsets explizit auf Full-Rect zurücksetzen.
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
	add_child(_sheet)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var back := SquishButton.new()
	back.theme_type_variation = &"BtnGhost"
	back.text = I18nService.t("album.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("album.titel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var count_chip := PanelContainer.new()
	count_chip.theme_type_variation = &"StatusCapsule"
	_count_label = Label.new()
	_count_label.theme_type_variation = &"SoftLabel"
	count_chip.add_child(_count_label)
	header.add_child(count_chip)
	_refresh_count()
	return header


func _build_rail() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(240, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rail_box = VBoxContainer.new()
	_rail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rail_box)
	for page: Dictionary in _pages:
		_rail_box.add_child(_build_page_chip(page))
	return scroll


func _build_page_chip(page: Dictionary) -> Control:
	var page_id := str(page.get("id", ""))
	var chip := SquishButton.new()
	chip.name = "PageChip_%s" % page_id
	chip.theme_type_variation = &"AcChip"
	chip.text = str(page.get("title_de", page_id))
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.focus_mode = Control.FOCUS_NONE
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon_path := "%s%s.svg" % [ICON_DIR, str(page.get("icon", "star"))]
	if ResourceLoader.exists(icon_path):
		chip.icon = load(icon_path)
	chip.self_modulate = Color(str(page.get("tint", "#FFFFFF")))
	chip.pressed.connect(_show_page.bind(page_id))
	return chip


func _build_page_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)
	_page_title = Label.new()
	_page_title.theme_type_variation = &"HeadlineLabel"
	panel.add_child(_page_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	return panel


func _show_page(page_id: String) -> void:
	_current_page = page_id
	var page := _page_def(page_id)
	if _page_title != null:
		_page_title.text = str(page.get("title_de", page_id))
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	for def: Dictionary in _by_page.get(page_id, []):
		_grid.add_child(_build_sticker_card(def))


func _build_sticker_card(def: Dictionary) -> Control:
	var id := str(def.get("id", ""))
	var unlocked := _is_unlocked(id)
	var tint := Color(str(_page_def(str(def.get("page", ""))).get("tint", "#FFFFFF")))
	var card := SquishButton.new()
	card.name = "Sticker_%s" % id
	card.theme_type_variation = &"AcCard"
	card.custom_minimum_size = Vector2(190, 200)
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(_on_sticker_tapped.bind(def))
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	card.add_child(content)
	content.add_child(_build_card_art(def, unlocked, tint))
	content.add_child(_build_name_band(def, unlocked))
	return card


func _build_card_art(def: Dictionary, unlocked: bool, tint: Color) -> Control:
	var frame := Control.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unlocked:
		var art := _art_rect(str(def.get("image", "")))
		if art != null:
			frame.add_child(art)
			return frame
	# Mystery-Slot (H §3.4): Seiten-Tint + generische Silhouette — NIE das
	# Motiv des Stickers leaken.
	var veil := ColorRect.new()
	veil.color = Color(tint, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(veil)
	var silhouette := TextureRect.new()
	silhouette.texture = load(ICON_DIR + "rabbit.svg")
	silhouette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	silhouette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	silhouette.set_anchors_preset(Control.PRESET_FULL_RECT)
	silhouette.self_modulate = Color(AcTokens.INK, 0.28)
	silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(silhouette)
	return frame


func _build_name_band(def: Dictionary, unlocked: bool) -> Control:
	var band := PanelContainer.new()
	band.theme_type_variation = &"StatusCapsule"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = AcTokens.PAPER
	band_style.set_corner_radius_all(AcTokens.RADIUS_ROW)
	band_style.border_color = RARITY_BORDER.get(str(def.get("rarity", "haeufig")), AcTokens.WHITE)
	band_style.set_border_width_all(3)
	band_style.set_content_margin_all(6.0)
	band.add_theme_stylebox_override("panel", band_style)
	var label := Label.new()
	label.text = str(def.get("name_de", "")) if unlocked else I18nService.t("album.unbekannt")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(label)
	return band


func _on_sticker_tapped(def: Dictionary) -> void:
	var id := str(def.get("id", ""))
	var unlocked := _is_unlocked(id)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	if unlocked:
		var art := _art_rect(str(def.get("image", "")))
		if art != null:
			art.custom_minimum_size = Vector2(0, 220)
			body.add_child(art)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if unlocked:
		text.text = str(def.get("flavor_de", ""))
	else:
		text.text = "%s\n%s" % [I18nService.t("album.hint_label"), str(def.get("hint_de", ""))]
	body.add_child(text)
	_sheet.set_title(str(def.get("name_de", "")) if unlocked else I18nService.t("album.unbekannt"))
	_sheet.add_content(body)
	_sheet.open()
	_mark_seen(id)


func _attach_unlock_service() -> void:
	_unlocks = StickerUnlocks.new()
	add_child(_unlocks)
	_unlocks.sticker_unlocked.connect(_on_sticker_unlocked)
	if _gs != null:
		_unlocks.attach(_gs, _catalog)


func _on_sticker_unlocked(def: Dictionary) -> void:
	_toasts.show_toast(I18nService.t("album.unlock_toast", {"name": str(def.get("name_de", ""))}))
	_confetti_burst()
	_refresh_count()
	if str(def.get("page", "")) == _current_page:
		_show_page(_current_page)


## Konfetti-Burst (eigene Partikel — JuiceKit hat kein Konfetti; float_text
## & Co. bleiben Minigame-Hosts vorbehalten).
func _confetti_burst() -> void:
	if ThemeService.is_reduced_motion(self):
		return
	var particles := CPUParticles2D.new()
	particles.position = size / 2.0
	particles.amount = 48
	particles.lifetime = 1.2
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.direction = Vector2(0, -1)
	particles.spread = 70.0
	particles.initial_velocity_min = 260.0
	particles.initial_velocity_max = 520.0
	particles.gravity = Vector2(0, 700)
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 7.0
	particles.color_ramp = _confetti_gradient()
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.6).timeout.connect(particles.queue_free)


func _refresh_count() -> void:
	if _count_label == null:
		return
	var total := StickerCatalog.regular_count(_catalog)
	_count_label.text = I18nService.t("album.zaehler", {"n": unlocked_count(), "total": total})


func _mark_seen(id: String) -> void:
	if _gs == null:
		return
	_gs.update(
		func(state: Dictionary) -> void:
			if state.get("stickers") is Dictionary:
				var stickers: Dictionary = state["stickers"]
				if not (stickers.get("seen") is Dictionary):
					stickers["seen"] = {}
				stickers["seen"][id] = true
	)


func _is_unlocked(id: String) -> bool:
	return _gs != null and StickerUnlocks.is_unlocked(_gs.state(), id)


func _page_def(page_id: String) -> Dictionary:
	for page: Dictionary in _pages:
		if str(page.get("id", "")) == page_id:
			return page
	return {}


func _art_rect(image_path: String) -> TextureRect:
	if not ResourceLoader.exists(image_path):
		return null
	var rect := TextureRect.new()
	rect.texture = load(image_path)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Anchors VOR dem Einhängen: im plain-Control-Frame der Karte füllt die
	# Art sonst nie den Rahmen (Container überschreiben Anchors ohnehin).
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _on_back_pressed() -> void:
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})


static func _confetti_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(
		[AcTokens.PINK, AcTokens.YELLOW, AcTokens.TEAL, AcTokens.LEAF]
	)
	gradient.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	return gradient


static func _router() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
