class_name LevelReiseCard
extends PanelContainer
## Level-Reise-Karte im Profil (W18/R3, G8-IDEE Progression Nr. 2): ein
## horizontal scrollbarer Pfad Level 1→40 mit erreichten Leveln als
## (leicht gedrehten) Stempeln, den ECHTEN Freischalt-Gates als
## beschrifteten Toren (LevelReiseLogic.gates — aus dem Code gelesen),
## jedem 5. Level als Meilenstein-Fest-Knoten (L40 = Goldene Möhre) und
## dem Gooby-Marker samt „noch X XP“-Hinweis an der aktuellen Position.
##
## Scrollen: DragScroll-Helfer (G8-PT3 B1 — Wisch auf Knoten pannt trotzdem),
## Knoten-Größen halten den physischen Touch-Floor (44 pt) über den
## Metrics-Hook `wende_metrics_an` des Profil-Screens. Alle Knoten sind rein
## visuell (MOUSE_FILTER_IGNORE) — die Geste gehört dem Scroller.

const KNOTEN_BASIS := 48.0
const MEILENSTEIN_FAKTOR := 1.3
## Serpentinen-Amplitude (Design-px): Knoten wandern abwechselnd hoch/runter.
const WELLE_PX := 10.0
const GATE_SLOT_PX := 52.0
const GATE_CHIP_BREITE := 116.0

var gs: Object = null

var _m: Dictionary = {}
var _wurzel: VBoxContainer
var _scroll: ScrollContainer
var _aktueller_knoten: Control = null


func _ready() -> void:
	name = "LevelReiseCard"
	theme_type_variation = &"AcCard"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wurzel = VBoxContainer.new()
	_wurzel.add_theme_constant_override("separation", 8)
	add_child(_wurzel)
	_rebuild()


## Metrics-Hook des Profil-Screens (wie PassportCard.setze_schmal): baut die
## Reise mit den frischen Faktoren neu — f skaliert Design-px, floor_px hält
## den 44-pt-Touch-Floor der Knoten.
func wende_metrics_an(m: Dictionary) -> void:
	_m = m
	_rebuild()


func _f() -> float:
	return float(_m.get("f", 1.0))


func _floor_px() -> float:
	return float(_m.get("floor_px", KNOTEN_BASIS))


func _knoten_px(meilenstein: bool) -> float:
	var basis := maxf(KNOTEN_BASIS * _f(), _floor_px())
	return basis * (MEILENSTEIN_FAKTOR if meilenstein else 1.0)


func _rebuild() -> void:
	for kind in _wurzel.get_children():
		_wurzel.remove_child(kind)
		kind.queue_free()
	_aktueller_knoten = null
	_wurzel.add_child(_baue_kopf())
	_wurzel.add_child(_baue_hinweis())
	_wurzel.add_child(_baue_band())
	ScreenShell.scale_fonts(self, _f())
	_scroll_zur_position.call_deferred()


## ---------------------------------------------------------------- Kopf


func _baue_kopf() -> Control:
	var head := HBoxContainer.new()
	head.name = "ReiseKopf"
	head.add_theme_constant_override("separation", 8)
	var icon_path := "res://assets/ui/icons/suitcase.svg"
	if ResourceLoader.exists(icon_path):
		var glyph := TextureRect.new()
		glyph.texture = load(icon_path)
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.custom_minimum_size = Vector2.ONE * 22.0
		glyph.self_modulate = AcTokens.INK
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(glyph)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("levelreise.titel")
	head.add_child(title)
	return head


func _baue_hinweis() -> Control:
	var label := Label.new()
	label.name = "ReiseHinweis"
	label.theme_type_variation = &"SoftLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var info := LevelReiseLogic.hinweis(_state())
	if bool(info.get("max", false)):
		label.text = I18nService.t("levelreise.hinweis_max", {"max": int(info["level"])})
		return label
	var text := I18nService.t(
		"levelreise.hinweis",
		{"xp": int(info["xp_naechstes"]), "level": int(info["naechstes_level"])}
	)
	if int(info.get("fest_level", 0)) > 0:
		text += (
			" · "
			+ I18nService.t(
				"levelreise.hinweis_fest",
				{"level": int(info["fest_level"]), "xp": int(info["xp_fest"])}
			)
		)
	label.text = text
	return label


## ---------------------------------------------------------------- Band


func _baue_band() -> Control:
	_scroll = ScrollContainer.new()
	_scroll.name = "ReiseScroll"
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.scroll_deadzone = 24
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var band := HBoxContainer.new()
	band.name = "ReiseBand"
	band.add_theme_constant_override("separation", 0)
	_scroll.add_child(band)
	var hoehe := 0.0
	for station: Dictionary in LevelReiseLogic.stationen(_state()):
		var spalte := _baue_station(station)
		band.add_child(spalte)
		hoehe = maxf(hoehe, spalte.get_combined_minimum_size().y)
	_scroll.custom_minimum_size = Vector2(0.0, hoehe + 12.0 * _f())
	DragScroll.anbinden(_scroll)
	return _scroll


