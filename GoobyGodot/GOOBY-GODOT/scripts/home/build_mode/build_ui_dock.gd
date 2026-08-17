class_name BuildUiDock
extends RefCounted
## G4/UI-BAU → W21 P2 „Welt zuerst“: Aufbau + Metrik-Pass des Baumodus-UIs.
## Der User-Frust der W21-Evaluierung („beim Bauen sieht man nichts außer
## die Knöpfe“, nur 59,1 % Welt beim Platzieren) kippt das Layout: das Lager
## ist ein AcnhKit.kontext_dock (einklappbare Frost-Leiste, STARTET
## EINGEKLAPPT) unten-mittig FLUSH an der Bildkante; eingeklappt bleibt nur
## die Griff-Zeile (Griff mit Stück-Zahl + Kategorie-Chips + Fertig),
## aufgeklappt kommt das Item-Blatt (Bild-Chips mit Zähler-Badge) dazu.
## Kamera wird eine schmale Icon-Spalte am rechten Rand, Presets/Goobay
## transluzente Icon-Chips oben links — die Welt bleibt frei.
##
## ZEILEN-CHOREOGRAPHIE (W20-P2c-Prinzip weitergedacht, ein Zustand = EINE
## Knopf-Zeile im Dock):
##   RUHE     Griff-Zeile + Ebenen-Zeile (Blatt zu)
##   BLATT    Griff-Zeile + Item-Blatt (Ebenen-Zeile duckt sich — beim
##            Stöbern wählt das Item seine Ebene selbst)
##   WERKZEUG Action-Zeile (Drehen/Platzieren/Einlagern/Abbrechen + Fertig)
##            — Griff-, Ebenen-Zeile und Blatt ducken sich komplett
## „Fertig“ wandert dabei als EIN Knoten zwischen Griff- und Action-Zeile
## (set_action_bar_offen) — er bleibt in JEDEM Zustand sichtbar und oben
## (Hit-Reihenfolge-Wache test_w20_bau_layout).
##
## SPERRZONEN-SCHNITTSTELLE (W20 P2c, für P1-Ausweich-Lanes von
## Sprechblasen/Toasts — keine Datei-Kollision, nur Aufrufe von außen):
##   BuildUiDock.aktive_zone() -> Rect2   [statisch]
##     Die vom Bau-Dock belegte Bildschirm-Zone in CANVAS-Koordinaten —
##     VOLL ausgebaut (aufgeklapptes Blatt + Ebenen-Zeile), damit die Zone
##     beim Werkzeug-/Klapp-Wechsel nicht springt. Rect2() = kein Dock.
##   dock_zone() -> Rect2                 [Instanz, gleicher Vertrag]
## Die Kamera-Spalte rechts und die Ecken-Chips links liegen bewusst NICHT
## in der Zone (eigene Randflächen); zusätzlich meldet BuildMode das Dock
## weiter als UiAnchors.ZONE_BOTTOM-Belegung an (bestehender dodge()-Weg).
##
## Diese Klasse baut NUR Layout und Metrik; Verhalten (pressed-Handler,
## Sounds, Klapp-Zeitpunkte) verdrahtet BuildMode auf den exponierten
## Knöpfen und den klappe_lager()/set_action_bar_offen()-Hebeln.

## VIS-2-Erbe: Mindest-Innenabstand der Lager-Fläche — kein Chip darf
## bündig an einer Kante starten (abgeschnittene Namen im Trailer-Review).
const DRAWER_RAND_X := 28.0
## Design-Basisbreite des Docks (Klemm-Deckel über ScreenShell.card_width —
## die echte Breite hugt den Zeilen-Inhalt und ist meist schmaler).
const DOCK_BASIS := 920.0
## Abstand zwischen Dock-Zeilen (Ebenen-Zeile / Lager-Leiste), Design-px.
const DOCK_LUFT := 10.0
## Pflicht-Luft zwischen Dock und Kamera-Spalte (Design-px, ×f).
const KAMERA_LUFT := 16.0
## Bild-Chip-Maße des Item-Blatts (Design-px, ×f): Thumb + Kurzname-Zeile.
## Höhe knapp überm natürlichen Inhalts-Minimum — jeder Design-px des
## offenen Blatts geht vom Welt-Budget ab (test_w21_bau_welt).
const CHIP_BREITE := 96.0
const CHIP_HOEHE := 66.0
## Icon-Fläche im Bild-Chip (Design-px) — CraftVorschau-Textur bzw.
## Kategorie-Icon-Fallback, solange die Bäckerei noch backt.
const CHIP_THUMB := 40.0
## Meta-Key: Design-Mindestmaß eines Knopfs (Vector2, ×f) — floors_und_
## schrift respektiert es ZUSÄTZLICH zum Touch-Floor (Bild-Chips wären
## sonst auf floor_px×floor_px gestutzt).
const META_MIN := "bau_design_min"
## Meta-Key: Icon-Basisgröße eines Icon-Chips (Design-px, ×f im Metrik-Pass).
const META_ICON := "bau_icon_basis"
## Kategorie → Icon (assets/ui/icons) — Fallback „sparkle“ für Unbekanntes.
const KAT_ICONS := {
	"schlafen": "moon",
	"sitzen": "sofa",
	"tische": "kat_tisch",
	"regale": "book",
	"lampen": "kat_lampe",
	"unterhaltung": "gamepad",
	"teppiche": "kat_teppich",
	"pflanzen": "kat_blume",
	"kueche": "hunger",
	"bad": "hygiene",
	"deko": "sparkle",
	"garten": "leaf",
	"wohnen": "home",
	"fenster": "eye",
	"bilder": "brush",
	"party": "gift",
	"girlanden": "kat_girlande",
	"buero": "gear",
}

