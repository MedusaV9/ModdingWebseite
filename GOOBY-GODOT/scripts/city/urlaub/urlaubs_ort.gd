class_name UrlaubsOrt
extends OrtScene
## W15/URLAUB — die begehbare Urlaubs-Besuchs-Szene (User-Wunsch: „Gooby im
## Urlaub begleiten … Sachen erleben … ganz viele neue Bereiche“). EIN
## Skript, DREI Szenen-Archetypen (Vorbild: raumstation.gd über OrtScene):
##
## - STRAND (beach/harbor): Sand, Meer mit dem BESTEHENDEN Wasser-Shader
##   (ranch/welt/wasser.gdshader), Liegestuhl, Sonnenschirm, Sandburg.
## - BERGE (meadowTrip/spookGarden/nightSky): Wiese, Zelt, Lagerfeuer,
##   Berg-Silhouetten, Ranch-Wald-Kit (assets/ranch/natur).
## - STADT (bigCity/bakery/toyRoom): Café-Terrasse (city-Innen-Kit),
##   Sehenswürdigkeits-Silhouette, Lichterkette.
##
## `space` besucht die BESTEHENDE Raumstation (UrlaubsBesuch.route_fuer).
##
## Erlebnisse vor Ort (2–3 aktive Dinge, alles über BESTEHENDE APIs):
## Streicheln (Clip + Spaß-Bonus), Foto (Fotomodus mit Urlaubs-Kulisse),
## 1 Mini-Aktivität (Tap-Spots bzw. Café-Bestell-Gag — KEIN neues
## Minigame) und 1 Souvenir-Spot (tägliches Fundstück → inventory.items +
## Münzen additiv). Gooby erzählt per AcBubble (UrlaubsSprueche-Rotation),
## 2 Urlauber-Gooby-Statisten mit Idle-Hops sorgen für Leben.
##
## Der Besuch ist eine reine ANSICHT: keine Energie-Kosten, KEINE
## Vacation-Phasen-Änderung — nur das additive Erinnerungs-Flag
## (`vacation.besuche`, UrlaubsBesuch.merke_besuch). Verlassen reist über
## SceneRouter.back() zur vorherigen Szene zurück.

const Vacation := preload("res://scripts/logic/vacation.gd")

const SKY_SHADER := "res://assets/sky/gooby_himmel.gdshader"
const WASSER_SHADER := "res://scripts/ranch/welt/wasser.gdshader"
const NATUR := "res://assets/ranch/natur"
const INNEN := "res://assets/city/innen"
const ESSEN := "res://assets/city/essen"

## Archetyp-Daten (Keys → strings/de+en/urlaub.json).
const ARCHETYP_DATEN := {
	"strand":
	{
		"titel_key": "urlaub.titel.strand",
		"mini_key": "urlaub.knopf.mini.strand",
		"spot_symbol": "🐚",
		"statisten_tints": [Color("#F2C57C"), Color("#8FD1C0")],
	},
	"berge":
	{
		"titel_key": "urlaub.titel.berge",
		"mini_key": "urlaub.knopf.mini.berge",
		"spot_symbol": "🌸",
		"statisten_tints": [Color("#A7C97E"), Color("#C9A07E")],
	},
	"stadt":
	{
		"titel_key": "urlaub.titel.stadt",
		"mini_key": "urlaub.knopf.mini.stadt",
		"spot_symbol": "☕",
		"statisten_tints": [Color("#D89BC0"), Color("#9BB7E8")],
	},
}

## Statisten-Idle: kleiner, gemütlicher Hop (reine Tween-Zahlen).
const STATIST_HOP_HOEHE := 0.14
const STATIST_HOP_DAUER := 1.4

## Archetyp der Szene (strand/berge/stadt) — von den drei .tscn-Wrappern
## gesetzt; unbekannte Werte fallen in _ready auf "strand" zurück.
@export var archetyp := "strand"

## Tests: Router-Attrappe statt /root/SceneRouter.
var router_override: Object = null
## Besuchtes Ziel (via receive_params; leer → erstes Ziel des Archetyps).
var dest_id := ""
## Tap-Mini-Zustand (UrlaubsAktivitaeten, pur) + UI-Knöpfe (Tests).
var tap_zustand: Dictionary = {}
var tap_knoepfe: Array[Button] = []
## Bestell-Gag-Rotation (stadt).
var bestell_zaehler := 0
## Urlauber-Statisten (Tests + Idle-Hops).
var statisten: Array[GoobyRig] = []

var _tap_ebene: Control
var _kamera: Camera3D


## Erstes Katalog-Ziel eines Archetyps (Fallback ohne receive_params).
static func erstes_ziel(fuer_archetyp: String) -> String:
	for ziel: String in ReiseLogic.ZIELE:
		if UrlaubsBesuch.archetyp_fuer(ziel) == fuer_archetyp:
			return ziel
	return "beach"


