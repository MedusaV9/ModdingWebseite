class_name RanchStammbaumPanel
extends PanelContainer
## Stammbaum-Ansicht (RW-2, IDEAS-3 Kap. 4.5): drei Generationen als
## gemalte PORTRAETS — Gene erscheinen NIRGENDS als Buchstaben. Unten
## das Fohlen mit "Geerbt"-Badges (Glueckswuerfe + Glitzer-Geheimnis),
## darueber Mutter/Vater, oben die Grosseltern aus den Snapshots
## (RanchHorseBreeding.eltern_snapshot, max 1 Ahnen-Ebene).
##
## Einbau: panel.setup(fohlen_dict) VOR add_child; das Panel ist ein
## normales Control (Popup/Screen-Einbettung macht der Aufrufer).

const Breeding := preload("res://scripts/ranch/gameplay/horse_breeding.gd")

const INK := Color("#3B3630")
const CREME := Color("#FFF6E8")
const GOLD := Color("#F2B04C")

var fohlen: Dictionary = {}


func setup(fohlen_dict: Dictionary) -> void:
	fohlen = fohlen_dict.duplicate(true)


func _ready() -> void:
	custom_minimum_size = Vector2(560.0, 520.0)
	var wurzel := VBoxContainer.new()
	wurzel.add_theme_constant_override("separation", 14)
	add_child(wurzel)
	var titel := Label.new()
	titel.text = I18nService.t("rpferd.stammbaum.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_font_size_override("font_size", 26)
	wurzel.add_child(titel)
	var ahnen := _dict(fohlen, "ahnen")
	var mutter := _dict(ahnen, "mutter")
	var vater := _dict(ahnen, "vater")
	wurzel.add_child(_reihe(_grosseltern(mutter) + _grosseltern(vater), 0.62))
	var eltern_reihe := _reihe([], 1.0)
	eltern_reihe.add_child(_portraet(mutter, I18nService.t("rpferd.stammbaum.mutter"), 0.85))
	eltern_reihe.add_child(_portraet(vater, I18nService.t("rpferd.stammbaum.vater"), 0.85))
	wurzel.add_child(eltern_reihe)
	var fohlen_reihe := _reihe([], 1.0)
	fohlen_reihe.add_child(_portraet(fohlen, I18nService.t("rpferd.stammbaum.fohlen"), 1.0))
	wurzel.add_child(fohlen_reihe)
	wurzel.add_child(_badges())


## Grosseltern-Portraets eines Eltern-Snapshots (0–2 Stueck).
func _grosseltern(elter: Dictionary) -> Array:
	var out: Array = []
	var ahnen := _dict(elter, "ahnen")
	for rolle: String in ["mutter", "vater"]:
		if ahnen.get(rolle) is Dictionary:
			var rollen_text := I18nService.t("rpferd.stammbaum.%s" % rolle)
			out.append(_portraet(ahnen[rolle], rollen_text, 0.62))
	return out


func _reihe(kinder: Array, _skala: float) -> HBoxContainer:
	var reihe := HBoxContainer.new()
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	reihe.add_theme_constant_override("separation", 18)
	for kind: Variant in kinder:
		reihe.add_child(kind)
	return reihe


func _portraet(pferd: Dictionary, rolle: String, skala: float) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var bild := PferdPortraet.new()
	bild.pferd = pferd
	bild.custom_minimum_size = Vector2(110.0, 92.0) * skala
	box.add_child(bild)
	var name_label := Label.new()
	var unbekannt := I18nService.t("rpferd.stammbaum.unbekannt")
	var pferd_name := str(pferd.get("name", ""))
	name_label.text = pferd_name if pferd_name != "" else unbekannt
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", int(16.0 * skala) + 2)
	box.add_child(name_label)
	var info := Label.new()
	var rasse_key := "rpferd.rasse.%s" % pferd.get("rasse", "")
	var rasse_text := I18nService.t(rasse_key) if I18nService.has_key(rasse_key) else ""
	info.text = "%s · %s" % [rolle, rasse_text] if rasse_text != "" else rolle
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", int(12.0 * skala) + 1)
	info.modulate.a = 0.75
	box.add_child(info)
	return box


## "Geerbt"-Chips: Glueckswuerfe je Stat + Glitzer-Geheimnis — statt Zahlen.
func _badges() -> Control:
	var reihe := HBoxContainer.new()
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	reihe.add_theme_constant_override("separation", 8)
	for badge: Variant in Breeding.erbe_badges(fohlen):
		var chip := PanelContainer.new()
		var stil := StyleBoxFlat.new()
		stil.bg_color = GOLD if str(badge) == "glitzer" else Color(CREME.r, CREME.g, CREME.b, 0.85)
		stil.set_corner_radius_all(9)
		stil.set_content_margin_all(6.0)
		chip.add_theme_stylebox_override("panel", stil)
		var text := Label.new()
		if str(badge) == "glitzer":
			text.text = I18nService.t("rpferd.stammbaum.erbe_glitzer")
		else:
			var stat := I18nService.t("rpferd.stat.%s" % badge)
			text.text = I18nService.t("rpferd.stammbaum.erbe_stat", {"stat": stat})
		text.add_theme_font_size_override("font_size", 13)
		text.add_theme_color_override("font_color", INK)
		chip.add_child(text)
		reihe.add_child(chip)
	return reihe


static func _dict(d: Dictionary, key: String) -> Dictionary:
	var raw: Variant = d.get(key)
	return raw if raw is Dictionary else {}


## Gemaltes Pferdekopf-Portraet: Fell-/Maehnenfarbe + Abzeichen sichtbar,
## Glitzer als Sternpunkte — kindgerechte Vererbung OHNE Genbuchstaben.
class PferdPortraet:
	extends Control

	var pferd: Dictionary = {}

	func _draw() -> void:
		var farb_id := str(pferd.get("farbe", "braun"))
		var farben: Array = RanchPferd.FELL.get(farb_id, RanchPferd.FELL["braun"])
		var fell: Color = farben[0]
		var maehne: Color = farben[1]
		var mitte := size * 0.5
		var r := minf(size.x, size.y) * 0.34
		# Rahmen-Karte
		var stil_rect := Rect2(Vector2.ZERO, size)
		draw_rect(stil_rect, Color(1.0, 0.98, 0.94, 0.9))
		draw_rect(stil_rect, Color("#3B3630"), false, 2.0)
		# Ohren, Kopf, Blesse/Stern, Maehne, Auge, Nuestern
		var ohr_l := mitte + Vector2(-r * 0.62, -r * 1.05)
		var ohr_r := mitte + Vector2(r * 0.62, -r * 1.05)
		for ohr: Vector2 in [ohr_l, ohr_r]:
			draw_circle(ohr, r * 0.3, fell)
		draw_circle(mitte, r, fell)
		draw_circle(mitte + Vector2(0.0, r * 0.55), r * 0.6, fell.lerp(Color.WHITE, 0.25))
		var abzeichen: Dictionary = (
			pferd.get("abzeichen") if pferd.get("abzeichen") is Dictionary else {}
		)
		if bool(abzeichen.get("blesse", false)):
			draw_rect(
				Rect2(mitte + Vector2(-r * 0.12, -r * 0.7), Vector2(r * 0.24, r * 1.1)),
				Color("#F7F1E4")
			)
		elif bool(abzeichen.get("stern", false)):
			draw_circle(mitte + Vector2(0.0, -r * 0.5), r * 0.18, Color("#F7F1E4"))
		draw_arc(
			mitte + Vector2(0.0, -r * 0.12), r * 0.94, PI * 1.15, PI * 1.85, 18, maehne, r * 0.34
		)
		draw_circle(mitte + Vector2(-r * 0.38, -r * 0.1), r * 0.11, Color("#3A2E2E"))
		draw_circle(mitte + Vector2(r * 0.38, -r * 0.1), r * 0.11, Color("#3A2E2E"))
		draw_circle(mitte + Vector2(-r * 0.2, r * 0.62), r * 0.06, Color("#4A2B33"))
		draw_circle(mitte + Vector2(r * 0.2, r * 0.62), r * 0.06, Color("#4A2B33"))
		var gene: Dictionary = pferd.get("gene") if pferd.get("gene") is Dictionary else {}
		if RanchRassen.ist_schecke(gene):
			draw_circle(mitte + Vector2(r * 0.55, r * 0.3), r * 0.22, Color("#F7F1E4"))
			draw_circle(mitte + Vector2(-r * 0.6, r * 0.45), r * 0.16, Color("#F7F1E4"))
		if RanchRassen.ist_glitzer(gene):
			for punkt: Vector2 in [
				Vector2(-0.7, -0.55), Vector2(0.75, -0.4), Vector2(0.5, 0.75), Vector2(-0.45, 0.7)
			]:
				draw_circle(mitte + punkt * r, r * 0.07, Color("#FFF2AF"))
