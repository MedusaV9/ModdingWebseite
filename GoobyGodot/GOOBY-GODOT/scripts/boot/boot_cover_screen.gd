class_name BootCoverScreen
extends CanvasLayer
## W14/LOADING — der Boot-Cover-Screen des allerersten Ladens (User-Wunsch:
## „Querformat-Coverartwork mit Ladebalken unten und dann eine Animation
## wenn's ins Spiel geht“). Komplett in Code gebaut (kein tscn), Layer 120 —
## liegt ÜBER dem LoadingVeil (100), damit die erste Router-Reise dahinter
## unsichtbar abläuft.
##
## - Vollbild-Artwork (assets/boot/boot_cover.png, 16:9): Querformat füllt,
##   Hochkant croppt sanft mit Fokus auf Gooby (BootPhasen.cover_layout);
##   greift der Zoom-Deckel, füllt die Randfarbe AUS dem Bild (nie schwarz).
##   W16/BOOTPERF (E2): das 2,7-MB-Artwork lädt THREADED statt synchron im
##   ersten Frame — bis es da ist, deckt die gebackene Randfarbe
##   (BootPhasen.RANDFARBE_FALLBACK, aus demselben Bild gemittelt) den
##   Bildschirm; die Laufzeit-Messung per get_image() entfällt komplett.
## - Unten (W16/G4, Alt-Web-Optik): eine Papier-Ladekarte im Stil der alten
##   Web-Loading-Card (styles.css `.mg-loading-card`: Papier #FFFAF2,
##   Radius 28, Hairline-Ring, Pop-Schatten) mit rotierendem Lade-Spruch
##   (loading.boot.sprueche, deterministische Rotation je Seed, 200-ms-
##   Crossfade wie die Web-Tipp-Zeile), dem Möhren-Ladebalken
##   (BootLadebalken, ECHTER Phasen-Fortschritt aus main.gd) und der
##   „Lädt… NN%“-Zeile (Prozent NUR bei echtem Fortschritt, Web-Regel).
##   Reduced Motion friert Crossfade UND Balken-Gleiten ein (P22-Entscheid).
## - oeffne(): Übergangs-Animation ins Spiel — weiches Aufzoomen + Kreis-Wipe
##   auf Gooby zentriert + Konfetti-Puff; Reduced Motion: schlichter Fade.

signal geoeffnet

const COVER_PFAD := "res://assets/boot/boot_cover.png"
const SPRUCH_ROTATE_SEC := 2.6
const SPRUECHE_KEY := "loading.boot.sprueche"
const LAEDT_KEY := "loading.laedt"
## Web .mg-loading-tip transition: 200-ms-Crossfade beim Spruch-Wechsel.
const SPRUCH_FADE_S := 0.2
const ZOOM_ZIEL := 1.07
const WIPE_S := 0.55
const FADE_S := 0.18
const WIPE_KANTE := 0.09
const KONFETTI_MENGE := 36
## Web-Karten-Maße in Design-px (styles.css): Radius --card-radius-lg,
## Spruch ≈ Titel-Typo (700), Lädt-Zeile 13/700 wie .mg-loading-hint.
const KARTE_RADIUS := 28.0
const SPRUCH_PX := 15
const LAEDT_PX := 13

## Deterministische Spruch-Rotation: Tests/Screenshots pinnen den Seed;
## -1 = beim _ready aus der Uhr würfeln (jeder Boot fühlt sich frisch an).
var spruch_seed := -1
## Tests: Reduced-Motion-Override der View-Schicht (-1 = AppSettings fragen,
## 0/1 = fest aus/an) — Muster wie LoadingVeil.stunde_override.
var reduced_motion_override := -1

var _root: Control
var _hintergrund: ColorRect
var _artwork: TextureRect
var _unten: VBoxContainer
var _karte: PanelContainer
var _spruch_label: Label
var _laedt_label: Label
var _laedt_basis := ""
var _balken: BootLadebalken
var _spruch_timer: Timer
var _spruch_tween: Tween
var _wipe_material: ShaderMaterial
var _spruch_schritt := 0
var _reduced := false
var _oeffnet := false
## EVAL-2026-08/C #5: true, solange der threaded Artwork-Load noch nicht
## per load_threaded_get abgeholt wurde — ein unabgeholter Load-Token
## leakt sonst bei Quit als RefCounted-Instanz im ObjectDB-Report.
var _artwork_offen := false


