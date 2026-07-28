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
##
## FIX1 (P0 „UI ist meist falsch skaliert“): Chrome, Rail, Chips und
## Kacheln skalieren über die zentrale Regel `UiScale.for_viewport()` und
## respektieren die Safe-Area — vorher waren alle Größen feste Design-px
## (Rail 240, Kacheln 190×200) und auf Retina-Geräten winzig.

signal ready_for_reveal

const Economy := preload("res://scripts/logic/economy.gd")

const ICON_DIR := "res://assets/ui/icons/"
const ROUTE_ALBUM := &"album"
const ROUTES := {ROUTE_ALBUM: "res://scripts/ui/album/album_screen.tscn"}
const RARITY_BORDER := {
	"haeufig": Color("#FFFFFF"),
	"selten": Color("#C7CBD6"),
	"episch": Color("#FFD34D"),
	"geheim": Color("#C9A6E8"),
}
## Set-komplett-Belohnung (BACKLOG-REST §4): Münzen je vervollständigter
## Seite, einmalig — Claim persistiert in stickers.setRewards[page_id].
const SET_REWARD_COINS := 120

## Tests: Navigation abschaltbar.
var auto_navigate := true
## Tests: GameState + Katalog/Seiten injizierbar (sonst Autoload/Registry).
var gs_override: Object = null
var catalog_override: Array = []
var pages_override: Array = []

var _gs: Object = null
var _catalog: Array = []
var _pages: Array = []
var _by_page: Dictionary = {}
var _current_page := ""
var _grid: GridContainer
var _page_title: Label
var _page_progress: Label
var _count_label: Label
var _rail_box: VBoxContainer
var _toasts: ToastLayer
var _sheet: PanelSheet
var _unlocks: StickerUnlocks
## FIX1: aktueller UI-Faktor + daraus abgeleitete Kachelgröße (Canvas-px).
var _f := 1.0
var _tile := Vector2(190, 200)
var _rows_box: VBoxContainer
var _rail_scroll: ScrollContainer
var _back_btn: Button
var _title_label: Label


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
	_gs = gs_override if gs_override != null else get_node_or_null("/root/GameState")
	_catalog = catalog_override if not catalog_override.is_empty() else StickerCatalog.all()
	_pages = pages_override if not pages_override.is_empty() else StickerCatalog.pages()
	_by_page = StickerCatalog.by_page(_catalog)
	if not _pages.is_empty():
		_current_page = str(_pages[0].get("id", ""))
	_build_ui()
	_apply_metrics()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_show_page(_current_page)
	_attach_unlock_service()
	ready_for_reveal.emit()


func _on_viewport_resized() -> void:
	if not is_inside_tree():
		return
	_apply_metrics()
	_show_page(_current_page)


## FIX1: zentrale Skalierung + Safe-Area auf Chrome/Rail/Kacheln anwenden
## (bei Rotation/Resize erneut — Kacheln baut _show_page danach neu).
func _apply_metrics() -> void:
	_f = UiScale.for_viewport(get_viewport())
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	_rows_box.offset_left = 24.0 + float(insets["left"])
	_rows_box.offset_right = -24.0 - float(insets["right"])
	_rows_box.offset_top = 16.0 + float(insets["top"])
	_rows_box.offset_bottom = -16.0 - float(insets["bottom"])
	# FB3: voller PHYSISCHER Touch-Floor (Retina-Faktor) — die alte
	# Canvas-Heuristik ×0.85 ließ die Seiten-Chips auf 40 pt schrumpfen.
	var floor_px := maxf(
		HudLayoutLogic.touch_floor_canvas(canvas),
		float(AcTokens.TOUCH_FLOOR) * UiScale.touch_px_per_pt(get_viewport())
	)
	_back_btn.custom_minimum_size = Vector2(0.0, maxf(44.0 * _f, floor_px))
	_scale_font(_back_btn, 17)
	_scale_font(_title_label, AcTokens.FONT_SIZE_TITLE)
	_scale_font(_count_label, AcTokens.FONT_SIZE_CAPTION)
	_scale_font(_page_title, 24)
	# Rail wächst mit, bleibt aber unter ~1/3 der Breite (Hochkant).
	_rail_scroll.custom_minimum_size = Vector2(minf(240.0 * _f, canvas.x * 0.32), 0.0)
	for chip in _rail_box.get_children():
		if chip is Control:
			(chip as Control).custom_minimum_size = Vector2(0.0, maxf(40.0 * _f, floor_px))
			_scale_font(chip as Control, AcTokens.FONT_SIZE_CAPTION)
	# Kacheln: Restbreite auf 2..4 Spalten aufteilen (Seitenverhältnis wie
	# die alte 190×200-Kachel).
	var avail := (
		canvas.x
		- (24.0 + float(insets["left"]))
		- (24.0 + float(insets["right"]))
		- _rail_scroll.custom_minimum_size.x
		- 14.0
	)
	var cols := clampi(int(floorf((avail + 14.0) / (190.0 * _f + 14.0))), 2, 4)
	_grid.columns = cols
	var tile_w := (avail - 14.0 * float(cols - 1)) / float(cols)
	_tile = Vector2(tile_w, tile_w * 200.0 / 190.0)


