class_name NowPlayingChip
extends PanelContainer
## „Was läuft?"-Zeile (W13/RADIO, H §6.1): Songtitel + Sender als kompakte
## AC-Karte; Überlängen laufen sanft als Endlos-Ticker durch (pure
## Offset-Funktion, Zeit über `_elapsed`/`now_ms` injizierbar).
##
## Zwei Betriebsarten:
## - INLINE (`inline = true`, RadioSheet): dauerhaft sichtbar, der Aufrufer
##   füttert set_now()/set_leer().
## - FLOATING (install_floating): hängt sich als Mini-Chip in eine vorhandene
##   (Canvas-)Ebene, hört auf `track_changed` des (Fake-)MusicDirectors und
##   blendet bei jedem neuen Radio-/Bordmusik-Track kurz ein. Bewusst über
##   den Radio-Code eingehängt, NICHT über HUD-Dateien (Ownership W13).

## Feuert, wenn der Floating-Chip wegen eines Trackwechsels sichtbar wird.
signal chip_gezeigt(text: String)

## Ticker-Tempo (px/s) — gemächlich, nichts soll hektisch wirken.
const SCROLL_PX_PRO_S := 26.0
## Lücke zwischen Text-Ende und Text-Wiederanfang im Endlos-Ticker.
const TICKER_LUECKE_PX := 48.0
## Anzeigedauer des Floating-Chips nach einem Trackstart.
const ANZEIGE_MS := 4000
const EINBLEND_S := 0.18

## INLINE-Modus (Sheet) statt Floating-Chip.
var inline := false
## MusicDirector-artiger Knoten (nur Floating; Test-Double erlaubt).
var music: Node
## Sichtbare Ticker-Breite in px (Aufrufer darf sie vor add_child anpassen).
var sicht_breite := 300.0
## Injizierbare Uhr für den Auto-Hide (Tests schieben die Zeit von Hand).
var now_ms: Callable = Callable()

var _clip: Control
var _label_a: Label
var _label_b: Label
var _glyph: Label
var _gesamt_text := ""
var _text_breite := 0.0
var _elapsed := 0.0
var _hide_at := 0


## Endlos-Ticker-Versatz (pur, testbar): passt der Text, steht er still;
## sonst wandert er mit `speed_px_s` nach links und beginnt nach
## `text_w + luecke_px` von vorn (zweite Textkopie schließt die Lücke).
static func ticker_offset(
	elapsed_s: float,
	text_w: float,
	sicht_w: float,
	speed_px_s := SCROLL_PX_PRO_S,
	luecke_px := TICKER_LUECKE_PX
) -> float:
	if text_w <= sicht_w:
		return 0.0
	return -fposmod(elapsed_s * speed_px_s, text_w + luecke_px)


## Floating-Chip in eine Ebene hängen (idempotent — vorhandener Chip wird
## wiederverwendet). `parent` ist z. B. die W3dUiLayer des Raums.
static func install_floating(parent: Node, music_node: Node) -> NowPlayingChip:
	var existing := parent.get_node_or_null("NowPlayingChip")
	if existing is NowPlayingChip:
		return existing
	var chip := NowPlayingChip.new()
	chip.name = "NowPlayingChip"
	chip.music = music_node
	chip.theme = ThemeService.theme()
	parent.add_child(chip)
	return chip


func _ready() -> void:
	if inline:
		# Inline sitzt bereits in einer AcCard — kein Karten-in-Karte-Look.
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		theme_type_variation = "AcCard"
	_baue_ui()
	if not inline:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		tooltip_text = I18nService.t("radio.was_laeuft")
		_lege_floating_aus()
		get_viewport().size_changed.connect(_lege_floating_aus)
		if music != null and music.has_signal("track_changed"):
			music.track_changed.connect(_on_track_changed)


