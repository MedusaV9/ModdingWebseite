class_name GoobyeLadenScene
extends Node3D
## Der erste begehbare „Goo und Bye“-Laden (G5/P24 Welle A, Doc §2/§3) —
## Diorama-Look nach dem Stadt-Ort-Muster (OrtScene/REHWEI): warmer
## Innenraum, KayKit-Requisiten, EINE Regal-Reihe zum Einräumen (Tap),
## EINE Kasse mit Gebrabbel-Piepen (gepitchte ui_chip-Reihe, §1.2), 2–3
## Kunden pro Markttag (deterministisch aus GoobyeMarkttag) und die
## Kassensturz-Karte mit FÜHLBAREM Umsatz-Hochzählen (UiMotion.count_to).
##
## UI nach User-Leitidee: Hintergrund vollflächig (Wisch-/Guckfläche),
## Bedienelemente mittig in der Daumenzone, Touch-Floor 44 pt überall
## (ScreenShell.touch_target). Story-Beat §1.3 (Schlüsselübergabe) als
## einfache Dialog-Karte beim Erstbetreten — gemerkt in dlc.goobye.*.
##
## Router-Contract (W1a): `ready_for_reveal` nach Aufbau; `receive_params`
## nimmt {"frisch_gekauft": true} entgegen. Tests: `game_state_override`
## und `seed_override`/`tempo` VOR add_child setzen.

signal ready_for_reveal

const Economy := preload("res://scripts/logic/economy.gd")
const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")
const INNEN := "res://assets/city/innen"

## Tages-Phasen: einräumen → offen (Kundenstrom) → abschluss (Kassensturz).
const PHASE_EINRAEUMEN := "einraeumen"
const PHASE_OFFEN := "offen"
const PHASE_ABSCHLUSS := "abschluss"

## Kundenstrom Welle A (§3.2 „klein, aber meins“): 2–3 Kunden pro Tag,
## Kunde 0 ist immer Onkel Alwin (Gag-Vertrag §6.3).
const KUNDEN_MIN := 2
const KUNDEN_MAX := 3

## Diorama-Ankerpunkte (Meter): Tür rechts, Regal links, Kasse rechts.
const TUER_POS := Vector3(5.4, 0.0, 1.4)
const REGAL_STOP := Vector3(-1.4, 0.0, 0.2)
const KASSE_STOP := Vector3(1.9, 0.0, 0.1)
const REGAL_POS := Vector3(-1.6, 0.0, -1.2)
const KASSE_POS := Vector3(1.9, 0.0, -1.2)

## Regal-Brett: Slot-Anker gleichmäßig über die Brettbreite.
const REGAL_BREITE := 2.6
const REGAL_HOEHE := 0.95

## Tempo-Bausteine der Kunden-Choreo (Sekunden, skaliert mit `tempo`).
const LAUF_SEC := 1.4
const STOEBER_SEC := 0.7
const PIEP_SEC := 0.32

## Bottom-Leiste (G3/P05-Muster): Breiten-Deckel + Abstand Safe-Unterkante.
const LEISTE_BASIS_BREITE := 560.0
const LEISTE_RAND_UNTEN := 16.0
const KARTE_BASIS := 380.0

## Kunden-Tinten je Archetyp (Form+Farbe-Sprache, nie nur Text).
const KUNDEN_TINTE := {
	"alwin": Color("#9FB4C7"),
	"listen_gooby": Color("#7FC8C0"),
	"familie": Color("#F2B5D4"),
	"hamster_gooby": Color("#F2C94C"),
}

## Tests/Screenshots: GameState-Double statt /root/GameState.
var game_state_override: Object = null
## Tests: fester Markttag-Seed (0 = Tages-Seed aus dem Datum).
var seed_override := 0
## Tests: Choreo-Zeitraffer (0.05 = fast sofort) und Navigation abschaltbar.
var tempo := 1.0
var auto_navigate := true

var phase := PHASE_EINRAEUMEN
var umsatz_heute := 0

var _gs: Object = null
var _regal: Dictionary = {}
var _lager: Dictionary = {}
var _tagesplan: Dictionary = {}
var _bon_idx := 0
var _kunde: GoobyRig = null
var _frisch_gekauft := false
var _gesichert := false
var _m: Dictionary = {}

var _cam: Camera3D
var _slot_anker: Array[Node3D] = []
var _slot_stapel: Array[Node3D] = []

