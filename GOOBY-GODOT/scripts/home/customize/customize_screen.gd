class_name CustomizeScreen
extends Control
## „Gestalten"-Screen (HAUS-CUSTOM) — der Anpassungs-Modus aus dem
## User-Wunsch: „Man soll alles, also auch den Haus-Stil, Farbe und
## Gras/Boden etc. anpassen können." AC-Look nach dem Muster IkeaScreen:
## Kategorien links, Options-Kacheln mit prozeduralem Vorschaubild,
## Palette-Farbwähler (keine RGB-Regler), Live-3D-Vorschau
## (CustomizePreview), „Zufällig"/„Zurücksetzen", Kauf-/Besitz-Anzeige.
##
## Nicht gekaufte Optionen dürfen VORGEMERKT werden: die Vorschau zeigt sie
## live („Anprobe"), gespeichert wird erst nach dem Kauf
## (HouseStyleState.kaufen → Economy.spend, ein Geld-Pfad).
##
## HUD-Verdrahtung (Muster ArcadeScreen/IkeaScreen): der Home-Besitzer
## verbindet `hud.action_pressed.connect(CustomizeScreen.handle_hud_action)`
## — siehe Handoff `HAUSCUSTOM-room-request.md`.

signal back_requested

const ROUTE := &"gestalten"
const ROUTES := {ROUTE: "res://scripts/home/customize/customize_screen.tscn"}
const HUD_ACTION := &"gestalten"

const LIST_WIDTH := 250
const TILE_SIZE := Vector2(104, 132)
const SWATCH_SIZE := 36
const PREVIEW_MIN_HEIGHT := 180

## Kategorien: id (auch String-Key customize.kategorie.<id>), Bereich
## (innen/haus/grund), kaufbare Options-Art, Farb-Quelle und Save-Keys.
const KATEGORIEN: Array[Dictionary] = [
	{"id": "wand", "bereich": "innen", "art": "wand"},
	{"id": "boden", "bereich": "innen", "art": "boden"},
	{"id": "fassade", "bereich": "haus", "farb_bereich": "fassade", "farb_key": "fassade"},
	{
		"id": "dach",
		"bereich": "haus",
		"art": "dachForm",
		"key": "dachForm",
		"farb_bereich": "dach",
		"farb_key": "dachFarbe",
	},
	{"id": "tuer", "bereich": "haus", "farb_bereich": "tuer", "farb_key": "tuerFarbe"},
	{"id": "fenster", "bereich": "haus", "farb_bereich": "fenster", "farb_key": "fensterFarbe"},
	{"id": "hausnummer", "bereich": "haus", "art": "hausnummer", "key": "hausnummer", "zahl": true},
	{
		"id": "briefkasten",
		"bereich": "haus",
		"art": "briefkasten",
		"key": "briefkasten",
		"farb_key": "briefkastenFarbe",
	},
	{
		"id": "vordach",
		"bereich": "haus",
		"art": "vordach",
		"key": "vordach",
		"farb_key": "vordachFarbe",
	},
	{
		"id": "grund_boden",
		"bereich": "grund",
		"art": "grundBoden",
		"key": "boden",
		"farb_key": "bodenFarbe",
	},
	{"id": "weg", "bereich": "grund", "art": "weg", "key": "weg", "farb_key": "wegFarbe"},
	{"id": "zaun", "bereich": "grund", "art": "zaun", "key": "zaun", "farb_key": "zaunFarbe"},
]

## Tests/Screenshots: Navigation abschaltbar, GameState austauschbar.
var auto_navigate := true
var game_state_override: Object = null

var _preview: CustomizePreview
var _kategorie_liste: VBoxContainer
var _raum_chips: HBoxContainer
var _optionen: HBoxContainer
var _optionen_scroll: ScrollContainer
var _farben: HBoxContainer
var _farben_row: HBoxContainer
var _zahl_row: HBoxContainer
var _zahl_label: Label
var _status_label: Label
var _kauf_button: Button
var _coins_label: Label
var _toasts: ToastLayer
var _kategorie: Dictionary = KATEGORIEN[0]
var _raum := "living"
var _pending_id := ""
var _pending_farbe := ""
var _rng := RandomNumberGenerator.new()


## Route am SceneRouter anmelden (idempotent) — wie IkeaScreen.
static func register_routes() -> void:
	var router := _router()
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


