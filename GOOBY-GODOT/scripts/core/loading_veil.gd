class_name LoadingVeil
extends CanvasLayer
## LoadingVeil — Transition-Fläche des SceneRouters (W1a; Optik W4/POLISH-3).
##
## AC-Look statt Cream+Spinner: driftendes Pattern (AcWallpaper-Shader) und
## eine mittige Karte. Zwei Varianten:
## - Minigame-Reise (ArcadeScreen meldet einen Travel-Hint an): Cover +
##   Spieltitel + rotierender deutscher Tipp.
## - Sonst: hüpfender Mini-Gooby (`loading_veil_gooby.gd`) + „Lädt…“.
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
const TIP_ROTATE_SEC := 3.2
const TIPS_KEY := "veil.tips"
## Fallback, bis P4 die Keys in strings/ einpflegt
## (handoffs/W4P2-strings-request.md).
const FALLBACK_TIPS: Array[String] = [
	"Tipp: Ein satter Gooby hüpft höher — Kühlschrank checken!",
	"Tipp: Im Baumodus kannst du Möbel drehen. Einfach nochmal tippen!",
	"Tipp: Sticker verstecken sich überall. Augen auf!",
	"Tipp: Der Endlos-Modus schaltet sich ab Level 10 frei.",
	"Tipp: Nach dem Aufwachen wartet Gooby am Waschbecken aufs Zähneputzen.",
	"Tipp: Besuch deine Freunde — zu zweit ist es flauschiger!",
]

static var _travel_hint: Dictionary = {}
static var _tip_cursor := 0

var _progress := 0.0
var _active_hint: Dictionary = {}
var _tip_timer: Timer

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
	_laedt_label.text = _text("veil.laedt", "Lädt…")
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
func prepare_for_travel(target: StringName) -> void:
	var targets: Array = _travel_hint.get("targets", [])
	if not _travel_hint.is_empty() and targets.has(target):
		_active_hint = _travel_hint
	else:
		clear_travel_hint()
		_active_hint = {}
	_apply_variant()


## Deckt den Bildschirm ab; kehrt zurück, sobald das Veil voll deckt.
func cover(reduced_motion := false) -> void:
	AudioDirector.try_play(self, "ui_close")
	visible = true
	set_progress(0.0)
	_gooby.set_animated(not reduced_motion)
	if _tip_label.visible:
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
	AudioDirector.try_play(self, "ui_open")
	_tip_timer.stop()
	if reduced_motion:
		_root.modulate.a = 0.0
	else:
		var tween := create_tween()
		tween.tween_property(_root, "modulate:a", 0.0, REVEAL_DURATION)
		await tween.finished
	visible = false
	_gooby.set_animated(false)
	revealed.emit()


func set_progress(ratio: float) -> void:
	_progress = clampf(ratio, 0.0, 1.0)
	if _progress_bar != null:
		_progress_bar.value = _progress
		_progress_bar.visible = _progress > 0.0 and _progress < 1.0


func get_progress() -> float:
	return _progress


func _on_travel_started(target: StringName, _travel_type: int) -> void:
	prepare_for_travel(target)


func _apply_variant() -> void:
	if _root == null:
		return
	var minigame := not _active_hint.is_empty()
	var cover_tex: Texture2D = _active_hint.get("cover")
	_cover_rect.visible = minigame and cover_tex != null
	_cover_rect.texture = cover_tex if minigame else null
	_title_label.visible = minigame and str(_active_hint.get("title", "")) != ""
	_title_label.text = str(_active_hint.get("title", ""))
	_tip_label.visible = minigame
	_gooby.visible = not minigame
	_laedt_label.visible = not minigame
	_backdrop.pattern = "arcade" if minigame else "dots"
	if minigame:
		_advance_tip()


func _advance_tip() -> void:
	var tips := _tips()
	if tips.is_empty():
		return
	_tip_label.text = str(tips[_tip_cursor % tips.size()])
	_tip_cursor += 1


func _on_tip_timer() -> void:
	if _tip_label.visible and visible:
		_advance_tip()


static func _tips() -> Array:
	if I18nService.has_key(TIPS_KEY):
		var items := I18nService.items(TIPS_KEY)
		if not items.is_empty():
			return items
	return FALLBACK_TIPS


static func _text(key: String, fallback: String) -> String:
	return I18nService.t(key) if I18nService.has_key(key) else fallback