## W20 P2c: schwache Referenz aufs zuletzt gebaute Dock — Grundlage der
## statischen Sperrzonen-Abfrage aktive_zone() (Datei-Kopf).
static var _aktive_ref: WeakRef = null

var ui: Control
var dock: VBoxContainer
## Das einklappbare Lager (AcnhKit.KontextDock, PanelContainer) — Tests
## referenzieren es weiter als `drawer` (Zeilen-Disjunktheit W20).
var kontext: AcnhKit.KontextDock
var drawer: PanelContainer
var griff_zeile: HFlowContainer
var kat_chips: Array[Button] = []
## W18 Befund 6: Fade-Kanten + Endpolster als Überlauf-Affordance der
## Lager-Chips (ScrollFade-Muster) — bleiben im Item-Blatt erhalten.
var drawer_fade: ScrollFade
var drawer_polster: MarginContainer
var drawer_items: HBoxContainer
var action_bar: HFlowContainer
var action_buttons: Array[Button] = []
var kamera_leiste: VBoxContainer
var kamera_buttons: Array[Button] = []
var ecke_links: HBoxContainer
var ebenen_leiste: HFlowContainer
var ebenen_chips: Array[Button] = []
var status_label: Label
var presets_button: Button
var goobay_button: Button
var done_button: Button
## Letzter Metrik-Pass (ScreenShell.metrics) — Chip-Rebuilds flooren damit
## frisch gebaute Knöpfe ohne neuen Viewport-Pass.
var m: Dictionary = {}
## Ergebnis des letzten Metrik-Passes: final gewählte Dock-Breite + voll
## ausgebaute Dock-Höhe — dock_zone() liest beides.
var _dock_breite := 0.0
var _dock_hoehe_voll_px := 0.0
## Kapazitäts-Text in Voll- und Kurzform — der Fit-Pass wählt nach der
## Dock-Klemme (W21-Erbe: die Ellipse fraß hochkant genau die Zahl).
var _capacity_voll := ""
var _capacity_kurz := ""
var _saferand: MarginContainer
var _blatt: ScrollContainer


## Sperrzone des Bau-Docks in Canvas-Koordinaten (Vertrag im Datei-Kopf) —
## Rect2() = kein Dock gebaut/sichtbar/messbar.
static func aktive_zone() -> Rect2:
	if _aktive_ref == null:
		return Rect2()
	var dock_ui: BuildUiDock = _aktive_ref.get_ref()
	if dock_ui == null or dock_ui.ui == null or not is_instance_valid(dock_ui.ui):
		return Rect2()
	if not dock_ui.ui.is_inside_tree() or not dock_ui.ui.visible:
		return Rect2()
	return dock_ui.dock_zone()


## PURE Umbruch-Schätzung eines HFlow: greedy Zeilenfüllung über die
## Kind-Minima. Die Live-Minima der Flows kennen ihren Umbruch erst NACH
## dem Layout-Pass — die Höhen-Schätzung der Zone braucht ihn davor
## (headless testbar, tests/unit/test_w20_bau_layout.gd).
static func flow_umbruch_hoehe(
	minima: Array[Vector2], breite: float, h_sep: float, v_sep: float
) -> float:
	var hoehe := 0.0
	var zeile := 0.0
	var x := -1.0
	for mind in minima:
		var neu := mind.x if x < 0.0 else x + h_sep + mind.x
		if x >= 0.0 and neu > breite:
			hoehe += zeile + v_sep
			x = mind.x
			zeile = mind.y
		else:
			x = neu
			zeile = maxf(zeile, mind.y)
	return hoehe + zeile


func build(ui_layer: Node, ebenen_keys: Array[String]) -> void:
	ui = Control.new()
	ui.name = "BuildModeUi"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.visible = false
	ui_layer.add_child(ui)
	# W20 P2c: als aktives Dock für die statische Sperrzonen-Abfrage
	# registrieren (weak — der Raum-Abbau räumt die Referenz mit ab).
	_aktive_ref = weakref(self)
	_build_kamera_leiste()
	_build_ecke_links()
	_build_dock(ebenen_keys)
	# Metrik-Pass erst verdrahten, wenn der Viewport existiert (Setup kann
	# vor dem Einhängen des Raums in den Baum laufen).
	if ui.is_inside_tree():
		_im_baum()
	else:
		ui.tree_entered.connect(_im_baum, CONNECT_ONE_SHOT)


