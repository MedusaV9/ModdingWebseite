class_name OrtWochenmarkt
extends OrtScene
## Wochenmarkt (Doc D §6.3, USER §D51): samstags 8–14 Uhr (Öffnungsregel in
## city_map.json, geprüft von OrtKatalog). Kein Innenraum, sondern ein Platz
## unter freiem Himmel — Stände, Kisten, Info-Schild. Verkauft wird die eigene
## ERNTE mit Preis-Elastizität (MarktPreise): jede heute verkaufte Einheit
## drückt den Preis, am nächsten Markttag ist er wieder voll.
##
## W15/MARKT — Eigenstand-Vollausbau: Neben dem Ankauf gibt es jetzt den
## EIGENEN Stand (MarktStand/MarktSim, Sheet-Tab „Mein Stand“). Gooby steht
## stolz mit Schürze dahinter (Schürze-Gag), bestückte Ware liegt sichtbar
## auf dem Tisch und Kunden-Goobys schauen vorbei — beim Zuschau-Replay
## hüpfen sie zu jedem Verkaufs-Pling mit.

const INNEN := "res://assets/city/innen"
const ESSEN := "res://assets/city/essen"
const MOEBEL := "res://assets/furniture"

## Marktmusik-Anbindung (W15/MARKT-Atmo): gespielt wird NUR, wenn die
## Registry wirklich einen Track mit diesem Kontext kennt — heute keiner,
## also bleibt der Hook bewusst still („nur wenn ein passender Track
## existiert, sonst weglassen“). Ein neuer music_registry-Eintrag mit
## context "location:markt" aktiviert ihn ohne Codeänderung.
const MUSIK_KONTEXT := "location:markt"

## Eigenstand-Anker (links vorn, gut im Kamerabild).
const EIGENSTAND_POS := Vector3(-1.9, 0.0, 0.7)
## Schürze-Gag: Latz + Tasche + Trägerband in Marktrot.
const SCHUERZE := Color("#E2574C")
const SCHUERZE_HELL := Color("#F7E6C8")
## Kunden-Goobys (Tints bewusst ≠ Händler-Grün) samt Plätzen vor dem Stand.
const KUNDEN_TINTS: Array[Color] = [Color("#E8A34C"), Color("#8B7DE8"), Color("#5CA9E8")]
const KUNDEN_PLAETZE: Array[Vector3] = [
	Vector3(-2.6, 0.0, 1.9),
	Vector3(-1.1, 0.0, 2.1),
	Vector3(-3.4, 0.0, 1.2),
]

## Der stolze Stand-Gooby (mit Schürze) hinter dem Eigenstand.
var stand_gooby: GoobyRig

var _kunden: Array[GoobyRig] = []
var _waren_deko: Node3D
var _naechster_hopser := 0
var _musik_gepusht := false
var _schuerze_gag_gezeigt := false


func _ready() -> void:
	super._ready()
	_starte_marktmusik()
	var gs := game_state()
	if gs != null and gs.has_signal("slice_changed"):
		gs.slice_changed.connect(_on_slice_changed)


func _exit_tree() -> void:
	if _musik_gepusht and is_inside_tree():
		MusicDirector.get_or_create(self).pop_context(MUSIK_KONTEXT)
		_musik_gepusht = false


## Marktplatz statt Ladenraum: keine Rückwand, Wiese, heller Himmel.
func _ist_draussen() -> bool:
	return true


