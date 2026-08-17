class_name RanchLoadingScreen
extends Control
## RW-8 — Vollbild-Ladebildschirm der langen Reisen (Stadt->Ranch, Zonen,
## Turnier, Besuch). Wird vom LoadingVeil lazy eingehaengt, wenn
## LoadingScreenRules.ist_lange_reise() zutrifft; kurze Wege behalten die
## kleine Karte.
##
## Aufbau (komplett in Code, kein tscn — vermeidet Kollisionen mit der
## FROZEN Veil-Szene): Artwork als Cover-Hintergrund mit sanftem Ken-Burns-
## Drift, GOOBY-RANCH-Logo oben, unten Tipp + Ladebalken mit ECHTEM
## threaded-Fortschritt (kein Fake — der Router speist set_progress).
## W16/G4: die Anzeigen konsumieren die G2-Karten-Bausteine des Alt-Web-
## Looks — der Balken ist der Teal-Verlaufsbalken (LoadingVeilBalken), die
## Laedt-Zeile zeigt „Laedt… NN%“ (Prozent nur bei echtem Fortschritt,
## Web-Regel), und unten rechts huepft der runde Motiv-Sticker
## (LoadingVeilSticker, winkender Gooby) statt des alten Vektor-Goobys.
## Reduced Motion friert Drift und Sticker ein; der Fortschritt laeuft immer.

const KEN_BURNS_SCALE := 1.06
const KEN_BURNS_S := 9.0
const SCRIM_ALPHA := 0.62
const TEXT_HELL := Color(1.0, 0.985, 0.95)
const TEXT_OUTLINE := Color(0.18, 0.12, 0.1, 0.9)
## Sticker-Motiv (Web motif_gooby_wave, §2.5) — fehlt das Bild, bleibt der
## Sticker-Kreis leer (Web-onerror-Verhalten der Veil-Karte).
const MOTIV_PFAD := "res://assets/acui/motif_gooby_wave.png"

var _artwork_id := ""
var _animated := false
var _art: TextureRect
var _scrim: TextureRect
var _logo: TextureRect
var _tip_label: Label
var _laedt_label: Label
var _laedt_basis := ""
var _progress: LoadingVeilBalken
var _gooby: LoadingVeilSticker
var _ken_burns: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hintergrund()
	_build_vordergrund()
	resized.connect(_on_resized)


## Artwork nach Id (LoadingScreenRules.ARTWORKS) setzen; unbekannte Id
## faellt aufs Key-Artwork zurueck.
func zeige(artwork_id: String) -> void:
	var pfad := LoadingScreenRules.artwork_pfad(artwork_id)
	if pfad.is_empty():
		artwork_id = "key"
		pfad = LoadingScreenRules.artwork_pfad(artwork_id)
	_artwork_id = artwork_id
	if ResourceLoader.exists(pfad):
		_art.texture = load(pfad)
	if _logo.texture == null and ResourceLoader.exists(LoadingScreenRules.LOGO_PFAD):
		_logo.texture = load(LoadingScreenRules.LOGO_PFAD)
	_restart_ken_burns()


func artwork_id() -> String:
	return _artwork_id


func set_tip(text: String) -> void:
	_tip_label.text = text


func tip_text() -> String:
	return _tip_label.text


## ECHTER Fortschritt (0..1) vom threaded Preload des Routers — der Balken
## zeigt nie mehr an, als wirklich geladen ist. Die Laedt-Zeile haengt wie
## im Web „ NN%“ an, solange echter Fortschritt laeuft (0<p<1).
func set_progress(ratio: float) -> void:
	_progress.value = clampf(ratio, 0.0, 1.0)
	_progress.visible = ratio > 0.0 and ratio < 1.0
	_update_laedt_zeile()


func progress_wert() -> float:
	return _progress.value


## „Laedt…“-Zeile wie im Web (loadingVeil.js progress()): Prozent NUR bei
## echtem Fortschritt (0<p<1), sonst bleibt das nackte Label stehen.
func _update_laedt_zeile() -> void:
	if _laedt_label == null or _laedt_basis.is_empty():
		return
	var p := _progress.value
	if p > 0.0 and p < 1.0:
		_laedt_label.text = "%s %d%%" % [_laedt_basis, roundi(p * 100.0)]
	else:
		_laedt_label.text = _laedt_basis


## Sticker-Hopser + Ken-Burns an/aus (Reduced Motion: aus, Standbild).
func set_animated(an: bool) -> void:
	_animated = an
	_gooby.set_animated(an)
	if an:
		_restart_ken_burns()
	else:
		_stop_ken_burns()