func _ready() -> void:
	layer = 120
	if spruch_seed < 0:
		spruch_seed = int(Time.get_ticks_usec()) % 100_000 + 1
	_build()
	_layout_anwenden()
	_naechster_spruch()
	_spruch_timer = Timer.new()
	_spruch_timer.wait_time = SPRUCH_ROTATE_SEC
	_spruch_timer.timeout.connect(_rotiere_spruch)
	add_child(_spruch_timer)
	_spruch_timer.start()


## Offenen Artwork-Load beim Teardown abholen (EVAL-2026-08/C #5): der
## Load-Token lebt sonst über das Engine-Cleanup hinaus und leakt.
func _exit_tree() -> void:
	if not _artwork_offen:
		return
	_artwork_offen = false
	lade_token_abholen(COVER_PFAD)


## Threaded-Load-Token deterministisch einsammeln (EVAL-2026-08/C #5): erst
## pollen, bis der Task WIRKLICH fertig ist, dann abholen. Ein blockierendes
## get auf einen noch laufenden Task nimmt den Task-Reorder-Pfad des
## ResourceLoaders — der leakt beim Quit-Teardown racig einen Token
## (empirisch ~1/15 Boots; die Poll-Variante war in allen Serien sauber).
## Nutzt auch main.gd für die offenen Warmup-Ziele.
static func lade_token_abholen(pfad: String, timeout_ms := 10_000) -> void:
	var status := ResourceLoader.load_threaded_get_status(pfad)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return
	var deadline := Time.get_ticks_msec() + timeout_ms
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		status = ResourceLoader.load_threaded_get_status(pfad)
	ResourceLoader.load_threaded_get(pfad)


## ECHTER Boot-Fortschritt 0..1 (BootPhasen.prozent-Werte aus main.gd).
func set_progress(ratio: float) -> void:
	if _balken != null:
		_balken.set_progress(ratio)
	_update_laedt_zeile()


func get_progress() -> float:
	return _balken.get_progress() if _balken != null else 0.0


## Fokuspunkt (Gooby) in Viewport-Pixeln — Zentrum des Kreis-Wipes.
func fokus_px() -> Vector2:
	var layout := _layout()
	return layout["fokus_px"]


func spruch_text() -> String:
	return _spruch_label.text if _spruch_label != null else ""


## Übergangs-Animation ins Spiel (awaitbar; feuert `geoeffnet`).
## Reduced Motion: schlichter Fade statt Zoom+Kreis-Wipe+Konfetti.
func oeffne(reduced_motion := false) -> void:
	if _oeffnet:
		return
	_oeffnet = true
	if _spruch_timer != null:
		_spruch_timer.stop()
	_stoppe_spruch_fade()
	AudioDirector.try_play(self, "travel_whoosh_auf")
	if reduced_motion or BootPhasen.wipe_variante(reduced_motion) == "fade":
		var fade := create_tween()
		fade.tween_property(_root, "modulate:a", 0.0, FADE_S)
		await fade.finished
		visible = false
		geoeffnet.emit()
		return
	await _oeffne_kreis()
	visible = false
	geoeffnet.emit()


