class_name LoadingVeil
extends CanvasLayer
## LoadingVeil — Transition-Fläche des SceneRouters (W1a; Optik W4/POLISH-3).
##
## AC-Look statt Cream+Spinner: driftendes Pattern (AcWallpaper-Shader) und
## eine mittige Karte. Vier Varianten:
## - Minigame-Reise (ArcadeScreen meldet einen Travel-Hint an): Cover +
##   Spieltitel + rotierender Tipp (`veil.tips`, lokalisiert).
## - LANGE Reise (RW-8; LoadingScreenRules: Stadt->Ranch, Ranch-Zonen,
##   Turnier, Besuch): Vollbild-Ladebildschirm (RanchLoadingScreen) mit
##   Artwork, Logo, echtem Ladebalken und rotierenden `loading.tips`.
##   Kurze Wege zeigen den vollen Schirm bewusst NIE.
## - DOOR_TRAVEL (EF-3/EVAL-1 F1): KEIN Vollveil — ein weicher, cremefarbener
##   Tür-Wisch (~130 ms rein, ~200 ms raus, durchgehende Bewegungsrichtung)
##   ohne Karte, ohne Tipps, ohne ui_open/close-Klänge (F9: das Panel-
##   Vokabular bleibt Panels vorbehalten). Raumwechsel im Haus fühlen sich
##   so wie ein Schritt durch die Tür an, nicht wie ein Ladebildschirm.
## - Sonst: hüpfender Mini-Gooby (`loading_veil_gooby.gd`) + `veil.laedt`.
##
## W14/LOADING-Politur: lebendigeres Kachel-Drift des Backdrops, hüpfende
## Fortschritts-Punkte (`loading_veil_punkte.gd`) statt Spinner-Gefühl
## (sie weichen dem echten Balken, sobald set_progress > 0 meldet) und
## Tipp-Texte im ACNH-Ton (`veil.tips`).
##
## Contract (nach W1 FROZEN, W1a-Handoff): cover(reduced_motion) /
## reveal(reduced_motion) sind awaitbare Coroutinen (Router:
## `await veil.cover(rm)`); Signale covered/revealed feuern zusätzlich.
## set_progress(0..1) bekommt den threaded-Load-Fortschritt vom Router.
## Node-Pfade Root / Root/Backdrop / Root/Spinner bleiben erhalten
## (Tests asserten sie) — der Spinner ist nur ausgeblendet.

signal covered
signal revealed

const COVER_DURATION := 0.25
const REVEAL_DURATION := 0.3
## Tür-Wisch (EF-3 F1): beide zusammen deutlich unter dem 350-ms-Budget.
const DOOR_COVER_DURATION := 0.13
const DOOR_REVEAL_DURATION := 0.2
## Weiche Wisch-Kante links/rechts als Anteil der Bildschirmbreite.
const DOOR_EDGE_FRAC := 0.18
const TIP_ROTATE_SEC := 3.2
const TIPS_KEY := "veil.tips"
## W14/LOADING: lebendigeres Kachel-Pattern — gleiche Drift-Richtung wie der
## AcTokens-Standard, nur spürbar flotter + etwas präsenter (nur im Veil;
## der Shader nullt die Drift unter Reduced Motion selbst).
const PATTERN_DRIFT_FAKTOR := 2.6
const PATTERN_OPACITY_VEIL := 0.58

static var _travel_hint: Dictionary = {}
static var _tip_cursor := 0
## Shuffle-Bag der grossen Ladebildschirm-Tipps (RW-8) — statisch, damit die
## Rotation über Veil-Instanzen hinweg ohne Wiederholung weiterläuft.
static var _loading_tipp_zustand: Dictionary = {}

## Tests/Screenshots: feste Tageszeit für die Artwork-Wahl (-1 = Systemzeit).
var stunde_override := -1.0

