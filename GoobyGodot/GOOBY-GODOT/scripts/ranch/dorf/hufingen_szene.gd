class_name HufingenSzene
extends Node3D
## Reit-Dorf Hufingen (RW-4) — betretbarer Ort in Reitweite der Ranch.
## Liegt auf den ECHTEN Weltkoordinaten der RW-1-Zone "hufingen"
## (Rect [360,420,300,220], Plateau h≈2.5, strasse_ende (560,530) —
## s. /tmp/gooby-godot/handoffs/RW1-welt-api.md), damit RanchWeltReiter
## und RanchGelaende ohne Anpassung funktionieren.
##
## Fünf Läden (Reitladen, Futterhof, Möbel-Scheune, Pferdehändlerin,
## Schmiede), jeder mit Ladentheke, Anbindestange und Gooby-NPC
## (RW-3s RNpcKatalog, defensive Fallback-Figuren wenn die Dorf-NPCs
## noch fehlen). Ortsschild am Weganfang bucht die ENTDECKUNG
## (RanchDorfState.entdecke) — erst danach ist Schnellreise frei.
## ANREISE per Ritt: via="ritt" startet am Weganfang, via="schnellreise"
## direkt am Ortsschild (Gate prüft DorfRouten.schnellreise).

const INK := Color("#3B3630")
const GEBAEUDE := "res://assets/ranch/gebaeude"

## RW-3s NPC-Stack wird DYNAMISCH geladen (kein Klassen-Verweis): parst
## eine seiner Dateien gerade nicht oder fehlen die Dorf-NPCs, baut die
## Szene eigene Fallback-Goobys statt kaputtzugehen (Parallel-Entwicklung).
const RNPC_KATALOG_PFAD := "res://scripts/ranch/npc/rnpc_katalog.gd"
const RNPC_FIGUR_PFAD := "res://scripts/ranch/npc/rnpc_figur.gd"

const ORTSSCHILD := Vector3(552.0, 0.0, 522.0)
const PLAZA := Vector3(600.0, 0.0, 540.0)
const SPAWN_RITT := Vector3(432.0, 0.0, 494.0)
const BODEN_RECT := Rect2(370.0, 430.0, 285.0, 205.0)

## Läden: Gebäude-GLB (+ Maßstab, Gebäude sind je ~13-15 m breit) +
## Position + Blickrichtung (Grad, Richtung Plaza).
const LAEDEN := [
	{
		"id": "reitladen",
		"glb": "scheune_klein.glb",
		"scale": 1.8,
		"pos": Vector3(576, 0, 496),
		"rot": 205.0
	},
	{
		"id": "futterhof",
		"glb": "silo_haus.glb",
		"scale": 2.2,
		"pos": Vector3(632, 0, 500),
		"rot": 145.0
	},
	{
		"id": "moebelscheune",
		"glb": "scheune_gross.glb",
		"scale": 1.4,
		"pos": Vector3(648, 0, 556),
		"rot": 105.0
	},
	{
		"id": "schmiede",
		"glb": "scheune.glb",
		"scale": 1.4,
		"pos": Vector3(612, 0, 592),
		"rot": 15.0
	},
	{
		"id": "pferdehaendlerin",
		"glb": "scheune_offen.glb",
		"scale": 1.8,
		"pos": Vector3(560, 0, 576),
		"rot": -60.0
	},
]

## Theken stehen VOR dem Gebäude (Gebäude-Halbtiefe + Gasse).
const THEKE_ABSTAND := 13.0

## Fallback-Goobys, falls RW-3s Dorf-NPCs (dorf_<laden>) noch fehlen.
const NPC_FALLBACK := {
	"reitladen": {"farbe": "#C98BB9", "akzent": "#8A5A7A", "accessoire": "schleife"},
	"futterhof": {"farbe": "#D9A066", "akzent": "#8A5A33", "accessoire": "strohhut"},
	"moebelscheune": {"farbe": "#8FD06C", "akzent": "#557B3E", "accessoire": "kopftuch"},
	"pferdehaendlerin": {"farbe": "#E8A87C", "akzent": "#B23A48", "accessoire": "halstuch"},
	"schmiede": {"farbe": "#9A93A6", "akzent": "#5C5566", "accessoire": "brille"},
}