## EIN Metrik-Pass für das komplette Bau-UI: Zeilen-Separations, Safe-Area-
## Polster, Touch-Floor/Schriften, Kapazitäts-Fit, Dock-Breite (hugt den
## Zeilen-Inhalt, gedeckelt über card_width) und die Randflächen (Kamera-
## Spalte rechts, Ecken-Chips links). Läuft beim Aufbau, bei jeder
## Viewport-Größenänderung und nach Chip-Rebuilds.
func apply_metrics() -> void:
	if ui == null or not ui.is_inside_tree():
		return
	m = ScreenShell.metrics(ui.get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var canvas: Vector2 = m["canvas"]
	dock.add_theme_constant_override("separation", int(DOCK_LUFT * f))
	kamera_leiste.add_theme_constant_override("separation", int(8.0 * f))
	ecke_links.add_theme_constant_override("separation", int(8.0 * f))
	for flow: HFlowContainer in [griff_zeile, action_bar, ebenen_leiste]:
		flow.add_theme_constant_override("h_separation", int(10.0 * f))
		flow.add_theme_constant_override("v_separation", int(8.0 * f))
	# Home-Indicator-Polster: das Dock sitzt FLUSH an der Unterkante
	# (KontextDock-Rolle rundet nur oben) — die Knöpfe bleiben überm Inset.
	_saferand.add_theme_constant_override("margin_bottom", int(float(insets["bottom"])))
	if drawer_fade != null:
		drawer_fade.kanten_hoehe(ScrollFade.KANTE * f)
		drawer_polster.add_theme_constant_override("margin_right", roundi(ScrollFade.KANTE * f))
		drawer_polster.add_theme_constant_override("margin_left", int(8.0 * f))
	_blatt.custom_minimum_size = Vector2(0.0, (CHIP_HOEHE + 12.0) * f)
	# Floors/Schriften/Icon-Größen VOR der Breiten-Schätzung — die Klemme
	# misst fertig skalierte Knopf-Minima.
	floors_und_schrift()
	var klemme := ScreenShell.card_width(m, DOCK_BASIS)
	# Kapazitäts-Fit gegen die Klemme: Kurzform, bevor die Zeile umbricht.
	_capacity_fit_gegen(klemme)
	var breite := minf(maxf(_panel_wunsch_breite(), _zeile_wunsch_breite(ebenen_leiste)), klemme)
	_dock_breite = breite
	_dock_hoehe_voll_px = _dock_hoehe_voll(breite)
	drawer.custom_minimum_size.x = minf(_panel_wunsch_breite(), breite)
	dock.anchor_left = 0.5
	dock.anchor_right = 0.5
	dock.anchor_top = 1.0
	dock.anchor_bottom = 1.0
	dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.offset_left = -breite * 0.5
	dock.offset_right = breite * 0.5
	dock.offset_bottom = 0.0
	# Höhe EXPLIZIT auf die Kind-Minima ziehen (Unterkante bleibt flush):
	# der Grow-BEGIN-Mechanismus feuert nur bei WACHSENDEN Minima — ein
	# erneuter Metrik-Pass ohne Min-Änderung ließe das Dock sonst auf
	# Offset-Höhe zusammenfallen und die Zeilen unter die Bildkante laufen.
	_hoehe_nachziehen()
	# Flow-Umbrüche kennen ihre Breite erst nach dem Layout-Pass — die Höhe
	# einmal nachgelagert nachziehen.
	_hoehe_nachziehen.call_deferred()
	_kamera_platzieren(f, insets, canvas)
	ecke_links.offset_left = float(insets["left"]) + ScreenShell.EDGE_X * f
	ecke_links.offset_top = float(insets["top"]) + ScreenShell.EDGE_Y * f
	# Blatt-Slot nach dem Layout-Pass primen (deckt auch den manuellen
	# Griff-Tap ab, der DIREKT übers Kit klappt — vorbei an klappe_lager).
	_blatt_slot_primen.call_deferred()


## Kapazitäts-Text (Griff-Titel) setzen — Voll-/Kurzform nach Platz
## („Lager 6/100“ bzw. „6/100“, W21: keine Zahlen-Ellipse).
func set_capacity_text(used: int, cap: int) -> void:
	var args := {"used": used, "cap": cap}
	_capacity_voll = I18nService.t("build.lager", args)
	_capacity_kurz = I18nService.t("build.lager_kurz", args)
	_capacity_fit_gegen(_dock_breite if _dock_breite > 0.0 else 100000.0)


## Touch-Floor (44 pt physisch) auf ALLE Bau-Knöpfe + Theme-Schriften ×f.
## Bild-/Icon-Chips tragen ihr Design-Mindestmaß in META_MIN (×f) — der
## Floor gilt zusätzlich; Text-Pillen behalten ihre text-basierte Breite.
func floors_und_schrift() -> void:
	if m.is_empty() or ui == null:
		return
	var f: float = m["f"]
	var floor_px: float = m["floor_px"]
	for node in ui.find_children("*", "Button", true, false):
		var btn := node as Control
		var mindest := Vector2(floor_px, floor_px)
		if btn.has_meta(META_MIN):
			var design: Vector2 = btn.get_meta(META_MIN)
			mindest = mindest.max(design * f)
		btn.custom_minimum_size = mindest
		if btn.has_meta(META_ICON):
			var basis := float(btn.get_meta(META_ICON))
			btn.add_theme_constant_override("icon_max_width", AcTokens.px(basis, f))
	ScreenShell.scale_fonts(ui, f)


## VOLL ausgebaute Dock-Zone in Canvas-Koordinaten — aufgeklapptes Blatt +
## Ebenen-Zeile, auch wenn gerade eingeklappt/geduckt (W18 Befund 2: der
## Ghost spawnte exakt hinter der Knopfleiste; die Zone darf beim
## Werkzeug-/Klapp-Wechsel nicht springen). Rect2() = kein Dock messbar.
func dock_zone() -> Rect2:
	if ui == null or not ui.is_inside_tree() or m.is_empty():
		return Rect2()
	var canvas := Vector2(ui.get_viewport().get_visible_rect().size)
	var breite := _dock_breite if _dock_breite > 0.0 else ScreenShell.card_width(m, DOCK_BASIS)
	var hoehe := maxf(dock.get_combined_minimum_size().y, _dock_hoehe_voll_px)
	return Rect2((canvas.x - breite) * 0.5, canvas.y - hoehe, breite, hoehe)


## Aktiver Ebenen-Chip trägt die ChipLeaf-Variation (disabled-Grau las sich
## als „nicht verfügbar“ — G1-Befund ui-bau §1d).
func set_aktive_ebene(ebene: int) -> void:
	for i in ebenen_chips.size():
		ebenen_chips[i].theme_type_variation = &"ChipLeaf" if i == ebene else &"AcChip"


## Persistente, dezente Modus-Anzeige (Status-Text in der Ebenen-Zeile).
func set_status(text: String) -> void:
	if status_label != null and status_label.text != text:
		status_label.text = text


## Zeilen-Choreographie WERKZEUG↔RUHE/BLATT (Datei-Kopf): bei offener
## Action-Zeile ducken sich Griff- und Ebenen-Zeile, „Fertig“ zieht als
## EIN Knoten mit um. Verstecken-zuerst (W20 P2d Flacker-Review) — zwischen
## den Zuweisungen existiert nie ein Zustand mit ZWEI Knopf-Zeilen.
func set_action_bar_offen(offen: bool) -> void:
	if offen:
		ebenen_leiste.visible = false
		griff_zeile.visible = false
		if done_button.get_parent() != action_bar:
			done_button.reparent(action_bar)
		action_bar.visible = true
	else:
		action_bar.visible = false
		if done_button.get_parent() != griff_zeile:
			done_button.reparent(griff_zeile)
		griff_zeile.visible = true
		ebenen_leiste.visible = kontext.ist_eingeklappt()


## Lager auf-/zuklappen (Kontext-Choreographie: Ghost→zu, Ende→auf — die
## Zeitpunkte steuert BuildMode). Die Ebenen-Zeile duckt sich beim offenen
## Blatt: beim Stöbern wählt das Item seine Ebene selbst.
func klappe_lager(zu: bool) -> void:
	if not zu and kontext.ist_eingeklappt():
		_blatt_slot_primen()
	kontext.klappe(zu)
	if not action_bar.visible:
		ebenen_leiste.visible = zu


## Ruheplatz des Blatts (Slot unter der Griff-Zeile) im EINGEKLAPPTEN
## Zustand primen: MotionKit.blatt_slide_in captured rest_y VOR dem
## Container-Sort — beim ERSTEN Aufklappen wäre die Basis die nie
## gelayoutete Bau-Position (0,0), der Slide zöge das Blatt ÜBER die
## Griff-Zeile und fräße dort Klicks (Hit-Wache test_w20_bau_layout).
## Der Slot kommt aus derselben puren Umbruch-Schätzung wie die Dock-Zone;
## offen gehört die Position dem Container-Sort (Guard).
func _blatt_slot_primen() -> void:
	if not kontext.ist_eingeklappt() or m.is_empty() or drawer.size.x <= 0.0:
		return
	var sb := kontext.get_theme_stylebox("panel")
	var innen := drawer.size.x - sb.content_margin_left - sb.content_margin_right
	var griff_hoehe := flow_umbruch_hoehe(
		_kind_minima(griff_zeile),
		innen,
		float(griff_zeile.get_theme_constant("h_separation")),
		float(griff_zeile.get_theme_constant("v_separation"))
	)
	var spalte := kontext.find_child("DockSpalte", true, false) as VBoxContainer
	kontext.inhalt.position.y = griff_hoehe + float(spalte.get_theme_constant("separation"))


func lager_eingeklappt() -> bool:
	return kontext.ist_eingeklappt()


## Kategorie-Chips der Griff-Zeile neu bestücken (nur Kategorien, die im
## Lager vorkommen — 18 Katalog-Kategorien passten nie in eine Griff-Zeile).
## Verhalten (pressed) verdrahtet BuildMode auf den zurückgegebenen Chips.
func set_kategorien(kategorien: Array[String]) -> Array[Button]:
	for chip in kat_chips:
		# remove_child VOR queue_free: der Name (Kat_<id>) wird sofort
		# frei — der Neuaufbau im selben Frame erbt ihn ohne @-Umbenennung.
		griff_zeile.remove_child(chip)
		chip.queue_free()
	kat_chips = []
	var f := float(m.get("f", 1.0))
	for kat in kategorien:
		var chip := AcnhKit.icon_button(_kat_icon(kat), f, true)
		chip.name = "Kat_" + kat
		# Kategorie-Namen kommen aus shop.kategorie.* (W2c-Domain, nur
		# konsumiert) — Shop und Bau-Lager sprechen dieselbe Sprache.
		chip.tooltip_text = I18nService.t("shop.kategorie." + kat)
		chip.set_meta(META_MIN, Vector2(48.0, 48.0))
		chip.set_meta(META_ICON, float(AcTokens.ICON_L))
		chip.set_meta("bau_kategorie", kat)
		var fertig_index := (
			done_button.get_index() if done_button.get_parent() == griff_zeile else -1
		)
		griff_zeile.add_child(chip)
		if fertig_index >= 0:
			griff_zeile.move_child(chip, fertig_index)
		kat_chips.append(chip)
	floors_und_schrift()
	# Neue Kategorie-Chips ändern die Griff-Zeilen-Höhe → Slot neu primen.
	_blatt_slot_primen.call_deferred()
	return kat_chips


## Aktiver Kategorie-Filter-Chip ("" = keiner): ChipLeaf-Grün statt Frost.
func set_aktive_kategorie(kategorie: String) -> void:
	for chip in kat_chips:
		var aktiv := str(chip.get_meta("bau_kategorie", "")) == kategorie
		chip.theme_type_variation = &"ChipLeaf" if aktiv else &"HudIconButton"


## Bild-Chip des Item-Blatts: Thumb (CraftVorschau-Textur, solange die
## Bäckerei backt das Kategorie-Icon), Kurzname-Zeile (Playtest-Harness
## findet Items über den Label-Text) und Zähler-Badge oben rechts.
## Verhalten (pressed, Textur-Nachschub) verdrahtet BuildMode.
func item_chip(def: Dictionary, anzahl: int) -> Button:
	var f := float(m.get("f", 1.0))
	var btn := SquishButton.new()
	btn.name = "Chip_" + str(def.get("id", "?"))
	btn.theme_type_variation = &"AcChip"
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta(META_MIN, Vector2(CHIP_BREITE, CHIP_HOEHE))
	btn.set_meta("bau_kategorie", str(def.get("kategorie", "")))
	btn.set_meta("bau_item_id", str(def.get("id", "")))
	var name := FurnitureCatalog.display_name(def, I18nService.get_locale())
	btn.tooltip_text = name
	var spalte := VBoxContainer.new()
	spalte.name = "ChipInhalt"
	spalte.set_anchors_preset(Control.PRESET_FULL_RECT)
	spalte.offset_top = 6.0 * f
	spalte.offset_bottom = -6.0 * f
	spalte.add_theme_constant_override("separation", 0)
	spalte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(spalte)
	var thumb := TextureRect.new()
	thumb.name = "Thumb"
	thumb.texture = _kat_icon(str(def.get("kategorie", "")))
	thumb.self_modulate = AcTokens.INK_SOFT
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = Vector2(0.0, CHIP_THUMB * f)
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spalte.add_child(thumb)
	var kurz := Label.new()
	kurz.name = "Name"
	kurz.theme_type_variation = "CaptionLabel"
	kurz.text = name
	kurz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kurz.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kurz.max_lines_visible = 1
	kurz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Kurzname darf den Chip NICHT über die Bild-Breite aufziehen — lange
	# Namen laufen in die Ellipse, der Volltext bleibt Tooltip/Label-Text.
	kurz.custom_minimum_size = Vector2(CHIP_BREITE * 0.8 * f, 0.0)
	kurz.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	kurz.clip_text = true
	spalte.add_child(kurz)
	var badge := PanelContainer.new()
	badge.name = "Badge"
	badge.theme_type_variation = "StatusCapsule"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_END
	badge.offset_right = 2.0 * f
	badge.offset_top = -4.0 * f
	btn.add_child(badge)
	var zahl := Label.new()
	zahl.name = "Anzahl"
	zahl.theme_type_variation = "CaptionLabel"
	zahl.text = "×%d" % anzahl
	zahl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(zahl)
	return btn


## Thumb eines Bild-Chips nachrüsten, sobald die CraftVorschau-Bäckerei
## fertig ist (BuildMode reicht die Textur durch).
func chip_textur(btn: Button, textur: Texture2D) -> void:
	if btn == null or textur == null:
		return
	var thumb := btn.find_child("Thumb", true, false) as TextureRect
	if thumb == null:
		return
	thumb.texture = textur
	thumb.self_modulate = Color.WHITE


## Bild-Chip eines Lager-Items (per bau_item_id-Meta) — null wenn (noch)
## keiner gebaut ist (Kategorie-Filter, leeres Lager).
func lager_chip(item_id: String) -> Button:
	for kind in drawer_items.get_children():
		if kind is Button and str((kind as Button).get_meta("bau_item_id", "")) == item_id:
			return kind
	return null


## Item-Blatt zum Chip eines Items scrollen (W21-Befund 3: der frisch
## eingelagerte Chip lag unsichtbar rechts außerhalb des Scroll-Fensters —
## Auto-Scroll zum neuen Item). Deferred rufen: der Chip braucht erst
## seinen Layout-Pass.
func blatt_scroll_zu(item_id: String) -> void:
	var chip := lager_chip(item_id)
	if chip != null and _blatt != null:
		_blatt.ensure_control_visible(chip)


func _im_baum() -> void:
	ui.get_viewport().size_changed.connect(apply_metrics)
	# Höhen-Konvergenz: JEDE Min-Änderung (Zeilen-Toggle, Klapp-Wechsel,
	# Chip-Rebuild, Flow-Re-Sort nach Breitenwechsel) zieht die Dock-Höhe
	# nach — deferred, die Flow-Minima sind erst nach dem Re-Sort frisch.
	dock.minimum_size_changed.connect(_hoehe_nachziehen, CONNECT_DEFERRED)
	apply_metrics()


## Kapazitäts-Fit gegen die Dock-Klemme: erst die Vollform probieren; würde
## die EINZEILIGE Griff-Zeile damit über die Klemme laufen, fällt der Titel
## auf die reine Zahl zurück, statt Information zu kappen oder umzubrechen.
func _capacity_fit_gegen(klemme: float) -> void:
	if kontext == null or _capacity_voll.is_empty():
		return
	_griff_titel(_kapazitaets_titel(klemme))


## Titel-Wahl (pur bis auf die Mess-Mutation): passt die Griff-Zeile mit
## der Vollform einzeilig in die Klemme? (tests/unit/test_vis2_lager_ui.gd)
func _kapazitaets_titel(klemme: float) -> String:
	_griff_titel(_capacity_voll)
	if _panel_wunsch_breite() <= klemme + 0.5:
		return _capacity_voll
	return _capacity_kurz


## Griff-Titel setzen — Pfeil-Format spiegelt AcnhKit.KontextDock.
func _griff_titel(titel: String) -> void:
	kontext.griff.set_meta(&"acnh_griff_titel", titel)
	kontext.griff.text = "%s  %s" % ["▸" if kontext.ist_eingeklappt() else "▾", titel]


## EINZEILIGE Wunschbreite der Lager-Leiste: breiteste Zeilen-Konfiguration
## (Griff-Zeile im Ruhe-/Blatt-Zustand vs. Action-Zeile im Werkzeug-
## Zustand) + Panel-Innenränder. Bewusst über ALLE Kinder (auch versteckte:
## „Einlagern“ etc.) — die Zone ist die VOLLE Ausbaustufe.
func _panel_wunsch_breite() -> float:
	var sb := kontext.get_theme_stylebox("panel")
	var rand := sb.content_margin_left + sb.content_margin_right
	return maxf(_zeile_wunsch_breite(griff_zeile), _zeile_wunsch_breite(action_bar)) + rand


func _zeile_wunsch_breite(zeile: Container) -> float:
	var sep := float(zeile.get_theme_constant("h_separation"))
	var breite := -sep
	for mind in _kind_minima(zeile):
		breite += mind.x + sep
	return maxf(breite, 0.0)


## Voll ausgebaute Dock-Höhe für eine Kandidaten-Breite: Ebenen-Zeile +
## Lager-Leiste mit Griff-Zeile UND aufgeklapptem Blatt, Flow-Zeilen über
## die pure Umbruch-Schätzung (flow_umbruch_hoehe). Die Action-Zeile ist
## nie höher als Griff-Zeile+Blatt — die Zone springt beim Wechsel nicht.
func _dock_hoehe_voll(breite: float) -> float:
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var sb := kontext.get_theme_stylebox("panel")
	var innen := breite - sb.content_margin_left - sb.content_margin_right
	var hoehe := sb.content_margin_top + sb.content_margin_bottom + float(insets["bottom"])
	var zeilen_hoehe := 0.0
	for zeile: HFlowContainer in [griff_zeile, action_bar]:
		var kandidat := flow_umbruch_hoehe(
			_kind_minima(zeile),
			innen,
			float(zeile.get_theme_constant("h_separation")),
			float(zeile.get_theme_constant("v_separation"))
		)
		zeilen_hoehe = maxf(zeilen_hoehe, kandidat)
	hoehe += zeilen_hoehe
	var spalte := kontext.find_child("DockSpalte", true, false) as VBoxContainer
	hoehe += float(spalte.get_theme_constant("separation"))
	hoehe += kontext.inhalt.get_combined_minimum_size().y
	hoehe += DOCK_LUFT * f
	hoehe += flow_umbruch_hoehe(
		_kind_minima(ebenen_leiste),
		breite,
		float(ebenen_leiste.get_theme_constant("h_separation")),
		float(ebenen_leiste.get_theme_constant("v_separation"))
	)
	return hoehe


## Dock-Höhe explizit auf die aktuellen Kind-Minima ziehen (Unterkante
## bleibt flush an der Bildkante). Godots Min-Size-Grow deckt nur den
## Wachstums-Fall ab — beim Schrumpfen (Blatt klappt zu) und nach einem
## erneuten Metrik-Pass bliebe die Höhe sonst stehen. Läuft initial im
## Metrik-Pass und danach über minimum_size_changed (die Flow-Minima sind
## erst NACH ihrem Re-Sort frisch — synchrone Reads nach Zeilen-Toggles
## wären stale; Wache: test_w20_bau_layout Disjunkt-Matrix).
func _hoehe_nachziehen() -> void:
	if m.is_empty() or dock == null or not dock.is_inside_tree():
		return
	dock.offset_top = -maxf(dock.get_combined_minimum_size().y, 10.0 * float(m["f"]))


## Kombinierte Minima ALLER Control-Kinder einer Zeile — bewusst auch
## unsichtbare (Einlagern-Knopf etc.): die Zone ist die VOLLE Ausbaustufe.
func _kind_minima(zeile: Container) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for kind in zeile.get_children():
		if kind is Control:
			out.append((kind as Control).get_combined_minimum_size())
	return out


## Kamera-Spalte platzieren (W20-P2-Prinzip, vereinfacht): passt sie ins
## freie Band ÜBER dem voll ausgebauten Dock, sitzt sie direkt darüber am
## rechten Rand (hochkant: Daumen-Nähe); sonst bleibt sie rechts mittig —
## das Dock hugt seinen Inhalt und lässt ihr dort Platz (quer).
func _kamera_platzieren(f: float, insets: Dictionary, canvas: Vector2) -> void:
	var rand_rechts := maxf(DRAWER_RAND_X * f, float(insets["right"]) + 12.0 * f)
	var kamera_min := kamera_leiste.get_combined_minimum_size()
	var luft := KAMERA_LUFT * f
	var dock_top := canvas.y - _dock_hoehe_voll_px
	var band_oben := float(insets["top"]) + ScreenShell.EDGE_Y * f
	kamera_leiste.anchor_left = 1.0
	kamera_leiste.anchor_right = 1.0
	kamera_leiste.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	kamera_leiste.offset_left = -rand_rechts
	kamera_leiste.offset_right = -rand_rechts
	if kamera_min.y <= dock_top - luft - band_oben:
		var oben := maxf(dock_top - luft - kamera_min.y, band_oben)
		kamera_leiste.anchor_top = 0.0
		kamera_leiste.anchor_bottom = 0.0
		kamera_leiste.grow_vertical = Control.GROW_DIRECTION_END
		kamera_leiste.offset_top = oben
		kamera_leiste.offset_bottom = oben + kamera_min.y
	else:
		kamera_leiste.anchor_top = 0.5
		kamera_leiste.anchor_bottom = 0.5
		kamera_leiste.grow_vertical = Control.GROW_DIRECTION_BOTH
		kamera_leiste.offset_top = 0.0
		kamera_leiste.offset_bottom = 0.0


## Unten-mittiges Dock: Ebenen-Zeile über der einklappbaren Lager-Leiste
## (AcnhKit.kontext_dock) — flush an der Bildkante, hugt den Zeilen-Inhalt.
func _build_dock(ebenen_keys: Array[String]) -> void:
	dock = VBoxContainer.new()
	dock.name = "BauDock"
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dock)
	_build_ebenen_leiste(ebenen_keys)
	_build_lager_leiste()
	# Startzustand „kein Werkzeug, Blatt zu“ HERSTELLEN statt erben
	# (W20 P2d Flacker-Review) — startet eingeklappt (W21-Choreographie).
	kontext.klappe(true)
	set_action_bar_offen(false)


