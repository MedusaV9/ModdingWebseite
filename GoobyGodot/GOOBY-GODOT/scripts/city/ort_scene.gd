class_name OrtScene
extends Node3D
## Ort-Framework-Basis (W3a CITY, Doc E §2): Betreten via Parkplatz →
## Innenraum-Szene mit NPC (W1b-GoobyRig, getintet) + Dialog-Sheet
## (OrtDialogRunner/-View) + optionalem Händler-UI (HaendlerSheet in
## W1c-PanelSheet). M2-Orte erben von dieser Klasse und überschreiben die
## drei Hooks `_baue_innenraum()`, `_dialog_pfad()`, `_sortiment_pfad()`.
##
## Router-Contract (W1a): `ready_for_reveal` nach Aufbau; `receive_params`
## nimmt {"ort_id": ...} entgegen. Tests: `game_state_override` VOR add_child.

signal ready_for_reveal
signal verlassen_angefordert

const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")

## Bottom-Leiste (G3/P05): Breiten-Deckel in Design-px + Abstand zur
## Safe-Area-Unterkante (beides skaliert mit dem UiScale-Faktor).
const LEISTE_BASIS_BREITE := 640.0
const LEISTE_RAND_UNTEN := 16.0

@export var ort_id := ""

var game_state_override: Object
var rig: GoobyRig
var voice: GoobyVoice
var dialog: OrtDialogView
## true, wenn dieser Besuch der ERSTE in diesem Ort war (Erste-Male-Karten).
var ist_erstbesuch := false
## G7-P55 „Läden lebendig“: Ambient-Besucher (OrtLeben) + Kassen-Verhalten
## des Haupt-NPCs (KassenNpc) — beide nur, wenn `_leben_konfig()` sie will.
var leben: OrtLeben
var kassen_npc: KassenNpc
## Test-Hooks: fester Besucher-Seed / Reduced-Motion erzwingen (-1 = aus) /
## Ambient-Audio stumm schalten (Headless-Runner, s. OrtLeben.stumm) /
## Uhr für die Stammkunden-Fenster injizieren (-1 = Systemuhr).
var leben_seed_override := -1
var leben_reduced_override := -1
var leben_stumm_override := false
var leben_stunde_override := -1.0

var _ui: Control
var _ui_layer: CanvasLayer
var _sheet: PanelSheet
var _toast: Node
var _zurueck: Button
## Bottom-Knopfleisten aus `_baue_knopfleiste()` — Re-Layout bei Rotation.
var _leisten: Array[Control] = []


func _ready() -> void:
	ist_erstbesuch = OrtKatalog.besuch_merken(game_state(), ort_id)
	_baue_raum()
	_baue_innenraum()
	_baue_npc()
	_baue_ui()
	_baue_leben()
	_starte_dialog()
	ready_for_reveal.emit()


func receive_params(params: Dictionary) -> void:
	var id := str(params.get("ort_id", ""))
	if not id.is_empty():
		ort_id = id


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


## Hook: Ort-spezifische Requisiten (KayKit-Innen-Assets etc.).
func _baue_innenraum() -> void:
	pass


## Hook: Pfad zum Dialogbaum-JSON ("" = kein Dialog).
func _dialog_pfad() -> String:
	return ""


## Hook: Pfad zum Sortiment-JSON ("" = kein Laden).
func _sortiment_pfad() -> String:
	return ""


## Hook: NPC-Konfiguration {tint: Color, emotion: String, pos: Vector3}.
func _npc_konfig() -> Dictionary:
	return {"tint": Color.WHITE, "emotion": "happy", "pos": Vector3(0.0, 0.0, -2.2)}


## Hook: true = Platz unter freiem Himmel (Wochenmarkt) statt Ladenraum —
## keine Rückwand, Wiesenboden, heller Himmel, schwächere Vignette.
func _ist_draussen() -> bool:
	return false


## Hook (G7-P55): Ambient-Leben-Konfig des Orts ({} = kein Leben).
## Schema s. OrtLeben-Docstring — neue Orte liefern hier ~15 Zeilen Konfig
## und bekommen Besucher, Sprüche, Glöckchen, Gemurmel und Kassen-NPC.
func _leben_konfig() -> Dictionary:
	return {}


