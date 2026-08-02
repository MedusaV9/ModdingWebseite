class_name GoobyeGrossmarktScene
extends Node3D
## Die Großmarkt-Fahrt des „Goo und Bye“ (G6/GOOBYE-B, Doc §4.1/§4.2) —
## der Nachschub wird zum ERLEBNIS: Gooby fährt mit dem Lieferwagen quer
## durch die Stadt zur Rampe hinter REHWEI (Running-Gag: beide tun so, als
## wäre das völlig normal), sucht Paletten aus (Budget, Staffel-Rabatt ab
## 10 Stück, Rampen-Tagesangebot) und fährt mit vollem Kofferraum zurück.
##
## Bauart: Diorama-Vignette nach dem Laden-Muster (kein CarController —
## die Fahrt ist Bühne, Tweens reichen). GEKAUFT wird ATOMAR an der Rampe
## (GoobyeGrossmarkt.kaufen, Münzen runter UND Lager rauf in EINEM
## update-Block) — die Rückfahrt ist reine Show, App-Abbruch verliert nie
## Ware. Die Route ist FLÜCHTIG (GoobyeRouten): der Ausgang geht immer
## explizit per goto() zurück in den Laden.
##
## Router-Contract (W1a): `ready_for_reveal` nach Aufbau; Tests setzen
## `game_state_override`/`seed_override`/`tempo` VOR add_child.

signal ready_for_reveal

const VAN_GLB := "res://assets/city/autos/delivery.glb"
const INNEN := "res://assets/city/innen"

## Phasen: hinfahrt → rampe (Paletten-Auswahl) → rueckfahrt → ankunft.
const PHASE_HINFAHRT := "hinfahrt"
const PHASE_RAMPE := "rampe"
const PHASE_RUECKFAHRT := "rueckfahrt"
const PHASE_ANKUNFT := "ankunft"

## Diorama-Ankerpunkte (Meter): Straße quer, Rampe rechts.
const VAN_START := Vector3(-9.0, 0.0, 0.6)
const VAN_RAMPE := Vector3(1.6, 0.0, 0.6)
const RAMPE_POS := Vector3(4.6, 0.0, -1.6)

## Fahrt-Tempo (Sekunden, skaliert mit `tempo`).
const FAHRT_SEC := 2.4

## Inhaltsspalte (Leitformat 2868×1320): Deckel + Ränder wie G3/P05.
const LISTE_BASIS_BREITE := 560.0
const FUSS_BASIS_BREITE := 560.0
const KARTE_BASIS := 380.0
const FUSS_RAND_UNTEN := 16.0

## Tests/Screenshots: GameState-Double statt /root/GameState.
var game_state_override: Object = null
## Tests: fester Tages-Seed (0 = Seed aus dem Datum).
var seed_override := 0
## Tests: Zeitraffer (0.05 = fast sofort) und Navigation abschaltbar.
var tempo := 1.0
var auto_navigate := true

var phase := PHASE_HINFAHRT

var _gs: Object = null
var _korb: Dictionary = {}
var _angebot_gruppe := ""
var _kauf_ergebnis: Dictionary = {}
var _m: Dictionary = {}

var _cam: Camera3D
var _van: Node3D
var _ladung: Node3D

var _ui: Control
var _toast: Node
var _verlassen: Button
var _titel_label: Label
var _gag_label: Label
var _budget_label: Label
var _kofferraum_label: Label
var _angebot_label: Label
var _scroll: ScrollContainer
var _liste: VBoxContainer
var _fuss: HFlowContainer
var _summe_label: Label
var _kaufen_knopf: Button
var _ankunft_overlay: Control
var _ankunft_kisten: Label
var _zurueck_knopf: Button
## ware_id → {anzahl: Label, preis: Label} für Zeilen-Updates.
var _zeilen: Dictionary = {}


func _ready() -> void:
	GoobyeState.register_slice()
	_gs = game_state()
	_angebot_gruppe = GoobyeGrossmarkt.tagesangebot_gruppe(_seed())
	_baue_kulisse()
	_baue_van()
	_baue_ui()
	_relayout_ui()
	get_viewport().size_changed.connect(_relayout_ui)
	_starte_hinfahrt()
	ready_for_reveal.emit()