## Eine Station: Tor-Slot oben, Knoten-Welle in der Mitte, Level-Zeile und
## Extras unten. Alles rein visuell — Eingaben laufen durch zum Scroller.
func _baue_station(station: Dictionary) -> Control:
	var level := int(station["level"])
	var spalte := VBoxContainer.new()
	spalte.name = "Station_%d" % level
	spalte.add_theme_constant_override("separation", 2)
	spalte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spalte.add_child(_baue_gate_slot(station))
	spalte.add_child(_baue_knoten_welle(station))
	var zeile := Label.new()
	zeile.name = "LevelZeile"
	zeile.theme_type_variation = &"CaptionLabel"
	zeile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zeile.text = str(level)
	zeile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not bool(station["erreicht"]):
		zeile.add_theme_color_override("font_color", AcTokens.INK_FAINT)
	spalte.add_child(zeile)
	spalte.add_child(_baue_extras(station))
	return spalte


## Beschriftete Tore (echte Gates) über dem Knoten; leerer Slot hält die
## Knoten-Reihe auf einer Linie.
func _baue_gate_slot(station: Dictionary) -> Control:
	var slot := VBoxContainer.new()
	slot.name = "GateSlot"
	slot.alignment = BoxContainer.ALIGNMENT_END
	slot.add_theme_constant_override("separation", 2)
	slot.custom_minimum_size = Vector2(0.0, GATE_SLOT_PX * _f())
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for gate: Dictionary in station["gates"]:
		var chip := PanelContainer.new()
		chip.name = "GateChip_%s" % str(gate["id"])
		var sb := StyleBoxFlat.new()
		sb.bg_color = AcTokens.PAPER_SHADE
		sb.border_color = AcTokens.YELLOW_DARK
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 6.0
		sb.content_margin_right = 6.0
		sb.content_margin_top = 2.0
		sb.content_margin_bottom = 2.0
		chip.add_theme_stylebox_override("panel", sb)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.theme_type_variation = &"CaptionLabel"
		label.text = "%s %s" % [str(gate["glyph"]), I18nService.t(str(gate["label_key"]))]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(minf(GATE_CHIP_BREITE * _f(), 150.0 * _f()), 0.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not bool(station["erreicht"]):
			label.add_theme_color_override("font_color", AcTokens.INK_SOFT)
		chip.add_child(label)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.add_child(chip)
	return slot


## Knoten in der Serpentine: plain-Control-Wrapper (Container würden die
## manuelle Wellen-Position/Drehung zurücksetzen) + Pfad-Stummel im _draw.
func _baue_knoten_welle(station: Dictionary) -> Control:
	var level := int(station["level"])
	var meilenstein := bool(station["meilenstein"])
	var knoten_px := _knoten_px(meilenstein)
	var wrapper := Control.new()
	wrapper.name = "Welle_%d" % level
	var wrap_hoehe := _knoten_px(true) + 2.0 * WELLE_PX * _f()
	wrapper.custom_minimum_size = Vector2(maxf(knoten_px + 8.0 * _f(), 56.0 * _f()), wrap_hoehe)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.draw.connect(_zeichne_pfad.bind(wrapper, station))
	wrapper.resized.connect(wrapper.queue_redraw)
	var knoten := _baue_knoten(station, knoten_px)
	wrapper.add_child(knoten)
	knoten.position = Vector2(
		(wrapper.custom_minimum_size.x - knoten_px) / 2.0,
		(wrap_hoehe - knoten_px) / 2.0 + _wellen_offset(level)
	)
	if bool(station["aktuell"]):
		_aktueller_knoten = wrapper
		wrapper.add_child(_baue_marker(wrapper, knoten, knoten_px))
	return wrapper


func _baue_knoten(station: Dictionary, knoten_px: float) -> Control:
	var level := int(station["level"])
	var erreicht := bool(station["erreicht"])
	var aktuell := bool(station["aktuell"])
	var meilenstein := bool(station["meilenstein"])
	var knoten := PanelContainer.new()
	knoten.name = "ReiseKnoten_%d" % level
	knoten.custom_minimum_size = Vector2.ONE * knoten_px
	knoten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(knoten_px / 2.0))
	if aktuell:
		sb.bg_color = AcTokens.PAPER
		sb.border_color = AcTokens.PINK_DARK
		sb.set_border_width_all(3)
	elif erreicht:
		sb.bg_color = AcTokens.YELLOW if meilenstein else AcTokens.LEAF
		sb.border_color = AcTokens.YELLOW_DARK if meilenstein else AcTokens.LEAF_DARK
		sb.set_border_width_all(2)
	else:
		sb.bg_color = AcTokens.PAPER_SHADE
		sb.border_color = AcTokens.YELLOW_DARK if meilenstein else AcTokens.OUTLINE_SOFT
		sb.set_border_width_all(2)
	knoten.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.name = "KnotenText"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if meilenstein:
		label.text = (
			LevelReiseLogic.GLYPH_MOEHRE if bool(station["max"]) else LevelReiseLogic.GLYPH_FEST
		)
	else:
		label.text = str(level)
		label.add_theme_color_override(
			"font_color", AcTokens.WHITE if erreicht and not aktuell else AcTokens.INK
		)
	if not erreicht and not aktuell:
		label.modulate.a = 0.55 if meilenstein else 0.7
	knoten.add_child(label)
	# Erreichte Level sitzen wie STEMPEL leicht verdreht im Heft.
	if erreicht and not aktuell:
		knoten.rotation_degrees = LevelReiseLogic.stempel_drehung("knoten%d" % level)
		knoten.pivot_offset = Vector2.ONE * knoten_px / 2.0
	return knoten