var _ui: Control
var _toast: Node
var _sheet: PanelSheet
var _verlassen: Button
var _titel_label: Label
var _umsatz_label: Label
var _lager_label: Label
var _slot_knoepfe: Array[Button] = []
var _leiste: HFlowContainer
var _oeffnen_knopf: Button
var _nachschub_knopf: Button
var _intro_overlay: Control
var _intro_knopf: Button
var _abschluss_overlay: Control
var _abschluss_umsatz: Label
var _feierabend_knopf: Button


func _ready() -> void:
	GoobyeState.register_slice()
	_gs = game_state()
	_lager = GoobyeState.lager_von(_gs)
	_regal = GoobyeRegal.neues_regal()
	_baue_raum()
	_baue_requisiten()
	_baue_regal()
	_baue_ui()
	_relayout_ui()
	get_viewport().size_changed.connect(_relayout_ui)
	if GoobyeState.erstbesuch_merken(_gs):
		_zeige_intro()
	ready_for_reveal.emit()


func receive_params(params: Dictionary) -> void:
	_frisch_gekauft = bool(params.get("frisch_gekauft", false))


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func _exit_tree() -> void:
	_bestand_sichern()


## ---------------------------------------------------------------- Tag-Flow


## Tap auf einen Regal-Slot: füllt ihn aus dem Lager (leerer Slot bekommt
## die erste Lager-Ware in Katalog-Reihenfolge, belegte Slots stocken auf).
func slot_tippen(slot_idx: int) -> void:
	if phase != PHASE_EINRAEUMEN:
		return
	var slots: Array = _regal.get("slots", [])
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var ware_id := str((slots[slot_idx] as Dictionary).get("ware", ""))
	if ware_id.is_empty():
		ware_id = _naechste_lager_ware()
	if ware_id.is_empty():
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(I18nService.t("dlc_goobye.laden.lager_leer"))
		return
	var bewegt := GoobyeRegal.einraeumen(_regal, slot_idx, ware_id, GoobyeRegal.MAX_JE_SLOT, _lager)
	if bewegt <= 0:
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(_slot_fehler_text(slot_idx, ware_id))
		return
	AudioDirector.try_play(self, "ui_chip", GoobyeKatalog.ton_fuer(ware_id))
	Haptics.success(self)
	_slots_aktualisieren()
	_lager_label_aktualisieren()
	if slot_idx < _slot_knoepfe.size():
		UiMotion.bounce(_slot_knoepfe[slot_idx])


## „Laden öffnen!“ — plant den deterministischen Markttag und startet die
## Kunden-Choreo (die Logik hat den Tag da schon KOMPLETT ausgerechnet).
func laden_oeffnen() -> void:
	if phase != PHASE_EINRAEUMEN:
		return
	if GoobyeRegal.gesamt_bestand(_regal) <= 0:
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(I18nService.t("dlc_goobye.laden.erst_einraeumen"))
		return
	phase = PHASE_OFFEN
	umsatz_heute = 0
	_bon_idx = 0
	_tagesplan = GoobyeMarkttag.tag_planen(
		_seed(),
		GoobyeRegal.sortiment_von(_regal),
		{"kunden_min": KUNDEN_MIN, "kunden_max": KUNDEN_MAX}
	)
	AudioDirector.try_play(self, "ui_confirm")
	_zeige_toast(I18nService.t("dlc_goobye.laden.offen_toast"))
	_umsatz_label_setzen()
	_knoepfe_aktualisieren()
	_naechster_kunde()


## Feierabend (Kassensturz-Karte): Umsatz in Münzen + Statistik verbuchen,
## dann zurück in die Einräum-Phase (nächster Tag).
func feierabend() -> void:
	if phase != PHASE_ABSCHLUSS:
		return
	AudioDirector.try_play(self, "ui_coins")
	Haptics.success(self)
	_umsatz_verbuchen()
	if _abschluss_overlay != null:
		_abschluss_overlay.queue_free()
		_abschluss_overlay = null
	phase = PHASE_EINRAEUMEN
	umsatz_heute = 0
	_umsatz_label_setzen()
	_knoepfe_aktualisieren()


## ------------------------------------------------------------ Kunden-Choreo