## Font nur bei echtem Faktor überschreiben — bei 1.0 bleibt das Theme.
func _scale_font(ctl: Control, base_px: int) -> void:
	if _f > 1.0:
		ctl.add_theme_font_size_override("font_size", int(base_px * _f))
	else:
		ctl.remove_theme_font_size_override("font_size")


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
	_rows_box = rows
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
	# UIFINAL: Kopfzeilen-Konsistenz — Zurück ist überall die Ghost-Outline-
	# Pill mit ‹-Pfeil (wie Arcade/Freunde/Profil), nicht die weiße Paper-Pill.
	var back := SquishButton.new()
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("album.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	_back_btn = back
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("album.titel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	_title_label = title
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
	_rail_scroll = scroll
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
	chip.text = _chip_text(page)
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.focus_mode = Control.FOCUS_NONE
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon_path := "%s%s.svg" % [ICON_DIR, str(page.get("icon", "star"))]
	if ResourceLoader.exists(icon_path):
		chip.icon = load(icon_path)
	chip.self_modulate = Color(str(page.get("tint", "#FFFFFF")))
	chip.pressed.connect(_show_page.bind(page_id))
	return chip


## Chip-Text mit Set-Fortschritt (n/N) + NEU-Hinweis für ungesehene
## freigeschaltete Sticker der Seite (BACKLOG-REST §4).
func _chip_text(page: Dictionary) -> String:
	var page_id := str(page.get("id", ""))
	var title := str(page.get("title_de", page_id))
	if _gs == null:
		return title
	var progress := StickerUnlocks.page_progress(_gs.state(), _catalog, page_id)
	var text := "%s  %d/%d" % [title, int(progress["unlocked"]), int(progress["total"])]
	if _unseen_on_page(page_id) > 0:
		text += "  %s" % I18nService.t("album.neu")
	return text


## Rail-Chips (Fortschritt/NEU) nach Unlocks oder Ansehen aktualisieren.
func _refresh_rail() -> void:
	if _rail_box == null:
		return
	for page: Dictionary in _pages:
		var chip := _rail_box.get_node_or_null("PageChip_%s" % str(page.get("id", "")))
		if chip is Button:
			(chip as Button).text = _chip_text(page)


## Anzahl freigeschalteter, aber noch nie angetippter Sticker der Seite.
func _unseen_on_page(page_id: String) -> int:
	if _gs == null:
		return 0
	var seen: Variant = _gs.get_value("stickers.seen", {})
	var seen_map: Dictionary = seen if seen is Dictionary else {}
	var count := 0
	for def: Dictionary in _by_page.get(page_id, []):
		var id := str(def.get("id", ""))
		if _is_unlocked(id) and not seen_map.has(id):
			count += 1
	return count


func _build_page_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)
	_page_title = Label.new()
	_page_title.theme_type_variation = &"HeadlineLabel"
	panel.add_child(_page_title)
	_page_progress = Label.new()
	_page_progress.theme_type_variation = &"SoftLabel"
	panel.add_child(_page_progress)
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
	_refresh_page_progress(page_id)
	if _grid == null:
		return
	for child in _grid.get_children():
		# remove_child VOR queue_free: sonst kollidieren die Namen der neuen
		# Karten mit den noch nicht freigegebenen alten (Auto-Rename).
		_grid.remove_child(child)
		child.queue_free()
	for def: Dictionary in _by_page.get(page_id, []):
		_grid.add_child(_build_sticker_card(def))


## Set-Fortschritt unter dem Seitentitel ("n von N gefunden" + Belohnungs-
## Status der Seite).
func _refresh_page_progress(page_id: String) -> void:
	if _page_progress == null or _gs == null:
		return
	var progress := StickerUnlocks.page_progress(_gs.state(), _catalog, page_id)
	var text := I18nService.t(
		"album.set_fortschritt", {"n": int(progress["unlocked"]), "total": int(progress["total"])}
	)
	if _set_reward_claimed(page_id):
		text += "  %s" % I18nService.t("album.set_komplett")
	_page_progress.text = text


func _build_sticker_card(def: Dictionary) -> Control:
	var id := str(def.get("id", ""))
	var unlocked := _is_unlocked(id)
	var tint := Color(str(_page_def(str(def.get("page", ""))).get("tint", "#FFFFFF")))
	var card := SquishButton.new()
	card.name = "Sticker_%s" % id
	card.theme_type_variation = &"AcCard"
	# FIX1: Kachelgröße kommt aus _apply_metrics (skaliert + responsiv).
	card.custom_minimum_size = _tile
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(_on_sticker_tapped.bind(def))
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	card.add_child(content)
	content.add_child(_build_card_art(def, unlocked, tint))
	content.add_child(_build_name_band(def, unlocked))
	if unlocked and not _is_seen(id):
		card.add_child(_build_new_badge())
	return card


## „NEU“-Marker (BACKLOG-REST §4): kleine Kapsel oben rechts auf frisch
## freigeschalteten, noch nie angetippten Stickern.
func _build_new_badge() -> Control:
	var badge := PanelContainer.new()
	badge.name = "NewBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = AcTokens.PINK
	style.set_corner_radius_all(AcTokens.RADIUS_ROW)
	style.set_content_margin_all(4.0)
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = I18nService.t("album.neu")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", AcTokens.WHITE)
	_scale_font(label, 12)
	badge.add_child(label)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -52.0 * _f
	badge.offset_top = 6.0
	badge.offset_right = -6.0
	return badge


func _build_card_art(def: Dictionary, unlocked: bool, tint: Color) -> Control:
	var frame := Control.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unlocked:
		var art := _art_rect(str(def.get("image", "")))
		if art != null:
			frame.add_child(art)
			return frame
	# Mystery-Slot (H §3.4 + BACKLOG-REST §3): Seiten-Tint + generische
	# Hasen-Silhouette + großes Fragezeichen — NIE das Motiv des Stickers
	# leaken (kein Graufilter über der echten Grafik).
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
	silhouette.self_modulate = Color(AcTokens.INK, 0.18)
	silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(silhouette)
	var mark := Label.new()
	mark.name = "MysteryMark"
	mark.text = "?"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.add_theme_color_override("font_color", Color(AcTokens.INK, 0.55))
	mark.add_theme_font_size_override("font_size", int(56 * maxf(_f, 1.0)))
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(mark)
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
	_scale_font(label, AcTokens.FONT_SIZE_CAPTION)
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
			art.custom_minimum_size = Vector2(0, 220.0 * _f)
			body.add_child(art)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scale_font(text, 16)
	if unlocked:
		text.text = str(def.get("flavor_de", ""))
	else:
		text.text = "%s\n%s" % [I18nService.t("album.hint_label"), str(def.get("hint_de", ""))]
	body.add_child(text)
	if not unlocked and not bool(def.get("secret", false)):
		# Tausch-Hinweis (BACKLOG-REST §4): Freunde-Vergleich als Sammel-Tipp.
		var hint := Label.new()
		hint.text = I18nService.t("album.tausch_hinweis")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color(AcTokens.INK, 0.6))
		_scale_font(hint, 14)
		body.add_child(hint)
	_sheet.set_title(str(def.get("name_de", "")) if unlocked else I18nService.t("album.unbekannt"))
	_sheet.add_content(body)
	_sheet.open()
	if unlocked and not _is_seen(id):
		_mark_seen(id)
		_show_page(_current_page)
		_refresh_rail()


