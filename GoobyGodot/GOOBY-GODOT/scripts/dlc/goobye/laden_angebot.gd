class_name GoobyeLadenAngebot
extends Node
## Szenen-Glue des Tagesangebots (W19 Welle B, Doc §4.4): Leisten-Knopf +
## Auswahl-Sheet (1 Warengruppe pro Tag) + prozedurales Gooby-Kritzel-
## Angebotsschild am Regal. Die Regeln (−15 %, +40 % Griff, Tages-
## Determinismus über die injizierte Uhr) rechnet die PURE GoobyeAngebot —
## hier lebt nur UI. Die 6 Schild-Varianten sind bewusst einfache
## prozedurale Schilder (Papierfarbe + Neigung + Tinte); „richtige“
## Kritzel-Texturen dürfen in Welle C nachziehen.

const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")

## 6 Kritzel-Varianten (§4.4) — Index = GoobyeAngebot.schild_variante.
const SCHILD_STILE: Array[Dictionary] = [
	{"papier": "#FFF4E6", "tinte": "#4A3B36", "neigung": -8.0},
	{"papier": "#F2C94C", "tinte": "#4A3B36", "neigung": 5.0},
	{"papier": "#F2B5D4", "tinte": "#7A3B5E", "neigung": -4.0},
	{"papier": "#A7DCD6", "tinte": "#2F5D57", "neigung": 9.0},
	{"papier": "#FFD8A8", "tinte": "#7A4A1F", "neigung": -11.0},
	{"papier": "#CDEB8B", "tinte": "#3F6212", "neigung": 3.0},
]

## Kontrakt zur Szene (konfig in anbauen): gs, leiste, sheet_host,
## toast (Callable(text)), ist_einraeumen (Callable() -> bool),
## schild_pos (Vector3 — Anker überm Regal).
var gs: Object = null
var toast := Callable()
var ist_einraeumen := Callable()
var schild_pos := Vector3.ZERO

## Öffentlich für Tests: Leisten-Knopf, offenes Sheet, Schild-Node.
var knopf: SquishButton
var sheet: PanelSheet
var schild: Node3D

var _szene: Node3D
var _sheet_host: Node


static func anbauen(szene: Node3D, konfig: Dictionary) -> GoobyeLadenAngebot:
	var glue := GoobyeLadenAngebot.new()
	glue.name = "AngebotGlue"
	glue.gs = konfig.get("gs")
	glue.toast = konfig.get("toast", Callable())
	glue.ist_einraeumen = konfig.get("ist_einraeumen", Callable())
	glue.schild_pos = konfig.get("schild_pos", Vector3.ZERO)
	glue._szene = szene
	glue._sheet_host = konfig.get("sheet_host")
	szene.add_child(glue)
	glue._baue_knopf(konfig.get("leiste"))
	glue.aktualisiere()
	glue.schild_aktualisieren()
	return glue


## Knopf-Zustand (nur in der Einräum-Phase wählbar — Manager-Moment).
func aktualisiere() -> void:
	if knopf == null:
		return
	knopf.disabled = ist_einraeumen.is_valid() and not bool(ist_einraeumen.call())


## ------------------------------------------------------------ Auswahl-Sheet


