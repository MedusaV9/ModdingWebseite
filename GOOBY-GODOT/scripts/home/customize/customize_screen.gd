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
## Inhaltsspalte W16: eigene Grid-Basis — die 660er-Standardspalte würde das
## Zwei-Spalten-Layout (Kategorien + Vorschau/Optionen) quetschen.
const SPALTE_BASIS := 920.0

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
## G7: Fade-Affordance + Boden-Polster (Kategorie-Liste, rechte Spalte).
var _kat_fade: ScrollFade
var _kat_polster: MarginContainer
var _rechts_fade: ScrollFade
var _raum_chips: HFlowContainer
var _optionen: HBoxContainer
var _optionen_scroll: ScrollContainer
var _farben: HFlowContainer
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
## FB3: Metrik-Pass (Safe-Area/Touch-Floor/UiScale) bei jedem Resize.
var _rows_box: VBoxContainer
var _back_btn: Button
## G4-Nachfix: Kopfzeilen-Teile für den bedarfsbasierten Umbruch — das
## Münzen-Label wandert auf schmalen Spalten in die eigene Zeile.
var _header_zeile: HBoxContainer
var _wallet_zeile: HBoxContainer
var _title_label: Label
var _kat_spalte: VBoxContainer
var _options_panel: PanelContainer
var _f := 1.0
## Kachel-Faktor: wie _f, aber in flachen Quer-Canvases gedeckelt, damit
## die Options-Zeile nicht die halbe Höhe frisst.
var _tile_f := 1.0
var _floor := float(AcTokens.TOUCH_FLOOR)
var _stagger_key := ""


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
	_apply_metrics()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_refresh_alles()


func _on_viewport_resized() -> void:
	if not is_inside_tree():
		return
	_apply_metrics()
	_refresh_alles()


## FB3/W16: Safe-Area + zentrale Skalierung + Touch-Floor + Inhaltsspalte —
## der Inhalt sitzt zentriert + breiten-gedeckelt (Grid-Basis 920), der
## AcWallpaper-Hintergrund läuft weiter vollflächig durch.
func _apply_metrics() -> void:
	if _rows_box == null or not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	_f = m["f"]
	_floor = m["floor_px"]
	var canvas: Vector2 = m["canvas"]
	# Kacheln in flachen Quer-Canvases deckeln (Höhe ist dort knapp).
	_tile_f = minf(_f, maxf(1.0, canvas.y / 820.0))
	ScreenShell.content_frame(_rows_box, m, SPALTE_BASIS)
	var spalte := ScreenShell.content_width(m, SPALTE_BASIS)
	if _back_btn != null:
		ScreenShell.touch_target(_back_btn, m)
	# Kategorie-Spalte bezieht ihr Budget aus der SPALTEN-Breite (vorher
	# volle Canvas-Breite — die linke Liste wäre relativ zu breit geworden).
	_kat_spalte.custom_minimum_size = Vector2(minf(LIST_WIDTH * _f, spalte * 0.3), 0.0)
	# G7: Fade-Kanten + Boden-Polster der Kategorie-Liste skalieren mit f.
	if _kat_fade != null:
		_kat_fade.kanten_hoehe(ScrollFade.KANTE * _f)
		_kat_polster.add_theme_constant_override("margin_bottom", roundi(ScrollFade.KANTE * _f))
	if _rechts_fade != null:
		_rechts_fade.kanten_hoehe(ScrollFade.KANTE * _f)
	_optionen_scroll.custom_minimum_size = Vector2(0.0, TILE_SIZE.y * _tile_f + 18.0)
	_kauf_button.custom_minimum_size = Vector2(150.0 * _f, _floor)
	ScreenShell.scale_fonts(self, _f)
	_layout_header(m)
	# Font-Overrides aus scale_fonts propagieren DEFERRED (THEME_CHANGED) —
	# bereits geshapte Labels melden im selben Frame noch ALTE Minbreiten.
	# Ein nachgezogener Pass misst nach dem Flush die echten Werte.
	call_deferred("_layout_header_nachziehen")
	_fit_preview(m)


