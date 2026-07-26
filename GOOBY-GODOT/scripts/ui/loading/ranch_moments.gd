class_name RanchMoments
extends CanvasLayer
## RW-8 — Ankunfts- und Belohnungsmomente der Ranch: kurze, gut getimte
## Titel-Einblendungen mit Sound-Stinger und (wo passend) Konfetti.
##
## Automatisch (defensiv verdrahtet, einmal pro Spielstand — additiver
## Save-Unterschlüssel `ranch.momente`, KEIN Version-Bump, Self-Heal beim
## Lesen wie RanchWeltState):
## - Erste Ankunft auf einem Ranch-Ziel → "Willkommen auf der Gooby Ranch!"
##   mit Logo + Fanfare.
## - Zonen-Entdeckung (Signal `zone_gewechselt` der Region-Szene) →
##   "Neu entdeckt" + Zonenname (rwelt.zone.<id>) + weicher Level-Pluck.
##
## Auf Zuruf (API für RW-5/Zucht — s. Handoff RW8-momente-api.md):
## - turniersieg(untertitel): Sieg-Fanfare + Jubel + Gold-Titel + Konfetti.
## - fohlen_geboren(name): Wiehern + Titelkarte.
## Reduced Motion: Titel erscheinen statisch, Konfetti entfällt (JuiceKit
## gated selbst); Töne bleiben. Eingaben werden NIE blockiert.

const NODE_NAME := "RanchMoments"
const SAVE_KEY := "ranch.momente"
const HALTEDAUER_S := 2.2
const AUSBLENDE_S := 0.4
## Titelkarten-Schriftgroessen (Theme-Schrift in Display-Groesse).
const TITEL_GROESSE := 52
const SUB_GROESSE := 24
const GOLD := Color(1.0, 0.82, 0.35)
const TEXT_HELL := Color(1.0, 0.985, 0.95)
const TEXT_OUTLINE := Color(0.2, 0.13, 0.1, 0.92)

static var _fallback: RanchMoments

## Tests: GameState-Double statt /root/GameState.
var game_state_override: Object = null

var _root: Control
var _juice: JuiceKit
var _aktuell: Control


## Autoload-frei nutzbar: /root/RanchMoments bevorzugt, sonst lazy unter /root.
static func get_or_create(from: Node) -> RanchMoments:
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is RanchMoments:
		return existing
	if _fallback != null and is_instance_valid(_fallback):
		return _fallback
	var node := RanchMoments.new()
	node.name = NODE_NAME
	_fallback = node
	from.get_tree().root.add_child.call_deferred(node)
	return node


## Einmal-pro-Save-Gate (PURE bis auf gs): true = Moment ist NEU und wird
## sofort als gesehen gemerkt. gs = GameState oder Test-Double (get_value/
## set_value); gs == null → true ohne Merken (Sitzungs-Fallback).
static func sollte_zeigen(gs: Object, moment_id: String) -> bool:
	if gs == null:
		return true
	var raw: Variant = gs.get_value(SAVE_KEY, null)
	var daten: Dictionary = raw if raw is Dictionary else {"v": 1, "gesehen": []}
	daten["v"] = maxi(1, int(daten.get("v", 1)))
	var gesehen: Array = daten.get("gesehen") if daten.get("gesehen") is Array else []
	if gesehen.has(moment_id):
		return false
	gesehen.append(moment_id)
	daten["gesehen"] = gesehen
	gs.set_value(SAVE_KEY, daten)
	return true


func _ready() -> void:
	layer = 95
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# CanvasLayer-Gotcha (W3d): Window-Theme kommt hier nicht an.
	_root.theme = ThemeService.theme()
	add_child(_root)
	_juice = JuiceKit.new()
	_juice.float_text_parent = _root
	add_child(_juice)
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)


## Willkommens-Moment (erste Ranch-Ankunft): Logo + Titel + Fanfare.
func willkommen() -> void:
	RanchAudio.get_or_create(self).fanfare(false)
	zeige_moment(
		I18nService.t("loading.moment.willkommen"),
		I18nService.t("loading.moment.willkommen_sub"),
		{"logo": true}
	)


## Zonen-Titel-Einblendung ("Neu entdeckt" + Zonenname).
func zone_entdeckt(zone_id: String) -> void:
	var name_key := "rwelt.zone.%s" % zone_id
	var zonen_name := I18nService.t(name_key) if I18nService.has_key(name_key) else zone_id
	AudioDirector.try_play(self, "ui_levelup")
	zeige_moment(zonen_name, I18nService.t("loading.moment.entdeckt"), {"sub_oben": true})