func _baue_innenraum() -> void:
	_prop("%s/table.glb" % MOEBEL, Vector3(-3.4, 0.0, -1.8), 0.0, 1.2)
	_prop("%s/table.glb" % MOEBEL, Vector3(3.4, 0.0, -1.8), 0.0, 1.2)
	_prop("%s/crate_carrots.gltf" % INNEN, Vector3(-4.2, 0.0, -0.4), 14.0, 0.7)
	_prop("%s/crate_tomatoes.gltf" % INNEN, Vector3(-2.6, 0.0, -0.4), -10.0, 0.7)
	_prop("%s/crate_buns.gltf" % INNEN, Vector3(2.6, 0.0, -0.4), 8.0, 0.7)
	_prop("%s/crate.gltf" % INNEN, Vector3(4.2, 0.0, -0.4), -16.0, 0.7)
	_prop("%s/menu.gltf" % INNEN, Vector3(0.0, 0.0, -3.6), 0.0, 1.8)
	_prop("%s/garten/bench.glb" % MOEBEL, Vector3(5.6, 0.0, 1.2), -100.0, 1.1)
	_prop("%s/garten/tree_fat.glb" % MOEBEL, Vector3(-6.4, 0.0, -3.4), 0.0, 2.4)
	_baue_auslage()
	_baue_eigenstand()
	_aktualisiere_stand_deko()
	_richte_kunden_ein()


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/wochenmarkt.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#4FBF8B"), "emotion": "happy", "pos": Vector3(0.0, 0.0, -2.4)}


## Wochenmarkt VERKAUFT nicht, er KAUFT — plus (W15) der EIGENE Stand.
## Ein Sheet mit zwei Tabs: Ankauf (MarktSheet) und „Mein Stand“
## (MarktStandSheet mit Bestücken/Preis-Slidern/Replay/Abrechnung).
func oeffne_laden() -> void:
	var inhalt := VBoxContainer.new()
	inhalt.add_theme_constant_override("separation", 10)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	inhalt.add_child(tabs)
	var halter := VBoxContainer.new()
	inhalt.add_child(halter)
	var ankauf := _tab_knopf(I18nService.t("markt.tab.ankauf"))
	var eigen := _tab_knopf(I18nService.t("markt.tab.eigenstand"))
	tabs.add_child(ankauf)
	tabs.add_child(eigen)
	ankauf.pressed.connect(_zeige_tab.bind(halter, ankauf, eigen, false))
	eigen.pressed.connect(_zeige_tab.bind(halter, ankauf, eigen, true))
	_zeige_tab(halter, ankauf, eigen, false)
	zeige_sheet(I18nService.t("city.markt.sheet_titel"), inhalt)


## Gemüse auf den Tischen (reine Deko, ohne Bezug zum Inventar).
func _baue_auslage() -> void:
	var auslage := {
		"carrot.glb": Vector3(-3.9, 0.78, -1.7),
		"tomato.glb": Vector3(-3.2, 0.78, -1.9),
		"salad.glb": Vector3(-2.7, 0.78, -1.6),
		"corn.glb": Vector3(2.8, 0.78, -1.7),
		"watermelon.glb": Vector3(3.5, 0.78, -1.9),
		"broccoli.glb": Vector3(4.1, 0.78, -1.6),
	}
	for datei: String in auslage:
		_prop("%s/%s" % [ESSEN, datei], auslage[datei], randf() * 40.0 - 20.0, 1.1)


func _on_verkauft(_ernte_id: String, _menge: int) -> void:
	if rig != null:
		rig.play_clip("wave")


## ------------------------------------------------------ Eigenstand (3D)


## Eigener Stand: Tisch + Kiste, dahinter der stolze Stand-Gooby mit
## Schürze (Schürze-Gag — s. markt.schuerze-Line beim Tab-Öffnen).
func _baue_eigenstand() -> void:
	_prop("%s/table.glb" % MOEBEL, EIGENSTAND_POS, 6.0, 1.2)
	_prop("%s/crate.gltf" % INNEN, EIGENSTAND_POS + Vector3(-1.2, 0.0, 0.6), 22.0, 0.6)
	stand_gooby = GoobyRig.new()
	stand_gooby.position = EIGENSTAND_POS + Vector3(0.0, 0.0, -0.9)
	add_child(stand_gooby)
	stand_gooby.set_emotion("ecstatic")
	_baue_schuerze(stand_gooby)


