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
##
## G8-P1 „Jeder Ort lebt“ (PT2-B4): die Eigenstand-Kunden kommen erst mit
## bestücktem Stand — der Grund-Markt bekommt deshalb OrtLeben-Bummler
## (Paket-Träger zwischen den Buden, ein Bank-Ausruher) plus Markt-Momente
## (Marktschreier-Glocke, Melonen-Schnäppchen). W17-Deko bleibt unberührt.
##
## W18/R3 PT2-B10 — Öffnungszeiten mit Charme statt Schranke: der Platz
## bleibt IMMER betretbar (Wohlfühl-Spiel!), aber außerhalb Sa 8–14 Uhr
## (Regel aus city_map.json via OrtKatalog) ruhen die Stände sichtbar —
## Planen über den Auslagen, ein „Bis Samstag!“-Schild am Greta-Platz,
## Greta selbst ist NICHT da (kein Dialog, der Ankauf-Tab vertröstet
## freundlich), und das Markt-Leben (Bummler, Schreier-Glocke, Gemurmel)
## ruht unsichtbar/eingefroren — die _leben_konfig() selbst bleibt
## zeitunabhängig (test_g8_ort_leben_rollout wacht über den Momente-
## Vertrag). Der EIGENE Stand bleibt über den „Mein Marktstand“-Knopf
## jederzeit erreichbar — bestückt wird ja gerade VOR dem Markttag;
## verkauft wird wie gehabt nur am Samstag (MarktSim bindet an den
## Markttag — das sagt das Stand-Sheet sichtbar an). Tests injizieren
## `zeit_override` (Muster MarktSheet/MarktStandSheet) und rufen danach
## `aktualisiere_marktzustand()`.

const INNEN := "res://assets/city/innen"
const ESSEN := "res://assets/city/essen"
const MOEBEL := "res://assets/furniture"
## ASSET-SOURCE (W17): Kenney-Marktstände (CC0) — docs/godot-rewrite/ASSET-CREDITS.md.
const MARKT := "res://assets/city/marktstand"

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

## Geschlossen-Charme (PT2-B10): Planen-Segeltuch + Schild-Holz.
const PLANE_FARBE := Color("#E8DAC0")
const SCHILD_HOLZ := Color("#B98A5A")
const SCHILD_TINTE := Color("#4A3B33")

## Der stolze Stand-Gooby (mit Schürze) hinter dem Eigenstand.
var stand_gooby: GoobyRig
## Tests/Screenshots frieren die Zeit ein (< 0 = echte Systemzeit) — wird
## beim Sheet-Öffnen in beide Tabs weitergereicht (PT2-B10).
var zeit_override := -1

var _kunden: Array[GoobyRig] = []
var _waren_deko: Node3D
var _naechster_hopser := 0
var _musik_gepusht := false
var _schuerze_gag_gezeigt := false
var _geschlossen_deko: Node3D
## Gretas Dialog lief schon (oder der Aufbau war offen)? Beim Flip auf
## OFFEN via aktualisiere_marktzustand() wird er sonst nachgestartet.
var _dialog_lief := false


func _ready() -> void:
	super._ready()
	_dialog_lief = markt_offen()
	_baue_stand_knopf()
	aktualisiere_marktzustand()
	_starte_marktmusik()
	var gs := game_state()
	if gs != null and gs.has_signal("slice_changed"):
		gs.slice_changed.connect(_on_slice_changed)


## Injizierte Zeit (Unix-Sekunden) — dasselbe Muster wie die Markt-Sheets.
func unix_s() -> int:
	if zeit_override >= 0:
		return zeit_override
	return int(Time.get_unix_time_from_system())


## Ist der Markt JETZT offen? (Sa 8–14 Uhr, Quelle city_map.json.)
func markt_offen() -> bool:
	return OrtKatalog.ist_offen("wochenmarkt", unix_s())


## Geschlossen-Charme an/aus je nach (injizierter) Zeit: Greta samt Dialog
## nur zur Marktzeit, sonst Planen + Schild. Beim Betreten automatisch;
## Flows/Tests rufen es nach dem Setzen von `zeit_override` erneut — beim
## Flip auf OFFEN startet Gretas Dialog nach, falls der Aufbau ihn (weil
## geschlossen) übersprungen hatte.
func aktualisiere_marktzustand() -> void:
	var offen := markt_offen()
	if rig != null:
		rig.visible = offen
	if _geschlossen_deko != null:
		_geschlossen_deko.visible = not offen
	# Markt-Leben ruht MIT den Ständen: unsichtbar + eingefroren (keine
	# Schreier-Glocke, kein Gemurmel, keine Bummler) — der Platz ist still.
	if leben != null:
		leben.visible = offen
		leben.process_mode = Node.PROCESS_MODE_INHERIT if offen else Node.PROCESS_MODE_DISABLED
	if offen and not _dialog_lief:
		_dialog_lief = true
		_starte_dialog()