func _ready() -> void:
	if not ARCHETYP_DATEN.has(archetyp):
		archetyp = "strand"
	if ort_id.is_empty():
		ort_id = "urlaub_%s" % archetyp
	if dest_id.is_empty() or UrlaubsBesuch.archetyp_fuer(dest_id) != archetyp:
		dest_id = erstes_ziel(archetyp)
	super._ready()
	UrlaubsBesuch.merke_besuch(game_state(), dest_id)
	_starte_statisten_hop()
	_erzaehle.call_deferred()


func receive_params(params: Dictionary) -> void:
	super.receive_params(params)
	var ziel := str(params.get("dest_id", ""))
	if UrlaubsBesuch.ZIEL_ARCHETYP.has(ziel):
		dest_id = ziel
		var ziel_archetyp := UrlaubsBesuch.archetyp_fuer(ziel)
		if ARCHETYP_DATEN.has(ziel_archetyp):
			archetyp = ziel_archetyp
			ort_id = "urlaub_%s" % archetyp


## ---------------------------------------------------------------- Aufbau


## Urlaubs-Kulisse statt Ladenraum (Muster raumstation._baue_raum):
## Sky-Shader-Himmel + Licht + Kamera gemeinsam, Boden/Panorama je Archetyp.
func _baue_raum() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = _himmel()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.97, 0.9)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	licht.light_energy = 1.1
	add_child(licht)
	match archetyp:
		"strand":
			_baue_strand_kulisse()
		"berge":
			_baue_berge_kulisse()
		_:
			_baue_stadt_kulisse()
	_kamera = Camera3D.new()
	_kamera.position = Vector3(0.0, 2.2, 4.6)
	_kamera.rotation_degrees = Vector3(-13.0, 0.0, 0.0)
	_kamera.current = true
	add_child(_kamera)


func _baue_innenraum() -> void:
	match archetyp:
		"strand":
			_baue_strand_props()
		"berge":
			_baue_berge_props()
		_:
			_baue_stadt_props()
	_baue_souvenir_spot(_souvenir_spot_position())
	_baue_statisten()


## Gooby selbst (der Urlauber!) — ungetint, bester Laune, mitten im Bild.
func _npc_konfig() -> Dictionary:
	return {"tint": Color.WHITE, "emotion": "ecstatic", "pos": Vector3(0.5, 0.0, -1.5)}


func _baue_ui() -> void:
	super._baue_ui()
	var daten: Dictionary = ARCHETYP_DATEN[archetyp]
	var titel := Label.new()
	titel.name = "UrlaubsTitel"
	titel.theme_type_variation = "HeadlineLabel"
	titel.text = I18nService.t(str(daten["titel_key"]))
	titel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 14)
	titel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui.add_child(titel)
	var reihe := HBoxContainer.new()
	reihe.name = "BesuchsKnoepfe"
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	reihe.add_theme_constant_override("separation", 10)
	reihe.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20
	)
	reihe.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui.add_child(reihe)
	reihe.add_child(_knopf("Streicheln", I18nService.t("urlaub.knopf.streicheln"), "PrimaryButton"))
	reihe.add_child(_knopf("Foto", I18nService.t("urlaub.knopf.foto"), "AccentButton"))
	reihe.add_child(_knopf("MiniAktivitaet", I18nService.t(str(daten["mini_key"])), "AccentButton"))
	reihe.add_child(_knopf("Souvenir", I18nService.t("urlaub.knopf.souvenir"), "AccentButton"))
	(reihe.get_node("Streicheln") as Button).pressed.connect(_on_streicheln)
	(reihe.get_node("Foto") as Button).pressed.connect(_on_foto)
	(reihe.get_node("MiniAktivitaet") as Button).pressed.connect(_on_mini)
	(reihe.get_node("Souvenir") as Button).pressed.connect(_on_souvenir)


## ------------------------------------------------------------ Erlebnisse


## Streicheln: Kuschel-Moment — Tanz-Clip, Spaß-Bonus, Erzähl-Blase und
## (falls eine Seele im Baum wohnt) ein Soul-Kommentar.
func _on_streicheln() -> void:
	AudioDirector.try_play(self, "ui_click")
	if rig != null:
		rig.set_emotion("ecstatic")
		rig.play_clip(GoobyRig.CLIP_DANCE)
	UrlaubsAktivitaeten.fun_bonus(game_state(), UrlaubsAktivitaeten.FUN_STREICHELN)
	SeeleRunner.kommentar_im_raum(self, UrlaubsBesuch.SOUL_KATEGORIE)
	_erzaehle()


## Foto: der BESTEHENDE Fotomodus über der Urlaubs-Kulisse (das Panorama
## IST der Spezial-Hintergrund — Muster raumstation._on_sternenfoto).
func _on_foto() -> void:
	var gs := game_state()
	if gs == null:
		return
	if not FotoModus.ist_frei(gs):
		zeige_toast(I18nService.t("urlaub.toast.keine_kamera"))
		return
	AudioDirector.try_play(self, "ui_click")
	FotoModus.oeffne(self, gs)