## EIN Verdrahtungspunkt für den HUD-/Baumodus-Knopf. true = konsumiert.
static func handle_hud_action(action: StringName) -> bool:
	if action != HUD_ACTION:
		return false
	register_routes()
	var router := _router()
	if router == null or not router.has_method("goto"):
		return false
	router.goto(ROUTE, {})
	return true


static func _router() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_rng.randomize()
	_build_ui()
	_refresh_alles()


# ── Öffentliche Steuerung (UI + Tests + Screenshots) ─────────────────────


func set_kategorie(kategorie_id: String) -> void:
	for kat: Dictionary in KATEGORIEN:
		if str(kat["id"]) == kategorie_id:
			_kategorie = kat
			break
	_pending_id = ""
	_refresh_alles()


func set_raum(room_id: String) -> void:
	_raum = room_id
	_pending_id = ""
	_refresh_alles()


## Options-Kachel wählen: Besitz → sofort anwenden, sonst vormerken
## („Anprobe": Vorschau zeigt sie live, Kaufen-Knopf wird aktiv).
func select_option(id: String) -> void:
	var art := str(_kategorie.get("art", ""))
	if art == "" or CustomizeCatalog.def(art, id).is_empty():
		return
	if HouseStyleState.ist_gekauft(_game_state(), art, id):
		_pending_id = ""
		_wende_option_an(id, _passende_farbe(art, id))
	else:
		_pending_id = id
		_pending_farbe = _passende_farbe(art, id)
	_refresh_alles()


## Palettenfarbe wählen (wirkt auf Vormerkung ODER aktuelle Option/Fläche).
func select_farbe(farb_id: String) -> void:
	if _pending_id != "":
		_pending_farbe = farb_id
		_refresh_alles()
		return
	var gs := _game_state()
	if _kategorie.has("farb_bereich") and not _kategorie.has("art"):
		HouseStyleState.set_haus(gs, str(_kategorie["farb_key"]), farb_id)
	else:
		_wende_option_an(_aktuelle_id(), farb_id)
	_refresh_alles()


## Vorgemerkte Option kaufen und anwenden. Liefert den Ergebniscode.
func buy_selected() -> String:
	if _pending_id == "":
		return HouseStyleState.RESULT_UNKNOWN
	var art := str(_kategorie.get("art", ""))
	var id := _pending_id
	var result := HouseStyleState.kaufen(_game_state(), art, id)
	_zeige_ergebnis(art, id, result)
	if result == HouseStyleState.RESULT_OK or result == HouseStyleState.RESULT_OWNED:
		_wende_option_an(id, _pending_farbe)
		_pending_id = ""
	_refresh_alles()
	return result


## „Zufällig" für den aktuellen Bereich — nur aus gekauften Optionen.
func zufall() -> void:
	var gs := _game_state()
	match str(_kategorie["bereich"]):
		"innen":
			HouseStyleState.zufall_raum(gs, _raum, _rng)
		"haus":
			HouseStyleState.zufall_haus(gs, _rng)
		"grund":
			HouseStyleState.zufall_grundstueck(gs, _rng)
	_pending_id = ""
	_refresh_alles()


## „Zurücksetzen" auf die Katalog-Defaults (Besitz bleibt).
func reset_aktuell() -> void:
	var gs := _game_state()
	match str(_kategorie["bereich"]):
		"innen":
			HouseStyleState.reset_raum(gs, _raum)
		"haus":
			HouseStyleState.reset_haus(gs)
		"grund":
			HouseStyleState.reset_grundstueck(gs)
	_pending_id = ""
	_refresh_alles()


func set_hausnummer_zahl(delta: int) -> void:
	var zahl := int(HouseStyleState.style(_game_state())["haus"]["hausnummerZahl"])
	HouseStyleState.set_haus(_game_state(), "hausnummerZahl", zahl + delta)
	_refresh_alles()


func preview() -> CustomizePreview:
	return _preview


func kategorie_id() -> String:
	return str(_kategorie["id"])


func aktueller_raum() -> String:
	return _raum


func pending_id() -> String:
	return _pending_id


# ── Anwenden ─────────────────────────────────────────────────────────────


func _wende_option_an(id: String, farb_id: String) -> void:
	var gs := _game_state()
	var art := str(_kategorie.get("art", ""))
	match str(_kategorie["bereich"]):
		"innen":
			HouseStyleState.set_raum_flaeche(gs, _raum, art, id, farb_id)
		"haus":
			HouseStyleState.set_haus(gs, str(_kategorie["key"]), id)
			if _kategorie.has("farb_key") and farb_id != "":
				HouseStyleState.set_haus(gs, str(_kategorie["farb_key"]), farb_id)
		"grund":
			HouseStyleState.set_grundstueck(gs, str(_kategorie["key"]), id)
			if farb_id != "":
				HouseStyleState.set_grundstueck(gs, str(_kategorie["farb_key"]), farb_id)