func _build_hintergrund() -> void:
	_art = TextureRect.new()
	_art.name = "Artwork"
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	var verlauf := Gradient.new()
	verlauf.set_color(0, Color(0.1, 0.07, 0.08, 0.0))
	verlauf.set_color(1, Color(0.1, 0.07, 0.08, SCRIM_ALPHA))
	verlauf.set_offset(0, 0.45)
	var textur := GradientTexture2D.new()
	textur.gradient = verlauf
	textur.fill_from = Vector2(0.0, 0.0)
	textur.fill_to = Vector2(0.0, 1.0)
	_scrim = TextureRect.new()
	_scrim.name = "Scrim"
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.texture = textur
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)


func _build_vordergrund() -> void:
	_logo = TextureRect.new()
	_logo.name = "Logo"
	_logo.custom_minimum_size = Vector2(360.0, 130.0)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_logo.offset_left = -180.0
	_logo.offset_right = 180.0
	_logo.offset_top = 16.0
	_logo.offset_bottom = 146.0
	add_child(_logo)
	# Genug Hoehe fuer mehrzeilige Tipps: ALIGNMENT_END haelt Balken +
	# Laedt-Zeile unten fest, lange Tipps wachsen nach OBEN statt aus dem Bild.
	# Seitenrand 210: haelt lange einzeilige Tipps aus der Gooby-Ecke unten
	# rechts heraus (der Hopser zeichnet UEBER dem Text).
	var unten := VBoxContainer.new()
	unten.name = "Unten"
	unten.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	unten.offset_left = 210.0
	unten.offset_right = -210.0
	unten.offset_top = -290.0
	unten.offset_bottom = -28.0
	unten.alignment = BoxContainer.ALIGNMENT_END
	unten.add_theme_constant_override("separation", 12)
	unten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(unten)
	_tip_label = _label("Tip", &"TitleLabel")
	unten.add_child(_tip_label)
	# G2-Baustein: Teal-Verlaufsbalken der Veil-Karte (LoadingVeilBalken
	# stylt sich in _ready selbst — Pill-Track + 90-Grad-Verlauf, Web §2.3).
	_progress = LoadingVeilBalken.new()
	_progress.name = "Progress"
	_progress.custom_minimum_size = Vector2(420.0, 14.0)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress.max_value = 1.0
	_progress.step = 0.001
	_progress.show_percentage = false
	_progress.visible = false
	unten.add_child(_progress)
	_laedt_label = _label("Laedt", &"SoftLabel")
	_laedt_basis = I18nService.t("loading.laedt")
	_laedt_label.text = _laedt_basis
	unten.add_child(_laedt_label)
	# G2-Baustein: runder Motiv-Sticker (weiss beringter Kreis + Bounce)
	# ersetzt den alten Vektor-Gooby — gleiche set_animated-API.
	_gooby = LoadingVeilSticker.new()
	_gooby.name = "Gooby"
	_gooby.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_gooby.offset_left = -152.0
	_gooby.offset_top = -140.0
	_gooby.offset_right = -36.0
	_gooby.offset_bottom = -24.0
	if ResourceLoader.exists(MOTIV_PFAD):
		_gooby.set_motiv(load(MOTIV_PFAD))
	_gooby.set_animated(_animated)
	add_child(_gooby)


func _label(node_name: String, variation: StringName) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Volle Containerbreite: lange deutsche Tipps brechen frueher um und
	# bleiben 1-2 Zeilen hoch statt schmal + vierzeilig.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", TEXT_HELL)
	label.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", 7)
	return label


## Sanfter Ken-Burns-Drift des Artworks (nur animiert; Standbild sonst).
func _restart_ken_burns() -> void:
	_stop_ken_burns()
	if not _animated or not is_inside_tree():
		return
	_art.pivot_offset = size / 2.0
	_art.scale = Vector2.ONE
	_ken_burns = create_tween()
	_ken_burns.set_loops()
	(
		_ken_burns
		. tween_property(_art, "scale", Vector2.ONE * KEN_BURNS_SCALE, KEN_BURNS_S)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_ken_burns
		. tween_property(_art, "scale", Vector2.ONE, KEN_BURNS_S)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _stop_ken_burns() -> void:
	if _ken_burns != null and _ken_burns.is_valid():
		_ken_burns.kill()
	_ken_burns = null
	if _art != null:
		_art.scale = Vector2.ONE


func _on_resized() -> void:
	if _art != null:
		_art.pivot_offset = size / 2.0
