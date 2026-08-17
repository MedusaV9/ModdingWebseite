class_name BoardingPass
extends PanelContainer
## Boarding-Pass-Sheet (W13B, Doc H §2.4): nach dem Einsteigen ins Taxi
## zeigt die Reise-App diese hübsche Karte — GOOBY-AIR-Kopfstreifen, Ziel,
## Gate-Gag "3¾", Sitz "1A — Fensterplatz", Flausch-Klasse, Abriss-Kante
## und ein Barcode-Gag aus Strichen (PUR + DETERMINISTISCH aus der Ziel-Id).
## Der "Gute Reise!"-Knopf startet über den injizierten Callback die
## BESTEHENDE Abflug-Cutscene (reise_app.gd ruft sie nur auf). Farben NUR
## aus AcTokens; das Datenpaket (`daten()`) ist pur und einzeln testbar.
##
## G4/P16 (ui-reisen NIEDRIG 12): Kartenbreite klemmt an die Safe-Area
## (`ScreenShell.card_width`), der Barcode passt sich der Kartenbreite an
## (kein Überlauf mehr auf schmalen Geräten) und die Schriften skalieren
## mit UiScale. Als Eigenbau-Overlay spielt die Karte ui_open/ui_close und
## meldet sich am PanelStack an (Back-Geste = „Gute Reise!“ — das Taxi ist
## bereits bestiegen, es gibt nur den Weg nach vorn).

## Barcode-Länge in "Strichen".
const BARCODE_LAENGE := 28
## Erlaubte Barcode-Glyphen: Vollbalken, Halbbalken, Haarstrich.
const BARCODE_ZEICHEN := ["█", "▌", "▏"]
## Wunschbreite der Karte in Design-px (klemmt an die Safe-Area).
const BASIS_BREITE := 380.0
## Barcode-Basisgröße in Design-px (wird auf die Kartenbreite eingepasst).
const BARCODE_PX := 22.0

static var _mono_cache: Font = null

var _box: VBoxContainer = null
var _barcode_label: Label = null
var _gute_reise := Callable()

## ------------------------------------------------------ pure Daten


## Datenpaket für die Karte ({} bei unbekanntem Ziel). Pur: Zeit kommt als
## now_ms herein, Zufall gibt es nicht (Barcode deterministisch je Ziel).
static func daten(ziel_id: String, now_ms: int) -> Dictionary:
	var info := ReiseLogic.bestaetigung(ziel_id, 0)
	if info.is_empty():
		return {}
	return {
		"ziel_id": ziel_id,
		"name_key": str(info["name_key"]),
		"tage": int(info["tage"]),
		"barcode": barcode(ziel_id),
		"datum_ms": now_ms,
	}


## Barcode-Gag: deterministische Strichfolge aus der Ziel-Id (LCG-Streuung).
static func barcode(ziel_id: String, laenge := BARCODE_LAENGE) -> String:
	var h := 7
	var text := "GOOBYAIR|" + ziel_id
	for i in text.length():
		h = (h * 31 + text.unicode_at(i)) % 1000003
	var out := ""
	for _i in laenge:
		h = int((h * 1103515245 + 12345) % 2147483647)
		out += BARCODE_ZEICHEN[h % BARCODE_ZEICHEN.size()]
	return out


## ------------------------------------------------------ UI