## Die Lager-Leiste: AcnhKit.kontext_dock mit umgebauter Griff-Zeile —
## der Kit-Griff wandert in eine HFlow-Zeile neben Kategorie-Chips,
## Action-Knöpfen und „Fertig“; das Item-Blatt (ScrollFade + Bild-Chips)
## ist der klappbare Inhalt.
func _build_lager_leiste() -> void:
	var blatt := _build_item_blatt()
	kontext = AcnhKit.kontext_dock(drawer_fade, "", float(m.get("f", 1.0)))
	kontext.name = "LagerKarte"
	kontext.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drawer = kontext
	dock.add_child(kontext)
	# Ebenen-Zeile folgt JEDEM Klapp-Wechsel (auch dem manuellen Griff-Tap,
	# der direkt kontext.klappe ruft): offenes Blatt duckt sie (Datei-Kopf).
	kontext.zustand_geaendert.connect(
		func(zu: bool) -> void:
			if not action_bar.visible:
				ebenen_leiste.visible = zu
	)
	var spalte := kontext.find_child("DockSpalte", true, false) as VBoxContainer
	# Safe-Polster: flush an der Unterkante, Knöpfe überm Home-Indicator.
	kontext.remove_child(spalte)
	_saferand = MarginContainer.new()
	_saferand.name = "SafeRand"
	for seite: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		_saferand.add_theme_constant_override(seite, 0)
	kontext.add_child(_saferand)
	_saferand.add_child(spalte)
	# Griff-Zeile: Kit-Griff + Kategorie-Chips + Fertig in EINER Flow-Zeile.
	griff_zeile = HFlowContainer.new()
	griff_zeile.name = "GriffZeile"
	griff_zeile.alignment = FlowContainer.ALIGNMENT_CENTER
	griff_zeile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spalte.add_child(griff_zeile)
	spalte.move_child(griff_zeile, 0)
	var griff := kontext.griff
	spalte.remove_child(griff)
	griff_zeile.add_child(griff)
	done_button = SquishButton.new()
	done_button.name = "BtnFertig"
	done_button.text = I18nService.t("build.fertig")
	done_button.theme_type_variation = "PrimaryButton"
	griff_zeile.add_child(done_button)
	_build_action_bar(spalte)
	blatt.name = "Inhalt"


