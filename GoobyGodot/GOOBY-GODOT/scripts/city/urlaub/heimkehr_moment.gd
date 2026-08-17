class_name HeimkehrMoment
extends RefCounted
## W19/MITBRINGSEL — Szenen-Glue des Wiedersehens-Moments (Doc E §3.2
## „Koffer + Mitbringsel-Tüte raus → Umarmung-Konfetti“). Die pure Logik
## lebt in HeimkehrLogik; hier passiert NUR die Inszenierung beim ersten
## Home-Besuch nach der Urlaubs-Abholung:
##
## - Gooby-Beat im Raum: celebrate-Clip + ecstatic (BESTEHENDE Rig-/
##   Emotions-API wie die Rückkehr-Cutscene), Wiedersehens-Spruch über die
##   vorhandene Raum-Bubble (room.say), Koffer + Mitbringsel-Tüte als
##   kurzlebige Props neben Gooby (Muster GoobyReactions-Kissenturm).
## - Tüten-Übergabe-KARTE (Muster UrlaubsBonus.WeltengoobyKarte): zeigt
##   das Mitbringsel + den dezenten GOOBY-FREE-Fenster-Hinweis; der
##   „Fest drücken!“-Knopf feuert das Umarmungs-Konfetti und schließt.
## - Overlay-Dirigent (W18/J1): der Moment reiht sich mit eigener
##   Priorität VOR dem Tagesbonus ein statt den Dirigenten zu umgehen;
##   ohne Dirigenten (nackte Tests) öffnet er direkt. Gefeiert wird beim
##   ÖFFNEN genau einmal (HeimkehrLogik.feiern ist der Latch).

## Dirigent-Priorität: der Herzmoment kommt VOR Tagesbonus (10)/Coachmark.
const PRIO_HEIMKEHR := 5
## Karten-CanvasLayer: ÜBER Raum-HUD (5) und Home-HUD (UiLayer 10) — sonst
## bleiben HUD-Knöpfe über dem Schleier sichtbar UND tappbar; unter
## Quest-Toasts (60), Guide (70) und RewardHub (90), die weiter durchkommen.
const KARTEN_LAYER := 40
## Kleiner Vorlauf, damit die Ankunft sich setzt (Morgen-Ritual-Geist).
const VORLAUF_S := 0.6
## Wie lange Koffer + Tüte neben Gooby stehen bleiben (Sekunden).
const PROP_DAUER_S := 12.0


## Beim Raum-Betreten aufrufen (home_entry._on_travel_finished): prüft das
## „Rückkehr steht aus“-Gate und reiht den Moment beim Dirigenten ein.
static func attach_to(room: Node) -> void:
	if room == null or not room.has_method("game_state") or not room.has_method("gooby"):
		return
	var gs: Object = room.game_state()
	if gs == null or not HeimkehrLogik.ausstehend(gs.state()):
		return
	var dirigent := OverlayDirigent.find(room)
	if dirigent == null:
		_oeffne(room, gs)
		return
	dirigent.anfordern("heimkehr", PRIO_HEIMKEHR, _oeffne.bind(room, gs), VORLAUF_S)


## Öffnen-Pfad (ruft der Dirigent an seiner Reihe; null = inzwischen
## hinfällig — Raum weg oder schon gefeiert, dann kommt das nächste Ticket).
static func _oeffne(room: Node, gs: Object) -> Control:
	if room == null or not is_instance_valid(room) or not room.is_inside_tree():
		return null
	var res := HeimkehrLogik.feiern(gs)
	if not bool(res["ok"]):
		return null
	_gooby_beat(room, res)
	return HeimkehrKarte.oeffne(room.get_tree().root, gs, res)


## Der Beat im Raum: Wiedersehens-Hüpfer + Emotion über die BESTEHENDE
## Rig-API (wie _spiele_rueckkehr der Cutscene), Spruch über die Raum-
## Bubble, Koffer + Tüte als kurzlebige Props (ohne Gooby: nur Karte).
static func _gooby_beat(room: Node, res: Dictionary) -> void:
	if room.has_method("say"):
		room.say(I18nService.t(str(res["spruch_key"])))
	var gooby: Node = room.gooby() if room.has_method("gooby") else null
	if gooby == null or not (gooby is Node3D):
		return
	if gooby.get("rig") is GoobyRig:
		gooby.rig.play_clip("celebrate")
		gooby.rig.set_emotion("ecstatic")
	_stelle_gepaeck(room, gooby as Node3D)