## G4-Nachfix: FB3-Befund hoch (Zentrum −2,5 px) — Zurück + Titel + Münzen
## verlangten minimal mehr Minbreite als die Spalten-Klemme, die Spalte
## rutschte aus dem Safe-Zentrum. Das Münzen-Label wandert deshalb in die
## eigene Zeile, sobald die Kopfzeile nicht mehr in die Spalte passt.
func _layout_header(m: Dictionary) -> void:
	if _header_zeile == null or _wallet_zeile == null:
		return
	var sep := float(_header_zeile.get_theme_constant("separation"))
	var noetig := (
		_back_btn.get_combined_minimum_size().x
		+ _title_label.get_combined_minimum_size().x
		+ _coins_label.get_combined_minimum_size().x
		+ 2.0 * sep
	)
	var unten := noetig > ScreenShell.content_width(m, SPALTE_BASIS)
	if unten != (_coins_label.get_parent() == _wallet_zeile):
		_coins_label.get_parent().remove_child(_coins_label)
		(_wallet_zeile if unten else _header_zeile).add_child(_coins_label)
	_wallet_zeile.visible = unten


## Deferred-Pass des Kopf-Umbruchs mit FRISCHEN Metriken (s. _apply_metrics).
func _layout_header_nachziehen() -> void:
	if is_inside_tree():
		_layout_header(ScreenShell.metrics(get_viewport()))


## G7: Deferred-Pass des Vorschau-Budgets — im Bau-Frame melden HFlow-
## Zeilen (Farb-Swatches!) noch ALTE Minima; die Vorschau bekam zu viel
## Höhe und drückte die Aktionen unter den Canvas (Befund quer 2868×1320).
func _fit_preview_nachziehen() -> void:
	if is_inside_tree():
		_fit_preview(ScreenShell.metrics(get_viewport()))


## Vorschau-Höhe = Budget, das NACH Chips + Options-Panel übrig bleibt —
## reicht es nicht, scrollt die rechte Spalte, statt dass Farben/Aktionen
## aus dem Canvas laufen.
func _fit_preview(m: Dictionary) -> void:
	if _preview == null or _options_panel == null:
		return
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	var body_h := (
		canvas.y - float(insets["top"]) - float(insets["bottom"]) - 28.0 * _f - _floor - 10.0
	)
	var chips_h := _floor + 8.0 if _raum_chips != null and _raum_chips.visible else 0.0
	var panel_h := _options_panel.get_combined_minimum_size().y
	var prev_min := clampf(body_h - chips_h - panel_h - 52.0, 120.0, canvas.y * 0.32)
	_preview.custom_minimum_size = Vector2(0.0, prev_min)


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
		call_deferred("_swatch_pop", farb_id)
		return
	var gs := _game_state()
	if _kategorie.has("farb_bereich") and not _kategorie.has("art"):
		HouseStyleState.set_haus(gs, str(_kategorie["farb_key"]), farb_id)
	else:
		_wende_option_an(_aktuelle_id(), farb_id)
	_refresh_alles()
	call_deferred("_swatch_pop", farb_id)


## G7: Mini-Pop auf dem frisch gewählten Swatch — deferred, weil der HFlow
## erst nach dem Sort die Pivot-Größe kennt. RM-Gate sitzt in UiMotion.
func _swatch_pop(farb_id: String) -> void:
	if _farben == null:
		return
	var swatch := _farben.get_node_or_null("Farbe_%s" % farb_id)
	if swatch is Control:
		UiMotion.bounce(swatch as Control, 1.12)


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
	# G7: Würfel-Spaß — die Vorschau wackelt kurz mit (RM-Gate in UiMotion).
	if _preview != null:
		_preview.wackeln()


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
	_rows_box = VBoxContainer.new()
	_rows_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rows_box.add_theme_constant_override("separation", 10)
	add_child(_rows_box)
	_rows_box.add_child(_build_header())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	_rows_box.add_child(body)
	body.add_child(_build_kategorie_spalte())
	body.add_child(_build_rechte_spalte())
	_toasts = ToastLayer.new()
	add_child(_toasts)