func _naechster_kunde() -> void:
	var bons: Array = _tagesplan.get("bons", [])
	if _bon_idx >= bons.size():
		_zeige_abschluss()
		return
	var bon: Dictionary = bons[_bon_idx]
	_kunde = GoobyRig.new()
	_kunde.position = TUER_POS
	_kunde.rotation.y = PI / 2.0
	add_child(_kunde)
	_kunde.set_emotion("happy")
	_tinte_rig(_kunde, KUNDEN_TINTE.get(str(bon.get("archetyp", "")), Color.WHITE))
	_kunde.set_locomotion(1.0)
	_zeige_toast(I18nService.t("dlc_goobye.laden.kunde_hinweis", {"name": _kunden_name(bon)}))
	var tween := create_tween()
	tween.tween_property(_kunde, "position", REGAL_STOP, LAUF_SEC * tempo)
	tween.tween_callback(_kunde_stoebert)
	tween.tween_interval(STOEBER_SEC * tempo)
	tween.tween_property(_kunde, "position", KASSE_STOP, LAUF_SEC * 0.7 * tempo)
	tween.tween_callback(_kassiere.bind(bon))


func _kunde_stoebert() -> void:
	if _kunde != null:
		_kunde.set_locomotion(0.0)


## Kassen-Moment (§1.2): pro Bon-Position EIN Gebrabbel-Piep — die Tonhöhe
## kommt aus der Warengruppe (GoobyeKatalog.ton_fuer via Melodie-Helfer).
func _kassiere(bon: Dictionary) -> void:
	if _kunde != null:
		_kunde.set_locomotion(0.0)
	var tween := create_tween()
	for position: Dictionary in bon.get("positionen", []):
		tween.tween_callback(_piep_position.bind(position))
		tween.tween_interval(PIEP_SEC * tempo)
	tween.tween_callback(_kunde_fertig)


func _piep_position(position: Dictionary) -> void:
	var ware_id := str(position.get("ware", ""))
	AudioDirector.try_play(self, "ui_chip", GoobyeKatalog.ton_fuer(ware_id))
	GoobyeRegal.entnehmen(_regal, ware_id, 1)
	umsatz_heute += int(position.get("preis", 0))
	_slots_aktualisieren()
	_umsatz_label_setzen()
	if _umsatz_label != null:
		UiMotion.bounce(_umsatz_label)


func _kunde_fertig() -> void:
	if _kunde == null:
		_kunde_weg()
		return
	_kunde.set_locomotion(1.0)
	_kunde.rotation.y = -PI / 2.0
	var tween := create_tween()
	tween.tween_property(_kunde, "position", TUER_POS, LAUF_SEC * tempo)
	tween.tween_callback(_kunde_weg)


func _kunde_weg() -> void:
	if _kunde != null:
		_kunde.queue_free()
		_kunde = null
	_bon_idx += 1
	_naechster_kunde()


## ------------------------------------------------------------ Verbuchen


## Kassensturz in den Save: Münzen (Economy, EIN update-Block) + Umsatz-
## Statistik (dlc.goobye.umsatz) + Regal-Reste bleiben im Regal liegen.
func _umsatz_verbuchen() -> void:
	if _gs == null or umsatz_heute <= 0:
		GoobyeState.umsatz_verbuchen(_gs, maxi(0, umsatz_heute))
		return
	var betrag := umsatz_heute
	_gs.update(
		func(state: Dictionary) -> void: Economy.award(state["economy"], betrag, "gooundbye")
	)
	GoobyeState.umsatz_verbuchen(_gs, betrag)


## Beim Verlassen/Abbau: Regal-Reste zurück ins Lager + Lager speichern —
## kein Stück geht verloren (kein Verderb, §1.4). Offener Tages-Umsatz
## wird mitgebucht (fair, falls mitten im Kundenstrom gegangen wird).
func _bestand_sichern() -> void:
	if _gesichert:
		return
	_gesichert = true
	if phase == PHASE_OFFEN or phase == PHASE_ABSCHLUSS:
		_umsatz_verbuchen()
	for slot: Dictionary in _regal.get("slots", []):
		var ware := str(slot.get("ware", ""))
		var menge := int(slot.get("menge", 0))
		if not ware.is_empty() and menge > 0:
			_lager[ware] = int(_lager.get(ware, 0)) + menge
		slot["ware"] = ""
		slot["menge"] = 0
	GoobyeState.lager_setzen(_gs, _lager)


## ------------------------------------------------------------ Nachschub