## EF-1/EVAL-1 D2: läuft der globale RewardHub, feiert ER (Toast+Ton+
## Konfetti auf der obersten Layer) — das Album hängt sich nur für den
## Grid-Refresh an dessen Auswertung (keine Doppel-Feier, kein zweiter
## Service). Ohne Hub (Tests/Alt-Aufrufer) bleibt der eigene Pfad erhalten.
func _attach_unlock_service() -> void:
	var hub := RewardHub.find(self)
	if hub != null and hub.unlocks != null and gs_override == null:
		hub.unlocks.sticker_unlocked.connect(_on_hub_sticker_unlocked)
		return
	_unlocks = StickerUnlocks.new()
	add_child(_unlocks)
	_unlocks.sticker_unlocked.connect(_on_sticker_unlocked)
	if _gs != null:
		_unlocks.attach(_gs, _catalog)


## Refresh-only-Pfad bei aktivem RewardHub: Anzeige aktualisieren, Feier
## und Set-Belohnung kommen vom Hub.
func _on_hub_sticker_unlocked(def: Dictionary) -> void:
	_refresh_count()
	_refresh_rail()
	if str(def.get("page", "")) == _current_page:
		_show_page(_current_page)
	_refresh_page_progress(_current_page)


func _on_sticker_unlocked(def: Dictionary) -> void:
	_toasts.show_toast(I18nService.t("album.unlock_toast", {"name": str(def.get("name_de", ""))}))
	_confetti_burst()
	_refresh_count()
	_refresh_rail()
	if str(def.get("page", "")) == _current_page:
		_show_page(_current_page)
	_maybe_claim_set_reward(str(def.get("page", "")))