## Ambient-Leben einhängen (nach `_baue_ui`, die Sprüche brauchen `_ui`).
func _baue_leben() -> void:
	var konfig := _leben_konfig()
	if konfig.is_empty():
		return
	konfig["ort_id"] = ort_id
	leben = OrtLeben.new()
	leben.name = "OrtLeben"
	leben.konfig = konfig
	leben.ui_layer = _ui
	leben.seed_override = leben_seed_override
	leben.reduced_override = leben_reduced_override
	leben.stumm = leben_stumm_override
	leben.stunde_override = leben_stunde_override
	add_child(leben)
	if bool(konfig.get("kasse", false)) and rig != null:
		kassen_npc = KassenNpc.new()
		kassen_npc.name = "KassenNpc"
		kassen_npc.rig = rig
		kassen_npc.reduced_override = leben_reduced_override
		add_child(kassen_npc)


## Laden-Sheet öffnen (auch via Dialog-Effekt "laden"). M2-Orte mit eigenem
## Händler-UI überschreiben das und rufen `zeige_sheet()` mit ihrem Inhalt.
## J3: Käufe piepen an der Kasse, wenn der Ort ein Kassen-Verhalten hat.
func oeffne_laden() -> void:
	if _sortiment_pfad().is_empty():
		return
	var inhalt := HaendlerSheet.new()
	inhalt.gs = game_state()
	inhalt.waren = CitySortiment.laden(_sortiment_pfad())
	inhalt.gekauft.connect(_on_leben_kunde_zahlt)
	zeige_sheet(I18nService.t("city.laden.titel"), inhalt)


## Kassen-Hook für Orte mit `kasse: true` in `_leben_konfig()` — auch für
## eigene Händler-Sheets der Erben nutzbar (Muster REHWEI).
func _on_leben_kunde_zahlt(_ware_id: String) -> void:
	if kassen_npc != null:
		kassen_npc.kunde_zahlt()


## Beliebigen Inhalt im Ort-PanelSheet zeigen (ein Sheet je Ort, wird neu
## befüllt). `open()` ist idempotent — ein zweiter Ruf blättert nur um.
func zeige_sheet(titel: String, inhalt: Control) -> void:
	if _sheet == null:
		return
	_sheet.set_title(titel)
	_sheet.add_content(inhalt)
	_sheet.open()


## W18/B7 (Layering-Klasse): Eigenbau-Overlays (MailSheet & Co.) IMMER als
## SPÄTESTES Geschwister in den UI-CanvasLayer hängen — deterministisch ÜBER
## dem Ort-PanelSheet (`_sheet`), nur der ToastLayer bleibt obenauf. Vorher
## landeten sie in `_ui` (frühes Geschwister des Sheets) und mounteten
## HINTER dem offenen Schalter-Sheet: alle Taps schluckte das Sheet
## (Playtest-Befund B7). Overlays, die am Modal-System (G7-P53) teilnehmen
## sollen, melden sich selbst per PanelStack.push/remove an (macht MailSheet).
func zeige_overlay(overlay: Control) -> void:
	if _ui_layer == null:
		return
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	overlay.theme = ThemeService.theme()
	_ui_layer.add_child(overlay)
	if _toast != null and is_instance_valid(_toast):
		_ui_layer.move_child(_toast, _ui_layer.get_child_count() - 1)


func zeige_toast(text: String) -> void:
	if _toast != null and _toast.has_method("show_toast"):
		_toast.show_toast(text)


## Requisiten-Helfer für die Innenraum-Hooks (GLB/GLTF, still bei Fehlpfad).
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


## Ecke-Ursprung-Möbel (Kenney, W18-Audit-Erkenntnis) wie zentrierte Props
## stellen: `mitte` = gewünschte Footprint-Mitte, `grund` = rohe (Breite,
## Tiefe) laut GLB-AABB — der Versatz kommt aus OrtRequisiten.
func _cc0(pfad: String, mitte: Vector3, rot_grad: float, groesse: float, grund: Vector2) -> Node3D:
	var versatz := OrtRequisiten.ecken_versatz(rot_grad, groesse, grund)
	return _prop(pfad, mitte + versatz, rot_grad, groesse)


## ---------------------------------------------------------------- Aufbau