func _oeffne_kreis() -> void:
	var groesse := _viewport_groesse()
	var layout := _layout()
	var fokus: Vector2 = layout["fokus_px"]
	_konfetti_puff(fokus)
	# Balken + Spruch zuerst weich weg — sie sollen nicht mitzoomen.
	var weg := create_tween()
	weg.tween_property(_unten, "modulate:a", 0.0, 0.12)
	# Weiches Aufzoomen aufs Artwork (Pivot = Gooby) …
	_artwork.pivot_offset = fokus - _artwork.position
	var tween := create_tween().set_parallel()
	(
		tween
		. tween_property(_artwork, "scale", Vector2.ONE * ZOOM_ZIEL, WIPE_S + 0.1)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	# … plus Kreis-Wipe: wachsende transparente Iris um Gooby (beide
	# Deck-Flächen teilen EIN Material — ein Uniform treibt beide).
	var aspekt := Vector2(groesse.x / maxf(groesse.y, 1.0), 1.0)
	var zentrum := fokus / groesse
	_wipe_material.set_shader_parameter("zentrum", zentrum)
	_wipe_material.set_shader_parameter("aspekt", aspekt)
	var max_r := 0.0
	for ecke in [Vector2(0, 0), Vector2(aspekt.x, 0), Vector2(0, 1), Vector2(aspekt.x, 1)]:
		max_r = maxf(max_r, (zentrum * aspekt).distance_to(ecke))
	var radius_setter := func(r: float) -> void: _wipe_material.set_shader_parameter("radius", r)
	(
		tween
		. tween_method(radius_setter, 0.0, max_r + WIPE_KANTE, WIPE_S)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)
	await tween.finished


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Blinde Taps schlucken, solange das Cover deckt (wie das Web-Veil).
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# CanvasLayer-Gotcha (W3d-Handoff): Window-Theme kommt hier nicht an.
	_root.theme = ThemeService.theme()
	add_child(_root)
	_wipe_material = ShaderMaterial.new()
	_wipe_material.shader = _wipe_shader()
	_wipe_material.set_shader_parameter("radius", -1.0)
	_wipe_material.set_shader_parameter("kante", WIPE_KANTE)
	_hintergrund = ColorRect.new()
	_hintergrund.name = "Hintergrund"
	_hintergrund.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hintergrund.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hintergrund.material = _wipe_material
	_root.add_child(_hintergrund)
	_artwork = TextureRect.new()
	_artwork.name = "Artwork"
	_artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_artwork.stretch_mode = TextureRect.STRETCH_SCALE
	_artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_artwork.material = _wipe_material
	# Randfarbe SOFORT (gebackener Mittelwert der Randpixel desselben Bildes,
	# s. BootPhasen.RANDFARBE_FALLBACK) — kein get_image()-CPU-Roundtrip mehr.
	_hintergrund.color = BootPhasen.RANDFARBE_FALLBACK
	_artwork_laden()
	_root.add_child(_artwork)
	_build_unten()
	_root.resized.connect(_layout_anwenden)


## Die Papier-Ladekarte unten (W16/G4): Web-Loading-Card-Sprache — Papier,
## Radius 28, Hairline-Ring, Pop-Schatten (wie loading_veil_karte.gd), darin
## Spruch (Ink, 700), Möhren-Balken und die „Lädt… NN%“-Zeile (Ink-Soft).
func _build_unten() -> void:
	_reduced = _ist_reduced_motion()
	var f := _skala()
	_unten = VBoxContainer.new()
	_unten.name = "Unten"
	_unten.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_unten.offset_left = 16.0
	_unten.offset_right = -16.0
	_unten.offset_top = -320.0 * f
	_unten.offset_bottom = -24.0 * f
	_unten.alignment = BoxContainer.ALIGNMENT_END
	_unten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_unten)
	_karte = PanelContainer.new()
	_karte.name = "Karte"
	_karte.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_karte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_karte.add_theme_stylebox_override("panel", _karten_stil(f))
	_unten.add_child(_karte)
	var box := VBoxContainer.new()
	box.name = "KartenBox"
	box.add_theme_constant_override("separation", int(round(8.0 * f)))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_karte.add_child(box)
	_spruch_label = Label.new()
	_spruch_label.name = "Spruch"
	_spruch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spruch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_stil(_spruch_label, SPRUCH_PX, 700, AcTokens.INK)
	box.add_child(_spruch_label)
	_balken = BootLadebalken.new()
	_balken.name = "Balken"
	_balken.custom_minimum_size = Vector2(420.0, 24.0 * f)
	_balken.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# RM-Entscheid (P22): Reduced Motion friert auch das Balken-Gleiten ein
	# (Anzeige springt aufs echte Ziel) — vorher wurde set_animated nie
	# produktiv aufgerufen, nur die Cover-Öffnung fadete.
	_balken.set_animated(not _reduced)
	box.add_child(_balken)
	_laedt_label = Label.new()
	_laedt_label.name = "Laedt"
	_laedt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_stil(_laedt_label, LAEDT_PX, 700, AcTokens.INK_SOFT)
	box.add_child(_laedt_label)


