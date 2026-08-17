class_name AcnhKit
extends RefCounted
## W21/ACNH — DIE Kern-Bausteine des Redesigns (UI-DESIGN-ACNH §5). Builder
## liefern fertig verdrahtete Controls im neuen Look; Größen kommen aus den
## AcTokens-Skalen (×f über AcTokens.px, round()-Konvention), Bewegung aus
## MotionKit. Area-Agents bauen ihre Flächen DIREKT hierauf.
##
## API (alle statisch):
##   AcnhKit.stat_kapsel(icon, farbe, bar_variation, f) -> PanelContainer
##       kompakte Stat-Zeile (Icon + Mini-Balken); Kinder heißen "Zeile",
##       "Zeile/Icon", "Zeile/Bar" — Standardrolle StatKapselMitte.
##   AcnhKit.stat_kapsel_gruppe(zeilen) -> VBoxContainer
##       stapelt Zeilen zur EINEN Kapsel-Gruppe (Separation 0 + Rollen).
##   AcnhKit.segment_rollen(zeilen)
##       vergibt Kopf/Mitte/Fuss nach Position (1 Zeile → StatusCapsule).
##   AcnhKit.gruppen_breite_angleichen(zeilen)
##       klemmt alle Zeilen auf EINE Gruppenbreite (breiteste Zeile).
##   AcnhKit.icon_button(icon, f, kompakt=false) -> Button
##       runder Soft-Outline-Knopf (SquishButton, HudIconButton-Rolle);
##       zwei Größen: BTN_H_PRIMAER / BTN_H_KOMPAKT.
##   AcnhKit.papier_karte(gross=false) -> PanelContainer
##       Papier-Karte (AcCard bzw. AcCardLg — Radien-Skala, Schatten-Pop).
##   AcnhKit.blatt_kopf(titel, on_back) -> AcScreenHeader
##       Blatt-/Screen-Kopf (W20-Grammatik: Zurück links, Titel mittig).
##   AcnhKit.kontext_dock(inhalt, griff_text, f) -> AcnhKit.KontextDock
##       einklappbare Frost-Leiste (KontextDock-Rolle) mit Griff-Zeile;
##       `klappe(zu)` animiert über MotionKit, Signal `zustand_geaendert`.

## Mini-Balken-Breite in einer Stat-Kapsel-Zeile (Design-px, ×f).
const BAR_W_MINI := 44.0


## Einklappbare Kontext-Leiste (Baumodus-Lager, Werkzeug-Docks): Griff-Zeile
## bleibt immer sichtbar, der Inhalt klappt ein/aus (Reduced-Motion-gated
## über MotionKit). Bewusst als Kit-Unterklasse — Area-Agents instanzieren
## über AcnhKit.kontext_dock().
class KontextDock:
	extends PanelContainer

	signal zustand_geaendert(eingeklappt: bool)

	var griff: Button
	var inhalt: Control

	var _eingeklappt := false

	func ist_eingeklappt() -> bool:
		return _eingeklappt

	func klappe(zu: bool) -> void:
		if zu == _eingeklappt:
			return
		_eingeklappt = zu
		inhalt.visible = not zu
		if not zu:
			MotionKit.blatt_slide_in(inhalt)
		_griff_pfeil()
		zustand_geaendert.emit(zu)

	func _griff_pfeil() -> void:
		var titel: String = griff.get_meta(&"acnh_griff_titel", "")
		griff.text = "%s  %s" % ["▸" if _eingeklappt else "▾", titel]


## Kompakte Stat-Zeile: farbiges Icon + Mini-Balken auf einer Frost-Kapsel-
## Zeile (Rolle StatKapselMitte; segment_rollen vergibt Kopf/Fuss).
static func stat_kapsel(
	icon: Texture2D, farbe: Color, bar_variation: StringName, f: float
) -> PanelContainer:
	var kapsel := PanelContainer.new()
	kapsel.theme_type_variation = &"StatKapselMitte"
	kapsel.mouse_filter = Control.MOUSE_FILTER_PASS
	var zeile := HBoxContainer.new()
	zeile.name = "Zeile"
	zeile.add_theme_constant_override("separation", AcTokens.px(AcTokens.SPACE_S, f))
	zeile.alignment = BoxContainer.ALIGNMENT_CENTER
	zeile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kapsel.add_child(zeile)
	var bild := TextureRect.new()
	bild.name = "Icon"
	bild.texture = icon
	bild.custom_minimum_size = Vector2.ONE * AcTokens.px(AcTokens.ICON_M, f)
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bild.self_modulate = farbe
	bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(bild)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.theme_type_variation = bar_variation
	bar.custom_minimum_size = Vector2(AcTokens.px(BAR_W_MINI, f), AcTokens.px(AcTokens.BAR_H, f))
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(bar)
	return kapsel


