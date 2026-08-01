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
##
## W16/G3 (Inhaltsspalte, Album-Sonderfall — Entscheid): das Rail+Seiten-
## Layout bekommt eine EIGENE Spalten-Basis 880 (`content_frame`), weil die
## 660er-Listen-Spalte für Rail + Grid zu schmal wäre; im HOCHFORMAT wird
## die Rail zur horizontalen Top-Chip-Leiste ÜBER dem Grid (vorher fraß die
## linke Rail 32 % der Breite und ließ nur 2 Mini-Spalten übrig).

signal ready_for_reveal

const Economy := preload("res://scripts/logic/economy.gd")

const ICON_DIR := "res://assets/ui/icons/"
const ROUTE_ALBUM := &"album"
const ROUTES := {ROUTE_ALBUM: "res://scripts/ui/album/album_screen.tscn"}
## W13/SAMMLUNG: Pseudo-Seiten-ID des Sammlungs-Bereichs (4 Web-Sets mit
## Claim-Belohnung, CollectionsView) — hängt als eigener Chip in der Rail.
const COLLECTIONS_PAGE := "__sammlungen__"
const RARITY_BORDER := {
	"haeufig": Color("#FFFFFF"),
	"selten": Color("#C7CBD6"),
	"episch": Color("#FFD34D"),
	"geheim": Color("#C9A6E8"),
}
## Set-komplett-Belohnung (BACKLOG-REST §4): Münzen je vervollständigter
## Seite, einmalig — Claim persistiert in stickers.setRewards[page_id].
const SET_REWARD_COINS := 120
## W16/G3: eigene Spalten-Basis des Albums (Rail+Grid brauchen mehr Luft
## als die 660er-Listen-Spalte — Entwurf ui-architektur §6.4 Welle 3).
const SPALTE_BASIS := 880.0

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
## W14: Icon-Glyph im Seiten-Header (ACNH-Abschnitts-Header-Muster).
var _page_icon: TextureRect
var _page_progress: Label
var _count_label: Label
var _rail_box: BoxContainer
var _toasts: ToastLayer
var _sheet: PanelSheet
var _unlocks: StickerUnlocks
## FIX1: aktueller UI-Faktor + daraus abgeleitete Kachelgröße (Canvas-px).
var _f := 1.0
var _tile := Vector2(190, 200)
var _rows_box: VBoxContainer
## W16/G3: Rail/Panel-Teiler — quer nebeneinander, hochkant gestapelt.
var _split: BoxContainer
var _rail_scroll: ScrollContainer
var _back_btn: Button
var _title_label: Label
## W13/SAMMLUNG: Grid-Scroller + lazily gebaute Sammlungs-View der
## Pseudo-Seite (Sichtbarkeit wird in _show_page umgeschaltet).
var _grid_scroll: ScrollContainer
var _collections_view: CollectionsView


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
	_show_page(_current_page, true)
	_attach_unlock_service()
	ready_for_reveal.emit()


func _on_viewport_resized() -> void:
	if not is_inside_tree():
		return
	_apply_metrics()
	_show_page(_current_page)


## W16/G3 (pur, testbar): Hochformat = kurze Kante ist die Breite.
static func ist_hochformat(canvas: Vector2) -> bool:
	return canvas.y > canvas.x