var game_state_override: Object
var reiter: RanchWeltReiter

var _via := "ritt"
var _bau: RanchBau
var _theken: Array[Dictionary] = []
var _laden_offen: DorfLaden
var _hud: CanvasLayer
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
var _naechster_laden := ""


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func receive_params(params: Dictionary) -> void:
	_via = str(params.get("via", "ritt"))


func _ready() -> void:
	_bau = RanchBau.new(self)
	_bau.baue_licht(11.0)
	_baue_boden()
	_baue_wege()
	_baue_dorf()
	_baue_reiter()
	_baue_hud()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.5, 0.0, 1.0)
	if reiter == null or _laden_offen != null:
		return
	_klammere_reiter()
	_pruefe_entdeckung()
	_pruefe_theken()


func _unhandled_input(event: InputEvent) -> void:
	if _laden_offen != null:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var taste := event as InputEventKey
		if taste.keycode == KEY_E or taste.keycode == KEY_ENTER:
			if not _naechster_laden.is_empty():
				oeffne_laden(_naechster_laden)


## ------------------------------------------------------------------ Welt


## Boden als Höhenfeld aus RanchGelaende (Reiter steht IMMER auf hoehe()).
func _baue_boden() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var schritt := 5.0
	var nx := int(BODEN_RECT.size.x / schritt)
	var nz := int(BODEN_RECT.size.y / schritt)
	for iz in nz:
		for ix in nx:
			var x0 := BODEN_RECT.position.x + float(ix) * schritt
			var z0 := BODEN_RECT.position.y + float(iz) * schritt
			var ecken := [
				Vector3(x0, RanchGelaende.hoehe(x0, z0), z0),
				Vector3(x0 + schritt, RanchGelaende.hoehe(x0 + schritt, z0), z0),
				Vector3(
					x0 + schritt, RanchGelaende.hoehe(x0 + schritt, z0 + schritt), z0 + schritt
				),
				Vector3(x0, RanchGelaende.hoehe(x0, z0 + schritt), z0 + schritt),
			]
			for i: int in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(ecken[i])
	st.generate_normals()
	var boden := MeshInstance3D.new()
	boden.name = "Boden"
	boden.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RanchBau.WIESE_GRUEN
	mat.roughness = 1.0
	boden.material_override = mat
	add_child(boden)


## Schotterweg-Band, das dem Gelände folgt (baue_weg liegt fix auf y=0.04).
func _weg_band(von: Vector3, bis: Vector3, breite: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var richtung := Vector3(bis.x - von.x, 0.0, bis.z - von.z).normalized()
	var quer := Vector3(-richtung.z, 0.0, richtung.x) * breite * 0.5
	var laenge := Vector2(bis.x - von.x, bis.z - von.z).length()
	var schritte := maxi(2, int(laenge / 6.0))
	for i in schritte:
		var a := von + richtung * (laenge * float(i) / float(schritte))
		var b := von + richtung * (laenge * float(i + 1) / float(schritte))
		var ecken := [a - quer, b - quer, b + quer, a + quer]
		for j in 4:
			var p: Vector3 = ecken[j]
			ecken[j] = Vector3(p.x, RanchGelaende.hoehe(p.x, p.z) + 0.06, p.z)
		for j: int in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(ecken[j])
	st.generate_normals()
	var weg := MeshInstance3D.new()
	weg.name = "Weg"
	weg.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RanchBau.WEG_GRAU
	mat.roughness = 1.0
	weg.material_override = mat
	add_child(weg)


func _baue_wege() -> void:
	_weg_band(SPAWN_RITT, Vector3(560.0, 0.0, 530.0), 5.0)
	_weg_band(Vector3(560.0, 0.0, 530.0), PLAZA, 6.0)
	for laden: Dictionary in LAEDEN:
		_weg_band(PLAZA, _theke_pos(laden), 3.5)
	var plaza := MeshInstance3D.new()
	var kreis := CylinderMesh.new()
	kreis.top_radius = 16.0
	kreis.bottom_radius = 16.0
	kreis.height = 0.08
	kreis.radial_segments = 26
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.79, 0.66)
	mat.roughness = 1.0
	kreis.material = mat
	plaza.mesh = kreis
	plaza.position = _punkt(PLAZA) + Vector3(0.0, 0.05, 0.0)
	add_child(plaza)