## Farbe, die zur Option passt: aktuelle behalten wenn erlaubt, sonst erste.
func _passende_farbe(art: String, id: String) -> String:
	var erlaubt := CustomizeCatalog.farben(art, id)
	if erlaubt.is_empty():
		return ""
	var aktuell := _aktuelle_farbe()
	return aktuell if erlaubt.has(aktuell) else str(erlaubt[0])


## Aktuelle Options-ID der Kategorie aus dem (geheilten) Stil.
func _aktuelle_id() -> String:
	var style := HouseStyleState.style(_game_state())
	match str(_kategorie["bereich"]):
		"innen":
			return str(_raum_style(style).get(str(_kategorie["art"]), ""))
		"haus":
			return str(style["haus"].get(str(_kategorie.get("key", "")), ""))
		"grund":
			return str(style["grundstueck"].get(str(_kategorie.get("key", "")), ""))
	return ""


func _aktuelle_farbe() -> String:
	var style := HouseStyleState.style(_game_state())
	match str(_kategorie["bereich"]):
		"innen":
			return str(_raum_style(style).get("%sFarbe" % str(_kategorie["art"]), ""))
		"haus":
			return str(style["haus"].get(str(_kategorie.get("farb_key", "")), ""))
		"grund":
			return str(style["grundstueck"].get(str(_kategorie.get("farb_key", "")), ""))
	return ""


func _raum_style(style: Dictionary) -> Dictionary:
	var raeume: Dictionary = style.get("raeume", {})
	if raeume.has(_raum):
		return raeume[_raum]
	return CustomizeCatalog.raum_default(_raum)


## Stil für die Vorschau: Vormerkung wird OHNE Speichern hineingepatcht.
func _preview_style() -> Dictionary:
	var style := HouseStyleState.style(_game_state())
	if _pending_id == "":
		return style
	match str(_kategorie["bereich"]):
		"innen":
			var raum := _raum_style(style).duplicate(true)
			raum[str(_kategorie["art"])] = _pending_id
			raum["%sFarbe" % str(_kategorie["art"])] = _pending_farbe
			style["raeume"][_raum] = raum
		"haus":
			style["haus"][str(_kategorie["key"])] = _pending_id
			if _kategorie.has("farb_key") and _pending_farbe != "":
				style["haus"][str(_kategorie["farb_key"])] = _pending_farbe
		"grund":
			style["grundstueck"][str(_kategorie["key"])] = _pending_id
			if _pending_farbe != "":
				style["grundstueck"][str(_kategorie["farb_key"])] = _pending_farbe
	return style


func _game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