func _exit_tree() -> void:
	if _musik_gepusht and is_inside_tree():
		MusicDirector.get_or_create(self).pop_context(MUSIK_KONTEXT)
		_musik_gepusht = false


## Marktplatz statt Ladenraum: keine Rückwand, Wiese, heller Himmel.
func _ist_draussen() -> bool:
	return true


func _baue_innenraum() -> void:
	# ASSET-SOURCE (W17) Sichtbarkeits-Fix: table.glb ist NIEDRIG (0,39 m),
	# die Kisten sind 0,65 m hoch — standen die Tische HINTER den Kisten,
	# verdeckten diese sie komplett und die Auslage schien zu schweben.
	# Deshalb: Tische vorn, Kisten dahinter.
	_prop("%s/table.glb" % MOEBEL, Vector3(-3.4, 0.0, -0.4), 0.0, 1.2)
	_prop("%s/table.glb" % MOEBEL, Vector3(3.4, 0.0, -0.4), 0.0, 1.2)
	_prop("%s/crate_carrots.gltf" % INNEN, Vector3(-4.2, 0.0, -1.8), 14.0, 0.7)
	_prop("%s/crate_tomatoes.gltf" % INNEN, Vector3(-2.6, 0.0, -1.8), -10.0, 0.7)
	_prop("%s/crate_buns.gltf" % INNEN, Vector3(2.6, 0.0, -1.8), 8.0, 0.7)
	_prop("%s/crate.gltf" % INNEN, Vector3(4.2, 0.0, -1.8), -16.0, 0.7)
	_prop("%s/menu.gltf" % INNEN, Vector3(0.0, 0.0, -3.6), 0.0, 1.8)
	_prop("%s/garten/bench.glb" % MOEBEL, Vector3(5.6, 0.0, 1.2), -100.0, 1.1)
	_prop("%s/garten/tree_fat.glb" % MOEBEL, Vector3(-6.4, 0.0, -3.4), 0.0, 2.4)
	# ASSET-SOURCE (W17): echte Marktstände mit Markisen hinter den
	# Tischen, Handkarren bei den Kunden, Laterne und zweite Sitzbank —
	# der Markt wirkt wie eine kleine Budengasse statt zweier Tische.
	# (stall-red in der hinteren Budenreihe, frei vom tree_fat-Schatten
	# und im 75°-Kamerakegel — weiter links läge er aus dem Bild.)
	_prop("%s/stall-red.glb" % MARKT, Vector3(-2.9, 0.0, -3.8), 10.0, 1.0)
	_prop("%s/stall-green.glb" % MARKT, Vector3(5.4, 0.0, -3.0), -18.0, 1.0)
	# stall.glb ist ein kleiner Markttresen (Platte ~0,37) — mit Brot und
	# Käse bestückt, damit die Bude nicht leer zwischen den Ständen steht.
	_prop("%s/stall.glb" % MARKT, Vector3(2.6, 0.0, -4.0), 4.0, 1.0)
	_prop("%s/bread.glb" % ESSEN, Vector3(2.45, 0.37, -4.1), 24.0, 0.9)
	_prop("%s/cheese.glb" % ESSEN, Vector3(2.8, 0.37, -3.9), -12.0, 0.9)
	_prop("%s/cart.glb" % MARKT, Vector3(0.8, 0.0, 1.7), -28.0, 0.9)
	_prop("%s/lantern.glb" % MARKT, Vector3(6.2, 0.0, -0.8), 0.0, 1.1)
	_prop("%s/stall-bench.glb" % MARKT, Vector3(4.3, 0.0, 1.7), 100.0, 1.0)
	_baue_auslage()
	_baue_eigenstand()
	_aktualisiere_stand_deko()
	_richte_kunden_ein()
	_baue_geschlossen_deko()


## Greta führt nur zur Marktzeit durch den Ankauf — außerhalb ist sie nicht
## da (PT2-B10), also startet auch kein Dialog.
func _dialog_pfad() -> String:
	if not markt_offen():
		return ""
	return "res://scripts/city/data/dialoge/wochenmarkt.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#4FBF8B"), "emotion": "happy", "pos": Vector3(0.0, 0.0, -2.4)}