func _build_header() -> Control:
	# G4-Nachfix: Kopf als 2-Zeilen-Gerüst — Zeile 1 wie gehabt, Zeile 2
	# nimmt das Münzen-Label auf, wenn die Kopfzeile nicht in die Spalte
	# passt (_layout_header; FB3-Befund hoch: Kopf-Minbreite drückte die
	# Spalte 2,5 px aus dem Safe-Zentrum).
	var kopf := VBoxContainer.new()
	kopf.add_theme_constant_override("separation", 4)
	_header_zeile = HBoxContainer.new()
	_header_zeile.add_theme_constant_override("separation", 10)
	kopf.add_child(_header_zeile)
	# Audio-Grammatik: jeder interaktive Knopf ist ein SquishButton
	# (Tap-Haptik + Press-Squish zentral, nie Button.new()).
	_back_btn = SquishButton.new()
	_back_btn.name = "BackButton"
	_back_btn.theme_type_variation = &"GhostButton"
	_back_btn.text = I18nService.t("customize.back")
	_back_btn.pressed.connect(_on_back_pressed)
	_header_zeile.add_child(_back_btn)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"TitleLabel"
	_title_label.text = I18nService.t("customize.title")
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_zeile.add_child(_title_label)
	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.theme_type_variation = &"HeadlineLabel"
	_header_zeile.add_child(_coins_label)
	_wallet_zeile = HBoxContainer.new()
	_wallet_zeile.name = "WalletZeile"
	_wallet_zeile.alignment = BoxContainer.ALIGNMENT_END
	_wallet_zeile.visible = false
	kopf.add_child(_wallet_zeile)
	return kopf


func _build_kategorie_spalte() -> Control:
	_kat_spalte = VBoxContainer.new()
	var column := _kat_spalte
	column.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	column.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.name = "KategorieScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# G7-Affordance: der User-Screenshot zeigte „Briefkasten“ hart halbiert,
	# ohne Hinweis dass die Liste scrollt — Fade-Kante + Boden-Polster (der
	# letzte Eintrag steht am Scroll-Ende frei, _apply_metrics skaliert).
	_kat_fade = ScrollFade.um(scroll)
	_kat_fade.name = "KategorieFade"
	column.add_child(_kat_fade)
	_kat_polster = MarginContainer.new()
	_kat_polster.name = "KategoriePolster"
	_kat_polster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kat_polster.add_theme_constant_override("margin_bottom", int(ScrollFade.KANTE))
	scroll.add_child(_kat_polster)
	_kategorie_liste = VBoxContainer.new()
	_kategorie_liste.name = "KategorieListe"
	_kategorie_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kategorie_liste.add_theme_constant_override("separation", 8)
	_kat_polster.add_child(_kategorie_liste)
	return column


func _build_rechte_spalte() -> Control:
	# FB3: die Spalte scrollt vertikal — vorher drückte ihre Minimalhöhe
	# (Chips + Vorschau + Options-Panel) in Quer-Formaten den ganzen Body
	# unter den Canvas-Rand (Farben/Zufall/Zurücksetzen unerreichbar).
	var scroll := ScrollContainer.new()
	scroll.name = "RechteSpalteScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# G7: auch hier Fade-Affordance — läuft die Spalte über (Innen-
	# Kategorien im flachen Quer), lädt die Kante zum Scrollen ein.
	_rechts_fade = ScrollFade.um(scroll)
	_rechts_fade.name = "RechteSpalteFade"
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	# HFlow: Raum-Chips brechen im Hochformat um, statt rechts rauszulaufen.
	_raum_chips = HFlowContainer.new()
	_raum_chips.name = "RaumChips"
	_raum_chips.add_theme_constant_override("h_separation", 6)
	_raum_chips.add_theme_constant_override("v_separation", 6)
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
	return _rechts_fade


func _build_options_panel() -> Control:
	var panel := PanelContainer.new()
	_options_panel = panel
	panel.theme_type_variation = &"AcCard"
	var rows := VBoxContainer.new()
	# G7: mehr Luft zwischen Kachel-Zeile, Farbzeile und Aktionen — der
	# User-Screenshot zeigte „Im Besitz“ + Zufällig/Zurücksetzen gequetscht.
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)
	_optionen_scroll = ScrollContainer.new()
	_optionen_scroll.name = "OptionenScroll"
	_optionen_scroll.custom_minimum_size = Vector2(0, TILE_SIZE.y * _f + 18)
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
	# HFlow: Swatches umbrechen — im Hochformat drückte die Zeile sonst die
	# ganze Spalte über den rechten Canvas-Rand.
	_farben = HFlowContainer.new()
	_farben.name = "Farben"
	_farben.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_farben.add_theme_constant_override("h_separation", 6)
	_farben.add_theme_constant_override("v_separation", 6)
	_farben_row.add_child(_farben)
	return _farben_row