# ── Aufbau ───────────────────────────────────────────────────────────────


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
	body.add_child(_build_kategorie_spalte())
	body.add_child(_build_rechte_spalte())
	_toasts = ToastLayer.new()
	add_child(_toasts)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.name = "BackButton"
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("customize.back")
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("customize.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.theme_type_variation = &"HeadlineLabel"
	header.add_child(_coins_label)
	return header


func _build_kategorie_spalte() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	column.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.name = "KategorieScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_kategorie_liste = VBoxContainer.new()
	_kategorie_liste.name = "KategorieListe"
	_kategorie_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kategorie_liste.add_theme_constant_override("separation", 6)
	scroll.add_child(_kategorie_liste)
	return column


func _build_rechte_spalte() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	_raum_chips = HBoxContainer.new()
	_raum_chips.name = "RaumChips"
	_raum_chips.add_theme_constant_override("separation", 6)
	column.add_child(_raum_chips)
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCardLg"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(card)
	_preview = CustomizePreview.new()
	_preview.name = "Preview"
	_preview.custom_minimum_size = Vector2(0, PREVIEW_MIN_HEIGHT)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(_preview)
	column.add_child(_build_options_panel())
	return column


func _build_options_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AcCard"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	_optionen_scroll = ScrollContainer.new()
	_optionen_scroll.name = "OptionenScroll"
	_optionen_scroll.custom_minimum_size = Vector2(0, TILE_SIZE.y + 18)
	_optionen_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(_optionen_scroll)
	_optionen = HBoxContainer.new()
	_optionen.name = "OptionenListe"
	_optionen.add_theme_constant_override("separation", 8)
	_optionen_scroll.add_child(_optionen)
	rows.add_child(_build_farben_row())
	rows.add_child(_build_aktions_row())
	return panel


func _build_farben_row() -> Control:
	_farben_row = HBoxContainer.new()
	_farben_row.add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionLabel"
	caption.text = I18nService.t("customize.farbe_titel")
	_farben_row.add_child(caption)
	_farben = HBoxContainer.new()
	_farben.name = "Farben"
	_farben.add_theme_constant_override("separation", 6)
	_farben_row.add_child(_farben)
	return _farben_row


## Hausnummern-Zahl (-/Nr./+) — lebt IN der Aktions-Zeile, damit die Höhe
## des Panels konstant bleibt (Mobile: 576er-Design-Höhe).
func _build_zahl_row() -> Control:
	_zahl_row = HBoxContainer.new()
	_zahl_row.name = "ZahlRow"
	_zahl_row.add_theme_constant_override("separation", 8)
	var minus := Button.new()
	minus.name = "ZahlMinus"
	minus.theme_type_variation = &"AcChip"
	minus.text = "-"
	minus.custom_minimum_size = Vector2(AcTokens.TOUCH_FLOOR, AcTokens.TOUCH_FLOOR)
	minus.pressed.connect(_on_zahl_pressed.bind(-1))
	_zahl_row.add_child(minus)
	_zahl_label = Label.new()
	_zahl_label.name = "ZahlLabel"
	_zahl_label.theme_type_variation = &"HeadlineLabel"
	_zahl_row.add_child(_zahl_label)
	var plus := Button.new()
	plus.name = "ZahlPlus"
	plus.theme_type_variation = &"AcChip"
	plus.text = "+"
	plus.custom_minimum_size = Vector2(AcTokens.TOUCH_FLOOR, AcTokens.TOUCH_FLOOR)
	plus.pressed.connect(_on_zahl_pressed.bind(1))
	_zahl_row.add_child(plus)
	return _zahl_row


func _build_aktions_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_build_zahl_row())
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.theme_type_variation = &"HeadlineLabel"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status_label)
	_kauf_button = Button.new()
	_kauf_button.name = "KaufButton"
	_kauf_button.theme_type_variation = &"PrimaryButton"
	_kauf_button.text = I18nService.t("customize.kaufen")
	_kauf_button.custom_minimum_size = Vector2(150, AcTokens.TOUCH_FLOOR)
	_kauf_button.pressed.connect(_on_kauf_pressed)
	row.add_child(_kauf_button)
	var zufall_btn := Button.new()
	zufall_btn.name = "ZufallButton"
	zufall_btn.theme_type_variation = &"AcChip"
	zufall_btn.text = I18nService.t("customize.zufall")
	zufall_btn.custom_minimum_size = Vector2(0, AcTokens.TOUCH_FLOOR)
	zufall_btn.pressed.connect(_on_zufall_pressed)
	row.add_child(zufall_btn)
	var reset_btn := Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.theme_type_variation = &"GhostButton"
	reset_btn.text = I18nService.t("customize.reset")
	reset_btn.custom_minimum_size = Vector2(0, AcTokens.TOUCH_FLOOR)
	reset_btn.pressed.connect(_on_reset_pressed)
	row.add_child(reset_btn)
	return row


# ── Auffrischen ──────────────────────────────────────────────────────────


func _refresh_alles() -> void:
	_refresh_kategorien()
	_refresh_raum_chips()
	_refresh_optionen()
	_refresh_farben()
	_refresh_aktionen()
	_refresh_wallet()
	_refresh_preview()


func _refresh_kategorien() -> void:
	_leeren(_kategorie_liste)
	var letzter_bereich := ""
	for kat: Dictionary in KATEGORIEN:
		if str(kat["bereich"]) != letzter_bereich:
			letzter_bereich = str(kat["bereich"])
			var kopf := Label.new()
			kopf.theme_type_variation = &"CaptionLabel"
			kopf.text = I18nService.t("customize.bereich.%s" % letzter_bereich)
			_kategorie_liste.add_child(kopf)
		var btn := Button.new()
		btn.name = "Kat_%s" % str(kat["id"])
		var aktiv := str(kat["id"]) == str(_kategorie["id"])
		btn.theme_type_variation = &"ChipLeaf" if aktiv else &"AcCardButton"
		btn.text = I18nService.t("customize.kategorie.%s" % str(kat["id"]))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, AcTokens.TOUCH_FLOOR)
		btn.pressed.connect(_on_kategorie_pressed.bind(str(kat["id"])))
		_kategorie_liste.add_child(btn)