func receive_params(_params: Dictionary) -> void:
	pass


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


## ---------------------------------------------------------------- Fahrt


func _starte_hinfahrt() -> void:
	phase = PHASE_HINFAHRT
	_zeige_toast(I18nService.t("dlc_goobye.grossmarkt.hinfahrt"))
	var tween := create_tween()
	tween.tween_property(_van, "position", VAN_RAMPE, FAHRT_SEC * tempo)
	tween.tween_callback(_rampe_oeffnen)


## Paletten-Auswahl an der Rampe (§4.1): Budget, Staffel, Tagesangebot.
func _rampe_oeffnen() -> void:
	phase = PHASE_RAMPE
	AudioDirector.try_play(self, "ui_confirm")
	_baue_zeilen()
	_scroll.visible = true
	_fuss.visible = true
	_angebot_label.visible = true
	_summen_aktualisieren()
	_relayout_ui()


## Kauf ATOMAR an der Rampe — dann ist die Rückfahrt reine Bühne.
func kaufen() -> void:
	if phase != PHASE_RAMPE:
		return
	var ergebnis := GoobyeGrossmarkt.kaufen(_gs, _korb, _angebot_gruppe)
	if not bool(ergebnis["ok"]):
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(I18nService.t("dlc_goobye.grossmarkt." + str(ergebnis["grund"])))
		return
	_kauf_ergebnis = ergebnis
	AudioDirector.try_play(self, "ui_buy")
	Haptics.success(self)
	_starte_rueckfahrt()


func _starte_rueckfahrt() -> void:
	phase = PHASE_RUECKFAHRT
	_scroll.visible = false
	_fuss.visible = false
	_angebot_label.visible = false
	_summen_aktualisieren()
	_zeige_ladung(int(_kauf_ergebnis.get("kisten", 0)))
	_zeige_toast(I18nService.t("dlc_goobye.grossmarkt.rueckfahrt"))
	_van.rotation.y = PI
	var tween := create_tween()
	tween.tween_property(_van, "position", VAN_START, FAHRT_SEC * 0.85 * tempo)
	tween.tween_callback(_zeige_ankunft)


## Einräum-Karte (§4.2 „Ausladen ist ein Mini-Ritual“): Kisten zählen
## FÜHLBAR hoch (count_to), dann geht es zurück in den Laden.
func _zeige_ankunft() -> void:
	phase = PHASE_ANKUNFT
	var teile := GoobyeUi.karte_overlay(_ui, _metrics(), "AnkunftOverlay", KARTE_BASIS)
	_ankunft_overlay = teile["overlay"]
	var box: VBoxContainer = teile["box"]
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_goobye.grossmarkt.einraeumen_titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	_ankunft_kisten = Label.new()
	_ankunft_kisten.name = "AnkunftKisten"
	_ankunft_kisten.theme_type_variation = &"TitleLabel"
	_ankunft_kisten.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ankunft_kisten.text = "0"
	box.add_child(_ankunft_kisten)
	AudioDirector.try_play(self, "ui_coins")
	UiMotion.count_to(_ankunft_kisten, 0, int(_kauf_ergebnis.get("kisten", 0)), _kisten_format)
	var zeile := Label.new()
	zeile.name = "AnkunftZeile"
	zeile.theme_type_variation = &"CaptionLabel"
	zeile.text = I18nService.t(
		"dlc_goobye.grossmarkt.einraeumen_zeile",
		{
			"kisten": int(_kauf_ergebnis.get("kisten", 0)),
			"betrag": int(_kauf_ergebnis.get("kosten", 0))
		}
	)
	zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zeile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(zeile)
	_zurueck_knopf = SquishButton.new()
	_zurueck_knopf.name = "ZurueckInDenLaden"
	_zurueck_knopf.theme_type_variation = &"BtnLeaf"
	_zurueck_knopf.text = I18nService.t("dlc_goobye.grossmarkt.zurueck")
	_zurueck_knopf.focus_mode = Control.FOCUS_NONE
	ScreenShell.touch_target(_zurueck_knopf, _metrics())
	_zurueck_knopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_zurueck_knopf.pressed.connect(_zurueck_in_den_laden)
	box.add_child(_zurueck_knopf)
	ScreenShell.scale_fonts(_ankunft_overlay, float(_metrics()["f"]))
	UiMotion.pop_in(teile["karte"])