## Karte als eigener CanvasLayer über `host` öffnen. `on_gute_reise` läuft
## NACH dem Schließen des Layers (reise_app startet damit die Cutscene).
static func oeffne(
	host: Node, ziel_id: String, now_ms: int, on_gute_reise: Callable
) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "BoardingPassLayer"
	host.add_child(layer)
	var wurzel := Control.new()
	wurzel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	wurzel.theme = ThemeService.theme()
	layer.add_child(wurzel)
	var schleier := ColorRect.new()
	schleier.color = AcTokens.VEIL
	schleier.set_anchors_preset(Control.PRESET_FULL_RECT)
	wurzel.add_child(schleier)
	var karte := BoardingPass.new()
	karte.setup(ziel_id, now_ms, on_gute_reise)
	karte.set_anchors_preset(Control.PRESET_CENTER)
	karte.grow_horizontal = Control.GROW_DIRECTION_BOTH
	karte.grow_vertical = Control.GROW_DIRECTION_BOTH
	wurzel.add_child(karte)
	# Eigenbau-Overlay (Grammatik): ui_open + PanelStack selbst nachbauen —
	# die Back-Geste landet damit auf close() statt hinter der Karte.
	AudioDirector.try_play(wurzel, "ui_open")
	PanelStack.push(karte)
	UiMotion.pop_in(karte)
	return layer