## Turniersieg-Moment: Sieg-Fanfare + Jubel + Gold-Titel + Konfetti.
func turniersieg(untertitel := "") -> void:
	RanchAudio.get_or_create(self).fanfare(true)
	var sub := untertitel
	if sub.is_empty():
		sub = I18nService.t("loading.moment.turniersieg_sub")
	zeige_moment(
		I18nService.t("loading.moment.turniersieg"), sub, {"farbe": GOLD, "konfetti": true}
	)


## Fohlen-Moment: Wiehern + Titelkarte mit Namen.
func fohlen_geboren(fohlen_name: String) -> void:
	RanchAudio.get_or_create(self).reaktion("freude")
	zeige_moment(
		I18nService.t("loading.moment.fohlen"),
		I18nService.t("loading.moment.fohlen_sub", {"name": fohlen_name}),
		{"konfetti": true}
	)


## Kern: Titelkarte einblenden (opts: logo, farbe, konfetti, sub_oben).
## Ein neuer Moment ersetzt den laufenden; Auto-Ausblenden nach HALTEDAUER_S.
func zeige_moment(titel: String, untertitel := "", opts: Dictionary = {}) -> void:
	if _aktuell != null and is_instance_valid(_aktuell):
		# Name sofort freigeben, sonst würde die neue Karte umbenannt
		# (queue_free räumt erst am Frame-Ende auf).
		_aktuell.name = "MomentAlt"
		_aktuell.queue_free()
	var karte := _baue_karte(titel, untertitel, opts)
	_root.add_child(karte)
	_aktuell = karte
	UiMotion.pop_in(karte)
	if bool(opts.get("konfetti", false)):
		_juice.confetti(80)
	var timer := get_tree().create_timer(HALTEDAUER_S)
	timer.timeout.connect(_blende_aus.bind(karte))


func _baue_karte(titel: String, untertitel: String, opts: Dictionary) -> Control:
	var karte := VBoxContainer.new()
	karte.name = "Moment"
	karte.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	karte.grow_horizontal = Control.GROW_DIRECTION_BOTH
	karte.grow_vertical = Control.GROW_DIRECTION_BOTH
	karte.position += Vector2(0.0, -70.0)
	karte.alignment = BoxContainer.ALIGNMENT_CENTER
	# Luft unter dem 52-px-Titel: 6 px kollidieren mit den Unterlaengen.
	karte.add_theme_constant_override("separation", 12)
	karte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bool(opts.get("logo", false)) and ResourceLoader.exists(LoadingScreenRules.LOGO_PFAD):
		var logo := TextureRect.new()
		logo.name = "Logo"
		logo.texture = load(LoadingScreenRules.LOGO_PFAD)
		logo.custom_minimum_size = Vector2(320.0, 108.0)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		karte.add_child(logo)
	var sub := _label(untertitel, &"SoftLabel", TEXT_HELL)
	sub.name = "Untertitel"
	sub.add_theme_font_size_override("font_size", SUB_GROESSE)
	var haupt := _label(titel, &"HeadlineLabel", opts.get("farbe", TEXT_HELL))
	haupt.name = "Titel"
	# Kino-Titelkarte: Theme-Schrift, aber Display-Groesse — 34 px Headline
	# geht auf einer Vollbild-Einblendung ueber der 3D-Szene unter.
	haupt.add_theme_font_size_override("font_size", TITEL_GROESSE)
	haupt.add_theme_constant_override("outline_size", 12)
	if bool(opts.get("sub_oben", false)):
		karte.add_child(sub)
		karte.add_child(haupt)
	else:
		karte.add_child(haupt)
		karte.add_child(sub)
	sub.visible = not untertitel.is_empty()
	return karte


func _label(text: String, variation: StringName, farbe: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", farbe)
	label.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", 8)
	return label


func _blende_aus(karte: Control) -> void:
	if karte == null or not is_instance_valid(karte):
		return
	var tween := UiMotion.fade_out(karte, AUSBLENDE_S)
	if tween == null:
		karte.queue_free()
		return
	tween.tween_callback(karte.queue_free)


func _on_travel_finished(target: StringName) -> void:
	if not String(target).begins_with("ranch/"):
		return
	if sollte_zeigen(_game_state(), "willkommen"):
		willkommen()
	_verbinde_zonen_signal()


func _verbinde_zonen_signal() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("get_current_scene"):
		return
	var szene: Node = router.get_current_scene()
	if szene == null or not szene.has_signal("zone_gewechselt"):
		return
	if not szene.is_connected("zone_gewechselt", _on_zone_gewechselt):
		szene.connect("zone_gewechselt", _on_zone_gewechselt)


func _on_zone_gewechselt(zone_id: String) -> void:
	if zone_id.is_empty() or zone_id == "hof":
		return
	if sollte_zeigen(_game_state(), "zone:%s" % zone_id):
		zone_entdeckt(zone_id)


func _game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")