## ------------------------------------------------------------ Korb-Logik


## Stepper „+“: Kofferraum- und Budget-Deckel prüfen BEVOR gezählt wird.
func plus_tippen(ware_id: String) -> void:
	if phase != PHASE_RAMPE:
		return
	var neu := _korb.duplicate(true)
	neu[ware_id] = int(neu.get(ware_id, 0)) + 1
	if not GoobyeGrossmarkt.passt_in_kofferraum(neu):
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(I18nService.t("dlc_goobye.grossmarkt.kofferraum_voll"))
		return
	var budget := 0 if _gs == null else int(_gs.get_value("economy.coins", 0))
	if GoobyeGrossmarkt.korb_summe(neu, _angebot_gruppe) > budget:
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(I18nService.t("dlc_goobye.grossmarkt.not_enough_coins"))
		return
	_korb = neu
	AudioDirector.try_play(self, "ui_chip", GoobyeKatalog.ton_fuer(ware_id))
	_zeile_aktualisieren(ware_id)
	_summen_aktualisieren()


func minus_tippen(ware_id: String) -> void:
	if phase != PHASE_RAMPE or int(_korb.get(ware_id, 0)) <= 0:
		return
	_korb[ware_id] = int(_korb[ware_id]) - 1
	if int(_korb[ware_id]) <= 0:
		_korb.erase(ware_id)
	AudioDirector.try_play(self, "ui_back")
	_zeile_aktualisieren(ware_id)
	_summen_aktualisieren()


## ---------------------------------------------------------------- 3D-Bühne


## Straßen-Diorama: warmes Licht, Asphaltband, Rampe + Kisten rechts.
func _baue_kulisse() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.92, 0.97)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.98, 0.94)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	add_child(licht)
	var boden := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(26.0, 12.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.72, 0.78, 0.66)
	bm.material = bmat
	boden.mesh = bm
	add_child(boden)
	var strasse := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(26.0, 0.02, 2.6)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.42, 0.43, 0.46)
	sm.material = smat
	strasse.mesh = sm
	strasse.position = Vector3(0.0, 0.01, 0.6)
	add_child(strasse)
	_baue_rampe()
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 2.1, 5.4)
	_cam.rotation_degrees = Vector3(-13.0, 0.0, 0.0)
	_cam.current = true
	add_child(_cam)


## Die Großmarkt-Rampe hinter REHWEI: Halle + Schild + Paletten-Stapel.
func _baue_rampe() -> void:
	var halle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(6.0, 3.2, 3.0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.90, 0.86, 0.78)
	hm.material = hmat
	halle.mesh = hm
	halle.position = RAMPE_POS + Vector3(1.4, 1.6, -1.2)
	add_child(halle)
	var schild := MeshInstance3D.new()
	var schm := BoxMesh.new()
	schm.size = Vector3(3.4, 0.7, 0.12)
	var schmat := StandardMaterial3D.new()
	schmat.albedo_color = Color(0.95, 0.55, 0.25)
	schm.material = schmat
	schild.mesh = schm
	schild.position = RAMPE_POS + Vector3(1.2, 2.6, 0.35)
	add_child(schild)
	var rampe := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(3.2, 0.5, 2.0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.62, 0.60, 0.58)
	rm.material = rmat
	rampe.mesh = rm
	rampe.position = RAMPE_POS + Vector3(0.4, 0.25, 0.2)
	add_child(rampe)
	_prop("%s/crate.gltf" % INNEN, RAMPE_POS + Vector3(-0.4, 0.5, 0.4), 8.0, 0.6)
	_prop("%s/crate_carrots.gltf" % INNEN, RAMPE_POS + Vector3(0.5, 0.5, 0.6), -12.0, 0.6)
	_prop("%s/crate_cheese.gltf" % INNEN, RAMPE_POS + Vector3(0.05, 0.5, -0.5), 20.0, 0.6)