func _baue_dorf() -> void:
	var schild := _bau.baue_schild(
		_punkt(ORTSSCHILD), I18nService.t("rdorf.ortsname"), I18nService.t("rdorf.ortsschild")
	)
	schild.rotation.y = deg_to_rad(-70.0)
	var brunnen := _bau.lade_glb("%s/brunnen.glb" % GEBAEUDE, 2.4)
	if brunnen != null:
		brunnen.position = _punkt(PLAZA)
		add_child(brunnen)
	var muehle := _bau.lade_glb("%s/windmuehle.glb" % GEBAEUDE, 2.0)
	if muehle != null:
		muehle.position = _punkt(Vector3(655.0, 0.0, 458.0))
		add_child(muehle)
	for laden: Dictionary in LAEDEN:
		_baue_laden(laden)
	for i in 6:
		var laterne := RanchBauVisuals.node_fuer({"id": "laterne", "footprint": Vector2i.ONE})
		var winkel := TAU * float(i) / 6.0
		laterne.position = _punkt(PLAZA + Vector3(cos(winkel), 0.0, sin(winkel)) * 14.0)
		add_child(laterne)


func _baue_laden(laden: Dictionary) -> void:
	var id := str(laden["id"])
	var wurzel := Node3D.new()
	wurzel.name = "Laden_%s" % id
	wurzel.position = _punkt(laden["pos"])
	wurzel.rotation.y = deg_to_rad(float(laden["rot"]))
	add_child(wurzel)
	var glb := _bau.lade_glb("%s/%s" % [GEBAEUDE, str(laden["glb"])], float(laden["scale"]))
	if glb != null:
		wurzel.add_child(glb)
	var theke_welt := _theke_pos(laden)
	_baue_theke(id, theke_welt, laden)
	_anbindestange(theke_welt + _seitwaerts(laden) * 5.5)
	if id == "pferdehaendlerin":
		_baue_koppel(_punkt(Vector3(538.0, 0.0, 596.0)))


## Theken-Weltposition: VOR dem Gebäude Richtung Plaza.
func _theke_pos(laden: Dictionary) -> Vector3:
	var pos: Vector3 = laden["pos"]
	var zur_plaza := Vector3(PLAZA.x - pos.x, 0.0, PLAZA.z - pos.z).normalized()
	return pos + zur_plaza * THEKE_ABSTAND


func _seitwaerts(laden: Dictionary) -> Vector3:
	var pos: Vector3 = laden["pos"]
	var zur_plaza := Vector3(PLAZA.x - pos.x, 0.0, PLAZA.z - pos.z).normalized()
	return Vector3(-zur_plaza.z, 0.0, zur_plaza.x)


