class_name PhoneShell
extends Control
## IGohbie — die Handy-Shell (Doc E §5.1): Vollbild-Overlay im AC-Look mit
## Statusleiste (Uhr, Münzen, Akku = Goobys Energie), App-Grid aus der
## `PhoneApps`-Registry und Zurück-Geste (Wisch nach unten auf dem Gerät,
## Home-Balken oder ESC). Ein Tipp aufs Grid ersetzt den Inhalt durch die
## App, der Home-Balken geht zurück — zweimal schließt das Handy.
##
## W16/G4 P18: Das Gerät ist KEINE 380×640-Fixkarte mehr — es skaliert mit
## `ScreenShell.metrics()` (×f, `card_width`/`card_max_height`-Deckel),
## Kacheln/Geste/Schriften ziehen mit, und bei Canvas-Änderung (Rotation)
## baut die Shell die aktive Ansicht mit frischen Metriken neu. Apps koppeln
## ihre Breiten über `inhalt_breite()`/`app_label()` an die REALE
## Gerätebreite statt an die 420er-City-Bausteine (G1 ui-post §3/§4).
##
## HUD-Anbindung (Orchestrator): `hud.action_pressed` mit &"igohbie" →
## `PhoneShell.handle_hud_action(action, host, gs)` — GLEICHE Signatur wie
## `GooberandoApp.handle_hud_action`, der Aufruf lässt sich also 1:1 tauschen.

signal app_geoeffnet(app_id: String)
signal geschlossen

const HUD_ACTION := &"igohbie"
## Wischweg (Design-px, ×f), ab dem die Zurück-Geste auslöst.
const GESTE_PX := 90.0
## Design-Basis des Geräts — die echte Größe liefert `geraet_groesse()`.
const GERAET_GROESSE := Vector2(380.0, 640.0)
## Kachelbreite und Beschriftungsgröße (Design-px): „GOOBERANDO" ist das
## längste Label und muss ohne Umbruch in eine von 3 Spalten passen.
const KACHEL_BREITE := 112.0
const KACHEL_FONT := 13
## AcCard-Innenrand (Theme `_card`: content_margin 18 je Seite).
const KARTEN_RAND := 18.0
## Reserve für den vertikalen Scrollbalken des Inhalts-Scrolls.
const SCROLL_RESERVE := 16.0

var gs: Object
## Host für Vollbild-Kinder (Fotomodus) — Default: der Szenenbaum-Wurzelknoten.
var host: Node

var aktive_app := ""

var _geraet: PanelContainer
var _inhalt: VBoxContainer
var _titel: Label
var _uhr: Label
var _muenzen: Label
var _akku: ProgressBar
var _geste_y := 0.0
## Zuletzt angewandte ScreenShell-Metriken (f, canvas, insets, floor_px).
var _m: Dictionary = {}


## Handy über der laufenden Szene öffnen (eigener CanvasLayer, Theme gesetzt).
static func oeffne(scene_host: Node, game_state: Object) -> PhoneShell:
	var layer := CanvasLayer.new()
	layer.name = "IGohbieLayer"
	layer.layer = 30
	scene_host.add_child(layer)
	var shell := PhoneShell.new()
	shell.name = "PhoneShell"
	shell.gs = game_state
	shell.host = scene_host
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	shell.theme = ThemeService.theme()
	shell.geschlossen.connect(func() -> void: layer.queue_free())
	layer.add_child(shell)
	return shell


## HUD-Aktions-Handler — identische Signatur wie GooberandoApp.
static func handle_hud_action(action: StringName, scene_host: Node, game_state: Object) -> bool:
	if action != HUD_ACTION:
		return false
	oeffne(scene_host, game_state)
	return true


## ------------------------------------------ geteilte Geometrie (Apps)


## Haupt-Viewport — auch für Builder benutzbar, die VOR add_child laufen.
static func _haupt_viewport() -> Viewport:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root if loop is SceneTree else null


## Gerätegröße aus den Metriken: 380×640 ×f, gedeckelt auf die Safe-Breite
## (`card_width`) und den Karten-Höhen-Deckel — das Gerät wächst und
## schrumpft mit dem Canvas, statt fix zu kleben (G1 ui-post §3).
static func geraet_groesse(m: Dictionary) -> Vector2:
	var f: float = m["f"]
	return Vector2(
		ScreenShell.card_width(m, GERAET_GROESSE.x),
		minf(GERAET_GROESSE.y * f, ScreenShell.card_max_height(m))
	)