## Mini-Aktivität: strand/berge = Tap-Spots, stadt = Café-Bestell-Gag.
func _on_mini() -> void:
	AudioDirector.try_play(self, "ui_click")
	if archetyp == "stadt":
		_bestell_gag()
		return
	if _tap_ebene != null and is_instance_valid(_tap_ebene):
		return
	tap_zustand = UrlaubsAktivitaeten.tap_neu()
	_baue_tap_ebene()


## Souvenir-Spot: das tägliche Fundstück (Cooldown zeitinjiziert im
## vacation-Slice; Gutschrift additiv über die bestehenden APIs).
func _on_souvenir() -> void:
	var res := UrlaubsAktivitaeten.souvenir_einloesen(game_state(), dest_id, _now_ms())
	if not bool(res["ok"]):
		zeige_toast(I18nService.t("urlaub.toast.souvenir_leer"))
		return
	AudioDirector.try_play(self, "ui_sticker")
	UrlaubsAktivitaeten.fun_bonus(game_state(), UrlaubsAktivitaeten.FUN_SOUVENIR)
	SeeleRunner.kommentar_im_raum(self, UrlaubsBesuch.SOUL_KATEGORIE)
	zeige_toast(
		(
			I18nService
			. t(
				"urlaub.toast.souvenir",
				{
					"name": I18nService.t("urlaub.souvenir.%s" % dest_id),
					"coins": int(res["coins"]),
				}
			)
		)
	)
	if rig != null:
		rig.play_clip("wave")


## ------------------------------------------------------------- Tap-Spots


func _baue_tap_ebene() -> void:
	_tap_ebene = Control.new()
	_tap_ebene.name = "TapEbene"
	_tap_ebene.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_ebene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_tap_ebene)
	tap_knoepfe.clear()
	var symbol := str(ARCHETYP_DATEN[archetyp]["spot_symbol"])
	var positionen := _tap_positionen()
	for i in positionen.size():
		var knopf := Button.new()
		knopf.name = "TapSpot%d" % i
		knopf.text = symbol
		knopf.theme_type_variation = "AccentButton"
		knopf.custom_minimum_size = Vector2(56.0, 56.0)
		knopf.pressed.connect(_on_tap.bind(i))
		_tap_ebene.add_child(knopf)
		tap_knoepfe.append(knopf)
	_platziere_tap_knoepfe.call_deferred(positionen)


## Knöpfe über den 3D-Markern platzieren (Kamera steht still — einmaliges
## Unprojezieren reicht; ohne Kamera bleibt die Fallback-Reihe).
func _platziere_tap_knoepfe(positionen: Array) -> void:
	for i in tap_knoepfe.size():
		var knopf := tap_knoepfe[i]
		if knopf == null or not is_instance_valid(knopf):
			continue
		var schirm := Vector2(120.0 + 90.0 * i, 180.0)
		if _kamera != null and _kamera.is_inside_tree():
			schirm = _kamera.unproject_position(positionen[i] + Vector3(0.0, 0.35, 0.0))
		knopf.position = schirm - knopf.size * 0.5


func _on_tap(index: int) -> void:
	var res := UrlaubsAktivitaeten.tap_tippe(tap_zustand, index)
	if not bool(res["ok"]):
		return
	AudioDirector.try_play(self, "ui_click")
	if index < tap_knoepfe.size() and is_instance_valid(tap_knoepfe[index]):
		tap_knoepfe[index].visible = false
	if not bool(res["fertig"]):
		return
	# Alle Spots gefunden: kleiner Bonus + Erzähl-Blase, Ebene abräumen.
	AudioDirector.try_play(self, "ui_sticker")
	UrlaubsAktivitaeten.fun_bonus(game_state(), UrlaubsAktivitaeten.FUN_MINI_FERTIG)
	SeeleRunner.kommentar_im_raum(self, UrlaubsBesuch.SOUL_KATEGORIE)
	zeige_toast(I18nService.t("urlaub.toast.mini_fertig"))
	if rig != null:
		rig.play_clip(GoobyRig.CLIP_DANCE)
	_erzaehle()
	if _tap_ebene != null and is_instance_valid(_tap_ebene):
		_tap_ebene.queue_free()
	_tap_ebene = null


## Tap-Spot-Weltpositionen (auch 3D-Marker-Anker in den Props).
func _tap_positionen() -> Array:
	if archetyp == "berge":
		return [
			Vector3(-3.2, 0.0, -1.0),
			Vector3(-1.6, 0.0, -2.6),
			Vector3(1.8, 0.0, -2.9),
			Vector3(3.4, 0.0, -1.2),
			Vector3(2.6, 0.0, 0.6),
		]
	return [
		Vector3(-3.6, 0.0, -0.6),
		Vector3(-2.0, 0.0, -2.2),
		Vector3(0.8, 0.0, -2.8),
		Vector3(3.0, 0.0, -1.8),
		Vector3(3.8, 0.0, 0.2),
	]