## Der Lieferwagen (Kenney car-kit); Fallback: Primitive-Kombi, damit die
## Vignette auch ohne importierte Assets steht.
func _baue_van() -> void:
	_van = _prop(VAN_GLB, VAN_START, 90.0, 1.0)
	if _van == null:
		_van = _primitiven_van()
		_van.position = VAN_START
		_van.rotation_degrees.y = 90.0
		add_child(_van)
	_ladung = Node3D.new()
	_ladung.name = "Ladung"
	_ladung.position = Vector3(0.0, 1.0, -1.1)
	_van.add_child(_ladung)


func _primitiven_van() -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "ErsatzVan"
	var karosse := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(1.1, 0.9, 2.3)
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.55, 0.75, 0.72)
	km.material = kmat
	karosse.mesh = km
	karosse.position = Vector3(0.0, 0.75, 0.0)
	wurzel.add_child(karosse)
	for z in [-0.7, 0.7]:
		for x in [-0.5, 0.5]:
			var rad := MeshInstance3D.new()
			var radm := CylinderMesh.new()
			radm.top_radius = 0.22
			radm.bottom_radius = 0.22
			radm.height = 0.16
			var radmat := StandardMaterial3D.new()
			radmat.albedo_color = Color(0.2, 0.2, 0.22)
			radm.material = radmat
			rad.mesh = radm
			rad.rotation_degrees.z = 90.0
			rad.position = Vector3(x, 0.24, z)
			wurzel.add_child(rad)
	return wurzel


## Kisten-Stapel auf dem Van für die Rückfahrt (max 6 sichtbar — Bühne).
func _zeige_ladung(kisten: int) -> void:
	if _ladung == null:
		return
	var holz := StandardMaterial3D.new()
	holz.albedo_color = Color(0.76, 0.58, 0.38)
	for i in mini(6, maxi(0, kisten)):
		var kiste := MeshInstance3D.new()
		var kistm := BoxMesh.new()
		kistm.size = Vector3(0.34, 0.3, 0.34)
		kistm.material = holz
		kiste.mesh = kistm
		var reihe := floori(float(i) / 3.0)
		kiste.position = Vector3((float(i % 3) - 1.0) * 0.38, 0.16 + float(reihe) * 0.34, 0.0)
		_ladung.add_child(kiste)


## Requisiten-Helfer (Ort-Muster: still bei Fehlpfad).
func _prop(pfad: String, pos: Vector3, rot_grad: float, groesse: float) -> Node3D:
	if not ResourceLoader.exists(pfad):
		return null
	var szene: PackedScene = load(pfad)
	if szene == null:
		return null
	var node: Node3D = szene.instantiate()
	node.position = pos
	node.rotation_degrees.y = rot_grad
	node.scale = Vector3.ONE * groesse
	add_child(node)
	return node


## ---------------------------------------------------------------- UI-Aufbau


