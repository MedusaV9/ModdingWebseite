class_name FuetterGrid
extends PanelContainer
## W14/FRIDGE — appetitliches Regal-Grid der Kühlschrank-Auswahl (ersetzt die
## flache Text-Liste): pro Speise eine AC-Karte mit ECHTER 3D-Vorschau
## (FuetterVorschau = geteilter Cosmetics-Icon-Renderer, gecacht), Name,
## Vorrats-Badge (×n), Stat-Vorschau-Pillen (+Hunger/+Spaß) und Zucker-Warn-
## Symbol bei Junk. Kategorien-Chips (aus FoodCatalog.kategorie abgeleitet)
## filtern das Regal. Leerer Vorrat = knuffiger Leerzustand („Der Kühlschrank
## gähnt vor Leere…") + Direkt-Knopf „Zu REHWEI fahren" (nur Route-Aufruf,
## der Kühlschrank verdrahtet ihn).

signal speise_gewaehlt(food_id: String)
signal schliessen_gewuenscht
signal rehwei_gewuenscht

const CHIP_ALLE := "alle"
const SPALTEN := 3
const ICON_PX := 84
const KARTE_MIN := Vector2(150, 172)
const REGAL_BREITE := 500.0
const REGAL_HOEHE_MAX := 384.0
const WARN_SYMBOL := "res://assets/fx/symbols/ausrufezeichen.svg"

var _entries: Array[Dictionary] = []
var _vorschau: FuetterVorschau
var _filter := CHIP_ALLE
var _chips_box: HBoxContainer
var _regal: GridContainer
var _icons: Dictionary = {}


## Chips aus den Vorrats-Einträgen ableiten: feste Katalog-Reihenfolge, nur
## vorhandene Kategorien, „Alles" voran sobald mindestens zwei da sind.
## PURE (testbar ohne Szene).
static func chips_fuer(entries: Array[Dictionary]) -> Array[String]:
	var vorhanden: Array[String] = []
	for kategorie: String in FoodCatalog.KATEGORIEN:
		for entry: Dictionary in entries:
			if FoodCatalog.kategorie(str(entry["id"])) == kategorie:
				vorhanden.append(kategorie)
				break
	if vorhanden.size() >= 2:
		vorhanden.push_front(CHIP_ALLE)
	return vorhanden


func setup(entries: Array[Dictionary], vorschau: FuetterVorschau = null) -> void:
	_entries = entries
	_vorschau = vorschau
	if _vorschau == null:
		_vorschau = FuetterVorschau.new()
		add_child(_vorschau)
	_vorschau.fertig.connect(_on_vorschau_fertig)
	theme = ThemeService.theme()
	theme_type_variation = "AcCard"
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_baue_inhalt()


func _baue_inhalt() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("rewards.kuehlschrank.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	if _entries.is_empty():
		_baue_leerzustand(box)
	else:
		_baue_chips(box)
		_baue_regal(box)
	var schliessen := Button.new()
	schliessen.name = "SchliessenKnopf"
	schliessen.theme_type_variation = "GhostButton"
	schliessen.text = I18nService.t("rewards.kuehlschrank.schliessen")
	schliessen.custom_minimum_size = Vector2(0, 44)
	schliessen.focus_mode = Control.FOCUS_NONE
	schliessen.pressed.connect(schliessen_gewuenscht.emit)
	box.add_child(schliessen)


# ── Leerzustand ───────────────────────────────────────────────────────────────


func _baue_leerzustand(box: VBoxContainer) -> void:
	var gaehnen := Label.new()
	gaehnen.name = "LeerTitel"
	gaehnen.text = I18nService.t("fuettern.leer_titel")
	gaehnen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(gaehnen)
	var tipp := Label.new()
	tipp.theme_type_variation = &"CaptionLabel"
	tipp.text = I18nService.t("fuettern.leer_tipp")
	tipp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tipp.custom_minimum_size = Vector2(300, 0)
	tipp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tipp)
	var rehwei := Button.new()
	rehwei.name = "RehweiKnopf"
	rehwei.theme_type_variation = "PrimaryButton"
	rehwei.text = I18nService.t("fuettern.leer_rehwei")
	rehwei.custom_minimum_size = Vector2(0, 48)
	rehwei.focus_mode = Control.FOCUS_NONE
	rehwei.pressed.connect(rehwei_gewuenscht.emit)
	box.add_child(rehwei)