## Hausnummern-Zahl (-/Nr./+) — lebt IN der Aktions-Zeile, damit die Höhe
## des Panels konstant bleibt (Mobile: 576er-Design-Höhe).
func _build_zahl_row() -> Control:
	_zahl_row = HBoxContainer.new()
	_zahl_row.name = "ZahlRow"
	_zahl_row.add_theme_constant_override("separation", 8)
	var minus := SquishButton.new()
	minus.name = "ZahlMinus"
	minus.theme_type_variation = &"AcChip"
	minus.text = "-"
	minus.custom_minimum_size = Vector2(_floor, _floor)
	minus.pressed.connect(_on_zahl_pressed.bind(-1))
	_zahl_row.add_child(minus)
	_zahl_label = Label.new()
	_zahl_label.name = "ZahlLabel"
	_zahl_label.theme_type_variation = &"HeadlineLabel"
	_zahl_row.add_child(_zahl_label)
	var plus := SquishButton.new()
	plus.name = "ZahlPlus"
	plus.theme_type_variation = &"AcChip"
	plus.text = "+"
	plus.custom_minimum_size = Vector2(_floor, _floor)
	plus.pressed.connect(_on_zahl_pressed.bind(1))
	_zahl_row.add_child(plus)
	return _zahl_row


func _build_aktions_row() -> Control:
	# HFlow: Kaufen/Zufall/Zurücksetzen brechen im Hochformat um.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	row.add_child(_build_zahl_row())
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	# G7: Title statt Headline — die 34er-Headline blähte die Aktionszeile
	# im flachen Querformat auf ~90 px und quetschte den Rest der Spalte.
	_status_label.theme_type_variation = &"TitleLabel"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_status_label)
	_kauf_button = SquishButton.new()
	_kauf_button.name = "KaufButton"
	_kauf_button.theme_type_variation = &"PrimaryButton"
	_kauf_button.text = I18nService.t("customize.kaufen")
	_kauf_button.custom_minimum_size = Vector2(150, _floor)
	_kauf_button.pressed.connect(_on_kauf_pressed)
	row.add_child(_kauf_button)
	var zufall_btn := SquishButton.new()
	zufall_btn.name = "ZufallButton"
	zufall_btn.theme_type_variation = &"AcChip"
	zufall_btn.text = I18nService.t("customize.zufall")
	zufall_btn.custom_minimum_size = Vector2(0, _floor)
	zufall_btn.pressed.connect(_on_zufall_pressed)
	row.add_child(zufall_btn)
	var reset_btn := SquishButton.new()
	reset_btn.name = "ResetButton"
	reset_btn.theme_type_variation = &"GhostButton"
	reset_btn.text = I18nService.t("customize.reset")
	reset_btn.custom_minimum_size = Vector2(0, _floor)
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
	# FB3: neu gebaute Listen bekommen die zentrale Schrift-Skala; die
	# Options-Kacheln blenden gestaffelt ein (Web-Stagger) — aber nur beim
	# KATEGORIE-Wechsel, nicht bei jedem Antippen einer Option.
	if is_inside_tree() and _rows_box != null:
		ScreenShell.scale_fonts(_rows_box, _f)
	var stagger_key := "%s/%s" % [str(_kategorie["id"]), _raum]
	if _optionen != null and stagger_key != _stagger_key:
		_stagger_key = stagger_key
		UiMotion.stagger_in(_optionen.get_children(), 0.02)
	# Panel-Inhalt hat sich geändert (Farben/Zahl-Zeile) → Vorschau-Budget
	# neu — sofort UND deferred (s. _fit_preview_nachziehen).
	if is_inside_tree():
		_fit_preview(ScreenShell.metrics(get_viewport()))
		call_deferred("_fit_preview_nachziehen")


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
		var btn := SquishButton.new()
		btn.name = "Kat_%s" % str(kat["id"])
		var aktiv := str(kat["id"]) == str(_kategorie["id"])
		btn.theme_type_variation = &"ChipLeaf" if aktiv else &"AcCardButton"
		btn.text = I18nService.t("customize.kategorie.%s" % str(kat["id"]))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, _floor)
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
		var chip := SquishButton.new()
		chip.name = "Raum_%s" % room_id
		chip.theme_type_variation = &"ChipLeaf" if room_id == _raum else &"AcChip"
		chip.text = I18nService.t("home.raum.%s" % room_id)
		# Floor auf BEIDEN Achsen — „Bad“ unterschreitet sonst die Breite.
		chip.custom_minimum_size = Vector2(_floor, _floor)
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
	var kachel := SquishButton.new()
	kachel.name = "Option_%s" % id
	kachel.custom_minimum_size = TILE_SIZE * _tile_f
	kachel.icon = CustomizeIcons.option_preview(art, id, farb_id)
	kachel.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kachel.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	# G7-Leitformat-Fix: expand_icon=true — das fixe 96-px-Icon sprengte
	# sonst den _tile_f-Deckel (Options-Zeile fraß im flachen Querformat
	# 221 statt ~150 px Höhe und drückte die Aktionen unter den Canvas).
	kachel.expand_icon = true
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
	# Kachel-Schrift folgt dem KACHEL-Deckel (_tile_f), nicht dem globalen
	# f — sonst hebelt der Text den gedeckelten Platz wieder aus (s. o.).
	kachel.set_meta(ScreenShell.META_FONT_SKIP, true)
	kachel.add_theme_font_size_override("font_size", int(maxf(roundf(13.0 * _tile_f), 10.0)))
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
	var swatch := SquishButton.new()
	swatch.name = "Farbe_%s" % farb_id
	# FB3: Swatches halten den PHYSISCHEN Touch-Floor (waren 36 Design-px).
	swatch.custom_minimum_size = Vector2.ONE * maxf(SWATCH_SIZE * _f, _floor)
	swatch.tooltip_text = I18nService.t("customize.farbe.%s" % farb_id)
	var box := StyleBoxFlat.new()
	box.bg_color = CustomizeMaterials.farbe(farb_id)
	box.set_corner_radius_all(AcTokens.RADIUS_ROW)
	# G7: gewählter Swatch deutlich — dicker Rahmen + weicher Pink-Schein.
	box.set_border_width_all(4 if aktiv else 1)
	box.border_color = AcTokens.PINK if aktiv else AcTokens.OUTLINE_SOFT
	if aktiv:
		box.shadow_color = Color(AcTokens.PINK, 0.35)
		box.shadow_size = 4
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
	# G4-Nachfix: neuer Text = neue Minbreite — Kopf-Umbruch nachziehen
	# (sofort + deferred, s. _apply_metrics zu den Font-Overrides).
	if is_inside_tree():
		_layout_header(ScreenShell.metrics(get_viewport()))
		call_deferred("_layout_header_nachziehen")


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
			# Audio-Grammatik: abgeschlossene Münz-AUSGABE = ui_buy (nicht
			# ui_confirm) + Erfolgs-Haptik am Kauf-Moment.
			AudioDirector.try_play(self, "ui_buy")
			Haptics.success(self)
			_toasts.show_toast(I18nService.t("customize.gekauft_toast", {"name": name_text}))
		HouseStyleState.RESULT_BROKE:
			AudioDirector.try_play(self, "ui_error")
			Haptics.warn(self)
			_toasts.show_toast(I18nService.t("customize.zu_teuer"), true)
		HouseStyleState.RESULT_OWNED:
			pass
		_:
			AudioDirector.try_play(self, "ui_error")
			Haptics.warn(self)
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
	# Audio-Grammatik: Palette = Auswahl-Chip (ui_chip), kein An-Aus-Schalter.
	AudioDirector.try_play(self, "ui_chip")
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
	# Audio-Grammatik: Stepper-Mikro-Schritt = ui_tick.
	AudioDirector.try_play(self, "ui_tick")
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