## G8-P1: Markt-Bummel — drei Bummler ziehen durch die Budengasse (gut
## 60 % mit Einkaufs-Paket), einer sitzt auf der hinteren Vorrats-Kiste
## (Deckel 0,8 × Skala 0,7 = 0,56 m) und schaut übers Treiben — die
## Gartenbank bei x 5,6 läge außerhalb des 75°-Kamerakegels. Unter freiem
## Himmel: Gemurmel JA, Türglocke NEIN. Momente: die Marktschreier-Glocke
## (laden_glocke TIEF als Handglocke) und das Melonen-Schnäppchen
## (mg_good = plumpst in die Tasche). Eigenstand-Kunden bleiben unberührt.
func _leben_konfig() -> Dictionary:
	# PT2-B10-Hinweis: die Konfig bleibt bewusst ZEITUNABHÄNGIG (Vertrag
	# in test_g8_ort_leben_rollout) — ruht der Markt, legt
	# aktualisiere_marktzustand() den fertigen OrtLeben-Node still.
	return {
		"besucher": 3,
		# z ≤ 1,6 hält die Bummler im Kamera-Mittelgrund (s. flughafen.gd).
		"punkte":
		[
			Vector3(-4.6, 0.0, 0.6),
			Vector3(0.2, 0.0, -0.4),
			Vector3(2.6, 0.0, -1.0),
			Vector3(4.6, 0.0, 0.4),
			Vector3(2.0, 0.0, 1.6),
		],
		"requisit": "paket",
		"sprueche": "markt",
		"blick": Vector3(0.0, 0.0, -3.6),
		"gemurmel": true,
		"tuer_glocke": false,
		"kasse": false,
		"sitze":
		[
			{"pos": Vector3(4.2, 0.56, -1.75), "blick": Vector3(0.0, 0.0, 2.0)},
		],
		"momente":
		[
			{
				"alle_s": 19.0,
				"versatz_s": 5.0,
				"sound": "laden_glocke",
				"pitch": 0.75,
				"clip": "wave",
				"sprueche": "wochenmarkt_schreier",
			},
			{
				"alle_s": 28.0,
				"versatz_s": 16.0,
				"sound": "mg_good",
				"pitch": 1.1,
				"clip": "hop",
				"sprueche": "wochenmarkt_ernte",
			},
		],
	}


## Wochenmarkt VERKAUFT nicht, er KAUFT — plus (W15) der EIGENE Stand.
## Ein Sheet mit zwei Tabs: Ankauf (MarktSheet) und „Mein Stand“
## (MarktStandSheet mit Bestücken/Preis-Slidern/Replay/Abrechnung).
func oeffne_laden() -> void:
	_oeffne_markt_sheet(false)


## PT2-B10: der eigene Stand direkt — der „Mein Marktstand“-Knopf landet
## gleich im Eigenstand-Tab (geschlossen ist er der einzige Weg ins Sheet).
func oeffne_stand() -> void:
	_oeffne_markt_sheet(true)


func _oeffne_markt_sheet(eigenstand: bool) -> void:
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
	_zeige_tab(halter, ankauf, eigen, eigenstand)
	zeige_sheet(I18nService.t("city.markt.sheet_titel"), inhalt)