## Reale Innenbreite des Geräts für App-Inhalte (Canvas-px): Gerätebreite
## minus AcCard-Rand und Scroll-Reserve. Apps koppeln ihre Text-/Karten-
## breiten HIERAN statt an die 420er-City-Bausteine — das behebt die
## Breiten-Kollision aus G1 ui-post §4.
static func inhalt_breite() -> float:
	var vp := _haupt_viewport()
	if vp == null:
		return GERAET_GROESSE.x - 2.0 * KARTEN_RAND - SCROLL_RESERVE
	var m := ScreenShell.metrics(vp)
	var f: float = m["f"]
	return geraet_groesse(m).x - 2.0 * KARTEN_RAND - SCROLL_RESERVE * f


## Breite für Fließtext IN einer App-Karte (zieht den Karten-Rand ab).
static func text_breite() -> float:
	return maxf(inhalt_breite() - 2.0 * KARTEN_RAND, 120.0)


## Wurzel-Box einer Phone-App einrichten: füllt die Gerätebreite (statt
## `CitySheetBausteine.richte_box_ein` mit 420er-Fixbreite).
static func richte_app_box_ein(box: VBoxContainer) -> void:
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)


## Autowrap-Label in Gerätebreite (W3a-GOTCHA: Breite VOR add_child setzen).
static func app_label(box: Control, text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var breite := text_breite()
	l.custom_minimum_size = Vector2(breite, 0.0)
	l.size = Vector2(breite, 0.0)
	if not variation.is_empty():
		l.theme_type_variation = variation
	box.add_child(l)
	return l


## Karten-Panel (AcCard) in Gerätebreite mit eigener VBox.
static func app_karte(box: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "AcCard"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(panel)
	var inhalt := VBoxContainer.new()
	inhalt.add_theme_constant_override("separation", 6)
	panel.add_child(inhalt)
	return inhalt


## Scroll-Bereich mit innerer VBox — Höhe in Design-px, ×f skaliert und
## auf ~60 % der Gerätehöhe gedeckelt (mehr Inhalt scrollt außen mit).
static func app_scroll_liste(box: Control, hoehe_design: float) -> VBoxContainer:
	var hoehe := hoehe_design
	var vp := _haupt_viewport()
	if vp != null:
		var m := ScreenShell.metrics(vp)
		var f: float = m["f"]
		hoehe = minf(hoehe_design * f, geraet_groesse(m).y * 0.6)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, hoehe)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var liste := VBoxContainer.new()
	liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	liste.add_theme_constant_override("separation", 8)
	scroll.add_child(liste)
	return liste


## Schriften eines App-Teilbaums auf den aktuellen ×f-Faktor heben —
## Apps rufen das nach JEDEM (Neu-)Bau ihrer Kinder auf.
static func app_fonts_skalieren(box: Control) -> void:
	if box == null or not box.is_inside_tree():
		return
	var m := ScreenShell.metrics(box.get_viewport())
	ScreenShell.scale_fonts(box, m["f"])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if host == null:
		host = get_tree().root
	_m = ScreenShell.metrics(get_viewport())
	_baue_scrim()
	_baue_geraet()
	zeige_grid()
	get_viewport().size_changed.connect(_on_canvas_geaendert)


func _process(_delta: float) -> void:
	if _uhr != null:
		_uhr.text = Time.get_time_string_from_system().substr(0, 5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		zurueck()
		get_viewport().set_input_as_handled()


## Wischweg in Canvas-px (Design 90 ×f) — öffentlich für Tests.
func geste_schwelle() -> float:
	return GESTE_PX * float(_m.get("f", 1.0))


## App-Grid zeigen (Startbildschirm).
func zeige_grid() -> void:
	aktive_app = ""
	_titel.text = I18nService.t("phone.titel")
	_leere_inhalt()
	var f: float = _m.get("f", 1.0)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(4.0 * f))
	grid.add_theme_constant_override("v_separation", int(14.0 * f))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_inhalt.add_child(grid)
	for app: Dictionary in PhoneApps.grid(gs):
		grid.add_child(_baue_kachel(app))
	if Fahrdienst.ist_rettungsweg(gs):
		PhoneShell.app_label(_inhalt, I18nService.t("phone.fahrdienst.rettung"), "CaptionLabel")
	ScreenShell.scale_fonts(_geraet, f)


## Eine App öffnen (id aus PhoneApps.ids()). Outcome klingt: gesperrt =
## ui_error, Ansichtswechsel ins App-UI = ui_chip (Grammatik W16 §3).
func oeffne_app(app_id: String) -> void:
	if not PhoneApps.ist_offen(app_id, gs):
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(I18nService.t(PhoneApps.gesperrt_key(app_id, gs)))
		return
	if aktive_app != app_id:
		AudioDirector.try_play(self, "ui_chip")
	aktive_app = app_id
	_titel.text = I18nService.t(str(PhoneApps.app(app_id).get("name_key", "phone.titel")))
	_leere_inhalt()
	var inhalt := _baue_app(app_id)
	if inhalt != null:
		_inhalt.add_child(inhalt)
	ScreenShell.scale_fonts(_geraet, _m.get("f", 1.0))
	app_geoeffnet.emit(app_id)


## Zurück-Geste: aus der App aufs Grid, vom Grid aus schließt das Handy.
func zurueck() -> void:
	if aktive_app.is_empty():
		schliesse()
		return
	zeige_grid()


func schliesse() -> void:
	geschlossen.emit()


## Fotomodus starten: Handy zu, Sucher über die laufende Szene.
func starte_fotomodus() -> FotoModus:
	var modus := FotoModus.oeffne(host, gs)
	schliesse()
	return modus


## ---------------------------------------------------------------- Aufbau


func _baue_scrim() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = AcTokens.VEIL_DEEP
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)