# ── Kategorien-Chips ──────────────────────────────────────────────────────────


func _baue_chips(box: VBoxContainer) -> void:
	var chips := chips_fuer(_entries)
	if chips.is_empty():
		return
	if not chips.has(_filter):
		_filter = chips[0]
	if chips.size() < 2:
		return
	_chips_box = HBoxContainer.new()
	_chips_box.add_theme_constant_override("separation", 6)
	_chips_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_chips_box)
	for kategorie: String in chips:
		var chip := Button.new()
		chip.name = "Chip_" + kategorie
		chip.text = I18nService.t("fuettern.chip." + kategorie)
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(0, 36)
		chip.pressed.connect(_on_chip_gewaehlt.bind(kategorie))
		_chips_box.add_child(chip)
	_style_chips()


func _on_chip_gewaehlt(kategorie: String) -> void:
	if _filter == kategorie:
		_style_chips()
		return
	_filter = kategorie
	AudioDirector.try_play(self, "ui_click")
	_style_chips()
	_fuelle_regal()


func _style_chips() -> void:
	if _chips_box == null:
		return
	for chip: Node in _chips_box.get_children():
		if not (chip is Button):
			continue
		var kategorie := str(chip.name).trim_prefix("Chip_")
		(chip as Button).theme_type_variation = (
			"PrimaryButton" if kategorie == _filter else "GhostButton"
		)


# ── Regal ─────────────────────────────────────────────────────────────────────


func _baue_regal(box: VBoxContainer) -> void:
	var brett := PanelContainer.new()
	brett.theme_type_variation = "AcWell"
	box.add_child(brett)
	var scroll := ScrollContainer.new()
	var zeilen := ceili(float(_entries.size()) / float(SPALTEN))
	var hoehe := minf((KARTE_MIN.y + 10.0) * float(zeilen), REGAL_HOEHE_MAX)
	scroll.custom_minimum_size = Vector2(REGAL_BREITE, hoehe)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	brett.add_child(scroll)
	_regal = GridContainer.new()
	_regal.name = "Regal"
	_regal.columns = SPALTEN
	_regal.add_theme_constant_override("h_separation", 10)
	_regal.add_theme_constant_override("v_separation", 10)
	_regal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_regal)
	_fuelle_regal()


func _fuelle_regal() -> void:
	if _regal == null:
		return
	for kind in _regal.get_children():
		# Sofort austragen, NICHT nur queue_free: sonst kollidieren die
		# Karten-Namen beim Neuaufbau und Godot benennt die neuen Karten um.
		_regal.remove_child(kind)
		kind.queue_free()
	_icons.clear()
	for entry: Dictionary in _entries:
		var food_id := str(entry["id"])
		if _filter != CHIP_ALLE and FoodCatalog.kategorie(food_id) != _filter:
			continue
		_regal.add_child(_baue_karte(food_id, int(entry["count"])))