func _baue_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UiLayer"
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Theme explizit: Window-Theme propagiert NICHT durch CanvasLayer.
	_ui.theme = ThemeService.theme()
	layer.add_child(_ui)
	_verlassen = SquishButton.new()
	_verlassen.name = "Verlassen"
	_verlassen.text = I18nService.t("dlc_goobye.grossmarkt.verlassen")
	_verlassen.theme_type_variation = &"BtnGhost"
	_verlassen.focus_mode = Control.FOCUS_NONE
	_verlassen.pressed.connect(_zurueck_in_den_laden)
	_ui.add_child(_verlassen)
	_titel_label = Label.new()
	_titel_label.name = "GrossmarktTitel"
	_titel_label.theme_type_variation = &"TitleLabel"
	_titel_label.text = I18nService.t("dlc_goobye.grossmarkt.titel")
	_titel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(_titel_label)
	_gag_label = Label.new()
	_gag_label.name = "GagZeile"
	_gag_label.theme_type_variation = &"CaptionLabel"
	_gag_label.text = I18nService.t("dlc_goobye.grossmarkt.gag")
	_gag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(_gag_label)
	_budget_label = Label.new()
	_budget_label.name = "BudgetZeile"
	_budget_label.theme_type_variation = &"HeadlineLabel"
	_ui.add_child(_budget_label)
	_kofferraum_label = Label.new()
	_kofferraum_label.name = "KofferraumZeile"
	_kofferraum_label.theme_type_variation = &"CaptionLabel"
	_ui.add_child(_kofferraum_label)
	_angebot_label = Label.new()
	_angebot_label.name = "AngebotBanner"
	_angebot_label.theme_type_variation = &"HeadlineLabel"
	_angebot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_angebot_label.text = _angebot_text()
	_angebot_label.visible = false
	_ui.add_child(_angebot_label)
	_scroll = ScrollContainer.new()
	_scroll.name = "PalettenScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.visible = false
	_ui.add_child(_scroll)
	_liste = VBoxContainer.new()
	_liste.name = "PalettenListe"
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 8)
	_scroll.add_child(_liste)
	_kaufen_knopf = SquishButton.new()
	_kaufen_knopf.name = "KaufenLosfahren"
	_kaufen_knopf.theme_type_variation = &"BtnLeaf"
	_kaufen_knopf.text = I18nService.t("dlc_goobye.grossmarkt.kaufen")
	_kaufen_knopf.focus_mode = Control.FOCUS_NONE
	_kaufen_knopf.pressed.connect(kaufen)
	_summe_label = Label.new()
	_summe_label.name = "SummeZeile"
	_summe_label.theme_type_variation = &"HeadlineLabel"
	_summe_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fuss = HFlowContainer.new()
	_fuss.name = "RampenFuss"
	_fuss.alignment = FlowContainer.ALIGNMENT_CENTER
	_fuss.add_theme_constant_override("h_separation", 14)
	_fuss.add_theme_constant_override("v_separation", 8)
	_fuss.visible = false
	_fuss.add_child(_summe_label)
	_fuss.add_child(_kaufen_knopf)
	_ui.add_child(_fuss)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	layer.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summen_aktualisieren()


## Paletten-Zeilen: Name + Rampen-Stückpreis, Stepper −/+, Zeilen-Preis
## (Staffel-Rabatt ab 10 Stück wird direkt an der Zeile sichtbar).
func _baue_zeilen() -> void:
	for kind in _liste.get_children():
		kind.queue_free()
	_zeilen = {}
	var hinweis := Label.new()
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = (
		I18nService
		. t(
			"dlc_goobye.grossmarkt.staffel_hinweis",
			{
				"ab": GoobyeKatalog.mengenrabatt_ab(),
				"prozent": roundi(GoobyeKatalog.mengenrabatt() * 100.0),
			}
		)
	)
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_liste.add_child(hinweis)
	for ware: Dictionary in GoobyeKatalog.waren():
		_baue_zeile(ware)
	ScreenShell.scale_fonts(_liste, float(_metrics()["f"]))


