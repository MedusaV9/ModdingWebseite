class_name UrlaubsBonus
extends RefCounted
## W13B/RAUMSTATION (Doc E §3.3) — Urlaubs-Nutzen-Glue über den puren
## W13B-Latches in vacation.gd/reise_logic.gd:
##
## 1. ERHOLUNGS-BOOST: `abholen()` stempelt `vacation.erholtBis` (now+48 h).
##    `sync()` spiegelt das als „erholt“-Buff in den BESTEHENDEN
##    Event-Buff-Slice (GoobyBuffs) — damit hängt die Anzeige an der
##    vorhandenen Buff-Chip-Leiste der Energie-Zeile (KEIN HUD-Umbau; das
##    Sonnen-Icon am Chip ist ein Request an den HUD-Owner). Die eigentliche
##    Drain-Bremse (×0,8) rechnet der Ticker über
##    `Vacation.energie_drain_faktor()` (Request an den Ticker-Owner).
## 2. WELTENGOOBY-TITEL: `abholen()` latcht `weltengoobyAt` bei 9/9
##    besuchten Zielen. `sync()` feiert das GENAU EINMAL — G4/P16
##    (ui-reisen MITTEL 10): statt eines flüchtigen Toasts erscheint eine
##    ZENTRIERTE Feier-Karte (CanvasLayer + Veil + AcCardLg, Muster
##    BoardingPass.oeffne) mit 🌍-Glyph, Titel und „Weiter“-Knopf ≥ 52·f.
##    Reduced Motion: UiMotion.pop_in springt sofort, kein Konfetti-Sparkle.
##    Der 9/9-Erfolg „weltenbummler“ bringt parallel Konfetti über den
##    RewardHub-Achievement-Pfad.
##
## `sync()` ist idempotent und darf beliebig oft laufen (Ort-Betreten,
## vacation_changed-Signal) — Zeit wird IMMER injiziert (now_ms).

const Vacation := preload("res://scripts/logic/vacation.gd")

## Buff-Eintrag im GoobyBuffs-Format ({id, stat, wert, until_ms}).
const BUFF_ID := "erholt"
const BUFF_STAT := "energy"
## Sichtbarer Chip-Wert („+5“) — Doc E §3.3 („Aufwachen gibt +5 Laune“);
## der eigentliche Nutzen ist die Drain-Bremse, nicht dieser Zahlwert.
const BUFF_WERT := 5.0
## Regrant-Toleranz: kleiner Rundungs-Drift zwischen until_ms und erholtBis
## (dauer_h-Umrechnung) darf NICHT jede sync()-Runde neu granten.
const BUFF_TOLERANZ_MS := 60_000


## Kompletter Abgleich Save → Buff/Feier. Rückgabe (für Tests):
## {buff_gewaehrt: bool, weltengooby_gefeiert: bool}.
## `host` (optional) = Node im Baum für Toast + Jingle.
static func sync(gs: Object, now_ms: int, host: Node = null) -> Dictionary:
	var result := {"buff_gewaehrt": false, "weltengooby_gefeiert": false}
	if gs == null:
		return result
	var v := Vacation.slice_of(gs.state())
	if _braucht_buff(gs, v, now_ms):
		_gewaehre_buff(gs, int(v["erholtBis"]), now_ms)
		result["buff_gewaehrt"] = true
	if Vacation.weltengooby(v) and not bool(v["weltengoobyGefeiert"]):
		_latche_feier(gs)
		_feiere(host)
		result["weltengooby_gefeiert"] = true
	return result


## Fehlt der „erholt“-Buff (oder endet er deutlich vor erholtBis)?
static func _braucht_buff(gs: Object, v: Dictionary, now_ms: int) -> bool:
	if not Vacation.erholungs_boost_aktiv(v, now_ms):
		return false
	var slice: Variant = gs.get_value("buffs", {})
	if not (slice is Dictionary):
		return true
	var erholt_bis := int(v["erholtBis"])
	for buff: Variant in (slice as Dictionary).get("aktiv", []):
		if buff is Dictionary and str(buff.get("id", "")) == BUFF_ID:
			return int(buff.get("until_ms", 0)) < erholt_bis - BUFF_TOLERANZ_MS
	return true