## Artwork nach der Crop-Mathe platzieren (auch bei Rotation/Resize).
func _layout_anwenden() -> void:
	if _artwork == null:
		return
	var layout := _layout()
	var rect: Rect2 = layout["rect"]
	_artwork.position = rect.position
	_artwork.size = rect.size
	_artwork.scale = Vector2.ONE
	if _balken != null:
		var f := _skala()
		var breite := clampf(_viewport_groesse().x * 0.56, 280.0, 560.0 * f)
		_balken.custom_minimum_size = Vector2(breite, 24.0 * f)


func _layout() -> Dictionary:
	var bild := Vector2(1920.0, 1080.0)
	if _artwork != null and _artwork.texture != null:
		bild = Vector2(_artwork.texture.get_size())
	return BootPhasen.cover_layout(_viewport_groesse(), bild)


func _viewport_groesse() -> Vector2:
	if _root != null and _root.size.x > 0.0:
		return _root.size
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1280, 720)


## W16/BOOTPERF (E8): Sprüche über den Domain-Teillade-Pfad holen — der
## erste Frame parst so NUR strings/<locale>/loading.json statt aller
## 77 Locale-Dateien (Ergebnis identisch, s. I18nService.items_aus_domain).
func _naechster_spruch() -> void:
	var sprueche := I18nService.items_aus_domain("loading", SPRUECHE_KEY)
	var index := BootPhasen.spruch_index(_spruch_schritt, sprueche.size(), spruch_seed)
	_spruch_schritt += 1
	if index >= 0 and _spruch_label != null:
		_spruch_label.text = str(sprueche[index])


## Spruch-Wechsel per 200-ms-Crossfade (Web .mg-loading-tip transition) —
## Reduced Motion wechselt hart (Muster wie loading_veil._wechsle_tip_weich).
func _rotiere_spruch() -> void:
	if _reduced or _spruch_label == null or not is_inside_tree():
		_naechster_spruch()
		return
	_stoppe_spruch_fade()
	_spruch_tween = create_tween()
	_spruch_tween.tween_property(_spruch_label, "modulate:a", 0.0, SPRUCH_FADE_S)
	_spruch_tween.tween_callback(_naechster_spruch)
	_spruch_tween.tween_property(_spruch_label, "modulate:a", 1.0, SPRUCH_FADE_S)


func _stoppe_spruch_fade() -> void:
	if _spruch_tween != null and _spruch_tween.is_valid():
		_spruch_tween.kill()
	_spruch_tween = null
	if _spruch_label != null:
		_spruch_label.modulate.a = 1.0


## „Lädt… NN%“ wie im Web (loadingVeil.js progress()): Prozent NUR bei
## echtem Fortschritt (0<p<1), sonst die nackte Zeile. Die Basis kommt LAZY
## mit der ersten Fortschritts-Meldung (nach dem ersten Frame) —
## I18nService.t() lädt die volle Locale-Tabelle und darf nicht in den
## ersten Pixel (bootperf B3/E8; die Sprüche gehen den Domain-Teilpfad).
func _update_laedt_zeile() -> void:
	if _laedt_label == null:
		return
	if _laedt_basis.is_empty():
		_laedt_basis = I18nService.t(LAEDT_KEY)
	var p := get_progress()
	if p > 0.0 and p < 1.0:
		_laedt_label.text = "%s %d%%" % [_laedt_basis, roundi(p * 100.0)]
	else:
		_laedt_label.text = _laedt_basis


## Reduced-Motion-Flag der View-Schicht (Balken-Gleiten + Spruch-Crossfade);
## defensiv wie main.gd/scene_router.gd — die Öffnung bekommt ihr Flag
## weiterhin von main über oeffne(reduced_motion).
func _ist_reduced_motion() -> bool:
	if reduced_motion_override >= 0:
		return reduced_motion_override > 0
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


func _skala() -> float:
	return UiScale.for_viewport(get_viewport())


static func _karten_stil(f: float) -> StyleBoxFlat:
	var stil := StyleBoxFlat.new()
	stil.bg_color = AcTokens.PAPER
	stil.set_corner_radius_all(int(round(KARTE_RADIUS * f)))
	stil.set_border_width_all(maxi(1, int(round(f))))
	stil.border_color = AcTokens.OUTLINE_SOFT
	stil.shadow_color = AcTokens.SHADOW_COLOR
	stil.shadow_size = int(round(15.0 * f))
	stil.shadow_offset = Vector2(0.0, 10.0 * f)
	stil.content_margin_left = 20.0 * f
	stil.content_margin_right = 20.0 * f
	stil.content_margin_top = 12.0 * f
	stil.content_margin_bottom = 12.0 * f
	return stil