## ------------------------------------------------------- Café-Bestell-Gag


## Kellner-Gag (stadt): jede Bestellung serviert das NÄCHSTE Quatsch-
## Gericht (Rotation, pur) — Kellner-Statist winkt, Gooby freut sich.
func _bestell_gag() -> void:
	var gerichte := I18nService.items("urlaub.bestellung")
	var index := UrlaubsAktivitaeten.bestellung_index(bestell_zaehler, gerichte.size())
	if index < 0:
		return
	bestell_zaehler += 1
	if not statisten.is_empty() and is_instance_valid(statisten[0]):
		statisten[0].play_clip("wave")
	if rig != null:
		rig.set_emotion("ecstatic")
		rig.play_clip(GoobyRig.CLIP_DANCE)
	UrlaubsAktivitaeten.fun_bonus(game_state(), UrlaubsAktivitaeten.FUN_MINI_FERTIG)
	SeeleRunner.kommentar_im_raum(self, UrlaubsBesuch.SOUL_KATEGORIE)
	AcBubble.show_bubble(_ui, String(gerichte[index]), {"speaker_3d": rig})


## ------------------------------------------------------------ Erzählung


## Gooby erzählt, was er erlebt hat (8 Lines je Archetyp, Rotation).
func _erzaehle() -> void:
	if _ui == null or rig == null:
		return
	var text := UrlaubsSprueche.naechste(archetyp)
	if text.is_empty():
		return
	AcBubble.show_bubble(_ui, text, {"speaker_3d": rig})


## ------------------------------------------------------------- Rückweg


## Besuch beendet → zurück zur vorherigen Szene (SceneRouter.back);
## ohne History (Direktstart) sanft nach Hause.
func _on_verlassen() -> void:
	verlassen_angefordert.emit()
	var router := _router()
	if router == null:
		return
	if router.has_method("back") and router.back():
		return
	if router.has_method("goto"):
		router.goto(&"home/living", {})


## --------------------------------------------------------------- Kulisse


func _baue_strand_kulisse() -> void:
	_boden(Vector2(20.0, 16.0), Color(0.93, 0.85, 0.66))
	# Meer mit dem BESTEHENDEN Wasser-Shader: band_modus → Schaumsaum
	# entlang der Uferkante (UV.x läuft nach der Drehung längs zur Küste).
	var meer := MeshInstance3D.new()
	meer.name = "Meer"
	var flaeche := PlaneMesh.new()
	flaeche.size = Vector2(16.0, 34.0)
	flaeche.subdivide_width = 12
	flaeche.subdivide_depth = 24
	var wasser := ShaderMaterial.new()
	wasser.shader = load(WASSER_SHADER)
	wasser.set_shader_parameter("band_modus", 1.0)
	wasser.set_shader_parameter("welle_staerke", 1.0)
	flaeche.material = wasser
	meer.mesh = flaeche
	meer.rotation_degrees.y = 90.0
	meer.position = Vector3(0.0, -0.04, -11.0)
	add_child(meer)
	# Düne als sanfter Abschluss hinter dem Handtuch-Bereich.
	_quader("Duene", Vector3(-6.5, 0.25, -4.5), Vector3(6.0, 0.5, 3.0), Color(0.9, 0.8, 0.6))


func _baue_berge_kulisse() -> void:
	_boden(Vector2(20.0, 16.0), Color(0.55, 0.72, 0.45))
	# Berg-Silhouetten: Kegel mit Schneekappen (Low-Poly aus Bordmitteln).
	_berg(Vector3(-6.0, 0.0, -12.0), 7.5, 4.2, Color(0.52, 0.55, 0.62))
	_berg(Vector3(1.5, 0.0, -14.0), 9.5, 5.2, Color(0.46, 0.5, 0.58))
	_berg(Vector3(8.0, 0.0, -11.0), 6.5, 3.6, Color(0.56, 0.58, 0.64))


func _baue_stadt_kulisse() -> void:
	_boden(Vector2(20.0, 16.0), Color(0.72, 0.7, 0.68))
	# Skyline-Silhouette + die eine Sehenswürdigkeit (Kugelturm).
	var skyline := [
		Vector3(-7.0, 1.6, -11.0),
		Vector3(-4.2, 2.4, -12.0),
		Vector3(2.8, 2.0, -12.0),
		Vector3(6.4, 2.8, -11.5),
	]
	for i in skyline.size():
		var pos: Vector3 = skyline[i]
		_quader("Skyline%d" % i, pos, Vector3(2.2, pos.y * 2.0, 1.6), Color(0.36, 0.38, 0.48))
	_baue_sehenswuerdigkeit(Vector3(-0.8, 0.0, -11.5))