func _baue_geraet() -> void:
	_geraet = PanelContainer.new()
	_geraet.name = "Geraet"
	_geraet.theme_type_variation = "AcCard"
	_geraet.set_anchors_preset(Control.PRESET_CENTER)
	_geraet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_geraet.grow_vertical = Control.GROW_DIRECTION_BOTH
	_geraet.gui_input.connect(_on_geraet_input)
	add_child(_geraet)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 12)
	_geraet.add_child(spalte)
	spalte.add_child(_baue_statusleiste())
	_titel = Label.new()
	_titel.theme_type_variation = "TitleLabel"
	_titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spalte.add_child(_titel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	spalte.add_child(scroll)
	_inhalt = VBoxContainer.new()
	_inhalt.name = "Inhalt"
	_inhalt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inhalt.add_theme_constant_override("separation", 12)
	scroll.add_child(_inhalt)
	spalte.add_child(_baue_home_balken())
	_wende_metrik_an()


## Metriken einsammeln und aufs Gerät anwenden (Größe + Schriften).
func _wende_metrik_an() -> void:
	_m = ScreenShell.metrics(get_viewport())
	_geraet.custom_minimum_size = PhoneShell.geraet_groesse(_m)
	_geraet.set_anchors_preset(Control.PRESET_CENTER)
	var f: float = _m["f"]
	if _akku != null:
		_akku.custom_minimum_size = Vector2(52.0, 12.0) * f
	ScreenShell.scale_fonts(_geraet, f)


## Canvas geändert (Rotation/Resize): Gerät neu vermessen und die aktive
## Ansicht mit frischen Metriken neu bauen (Muster RadioSheet W17/G4).
func _on_canvas_geaendert() -> void:
	if _geraet == null or not is_inside_tree():
		return
	_wende_metrik_an()
	if aktive_app.is_empty():
		zeige_grid()
	else:
		oeffne_app(aktive_app)


func _baue_statusleiste() -> Control:
	var zeile := HBoxContainer.new()
	zeile.name = "Statusleiste"
	zeile.add_theme_constant_override("separation", 10)
	_uhr = Label.new()
	_uhr.theme_type_variation = "CaptionLabel"
	_uhr.text = Time.get_time_string_from_system().substr(0, 5)
	zeile.add_child(_uhr)
	var luecke := Control.new()
	luecke.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(luecke)
	zeile.add_child(_icon("res://assets/ui/icons/coin.svg"))
	_muenzen = Label.new()
	_muenzen.theme_type_variation = "CaptionLabel"
	zeile.add_child(_muenzen)
	zeile.add_child(_icon("res://assets/ui/icons/energy.svg"))
	_akku = ProgressBar.new()
	_akku.theme_type_variation = "StatEnergy"
	_akku.show_percentage = false
	_akku.max_value = 100.0
	_akku.custom_minimum_size = Vector2(52.0, 12.0)
	_akku.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(_akku)
	_aktualisiere_status()
	return zeile


func _baue_home_balken() -> Control:
	var btn := SquishButton.new()
	btn.name = "HomeBalken"
	btn.theme_type_variation = "GhostButton"
	btn.text = I18nService.t("phone.zurueck")
	btn.focus_mode = Control.FOCUS_NONE
	# W16 F12: der meistgenutzte Knopf der Shell — Zurück klingt als ui_back.
	btn.pressed.connect(
		func() -> void:
			AudioDirector.try_play(btn, "ui_back")
			zurueck()
	)
	return btn


func _baue_kachel(app: Dictionary) -> Control:
	var f: float = _m.get("f", 1.0)
	# Kachelbreite an die REALE Gerätebreite koppeln (3 Spalten + Lücken
	# müssen auch auf schmalen Canvases in die Karte passen).
	var innen := _geraet.custom_minimum_size.x - 2.0 * KARTEN_RAND
	var kachel_breite := minf(KACHEL_BREITE * f, (innen - 2.0 * 4.0 * f) / 3.0)
	var app_id := str(app["id"])
	var kachel := VBoxContainer.new()
	kachel.name = "Kachel%s" % app_id.capitalize()
	kachel.add_theme_constant_override("separation", int(4.0 * f))
	kachel.custom_minimum_size = Vector2(kachel_breite, 0.0)
	var btn := SquishButton.new()
	btn.theme_type_variation = "HudIconButton"
	btn.custom_minimum_size = Vector2(minf(84.0 * f, kachel_breite), 84.0 * f)
	ScreenShell.touch_target(btn, _m)
	btn.expand_icon = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = I18nService.t(str(app["text_key"]))
	var pfad := PhoneApps.icon_pfad(app_id)
	if ResourceLoader.exists(pfad):
		btn.icon = load(pfad)
	if not bool(app["offen"]):
		btn.modulate = AcTokens.INK_FAINT
	if app_id == Fahrdienst.TAXI and Fahrdienst.ist_rettungsweg(gs):
		btn.modulate = AcTokens.GOLD
	btn.pressed.connect(func() -> void: oeffne_app(app_id))
	# W13C INSTANT: Ungelesen-Badge am App-Icon (nur InstantGooby, nur > 0).
	var badge := InstantGoobyApp.unread_badge(app_id)
	if badge != null:
		btn.add_child(badge)
	kachel.add_child(btn)
	var name_label := Label.new()
	name_label.theme_type_variation = "CaptionLabel"
	name_label.text = I18nService.t(str(app["name_key"]))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", KACHEL_FONT)
	name_label.custom_minimum_size = Vector2(kachel_breite, 0.0)
	name_label.size = Vector2(kachel_breite, 0.0)
	kachel.add_child(name_label)
	return kachel


## App-Inhalt bauen — EINE Stelle, an der Id auf UI trifft.
func _baue_app(app_id: String) -> Control:
	# W13C INSTANT: Variable statt 7. return (gdlint max-returns).
	var inhalt: Control = null
	match app_id:
		Fahrdienst.TAXI, Fahrdienst.GUBER:
			var fahrt := FahrdienstApp.new()
			fahrt.gs = gs
			fahrt.dienst = app_id
			fahrt.eingestiegen.connect(func(_d: String) -> void: schliesse())
			return fahrt
		"gooberando":
			var essen := GooberandoApp.new()
			essen.gs = gs
			return essen
		"kamera":
			var kamera := PhoneKameraApp.new()
			kamera.gs = gs
			kamera.fotomodus_gewuenscht.connect(starte_fotomodus)
			return kamera
		"freunde":
			return PhoneSocialApps.freunde(host)
		"goobypal":
			return PhoneSocialApps.goobypal(gs, _on_pal_freund)
		InstantGoobyApp.APP_ID:
			var feed := InstantGoobyApp.new()
			feed.gs = gs
			inhalt = feed
	return inhalt


## --------------------------------------------------------------- Actions


func _on_pal_freund(freund: Dictionary) -> void:
	_leere_inhalt()
	var sheet := PhoneSocialApps.pal_sheet(self, freund)
	if sheet == null:
		return
	if sheet is GoobyPalSheet:
		(sheet as GoobyPalSheet).closed.connect(func() -> void: oeffne_app("goobypal"))
		(sheet as GoobyPalSheet).toast_requested.connect(_zeige_toast)
	_inhalt.add_child(sheet)
	ScreenShell.scale_fonts(_geraet, _m.get("f", 1.0))


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		schliesse()


## Zurück-Geste: Wisch nach unten auf dem Gerät (Maus-Drag zählt auch).
## Der Schwellwert skaliert ×f — 90 Design-px wären auf dem iPhone hoch
## sonst ein ~28-pt-Mini-Wisch (G1 ui-post §3).
func _on_geraet_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_geste_y += (event as InputEventScreenDrag).relative.y
	elif event is InputEventMouseMotion:
		var maus: InputEventMouseMotion = event
		if maus.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_geste_y += maus.relative.y
		else:
			_geste_y = 0.0
	else:
		_geste_y = 0.0
		return
	if _geste_y > geste_schwelle():
		_geste_y = 0.0
		zurueck()


func _aktualisiere_status() -> void:
	if gs == null:
		return
	_muenzen.text = str(int(gs.get_value("economy.coins", 0)))
	_akku.value = float(gs.get_value("gooby.stats.energy", 100.0))


func _leere_inhalt() -> void:
	for kind in _inhalt.get_children():
		_inhalt.remove_child(kind)
		kind.queue_free()
	_aktualisiere_status()


func _icon(pfad: String) -> TextureRect:
	var rect := TextureRect.new()
	if ResourceLoader.exists(pfad):
		rect.texture = load(pfad)
	rect.custom_minimum_size = Vector2(18.0, 18.0) * float(_m.get("f", 1.0))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.self_modulate = AcTokens.INK_SOFT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