func _label_stil(label: Label, groesse: int, gewicht: int, farbe: Color) -> void:
	var fs := UiScale.font_scale(get_viewport())
	label.add_theme_font_override("font", _font(gewicht))
	label.add_theme_font_size_override("font_size", int(round(groesse * fs)))
	label.add_theme_color_override("font_color", farbe)


static func _font(gewicht: int) -> FontVariation:
	var variante := FontVariation.new()
	variante.base_font = load(AcTokens.FONT_PATH)
	variante.variation_opentype = {"wght": gewicht}
	return variante


## W16/BOOTPERF (E2a): Artwork threaded anfordern statt synchron dekodieren —
## der größte Einzelblocker des ersten Frames (2,7-MB-PNG lossless) wandert
## damit vom Main-Thread in den ResourceLoader-Pool. Cache-Hit (Soft-Restart,
## Tests) → sofort setzen; Request-Fehler → heutiges Synchron-Verhalten.
func _artwork_laden() -> void:
	if not ResourceLoader.exists(COVER_PFAD):
		return
	if ResourceLoader.has_cached(COVER_PFAD):
		_artwork.texture = load(COVER_PFAD)
		return
	if ResourceLoader.load_threaded_request(COVER_PFAD) != OK:
		_artwork.texture = load(COVER_PFAD)
		return
	_artwork_offen = true
	set_process(true)


## Frame-Polling des threaded Artwork-Loads: setzt die Textur, sobald sie da
## ist (1–3 Frames nach dem ersten Pixel, unauffällig hinter der identischen
## Randfarbe). _layout() rechnet ohne Textur mit den echten Bildmaßen
## (1920×1080) — es gibt also keinen Layout-Sprung beim Eintreffen.
## Bewusst _process statt await-Poll-Schleife (EVAL-2026-08/C #5): eine bei
## Quit suspendierte Coroutine hielte FunctionState + Signal-StringName über
## das Engine-Cleanup hinaus am Leben — _process kann nicht hängen bleiben.
func _process(_delta: float) -> void:
	if not _artwork_offen:
		set_process(false)
		return
	var status := ResourceLoader.load_threaded_get_status(COVER_PFAD)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_artwork_offen = false
	set_process(false)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var tex := ResourceLoader.load_threaded_get(COVER_PFAD)
		if tex is Texture2D and _artwork != null:
			_artwork.texture = tex
			_layout_anwenden()
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		# Token auch im Fehlerfall abholen — sonst leakt er bei Quit.
		ResourceLoader.load_threaded_get(COVER_PFAD)


## Kleiner Konfetti-Puff auf Gooby zentriert (nur im animierten Pfad —
## der Reduced-Motion-Fade ruft ihn gar nicht erst auf).
func _konfetti_puff(fokus: Vector2) -> void:
	var puff := CPUParticles2D.new()
	puff.name = "KonfettiPuff"
	puff.position = fokus
	puff.one_shot = true
	puff.emitting = true
	puff.amount = KONFETTI_MENGE
	puff.lifetime = 0.9
	puff.explosiveness = 1.0
	puff.direction = Vector2.UP
	puff.spread = 180.0
	puff.gravity = Vector2(0.0, 420.0)
	puff.initial_velocity_min = 140.0
	puff.initial_velocity_max = 340.0
	puff.angular_velocity_min = -260.0
	puff.angular_velocity_max = 260.0
	puff.scale_amount_min = 3.0
	puff.scale_amount_max = 6.0
	puff.hue_variation_min = -0.5
	puff.hue_variation_max = 0.5
	puff.color = Color("#FFD166")
	_root.add_child(puff)


static func _wipe_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 zentrum = vec2(0.5, 0.5);
uniform vec2 aspekt = vec2(1.777, 1.0);
uniform float radius = -1.0;
uniform float kante = 0.09;
void fragment() {
	float d = distance(SCREEN_UV * aspekt, zentrum * aspekt);
	COLOR.a *= smoothstep(radius - kante, radius, d);
}
"""
	return shader
