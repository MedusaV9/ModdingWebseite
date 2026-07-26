class_name DorfLaden
extends Control
## Laden-Screen von Hufingen (RW-4) — EIN wiederverwendbarer Vollbild-Screen
## für alle fünf Läden (Reitladen, Futterhof, Möbel-Scheune, Pferdehändlerin,
## Schmiede). AC-Look: AcWallpaper.for_context("shop"), Ladentheke als
## Papier-Panel, Warenliste mit Preisen, Gooby-Verkäufer-Gruß oben.
## ALLE Buchungen laufen atomar über DorfWirtschaft/DorfHaendler.

signal geschlossen

const INK := Color("#3B3630")
const PAPIER := Color(0.98, 0.95, 0.88, 0.97)
const GOLD_TEXT := Color("#8A6A2E")
const FEHLER_ROT := Color("#B23A48")
const OK_GRUEN := Color("#4E7C3A")

var laden_id := "futterhof"
var game_state_override: Object

var _liste: VBoxContainer
var _coins_label: Label
var _feedback: Label
var _feedback_t := 0.0


static func neu(id: String, gs: Object = null) -> DorfLaden:
	var laden := DorfLaden.new()
	laden.laden_id = id
	laden.game_state_override = gs
	laden.name = "Laden_%s" % id
	return laden


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var papier := AcWallpaper.for_context("shop")
	papier.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(papier)
	_baue_theke()
	_refresh()


func _process(delta: float) -> void:
	if _feedback_t > 0.0:
		_feedback_t -= delta
		_feedback.modulate.a = clampf(_feedback_t / 0.4, 0.0, 1.0)


## ------------------------------------------------------------------ Aufbau


func _baue_theke() -> void:
	var mitte := CenterContainer.new()
	mitte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(mitte)
	var panel := PanelContainer.new()
	var stil := StyleBoxFlat.new()
	stil.bg_color = PAPIER
	stil.set_corner_radius_all(18)
	stil.set_content_margin_all(18)
	stil.border_color = Color(INK, 0.25)
	stil.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", stil)
	panel.custom_minimum_size = Vector2(620, 520)
	mitte.add_child(panel)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 8)
	panel.add_child(spalte)

	var kopf := HBoxContainer.new()
	spalte.add_child(kopf)
	var titel := Label.new()
	titel.text = I18nService.t("rdorf.laden.%s" % laden_id)
	titel.add_theme_font_size_override("font_size", 26)
	titel.add_theme_color_override("font_color", INK)
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	_coins_label = Label.new()
	_coins_label.add_theme_color_override("font_color", GOLD_TEXT)
	_coins_label.add_theme_font_size_override("font_size", 20)
	kopf.add_child(_coins_label)

	var verkaeufer := Label.new()
	verkaeufer.text = (
		"%s — %s"
		% [
			I18nService.t("rdorf.npc.%s" % laden_id),
			I18nService.t("rdorf.npc_rolle.%s" % laden_id),
		]
	)
	verkaeufer.add_theme_color_override("font_color", Color(INK, 0.75))
	spalte.add_child(verkaeufer)
	var gruss := Label.new()
	gruss.text = "\u201E%s\u201C" % I18nService.t("rdorf.gruss.%s" % laden_id)
	gruss.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gruss.add_theme_color_override("font_color", Color(INK, 0.6))
	spalte.add_child(gruss)
	spalte.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spalte.add_child(scroll)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 6)
	scroll.add_child(_liste)

	_feedback = Label.new()
	_feedback.add_theme_color_override("font_color", FEHLER_ROT)
	_feedback.modulate.a = 0.0
	spalte.add_child(_feedback)
	var fertig := Button.new()
	fertig.text = I18nService.t("rdorf.fertig")
	fertig.pressed.connect(func() -> void: geschlossen.emit())
	spalte.add_child(fertig)


## Warenliste je Laden neu aufbauen (nach jedem Kauf: eine Wahrheit = Save).
func _refresh() -> void:
	var gs := game_state()
	_coins_label.text = "%d G" % (int(gs.get_value("economy.coins", 0)) if gs != null else 0)
	for kind in _liste.get_children():
		kind.queue_free()
	match laden_id:
		"reitladen":
			_fuelle_reitladen(gs)
		"futterhof":
			_fuelle_futterhof(gs)
		"moebelscheune":
			_fuelle_moebelscheune(gs)
		"pferdehaendlerin":
			_fuelle_haendlerin(gs)
		"schmiede":
			_fuelle_schmiede(gs)


## ------------------------------------------------------------------ Läden