## FIX1: zentrale Skalierung + Safe-Area auf Chrome/Rail/Kacheln anwenden
## (bei Rotation/Resize erneut — Kacheln baut _show_page danach neu).
## W16/G3: `_rows_box` liegt jetzt in der zentrierten Inhaltsspalte
## (eigene Basis 880, Meta-Flag fürs FB3-Audit); die Rail wechselt je
## Orientierung zwischen linker Spalte (quer) und Top-Chip-Leiste (hoch).
func _apply_metrics() -> void:
	var m := ScreenShell.metrics(get_viewport())
	_f = m["f"]
	var floor_px: float = m["floor_px"]
	ScreenShell.content_frame(_rows_box, m, SPALTE_BASIS)
	_back_btn.custom_minimum_size = Vector2(0.0, maxf(44.0 * _f, floor_px))
	_scale_font(_back_btn, 17)
	_scale_font(_title_label, AcTokens.FONT_SIZE_TITLE)
	_scale_font(_count_label, AcTokens.FONT_SIZE_CAPTION)
	_scale_font(_page_title, 24)
	if _page_icon != null:
		_page_icon.custom_minimum_size = Vector2.ONE * roundf(24.0 * maxf(_f, 1.0))
	var hoch := ist_hochformat(m["canvas"])
	var spalte := ScreenShell.content_width(m, SPALTE_BASIS)
	_layout_rail(hoch, spalte, floor_px)
	# Kacheln: Restbreite auf 2..4 Spalten aufteilen (Seitenverhältnis wie
	# die alte 190×200-Kachel). W14: Lücken aufs 8er-Raster (16 statt 14) —
	# MUSS zur split-/Grid-Separation in _build_ui/_build_page_panel passen.
	var avail := spalte
	if not hoch:
		avail -= _rail_scroll.custom_minimum_size.x + 16.0
	var cols := clampi(int(floorf((avail + 16.0) / (190.0 * _f + 16.0))), 2, 4)
	_grid.columns = cols
	var tile_w := (avail - 16.0 * float(cols - 1)) / float(cols)
	_tile = Vector2(tile_w, tile_w * 200.0 / 190.0)
	# W13/SAMMLUNG: Layout-Kenngrößen an die Sammlungs-View weiterreichen
	# (FIX1 + W16: reale Panelbreite für die responsive Slot-Spaltenzahl).
	if _collections_view != null:
		_collections_view.apply_layout(_f, avail, floor_px)


## W16/G3: Rail-Ausrichtung je Orientierung. Hochformat: horizontale
## Chip-Leiste über dem Grid (Chips in natürlicher Breite, Leiste scrollt
## seitwärts, Balken versteckt — Zentrier-Diebstahl-Regel aus G2/SPALTE);
## Querformat: vertikale Spalte, Chips füllen die Rail-Breite und ellipsen
## (W14-P0-Regel gegen die Mindestbreiten-Blähung).
func _layout_rail(hoch: bool, spalte: float, floor_px: float) -> void:
	_split.vertical = hoch
	_rail_box.vertical = not hoch
	if hoch:
		_rail_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_rail_scroll.custom_minimum_size = Vector2.ZERO
		_rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_rail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		_rail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# Rail wächst mit, bleibt aber unter ~1/3 der Spaltenbreite.
		_rail_scroll.custom_minimum_size = Vector2(minf(240.0 * _f, spalte * 0.32), 0.0)
		_rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_rail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	for chip in _rail_box.get_children():
		if chip is Button:
			_layout_chip(chip as Button, hoch, floor_px)


## FB3: voller PHYSISCHER Touch-Floor je Chip (Retina-Faktor) — die alte
## Canvas-Heuristik ×0.85 ließ die Seiten-Chips auf 40 pt schrumpfen.
func _layout_chip(chip: Button, hoch: bool, floor_px: float) -> void:
	chip.custom_minimum_size = Vector2(0.0, maxf(40.0 * _f, floor_px))
	_scale_font(chip, AcTokens.FONT_SIZE_CAPTION)
	if hoch:
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		chip.clip_text = false
		chip.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	else:
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_clamp_chip_text(chip)


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
	# W14: Album-Stimmung (Web-V6 „album“) statt Standard-Blätter.
	add_child(AcWallpaper.for_context("album"))

	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 24.0
	rows.offset_right = -24.0
	rows.offset_top = 16.0
	rows.offset_bottom = -16.0
	# W14: 8er-Raster (12 war rasterfremd).
	rows.add_theme_constant_override("separation", 16)
	add_child(rows)
	_rows_box = rows
	rows.add_child(_build_header())

	# W16/G3: BoxContainer statt HBox — _layout_rail kippt ihn im
	# Hochformat auf vertikal (Rail-Leiste oben, Seiten-Panel darunter).
	var split := BoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	rows.add_child(split)
	_split = split
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
	header.add_theme_constant_override("separation", 16)
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
	scroll.scroll_deadzone = 24
	_rail_scroll = scroll
	# W16/G3: BoxContainer — _layout_rail kippt die Chip-Achse je Format.
	_rail_box = BoxContainer.new()
	_rail_box.vertical = true
	_rail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rail_box)
	# W13/SAMMLUNG: der Sammlungs-Chip steht VOR den Sticker-Seiten (Web:
	# „Sticker“-Tab mit den 4 Sets ist der erste Album-Tab).
	_rail_box.add_child(_build_collections_chip())
	for page: Dictionary in _pages:
		_rail_box.add_child(_build_page_chip(page))
	return scroll


