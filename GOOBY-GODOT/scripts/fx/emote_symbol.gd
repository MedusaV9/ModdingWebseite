class_name EmoteSymbol
extends Node3D
## FEEL-AC — Emote-Symbol über Goobys Kopf (Ausrufezeichen, Herzchen, …).
## Ein Billboard-Sprite3D mit den sauberen SVG-Symbolen aus
## assets/fx/symbols (GOOBY-Stil: weißer Halo + kräftige Füllung + dunkle
## Kontur — auf dem Handy aus Kameradistanz sofort lesbar, keine Emojis).
##
## Pop-in mit Überschwinger, sanftes Schweben, Pop-out über verschwinde().
## Reduced Motion: nur Ein-/Ausblenden, kein Hüpfen/Schweben.
## Immer sichtbar (no_depth_test + hohe render_priority) — ein Symbol, das
## hinter einem Möbel verschwindet, ist keins.

## Sichtbare Symbolhöhe in Metern (Lesbarkeits-Budget für Handy-Distanz).
const SYMBOL_HOEHE_M := 0.5
## SVG-Rastergröße (assets/fx/symbols/*.svg: width/height 192).
const TEXTUR_PX := 192.0
const POP_IN_S := 0.28
const POP_OUT_S := 0.16
const SCHWEBE_AMP_M := 0.035
const SCHWEBE_HZ := 1.1

var symbol_id := ""
var reduziert := false

var _sprite: Sprite3D = null
var _basis_y := 0.0
var _zeit := 0.0
var _geht := false


## Symbol bauen (Aufrufer positioniert und hängt es ein).
static func erzeuge(symbol: String, reduced_motion: bool) -> EmoteSymbol:
	var node := EmoteSymbol.new()
	node.name = "EmoteSymbol"
	node.symbol_id = symbol
	node.reduziert = reduced_motion
	return node


func _ready() -> void:
	_basis_y = position.y
	_sprite = Sprite3D.new()
	_sprite.name = "Symbol"
	var textur: Variant = load(FeelEmotions.symbol_pfad(symbol_id))
	if textur is Texture2D:
		_sprite.texture = textur
	else:
		push_warning("EmoteSymbol: Symbol-Textur fehlt: %s" % symbol_id)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.no_depth_test = true
	_sprite.render_priority = 20
	_sprite.pixel_size = SYMBOL_HOEHE_M / TEXTUR_PX
	add_child(_sprite)
	_pop_in()


func _process(delta: float) -> void:
	if reduziert or _geht:
		return
	_zeit += delta
	position.y = _basis_y + SCHWEBE_AMP_M * sin(TAU * SCHWEBE_HZ * _zeit)


## Pop-out und selbst aufräumen (idempotent).
func verschwinde() -> void:
	if _geht or not is_inside_tree():
		if not is_inside_tree():
			queue_free()
		return
	_geht = true
	var tween := create_tween()
	if reduziert:
		tween.tween_property(_sprite, "modulate:a", 0.0, POP_OUT_S)
	else:
		tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
		tween.tween_property(self, "scale", Vector3.ONE * 0.05, POP_OUT_S)
	tween.tween_callback(queue_free)


func geht_gerade() -> bool:
	return _geht


func _pop_in() -> void:
	if reduziert:
		_sprite.modulate.a = 0.0
		var fade := create_tween()
		fade.tween_property(_sprite, "modulate:a", 1.0, POP_IN_S)
		return
	scale = Vector3.ONE * 0.1
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector3.ONE, POP_IN_S)