## Nachschub-Sheet (§2.2 Großmarkt light): 1 Stück je Tap zum
## Einkaufspreis (GoobyePreis) — Welle B fährt dafür wirklich mit dem Auto.
func _zeige_nachschub() -> void:
	if _sheet == null:
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var hinweis := Label.new()
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("dlc_goobye.nachschub.hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hinweis)
	for ware: Dictionary in GoobyeKatalog.waren():
		var knopf := SquishButton.new()
		knopf.name = "Nachschub_" + str(ware["id"])
		knopf.theme_type_variation = &"BtnGhost"
		knopf.text = (
			I18nService
			. t(
				"dlc_goobye.nachschub.zeile",
				{
					"name": I18nService.t(str(ware.get("name_key", ""))),
					"preis": GoobyePreis.einkaufspreis(ware),
				}
			)
		)
		knopf.focus_mode = Control.FOCUS_NONE
		knopf.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
		knopf.pressed.connect(_nachschub_kaufen.bind(str(ware["id"])))
		box.add_child(knopf)
	_sheet.set_title(I18nService.t("dlc_goobye.nachschub.titel"))
	_sheet.add_content(box)
	_sheet.open()


## Einkauf ATOMAR in EINEM update-Block: Münzen runter UND Lager rauf.
func _nachschub_kaufen(ware_id: String) -> void:
	var ware := GoobyeKatalog.ware(ware_id)
	if ware.is_empty() or _gs == null:
		return
	var preis := GoobyePreis.einkaufspreis(ware)
	# Einelementiges Array als Rückkanal (Lambda fängt per Wert).
	var bezahlt := [false]
	_gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, "gooundbye_einkauf"):
				return
			bezahlt[0] = true
			var goobye := GoobyeState.ensure_goobye(state)
			var lager: Dictionary = goobye["lager"]
			lager[ware_id] = int(lager.get(ware_id, 0)) + 1
	)
	if not bool(bezahlt[0]):
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(I18nService.t("dlc_goobye.nachschub.zu_teuer"))
		return
	_gs.notify_slice_changed(GoobyeState.SLICE_ID)
	_lager[ware_id] = int(_lager.get(ware_id, 0)) + 1
	AudioDirector.try_play(self, "ui_buy")
	_lager_label_aktualisieren()
	_zeige_toast(
		I18nService.t(
			"dlc_goobye.nachschub.gekauft", {"name": I18nService.t(str(ware.get("name_key", "")))}
		)
	)


## ---------------------------------------------------------------- 3D-Aufbau


## Warmer Innenraum nach dem Ort-Muster (OrtScene._baue_raum).
func _baue_raum() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.98, 0.94, 0.87)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.97, 0.92)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	add_child(licht)
	var boden := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(14.0, 10.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.87, 0.77, 0.62)
	bm.material = bmat
	boden.mesh = bm
	add_child(boden)
	var wand := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(14.0, 5.0, 0.3)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.96, 0.90, 0.80)
	wm.material = wmat
	wand.mesh = wm
	wand.position = Vector3(0.0, 2.5, -4.0)
	add_child(wand)
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 2.0, 4.2)
	_cam.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	_cam.current = true
	add_child(_cam)


## KayKit-Requisiten wie im REHWEI-Vorbild: Kasse rechts, Kisten links.
func _baue_requisiten() -> void:
	_prop("%s/kitchencounter_straight.gltf" % INNEN, KASSE_POS, 90.0, 0.9)
	_prop("%s/crate_carrots.gltf" % INNEN, Vector3(-3.8, 0.0, -1.8), 12.0, 0.65)
	_prop("%s/crate.gltf" % INNEN, Vector3(-4.0, 0.0, 0.0), -10.0, 0.65)
	_prop("%s/crate_cheese.gltf" % INNEN, Vector3(3.6, 0.0, 0.6), -14.0, 0.65)
	_prop("%s/menu.gltf" % INNEN, Vector3(3.0, 0.0, -3.4), 0.0, 1.6)
	_prop("%s/fridge_A.gltf" % INNEN, Vector3(-5.4, 0.0, -3.2), 0.0, 0.9)


## Regal-Reihe aus Grund-Meshes: Brett + Füße + je Slot ein Anker mit
## Stapel-Halter (die Waren-Meshes hängen unter dem Halter).
func _baue_regal() -> void:
	var holz := StandardMaterial3D.new()
	holz.albedo_color = Color(0.72, 0.53, 0.35)
	var brett := MeshInstance3D.new()
	var brett_mesh := BoxMesh.new()
	brett_mesh.size = Vector3(REGAL_BREITE, 0.06, 0.5)
	brett_mesh.material = holz
	brett.mesh = brett_mesh
	brett.position = REGAL_POS + Vector3(0.0, REGAL_HOEHE, 0.0)
	add_child(brett)
	for seite in [-1.0, 1.0]:
		var fuss := MeshInstance3D.new()
		var fuss_mesh := BoxMesh.new()
		fuss_mesh.size = Vector3(0.08, REGAL_HOEHE, 0.45)
		fuss_mesh.material = holz
		fuss.mesh = fuss_mesh
		fuss.position = (
			REGAL_POS + Vector3(seite * (REGAL_BREITE / 2.0 - 0.06), REGAL_HOEHE / 2.0, 0.0)
		)
		add_child(fuss)
	for i in GoobyeRegal.SLOTS:
		var anker := Node3D.new()
		anker.name = "SlotAnker%d" % i
		anker.position = REGAL_POS + Vector3(_slot_x(i), REGAL_HOEHE + 0.05, 0.0)
		add_child(anker)
		_slot_anker.append(anker)
		var stapel := Node3D.new()
		stapel.name = "Stapel"
		anker.add_child(stapel)
		_slot_stapel.append(stapel)