## Koffer + Mitbringsel-Tüte neben Gooby (reine Primitive, kurzlebig —
## Muster GoobyReactions._build_tower; Reduced Motion zeigt sie trotzdem,
## sie bewegen sich nicht).
static func _stelle_gepaeck(room: Node, gooby: Node3D) -> void:
	var gepaeck := Node3D.new()
	gepaeck.name = "HeimkehrGepaeck"
	gepaeck.add_child(_koffer())
	gepaeck.add_child(_tuete())
	gepaeck.position = gooby.global_position + Vector3(0.55, 0.0, 0.25)
	room.add_child(gepaeck)
	# Methoden-Callable statt Lambda (B2): stirbt der Raum vor dem Timeout,
	# trennt Godot die Verbindung automatisch.
	var tree := room.get_tree()
	if tree != null:
		tree.create_timer(PROP_DAUER_S).timeout.connect(gepaeck.queue_free)


static func _koffer() -> Node3D:
	var koffer := Node3D.new()
	koffer.name = "Koffer"
	var korpus := MeshInstance3D.new()
	var kbox := BoxMesh.new()
	kbox.size = Vector3(0.34, 0.46, 0.16)
	korpus.mesh = kbox
	korpus.material_override = _matte(Color("#C9846B"))
	korpus.position = Vector3(0.0, 0.23, 0.0)
	koffer.add_child(korpus)
	var griff := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(0.14, 0.05, 0.05)
	griff.mesh = gbox
	griff.material_override = _matte(Color("#8A5A44"))
	griff.position = Vector3(0.0, 0.49, 0.0)
	koffer.add_child(griff)
	return koffer


static func _tuete() -> Node3D:
	var tuete := Node3D.new()
	tuete.name = "MitbringselTuete"
	var korpus := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(0.26, 0.3, 0.18)
	korpus.mesh = tbox
	korpus.material_override = _matte(Color("#59C9B9"))
	korpus.position = Vector3(0.32, 0.15, 0.05)
	tuete.add_child(korpus)
	var henkel := MeshInstance3D.new()
	var hbox := BoxMesh.new()
	hbox.size = Vector3(0.16, 0.08, 0.02)
	henkel.mesh = hbox
	henkel.material_override = _matte(Color("#3B3630"))
	henkel.position = Vector3(0.32, 0.34, 0.05)
	tuete.add_child(henkel)
	return tuete