## Action-Zeile (nur mit Ghost/Girlande sichtbar, verdrängt dann Griff-
## und Ebenen-Zeile — set_action_bar_offen). Drehen/Abbrechen sind Icon-
## Chips (Tooltip trägt den Namen), Platzieren bleibt der Akzent-CTA,
## Einlagern behält Text (nur im Move-Modus sichtbar).
func _build_action_bar(spalte: VBoxContainer) -> void:
	action_bar = HFlowContainer.new()
	action_bar.name = "ActionBar"
	action_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_bar.visible = false
	spalte.add_child(action_bar)
	spalte.move_child(action_bar, 1)
	action_buttons = []
	for eintrag: Array in [
		["BtnDrehen", "", "rotate_right", "build.rotieren", "BtnGhost"],
		["BtnPlatzieren", "build.bestaetigen", "", "", "AccentButton"],
		["BtnEinlagern", "build.einlagern", "", "", "BtnGhost"],
		["BtnAbbrechen", "", "close", "build.abbrechen", "BtnGhost"],
	]:
		var btn := SquishButton.new()
		btn.name = str(eintrag[0])
		if str(eintrag[1]) != "":
			btn.text = I18nService.t(str(eintrag[1]))
		else:
			btn.icon = load("res://assets/ui/icons/%s.svg" % str(eintrag[2]))
			btn.expand_icon = false
			btn.tooltip_text = I18nService.t(str(eintrag[3]))
			btn.set_meta(META_MIN, Vector2(48.0, 48.0))
			btn.set_meta(META_ICON, float(AcTokens.ICON_L))
		btn.theme_type_variation = str(eintrag[4])
		btn.focus_mode = Control.FOCUS_NONE
		action_bar.add_child(btn)
		action_buttons.append(btn)