## Rail-Chip der Sammlungs-Seite (W13/SAMMLUNG) — gleiches AcChip-Muster wie
## die Seiten-Chips, Fortschritt über alle 4 Sets (n/32).
func _build_collections_chip() -> Control:
	var chip := SquishButton.new()
	chip.name = "PageChip_%s" % COLLECTIONS_PAGE
	chip.theme_type_variation = &"AcChip"
	chip.text = _collections_chip_text()
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.focus_mode = Control.FOCUS_NONE
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clamp_chip_text(chip)
	var icon_path := str(CollectionsView.SET_ICONS.get("fish", ""))
	if ResourceLoader.exists(icon_path):
		chip.icon = load(icon_path)
	chip.self_modulate = Color("#FFE3F0")
	chip.pressed.connect(_show_page.bind(COLLECTIONS_PAGE, true))
	return chip


## W14-P0 (FB3-Audit „Sticker laufen rechts aus dem Bild“): lange Chip-Texte
## („Morgenmuffel 3/6 NEU“) blähten die Mindestbreite der Rail auf — der
## ScrollContainer (horizontal_scroll DISABLED) erbt die Kind-Mindestbreite,
## das Grid rechnete aber mit der SOLL-Rail-Breite und lief übers Canvas.
## clip_text nimmt den Text aus der Mindestbreiten-Rechnung, „…“ kürzt sauber.
func _clamp_chip_text(chip: Button) -> void:
	chip.clip_text = true
	chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _collections_chip_text() -> String:
	var title := I18nService.t("collections.chip")
	if _gs == null:
		return title
	var progress := CollectionsLogic.total_progress(_collections_slice())
	return "%s  %d/%d" % [title, int(progress["have"]), int(progress["total"])]


func _build_page_chip(page: Dictionary) -> Control:
	var page_id := str(page.get("id", ""))
	var chip := SquishButton.new()
	chip.name = "PageChip_%s" % page_id
	chip.theme_type_variation = &"AcChip"
	chip.text = _chip_text(page)
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.focus_mode = Control.FOCUS_NONE
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clamp_chip_text(chip)
	var icon_path := "%s%s.svg" % [ICON_DIR, str(page.get("icon", "star"))]
	if ResourceLoader.exists(icon_path):
		chip.icon = load(icon_path)
	chip.self_modulate = Color(str(page.get("tint", "#FFFFFF")))
	chip.pressed.connect(_show_page.bind(page_id, true))
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
	var collections_chip := _rail_box.get_node_or_null("PageChip_%s" % COLLECTIONS_PAGE)
	if collections_chip is Button:
		(collections_chip as Button).text = _collections_chip_text()


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
	# W14: Seiten-Header mit Icon-Glyph (Settings-Gruppen-Muster) — das
	# Seiten-Icon der Rail wandert mit in die Überschrift.
	var head := HBoxContainer.new()
	head.name = "PageHead"
	head.add_theme_constant_override("separation", 8)
	panel.add_child(head)
	_page_icon = TextureRect.new()
	_page_icon.name = "PageIcon"
	_page_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page_icon.custom_minimum_size = Vector2.ONE * 24.0
	_page_icon.self_modulate = AcTokens.INK
	_page_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_page_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_page_icon)
	_page_title = Label.new()
	_page_title.theme_type_variation = &"HeadlineLabel"
	head.add_child(_page_title)
	_page_progress = Label.new()
	_page_progress.theme_type_variation = &"SoftLabel"
	panel.add_child(_page_progress)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# W16/G3 (G2-Scrollbalken-Regel): der sichtbare V-Balken addiert seine
	# Breite auf die Grid-Mindestbreite und drückte die Inhaltsspalte um
	# ~7 px aus dem Safe-Zentrum (FB3 content_mitte). Touch-Drag/Mausrad
	# funktionieren unverändert.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 24
	panel.add_child(scroll)
	_grid_scroll = scroll
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_grid)
	# W13/SAMMLUNG: die Sammlungs-View liegt als Geschwister des Grids im
	# Panel — _show_page schaltet zwischen beiden um.
	_collections_view = CollectionsView.new()
	_collections_view.name = "CollectionsView"
	_collections_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_collections_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_collections_view.visible = false
	_collections_view.set_claimed.connect(_on_collection_set_claimed)
	panel.add_child(_collections_view)
	_collections_view.setup(_gs)
	return panel