func _zeige_sheet() -> void:
	if _sheet_host == null:
		return
	sheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	_sheet_host.add_child(sheet)
	sheet.closed.connect(sheet.queue_free)
	sheet.set_title(I18nService.t("dlc_goobye.tagesangebot.titel"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var hinweis := Label.new()
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("dlc_goobye.tagesangebot.hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hinweis)
	var aktiv := GoobyeAngebot.aktive_gruppe_von(gs)
	if not aktiv.is_empty():
		var zeile := Label.new()
		zeile.name = "AngebotAktiv"
		zeile.theme_type_variation = &"HeadlineLabel"
		zeile.text = I18nService.t("dlc_goobye.tagesangebot.aktiv", {"name": _gruppen_name(aktiv)})
		zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(zeile)
	for gruppe: Dictionary in GoobyeKatalog.gruppen():
		box.add_child(_baue_gruppen_knopf(gruppe))
	sheet.add_content(box)
	sheet.open()


## Gruppen-Knopf: Form+Farbe-Chip (Ⅰ§2.5 — nie nur Text) + „<Name> anbieten“.
func _baue_gruppen_knopf(gruppe: Dictionary) -> Control:
	var gruppe_id := str(gruppe["id"])
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(18.0, 18.0)
	chip.color = Color(str(gruppe.get("farbe", "#CCCCCC")))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if str(gruppe.get("form", "")) == "raute":
		chip.rotation_degrees = 45.0
	zeile.add_child(chip)
	var b := SquishButton.new()
	b.name = "Angebot_" + gruppe_id
	b.theme_type_variation = &"BtnGhost"
	b.text = I18nService.t(
		"dlc_goobye.tagesangebot.waehlen", {"name": I18nService.t(str(gruppe.get("name_key", "")))}
	)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_waehle.bind(gruppe_id))
	zeile.add_child(b)
	return zeile


## Wahl: der AUSGANG klingt (AUDIO-GRAMMATIK) — ok = Schild hängt.
func _waehle(gruppe_id: String) -> void:
	match GoobyeAngebot.waehle(gs, gruppe_id):
		GoobyeAngebot.RESULT_OK:
			AudioDirector.try_play(self, "ui_confirm")
			Haptics.success(self)
			_toast(
				I18nService.t(
					"dlc_goobye.tagesangebot.gewaehlt", {"name": _gruppen_name(gruppe_id)}
				)
			)
			schild_aktualisieren()
			if sheet != null:
				sheet.close()
				sheet = null
		GoobyeAngebot.RESULT_SCHON_GEWAEHLT:
			AudioDirector.try_play(self, "ui_error")
			Haptics.warn(self)
			_toast(I18nService.t("dlc_goobye.tagesangebot.schon_gewaehlt"))
		_:
			AudioDirector.try_play(self, "ui_error")


## ------------------------------------------------------------ Kritzel-Schild


## Schild neu bauen: hängt NUR, wenn heute ein Angebot aktiv ist. Variante
## deterministisch aus Tag + Gruppe (GoobyeAngebot.schild_variante).
func schild_aktualisieren() -> void:
	if schild != null:
		schild.queue_free()
		schild = null
	var gruppe_id := GoobyeAngebot.aktive_gruppe_von(gs)
	if gruppe_id.is_empty() or _szene == null:
		return
	var tag := GoobyeAngebot.tag_key(_jetzt_ms())
	var stil: Dictionary = SCHILD_STILE[GoobyeAngebot.schild_variante(tag, gruppe_id)]
	schild = Node3D.new()
	schild.name = "AngebotsSchild"
	schild.position = schild_pos
	schild.rotation_degrees.z = float(stil["neigung"])
	var papier := MeshInstance3D.new()
	var brett := BoxMesh.new()
	brett.size = Vector3(0.66, 0.44, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(stil["papier"]))
	brett.material = mat
	papier.mesh = brett
	schild.add_child(papier)
	schild.add_child(_schild_text(I18nService.t("dlc_goobye.tagesangebot.schild"), 0.09, stil, 72))
	schild.add_child(_schild_text(_gruppen_name(gruppe_id), -0.1, stil, 44))
	_szene.add_child(schild)


func _schild_text(text: String, hoehe: float, stil: Dictionary, groesse: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = groesse
	label.pixel_size = 0.003
	label.modulate = Color(str(stil["tinte"]))
	label.position = Vector3(0.0, hoehe, 0.025)
	return label


## ------------------------------------------------------------ Helfer


func _baue_knopf(leiste: Container) -> void:
	knopf = SquishButton.new()
	knopf.name = "Tagesangebot"
	knopf.theme_type_variation = &"BtnGhost"
	knopf.text = I18nService.t("dlc_goobye.tagesangebot.knopf")
	knopf.focus_mode = Control.FOCUS_NONE
	knopf.pressed.connect(_zeige_sheet)
	if leiste != null:
		leiste.add_child(knopf)


func _gruppen_name(gruppe_id: String) -> String:
	return I18nService.t(str(GoobyeKatalog.gruppe(gruppe_id).get("name_key", "")))


func _toast(text: String) -> void:
	if toast.is_valid():
		toast.call(text)


func _jetzt_ms() -> int:
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