func _baue_raum() -> void:
	var draussen := _ist_draussen()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.74, 0.93) if draussen else Color(0.98, 0.94, 0.87)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.97, 0.92)
	e.ambient_light_energy = 1.0 if draussen else 0.9
	env.environment = e
	add_child(env)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	add_child(licht)
	var boden := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(14.0, 10.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.62, 0.76, 0.52) if draussen else Color(0.87, 0.77, 0.62)
	bm.material = bmat
	boden.mesh = bm
	add_child(boden)
	if not draussen:
		var wand := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(14.0, 5.0, 0.3)
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.96, 0.90, 0.80)
		wm.material = wmat
		wand.mesh = wm
		wand.position = Vector3(0.0, 2.5, -4.0)
		add_child(wand)
	var kamera := Camera3D.new()
	kamera.position = Vector3(0.0, 2.0, 4.2)
	kamera.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	kamera.current = true
	add_child(kamera)


func _baue_npc() -> void:
	var konfig := _npc_konfig()
	rig = GoobyRig.new()
	rig.position = konfig.get("pos", Vector3(0, 0, -2.2))
	rig.rotation.y = 0.0
	add_child(rig)
	rig.set_emotion(str(konfig.get("emotion", "happy")))
	_tinte_npc(konfig.get("tint", Color.WHITE))
	voice = GoobyVoice.new()
	add_child(voice)
	voice.silbe.connect(func(_i: int, _n: int) -> void: rig.babble_pulse())


func _baue_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UiLayer"
	add_child(_ui_layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	_ui.theme = ThemeService.theme()
	_ui_layer.add_child(_ui)
	_baue_vignette()
	dialog = OrtDialogView.new()
	dialog.voice = voice
	_ui.add_child(dialog)
	dialog.effekt.connect(_on_dialog_effekt)
	dialog.beendet.connect(_on_dialog_beendet)
	_zurueck = Button.new()
	_zurueck.name = "Verlassen"
	_zurueck.text = I18nService.t("city.ort.verlassen")
	_zurueck.theme_type_variation = "GhostButton"
	_zurueck.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_zurueck.pressed.connect(_on_verlassen)
	_ui.add_child(_zurueck)
	_sheet = PanelSheetScene.instantiate()
	_sheet.theme = ThemeService.theme()
	_ui_layer.add_child(_sheet)
	_toast = load("res://scripts/ui/toast.gd").new()
	_toast.theme = ThemeService.theme()
	_ui_layer.add_child(_toast)
	# ToastLayer setzt in _ready nur Anker — nach add_child Full-Rect ziehen.
	_toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_relayout_ui)
	_relayout_ui()


## ------------------------------------------------ Knopfleiste (G3/P05)


## Zentrierte, Safe-Area-bewusste Bottom-Knopfleiste (User-Leitidee
## „Knöpfe weg von den Ecken, hin zur Mitte/Daumenzone“): HFlowContainer
## bricht auf schmalen Formaten um statt über die Ränder zu laufen, jeder
## Knopf bekommt den physischen Touch-Floor (≥ 44 pt). Erben rufen den
## Helfer statt eigener HBox-Zeilen; Re-Layout läuft über `size_changed`.
func _baue_knopfleiste(knoepfe: Array[Button], leisten_name := "OrtKnoepfe") -> HFlowContainer:
	var leiste := HFlowContainer.new()
	leiste.name = leisten_name
	leiste.alignment = FlowContainer.ALIGNMENT_CENTER
	leiste.add_theme_constant_override("h_separation", 10)
	leiste.add_theme_constant_override("v_separation", 8)
	for knopf in knoepfe:
		leiste.add_child(knopf)
	_ui.add_child(leiste)
	_leisten.append(leiste)
	_layout_knopfleiste(leiste, ScreenShell.metrics(get_viewport()))
	return leiste


## Alle Metrics-abhängigen UI-Teile nachziehen (Aufbau + Rotation).
func _relayout_ui() -> void:
	if _ui == null or not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	_layout_verlassen(m)
	for leiste in _leisten:
		if leiste != null and is_instance_valid(leiste):
			_layout_knopfleiste(leiste, m)
	_nach_ui_relayout(m)


## Hook für Orte mit eigenen Metrics-abhängigen UI-Extras (Titel,
## Tap-Spots, Hinweis-Zeilen) — läuft nach jedem `_relayout_ui()`.
func _nach_ui_relayout(_m: Dictionary) -> void:
	pass