## --------------------------------------------------------------- Props


func _baue_strand_props() -> void:
	_baue_liegestuhl(Vector3(-2.6, 0.0, -1.2), 18.0)
	_baue_sonnenschirm(Vector3(-3.3, 0.0, -1.9), Color(0.94, 0.62, 0.66))
	_baue_sandburg(Vector3(1.6, 0.0, -1.4))
	_prop("%s/log.glb" % NATUR, Vector3(-4.6, 0.0, 0.8), 35.0, 2.2)
	_handtuch("Handtuch0", Vector3(2.9, 0.0, 0.4), Color(0.95, 0.75, 0.4))
	_handtuch("Handtuch1", Vector3(-1.0, 0.0, 0.9), Color(0.55, 0.75, 0.95))
	for i in _tap_positionen().size():
		_muschel_marker(_tap_positionen()[i], i)


func _baue_berge_props() -> void:
	_baue_zelt(Vector3(-2.8, 0.0, -2.0), 20.0)
	_baue_lagerfeuer(Vector3(0.2, 0.0, -0.6))
	_prop("%s/tree_default.glb" % NATUR, Vector3(-5.2, 0.0, -4.5), 10.0, 1.6)
	_prop("%s/tree_detailed.glb" % NATUR, Vector3(5.4, 0.0, -5.0), 70.0, 1.5)
	_prop("%s/tree_oak.glb" % NATUR, Vector3(4.2, 0.0, -3.0), 0.0, 1.2)
	_prop("%s/rock_largeA.glb" % NATUR, Vector3(-4.4, 0.0, -0.4), 25.0, 1.0)
	_prop("%s/plant_bush.glb" % NATUR, Vector3(2.2, 0.0, -3.6), 0.0, 1.4)
	# Die Bergblume, die Gooby gerade bestaunt (Erlebnis-Anker).
	_prop("%s/flower_purpleA.glb" % NATUR, Vector3(1.3, 0.0, -1.6), 0.0, 2.4)
	var blumen := ["flower_redA", "flower_yellowA", "flower_purpleA"]
	var positionen := _tap_positionen()
	for i in positionen.size():
		var name: String = blumen[i % blumen.size()]
		_prop("%s/%s.glb" % [NATUR, name], positionen[i], 20.0 * i, 1.6)


func _baue_stadt_props() -> void:
	_baue_cafe_terrasse(Vector3(-2.4, 0.0, -1.8))
	_baue_lichterkette(Vector3(-4.4, 2.4, -3.2), Vector3(4.4, 2.4, -3.2), 7)
	_prop("%s/menu.gltf" % INNEN, Vector3(-4.2, 0.0, -2.8), 15.0, 1.8)
	# Gooby schleckt ein RIESEN-Eis (bestehendes Food-Kit als Prop).
	_prop("%s/ice-cream.glb" % ESSEN, Vector3(1.4, 0.0, -1.3), 0.0, 3.0)


## --------------------------------------------------------- Prop-Bauteile


func _boden(groesse: Vector2, farbe: Color) -> void:
	var boden := MeshInstance3D.new()
	boden.name = "UrlaubsBoden"
	var flaeche := PlaneMesh.new()
	flaeche.size = groesse
	var material := StandardMaterial3D.new()
	material.albedo_color = farbe
	material.roughness = 0.9
	flaeche.material = material
	boden.mesh = flaeche
	add_child(boden)


