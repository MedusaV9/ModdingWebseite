class_name CollectionsView
extends Control
## Sammlungs-Bereich im Album (W13/SAMMLUNG, Web-Parität zu
## GOOBY/src/ui/albumScreen.js renderCollections): 4 Set-Karten im AC-Look
## (AcCard), je Karte Icon-Slots aller Set-Einträge (gesammelt = farbige
## Pastell-Kachel mit Set-Icon, fehlend = „?"-Silhouette — NIE ein Leak),
## Fortschritt n/m und ein Claim-Knopf, der bei vollem Set die Web-Belohnung
## über CollectionsLogic.apply_claim bucht (einmalig). Die Feier (Toast +
## Konfetti) macht der Album-Screen über sein set_claimed-Signal.
##
## Kein eigener Service, kein Polling: refresh() liest den Save-Slice über
## die GameState-API; die Uhr kommt injiziert vom GameState (clock).

signal set_claimed(set_id: String, reward: Dictionary)

## Set-Icons (Web SET_ICONS: fish/carrot/home/hunger) — fish + carrot sind
## neue Ports nach assets/collections/, Rest sind vorhandene UI-Icons.
const SET_ICONS := {
	"fish": "res://assets/collections/fish.svg",
	"veggies": "res://assets/collections/carrot.svg",
	"landmarks": "res://assets/ui/icons/home.svg",
	"treats": "res://assets/ui/icons/hunger.svg",
}
const CHECK_ICON := "res://assets/ui/icons/check.svg"
const COIN_ICON := "res://assets/ui/icons/coin.svg"
## Web-Referenzwert — nur noch Fallback, solange keine Panelbreite bekannt
## ist (W16/G3: Spaltenzahl kommt sonst responsiv aus `_slot_columns()`).
const SLOT_COLUMNS := 5

var _gs: Object = null
var _cards_box: VBoxContainer
var _f := 1.0
## W16/G3: nutzbare Panelbreite + physischer Touch-Floor (vom Album).
var _avail_w := 0.0
var _floor_px := 0.0


## Web tintOf-Port: deterministische Pastellfarbe je Eintrag (hsl → hsv;
## 62 % Sättigung / 72 % Helligkeit) — kein Zufall, gleiche Kachel = gleiche
## Farbe über Sessions hinweg.
static func tint_of(set_id: String, entry_id: String) -> Color:
	var s := "%s.%s" % [set_id, entry_id]
	var h := 0
	for i in s.length():
		h = int((h * 31 + s.unicode_at(i)) % 4294967296)
	return Color.from_hsv(float(h % 360) / 360.0, 0.389, 0.894)


## View an den GameState hängen und die Karten bauen.
func setup(gs: Object) -> void:
	_gs = gs
	if _cards_box == null:
		_build_ui()
	refresh()


## Alle 4 Karten aus dem aktuellen Save-Slice neu aufbauen.
func refresh() -> void:
	if _cards_box == null:
		return
	for child in _cards_box.get_children():
		# remove_child VOR queue_free (Namens-Kollision neuer Karten, s. Album).
		_cards_box.remove_child(child)
		child.queue_free()
	var c := _slice()
	for def: Dictionary in CollectionsLogic.sets():
		_cards_box.add_child(_build_set_card(str(def["id"]), c))


## FIX1/W16-Anschluss: Layout-Kenngrößen vom Album übernehmen — Retina-
## Faktor, nutzbare Panelbreite (responsive Slot-Spaltenzahl) und der
## physische Touch-Floor für den Claim-Knopf.
func apply_layout(f: float, avail_w: float, floor_px: float) -> void:
	var unveraendert := (
		is_equal_approx(_f, f)
		and is_equal_approx(_avail_w, avail_w)
		and is_equal_approx(_floor_px, floor_px)
	)
	if unveraendert:
		return
	_f = f
	_avail_w = avail_w
	_floor_px = floor_px
	refresh()