## W14: animate=true (Erstaufbau + Rail-Chip-Tap) staffelt die Kacheln weich
## ein; Refresh-Pfade (Resize, Unlock, Gesehen-Markierung) bleiben ruhig.
func _show_page(page_id: String, animate := false) -> void:
	_current_page = page_id
	# W13/SAMMLUNG: Pseudo-Seite — Grid aus, Sammlungs-View an (und zurück).
	if page_id == COLLECTIONS_PAGE:
		if _page_title != null:
			_page_title.text = I18nService.t("collections.titel")
		_set_page_icon(str(CollectionsView.SET_ICONS.get("fish", "")))
		_refresh_collections_progress()
		if _grid_scroll != null:
			_grid_scroll.visible = false
		if _collections_view != null:
			_collections_view.visible = true
			_collections_view.refresh()
		return
	if _grid_scroll != null:
		_grid_scroll.visible = true
	if _collections_view != null:
		_collections_view.visible = false
	var page := _page_def(page_id)
	if _page_title != null:
		_page_title.text = str(page.get("title_de", page_id))
	_set_page_icon("%s%s.svg" % [ICON_DIR, str(page.get("icon", "star"))])
	_refresh_page_progress(page_id)
	if _grid == null:
		return
	for child in _grid.get_children():
		# remove_child VOR queue_free: sonst kollidieren die Namen der neuen
		# Karten mit den noch nicht freigegebenen alten (Auto-Rename).
		_grid.remove_child(child)
		child.queue_free()
	var cards: Array = []
	for def: Dictionary in _by_page.get(page_id, []):
		var card := _build_sticker_card(def)
		_grid.add_child(card)
		cards.append(card)
	if animate:
		UiMotion.stagger_in(cards, 0.02)


## Seiten-Icon setzen (fehlt die Datei, verschwindet der Glyph statt ein
## leeres Quadrat zu lassen).
func _set_page_icon(icon_path: String) -> void:
	if _page_icon == null:
		return
	var has_icon := not icon_path.is_empty() and ResourceLoader.exists(icon_path)
	_page_icon.texture = load(icon_path) if has_icon else null
	_page_icon.visible = has_icon


## Fortschrittszeile der Sammlungs-Seite („n von 32 Schätzen gefunden“).
func _refresh_collections_progress() -> void:
	if _page_progress == null:
		return
	var progress := CollectionsLogic.total_progress(_collections_slice())
	_page_progress.text = I18nService.t(
		"collections.gesamt", {"n": int(progress["have"]), "total": int(progress["total"])}
	)


func _collections_slice() -> Dictionary:
	if _gs == null:
		return CollectionsLogic.normalize_slice(null)
	return CollectionsLogic.normalize_slice(_gs.state().get("collections"))


## Claim-Feier (W13/SAMMLUNG): Toast + Konfetti + Sticker-Pluck über die
## VORHANDENEN Mechanismen (eigene ToastLayer, _confetti_burst, Audio) — die
## setsClaimed-Sticker/Erfolge feiert der globale RewardHub von selbst, weil
## apply_claim slice_changed("collections") notifiziert.
func _on_collection_set_claimed(set_id: String, reward: Dictionary) -> void:
	(
		_toasts
		. show_toast(
			(
				I18nService
				. t(
					"collections.claim_toast",
					{
						"name": I18nService.t("collections.set.%s" % set_id),
						"coins": int(reward.get("coins", 0)),
						"item": I18nService.t("collections.reward.%s" % set_id),
					}
				)
			)
		)
	)
	AudioDirector.try_play(self, "ui_sticker")
	# W14/UIKERN-Kontrakt: Set-Claim ist eine Spezial-Interaktion → success.
	Haptics.success(self)
	_confetti_burst()
	_refresh_rail()
	_refresh_collections_progress()


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
	# W13B/STICKER (H §3.4): freigeschaltete GOLD-Sticker glitzern dezent
	# (Shimmer-Shader; Reduced Motion = statischer Glanz). Mystery-Slots
	# bleiben effektfrei — die Rarity soll nichts leaken.
	if unlocked:
		StickerCard.attach_glitter(card, str(def.get("rarity", "")), RewardFx.reduced_motion(self))
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
	if unlocked:
		# W13B/STICKER: Rarity-Begriff im Detail-Sheet (strings album.rarity_*).
		var rarity_label := Label.new()
		rarity_label.text = I18nService.t("album.rarity_%s" % str(def.get("rarity", "haeufig")))
		rarity_label.theme_type_variation = &"SoftLabel"
		_scale_font(rarity_label, 13)
		body.add_child(rarity_label)
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
	# W14/UIKERN-Kontrakt: Seiten-komplett-Belohnung → success-Haptik.
	Haptics.success(self)
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