## Item-Blatt: Scroll-Reihe der Bild-Chips mit Fade-Kanten + Endpolster
## (W18 Befund 6) und Touch-Deadzone (Wisch über Chips ≠ sofortiger Tap).
func _build_item_blatt() -> Control:
	_blatt = ScrollContainer.new()
	_blatt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_blatt.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_blatt.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_blatt.scroll_deadzone = 24
	drawer_fade = ScrollFade.um(_blatt)
	drawer_fade.name = "LagerChipFade"
	drawer_polster = MarginContainer.new()
	drawer_polster.name = "LagerChipPolster"
	for seite: String in ["margin_left", "margin_top", "margin_bottom"]:
		drawer_polster.add_theme_constant_override(seite, 0)
	drawer_polster.add_theme_constant_override("margin_right", int(ScrollFade.KANTE))
	_blatt.add_child(drawer_polster)
	drawer_items = HBoxContainer.new()
	drawer_items.name = "LagerChips"
	drawer_items.add_theme_constant_override("separation", 8)
	drawer_polster.add_child(drawer_items)
	return drawer_fade


## Ebenen-Umschalter (W13B, Doc D §2.1) in der Daumenzone: Status-Text
## (persistente Modus-/Ebenen-Anzeige, bewusst OHNE Kapsel-Panel — weniger
## gemalte Fläche überm Raum) + Boden/Wand/Decke-Chips als Flow.
func _build_ebenen_leiste(ebenen_keys: Array[String]) -> void:
	ebenen_leiste = HFlowContainer.new()
	ebenen_leiste.name = "EbenenLeiste"
	ebenen_leiste.alignment = FlowContainer.ALIGNMENT_CENTER
	ebenen_leiste.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(ebenen_leiste)
	status_label = Label.new()
	status_label.name = "ModusStatus"
	status_label.theme_type_variation = "CaptionLabel"
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ebenen_leiste.add_child(status_label)
	ebenen_chips = []
	for key: String in ebenen_keys:
		var btn := SquishButton.new()
		btn.text = I18nService.t(key)
		btn.theme_type_variation = "AcChip"
		btn.focus_mode = Control.FOCUS_NONE
		ebenen_leiste.add_child(btn)
		ebenen_chips.append(btn)