## Gooby-Marker über dem aktuellen Knoten (+ „noch X XP“ übernimmt die
## Hinweis-Zeile im Kopf; hier nur die Figur, damit nichts überlappt).
func _baue_marker(wrapper: Control, knoten: Control, knoten_px: float) -> Control:
	var marker := Label.new()
	marker.name = "ReiseMarker"
	marker.text = "🐰"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.position = Vector2(
		knoten.position.x + knoten_px / 2.0 - 12.0 * _f(), knoten.position.y - 24.0 * _f()
	)
	marker.z_index = 2
	wrapper.set_meta("marker", true)
	return marker


func _baue_extras(station: Dictionary) -> Control:
	var extras: Dictionary = station["extras"]
	var teile: Array[String] = []
	if int(extras.get("garderobe", 0)) > 0:
		teile.append(I18nService.t("levelreise.extra_garderobe", {"n": int(extras["garderobe"])}))
	if int(extras.get("modifier", 0)) > 0:
		teile.append(I18nService.t("levelreise.extra_modifier", {"n": int(extras["modifier"])}))
	if bool(station["aktuell"]):
		var info := LevelReiseLogic.hinweis(_state())
		if not bool(info.get("max", false)):
			teile.append(I18nService.t("levelreise.marker_xp", {"xp": int(info["xp_naechstes"])}))
	var label := Label.new()
	label.name = "Extras_%d" % int(station["level"])
	label.theme_type_variation = &"CaptionLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0.0, 18.0 * _f())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "\n".join(teile)
	if bool(station["aktuell"]):
		label.add_theme_color_override("font_color", AcTokens.PINK_DARK)
	else:
		label.add_theme_color_override("font_color", AcTokens.INK_FAINT)
	return label


## Serpentine: gerade Level unten, ungerade oben — ±WELLE_PX um die Mitte.
func _wellen_offset(level: int) -> float:
	return (WELLE_PX if level % 2 == 0 else -WELLE_PX) * _f()


## Pfad-Stummel dieser Station: Linie vom linken Rand (Höhe des Nachbarn)
## über die eigene Knoten-Mitte zum rechten Rand (Höhe des Nachbarn) —
## Nachbar-Höhen sind über die Level-Parität bekannt, die Stummel stoßen
## bei Separation 0 nahtlos aneinander.
func _zeichne_pfad(wrapper: Control, station: Dictionary) -> void:
	var level := int(station["level"])
	var mitte := Vector2(wrapper.size.x / 2.0, wrapper.size.y / 2.0 + _wellen_offset(level))
	var farbe: Color = (
		Color(AcTokens.LEAF_DARK, 0.5) if bool(station["erreicht"]) else AcTokens.TRACK_SOFT
	)
	var dicke := 5.0 * _f()
	if level > 1:
		var links_y := wrapper.size.y / 2.0 + _wellen_offset(level - 1)
		var start := Vector2(0.0, (links_y + mitte.y) / 2.0)
		wrapper.draw_line(start, mitte, farbe, dicke, true)
	if level < LevelReiseLogic.Leveling.MAX_LEVEL:
		var rechts_y := wrapper.size.y / 2.0 + _wellen_offset(level + 1)
		var ziel := Vector2(wrapper.size.x, (rechts_y + mitte.y) / 2.0)
		wrapper.draw_line(mitte, ziel, farbe, dicke, true)


## Beim Öffnen die aktuelle Position ins Bild holen (deferred — Layout muss
## erst stehen).
func _scroll_zur_position() -> void:
	if _scroll == null or _aktueller_knoten == null:
		return
	if not is_inside_tree() or not _aktueller_knoten.is_inside_tree():
		return
	_scroll.ensure_control_visible(_aktueller_knoten)


func _state() -> Dictionary:
	if gs == null or not gs.has_method("state"):
		return {}
	return gs.state()