func _fuelle_reitladen(gs: Object) -> void:
	var wirtschaft: Variant = gs.get_value("ranch.wirtschaft", {}) if gs != null else {}
	var owned: Array = []
	if wirtschaft is Dictionary and (wirtschaft as Dictionary).get("gear") is Dictionary:
		var gear: Dictionary = (wirtschaft as Dictionary)["gear"]
		owned = gear.get("owned") if gear.get("owned") is Array else []
	for eintrag: Variant in RanchWirtschaft.gear_katalog(RanchWirtschaft.load_balance()):
		var ware: Dictionary = eintrag
		var gear_id := str(ware["id"])
		var name := (
			"%s (%s)"
			% [
				I18nService.t("ranchplay.gear.%s" % str(ware["slot"])),
				I18nService.t("ranchplay.gearfarbe.%s" % str(ware["farbe"])),
			]
		)
		if owned.has(gear_id):
			_zeile(name, I18nService.t("rdorf.besitz"), Callable())
		else:
			_zeile(
				name,
				_kauf_text(int(ware["preis"])),
				func() -> void: _melde(DorfWirtschaft.gear_kaufen(gs, gear_id))
			)


func _fuelle_futterhof(gs: Object) -> void:
	var bal := DorfKatalog.load_balance()
	for eintrag: Variant in DorfKatalog.futter_waren(bal):
		var ware: Dictionary = eintrag
		var ware_id := str(ware["id"])
		_zeile(
			I18nService.t("rdorf.waren.%s" % ware_id),
			_kauf_text(int(ware["preis"])),
			func() -> void: _melde(DorfWirtschaft.futter_kaufen(gs, ware_id))
		)
	_ueberschrift(I18nService.t("rdorf.ankauf_titel"))
	var lager: Variant = gs.get_value("ranch.wirtschaft.lager", {}) if gs != null else {}
	for art: Variant in DorfKatalog.futter_ankauf(bal).keys():
		var art_id := str(art)
		var bestand := 0
		if lager is Dictionary:
			bestand = int((lager as Dictionary).get(art_id, 0))
		var preis := int(DorfKatalog.futter_ankauf(bal)[art_id])
		_zeile(
			"%s (%d)" % [I18nService.t("rdorf.waren.%s" % art_id), bestand],
			"%s +%d G" % [I18nService.t("rdorf.verkaufen"), preis],
			func() -> void: _melde(DorfWirtschaft.ernte_verkaufen(gs, art_id, 1))
		)


func _fuelle_moebelscheune(gs: Object) -> void:
	var bal := DorfKatalog.load_balance()
	var bau_bal := RanchBauKatalog.load_balance()
	var defs := RanchBauKatalog.defs(bau_bal)
	for id: Variant in DorfKatalog.ranch_deko_ids(bal):
		var deko_id := str(id)
		if not defs.has(deko_id):
			continue
		var def: Dictionary = defs[deko_id]
		_zeile(
			I18nService.t("rbau.item.%s" % deko_id),
			_kauf_text(int(def["kosten"])),
			func() -> void: _melde(DorfWirtschaft.deko_kaufen(gs, deko_id))
		)
	_ueberschrift(I18nService.t("rdorf.moebel_titel"))
	var moebel_defs: Dictionary = DorfWirtschaft.FurnitureCatalog.defs()
	for eintrag: Variant in DorfKatalog.moebel(bal):
		var ware: Dictionary = eintrag
		var item_id := str(ware["id"])
		if not moebel_defs.has(item_id):
			continue
		var name: String = DorfWirtschaft.FurnitureCatalog.display_name(
			moebel_defs[item_id], I18nService.get_locale()
		)
		_zeile(
			name,
			_kauf_text(int(ware["preis"])),
			func() -> void: _melde(DorfWirtschaft.moebel_kaufen(gs, item_id))
		)


func _fuelle_haendlerin(gs: Object) -> void:
	_ueberschrift(I18nService.t("rdorf.angebot_heute"))
	var bal := DorfKatalog.load_balance()
	var dorf := RanchDorfState.lese(gs)
	var heute_verkauft: Array = []
	if str(dorf["verkauft"]["tag"]) == RanchDorfState.heute(gs):
		heute_verkauft = dorf["verkauft"]["angebote"]
	for eintrag: Variant in DorfHaendler.angebot(gs, bal):
		var pferd: Dictionary = eintrag
		var pool_id := str(pferd["id"])
		var name := I18nService.t(str(pferd.get("name_key", "rdorf.ortsname")))
		if heute_verkauft.has(pool_id):
			_zeile(name, I18nService.t("rdorf.verkauft"), Callable(), Color(str(pferd["farbe"])))
		else:
			_zeile(
				name,
				_kauf_text(int(pferd["preis"])),
				func() -> void: _melde(DorfHaendler.pferd_kaufen(gs, pool_id)),
				Color(str(pferd["farbe"]))
			)
	_ueberschrift(I18nService.t("rdorf.eigene_pferde"))
	var pferde: Variant = gs.get_value("ranch.tiere.pferde", {}) if gs != null else {}
	if pferde is Dictionary:
		for pferd_id: Variant in (pferde as Dictionary).keys():
			var eigenes: Dictionary = (pferde as Dictionary)[pferd_id]
			var pid := str(pferd_id)
			var erloes := DorfHaendler.verkaufspreis(gs, pid, bal)
			_zeile(
				str(eigenes.get("name", pid)),
				"%s +%d G" % [I18nService.t("rdorf.verkaufen"), erloes],
				func() -> void: _melde(DorfHaendler.pferd_verkaufen(gs, pid))
			)