func _quader(name_id: String, pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var teil := MeshInstance3D.new()
	teil.name = name_id
	var box := BoxMesh.new()
	box.size = groesse
	var material := StandardMaterial3D.new()
	material.albedo_color = farbe
	material.roughness = 0.8
	box.material = material
	teil.mesh = box
	teil.position = pos
	add_child(teil)
	return teil


func _baue_liegestuhl(pos: Vector3, rot_grad: float) -> void:
	var stuhl := Node3D.new()
	stuhl.name = "Liegestuhl"
	stuhl.position = pos
	stuhl.rotation_degrees.y = rot_grad
	add_child(stuhl)
	var holz := Color(0.75, 0.6, 0.42)
	var stoff := Color(0.95, 0.55, 0.55)
	stuhl.add_child(_teil(Vector3(0.0, 0.28, 0.3), Vector3(0.8, 0.08, 1.0), holz))
	var lehne := _teil(Vector3(0.0, 0.62, -0.35), Vector3(0.8, 0.08, 0.9), holz)
	lehne.rotation_degrees.x = -50.0
	stuhl.add_child(lehne)
	stuhl.add_child(_teil(Vector3(0.0, 0.3, 0.3), Vector3(0.7, 0.1, 0.9), stoff))
	var polster := _teil(Vector3(0.0, 0.64, -0.33), Vector3(0.7, 0.1, 0.8), stoff)
	polster.rotation_degrees.x = -50.0
	stuhl.add_child(polster)
	stuhl.add_child(_teil(Vector3(-0.35, 0.14, 0.7), Vector3(0.08, 0.28, 0.08), holz))
	stuhl.add_child(_teil(Vector3(0.35, 0.14, 0.7), Vector3(0.08, 0.28, 0.08), holz))
	stuhl.add_child(_teil(Vector3(-0.35, 0.14, -0.1), Vector3(0.08, 0.28, 0.08), holz))
	stuhl.add_child(_teil(Vector3(0.35, 0.14, -0.1), Vector3(0.08, 0.28, 0.08), holz))


func _baue_sonnenschirm(pos: Vector3, farbe: Color) -> void:
	var schirm := Node3D.new()
	schirm.name = "Sonnenschirm"
	schirm.position = pos
	add_child(schirm)
	schirm.add_child(_teil(Vector3(0.0, 1.1, 0.0), Vector3(0.1, 2.2, 0.1), Color(0.8, 0.72, 0.6)))
	var dach := MeshInstance3D.new()
	var kegel := CylinderMesh.new()
	kegel.top_radius = 0.04
	kegel.bottom_radius = 1.5
	kegel.height = 0.7
	kegel.radial_segments = 10
	var material := StandardMaterial3D.new()
	material.albedo_color = farbe
	material.roughness = 0.7
	kegel.material = material
	dach.mesh = kegel
	dach.position = Vector3(0.0, 2.35, 0.0)
	schirm.add_child(dach)


func _baue_sandburg(pos: Vector3) -> void:
	var burg := Node3D.new()
	burg.name = "Sandburg"
	burg.position = pos
	add_child(burg)
	var sand := Color(0.87, 0.76, 0.53)
	for eck: Vector3 in [
		Vector3(-0.4, 0.0, -0.4),
		Vector3(0.4, 0.0, -0.4),
		Vector3(-0.4, 0.0, 0.4),
		Vector3(0.4, 0.0, 0.4),
	]:
		var turm := MeshInstance3D.new()
		var zylinder := CylinderMesh.new()
		zylinder.top_radius = 0.16
		zylinder.bottom_radius = 0.2
		zylinder.height = 0.55
		zylinder.material = _matt(sand)
		turm.mesh = zylinder
		turm.position = eck + Vector3(0.0, 0.28, 0.0)
		burg.add_child(turm)
		var spitze := MeshInstance3D.new()
		var kegel := CylinderMesh.new()
		kegel.top_radius = 0.0
		kegel.bottom_radius = 0.2
		kegel.height = 0.25
		kegel.material = _matt(sand.darkened(0.1))
		spitze.mesh = kegel
		spitze.position = eck + Vector3(0.0, 0.68, 0.0)
		burg.add_child(spitze)
	burg.add_child(_teil(Vector3(0.0, 0.25, 0.0), Vector3(0.8, 0.5, 0.8), sand))


func _handtuch(name_id: String, pos: Vector3, farbe: Color) -> void:
	var tuch := _quader(name_id, pos + Vector3(0.0, 0.015, 0.0), Vector3(0.9, 0.03, 1.6), farbe)
	tuch.rotation_degrees.y = randf_range(-15.0, 15.0)


func _muschel_marker(pos: Vector3, index: int) -> void:
	var muschel := MeshInstance3D.new()
	muschel.name = "Muschel%d" % index
	var kugel := SphereMesh.new()
	kugel.radius = 0.14
	kugel.height = 0.18
	kugel.material = _matt(Color(0.97, 0.88, 0.92))
	muschel.mesh = kugel
	muschel.position = pos + Vector3(0.0, 0.07, 0.0)
	add_child(muschel)


func _berg(pos: Vector3, hoehe: float, radius: float, farbe: Color) -> void:
	var berg := MeshInstance3D.new()
	berg.name = "Berg"
	var kegel := CylinderMesh.new()
	kegel.top_radius = 0.0
	kegel.bottom_radius = radius
	kegel.height = hoehe
	kegel.radial_segments = 8
	kegel.material = _matt(farbe)
	berg.mesh = kegel
	berg.position = pos + Vector3(0.0, hoehe * 0.5, 0.0)
	add_child(berg)
	var kappe := MeshInstance3D.new()
	var schnee := CylinderMesh.new()
	schnee.top_radius = 0.0
	schnee.bottom_radius = radius * 0.35
	schnee.height = hoehe * 0.28
	schnee.radial_segments = 8
	schnee.material = _matt(Color(0.96, 0.97, 1.0))
	kappe.mesh = schnee
	kappe.position = pos + Vector3(0.0, hoehe - hoehe * 0.14, 0.0)
	add_child(kappe)


func _baue_zelt(pos: Vector3, rot_grad: float) -> void:
	var zelt := MeshInstance3D.new()
	zelt.name = "Zelt"
	var prisma := PrismMesh.new()
	prisma.size = Vector3(1.8, 1.3, 2.0)
	prisma.material = _matt(Color(0.9, 0.5, 0.35))
	zelt.mesh = prisma
	zelt.position = pos + Vector3(0.0, 0.65, 0.0)
	zelt.rotation_degrees.y = rot_grad
	add_child(zelt)


func _baue_lagerfeuer(pos: Vector3) -> void:
	var feuer := Node3D.new()
	feuer.name = "Lagerfeuer"
	feuer.position = pos
	add_child(feuer)
	for i in 5:
		var stein := MeshInstance3D.new()
		var kugel := SphereMesh.new()
		kugel.radius = 0.12
		kugel.height = 0.2
		kugel.material = _matt(Color(0.5, 0.48, 0.46))
		stein.mesh = kugel
		var winkel := TAU * float(i) / 5.0
		stein.position = Vector3(cos(winkel) * 0.45, 0.06, sin(winkel) * 0.45)
		feuer.add_child(stein)
	var flamme := MeshInstance3D.new()
	var kegel := CylinderMesh.new()
	kegel.top_radius = 0.0
	kegel.bottom_radius = 0.22
	kegel.height = 0.55
	var glut := StandardMaterial3D.new()
	glut.albedo_color = Color(1.0, 0.55, 0.2)
	glut.emission_enabled = true
	glut.emission = Color(1.0, 0.45, 0.1)
	glut.emission_energy_multiplier = 1.4
	kegel.material = glut
	flamme.mesh = kegel
	flamme.position = Vector3(0.0, 0.3, 0.0)
	feuer.add_child(flamme)
	var licht := OmniLight3D.new()
	licht.position = Vector3(0.0, 0.6, 0.0)
	licht.omni_range = 5.0
	licht.light_color = Color(1.0, 0.7, 0.4)
	licht.light_energy = 1.2
	feuer.add_child(licht)


func _baue_cafe_terrasse(pos: Vector3) -> void:
	var terrasse := Node3D.new()
	terrasse.name = "CafeTerrasse"
	terrasse.position = pos
	add_child(terrasse)
	var tisch := _prop("%s/table_round_A.gltf" % INNEN, pos, 0.0, 1.1)
	if tisch == null:
		terrasse.add_child(
			_teil(Vector3(0.0, 0.45, 0.0), Vector3(1.0, 0.9, 1.0), Color(0.6, 0.45, 0.35))
		)
	var theke := _prop(
		"%s/kitchencounter_straight.gltf" % INNEN, pos + Vector3(-1.6, 0.0, -1.4), 25.0, 0.9
	)
	if theke == null:
		terrasse.add_child(
			_teil(Vector3(-1.6, 0.45, -1.4), Vector3(1.6, 0.9, 0.6), Color(0.5, 0.4, 0.35))
		)
	_baue_sonnenschirm(pos + Vector3(0.0, 0.0, 0.0), Color(0.75, 0.3, 0.3))


func _baue_lichterkette(von: Vector3, bis: Vector3, anzahl: int) -> void:
	var kette := Node3D.new()
	kette.name = "Lichterkette"
	add_child(kette)
	for i in anzahl:
		var t := float(i) / float(maxi(1, anzahl - 1))
		var birne := MeshInstance3D.new()
		var kugel := SphereMesh.new()
		kugel.radius = 0.08
		kugel.height = 0.14
		var leucht := StandardMaterial3D.new()
		leucht.albedo_color = Color(1.0, 0.9, 0.6)
		leucht.emission_enabled = true
		leucht.emission = Color(1.0, 0.85, 0.5)
		leucht.emission_energy_multiplier = 1.2
		kugel.material = leucht
		birne.mesh = kugel
		# Leichter Durchhang in der Mitte (Kettenlinie, günstig genähert).
		var hang := sin(t * PI) * 0.45
		birne.position = von.lerp(bis, t) - Vector3(0.0, hang, 0.0)
		kette.add_child(birne)


func _baue_sehenswuerdigkeit(pos: Vector3) -> void:
	var turm := Node3D.new()
	turm.name = "Sehenswuerdigkeit"
	turm.position = pos
	add_child(turm)
	var dunkel := Color(0.3, 0.32, 0.42)
	turm.add_child(_teil(Vector3(0.0, 2.2, 0.0), Vector3(1.2, 4.4, 1.2), dunkel))
	turm.add_child(_teil(Vector3(0.0, 4.7, 0.0), Vector3(0.7, 0.6, 0.7), dunkel))
	var kugel := MeshInstance3D.new()
	var sphaere := SphereMesh.new()
	sphaere.radius = 0.55
	sphaere.height = 1.1
	var glanz := StandardMaterial3D.new()
	glanz.albedo_color = Color(0.95, 0.8, 0.4)
	glanz.emission_enabled = true
	glanz.emission = Color(0.9, 0.7, 0.3)
	glanz.emission_energy_multiplier = 0.5
	sphaere.material = glanz
	kugel.mesh = sphaere
	kugel.position = Vector3(0.0, 5.6, 0.0)
	turm.add_child(kugel)


## Souvenir-Spot-Markierung (leuchtender Ring — Muster raumstation-FotoSpot).
func _baue_souvenir_spot(pos: Vector3) -> void:
	var spot := MeshInstance3D.new()
	spot.name = "SouvenirSpot"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.34
	ring.outer_radius = 0.44
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.4)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.85, 0.3)
	material.emission_energy_multiplier = 0.8
	ring.material = material
	spot.mesh = ring
	spot.position = pos + Vector3(0.0, 0.02, 0.0)
	add_child(spot)