## Kamera als transluzente Icon-Mini-Chips (icon_button klein) am rechten
## Rand: Draufsicht/Schrägsicht + 2×90°-Drehung. Offsets setzt der
## Metrik-Pass (_kamera_platzieren).
func _build_kamera_leiste() -> void:
	kamera_leiste = VBoxContainer.new()
	kamera_leiste.name = "KameraLeiste"
	kamera_leiste.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	kamera_leiste.grow_vertical = Control.GROW_DIRECTION_BOTH
	kamera_leiste.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui.add_child(kamera_leiste)
	kamera_buttons = []
	for eintrag: Array in [
		["cam_oben", "build.kamera.oben"],
		["cam_schraeg", "build.kamera.schraeg"],
		["rotate_left", "build.kamera.links"],
		["rotate_right", "build.kamera.rechts"],
	]:
		var btn := AcnhKit.icon_button(
			load("res://assets/ui/icons/%s.svg" % str(eintrag[0])), 1.0, true
		)
		btn.name = "Kamera_" + str(eintrag[0])
		btn.tooltip_text = I18nService.t(str(eintrag[1]))
		btn.set_meta(META_MIN, Vector2(48.0, 48.0))
		btn.set_meta(META_ICON, float(AcTokens.ICON_L))
		kamera_leiste.add_child(btn)
		kamera_buttons.append(btn)