## „Verlassen“ aus der harten (16,16)-Ecke in die Safe-Area (Notch/Insel!)
## + physischer Touch-Floor — wirkt auf ALLE Orte der Domäne.
func _layout_verlassen(m: Dictionary) -> void:
	if _zurueck == null or not is_instance_valid(_zurueck):
		return
	var insets: Dictionary = m["insets"]
	var f: float = m["f"]
	ScreenShell.touch_target(_zurueck, m)
	ScreenShell.scale_fonts(_zurueck, f)
	_zurueck.position = Vector2(float(insets["left"]) + 16.0 * f, float(insets["top"]) + 12.0 * f)


## Leisten-Geometrie: Breite gedeckelt (Flow-Umbruch statt Überlauf),
## horizontal in der MITTE des Safe-Rechtecks (asymmetrische Insets im
## Querformat), Unterkante über Home-Indicator + Inset; wächst nach OBEN.
func _layout_knopfleiste(leiste: Control, m: Dictionary) -> void:
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	var f: float = m["f"]
	for kind in leiste.get_children():
		if kind is Control:
			ScreenShell.touch_target(kind, m)
	ScreenShell.scale_fonts(leiste, f)
	var breite := ScreenShell.card_width(m, LEISTE_BASIS_BREITE)
	var mitte := (float(insets["left"]) + canvas.x - float(insets["right"])) / 2.0
	leiste.anchor_left = 0.5
	leiste.anchor_right = 0.5
	leiste.anchor_top = 1.0
	leiste.anchor_bottom = 1.0
	leiste.grow_horizontal = Control.GROW_DIRECTION_BOTH
	leiste.grow_vertical = Control.GROW_DIRECTION_BEGIN
	leiste.offset_left = mitte - canvas.x / 2.0 - breite / 2.0
	leiste.offset_right = mitte - canvas.x / 2.0 + breite / 2.0
	leiste.offset_bottom = -(float(insets["bottom"]) + LEISTE_RAND_UNTEN * f)
	leiste.offset_top = leiste.offset_bottom


## Sanfte Vignette über dem 3D-Bild (W4-P3-Ambiente, mobil-tauglich): EINE
## radiale GradientTexture2D, kein Shader und kein Post-Process-Pass — auf
## Handys kostet das genau ein zusätzliches Blit. Farbe = Theme-Tinte
## (AcTokens.INK), Stärke draußen halb so hoch wie im Laden.
func _baue_vignette() -> void:
	var staerke := 0.16 if _ist_draussen() else 0.32
	var verlauf := Gradient.new()
	var tinte := AcTokens.INK
	verlauf.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	verlauf.colors = PackedColorArray(
		[
			Color(tinte.r, tinte.g, tinte.b, 0.0),
			Color(tinte.r, tinte.g, tinte.b, 0.0),
			Color(tinte.r, tinte.g, tinte.b, staerke),
		]
	)
	var textur := GradientTexture2D.new()
	textur.gradient = verlauf
	textur.fill = GradientTexture2D.FILL_RADIAL
	textur.fill_from = Vector2(0.5, 0.5)
	textur.fill_to = Vector2(1.0, 0.5)
	textur.width = 192
	textur.height = 192
	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.texture = textur
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(rect)


func _starte_dialog() -> void:
	var pfad := _dialog_pfad()
	if pfad.is_empty():
		return
	var baum := OrtDialogRunner.baum_laden(pfad)
	var gs := game_state()
	var flags: Dictionary = {}
	if gs != null:
		var raw: Variant = gs.get_value("city.flags", {})
		flags = raw.duplicate(true) if raw is Dictionary else {}
	dialog.starte(baum, flags)


func _on_dialog_effekt(daten: Dictionary) -> void:
	var gs := game_state()
	match str(daten.get("typ", "")):
		"flag":
			if gs != null:
				CityState.set_flag(gs, str(daten["name"]), bool(daten["wert"]))
		"item":
			if gs != null:
				var item := str(daten["name"])
				gs.update(
					func(state: Dictionary) -> void:
						var items: Dictionary = state["inventory"]["items"]
						items[item] = int(items.get(item, 0)) + 1
				)
				zeige_toast(I18nService.t("city.ort.item_erhalten"))
		"laden":
			oeffne_laden()


func _on_dialog_beendet() -> void:
	# Dialog zu Ende: freundlich winken; Laden bleibt über den Knopf offen.
	if rig != null:
		rig.play_clip("wave")


func _on_verlassen() -> void:
	verlassen_angefordert.emit()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null:
		router.goto(CityScene.ROUTE_CITY, {"spawn": ort_id})


func _tinte_npc(farbe: Color) -> void:
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