func _souvenir_spot_position() -> Vector3:
	match archetyp:
		"berge":
			return Vector3(-1.2, 0.0, 0.8)
		"stadt":
			return Vector3(2.8, 0.0, 0.2)
		_:
			return Vector3(-0.6, 0.0, 1.2)


## ------------------------------------------------------------- Statisten


## 2 Urlauber-Goobys (getintete Rigs mit Idle-Loops) — Lebendigkeit.
func _baue_statisten() -> void:
	var daten: Dictionary = ARCHETYP_DATEN[archetyp]
	var tints: Array = daten["statisten_tints"]
	var plaetze := _statisten_plaetze()
	for i in tints.size():
		var statist := GoobyRig.new()
		statist.name = "Statist%d" % i
		statist.position = plaetze[i % plaetze.size()]
		statist.rotation_degrees.y = -20.0 + 40.0 * i
		add_child(statist)
		statist.set_emotion("happy")
		_tinte_rig(statist, tints[i])
		statisten.append(statist)


func _statisten_plaetze() -> Array:
	match archetyp:
		"berge":
			return [Vector3(-3.6, 0.0, -0.2), Vector3(3.0, 0.0, -2.2)]
		"stadt":
			return [Vector3(-3.4, 0.0, -2.4), Vector3(3.4, 0.0, -2.6)]
		_:
			return [Vector3(2.9, 0.0, 0.4), Vector3(-1.0, 0.0, 0.9)]