func _baue_theke(id: String, welt: Vector3, laden: Dictionary) -> void:
	var pos := _punkt(welt)
	var wurzel := Node3D.new()
	wurzel.name = "Theke_%s" % id
	wurzel.position = pos
	var zur_plaza := Vector3(PLAZA.x - welt.x, 0.0, PLAZA.z - welt.z)
	wurzel.rotation.y = atan2(zur_plaza.x, zur_plaza.z)
	add_child(wurzel)
	_quader(wurzel, Vector3(0.0, 0.55, 0.0), Vector3(2.6, 1.1, 0.8), RanchBau.HOLZ_HELL)
	_quader(wurzel, Vector3(0.0, 1.12, 0.0), Vector3(2.8, 0.1, 1.0), RanchBau.HOLZ_DUNKEL)
	var name_schild := Label3D.new()
	name_schild.text = I18nService.t("rdorf.laden.%s" % id)
	name_schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_schild.font_size = 72
	name_schild.pixel_size = 0.006
	name_schild.modulate = INK
	name_schild.outline_size = 16
	name_schild.outline_modulate = Color(1.0, 0.98, 0.93, 0.9)
	name_schild.position = Vector3(0.0, 2.6, 0.0)
	wurzel.add_child(name_schild)
	var npc := _npc_fuer(id)
	npc.position = Vector3(0.0, 0.0, -1.4)
	npc.rotation.y = PI
	wurzel.add_child(npc)
	_theken.append({"id": id, "pos": pos, "rot": float(laden["rot"])})


## RW-3s Dorf-NPC (dorf_<laden>) nutzen, wenn er existiert — sonst der
## eingebaute Fallback-Gooby (Handoff RW4-dorf-npcs.md).
func _npc_fuer(id: String) -> Node3D:
	var fallback: Dictionary = NPC_FALLBACK.get(id, NPC_FALLBACK["futterhof"])
	var def := {
		"id": "rw4_%s" % id,
		"typ": "npc",
		"modell":
		{
			"art": "gooby",
			"farbe": str(fallback["farbe"]),
			"akzent": str(fallback["akzent"]),
			"groesse": 1.0,
			"accessoire": str(fallback["accessoire"]),
		},
	}
	var katalog := _lade_script(RNPC_KATALOG_PFAD)
	if katalog != null:
		var eintrag: Variant = katalog.npc("dorf_%s" % id)
		if eintrag is Dictionary and not (eintrag as Dictionary).is_empty():
			def = eintrag
	var figur_script := _lade_script(RNPC_FIGUR_PFAD)
	if figur_script != null:
		var figur: Variant = figur_script.neu(def)
		if figur is Node3D:
			return figur
	return _fallback_gooby(def)


## GDScript defensiv laden (null bei fehlender/kaputter Datei).
func _lade_script(pfad: String) -> GDScript:
	if not ResourceLoader.exists(pfad):
		return null
	var script: Variant = ResourceLoader.load(pfad)
	if script is GDScript and (script as GDScript).can_instantiate():
		return script
	return null


## Minimaler Verkäufer-Gooby (Kugel-Körper, Kopf, Augen, Namensschild) —
## nur falls RW-3s RNpcFigur (noch) nicht ladbar ist.
func _fallback_gooby(def: Dictionary) -> Node3D:
	var modell: Dictionary = def.get("modell") if def.get("modell") is Dictionary else {}
	var fell := Color(str(modell.get("farbe", "#D9A066")))
	var wurzel := Node3D.new()
	wurzel.name = "Npc_%s" % str(def.get("id", "npc"))
	var rumpf := MeshInstance3D.new()
	var rumpf_mesh := SphereMesh.new()
	rumpf_mesh.radius = 0.42
	rumpf_mesh.height = 0.95
	rumpf_mesh.material = RanchPferd.material(fell)
	rumpf.mesh = rumpf_mesh
	rumpf.position.y = 0.48
	wurzel.add_child(rumpf)
	var kopf := MeshInstance3D.new()
	var kopf_mesh := SphereMesh.new()
	kopf_mesh.radius = 0.3
	kopf_mesh.height = 0.6
	kopf_mesh.material = RanchPferd.material(fell.lightened(0.12))
	kopf.mesh = kopf_mesh
	kopf.position.y = 1.15
	wurzel.add_child(kopf)
	for seite: float in [-1.0, 1.0]:
		var auge := MeshInstance3D.new()
		var auge_mesh := SphereMesh.new()
		auge_mesh.radius = 0.05
		auge_mesh.height = 0.1
		auge_mesh.material = RanchPferd.material(Color(0.13, 0.12, 0.14))
		auge.mesh = auge_mesh
		auge.position = Vector3(seite * 0.11, 1.2, 0.26)
		wurzel.add_child(auge)
	var schild := Label3D.new()
	schild.text = I18nService.t("rnpc.%s.name" % str(def.get("id", "")))
	schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	schild.font_size = 64
	schild.pixel_size = 0.004
	schild.modulate = Color(0.22, 0.18, 0.16)
	schild.outline_size = 14
	schild.outline_modulate = Color(1.0, 0.98, 0.93, 0.9)
	schild.position = Vector3(0.0, 1.7, 0.0)
	wurzel.add_child(schild)
	return wurzel