## Buff über den BESTEHENDEN GoobyBuffs-Pfad granten — Laufzeit exakt bis
## erholtBis (dauer_h rückgerechnet, damit Buff-Chip und Drain-Bremse
## zusammen auslaufen).
static func _gewaehre_buff(gs: Object, erholt_bis: int, now_ms: int) -> void:
	var dauer_h := float(erholt_bis - now_ms) / float(GoobyBuffs.MS_PER_HOUR)
	GoobyBuffs.grant(gs, BUFF_ID, BUFF_STAT, BUFF_WERT, dauer_h, now_ms)


## Feier-Latch in den vacation-Slice schreiben (überlebt slice_of).
static func _latche_feier(gs: Object) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			if state.get("vacation") is Dictionary:
				state["vacation"]["weltengoobyGefeiert"] = true
	)
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("vacation")


## G4/P16: Feier-KARTE statt Toast — der Titel-Moment (einmalig pro
## Spielstand) bekommt eine zentrierte Karte über Abdunkelung; Jingle
## (ui_sticker = Belohnung) + Erfolgs-Haptik bleiben auf derselben Schiene.
static func _feiere(host: Node) -> void:
	if host == null or not host.is_inside_tree():
		return
	WeltengoobyKarte.oeffne(host.get_tree().root)
	AudioDirector.try_play(host, "ui_sticker")
	Haptics.success(host)


## Zentrierte Weltengooby-Feier-Karte (Muster BoardingPass.oeffne):
## eigener CanvasLayer + Veil + AcCardLg-Karte, „Weiter“-Knopf schließt.
## Meldet sich am PanelStack an (Back-Geste schließt NUR die Karte).
class WeltengoobyKarte:
	extends PanelContainer

	## Wunschbreite in Design-px (klemmt an die Safe-Area).
	const BASIS_BREITE := 360.0

	static func oeffne(host: Node) -> CanvasLayer:
		var layer := CanvasLayer.new()
		layer.name = "WeltengoobyLayer"
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
		var karte := WeltengoobyKarte.new()
		karte.set_anchors_preset(Control.PRESET_CENTER)
		karte.grow_horizontal = Control.GROW_DIRECTION_BOTH
		karte.grow_vertical = Control.GROW_DIRECTION_BOTH
		wurzel.add_child(karte)
		PanelStack.push(karte)
		UiMotion.pop_in(karte)
		UiMotion.sparkle(karte, AcTokens.GOLD)
		return layer

	func _ready() -> void:
		name = "WeltengoobyKarte"
		theme_type_variation = &"AcCardLg"
		var m := ScreenShell.metrics(get_viewport())
		var f: float = m["f"]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.custom_minimum_size = Vector2(ScreenShell.card_width(m, BASIS_BREITE), 0.0)
		add_child(box)
		var glyph := Label.new()
		glyph.name = "FeierGlyph"
		glyph.text = "🌍"
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", int(roundf(56.0 * f)))
		glyph.set_meta(ScreenShell.META_FONT_SKIP, true)
		box.add_child(glyph)
		var titel := Label.new()
		titel.name = "FeierTitel"
		titel.theme_type_variation = &"HeadlineLabel"
		titel.text = I18nService.t("g4travel.feier.titel")
		titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(titel)
		var text := Label.new()
		text.name = "FeierText"
		text.text = I18nService.t("raumstation.weltengooby.toast")
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.custom_minimum_size = Vector2(box.custom_minimum_size.x, 0.0)
		box.add_child(text)
		var weiter := SquishButton.new()
		weiter.name = "FeierWeiter"
		weiter.theme_type_variation = &"PrimaryButton"
		weiter.text = I18nService.t("g4travel.feier.weiter")
		weiter.focus_mode = Control.FOCUS_NONE
		weiter.custom_minimum_size = Vector2(0.0, roundf(52.0 * f))
		ScreenShell.touch_target(weiter, m)
		weiter.pressed.connect(close)
		box.add_child(weiter)
		ScreenShell.scale_fonts(self, f)

	## PanelStack-Vertrag: Back-Geste/„Weiter“ räumen die Feier weg.
	func close() -> void:
		PanelStack.remove(self)
		AudioDirector.try_play(self, "ui_close")
		var node: Node = self
		while node != null and not (node is CanvasLayer):
			node = node.get_parent()
		if node != null:
			node.queue_free()