## Karteninhalt bauen (vor add_child aufrufen). Breite/Schrift klemmt
## erst `_ready` (braucht den Viewport für Metrics).
func setup(ziel_id: String, now_ms: int, on_gute_reise: Callable) -> void:
	name = "BoardingPassKarte"
	theme_type_variation = &"AcCardLg"
	_gute_reise = on_gute_reise
	var paket := daten(ziel_id, now_ms)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(BASIS_BREITE, 0.0)
	_box = box
	add_child(box)

	var streifen := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.PINK
	sb.set_corner_radius_all(AcTokens.RADIUS_ROW)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	streifen.add_theme_stylebox_override("panel", sb)
	box.add_child(streifen)
	var kopf := VBoxContainer.new()
	kopf.add_theme_constant_override("separation", 0)
	streifen.add_child(kopf)
	var titel := Label.new()
	titel.name = "PassTitel"
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("reisepass.pass.titel")
	titel.add_theme_color_override("font_color", AcTokens.WHITE)
	kopf.add_child(titel)
	var airline := Label.new()
	airline.name = "PassAirline"
	airline.theme_type_variation = &"CaptionLabel"
	airline.text = I18nService.t("reisepass.pass.airline")
	airline.add_theme_color_override("font_color", AcTokens.WHITE)
	kopf.add_child(airline)

	if paket.is_empty():
		return
	var raster := GridContainer.new()
	raster.name = "PassFelder"
	raster.columns = 2
	raster.add_theme_constant_override("h_separation", 24)
	raster.add_theme_constant_override("v_separation", 4)
	box.add_child(raster)
	_feld(raster, "Ziel", I18nService.t("reisepass.pass.ziel"), I18nService.t(paket["name_key"]))
	_feld(
		raster,
		"Gate",
		I18nService.t("reisepass.pass.gate"),
		I18nService.t("reisepass.pass.gate_wert")
	)
	_feld(
		raster,
		"Sitz",
		I18nService.t("reisepass.pass.sitz"),
		I18nService.t("reisepass.pass.sitz_wert")
	)
	_feld(
		raster,
		"Klasse",
		I18nService.t("reisepass.pass.klasse"),
		I18nService.t("reisepass.pass.klasse_wert")
	)
	var gepaeck := Label.new()
	gepaeck.name = "PassGepaeck"
	gepaeck.theme_type_variation = &"CaptionLabel"
	gepaeck.text = I18nService.t("reisepass.pass.gepaeck")
	gepaeck.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(gepaeck)
	var hinweis := Label.new()
	hinweis.name = "PassHinweis"
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("reisepass.pass.hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hinweis)

	var abriss := Label.new()
	abriss.name = "AbrissKante"
	abriss.text = "✂" + " ·".repeat(24)
	abriss.add_theme_color_override("font_color", AcTokens.INK_FAINT)
	abriss.clip_text = true
	box.add_child(abriss)
	var barcode_label := Label.new()
	barcode_label.name = "Barcode"
	barcode_label.text = str(paket["barcode"])
	barcode_label.add_theme_font_override("font", _mono_font())
	barcode_label.add_theme_font_size_override("font_size", int(BARCODE_PX))
	barcode_label.add_theme_color_override("font_color", AcTokens.INK)
	barcode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# G4/P16: Barcode wird auf die Kartenbreite EINGEPASST (s. _relayout) —
	# scale_fonts soll ihn nicht noch einmal anfassen; clip als Notnagel.
	barcode_label.clip_text = true
	barcode_label.set_meta(ScreenShell.META_FONT_SKIP, true)
	_barcode_label = barcode_label
	box.add_child(barcode_label)

	var knopf := SquishButton.new()
	knopf.name = "GuteReiseBtn"
	knopf.theme_type_variation = &"BtnLeaf"
	knopf.text = I18nService.t("reisepass.pass.gute_reise")
	knopf.custom_minimum_size = Vector2(0.0, 52.0)
	knopf.focus_mode = Control.FOCUS_NONE
	knopf.pressed.connect(_on_gute_reise_pressed)
	box.add_child(knopf)


## Breite/Schrift klemmen, sobald der Viewport da ist; Rotation zieht nach.
func _ready() -> void:
	_relayout()
	get_viewport().size_changed.connect(_relayout)


## G4/P16 (ui-reisen NIEDRIG 12): Kartenbreite = card_width (Safe-Area-
## Klemmung), Barcode-Font passt sich der Breite an, Theme-Schriften × f.
func _relayout() -> void:
	var vp := get_viewport()
	if vp == null or _box == null:
		return
	var m := ScreenShell.metrics(vp)
	var f: float = m["f"]
	var breite := ScreenShell.card_width(m, BASIS_BREITE)
	_box.custom_minimum_size = Vector2(breite, 0.0)
	if _barcode_label != null:
		var mess := (
			_mono_font()
			. get_string_size(_barcode_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(BARCODE_PX))
			. x
		)
		var px := BARCODE_PX
		if mess > 0.0:
			px = clampf(BARCODE_PX * (breite - 8.0) / mess, 12.0, BARCODE_PX * f)
		_barcode_label.add_theme_font_size_override("font_size", int(px))
	var knopf: Control = _box.get_node_or_null("GuteReiseBtn")
	if knopf != null:
		knopf.custom_minimum_size = Vector2(0.0, roundf(52.0 * f))
		ScreenShell.touch_target(knopf, m)
	ScreenShell.scale_fonts(self, f)


## PanelStack-Vertrag (Back-Geste): die Reise ist beim Boarding-Pass schon
## bezahlt UND bestiegen — Schließen heißt deshalb „Gute Reise!“.
func close() -> void:
	_on_gute_reise_pressed()


## Erst den Layer wegräumen, DANN der Callback (die Cutscene übernimmt den
## Bildschirm — die Karte soll nicht darüber hängen bleiben).
func _on_gute_reise_pressed() -> void:
	PanelStack.remove(self)
	AudioDirector.try_play(self, "ui_close")
	var layer := _mein_layer()
	if layer != null:
		layer.queue_free()
	if _gute_reise.is_valid():
		_gute_reise.call()


func _mein_layer() -> CanvasLayer:
	var node: Node = self
	while node != null:
		if node is CanvasLayer:
			return node
		node = node.get_parent()
	return null


func _feld(raster: GridContainer, feld_name: String, key_text: String, wert_text: String) -> void:
	var key := Label.new()
	key.theme_type_variation = &"SoftLabel"
	key.text = key_text
	raster.add_child(key)
	var wert := Label.new()
	wert.name = "PassWert%s" % feld_name
	wert.theme_type_variation = &"HeadlineLabel"
	wert.text = wert_text
	raster.add_child(wert)


static func _mono_font() -> Font:
	if _mono_cache == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(
			["JetBrains Mono", "DejaVu Sans Mono", "Menlo", "Consolas", "monospace"]
		)
		_mono_cache = sys
	return _mono_cache