func _refresh_raum_chips() -> void:
	_leeren(_raum_chips)
	var innen := str(_kategorie["bereich"]) == "innen"
	_raum_chips.visible = innen
	if not innen:
		return
	for room_id: String in RoomDefs.ids():
		if bool(RoomDefs.room(room_id).get("outdoor", false)):
			continue
		var chip := Button.new()
		chip.name = "Raum_%s" % room_id
		chip.theme_type_variation = &"ChipLeaf" if room_id == _raum else &"AcChip"
		chip.text = I18nService.t("home.raum.%s" % room_id)
		chip.custom_minimum_size = Vector2(0, AcTokens.TOUCH_FLOOR)
		chip.pressed.connect(_on_raum_pressed.bind(room_id))
		_raum_chips.add_child(chip)


func _refresh_optionen() -> void:
	_leeren(_optionen)
	var art := str(_kategorie.get("art", ""))
	_optionen_scroll.visible = art != ""
	if art == "":
		return
	var gs := _game_state()
	var aktuelle := _aktuelle_id()
	for option: Dictionary in CustomizeCatalog.optionen(art):
		var id := str(option["id"])
		var farbe := _kachel_farbe(art, id, aktuelle)
		_optionen.add_child(_make_kachel(gs, art, option, id == aktuelle, farbe))


## Kachel-Vorschaufarbe: aktive Option in ihrer echten Farbe, Rest neutral;
## Optionen ohne eigene Farbliste (Dachformen) zeigen die Bereichsfarbe.
func _kachel_farbe(art: String, id: String, aktuelle: String) -> String:
	if id == _pending_id:
		return _pending_farbe
	var erlaubt := CustomizeCatalog.farben(art, id)
	if erlaubt.is_empty():
		return _aktuelle_farbe() if _aktuelle_farbe() != "" else "creme"
	if id == aktuelle and erlaubt.has(_aktuelle_farbe()):
		return _aktuelle_farbe()
	return str(erlaubt[0])


func _make_kachel(
	gs: Object, art: String, option: Dictionary, aktiv: bool, farb_id: String
) -> Button:
	var id := str(option["id"])
	var kachel := Button.new()
	kachel.name = "Option_%s" % id
	kachel.custom_minimum_size = TILE_SIZE
	kachel.icon = CustomizeIcons.option_preview(art, id, farb_id)
	kachel.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kachel.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	kachel.expand_icon = false
	# Das Theme tönt Button-Icons dunkelbraun (INK) — die Muster-Vorschau
	# muss aber in Originalfarben erscheinen.
	for zustand: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		kachel.add_theme_color_override(zustand, Color.WHITE)
	kachel.add_theme_color_override("icon_focus_color", Color.WHITE)
	var gekauft := HouseStyleState.ist_gekauft(gs, art, id)
	var status := I18nService.t("customize.im_besitz")
	if not gekauft:
		status = I18nService.t("customize.preis", {"n": int(option.get("preis", 0))})
	var titel := CustomizeCatalog.display_name(option, I18nService.get_locale())
	kachel.text = "%s\n%s" % [titel, status]
	kachel.add_theme_font_size_override("font_size", 13)
	var box := StyleBoxFlat.new()
	box.bg_color = Color.WHITE if gekauft else Color("#F3EDE3")
	box.set_corner_radius_all(AcTokens.RADIUS_ROW)
	box.set_border_width_all(3 if aktiv or id == _pending_id else 1)
	box.border_color = AcTokens.PINK if aktiv else AcTokens.OUTLINE_SOFT
	if id == _pending_id:
		box.border_color = AcTokens.GOLD
	box.set_content_margin_all(8)
	kachel.add_theme_stylebox_override("normal", box)
	kachel.add_theme_stylebox_override("hover", box)
	kachel.add_theme_stylebox_override("pressed", box)
	kachel.add_theme_stylebox_override("focus", box)
	kachel.pressed.connect(_on_option_pressed.bind(id))
	return kachel


func _refresh_farben() -> void:
	_leeren(_farben)
	var farben := _erlaubte_farben()
	_farben_row.visible = not farben.is_empty()
	var aktiv := _pending_farbe if _pending_id != "" else _aktuelle_farbe()
	for farb_id: Variant in farben:
		_farben.add_child(_make_swatch(str(farb_id), str(farb_id) == aktiv))