func _baue_karte(food_id: String, anzahl: int) -> Control:
	var karte := Button.new()
	karte.name = "Karte_" + food_id
	karte.theme_type_variation = "AcCardButton"
	karte.custom_minimum_size = KARTE_MIN
	karte.focus_mode = Control.FOCUS_NONE
	karte.pressed.connect(_on_karte_gedrueckt.bind(food_id))
	var inhalt := MarginContainer.new()
	inhalt.set_anchors_preset(Control.PRESET_FULL_RECT)
	for seite: String in ["left", "right", "top", "bottom"]:
		inhalt.add_theme_constant_override("margin_" + seite, 8)
	karte.add_child(inhalt)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 3)
	inhalt.add_child(spalte)
	spalte.add_child(_baue_kartenkopf(food_id, anzahl))
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _vorschau.hole_speise(food_id)
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spalte.add_child(icon)
	_icons[food_id] = icon
	var speise_name := Label.new()
	speise_name.theme_type_variation = &"CaptionLabel"
	speise_name.text = FoodCatalog.display_name(food_id)
	speise_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speise_name.clip_text = true
	# G7-P51 Text-Fit: Karten-Name ist ein Listen-Chip — Ellipsis statt
	# hartem Mitten-im-Wort-Schnitt bei langen Speise-Namen.
	speise_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	spalte.add_child(speise_name)
	spalte.add_child(_baue_pillen(food_id))
	_ignoriere_maus(inhalt)
	return karte


## Kopfzeile der Karte: Zucker-Warn-Symbol (nur Junk) links, ×n-Badge rechts.
func _baue_kartenkopf(food_id: String, anzahl: int) -> Control:
	var kopf := HBoxContainer.new()
	if FoodCatalog.is_junk(food_id):
		var warnung := TextureRect.new()
		warnung.name = "JunkWarnung"
		warnung.texture = load(WARN_SYMBOL)
		warnung.custom_minimum_size = Vector2(16, 16)
		warnung.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		warnung.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		warnung.modulate = AcTokens.DANGER
		warnung.tooltip_text = I18nService.t("fuettern.junk_warnung")
		kopf.add_child(warnung)
	var abstand := Control.new()
	abstand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(abstand)
	var badge := Label.new()
	badge.name = "Badge"
	badge.text = I18nService.t("fuettern.vorrat_badge", {"anzahl": anzahl})
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", AcTokens.INK_SOFT)
	kopf.add_child(badge)
	return kopf


func _baue_pillen(food_id: String) -> Control:
	var pillen := HBoxContainer.new()
	pillen.name = "Pillen"
	pillen.alignment = BoxContainer.ALIGNMENT_CENTER
	pillen.add_theme_constant_override("separation", 4)
	var deltas := FoodCatalog.deltas(food_id)
	var hunger := int(deltas["hunger"])
	if hunger > 0:
		pillen.add_child(
			_pille(I18nService.t("fuettern.pill_hunger", {"wert": hunger}), AcTokens.STAT_HUNGER)
		)
	var spass := int(deltas["fun"])
	if spass > 0:
		pillen.add_child(
			_pille(I18nService.t("fuettern.pill_spass", {"wert": spass}), AcTokens.STAT_FUN)
		)
	return pillen


func _pille(text: String, farbe: Color) -> Control:
	var panel := PanelContainer.new()
	var stil := StyleBoxFlat.new()
	stil.bg_color = Color(farbe, 0.16)
	stil.set_corner_radius_all(8)
	stil.content_margin_left = 6.0
	stil.content_margin_right = 6.0
	stil.content_margin_top = 1.0
	stil.content_margin_bottom = 1.0
	panel.add_theme_stylebox_override("panel", stil)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", farbe.darkened(0.35))
	panel.add_child(label)
	return panel


func _on_karte_gedrueckt(food_id: String) -> void:
	speise_gewaehlt.emit(food_id)


func _on_vorschau_fertig(id: String, textur: Texture2D) -> void:
	if not id.begins_with(FuetterVorschau.PREFIX):
		return
	var icon: Variant = _icons.get(id.trim_prefix(FuetterVorschau.PREFIX))
	if icon is TextureRect and is_instance_valid(icon):
		(icon as TextureRect).texture = textur


## Karten-Inhalt darf Taps nicht schlucken — alles durchreichen zum Button.
static func _ignoriere_maus(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind in node.get_children():
		if kind is Control:
			_ignoriere_maus(kind)