var _progress := 0.0
var _active_hint: Dictionary = {}
var _ranch_aktiv := false
var _ranch_ziel := StringName()
var _ranch_screen: RanchLoadingScreen
var _tip_timer: Timer
## EF-3 F1: aktiver Tür-Wisch-Modus (gesetzt via prepare_for_travel).
var _door_aktiv := false
var _door_wipe: Control
## W14/LOADING: hüpfende Fortschritts-Punkte (statt Spinner) in der Karte.
var _punkte: LoadingVeilPunkte

@onready var _root: Control = $Root
@onready var _backdrop: AcWallpaper = $Root/Backdrop
@onready var _card: PanelContainer = %Card
@onready var _cover_rect: TextureRect = %Cover
@onready var _title_label: Label = %Title
@onready var _gooby: LoadingVeilGooby = %Gooby
@onready var _laedt_label: Label = %Laedt
@onready var _tip_label: Label = %Tip
@onready var _progress_bar: ProgressBar = %Progress


func _ready() -> void:
	layer = 100
	visible = false
	_root.modulate.a = 0.0
	# CanvasLayer-Gotcha (W3d-Handoff): Window-Theme kommt hier nicht an.
	_root.theme = ThemeService.theme()
	_laedt_label.text = I18nService.t("veil.laedt")
	# W14/LOADING: lebendigeres Drift + Fortschritts-Punkte unterm Lädt-Text.
	_backdrop.drift = _backdrop.drift * PATTERN_DRIFT_FAKTOR
	_backdrop.pattern_opacity = PATTERN_OPACITY_VEIL
	_punkte = LoadingVeilPunkte.new()
	_punkte.name = "Punkte"
	_punkte.set_animated(false)
	var card_box := _laedt_label.get_parent()
	card_box.add_child(_punkte)
	card_box.move_child(_punkte, _laedt_label.get_index() + 1)
	_tip_timer = Timer.new()
	_tip_timer.wait_time = TIP_ROTATE_SEC
	_tip_timer.timeout.connect(_on_tip_timer)
	add_child(_tip_timer)
	var parent := get_parent()
	if parent != null and parent.has_signal("travel_started"):
		parent.travel_started.connect(_on_travel_started)
	_apply_variant()


## Reise-Kontext fürs nächste Veil (setzt der ArcadeScreen beim Kachel-Tap):
## {game_id, title, cover: Texture2D, targets: [StringName]}. Bleibt über
## die Kette Arcade→Pregame→Host gültig und löscht sich bei jeder Reise zu
## einem Ziel außerhalb von `targets` selbst (kein Aufräum-Zwang für Aufrufer).
static func set_travel_hint(hint: Dictionary) -> void:
	_travel_hint = hint


static func clear_travel_hint() -> void:
	_travel_hint = {}


## Vom Router-Signal getrieben; Tests dürfen es direkt aufrufen.
## travel_type: SceneRouter.TravelType — DOOR_TRAVEL bekommt nie den
## vollen Ladebildschirm (LoadingScreenRules), sondern den Tür-Wisch.
func prepare_for_travel(target: StringName, travel_type := 0) -> void:
	var targets: Array = _travel_hint.get("targets", [])
	if not _travel_hint.is_empty() and targets.has(target):
		_active_hint = _travel_hint
	else:
		clear_travel_hint()
		_active_hint = {}
	_door_aktiv = travel_type == LoadingScreenRules.DOOR_TRAVEL and _active_hint.is_empty()
	_ranch_ziel = target
	_ranch_aktiv = (
		_active_hint.is_empty()
		and not _door_aktiv
		and LoadingScreenRules.ist_lange_reise(target, travel_type)
	)
	_apply_variant()