func _erlaubte_farben() -> Array:
	if _kategorie.has("farb_bereich"):
		return CustomizeCatalog.farb_wahl(str(_kategorie["farb_bereich"]))
	var art := str(_kategorie.get("art", ""))
	if art == "":
		return []
	var id := _pending_id if _pending_id != "" else _aktuelle_id()
	return CustomizeCatalog.farben(art, id)


func _make_swatch(farb_id: String, aktiv: bool) -> Button:
	var swatch := Button.new()
	swatch.name = "Farbe_%s" % farb_id
	swatch.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
	swatch.tooltip_text = I18nService.t("customize.farbe.%s" % farb_id)
	var box := StyleBoxFlat.new()
	box.bg_color = CustomizeMaterials.farbe(farb_id)
	box.set_corner_radius_all(AcTokens.RADIUS_ROW)
	box.set_border_width_all(3 if aktiv else 1)
	box.border_color = AcTokens.PINK if aktiv else AcTokens.OUTLINE_SOFT
	swatch.add_theme_stylebox_override("normal", box)
	swatch.add_theme_stylebox_override("hover", box)
	swatch.add_theme_stylebox_override("pressed", box)
	swatch.pressed.connect(_on_farbe_pressed.bind(farb_id))
	return swatch


func _refresh_aktionen() -> void:
	_zahl_row.visible = bool(_kategorie.get("zahl", false))
	if _zahl_row.visible:
		var zahl := int(HouseStyleState.style(_game_state())["haus"]["hausnummerZahl"])
		_zahl_label.text = I18nService.t("customize.hausnummer_zahl", {"n": zahl})
	if _pending_id != "":
		var art := str(_kategorie.get("art", ""))
		var preis := CustomizeCatalog.preis(art, _pending_id)
		_status_label.text = I18nService.t("customize.preis", {"n": preis})
		_kauf_button.visible = true
		return
	_kauf_button.visible = false
	_status_label.text = I18nService.t("customize.im_besitz")


func _refresh_wallet() -> void:
	var gs := _game_state()
	var coins := int(gs.get_value("economy.coins", 0)) if gs != null else 0
	_coins_label.text = I18nService.t("customize.muenzen", {"n": coins})


func _refresh_preview() -> void:
	if _preview == null:
		return
	var style := _preview_style()
	var innen := str(_kategorie["bereich"]) == "innen"
	if innen and (_preview.modus() != "innen" or _preview_raum_veraltet()):
		_preview.show_interior(_raum, style)
	elif not innen and _preview.modus() != "aussen":
		_preview.show_exterior(style)
	else:
		_preview.update_style(style)


func _preview_raum_veraltet() -> bool:
	return _preview.raum_id() != _raum


func _zeige_ergebnis(art: String, id: String, result: String) -> void:
	var def := CustomizeCatalog.def(art, id)
	var name_text := CustomizeCatalog.display_name(def, I18nService.get_locale())
	match result:
		HouseStyleState.RESULT_OK:
			AudioDirector.try_play(self, "ui_confirm")
			_toasts.show_toast(I18nService.t("customize.gekauft_toast", {"name": name_text}))
		HouseStyleState.RESULT_BROKE:
			_toasts.show_toast(I18nService.t("customize.zu_teuer"), true)
		HouseStyleState.RESULT_OWNED:
			pass
		_:
			_toasts.show_toast(I18nService.t("customize.fehler"), true)


## Kinder SOFORT aushängen und dann freigeben (Layout, s. IkeaScreen).
func _leeren(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# ── Signale ──────────────────────────────────────────────────────────────


func _on_kategorie_pressed(kategorie_id: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	set_kategorie(kategorie_id)


func _on_raum_pressed(room_id: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	set_raum(room_id)


func _on_option_pressed(id: String) -> void:
	AudioDirector.try_play(self, "ui_click")
	select_option(id)


func _on_farbe_pressed(farb_id: String) -> void:
	AudioDirector.try_play(self, "ui_toggle")
	select_farbe(farb_id)


func _on_kauf_pressed() -> void:
	buy_selected()


func _on_zufall_pressed() -> void:
	AudioDirector.try_play(self, "ui_click")
	zufall()


func _on_reset_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	reset_aktuell()


func _on_zahl_pressed(delta: int) -> void:
	AudioDirector.try_play(self, "ui_toggle")
	set_hausnummer_zahl(delta)


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