## Schürze aus drei CosmeticParts-Boxen (Anker wie koerper_form.gd:
## Hals ≈ y 0.45, Brille z ≈ 0.21 — der Latz sitzt darunter am Bauch).
func _baue_schuerze(ziel: GoobyRig) -> void:
	CosmeticParts.box(ziel, Vector3(0.34, 0.30, 0.03), SCHUERZE, Vector3(0.0, 0.30, 0.24))
	CosmeticParts.box(ziel, Vector3(0.18, 0.11, 0.034), SCHUERZE_HELL, Vector3(0.0, 0.25, 0.245))
	CosmeticParts.box(ziel, Vector3(0.05, 0.14, 0.028), SCHUERZE, Vector3(0.0, 0.49, 0.22))


## Bestückte Ware sichtbar auf den Stand legen (nur Waren mit Essen-GLB;
## _prop schweigt bei Fehlpfad — Möbel-Waren zeigen die Kiste daneben).
func _aktualisiere_stand_deko() -> void:
	if _waren_deko != null:
		_waren_deko.queue_free()
	_waren_deko = Node3D.new()
	_waren_deko.position = EIGENSTAND_POS + Vector3(0.0, 0.93, 0.0)
	add_child(_waren_deko)
	var plaetze: Array[Vector3] = [
		Vector3(-0.45, 0.0, -0.05),
		Vector3(0.05, 0.0, 0.12),
		Vector3(0.45, 0.0, -0.1),
		Vector3(-0.1, 0.0, -0.2),
	]
	var slots: Array = MarktStand.slice_von(game_state())["slots"]
	for i in mini(slots.size(), plaetze.size()):
		var ware := str((slots[i] as Dictionary)["ware"])
		var pfad := "%s/%s.glb" % [ESSEN, ware]
		if not ResourceLoader.exists(pfad):
			continue
		var szene: PackedScene = load(pfad)
		if szene == null:
			continue
		var node: Node3D = szene.instantiate()
		node.position = plaetze[i]
		node.rotation_degrees.y = randf() * 40.0 - 20.0
		_waren_deko.add_child(node)


## Kunden-Goobys vor dem Stand: sie kommen, sobald der Stand bestückt ist
## (je mehr Waren, desto mehr Kundschaft), und gehen mit der Abrechnung.
func _richte_kunden_ein() -> void:
	var slots: Array = MarktStand.slice_von(game_state())["slots"]
	var soll := 0 if slots.is_empty() else clampi(slots.size() + 1, 2, KUNDEN_PLAETZE.size())
	while _kunden.size() > soll:
		var weg: GoobyRig = _kunden.pop_back()
		if is_instance_valid(weg):
			weg.queue_free()
	while _kunden.size() < soll:
		var i := _kunden.size()
		var kunde := GoobyRig.new()
		kunde.position = KUNDEN_PLAETZE[i]
		kunde.rotation_degrees.y = 180.0 + (i - 1) * 24.0
		add_child(kunde)
		kunde.set_emotion("happy")
		_tinte_rig(kunde, KUNDEN_TINTS[i % KUNDEN_TINTS.size()])
		_kunden.append(kunde)


## ------------------------------------------------------ Eigenstand (UI)


func _tab_knopf(text: String) -> Button:
	var knopf := Button.new()
	knopf.theme_type_variation = "GhostButton"
	knopf.text = text
	knopf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return knopf