## W16/G3 (HOCH-Fix ui-profil §4): Spaltenzahl aus der REALEN Panelbreite
## statt fix 5 — bei f=3 sprengten 5 Slot-Spalten (~900 px Mindestbreite)
## das ~806-px-Panel im Hochformat (horizontal-Scroll ist DISABLED, das
## Raster lief also rechts aus dem Bild).
func _slot_columns() -> int:
	if _avail_w <= 0.0:
		return SLOT_COLUMNS
	return clampi(int(_avail_w / (68.0 * maxf(_f, 1.0))), 3, 6)


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# W16/G3: Balken versteckt wie beim Sticker-Grid (G2-Scrollbalken-
	# Regel) — der sichtbare Balken überlagerte sonst die Claim-Zeile.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 24
	add_child(scroll)
	_cards_box = VBoxContainer.new()
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_theme_constant_override("separation", 14)
	scroll.add_child(_cards_box)


func _build_set_card(set_id: String, c: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "SetCard_%s" % set_id
	card.theme_type_variation = &"AcCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var progress := CollectionsLogic.set_progress(c, set_id)
	box.add_child(_build_card_header(set_id, progress))
	box.add_child(_build_hint(set_id))
	box.add_child(_build_entry_grid(set_id, c))
	box.add_child(_build_claim_row(set_id, c, progress))
	return card


func _build_card_header(set_id: String, progress: Dictionary) -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var icon := _icon_rect(set_id, 26.0 * maxf(_f, 1.0))
	if icon != null:
		icon.self_modulate = AcTokens.INK
		header.add_child(icon)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("collections.set.%s" % set_id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	# G7-P51 Text-Fit: clip ohne Overrun schnitt lange Set-Namen MITTEN im
	# Wort ab — Kopfzeile neben dem Fortschritts-Chip darf sauber kürzen.
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_scale_font(title, 22)
	header.add_child(title)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"StatusCapsule"
	var count := Label.new()
	count.name = "ProgressLabel"
	count.theme_type_variation = &"SoftLabel"
	count.text = I18nService.t(
		"collections.fortschritt", {"n": int(progress["have"]), "total": int(progress["total"])}
	)
	_scale_font(count, AcTokens.FONT_SIZE_CAPTION)
	chip.add_child(count)
	header.add_child(chip)
	return header


func _build_hint(set_id: String) -> Control:
	var hint := Label.new()
	hint.text = I18nService.t("collections.hinweis.%s" % set_id)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", AcTokens.INK_SOFT)
	_scale_font(hint, 14)
	return hint


func _build_entry_grid(set_id: String, c: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.name = "EntryGrid"
	grid.columns = _slot_columns()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for entry_id: String in CollectionsLogic.set_def(set_id).get("entries", []):
		grid.add_child(_build_entry_slot(set_id, entry_id, c))
	return grid


## Ein Icon-Slot: gesammelt = Pastell-Kachel + Set-Icon + Name (+ ×n-Badge),
## fehlend = graue Kachel + „?"-Silhouette + „???" (Web-Mystery-Regel).
func _build_entry_slot(set_id: String, entry_id: String, c: Dictionary) -> Control:
	var count := CollectionsLogic.count_of(c, set_id, entry_id)
	var owned := count >= 1
	var slot := VBoxContainer.new()
	slot.name = "Slot_%s" % entry_id
	slot.add_theme_constant_override("separation", 4)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tile := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = tint_of(set_id, entry_id) if owned else AcTokens.TRACK_SOFT
	style.set_corner_radius_all(AcTokens.RADIUS_ROW)
	style.set_content_margin_all(8.0)
	tile.add_theme_stylebox_override("panel", style)
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(52.0, 52.0) * maxf(_f, 1.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(frame)
	if owned:
		var icon := _icon_rect(set_id, 0.0)
		if icon != null:
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.self_modulate = Color(AcTokens.INK, 0.75)
			frame.add_child(icon)
		if count > 1:
			frame.add_child(_build_count_badge(count))
	else:
		var mark := Label.new()
		mark.name = "MysteryMark"
		mark.text = "?"
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.add_theme_color_override("font_color", Color(AcTokens.INK, 0.45))
		mark.add_theme_font_size_override("font_size", int(28 * maxf(_f, 1.0)))
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(mark)
	slot.add_child(tile)
	var caption := Label.new()
	caption.text = (
		I18nService.t("collections.eintrag.%s.%s" % [set_id, entry_id])
		if owned
		else I18nService.t("collections.unbekannt")
	)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.clip_text = true
	# G7-P51 Text-Fit: Kachel-Unterschrift ist ein Listen-Chip — Ellipsis
	# statt hartem Mitten-im-Wort-Schnitt.
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_theme_color_override(
		"font_color", AcTokens.INK if owned else Color(AcTokens.INK, 0.45)
	)
	_scale_font(caption, 12)
	slot.add_child(caption)
	return slot


## Wiederholungs-Badge „×n" (Web .g23-al-n) oben rechts auf der Kachel.
func _build_count_badge(count: int) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = AcTokens.PINK
	style.set_corner_radius_all(AcTokens.RADIUS_PILL)
	style.set_content_margin_all(3.0)
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "×%d" % count
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", AcTokens.WHITE)
	_scale_font(label, 11)
	badge.add_child(label)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -30.0 * _f
	badge.offset_top = -4.0
	badge.offset_right = 4.0
	return badge


func _build_claim_row(set_id: String, c: Dictionary, progress: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var status := Label.new()
	status.theme_type_variation = &"SoftLabel"
	status.text = I18nService.t(
		"album.set_fortschritt", {"n": int(progress["have"]), "total": int(progress["total"])}
	)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true
	# G7-P51 Text-Fit: Status-Zeile neben dem Claim-Knopf kürzt sauber.
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_scale_font(status, AcTokens.FONT_SIZE_CAPTION)
	row.add_child(status)
	var claimed := CollectionsLogic.is_claimed(c, set_id)
	var complete := CollectionsLogic.is_set_complete(c, set_id)
	var button := SquishButton.new()
	button.name = "ClaimButton"
	button.focus_mode = Control.FOCUS_NONE
	# W16/G3: physischer Touch-Floor — 44·f allein blieb im Hochformat
	# (Floor ≈ 143 px bei f=3) knapp darunter.
	button.custom_minimum_size = Vector2(0.0, maxf(44.0 * maxf(_f, 1.0), _floor_px))
	# Web-Knopf trägt ein KLEINES Icon (13 px) — ohne Deckel füllt das
	# Coin-SVG sonst die ganze Knopfhöhe.
	button.add_theme_constant_override("icon_max_width", int(20 * maxf(_f, 1.0)))
	if claimed:
		button.theme_type_variation = &"GhostButton"
		button.text = I18nService.t("collections.claimed")
		button.disabled = true
		if ResourceLoader.exists(CHECK_ICON):
			button.icon = load(CHECK_ICON)
	else:
		button.theme_type_variation = &"BtnYellow"
		button.text = I18nService.t("collections.claim")
		button.disabled = not complete
		if ResourceLoader.exists(COIN_ICON):
			button.icon = load(COIN_ICON)
		button.pressed.connect(_on_claim_pressed.bind(set_id))
	_scale_font(button, 16)
	row.add_child(button)
	return row


func _on_claim_pressed(set_id: String) -> void:
	var reward := CollectionsLogic.apply_claim(_gs, set_id, _now_ms(), _local_day())
	if reward.is_empty():
		return
	refresh()
	set_claimed.emit(set_id, reward)


func _slice() -> Dictionary:
	if _gs == null:
		return CollectionsLogic.normalize_slice(null)
	return CollectionsLogic.normalize_slice(_gs.state().get("collections"))


func _icon_rect(set_id: String, side: float) -> TextureRect:
	var path := str(SET_ICONS.get(set_id, ""))
	if not ResourceLoader.exists(path):
		return null
	var rect := TextureRect.new()
	rect.texture = load(path)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if side > 0.0:
		rect.custom_minimum_size = Vector2(side, side)
	return rect


## Font nur bei echtem Faktor überschreiben — bei 1.0 bleibt das Theme (FIX1).
func _scale_font(ctl: Control, base_px: int) -> void:
	if _f > 1.0:
		ctl.add_theme_font_size_override("font_size", int(base_px * _f))
	else:
		ctl.remove_theme_font_size_override("font_size")


## Uhr kommt injiziert vom GameState (Tests pinnen gs.clock) — kein eigener
## Zeitzugriff, Fallback nur ohne GameState.
func _now_ms() -> int:
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _local_day() -> String:
	if _gs != null and "clock" in _gs:
		return str(_gs.clock.local_day())
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]