func _baue_zeile(ware: Dictionary) -> void:
	var ware_id := str(ware["id"])
	var zeile := HBoxContainer.new()
	zeile.name = "Palette_" + ware_id
	zeile.add_theme_constant_override("separation", 8)
	_liste.add_child(zeile)
	var texte := VBoxContainer.new()
	texte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(texte)
	var name_label := Label.new()
	name_label.text = (
		I18nService
		. t(
			"dlc_goobye.grossmarkt.zeile",
			{
				"name": I18nService.t(str(ware.get("name_key", ""))),
				"preis": GoobyeGrossmarkt.stueckpreis(ware, _angebot_gruppe),
			}
		)
	)
	texte.add_child(name_label)
	var preis_label := Label.new()
	preis_label.theme_type_variation = &"CaptionLabel"
	texte.add_child(preis_label)
	if str(ware.get("gruppe", "")) == _angebot_gruppe:
		var stern := Label.new()
		stern.theme_type_variation = &"CaptionLabel"
		stern.text = I18nService.t("dlc_goobye.grossmarkt.angebot_tag")
		texte.add_child(stern)
	var minus := SquishButton.new()
	minus.name = "Minus_" + ware_id
	minus.theme_type_variation = &"BtnGhost"
	minus.text = "−"
	minus.focus_mode = Control.FOCUS_NONE
	ScreenShell.touch_target(minus, _metrics())
	minus.pressed.connect(minus_tippen.bind(ware_id))
	zeile.add_child(minus)
	var anzahl := Label.new()
	anzahl.name = "Anzahl_" + ware_id
	anzahl.theme_type_variation = &"HeadlineLabel"
	anzahl.custom_minimum_size = Vector2(44.0, 0.0)
	anzahl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zeile.add_child(anzahl)
	var plus := SquishButton.new()
	plus.name = "Plus_" + ware_id
	plus.theme_type_variation = &"BtnTeal"
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	ScreenShell.touch_target(plus, _metrics())
	plus.pressed.connect(plus_tippen.bind(ware_id))
	zeile.add_child(plus)
	_zeilen[ware_id] = {"anzahl": anzahl, "preis": preis_label}
	_zeile_aktualisieren(ware_id)


## ------------------------------------------------------------ Anzeige


func _zeile_aktualisieren(ware_id: String) -> void:
	if not _zeilen.has(ware_id):
		return
	var menge := int(_korb.get(ware_id, 0))
	var teile: Dictionary = _zeilen[ware_id]
	(teile["anzahl"] as Label).text = str(menge)
	var preis_label: Label = teile["preis"]
	if menge <= 0:
		preis_label.text = ""
		return
	var ware := GoobyeKatalog.ware(ware_id)
	var text := I18nService.t(
		"dlc_goobye.grossmarkt.zeilen_preis",
		{"betrag": GoobyeGrossmarkt.palette_preis(ware, menge, _angebot_gruppe)}
	)
	if menge >= GoobyeKatalog.mengenrabatt_ab():
		text += " " + I18nService.t("dlc_goobye.grossmarkt.staffel_tag")
	preis_label.text = text


func _summen_aktualisieren() -> void:
	var budget := 0 if _gs == null else int(_gs.get_value("economy.coins", 0))
	if _budget_label != null:
		_budget_label.text = I18nService.t("dlc_goobye.grossmarkt.budget", {"betrag": budget})
	if _kofferraum_label != null:
		_kofferraum_label.text = (
			I18nService
			. t(
				"dlc_goobye.grossmarkt.kofferraum",
				{
					"kisten": GoobyeGrossmarkt.korb_kisten(_korb),
					"max": GoobyeKatalog.kofferraum_kisten(),
				}
			)
		)
	if _summe_label != null:
		_summe_label.text = I18nService.t(
			"dlc_goobye.grossmarkt.summe",
			{"betrag": GoobyeGrossmarkt.korb_summe(_korb, _angebot_gruppe)}
		)


func _angebot_text() -> String:
	if _angebot_gruppe.is_empty():
		return ""
	return (
		I18nService
		. t(
			"dlc_goobye.grossmarkt.angebot",
			{
				"gruppe": I18nService.t("dlc_goobye.gruppe." + _angebot_gruppe),
				"prozent": roundi(GoobyeKatalog.tagesrabatt() * 100.0),
			}
		)
	)


func _kisten_format(wert: int) -> String:
	return str(wert)


func _zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)


## ---------------------------------------------------------------- Layout


func _metrics() -> Dictionary:
	if _m.is_empty():
		_m = ScreenShell.metrics(get_viewport())
	return _m


