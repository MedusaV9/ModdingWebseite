class_name BoardingPass
extends PanelContainer
## Boarding-Pass-Sheet (W13B, Doc H §2.4): nach dem Einsteigen ins Taxi
## zeigt die Reise-App diese hübsche Karte — GOOBY-AIR-Kopfstreifen, Ziel,
## Gate-Gag "3¾", Sitz "1A — Fensterplatz", Flausch-Klasse, Abriss-Kante
## und ein Barcode-Gag aus Strichen (PUR + DETERMINISTISCH aus der Ziel-Id).
## Der "Gute Reise!"-Knopf startet über den injizierten Callback die
## BESTEHENDE Abflug-Cutscene (reise_app.gd ruft sie nur auf). Farben NUR
## aus AcTokens; das Datenpaket (`daten()`) ist pur und einzeln testbar.

## Barcode-Länge in "Strichen".
const BARCODE_LAENGE := 28
## Erlaubte Barcode-Glyphen: Vollbalken, Halbbalken, Haarstrich.
const BARCODE_ZEICHEN := ["█", "▌", "▏"]

static var _mono_cache: Font = null

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
	UiMotion.pop_in(karte)
	return layer


## Karteninhalt bauen (vor add_child aufrufen).
func setup(ziel_id: String, now_ms: int, on_gute_reise: Callable) -> void:
	name = "BoardingPassKarte"
	theme_type_variation = &"AcCardLg"
	var paket := daten(ziel_id, now_ms)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(380.0, 0.0)
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
	barcode_label.add_theme_font_size_override("font_size", 22)
	barcode_label.add_theme_color_override("font_color", AcTokens.INK)
	barcode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(barcode_label)

	var knopf := SquishButton.new()
	knopf.name = "GuteReiseBtn"
	knopf.theme_type_variation = &"BtnLeaf"
	knopf.text = I18nService.t("reisepass.pass.gute_reise")
	knopf.custom_minimum_size = Vector2(0.0, 52.0)
	knopf.focus_mode = Control.FOCUS_NONE
	knopf.pressed.connect(_on_gute_reise_pressed.bind(on_gute_reise))
	box.add_child(knopf)


## Erst den Layer wegräumen, DANN den Callback (die Cutscene übernimmt den
## Bildschirm — die Karte soll nicht darüber hängen bleiben).
func _on_gute_reise_pressed(on_gute_reise: Callable) -> void:
	var layer := _mein_layer()
	if layer != null:
		layer.queue_free()
	if on_gute_reise.is_valid():
		on_gute_reise.call()


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