func _fuelle_schmiede(gs: Object) -> void:
	var bal := DorfKatalog.load_balance()
	var dorf := RanchDorfState.lese(gs)
	var owned: Array = dorf["hufeisen"]["owned"]
	for eintrag: Variant in DorfKatalog.schmiede_waren(bal):
		var ware: Dictionary = eintrag
		var ware_id := str(ware["id"])
		if owned.has(ware_id):
			_zeile(
				I18nService.t("rdorf.waren.%s" % ware_id), I18nService.t("rdorf.besitz"), Callable()
			)
		else:
			_zeile(
				I18nService.t("rdorf.waren.%s" % ware_id),
				_kauf_text(int(ware["preis"])),
				func() -> void: _melde(DorfWirtschaft.schmiede_kaufen(gs, ware_id))
			)
	if owned.is_empty():
		return
	_ueberschrift(I18nService.t("rdorf.eigene_pferde"))
	var pro_pferd: Dictionary = dorf["hufeisen"]["proPferd"]
	var pferde: Variant = gs.get_value("ranch.tiere.pferde", {}) if gs != null else {}
	if not (pferde is Dictionary):
		return
	for pferd_id: Variant in (pferde as Dictionary).keys():
		var pid := str(pferd_id)
		var eigenes: Dictionary = (pferde as Dictionary)[pid]
		var aktuell := str(pro_pferd.get(pid, ""))
		var naechstes := _naechstes_hufeisen(owned, aktuell)
		var knopf_text := (
			I18nService.t("rdorf.hufeisen_abnehmen")
			if naechstes.is_empty()
			else (
				"%s: %s"
				% [
					I18nService.t("rdorf.hufeisen_anlegen"),
					I18nService.t("rdorf.waren.%s" % naechstes),
				]
			)
		)
		var zeile_name := str(eigenes.get("name", pid))
		if not aktuell.is_empty():
			zeile_name += " (%s)" % I18nService.t("rdorf.waren.%s" % aktuell)
		_zeile(
			zeile_name,
			knopf_text,
			func() -> void: _melde(DorfWirtschaft.hufeisen_anlegen(gs, pid, naechstes))
		)


## Durch die gekauften Sorten klicken: "" → erste → zweite → ... → "".
func _naechstes_hufeisen(owned: Array, aktuell: String) -> String:
	if aktuell.is_empty():
		return str(owned[0])
	var i := owned.find(aktuell)
	if i < 0 or i + 1 >= owned.size():
		return ""
	return str(owned[i + 1])


## ------------------------------------------------------------------ Bausteine


func _ueberschrift(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(INK, 0.85))
	_liste.add_child(label)


## Eine Waren-Zeile: Name links, Aktions-Knopf rechts (Callable() = nur Text).
func _zeile(titel: String, aktion: String, callback: Callable, tupfer := Color.TRANSPARENT) -> void:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	_liste.add_child(zeile)
	if tupfer.a > 0.0:
		var punkt := ColorRect.new()
		punkt.color = tupfer
		punkt.custom_minimum_size = Vector2(22, 22)
		zeile.add_child(punkt)
	var label := Label.new()
	label.text = titel
	label.add_theme_color_override("font_color", INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(label)
	if callback.is_null():
		var status := Label.new()
		status.text = aktion
		status.add_theme_color_override("font_color", Color(INK, 0.55))
		zeile.add_child(status)
		return
	var knopf := Button.new()
	knopf.text = aktion
	knopf.pressed.connect(callback)
	zeile.add_child(knopf)


func _kauf_text(preis: int) -> String:
	return "%s %d G" % [I18nService.t("rdorf.kaufen"), preis]


## Ergebnis einer Buchung melden (Fehler rot, Erfolg grün) + Liste erneuern.
func _melde(ergebnis: Dictionary) -> void:
	if bool(ergebnis.get("ok", false)):
		_feedback.add_theme_color_override("font_color", OK_GRUEN)
		_feedback.text = I18nService.t("rdorf.gekauft")
	else:
		_feedback.add_theme_color_override("font_color", FEHLER_ROT)
		_feedback.text = I18nService.t("rdorf.fehler.%s" % str(ergebnis.get("fehler", "unbekannt")))
	_feedback_t = 1.6
	_feedback.modulate.a = 1.0
	_refresh()