func _relayout_ui() -> void:
	if _ui == null or not is_inside_tree():
		return
	_m = ScreenShell.metrics(get_viewport())
	var f: float = _m["f"]
	var canvas: Vector2 = _m["canvas"]
	var insets: Dictionary = _m["insets"]
	# Hochformat sieht horizontal weniger Welt — Kamera etwas zurück.
	if _cam != null:
		_cam.position.z = 7.4 if canvas.y > canvas.x else 5.4
	ScreenShell.scale_fonts(_ui, f)
	ScreenShell.touch_target(_verlassen, _m)
	_verlassen.position = Vector2(float(insets["left"]) + 16.0 * f, float(insets["top"]) + 12.0 * f)
	_titel_label.size = Vector2(canvas.x * 0.5, 0.0)
	_titel_label.position = Vector2(canvas.x * 0.25, float(insets["top"]) + 14.0 * f)
	_gag_label.size = Vector2(canvas.x * 0.6, 0.0)
	_gag_label.position = Vector2(canvas.x * 0.2, float(insets["top"]) + 52.0 * f)
	_budget_label.position = Vector2(
		canvas.x - float(insets["right"]) - _budget_label.size.x - 20.0 * f,
		float(insets["top"]) + 16.0 * f
	)
	_kofferraum_label.position = Vector2(
		canvas.x - float(insets["right"]) - _kofferraum_label.size.x - 20.0 * f,
		float(insets["top"]) + 52.0 * f
	)
	_angebot_label.size = Vector2(canvas.x * 0.7, 0.0)
	_angebot_label.position = Vector2(canvas.x * 0.15, float(insets["top"]) + 84.0 * f)
	_layout_liste(f, canvas, insets)
	_layout_fuss(f, canvas, insets)


## Inhaltsspalte mittig: Scroll-Liste zwischen Kopf und Fuß-Leiste;
## Zeilen-Stepper ziehen den Touch-Floor bei Rotation nach.
func _layout_liste(f: float, canvas: Vector2, insets: Dictionary) -> void:
	var breite := ScreenShell.card_width(_m, LISTE_BASIS_BREITE)
	var oben := float(insets["top"]) + 122.0 * f
	var unten := canvas.y - float(insets["bottom"]) - (FUSS_RAND_UNTEN + 76.0) * f
	_scroll.position = Vector2((canvas.x - breite) / 2.0, oben)
	_scroll.size = Vector2(breite, maxf(120.0, unten - oben))
	for zeile in _liste.get_children():
		for kind in zeile.get_children():
			if kind is Button:
				ScreenShell.touch_target(kind, _m)


func _layout_fuss(f: float, canvas: Vector2, insets: Dictionary) -> void:
	for kind in _fuss.get_children():
		if kind is Button:
			ScreenShell.touch_target(kind, _m)
	var breite := ScreenShell.card_width(_m, FUSS_BASIS_BREITE)
	var mitte := (float(insets["left"]) + canvas.x - float(insets["right"])) / 2.0
	_fuss.anchor_left = 0.5
	_fuss.anchor_right = 0.5
	_fuss.anchor_top = 1.0
	_fuss.anchor_bottom = 1.0
	_fuss.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fuss.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fuss.offset_left = mitte - canvas.x / 2.0 - breite / 2.0
	_fuss.offset_right = mitte - canvas.x / 2.0 + breite / 2.0
	_fuss.offset_bottom = -(float(insets["bottom"]) + FUSS_RAND_UNTEN * f)
	_fuss.offset_top = _fuss.offset_bottom


## ---------------------------------------------------------------- Helfer


func _seed() -> int:
	if seed_override != 0:
		return seed_override
	return GoobyeMarkttag.tages_seed(_tag_key())


func _tag_key() -> String:
	var ms := int(Time.get_unix_time_from_system() * 1000.0)
	if _gs != null and "clock" in _gs:
		ms = int(_gs.clock.now_ms())
	return Time.get_date_string_from_unix_time(floori(float(ms) / 1000.0))


## Ausgang IMMER explizit (flüchtige Route): zurück in den Laden.
func _zurueck_in_den_laden() -> void:
	AudioDirector.try_play(self, "ui_back")
	if not auto_navigate:
		return
	var params := {}
	if phase == PHASE_ANKUNFT:
		params["eingeraeumt"] = int(_kauf_ergebnis.get("kisten", 0))
	GoobyeRouten.fahre_zum_laden(get_tree(), params)