## Anbindestange: zwei Pfosten + Querbalken (Pferd wartet hier beim Einkauf).
func _anbindestange(welt: Vector3) -> void:
	var pos := _punkt(welt)
	var wurzel := Node3D.new()
	wurzel.name = "Anbindestange"
	wurzel.position = pos
	add_child(wurzel)
	for seite: float in [-1.0, 1.0]:
		_quader(
			wurzel, Vector3(seite * 1.1, 0.55, 0.0), Vector3(0.18, 1.1, 0.18), RanchBau.HOLZ_DUNKEL
		)
	_quader(wurzel, Vector3(0.0, 0.95, 0.0), Vector3(2.4, 0.14, 0.14), RanchBau.HOLZ_HELL)


## Kleine Verkaufs-Koppel der Pferdehändlerin mit zwei Angebots-Pferden.
func _baue_koppel(pos: Vector3) -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Koppel"
	wurzel.position = pos
	add_child(wurzel)
	for i in 8:
		var winkel := TAU * float(i) / 8.0
		var pfosten := Vector3(cos(winkel), 0.0, sin(winkel)) * 9.0
		_quader(
			wurzel, pfosten + Vector3(0.0, 0.5, 0.0), Vector3(0.18, 1.0, 0.18), RanchBau.HOLZ_DUNKEL
		)
		var naechster := Vector3(cos(winkel + TAU / 8.0), 0.0, sin(winkel + TAU / 8.0)) * 9.0
		var mitte := (pfosten + naechster) * 0.5 + Vector3(0.0, 0.8, 0.0)
		var balken := _quader(
			wurzel, mitte, Vector3(pfosten.distance_to(naechster), 0.12, 0.1), RanchBau.HOLZ_HELL
		)
		balken.rotation.y = atan2(naechster.x - pfosten.x, naechster.z - pfosten.z) + PI * 0.5
	var farben := [RanchPferd.FELL["schecke"], RanchPferd.FELL["fuchs"]]
	for i in 2:
		var pferd := RanchPferd.neu(farben[i][0], farben[i][1])
		pferd.position = Vector3(-3.0 + float(i) * 6.0, 0.0, float(i) * 2.0 - 1.0)
		pferd.rotation.y = 0.7 + float(i) * 2.1
		wurzel.add_child(pferd)


func _baue_reiter() -> void:
	reiter = RanchWeltReiter.new()
	reiter.name = "Reiter"
	add_child(reiter)
	if _via == "schnellreise":
		reiter.springe_zu(_punkt(ORTSSCHILD + Vector3(4.0, 0.0, 6.0)), deg_to_rad(-70.0))
	else:
		reiter.springe_zu(_punkt(SPAWN_RITT), deg_to_rad(-90.0))


## ------------------------------------------------------------------ HUD