func _zeige_tab(halter: VBoxContainer, ankauf: Button, eigen: Button, eigenstand: bool) -> void:
	for kind in halter.get_children():
		kind.queue_free()
	ankauf.theme_type_variation = "PrimaryButton" if not eigenstand else "GhostButton"
	eigen.theme_type_variation = "PrimaryButton" if eigenstand else "GhostButton"
	if not eigenstand:
		var markt := MarktSheet.new()
		markt.gs = game_state()
		markt.erstes_mal = ist_erstbesuch
		markt.verkauft.connect(_on_verkauft)
		halter.add_child(markt)
		return
	var stand := MarktStandSheet.new()
	stand.gs = game_state()
	stand.erstes_mal = ist_erstbesuch
	stand.replay_gestartet.connect(_on_replay_gestartet)
	stand.verkauf_gezeigt.connect(_on_verkauf_gezeigt)
	stand.replay_beendet.connect(_on_replay_beendet)
	stand.abgeholt.connect(_on_abgeholt)
	halter.add_child(stand)
	_zeige_schuerze_gag()


## Schürze-Gag: beim ersten Öffnen des Eigenstand-Tabs pro Besuch platzt
## der Stand-Gooby vor Stolz (Sprechblase über der Schürze).
func _zeige_schuerze_gag() -> void:
	if _schuerze_gag_gezeigt or stand_gooby == null or _ui == null:
		return
	_schuerze_gag_gezeigt = true
	stand_gooby.play_clip("wave")
	AcBubble.show_bubble(_ui, I18nService.t("markt.schuerze"), {"speaker_3d": stand_gooby})


## --------------------------------------------------- Replay-Reaktionen


func _on_replay_gestartet() -> void:
	for kunde in _kunden:
		if is_instance_valid(kunde):
			kunde.set_emotion("ecstatic")
	# 2-3 Markt-Kommentare laufen über die SeeleRunner.kommentar-API —
	# in Ort-Szenen ohne GoobyReactions-Runner bleibt der Ruf still und die
	# Tages-Line im Sheet übernimmt (s. >> MARKT→VOICE im Handoff).
	SeeleRunner.kommentar_im_raum(self, "markt.stand")


## Verkaufs-Pling im Replay: der nächste Kunde hüpft, der Stand-Gooby
## winkt bei jedem dritten Verkauf stolz dazu.
func _on_verkauf_gezeigt(_ware_id: String, _preis: int) -> void:
	if not _kunden.is_empty():
		var kunde: GoobyRig = _kunden[_naechster_hopser % _kunden.size()]
		if is_instance_valid(kunde):
			kunde.play_clip("hop")
	_naechster_hopser += 1
	if stand_gooby != null and _naechster_hopser % 3 == 0:
		stand_gooby.play_clip("wave")


func _on_replay_beendet() -> void:
	for kunde in _kunden:
		if is_instance_valid(kunde):
			kunde.set_emotion("happy")
			kunde.play_clip("wave")


func _on_abgeholt(erloes: int) -> void:
	if stand_gooby != null:
		stand_gooby.set_emotion("ecstatic")
		stand_gooby.play_clip("celebrate" if erloes > 0 else "wave")
	SeeleRunner.kommentar_im_raum(self, "markt.stand")


## Stand-Deko und Kundschaft folgen dem Save (Bestücken/Entnehmen/Abholen).
func _on_slice_changed(slice_id: String, _data: Variant) -> void:
	if slice_id != CityState.SLICE_ID:
		return
	_aktualisiere_stand_deko()
	_richte_kunden_ein()


## ---------------------------------------------------------------- Atmo


## Marktmusik als Overlay über dem City-Kontext — NUR wenn die Registry
## einen Track kennt (s. MUSIK_KONTEXT-Kommentar).
func _starte_marktmusik() -> void:
	if MusicRegistry.track_for(MUSIK_KONTEXT).is_empty():
		return
	MusicDirector.get_or_create(self).push_context(MUSIK_KONTEXT)
	_musik_gepusht = true


## Rig-Tint wie OrtScene._tinte_npc, nur für beliebige Rigs (Kunden).
func _tinte_rig(ziel: GoobyRig, farbe: Color) -> void:
	for mesh in ziel.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.55)
				mi.set_surface_override_material(i, kopie)