## Set-komplett-Belohnung: Seite voll → einmalig Münzen + Toast + Konfetti.
## Claim persistiert ADDITIV in stickers.setRewards[page_id] (kein Bump).
func _maybe_claim_set_reward(page_id: String) -> void:
	if _gs == null or page_id.is_empty() or _set_reward_claimed(page_id):
		return
	var progress := StickerUnlocks.page_progress(_gs.state(), _catalog, page_id)
	if int(progress["total"]) <= 0 or int(progress["unlocked"]) < int(progress["total"]):
		return
	_gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("stickers") is Dictionary):
				state["stickers"] = {"unlocked": {}, "seen": {}}
			var stickers: Dictionary = state["stickers"]
			if not (stickers.get("setRewards") is Dictionary):
				stickers["setRewards"] = {}
			stickers["setRewards"][page_id] = _now_ms()
			if state.get("economy") is Dictionary:
				Economy.award(state["economy"], SET_REWARD_COINS, "stickerSet")
	)
	_gs.notify_slice_changed("stickers")
	var title := str(_page_def(page_id).get("title_de", page_id))
	_toasts.show_toast(
		I18nService.t("album.set_belohnung", {"title": title, "coins": SET_REWARD_COINS})
	)
	_confetti_burst()
	_refresh_page_progress(_current_page)


func _set_reward_claimed(page_id: String) -> bool:
	if _gs == null:
		return false
	var rewards: Variant = _gs.get_value("stickers.setRewards", {})
	return rewards is Dictionary and (rewards as Dictionary).has(page_id)


func _now_ms() -> int:
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


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


func _is_seen(id: String) -> bool:
	if _gs == null:
		return false
	var seen: Variant = _gs.get_value("stickers.seen", {})
	return seen is Dictionary and (seen as Dictionary).has(id)


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
	# FIX1: EIN gemeinsamer Zurück-Pfad (Router-History/Panel-Stack), sonst
	# der &"home"-Alias — vorher war &"home" NIE registriert und der Knopf
	# tat still nichts.
	if router.has_method("handle_back_request") and router.handle_back_request():
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