func _baue_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "Hud"
	add_child(_hud)
	var titel := Label.new()
	titel.text = I18nService.t("rdorf.ortsname")
	titel.position = Vector2(24, 16)
	titel.add_theme_font_size_override("font_size", 26)
	titel.add_theme_color_override("font_color", INK)
	titel.add_theme_color_override("font_outline_color", Color(1, 0.98, 0.93, 0.9))
	titel.add_theme_constant_override("outline_size", 8)
	_hud.add_child(titel)
	var heim := Button.new()
	heim.text = I18nService.t("rdorf.heimreiten")
	heim.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	heim.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	heim.position = Vector2(-230, 16)
	heim.custom_minimum_size = Vector2(210, 40)
	heim.pressed.connect(_heimreiten)
	_hud.add_child(heim)
	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-200, -72)
	_prompt.custom_minimum_size = Vector2(400, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_color", INK)
	_prompt.add_theme_color_override("font_outline_color", Color(1, 0.98, 0.93, 0.95))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.visible = false
	_hud.add_child(_prompt)
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-250, 70)
	_toast.custom_minimum_size = Vector2(500, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color("#4E7C3A"))
	_toast.add_theme_color_override("font_outline_color", Color(1, 0.98, 0.93, 0.95))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	_hud.add_child(_toast)


## ------------------------------------------------------------------ Ablauf


func _klammere_reiter() -> void:
	var rand := 6.0
	reiter.position.x = clampf(
		reiter.position.x, BODEN_RECT.position.x + rand, BODEN_RECT.end.x - rand
	)
	reiter.position.z = clampf(
		reiter.position.z, BODEN_RECT.position.y + rand, BODEN_RECT.end.y - rand
	)


## Ortsschild passiert? → Entdeckung buchen (schaltet Schnellreise frei).
func _pruefe_entdeckung() -> void:
	var schild := _punkt(ORTSSCHILD)
	if Vector2(reiter.position.x - schild.x, reiter.position.z - schild.z).length() > 9.0:
		return
	if RanchDorfState.entdecke(game_state()):
		_zeige_toast(I18nService.t("rdorf.entdeckt"))


func _pruefe_theken() -> void:
	_naechster_laden = ""
	var beste := 6.5
	for theke: Dictionary in _theken:
		var pos: Vector3 = theke["pos"]
		var abstand := Vector2(reiter.position.x - pos.x, reiter.position.z - pos.z).length()
		if abstand < beste:
			beste = abstand
			_naechster_laden = str(theke["id"])
	if _naechster_laden.is_empty():
		_prompt.visible = false
	else:
		_prompt.visible = true
		_prompt.text = I18nService.t(
			"rdorf.prompt", {"laden": I18nService.t("rdorf.laden.%s" % _naechster_laden)}
		)


## Laden öffnen: Reiter parkt an der Anbindestange, Screen als Overlay.
func oeffne_laden(id: String) -> void:
	if _laden_offen != null:
		return
	reiter.steuerung_aktiv = false
	_prompt.visible = false
	_laden_offen = DorfLaden.neu(id, game_state())
	_laden_offen.geschlossen.connect(_schliesse_laden)
	_hud.add_child(_laden_offen)


func _schliesse_laden() -> void:
	if _laden_offen == null:
		return
	_laden_offen.queue_free()
	_laden_offen = null
	reiter.steuerung_aktiv = true


## Heimreiten: zurück in RW-1s offene Region (Zone hufingen — von dort
## reitet man den Feldweg zur Ranch); ohne Region direkt zum Hof.
func _heimreiten() -> void:
	var router: Object = DorfRouten.router_override
	if router == null:
		router = get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	if ResourceLoader.exists(DorfRouten.SZENE_WELT):
		if router.has_method("register_route"):
			router.register_route(DorfRouten.ROUTE_WELT, DorfRouten.SZENE_WELT)
		router.goto(DorfRouten.ROUTE_WELT, {"spawn_zone": "hufingen"})
	else:
		router.goto(RanchRouten.ROUTE_HOF, {})


func _zeige_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 3.0
	_toast.modulate.a = 1.0


## ------------------------------------------------------------------ Helfer


## Weltpunkt auf Bodenhöhe (RanchGelaende — eine Wahrheit mit dem Reiter).
func _punkt(welt: Vector3) -> Vector3:
	return Vector3(welt.x, RanchGelaende.hoehe(welt.x, welt.z), welt.z)


func _quader(wurzel: Node3D, pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mesh.material = RanchPferd.material(farbe)
	mi.mesh = mesh
	mi.position = pos
	wurzel.add_child(mi)
	return mi