## Zeilen zur EINEN Kapsel-Gruppe stapeln: Separation 0, Segment-Rollen,
## einheitliche Breite — die Gruppe liest sich als EIN Element.
static func stat_kapsel_gruppe(zeilen: Array) -> VBoxContainer:
	var gruppe := VBoxContainer.new()
	gruppe.name = "StatKapselGruppe"
	gruppe.add_theme_constant_override("separation", 0)
	gruppe.mouse_filter = Control.MOUSE_FILTER_PASS
	for zeile: Control in zeilen:
		gruppe.add_child(zeile)
	segment_rollen(zeilen)
	gruppen_breite_angleichen(zeilen)
	return gruppe


## Kopf/Mitte/Fuss nach Position: erste Zeile oben gerundet, letzte unten;
## eine einzelne Zeile bleibt eine ganze Pill (StatusCapsule).
static func segment_rollen(zeilen: Array) -> void:
	if zeilen.is_empty():
		return
	if zeilen.size() == 1:
		(zeilen[0] as Control).theme_type_variation = &"StatusCapsule"
		return
	for i in zeilen.size():
		var zeile := zeilen[i] as Control
		if i == 0:
			zeile.theme_type_variation = &"StatKapselKopf"
		elif i == zeilen.size() - 1:
			zeile.theme_type_variation = &"StatKapselFuss"
		else:
			zeile.theme_type_variation = &"StatKapselMitte"


## Alle Zeilen auf EINE Gruppenbreite klemmen (breiteste Zeile gewinnt) —
## sonst wäre jedes Segment nur so breit wie sein eigener Inhalt.
static func gruppen_breite_angleichen(zeilen: Array) -> void:
	var breite := 0.0
	for zeile: Control in zeilen:
		zeile.custom_minimum_size.x = 0.0
		breite = maxf(breite, zeile.get_combined_minimum_size().x)
	for zeile: Control in zeilen:
		zeile.custom_minimum_size.x = breite


## Runder Icon-Knopf mit Soft-Outline (Frost, Boden-Lippe): GENAU zwei
## Größen — Primär (BTN_H_PRIMAER) und Kompakt (BTN_H_KOMPAKT/Touch-Floor).
static func icon_button(icon: Texture2D, f: float, kompakt := false) -> Button:
	var btn := SquishButton.new()
	btn.theme_type_variation = &"HudIconButton"
	btn.icon = icon
	btn.expand_icon = false
	btn.focus_mode = Control.FOCUS_NONE
	var h := AcTokens.BTN_H_KOMPAKT if kompakt else AcTokens.BTN_H_PRIMAER
	btn.custom_minimum_size = Vector2.ONE * float(AcTokens.px(float(h), f))
	var icon_basis := AcTokens.ICON_M if kompakt else AcTokens.ICON_L
	btn.add_theme_constant_override("icon_max_width", AcTokens.px(float(icon_basis), f))
	return btn


## Papier-Karte: warme Paper-Fläche, Radien-Skala (28/36), Schatten-Pop.
static func papier_karte(gross := false) -> PanelContainer:
	var karte := PanelContainer.new()
	karte.theme_type_variation = &"AcCardLg" if gross else &"AcCard"
	return karte


## Blatt-/Screen-Kopf: EINE Kopfzeilen-Grammatik (W20 AcScreenHeader —
## Zurück-Pill links, Titel mittig, Chips rechts). `apply_metrics(m)` beim
## Screen-Metrics-Pass rufen (Touch-Floor + Schriften).
static func blatt_kopf(titel: String, on_back := Callable()) -> AcScreenHeader:
	return AcScreenHeader.build(titel, on_back)


## Einklappbare Kontext-Leiste: Griff-Zeile + Inhalt in einer Frost-Karte
## (KontextDock-Rolle). Griff-Tap klappt ein/aus (MotionKit-Blatt-Slide).
static func kontext_dock(inhalt: Control, griff_text: String, f: float) -> KontextDock:
	var dock := KontextDock.new()
	dock.theme_type_variation = &"KontextDock"
	var spalte := VBoxContainer.new()
	spalte.name = "DockSpalte"
	spalte.add_theme_constant_override("separation", AcTokens.px(AcTokens.SPACE_S, f))
	dock.add_child(spalte)
	var griff := SquishButton.new()
	griff.name = "Griff"
	griff.theme_type_variation = &"AcChip"
	griff.focus_mode = Control.FOCUS_NONE
	griff.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	griff.custom_minimum_size = Vector2(
		float(AcTokens.px(float(AcTokens.BTN_H_KOMPAKT * 2), f)),
		float(AcTokens.px(float(AcTokens.BTN_H_KOMPAKT), f))
	)
	griff.set_meta(&"acnh_griff_titel", griff_text)
	spalte.add_child(griff)
	inhalt.name = "Inhalt"
	spalte.add_child(inhalt)
	dock.griff = griff
	dock.inhalt = inhalt
	dock._griff_pfeil()
	griff.pressed.connect(func() -> void: dock.klappe(not dock.ist_eingeklappt()))
	return dock