static func _matte(farbe: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.roughness = 0.85
	return mat


## Tüten-Übergabe-Karte (Muster UrlaubsBonus.WeltengoobyKarte): eigener
## CanvasLayer + Veil + AcCardLg; „Fest drücken!“ feuert Konfetti + schließt.
## Meldet sich am PanelStack an (Back-Geste schließt NUR die Karte).
class HeimkehrKarte:
	extends PanelContainer

	## Wunschbreite in Design-px (klemmt an die Safe-Area).
	const BASIS_BREITE := 360.0

	var geschenk: Dictionary = {}
	var game_state: Object = null

	static func oeffne(host: Node, gs: Object, res: Dictionary) -> HeimkehrKarte:
		var layer := CanvasLayer.new()
		layer.name = "HeimkehrLayer"
		layer.layer = KARTEN_LAYER
		host.add_child(layer)
		var wurzel := Control.new()
		wurzel.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Theme explizit: Window-Theme propagiert NICHT durch CanvasLayer.
		wurzel.theme = ThemeService.theme()
		layer.add_child(wurzel)
		var schleier := ColorRect.new()
		schleier.color = AcTokens.VEIL
		schleier.set_anchors_preset(Control.PRESET_FULL_RECT)
		wurzel.add_child(schleier)
		var karte := HeimkehrKarte.new()
		karte.geschenk = res
		karte.game_state = gs
		karte.set_anchors_preset(Control.PRESET_CENTER)
		karte.grow_horizontal = Control.GROW_DIRECTION_BOTH
		karte.grow_vertical = Control.GROW_DIRECTION_BOTH
		wurzel.add_child(karte)
		PanelStack.push(karte)
		UiMotion.pop_in(karte)
		UiMotion.sparkle(karte, AcTokens.GOLD)
		AudioDirector.try_play(karte, "ui_sticker")
		Haptics.success(karte)
		return karte

	func _ready() -> void:
		name = "HeimkehrKarte"
		theme_type_variation = &"AcCardLg"
		var m := ScreenShell.metrics(get_viewport())
		var f: float = m["f"]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.custom_minimum_size = Vector2(ScreenShell.card_width(m, BASIS_BREITE), 0.0)
		add_child(box)
		var glyph := Label.new()
		glyph.name = "HeimkehrGlyph"
		glyph.text = "🧳🛍️"
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(roundf(52.0 * f)))
		glyph.set_meta(ScreenShell.META_FONT_SKIP, true)
		box.add_child(glyph)
		var titel := Label.new()
		titel.name = "HeimkehrTitel"
		titel.theme_type_variation = &"HeadlineLabel"
		titel.text = I18nService.t("heimkehr.titel")
		titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(titel)
		var tuete := Label.new()
		tuete.name = "HeimkehrTuete"
		tuete.text = I18nService.t("heimkehr.tuete", {"name": _mitbringsel_name()})
		tuete.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tuete.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tuete.custom_minimum_size = Vector2(box.custom_minimum_size.x, 0.0)
		box.add_child(tuete)
		_baue_fenster_hinweis(box)
		var umarmen := SquishButton.new()
		umarmen.name = "HeimkehrUmarmen"
		umarmen.theme_type_variation = &"PrimaryButton"
		umarmen.text = I18nService.t("heimkehr.knopf.umarmen")
		umarmen.focus_mode = Control.FOCUS_NONE
		umarmen.custom_minimum_size = Vector2(0.0, roundf(52.0 * f))
		ScreenShell.touch_target(umarmen, m)
		umarmen.pressed.connect(_on_umarmen)
		box.add_child(umarmen)
		ScreenShell.scale_fonts(self, f)

	## Dezenter Hinweis aufs 24-h-GOOBY-FREE-Fenster (nur solange offen).
	func _baue_fenster_hinweis(box: VBoxContainer) -> void:
		if game_state == null:
			return
		var jetzt := _now_ms()
		if not HeimkehrLogik.fenster_offen(game_state.state(), jetzt):
			return
		var hinweis := Label.new()
		hinweis.name = "HeimkehrGfreeHinweis"
		hinweis.theme_type_variation = &"CaptionLabel"
		hinweis.text = (
			I18nService
			. t(
				"heimkehr.gfree.fenster",
				{
					"ziel": I18nService.t("travel.ziel.%s" % str(geschenk.get("ziel_id", ""))),
					"stunden": HeimkehrLogik.fenster_rest_h(game_state.state(), jetzt),
				}
			)
		)
		hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hinweis.custom_minimum_size = Vector2(box.custom_minimum_size.x, 0.0)
		box.add_child(hinweis)

	func _mitbringsel_name() -> String:
		return HeimkehrLogik.mitbringsel_name(
			str(geschenk.get("typ", "")), str(geschenk.get("ziel_id", ""))
		)

	## Umarmungs-Konfetti (überlebt die Karte: hängt an der Baumwurzel) +
	## Belohnungs-Jingle, dann schließen.
	func _on_umarmen() -> void:
		var wurzel := get_tree().root
		RewardFx.konfetti_2d(wurzel, 48, get_viewport_rect().size.x)
		AudioDirector.try_play(self, "ui_sticker")
		Haptics.success(self)
		close()

	## PanelStack-Vertrag: Back-Geste/„Fest drücken!“ räumen die Karte weg.
	func close() -> void:
		PanelStack.remove(self)
		AudioDirector.try_play(self, "ui_close")
		var node: Node = self
		while node != null and not (node is CanvasLayer):
			node = node.get_parent()
		if node != null:
			node.queue_free()

	func _now_ms() -> int:
		if game_state != null and "clock" in game_state and game_state.clock != null:
			return int(game_state.clock.now_ms())
		return int(Time.get_unix_time_from_system() * 1000.0)