## G4/P17: Floating-Chip UNTER die Safe-Area-Oberkante legen (fix 14 px
## landete im Hochformat unter Notch/Dynamic Island) und die Ticker-
## Sichtbreite aus der Canvas ableiten statt fixer 300 px. Läuft bei
## jedem Viewport-Resize erneut (Rotation).
func _lege_floating_aus() -> void:
	if inline or not is_inside_tree():
		return
	var vp := get_viewport()
	var f := UiScale.for_viewport(vp)
	var insets := UiScale.safe_insets_canvas(vp)
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	# Offsets EXPLIZIT nullen: set_anchors_preset(keep_offsets=false)
	# kompensiert sonst die Offsets so, dass das Rect an Ort und Stelle
	# (links oben) kleben bleibt — grow zentriert dann um die linke Kante.
	offset_left = 0.0
	offset_right = 0.0
	offset_top = float(insets["top"]) + 14.0 * f
	offset_bottom = offset_top
	if _clip != null:
		var canvas := Vector2(vp.get_visible_rect().size)
		sicht_breite = clampf(canvas.x * 0.38, 220.0, 420.0 * f)
		_clip.custom_minimum_size.x = sicht_breite


func _process(delta: float) -> void:
	_elapsed += delta
	_lege_ticker_aus()
	if not inline and visible and _hide_at > 0 and _jetzt_ms() >= _hide_at:
		visible = false


## Inline-API: aktuellen Titel + Sender anzeigen (Ticker-Format).
func set_now(titel: String, sender: String) -> void:
	_setze_text(I18nService.t("radio.ticker", {"titel": titel, "sender": sender}))


## Inline-API: Ruhetext ohne Sender (z. B. „Gerade Stille im Äther.").
func set_leer(text: String) -> void:
	_setze_text(text)


func ticker_text() -> String:
	return _gesamt_text


# ── Intern ────────────────────────────────────────────────────────────────────


func _baue_ui() -> void:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 8)
	add_child(zeile)
	_glyph = Label.new()
	_glyph.text = "♪"
	_glyph.theme_type_variation = "CaptionLabel"
	zeile.add_child(_glyph)
	_clip = Control.new()
	_clip.name = "TickerClip"
	_clip.clip_contents = true
	_clip.custom_minimum_size = Vector2(sicht_breite, 26.0)
	_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(_clip)
	_label_a = _ticker_label("TickerText")
	_label_b = _ticker_label("TickerTextKopie")
	_label_b.visible = false


func _ticker_label(label_name: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(label)
	return label


func _setze_text(text: String) -> void:
	if text == _gesamt_text:
		return
	_gesamt_text = text
	_elapsed = 0.0
	for label: Label in [_label_a, _label_b]:
		if label == null:
			continue
		label.text = text
		label.size = label.get_minimum_size()
	if _label_a != null:
		_text_breite = _label_a.get_minimum_size().x
		_clip.custom_minimum_size.y = maxf(26.0, _label_a.get_minimum_size().y)
	_lege_ticker_aus()


func _lege_ticker_aus() -> void:
	if _label_a == null or _clip == null:
		return
	var sicht_w := maxf(1.0, _clip.size.x)
	var offset := ticker_offset(_elapsed, _text_breite, sicht_w)
	_label_a.position.x = offset
	var laeuft := _text_breite > sicht_w
	_label_b.visible = laeuft
	if laeuft:
		_label_b.position.x = offset + _text_breite + TICKER_LUECKE_PX


## Trackwechsel des (Fake-)Directors: nur ECHTE Radio-/Bordmusik-Starts
## blenden den Chip ein — Kontextmusik (Raumwechsel) bleibt still.
func _on_track_changed(track_id: String) -> void:
	if inline:
		return
	if track_id.is_empty():
		visible = false
		return
	if music == null or not music.has_method("is_radio_playing"):
		return
	if not bool(music.is_radio_playing()):
		return
	var entry := MusicRegistry.entry(track_id)
	set_now(str(entry.get("title", track_id)), _sender_anzeige())
	_hide_at = _jetzt_ms() + ANZEIGE_MS
	_zeige_sanft()
	chip_gezeigt.emit(_gesamt_text)


func _zeige_sanft() -> void:
	visible = true
	if not is_inside_tree():
		return
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, EINBLEND_S)


func _sender_anzeige() -> String:
	var station_id := ""
	if music != null and music.has_method("radio_station"):
		station_id = str(music.radio_station())
	if station_id.is_empty() or station_id == MusicDirector.BORDMUSIK_STATION:
		return I18nService.t("radio.bordmusik_titel")
	for station: Dictionary in MusicRegistry.stations():
		if str(station.get("id", "")) == station_id:
			return RadioLogic.sender_name(station)
	return station_id


func _jetzt_ms() -> int:
	if now_ms.is_valid():
		return int(now_ms.call())
	return Time.get_ticks_msec()