## Ecken-Chips oben links: Presets (Layout-Tausch, W13C) + Goobay
## (verkauft wird aus dem LAGER — Doc D §5.4) als Icon-Mini-Chips.
func _build_ecke_links() -> void:
	ecke_links = HBoxContainer.new()
	ecke_links.name = "EckeLinks"
	ecke_links.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ecke_links.grow_horizontal = Control.GROW_DIRECTION_END
	ecke_links.grow_vertical = Control.GROW_DIRECTION_END
	ui.add_child(ecke_links)
	presets_button = AcnhKit.icon_button(load("res://assets/ui/icons/book.svg"), 1.0, true)
	presets_button.name = "BtnPresets"
	presets_button.tooltip_text = I18nService.t("build.preset.knopf")
	presets_button.set_meta(META_MIN, Vector2(48.0, 48.0))
	presets_button.set_meta(META_ICON, float(AcTokens.ICON_L))
	ecke_links.add_child(presets_button)
	goobay_button = AcnhKit.icon_button(load("res://assets/ui/icons/coin.svg"), 1.0, true)
	goobay_button.name = "BtnGoobay"
	goobay_button.tooltip_text = I18nService.t("goobay.verkaufen")
	goobay_button.set_meta(META_MIN, Vector2(48.0, 48.0))
	goobay_button.set_meta(META_ICON, float(AcTokens.ICON_L))
	ecke_links.add_child(goobay_button)


func _kat_icon(kategorie: String) -> Texture2D:
	var icon := str(KAT_ICONS.get(kategorie, "sparkle"))
	return load("res://assets/ui/icons/%s.svg" % icon)