## Deckt den Bildschirm ab; kehrt zurück, sobald das Veil voll deckt.
func cover(reduced_motion := false) -> void:
	if _door_aktiv:
		await _cover_door(reduced_motion)
		return
	# F9: Reisen haben ihr eigenes Whoosh-Paar — ui_close bleibt Panels.
	AudioDirector.try_play(self, "travel_whoosh_zu")
	visible = true
	_root.visible = true
	set_progress(0.0)
	_gooby.set_animated(not reduced_motion and not _ranch_aktiv)
	_punkte.set_animated(not reduced_motion and not _ranch_aktiv)
	if _ranch_screen != null:
		_ranch_screen.set_animated(not reduced_motion and _ranch_aktiv)
	if _tip_label.visible or _ranch_aktiv:
		_tip_timer.start()
	if reduced_motion:
		_root.modulate.a = 1.0
	else:
		_card.pivot_offset = _card.size / 2.0
		_card.scale = Vector2.ONE * 0.92
		var tween := create_tween().set_parallel()
		tween.tween_property(_root, "modulate:a", 1.0, COVER_DURATION)
		(
			tween
			. tween_property(_card, "scale", Vector2.ONE, COVER_DURATION)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
		await tween.finished
	covered.emit()


## Öffnet das Veil wieder; kehrt zurück, sobald es voll transparent ist.
func reveal(reduced_motion := false) -> void:
	if _door_aktiv:
		await _reveal_door(reduced_motion)
		return
	# F9: Reisen haben ihr eigenes Whoosh-Paar — ui_open bleibt Panels.
	AudioDirector.try_play(self, "travel_whoosh_auf")
	_tip_timer.stop()
	if reduced_motion:
		_root.modulate.a = 0.0
	else:
		var tween := create_tween()
		tween.tween_property(_root, "modulate:a", 0.0, REVEAL_DURATION)
		await tween.finished
	visible = false
	_gooby.set_animated(false)
	_punkte.set_animated(false)
	if _ranch_screen != null:
		_ranch_screen.set_animated(false)
	revealed.emit()


func set_progress(ratio: float) -> void:
	_progress = clampf(ratio, 0.0, 1.0)
	if _progress_bar != null:
		_progress_bar.value = _progress
		_progress_bar.visible = _progress > 0.0 and _progress < 1.0 and not _ranch_aktiv
	# W14/LOADING: Punkte weichen dem ECHTEN Balken — nie beide gleichzeitig.
	if _punkte != null and _progress_bar != null:
		_punkte.visible = not _progress_bar.visible
	if _ranch_screen != null:
		_ranch_screen.set_progress(_progress if _ranch_aktiv else 0.0)


func get_progress() -> float:
	return _progress


func _on_travel_started(target: StringName, travel_type: int) -> void:
	prepare_for_travel(target, travel_type)


## ── Tür-Wisch (EF-3 F1) ─────────────────────────────────────────────────
## Ein cremefarbenes Band mit weichen Kanten wischt in EINER Bewegungs-
## richtung über den Schirm: cover() schiebt es von links herein (deckend,
## SWAP passiert dahinter), reveal() schiebt es nach rechts hinaus. Kein
## Vollbild-Schwarz, keine Karte, kein Klang — ein Schritt durch die Tür.


func _cover_door(reduced_motion := false) -> void:
	visible = true
	_root.visible = false
	var wipe := _ensure_door_wipe()
	var canvas := _canvas_size()
	var edge := DOOR_EDGE_FRAC * canvas.x
	wipe.size = Vector2(canvas.x + 2.0 * edge, canvas.y)
	wipe.visible = true
	# Voll deckend, sobald die opake Mitte (Breite = Canvas) den Schirm füllt.
	var covered_x := -edge
	if reduced_motion:
		wipe.position = Vector2(covered_x, 0.0)
	else:
		wipe.position = Vector2(-wipe.size.x, 0.0)
		var tween := create_tween()
		tween.tween_property(wipe, "position:x", covered_x, DOOR_COVER_DURATION)
		await tween.finished
	covered.emit()


func _reveal_door(reduced_motion := false) -> void:
	var wipe := _door_wipe
	if wipe != null and is_instance_valid(wipe):
		if reduced_motion:
			wipe.visible = false
		else:
			# Bewegung läuft weiter nach rechts — die linke weiche Kante
			# gibt den neuen Raum frei.
			var tween := create_tween()
			tween.tween_property(wipe, "position:x", _canvas_size().x, DOOR_REVEAL_DURATION)
			await tween.finished
			wipe.visible = false
	visible = false
	_root.visible = true
	revealed.emit()


## Wisch-Fläche lazy bauen: ColorRect mit Shader, der links/rechts weich
## in Transparenz ausläuft (Kante = DOOR_EDGE_FRAC der Canvas-Breite).
func _ensure_door_wipe() -> Control:
	if _door_wipe != null and is_instance_valid(_door_wipe):
		return _door_wipe
	var rect := ColorRect.new()
	rect.name = "DoorWipe"
	rect.visible = false
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _door_wipe_shader()
	mat.set_shader_parameter("kante", DOOR_EDGE_FRAC / (1.0 + 2.0 * DOOR_EDGE_FRAC))
	rect.material = mat
	add_child(rect)
	_door_wipe = rect
	return rect


func _canvas_size() -> Vector2:
	if _root != null and _root.size.x > 0.0:
		return _root.size
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1280, 720)