func _slot_x(i: int) -> float:
	var schritt := REGAL_BREITE / float(GoobyeRegal.SLOTS)
	return (float(i) + 0.5) * schritt - REGAL_BREITE / 2.0


## Slot-Visuals neu bauen: pro Stück EIN form+farb-kodiertes Mini-Mesh
## (§2.5: Warengruppen sind IMMER Form UND Farbe, nie nur Farbe).
func _slots_aktualisieren() -> void:
	var slots: Array = _regal.get("slots", [])
	for i in _slot_stapel.size():
		var stapel := _slot_stapel[i]
		for kind in stapel.get_children():
			kind.queue_free()
		if i >= slots.size():
			continue
		var slot: Dictionary = slots[i]
		var ware := GoobyeKatalog.ware(str(slot.get("ware", "")))
		var menge := mini(int(slot.get("menge", 0)), GoobyeRegal.MAX_JE_SLOT)
		if ware.is_empty() or menge <= 0:
			continue
		var gruppe := GoobyeKatalog.gruppe(str(ware.get("gruppe", "")))
		var mesh := _form_mesh(str(gruppe.get("form", "eckig")))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(str(gruppe.get("farbe", "#CCCCCC")))
		for n in menge:
			var stueck := MeshInstance3D.new()
			stueck.mesh = mesh
			stueck.material_override = mat
			var reihe := floori(float(n) / 4.0)
			var spalte := n % 4
			stueck.position = Vector3((float(spalte) - 1.5) * 0.11, 0.05 + float(reihe) * 0.13, 0.0)
			if str(gruppe.get("form", "")) == "raute":
				stueck.rotation_degrees.z = 45.0
			stapel.add_child(stueck)
	_slot_knoepfe_beschriften()


## Form-Sprache der Warengruppen (§2.5) als Grund-Meshes.
func _form_mesh(form: String) -> Mesh:
	match form:
		"rund":
			var kugel := SphereMesh.new()
			kugel.radius = 0.05
			kugel.height = 0.1
			return kugel
		"tropfen":
			var kapsel := CapsuleMesh.new()
			kapsel.radius = 0.04
			kapsel.height = 0.12
			return kapsel
		"dreieck":
			var prisma := PrismMesh.new()
			prisma.size = Vector3(0.1, 0.1, 0.1)
			return prisma
		"stern":
			var stern := CylinderMesh.new()
			stern.top_radius = 0.02
			stern.bottom_radius = 0.06
			stern.height = 0.1
			stern.radial_segments = 5
			return stern
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.09, 0.09, 0.09)
			return box


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


