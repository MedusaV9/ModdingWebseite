class_name StickerCard
extends RefCounted
## W13B/STICKER (H §3.3/3.4) — Rarity-Effekte der Sticker-Karten. Zwei
## Bausteine, beide zustandslos:
## - `celebration_for()`: pures Rarity→Feier-Mapping für den RewardHub
##   (normal = Toast, Silber = Toast + Funkeln, Gold = Toast + Konfetti +
##   eigener Jingle aus der Bestands-SFX-Palette — kein neues Audio).
## - `attach_glitter()`: dezentes Shimmer-Shader-Overlay über GOLD-Karten
##   im Album (mobile-günstig, prozedural; Reduced Motion friert den
##   Shader über `motion_scale = 0` ein → statischer Glanz).
## Reduced Motion wird INJIZIERT (Parameter statt Autoload-Read), damit die
## Helfer headless pur testbar bleiben.

const SHIMMER_SHADER := "res://scripts/ui/album/sticker_shimmer.gdshader"
## Nur GOLD glitzert im Album (= episch, Randfarbe #FFD34D). Geheime
## Sticker feiern zwar wie Gold, tragen aber keinen Dauer-Schimmer.
const GOLD_RARITY := "episch"
const FUNKEL_TEILE := 14
const SILBER := Color("#E8ECF4")
const GOLD := Color("#FFD166")


## Pures Rarity→Feier-Mapping (H §3.4):
##   haeufig → bisheriger Toast (Sticker-Pluck, kein Konfetti mehr)
##   selten  → Toast + kleines Silber-Funkeln
##   episch/geheim → Toast + Konfetti + eigener Jingle (mg_win-Dreiklang)
static func celebration_for(rarity: String) -> Dictionary:
	match rarity:
		"selten":
			return {
				"tier": "silber",
				"sfx": "ui_sticker",
				"konfetti": false,
				"funkeln": true,
				"toast_key": "album.unlock_toast_selten",
			}
		"episch", "geheim":
			return {
				"tier": "gold",
				"sfx": "mg_win",
				"konfetti": true,
				"funkeln": false,
				"toast_key": "album.unlock_toast_episch",
			}
	return {
		"tier": "normal",
		"sfx": "ui_sticker",
		"konfetti": false,
		"funkeln": false,
		"toast_key": "album.unlock_toast",
	}


## Glitzert diese Rarity im Album? (nur Gold — H §3.4)
static func has_gold_glitter(rarity: String) -> bool:
	return rarity == GOLD_RARITY


## Shimmer-Overlay über eine (freigeschaltete) Karte legen. Liefert das
## Overlay oder null (keine Gold-Rarity). `reduced_motion` = statischer
## Glanz statt Animation — das Overlay bleibt (Rarity soll sichtbar sein).
static func attach_glitter(card: Control, rarity: String, reduced_motion: bool) -> Control:
	if card == null or not has_gold_glitter(rarity):
		return null
	var overlay := ColorRect.new()
	overlay.name = "GoldShimmer"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(SHIMMER_SHADER)
	mat.set_shader_parameter("motion_scale", 0.0 if reduced_motion else 1.0)
	overlay.material = mat
	# Anchors VOR dem Einhängen (Muster _art_rect: plain-Control-Parent).
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(overlay)
	return overlay


## Kleines Silber-Funkeln zur Unlock-Feier — deutlich dezenter als das
## Gold-Konfetti (wenige, kurzlebige Glitzerpunkte um die Toast-Zone).
## Reduced Motion lässt Partikel ganz weg (wie RewardFx.konfetti_2d).
static func funkel_burst(parent: Node, breite_px := 640.0) -> void:
	if parent == null or not parent.is_inside_tree() or RewardFx.reduced_motion(parent):
		return
	var particles := CPUParticles2D.new()
	particles.name = "SilberFunkeln"
	particles.position = Vector2(breite_px * 0.5, 84.0)
	particles.one_shot = true
	particles.emitting = true
	particles.amount = FUNKEL_TEILE
	particles.lifetime = 0.7
	particles.explosiveness = 1.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(breite_px * 0.18, 10.0)
	particles.direction = Vector2.UP
	particles.spread = 80.0
	particles.gravity = Vector2(0.0, 140.0)
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 90.0
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0
	particles.color_ramp = _funkel_gradient()
	parent.add_child(particles)
	var tree := parent.get_tree()
	if tree == null:
		particles.queue_free()
		return
	# Methoden-Callable statt Lambda-Capture (B2-Muster aus RewardFx).
	tree.create_timer(1.0).timeout.connect(particles.queue_free)


static func _funkel_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, SILBER)
	gradient.set_color(1, Color(GOLD, 0.0))
	gradient.add_point(0.55, Color("#FFF6E8"))
	return gradient