## Gemüse auf den Tischen (reine Deko, ohne Bezug zum Inventar).
## ASSET-SOURCE (W17) Bodenkontakt-Fix: table.glb ist ein NIEDRIGER Tisch
## (Platte bei y≈0,39 bei Skala 1,2) — die alte Höhe 0,78 ließ die Ware
## sichtbar schweben. 0,40 legt sie direkt auf die Platte (z folgt den
## nach vorn getauschten Tischen aus _baue_innenraum()).
func _baue_auslage() -> void:
	var auslage := {
		"carrot.glb": Vector3(-3.55, 0.4, -0.35),
		"tomato.glb": Vector3(-3.2, 0.4, -0.5),
		"salad.glb": Vector3(-2.7, 0.4, -0.2),
		"corn.glb": Vector3(2.8, 0.4, -0.3),
		"watermelon.glb": Vector3(3.5, 0.4, -0.5),
		"broccoli.glb": Vector3(4.1, 0.4, -0.2),
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
	# ASSET-SOURCE (W17): Platte des niedrigen table.glb liegt bei ~0,39
	# (nicht 0,93) — s. _baue_auslage(); sonst schwebt die Stand-Ware.
	_waren_deko.position = EIGENSTAND_POS + Vector3(0.0, 0.4, 0.0)
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


## ------------------------------------------- Geschlossen-Charme (PT2-B10)


## Planen über den Auslagen + „Bis Samstag!“-Schild am Greta-Platz — als
## EINE Gruppe gebaut und per Sichtbarkeit geschaltet, damit Flows den
## Zustand über aktualisiere_marktzustand() flippen können.
func _baue_geschlossen_deko() -> void:
	_geschlossen_deko = Node3D.new()
	_geschlossen_deko.name = "GeschlossenDeko"
	_geschlossen_deko.visible = false
	add_child(_geschlossen_deko)
	# Segeltuch über beiden Auslage-Tischen und dem kleinen Markttresen
	# (Maße folgen _baue_innenraum: table.glb-Platte ~0,39, Ware ~0,4–0,6).
	_plane(Vector3(-3.4, 0.62, -0.35), Vector3(3.1, 0.5, 1.8), 4.0)
	_plane(Vector3(3.4, 0.62, -0.35), Vector3(3.1, 0.5, 1.8), -3.0)
	_plane(Vector3(2.6, 0.6, -4.0), Vector3(1.7, 0.5, 1.3), 6.0)
	_baue_samstag_schild()


## Eine Stand-Plane: weiches Segeltuch-Rechteck, leicht verdreht.
func _plane(pos: Vector3, groesse: Vector3, rot_grad: float) -> void:
	var plane := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = groesse
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLANE_FARBE
	mat.roughness = 1.0
	box.material = mat
	plane.mesh = box
	plane.position = pos
	plane.rotation_degrees.y = rot_grad
	_geschlossen_deko.add_child(plane)


## Holzschild „Bis Samstag! Sa 8–14 Uhr“ dort, wo sonst Greta steht.
func _baue_samstag_schild() -> void:
	var halter := Node3D.new()
	halter.name = "SamstagSchild"
	halter.position = Vector3(0.0, 0.0, -2.4)
	halter.rotation_degrees.y = -4.0
	_geschlossen_deko.add_child(halter)
	var pfosten := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.07, 0.95, 0.07)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = SCHILD_HOLZ
	pbox.material = pmat
	pfosten.mesh = pbox
	pfosten.position = Vector3(0.0, 0.48, 0.0)
	halter.add_child(pfosten)
	var brett := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(1.2, 0.62, 0.05)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = PLANE_FARBE
	bbox.material = bmat
	brett.mesh = bbox
	brett.position = Vector3(0.0, 1.1, 0.0)
	halter.add_child(brett)
	var text := Label3D.new()
	text.name = "SchildText"
	text.text = I18nService.t("markt.geschlossen.schild")
	text.font_size = 44
	text.pixel_size = 0.004
	text.modulate = SCHILD_TINTE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.position = Vector3(0.0, 1.1, 0.04)
	halter.add_child(text)


## ------------------------------------------------------ Eigenstand (UI)


## „Mein Marktstand“ unten in der Safe-Area-Leiste (PT2-B10): der eigene
## Stand ist so AUCH ohne Greta erreichbar — bestückt wird gerade dann,
## wenn der Markt noch gar nicht läuft.
func _baue_stand_knopf() -> void:
	var knopf := Button.new()
	knopf.name = "StandKnopf"
	knopf.theme_type_variation = "AccentButton"
	knopf.text = I18nService.t("markt.stand_knopf")
	knopf.pressed.connect(oeffne_stand)
	var knoepfe: Array[Button] = [knopf]
	_baue_knopfleiste(knoepfe, "MarktKnoepfe")


func _tab_knopf(text: String) -> Button:
	var knopf := Button.new()
	knopf.theme_type_variation = "GhostButton"
	knopf.text = text
	knopf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return knopf


func _zeige_tab(halter: VBoxContainer, ankauf: Button, eigen: Button, eigenstand: bool) -> void:
	for kind in halter.get_children():
		# Wie panel_sheet.add_content/PT2-B11: Name sofort freigeben, damit
		# ein Neuaufbau im selben Frame keine umnummerierten Knoten erbt.
		halter.remove_child(kind)
		kind.queue_free()
	ankauf.theme_type_variation = "PrimaryButton" if not eigenstand else "GhostButton"
	eigen.theme_type_variation = "PrimaryButton" if eigenstand else "GhostButton"
	if not eigenstand:
		var markt := MarktSheet.new()
		markt.gs = game_state()
		# PT2-B10: die (injizierte) Ort-Zeit gilt auch im Tab — der Ankauf
		# vertröstet außerhalb Sa 8–14 freundlich.
		markt.zeit_override = zeit_override
		markt.erstes_mal = ist_erstbesuch
		markt.verkauft.connect(_on_verkauft)
		halter.add_child(markt)
		return
	var stand := MarktStandSheet.new()
	stand.gs = game_state()
	stand.zeit_override = zeit_override
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
	# W15/INTEGRATE (MARKT→VOICE-Request): Kategorie markt.stand existiert
	# jetzt in SoulLinien — wie bei der Raumstation spricht der statische
	# Einstieg über den zuletzt aktiven SeeleRunner (None-sicher), weil die
	# Ort-Szene keinen eigenen GoobyReactions-Runner hat. Fällt der Ruf
	# still, übernimmt die Tages-Line im Sheet.
	SeeleRunner.kommentar_global("markt.stand")


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
	SeeleRunner.kommentar_global("markt.stand")


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