func _tinte_rig(rig: GoobyRig, farbe: Color) -> void:
	if farbe == Color.WHITE or rig == null:
		return
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.55)
				mi.set_surface_override_material(i, kopie)


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
	_verlassen.text = I18nService.t("dlc_goobye.laden.verlassen")
	_verlassen.theme_type_variation = &"BtnGhost"
	_verlassen.focus_mode = Control.FOCUS_NONE
	_verlassen.pressed.connect(_on_verlassen)
	_ui.add_child(_verlassen)
	_titel_label = Label.new()
	_titel_label.name = "LadenTitel"
	_titel_label.theme_type_variation = &"TitleLabel"
	_titel_label.text = I18nService.t("dlc_goobye.laden.titel")
	_titel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(_titel_label)
	_umsatz_label = Label.new()
	_umsatz_label.name = "UmsatzZeile"
	_umsatz_label.theme_type_variation = &"HeadlineLabel"
	_ui.add_child(_umsatz_label)
	_lager_label = Label.new()
	_lager_label.name = "LagerZeile"
	_lager_label.theme_type_variation = &"CaptionLabel"
	_ui.add_child(_lager_label)
	for i in GoobyeRegal.SLOTS:
		var knopf := SquishButton.new()
		knopf.name = "Slot%d" % i
		knopf.theme_type_variation = &"BtnGhost"
		knopf.focus_mode = Control.FOCUS_NONE
		knopf.pressed.connect(slot_tippen.bind(i))
		_ui.add_child(knopf)
		_slot_knoepfe.append(knopf)
	_oeffnen_knopf = SquishButton.new()
	_oeffnen_knopf.name = "LadenOeffnen"
	_oeffnen_knopf.theme_type_variation = &"BtnLeaf"
	_oeffnen_knopf.text = I18nService.t("dlc_goobye.laden.oeffnen")
	_oeffnen_knopf.focus_mode = Control.FOCUS_NONE
	_oeffnen_knopf.pressed.connect(laden_oeffnen)
	_nachschub_knopf = SquishButton.new()
	_nachschub_knopf.name = "Nachschub"
	_nachschub_knopf.theme_type_variation = &"BtnTeal"
	_nachschub_knopf.text = I18nService.t("dlc_goobye.laden.nachschub")
	_nachschub_knopf.focus_mode = Control.FOCUS_NONE
	_nachschub_knopf.pressed.connect(_zeige_nachschub)
	_leiste = HFlowContainer.new()
	_leiste.name = "LadenKnoepfe"
	_leiste.alignment = FlowContainer.ALIGNMENT_CENTER
	_leiste.add_theme_constant_override("h_separation", 10)
	_leiste.add_theme_constant_override("v_separation", 8)
	_leiste.add_child(_nachschub_knopf)
	_leiste.add_child(_oeffnen_knopf)
	_ui.add_child(_leiste)
	_sheet = PanelSheetScene.instantiate()
	_sheet.theme = ThemeService.theme()
	layer.add_child(_sheet)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	layer.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_umsatz_label_setzen()
	_lager_label_aktualisieren()
	_slots_aktualisieren()
	_knoepfe_aktualisieren()


## Story-Beat §1.3: Schlüsselübergabe-Karte beim Erstbetreten (einmalig).
func _zeige_intro() -> void:
	var teile := _karte_overlay("IntroOverlay")
	_intro_overlay = teile["overlay"]
	var box: VBoxContainer = teile["box"]
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_goobye.intro.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	for key: String in ["zeile1", "zeile2", "zeile3"]:
		var zeile := Label.new()
		zeile.text = I18nService.t("dlc_goobye.intro." + key)
		zeile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(zeile)
	_intro_knopf = SquishButton.new()
	_intro_knopf.name = "IntroWeiter"
	_intro_knopf.theme_type_variation = &"BtnLeaf"
	_intro_knopf.text = I18nService.t("dlc_goobye.intro.knopf")
	_intro_knopf.focus_mode = Control.FOCUS_NONE
	_intro_knopf.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	_intro_knopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_intro_knopf.pressed.connect(_intro_schliessen)
	box.add_child(_intro_knopf)
	ScreenShell.scale_fonts(_intro_overlay, float(_metrics()["f"]))
	UiMotion.pop_in(teile["karte"])


func _intro_schliessen() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	Haptics.success(self)
	if _intro_overlay != null:
		_intro_overlay.queue_free()
		_intro_overlay = null