static func _door_wipe_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 farbe : source_color = vec4(1.0, 0.964706, 0.92549, 1.0);
uniform float kante = 0.13;
void fragment() {
	float a = smoothstep(0.0, kante, UV.x) * smoothstep(0.0, kante, 1.0 - UV.x);
	COLOR = vec4(farbe.rgb, a);
}
"""
	return shader


func _apply_variant() -> void:
	if _root == null:
		return
	var minigame := not _active_hint.is_empty()
	var ranch := _ranch_aktiv and not minigame
	var cover_tex: Texture2D = _active_hint.get("cover")
	_cover_rect.visible = minigame and cover_tex != null
	_cover_rect.texture = cover_tex if minigame else null
	_title_label.visible = minigame and str(_active_hint.get("title", "")) != ""
	_title_label.text = str(_active_hint.get("title", ""))
	_tip_label.visible = minigame
	_gooby.visible = not minigame
	_laedt_label.visible = not minigame
	_card.visible = not ranch
	_backdrop.pattern = "arcade" if minigame else "dots"
	_apply_ranch_variant(ranch)
	if minigame:
		_advance_tip()


## Vollbild-Schirm der langen Reisen ein-/ausblenden (RW-8).
func _apply_ranch_variant(ranch: bool) -> void:
	if not ranch:
		if _ranch_screen != null:
			_ranch_screen.visible = false
		return
	if String(_ranch_ziel).begins_with("ranch/") and is_inside_tree():
		# Bootstrap der Ranch-Klangschicht + Ankunftsmomente (lazy, einmalig —
		# beide Knoten hängen sich selbst an SceneRouter.travel_finished).
		RanchAudio.get_or_create(self)
		RanchMoments.get_or_create(self)
	if _ranch_screen == null:
		_ranch_screen = RanchLoadingScreen.new()
		_ranch_screen.name = "RanchScreen"
		_root.add_child(_ranch_screen)
	_ranch_screen.visible = true
	var stunde := stunde_override
	if stunde < 0.0:
		stunde = LoadingScreenRules.aktuelle_stunde()
	_ranch_screen.zeige(LoadingScreenRules.artwork_id_fuer(_ranch_ziel, stunde))
	_ranch_screen.set_progress(0.0)
	_advance_loading_tip()


func _advance_tip() -> void:
	var tips := _tips()
	if tips.is_empty():
		return
	_tip_label.text = str(tips[_tip_cursor % tips.size()])
	_tip_cursor += 1


## Tipp des Vollbild-Schirms aus dem Shuffle-Bag (nie zweimal derselbe).
func _advance_loading_tip() -> void:
	if _ranch_screen == null:
		return
	var tips := I18nService.items(LoadingScreenRules.TIPS_KEY)
	var index := LoadingScreenRules.naechster_tipp_index(tips.size(), _loading_tipp_zustand)
	if index >= 0:
		_ranch_screen.set_tip(str(tips[index]))


func _on_tip_timer() -> void:
	if not visible:
		return
	if _ranch_aktiv and _ranch_screen != null and _ranch_screen.visible:
		_advance_loading_tip()
	elif _tip_label.visible:
		_advance_tip()


static func _tips() -> Array:
	return I18nService.items(TIPS_KEY)