## Statisten-Tint (Muster OrtScene._tinte_npc, nur auf beliebigem Rig).
func _tinte_rig(ziel_rig: GoobyRig, farbe: Color) -> void:
	if farbe == Color.WHITE or ziel_rig == null:
		return
	for mesh in ziel_rig.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var material: Material = mi.mesh.surface_get_material(i)
			if material is StandardMaterial3D:
				var kopie: StandardMaterial3D = material.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.55)
				mi.set_surface_override_material(i, kopie)


func _starte_statisten_hop() -> void:
	if _reduced_motion():
		return
	for i in statisten.size():
		var statist := statisten[i]
		if statist == null or not is_instance_valid(statist):
			continue
		var basis_y := statist.position.y
		var tween := create_tween().set_loops()
		tween.tween_interval(0.4 * i)
		(
			tween
			. tween_property(
				statist, "position:y", basis_y + STATIST_HOP_HOEHE, STATIST_HOP_DAUER * 0.5
			)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tween
			. tween_property(statist, "position:y", basis_y, STATIST_HOP_DAUER * 0.5)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN)
		)


## --------------------------------------------------------------- Helfer


func _himmel() -> Sky:
	var material := ShaderMaterial.new()
	material.shader = load(SKY_SHADER)
	match archetyp:
		"strand":
			material.set_shader_parameter("zenit_farbe", Color(0.4, 0.66, 0.92))
			material.set_shader_parameter("wolken_menge", 0.25)
		"berge":
			material.set_shader_parameter("zenit_farbe", Color(0.45, 0.62, 0.88))
			material.set_shader_parameter("wolken_menge", 0.45)
		_:
			material.set_shader_parameter("zenit_farbe", Color(0.5, 0.55, 0.85))
			material.set_shader_parameter("horizont_farbe", Color(0.95, 0.8, 0.7))
			material.set_shader_parameter("wolken_menge", 0.15)
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	return sky


func _teil(pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var teil := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = groesse
	box.material = _matt(farbe)
	teil.mesh = box
	teil.position = pos
	return teil


func _matt(farbe: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = farbe
	material.roughness = 0.85
	return material


func _knopf(name_id: String, text: String, variation: String) -> Button:
	var btn := Button.new()
	btn.name = name_id
	btn.text = text
	btn.theme_type_variation = variation
	btn.custom_minimum_size = Vector2(0.0, 52.0)
	return btn


func _router() -> Object:
	if router_override != null:
		return router_override
	return get_node_or_null("/root/SceneRouter")


func _now_ms() -> int:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return (
		settings != null
		and settings.has_method("is_reduced_motion")
		and settings.is_reduced_motion()
	)