## Kassensturz-Karte (§2.3): Umsatz zählt FÜHLBAR hoch (count_to).
func _zeige_abschluss() -> void:
	phase = PHASE_ABSCHLUSS
	_knoepfe_aktualisieren()
	var teile := _karte_overlay("AbschlussOverlay")
	_abschluss_overlay = teile["overlay"]
	var box: VBoxContainer = teile["box"]
	var titel := Label.new()
	titel.theme_type_variation = &"TitleLabel"
	titel.text = I18nService.t("dlc_goobye.abschluss.titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	var unter := Label.new()
	unter.theme_type_variation = &"CaptionLabel"
	unter.text = I18nService.t("dlc_goobye.abschluss.untertitel")
	unter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(unter)
	_abschluss_umsatz = Label.new()
	_abschluss_umsatz.name = "AbschlussUmsatz"
	_abschluss_umsatz.theme_type_variation = &"TitleLabel"
	_abschluss_umsatz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_abschluss_umsatz.text = "0"
	box.add_child(_abschluss_umsatz)
	UiMotion.count_to(_abschluss_umsatz, 0, umsatz_heute, _umsatz_format)
	var verkauft := 0
	for anzahl: Variant in (_tagesplan.get("verkauft", {}) as Dictionary).values():
		verkauft += int(anzahl)
	_abschluss_zeile(box, "kunden", str(int(_tagesplan.get("kundenzahl", 0))))
	_abschluss_zeile(box, "artikel", str(verkauft))
	var verpasst := int(_tagesplan.get("verpasst", 0))
	if verpasst > 0:
		var tipp := Label.new()
		tipp.name = "VerpasstTipp"
		tipp.theme_type_variation = &"CaptionLabel"
		tipp.text = I18nService.t("dlc_goobye.abschluss.verpasst", {"anzahl": verpasst})
		tipp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(tipp)
	_feierabend_knopf = SquishButton.new()
	_feierabend_knopf.name = "Feierabend"
	_feierabend_knopf.theme_type_variation = &"BtnLeaf"
	_feierabend_knopf.text = I18nService.t("dlc_goobye.abschluss.feierabend")
	_feierabend_knopf.focus_mode = Control.FOCUS_NONE
	_feierabend_knopf.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	_feierabend_knopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_feierabend_knopf.pressed.connect(feierabend)
	box.add_child(_feierabend_knopf)
	ScreenShell.scale_fonts(_abschluss_overlay, float(_metrics()["f"]))
	UiMotion.pop_in(teile["karte"])


func _abschluss_zeile(box: VBoxContainer, key: String, wert: String) -> void:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	box.add_child(zeile)
	var links := Label.new()
	links.text = I18nService.t("dlc_goobye.abschluss." + key)
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(links)
	var rechts := Label.new()
	rechts.name = "Wert_" + key
	rechts.theme_type_variation = &"HeadlineLabel"
	rechts.text = wert
	zeile.add_child(rechts)


## Abgedunkeltes Overlay + zentrierte AcCard-Karte (Daumenzone-freundlich:
## die Karte sitzt mittig, der Knopf ist ihr unterstes Element).
func _karte_overlay(overlay_name: String) -> Dictionary:
	var overlay := Control.new()
	overlay.name = overlay_name
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(AcTokens.INK.r, AcTokens.INK.g, AcTokens.INK.b, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var karte := PanelContainer.new()
	karte.name = "Karte"
	karte.theme_type_variation = &"AcCard"
	karte.set_anchors_preset(Control.PRESET_CENTER)
	karte.grow_horizontal = Control.GROW_DIRECTION_BOTH
	karte.grow_vertical = Control.GROW_DIRECTION_BOTH
	var breite := ScreenShell.card_width(_metrics(), KARTE_BASIS)
	karte.custom_minimum_size = Vector2(breite, 0.0)
	overlay.add_child(karte)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	karte.add_child(box)
	return {"overlay": overlay, "karte": karte, "box": box}


## ---------------------------------------------------------------- Layout


func _metrics() -> Dictionary:
	if _m.is_empty():
		_m = ScreenShell.metrics(get_viewport())
	return _m


## Alle Metrics-abhängigen UI-Teile (Aufbau + Rotation, Ort-Muster).
func _relayout_ui() -> void:
	if _ui == null or not is_inside_tree():
		return
	_m = ScreenShell.metrics(get_viewport())
	var f: float = _m["f"]
	var canvas: Vector2 = _m["canvas"]
	var insets: Dictionary = _m["insets"]
	# Hochformat sieht horizontal weniger Welt — Kamera etwas zurück,
	# damit Regal-Reihe UND Kasse im Bild bleiben (vor dem Slot-Unproject!).
	if _cam != null:
		_cam.position.z = 6.0 if canvas.y > canvas.x else 4.2
	ScreenShell.scale_fonts(_ui, f)
	ScreenShell.touch_target(_verlassen, _m)
	_verlassen.position = Vector2(float(insets["left"]) + 16.0 * f, float(insets["top"]) + 12.0 * f)
	_titel_label.size = Vector2(canvas.x * 0.5, 0.0)
	_titel_label.position = Vector2(canvas.x * 0.25, float(insets["top"]) + 14.0 * f)
	_umsatz_label.position = Vector2(
		canvas.x - float(insets["right"]) - _umsatz_label.size.x - 20.0 * f,
		float(insets["top"]) + 16.0 * f
	)
	_lager_label.position = Vector2(
		canvas.x - float(insets["right"]) - _lager_label.size.x - 20.0 * f,
		float(insets["top"]) + 52.0 * f
	)
	_layout_slots()
	_layout_leiste(f, canvas, insets)


## Slot-Knöpfe über die 3D-Anker legen (unproject je Relayout, nie pro
## Frame — die Kamera steht still).
func _layout_slots() -> void:
	if _cam == null or not _cam.is_inside_tree():
		return
	for i in _slot_knoepfe.size():
		if i >= _slot_anker.size():
			break
		var knopf := _slot_knoepfe[i]
		ScreenShell.touch_target(knopf, _m)
		var punkt := _cam.unproject_position(_slot_anker[i].global_position)
		knopf.position = punkt - knopf.size / 2.0 - Vector2(0.0, knopf.size.y * 0.8)


## Bottom-Leiste mittig in der Daumenzone (G3/P05-Geometrie).
func _layout_leiste(f: float, canvas: Vector2, insets: Dictionary) -> void:
	for kind in _leiste.get_children():
		if kind is Control:
			ScreenShell.touch_target(kind, _m)
	var breite := ScreenShell.card_width(_m, LEISTE_BASIS_BREITE)
	var mitte := (float(insets["left"]) + canvas.x - float(insets["right"])) / 2.0
	_leiste.anchor_left = 0.5
	_leiste.anchor_right = 0.5
	_leiste.anchor_top = 1.0
	_leiste.anchor_bottom = 1.0
	_leiste.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_leiste.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_leiste.offset_left = mitte - canvas.x / 2.0 - breite / 2.0
	_leiste.offset_right = mitte - canvas.x / 2.0 + breite / 2.0
	_leiste.offset_bottom = -(float(insets["bottom"]) + LEISTE_RAND_UNTEN * f)
	_leiste.offset_top = _leiste.offset_bottom


## ---------------------------------------------------------------- Anzeige


func _umsatz_label_setzen() -> void:
	if _umsatz_label != null:
		_umsatz_label.text = I18nService.t("dlc_goobye.laden.umsatz", {"betrag": umsatz_heute})


func _umsatz_format(wert: int) -> String:
	return str(wert)


func _lager_label_aktualisieren() -> void:
	if _lager_label == null:
		return
	var stueck := 0
	for menge: Variant in _lager.values():
		stueck += int(menge)
	_lager_label.text = I18nService.t("dlc_goobye.laden.lager", {"stueck": stueck})


func _slot_knoepfe_beschriften() -> void:
	var slots: Array = _regal.get("slots", [])
	for i in _slot_knoepfe.size():
		if i >= slots.size():
			break
		var menge := int((slots[i] as Dictionary).get("menge", 0))
		_slot_knoepfe[i].text = "+" if menge <= 0 else "×%d" % menge


func _knoepfe_aktualisieren() -> void:
	var einraeumen := phase == PHASE_EINRAEUMEN
	if _oeffnen_knopf != null:
		_oeffnen_knopf.disabled = not einraeumen
	if _nachschub_knopf != null:
		_nachschub_knopf.disabled = not einraeumen
	for knopf in _slot_knoepfe:
		knopf.disabled = not einraeumen


func _zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)


## ---------------------------------------------------------------- Helfer


## Erste Ware im Lager in Katalog-Reihenfolge ("" = Lager leer).
func _naechste_lager_ware() -> String:
	for ware: Dictionary in GoobyeKatalog.waren():
		var id := str(ware["id"])
		if int(_lager.get(id, 0)) > 0:
			return id
	return ""


func _slot_fehler_text(slot_idx: int, ware_id: String) -> String:
	var slots: Array = _regal.get("slots", [])
	var slot: Dictionary = slots[slot_idx]
	if int(slot.get("menge", 0)) >= GoobyeRegal.MAX_JE_SLOT:
		return I18nService.t("dlc_goobye.laden.regal_voll")
	if int(_lager.get(ware_id, 0)) <= 0:
		return I18nService.t("dlc_goobye.laden.lager_leer")
	return I18nService.t("dlc_goobye.laden.regal_voll")


func _kunden_name(bon: Dictionary) -> String:
	return I18nService.t("dlc_goobye.laden.kunde_" + str(bon.get("archetyp", "alwin")))


func _seed() -> int:
	if seed_override != 0:
		return seed_override
	return GoobyeMarkttag.tages_seed(_tag_key())


func _tag_key() -> String:
	var ms := int(Time.get_unix_time_from_system() * 1000.0)
	if _gs != null and "clock" in _gs:
		ms = int(_gs.clock.now_ms())
	return Time.get_date_string_from_unix_time(floori(float(ms) / 1000.0))


func _on_verlassen() -> void:
	AudioDirector.try_play(self, "ui_back")
	_bestand_sichern()
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	if router.has_method("handle_back_request") and router.handle_back_request():
		return
	if router.has_method("goto"):
		DlcScreen.register_routes()
		router.goto(DlcScreen.ROUTE, {})
